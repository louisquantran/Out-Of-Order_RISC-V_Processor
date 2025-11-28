`timescale 1ns/1ps
import types_pkg::*;

module ooo_top_tb;

  // Clock / Reset 
  logic clk   = 0;
  logic reset = 1;

  localparam int CLK_PERIOD = 10;  // 10 ns, 100 MHz

  // exec_ready from "execute" back to backend
  logic exec_ready;

  // Fake FU to DUT signals 
  // ISSUE-SLOT READY
  logic        fu_alu_ready_tb;
  logic        fu_b_ready_tb;
  logic        fu_mem_ready_tb;

  // COMPLETION VALID
  logic        fu_alu_done_tb;
  logic        fu_b_done_tb;
  logic        fu_mem_done_tb;

  // ROB tags for completed instructions
  logic [4:0]  rob_fu_alu_tb;
  logic [4:0]  rob_fu_b_tb;
  logic [4:0]  rob_fu_mem_tb;

  // Preg wakeup broadcasts (p_*_in)
  logic [6:0]  ps_in_alu_tb;
  logic [6:0]  ps_in_b_tb;    // not connected to DUT (no p_b_in), just for debug
  logic [6:0]  ps_in_mem_tb;

  // Data from FUs into PRF
  logic [31:0] data_alu_in_tb;
  logic [31:0] data_mem_in_tb;

  // DUT 
  ooo_top dut (
    .clk          (clk),
    .reset        (reset),
    .exec_ready   (exec_ready),

    // FU issue-ready (into dispatch/RS)
    .fu_alu_ready (fu_alu_ready_tb),
    .fu_b_ready   (fu_b_ready_tb),
    .fu_mem_ready (fu_mem_ready_tb),

    // FU completion (into ROB / dispatch)
    .fu_alu_done  (fu_alu_done_tb),
    .fu_b_done    (fu_b_done_tb),
    .fu_mem_done  (fu_mem_done_tb),

    // Completed ROB tags
    .rob_fu_alu   (rob_fu_alu_tb),
    .rob_fu_b     (rob_fu_b_tb),
    .rob_fu_mem   (rob_fu_mem_tb),

    // Preg wakeup (same cycle as fu_*_done)
    .p_alu_in     (ps_in_alu_tb),
    .p_mem_in     (ps_in_mem_tb),

    // Data from FUs (now driven by TB, not tied to 0)
    .data_alu_in  (data_alu_in_tb),
    .data_mem_in  (data_mem_in_tb)
  );

  // 100 MHz clock
  always #(CLK_PERIOD/2) clk = ~clk;

  // Helpers
  task automatic run_cycles(input int n);
    repeat (n) @(posedge clk);
  endtask

  // Tie-offs / static signals 
  initial begin
    exec_ready = 1'b1;   // backend always able to take work, for now

    // FUs accept new ops by default
    fu_alu_ready_tb = 1'b1;
    fu_b_ready_tb   = 1'b1;
    fu_mem_ready_tb = 1'b1;

    // Completion defaults
    fu_alu_done_tb  = 1'b0;
    fu_b_done_tb    = 1'b0;
    fu_mem_done_tb  = 1'b0;
    rob_fu_alu_tb   = '0;
    rob_fu_b_tb     = '0;
    rob_fu_mem_tb   = '0;
    ps_in_alu_tb    = '0;
    ps_in_b_tb      = '0;
    ps_in_mem_tb    = '0;

    data_alu_in_tb  = '0;
    data_mem_in_tb  = '0;
  end

  // Reset sequence 
  initial begin
    reset = 1'b1;
    run_cycles(5);           // 5 cycles of reset
    reset = 1'b0;
    $display("[%0t] Deassert reset", $time);

    // Safety guard
    run_cycles(1000);
    $display("[%0t] TEST DONE (timeout)", $time);
    $finish;
  end

  //   Backpressure corner-case: FU NOT READY

  initial begin
    @(negedge reset);         // wait until reset deasserted
    run_cycles(40);           // let pipeline warm up

    $display("[%0t] *** TEST: Stall ALU FU (fu_alu_ready_tb=0) to exercise RS full / backpressure ***", $time);
    fu_alu_ready_tb = 1'b0;   // ALU cannot accept issues
    run_cycles(30);           // keep it stalled for a while

    $display("[%0t] *** RELEASE: ALU FU ready again (fu_alu_ready_tb=1) ***", $time);
    fu_alu_ready_tb = 1'b1;   // allow ALU issues again
  end

  // Handshake

  wire fetch_fire_tb     = dut.fetch_fire;
  wire ren_in_fire_tb    = dut.ren_in_fire;
  wire ren_out_fire_tb   = dut.r_to_bf_di && dut.r_sb_to_r;
  wire disp_in_fire_tb   = dut.v_sb_to_di && dut.r_di_to_sb;
  wire rob_write_fire_tb = dut.rob_write_en;

  // Issue + RS outputs from top-level dispatch/RS
  wire    alu_issued_tb = dut.alu_issued;
  wire    b_issued_tb   = dut.b_issued;
  wire    mem_issued_tb = dut.mem_issued;

  rs_data rs_alu_tb;
  rs_data rs_b_tb;
  rs_data rs_mem_tb;

  assign rs_alu_tb = dut.rs_alu;
  assign rs_b_tb   = dut.rs_b;
  assign rs_mem_tb = dut.rs_mem;

  //  Fake execute pipelines for ALU / Branch / Mem

  typedef struct {
    logic [4:0] rob_tag;
    logic [6:0] pd;
    int         cycles_left;
  } fu_job_t;

  // Per-FU queues
  fu_job_t alu_q[$];
  fu_job_t br_q[$];
  fu_job_t mem_q[$];

  localparam int ALU_LAT = 3;
  localparam int BR_LAT  = 3;
  localparam int MEM_LAT = 3;

  // Main fake-execute process
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      fu_alu_done_tb  <= 1'b0;
      fu_b_done_tb    <= 1'b0;
      fu_mem_done_tb  <= 1'b0;

      alu_q.delete();
      br_q.delete();
      mem_q.delete();
    end else begin
      // Default: no completion pulse this cycle
      fu_alu_done_tb  <= 1'b0;
      fu_b_done_tb    <= 1'b0;
      fu_mem_done_tb  <= 1'b0;

      // 1) Capture ISSUE events from each RS

      // ALU issue
      if (alu_issued_tb) begin
        fu_job_t job;
        job.rob_tag     = rs_alu_tb.rob_index;
        job.pd          = rs_alu_tb.pd;
        job.cycles_left = ALU_LAT;
        alu_q.push_back(job);

        $display("[%0t] ALU ISSUE : fu=%0d pd=%0d ps1=%0d ps2=%0d rob=%0d ps1_r=%0b ps2_r=%0b",
                 $time,
                 rs_alu_tb.fu, rs_alu_tb.pd, rs_alu_tb.ps1, rs_alu_tb.ps2,
                 rs_alu_tb.rob_index, rs_alu_tb.ps1_ready, rs_alu_tb.ps2_ready);
      end

      // Branch issue
      if (b_issued_tb) begin
        fu_job_t job;
        job.rob_tag     = rs_b_tb.rob_index;
        job.pd          = rs_b_tb.pd;  // usually 0 for pure branches
        job.cycles_left = BR_LAT;
        br_q.push_back(job);

        $display("[%0t] BR  ISSUE : fu=%0d pd=%0d ps1=%0d ps2=%0d rob=%0d ps1_r=%0b ps2_r=%0b",
                 $time,
                 rs_b_tb.fu, rs_b_tb.pd, rs_b_tb.ps1, rs_b_tb.ps2,
                 rs_b_tb.rob_index, rs_b_tb.ps1_ready, rs_b_tb.ps2_ready);
      end

      // MEM issue
      if (mem_issued_tb) begin
        fu_job_t job;
        job.rob_tag     = rs_mem_tb.rob_index;
        job.pd          = rs_mem_tb.pd;  // loads nonzero, stores 0
        job.cycles_left = MEM_LAT;
        mem_q.push_back(job);

        $display("[%0t] MEM ISSUE : fu=%0d pd=%0d ps1=%0d ps2=%0d rob=%0d ps1_r=%0b ps2_r=%0b",
                 $time,
                 rs_mem_tb.fu, rs_mem_tb.pd, rs_mem_tb.ps1, rs_mem_tb.ps2,
                 rs_mem_tb.rob_index, rs_mem_tb.ps1_ready, rs_mem_tb.ps2_ready);
      end

      // 2) Decrement countdowns for all jobs
      for (int i = 0; i < alu_q.size(); i++)
        if (alu_q[i].cycles_left > 0) alu_q[i].cycles_left--;

      for (int i = 0; i < br_q.size(); i++)
        if (br_q[i].cycles_left > 0) br_q[i].cycles_left--;

      for (int i = 0; i < mem_q.size(); i++)
        if (mem_q[i].cycles_left > 0) mem_q[i].cycles_left--;

      // 3) Fire completions when jobs reach 0 (one per FU per cycle for simplicity)

      // ALU complete
      if (alu_q.size() > 0 && (alu_q[0].cycles_left == 0)) begin
        fu_alu_done_tb  <= 1'b1;
        rob_fu_alu_tb   <= alu_q[0].rob_tag;
        ps_in_alu_tb    <= alu_q[0].pd;  // broadcast dest preg

        // Write some non-zero pattern into PRF based on pd
        data_alu_in_tb  <= {24'hA5_00, alu_q[0].pd};  // e.g., 0xA500 + pd

        $display("[%0t] FAKE ALU COMPLETE: rob_tag=%0d pd=%0d data=%08h",
                 $time, alu_q[0].rob_tag, alu_q[0].pd, data_alu_in_tb);
        alu_q.pop_front();
      end

      // Branch complete
      if (br_q.size() > 0 && (br_q[0].cycles_left == 0)) begin
        fu_b_done_tb  <= 1'b1;
        rob_fu_b_tb   <= br_q[0].rob_tag;

        // Branch dest usually 0; still keep ps_in_b_tb for debug
        ps_in_b_tb    <= br_q[0].pd;

        $display("[%0t] FAKE BR  COMPLETE: rob_tag=%0d",
                 $time, br_q[0].rob_tag);
        br_q.pop_front();
      end

      // MEM complete
      if (mem_q.size() > 0 && (mem_q[0].cycles_left == 0)) begin
        fu_mem_done_tb  <= 1'b1;
        rob_fu_mem_tb   <= mem_q[0].rob_tag;

        // Loads: pd != 0; Stores: pd == 0
        ps_in_mem_tb    <= mem_q[0].pd;
        data_mem_in_tb  <= {24'h5A_00, mem_q[0].pd};  // another pattern

        $display("[%0t] FAKE MEM COMPLETE: rob_tag=%0d pd=%0d data=%08h",
                 $time, mem_q[0].rob_tag, mem_q[0].pd, data_mem_in_tb);
        mem_q.pop_front();
      end

    end
  end

  // Monitors

  // PC and Fetch monitor + PC+4 assertion
  logic [31:0] last_pc;

  always @(posedge clk) begin
    if (!reset && fetch_fire_tb) begin
      $display("[%0t] FETCH     : pc=%h instr=%h v_fetch=%0b r_to_fetch=%0b",
               $time,
               dut.pc_reg,
               dut.fetch_out.instr,
               dut.v_fetch,
               dut.r_to_fetch);

      // Simple PC + 4 check after the first step
      if (last_pc != 32'h0 && dut.pc_reg != last_pc + 32'd4) begin
        $error("[%0t] PC did not increment by 4: prev=%h now=%h",
               $time, last_pc, dut.pc_reg);
      end
      last_pc <= dut.pc_reg;
    end
  end

  // Stop when we hit end-of-program (instr = xxxxxxxx from ROM)
  always @(posedge clk) begin
    if (!reset && fetch_fire_tb && (dut.fetch_out.instr === 32'hxxxxxxxx)) begin
      $display("[%0t] Hit end of program (instr=xxxxxxxx). Stopping.", $time);
      $finish;
    end
  end

  // Decode to Rename input (post-decode skid buffer output into rename)
  always @(posedge clk) begin
    if (!reset && ren_in_fire_tb) begin
      $display("[%0t] DEC→REN   : pc=%h rs1=%0d rs2=%0d rd=%0d opcode=0x%0h aluop=0x%0h imm=%h",
               $time,
               dut.sb_d_out.pc,
               dut.sb_d_out.rs1,
               dut.sb_d_out.rs2,
               dut.sb_d_out.rd,
               dut.sb_d_out.Opcode,
               dut.sb_d_out.ALUOp,
               dut.sb_d_out.imm);
    end
  end

  // Rename output
  always @(posedge clk) begin
    if (!reset && ren_out_fire_tb) begin
      $display("[%0t] RENAMEOUT : pc=%h fu=%0d pd_new=%0d ps1=%0d ps2=%0d rob_index=%0d",
               $time,
               dut.rename_out.pc,
               dut.rename_out.fu,
               dut.rename_out.pd_new,
               dut.rename_out.ps1,
               dut.rename_out.ps2,
               dut.rename_out.rob_tag);
    end
  end

  // Dispatch input (post-rename skid → dispatch)
  always @(posedge clk) begin
    if (!reset && disp_in_fire_tb) begin
      $display("[%0t] DISPATCHIN: pc=%h fu=%0d pd_new=%0d ps1=%0d ps2=%0d rob_idx_in=%0d",
               $time,
               dut.sb_to_di_out.pc,
               dut.sb_to_di_out.fu,
               dut.sb_to_di_out.pd_new,
               dut.sb_to_di_out.ps1,
               dut.sb_to_di_out.ps2,
               dut.rob_index);
    end
  end

  // ROB write / allocation
  always @(posedge clk) begin
    if (!reset && rob_write_fire_tb) begin
      $display("[%0t] ROBWRITE  : idx=%0d pc=%h pd_new=%0d pd_old=%0d full=%0b",
               $time,
               dut.rob_index,
               dut.sb_to_di_out.pc,
               dut.sb_to_di_out.pd_new,
               dut.sb_to_di_out.pd_old,
               dut.rob_full);
    end
  end

  // ROB full / backpressure debug
  always @(posedge clk) begin
    if (!reset && dut.v_sb_to_di && dut.rob_full) begin
      $display("[%0t] ROB FULL (write side seeing full while v_sb_to_di=1)", $time);
    end
    if (!reset && dut.v_sb_to_di && !dut.r_di_to_sb) begin
      $display("[%0t] DISPATCH not ready (r_di_to_sb=0)", $time);
    end
  end

  // ROB retire monitor
  always @(posedge clk) begin
    if (!reset && dut.valid_retired) begin
      $display("[%0t] ROB RETIRE: preg_old=%0d (free this reg)",
               $time, dut.preg_old);
    end
  end

  //   EXTRA MONITORS: ROB FULL + RS FULL FLAGS + PRF READS

  wire rob_full_tb     = dut.rob_full;
  wire rs_alu_full_tb  = dut.u_dispatch.rs_alu_full;
  wire rs_b_full_tb    = dut.u_dispatch.rs_b_full;
  wire rs_mem_full_tb  = dut.u_dispatch.rs_mem_full;

  // PRF outputs (from phys_reg_file inside ooo_top)
  wire [31:0] ps1_out_alu_tb = dut.ps1_out_alu;
  wire [31:0] ps2_out_alu_tb = dut.ps2_out_alu;

  always @(posedge clk) begin
    if (!reset && rob_full_tb)
      $display("[%0t] MON: ROB FULL asserted (dut.rob_full=1)", $time);
    if (!reset && rs_alu_full_tb)
      $display("[%0t] MON: RS_ALU FULL asserted",  $time);
    if (!reset && rs_b_full_tb)
      $display("[%0t] MON: RS_BR  FULL asserted",  $time);
    if (!reset && rs_mem_full_tb)
      $display("[%0t] MON: RS_MEM FULL asserted",  $time);

    // When ALU issues, we can peek at the PRF read values
    if (!reset && alu_issued_tb) begin
      $display("[%0t] PRF READ  : ALU ps1_val=%08h ps2_val=%08h",
               $time, ps1_out_alu_tb, ps2_out_alu_tb);
    end
  end

endmodule
