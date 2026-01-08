`timescale 1ns/1ps
import types_pkg::*;

module ooo_top_tb;

  // ---------------- Clock / Reset / DUT ----------------
  logic clk   = 0;
  logic reset = 1;
  logic exec_ready;

  localparam int CLK_PERIOD        = 10;    // 100 MHz
  localparam int MAX_CYCLES        = 1000;  // safety timeout
  localparam int PIPE_DRAIN_CYCLES = 50;    // after hitting invalid instr

  // NEW: stall watchdog threshold
  localparam int STALL_LIMIT_CYCLES = 80;

  // Clock
  always #(CLK_PERIOD/2) clk = ~clk;

  // DUT
  ooo_top dut (
    .clk        (clk),
    .reset      (reset),
    .exec_ready (exec_ready)
  );

  // Simple helper
  task automatic run_cycles(input int n);
    repeat (n) @(posedge clk);
  endtask

  // ---------------- Handy wires into DUT internals ----------------

  // Fetch fire (already computed inside ooo_top)
  wire        fetch_fire_tb = dut.fetch_fire;
  wire fetch_data  fetch_mon     = dut.fetch_out;

  // If you have these in ooo_top, tap them directly (used for stability checks)
  // NOTE: if your top-level names differ, update these to match.
  wire v_fetch_tb   = dut.v_fetch;
  wire r_to_fetch_tb = dut.r_to_fetch;

  // Branch "taken" indicator (matches actual PC update condition)
  wire branch_taken_tb = fetch_fire_tb &&
                         dut.b_out.fu_b_done &&
                         dut.b_out.jalr_bne_signal;

  // ---------------- PC Checker ----------------
  logic [31:0] prev_pc;
  logic        prev_branch_taken;
  logic [31:0] prev_branch_pc;
  logic        prev_fetch_fire;

  always_ff @(posedge clk) begin
    if (reset) begin
      prev_pc           <= 32'h0000_0000;
      prev_branch_taken <= 1'b0;
      prev_branch_pc    <= 32'h0000_0000;
      prev_fetch_fire   <= 1'b0;
    end else begin
      if (prev_fetch_fire) begin
        if (prev_branch_taken) begin
          if (dut.pc_reg !== prev_branch_pc) begin
            $error("[%0t] PC mismatch on branch: got 0x%08h, expected 0x%08h",
                   $time, dut.pc_reg, prev_branch_pc);
          end else begin
            $display("[%0t] PC OK (branch) : pc_reg=0x%08h",
                     $time, dut.pc_reg);
          end
        end else begin
          if (dut.pc_reg !== (prev_pc + 32'd4)) begin
            $error("[%0t] PC mismatch on sequential step: prev=0x%08h, got=0x%08h",
                   $time, prev_pc, dut.pc_reg);
          end else begin
            $display("[%0t] PC OK (seq)    : 0x%08h -> 0x%08h",
                     $time, prev_pc, dut.pc_reg);
          end
        end
      end

      prev_pc           <= dut.pc_reg;
      prev_branch_taken <= branch_taken_tb;
      prev_branch_pc    <= dut.b_out.pc;
      prev_fetch_fire   <= fetch_fire_tb;
    end
  end

  // ---------------- Detect "no more valid instructions" ----------------
  logic seen_invalid_instr;
  int   drain_counter;

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      seen_invalid_instr <= 1'b0;
      drain_counter      <= 0;
    end else begin
      if (fetch_fire_tb && !seen_invalid_instr) begin
        if (^fetch_mon.instr === 1'bx) begin
          seen_invalid_instr <= 1'b1;
          $display("[%0t] Detected invalid/X instruction at PC=0x%08h, starting drain.",
                   $time, fetch_mon.pc);
        end
      end

      if (seen_invalid_instr && drain_counter < PIPE_DRAIN_CYCLES)
        drain_counter <= drain_counter + 1;
    end
  end

  // ============================================================
  // NEW: Ready/Valid stability checkers
  // ============================================================

  // 1) Fetch payload must be stable while v_fetch && !r_to_fetch
  // This will catch the common bug: "valid_out=1 always" + changing PC/data while downstream not ready
  fetch_data fetch_hold;
  logic      fetch_holding;

  always_ff @(posedge clk) begin
    if (reset) begin
      fetch_hold    <= '0;
      fetch_holding <= 1'b0;
    end else begin
      if (v_fetch_tb && !r_to_fetch_tb) begin
        if (!fetch_holding) begin
          fetch_hold    <= dut.fetch_out;
          fetch_holding <= 1'b1;
        end else begin
          if (dut.fetch_out !== fetch_hold) begin
            $error("[%0t] FETCH PAYLOAD CHANGED while stalled (v_fetch=1, r_to_fetch=0). Held pc=0x%08h instr=0x%08h, now pc=0x%08h instr=0x%08h",
                   $time,
                   fetch_hold.pc, fetch_hold.instr,
                   dut.fetch_out.pc, dut.fetch_out.instr);
          end
        end
      end else begin
        fetch_holding <= 1'b0;
      end
    end
  end

  // 2) Rename output must be stable while rename.valid_out && !rename.ready_out
  // NOTE: update instance path if your rename instance isn't "u_rename"
  rename_data ren_hold;
  logic       ren_holding;

  always_ff @(posedge clk) begin
    if (reset) begin
      ren_hold    <= '0;
      ren_holding <= 1'b0;
    end else begin
      if (dut.u_rename.valid_out && !dut.u_rename.ready_out) begin
        if (!ren_holding) begin
          ren_hold    <= dut.rename_out;
          ren_holding <= 1'b1;
        end else begin
          if (dut.rename_out !== ren_hold) begin
            $error("[%0t] RENAME_OUT CHANGED while stalled (rename.valid_out=1, rename.ready_out=0). Held pc=0x%08h rob_tag=%0d, now pc=0x%08h rob_tag=%0d",
                   $time,
                   ren_hold.pc, ren_hold.rob_tag,
                   dut.rename_out.pc, dut.rename_out.rob_tag);
          end
        end
      end else begin
        ren_holding <= 1'b0;
      end
    end
  end

  // 3) Post-rename skid output must be stable while v_sb_to_di && !r_di_to_sb
  rename_data sb_hold;
  logic       sb_holding;

  always_ff @(posedge clk) begin
    if (reset) begin
      sb_hold    <= '0;
      sb_holding <= 1'b0;
    end else begin
      if (dut.v_sb_to_di && !dut.r_di_to_sb) begin
        if (!sb_holding) begin
          sb_hold    <= dut.sb_to_di_out;
          sb_holding <= 1'b1;
        end else begin
          if (dut.sb_to_di_out !== sb_hold) begin
            $error("[%0t] SB_TO_DI_OUT CHANGED while stalled (v_sb_to_di=1, r_di_to_sb=0). Held pc=0x%08h rob_tag=%0d, now pc=0x%08h rob_tag=%0d",
                   $time,
                   sb_hold.pc, sb_hold.rob_tag,
                   dut.sb_to_di_out.pc, dut.sb_to_di_out.rob_tag);
          end
        end
      end else begin
        sb_holding <= 1'b0;
      end
    end
  end

  // ============================================================
  // NEW: Forward-progress watchdog
  // ============================================================
  int stall_ctr;

  function automatic bit made_progress_this_cycle;
    // Expand this list as needed; the idea is to catch "everything stopped"
    made_progress_this_cycle =
      fetch_fire_tb ||
      dut.rob_write_en ||
      dut.alu_issued || dut.mem_issued || dut.b_issued ||
      dut.alu_out.fu_alu_done || dut.mem_out.fu_mem_done || dut.b_out.fu_b_done ||
      dut.mispredict ||
      dut.b_out.hit;
  endfunction

  task automatic dump_stall_snapshot;
    $display("----------- STALL SNAPSHOT @ %0t -----------", $time);
    $display("pc_reg=0x%08h", dut.pc_reg);
    $display("fetch_fire=%0b v_fetch=%0b r_to_fetch=%0b", fetch_fire_tb, v_fetch_tb, r_to_fetch_tb);
    $display("v_decode=%0b", dut.v_decode);

    // Rename handshake
    $display("rename.valid_out=%0b rename.ready_out=%0b",
             dut.u_rename.valid_out, dut.u_rename.ready_out);

    // Post-rename skid handshake
    $display("v_sb_to_di=%0b r_di_to_sb=%0b", dut.v_sb_to_di, dut.r_di_to_sb);

    // ROB
    $display("rob_write_en=%0b rob_index=%0d", dut.rob_write_en, dut.rob_index);

    // FU status
    $display("alu_done=%0b mem_done=%0b br_done=%0b",
             dut.alu_out.fu_alu_done, dut.mem_out.fu_mem_done, dut.b_out.fu_b_done);

    $display("mispredict=%0b mispredict_tag=%0d hit=%0b",
             dut.mispredict, dut.mispredict_tag, dut.b_out.hit);

    $display("--------------------------------------------");
  endtask

  always_ff @(posedge clk) begin
    if (reset) begin
      stall_ctr <= 0;
    end else begin
      if (made_progress_this_cycle()) begin
        stall_ctr <= 0;
      end else begin
        stall_ctr <= stall_ctr + 1;
        if (stall_ctr == STALL_LIMIT_CYCLES) begin
          dump_stall_snapshot();
          $fatal(1, "[%0t] DEADLOCK: no forward progress for %0d cycles.",
                 $time, STALL_LIMIT_CYCLES);
        end
      end
    end
  end

  // ---------------- Debug printing / pipeline tracing ----------------

  // FETCH
  always_ff @(posedge clk) begin
    if (!reset && fetch_fire_tb) begin
      fetch_data f = dut.fetch_out;
      $display("[%0t] FETCH : pc=0x%08h instr=0x%08h pc_4=0x%08h",
               $time, f.pc, f.instr, f.pc_4);
    end
  end

  // DECODE → RENAME (decode output)
  always_ff @(posedge clk) begin
    if (!reset && dut.v_decode) begin
      decode_data d = dut.decode_out;
      $display("[%0t] DEC→REN : pc=0x%08h rs1=%0d rs2=%0d rd=%0d opcode=0x%02h fu=%0d imm=0x%08h",
               $time, d.pc, d.rs1, d.rs2, d.rd, d.Opcode, d.fu, d.imm);
    end
  end

  // RENAME output
  always_ff @(posedge clk) begin
    if (!reset && dut.r_to_bf_di) begin
      rename_data r = dut.rename_out;
      $display("[%0t] RENAMEOUT : pc=0x%08h fu=%0d pd_new=%0d pd_old=%0d ps1=%0d ps2=%0d opcode=0x%02h imm=0x%08h rob_tag=%0d",
               $time, r.pc, r.fu, r.pd_new, r.pd_old, r.ps1, r.ps2,
               r.Opcode, r.imm[31:0], r.rob_tag);
    end
  end

  // RENAME → DISPATCH (post-rename skid out)
  always_ff @(posedge clk) begin
    if (!reset && dut.v_sb_to_di && dut.r_di_to_sb) begin
      rename_data r = dut.sb_to_di_out;
      $display("[%0t] REN→DIS : pc=0x%08h fu=%0d pd_new=%0d ps1=%0d ps2=%0d rob_tag=%0d",
               $time, r.pc, r.fu, r.pd_new, r.ps1, r.ps2, r.rob_tag);
    end
  end

  // ROB enqueue
  always_ff @(posedge clk) begin
    if (!reset && dut.rob_write_en) begin
      rename_data r = dut.sb_to_di_out;
      $display("[%0t] ROB ENQ : rob_idx=%0d pc=0x%08h pd_new=%0d pd_old=%0d",
               $time, dut.rob_index, r.pc, r.pd_new, r.pd_old);
    end
  end

  // ISSUE from RS: ALU / MEM / BR
  always_ff @(posedge clk) begin
    if (!reset && dut.alu_issued) begin
      rs_data ra = dut.rs_alu;
      $display("[%0t] ISSUE ALU : rob=%0d pd=%0d ps1=%0d ps2=%0d",
               $time, ra.rob_index, ra.pd, ra.ps1, ra.ps2);
    end

    if (!reset && dut.mem_issued) begin
      rs_data rm = dut.rs_mem;
      $display("[%0t] ISSUE MEM : rob=%0d pd=%0d ps1=%0d ps2=%0d",
               $time, rm.rob_index, rm.pd, rm.ps1, rm.ps2);
    end

    if (!reset && dut.b_issued) begin
      rs_data rb = dut.rs_b;
      $display("[%0t] ISSUE BR  : rob=%0d pd=%0d ps1=%0d ps2=%0d",
               $time, rb.rob_index, rb.pd, rb.ps1, rb.ps2);
    end
  end

  // FU completes: ALU / MEM / BR
  always_ff @(posedge clk) begin
    if (!reset && dut.alu_out.fu_alu_done) begin
      $display("[%0t] FU ALU DONE : rob=%0d pd=%0d data=0x%08h",
               $time, dut.alu_out.rob_fu_alu, dut.alu_out.p_alu, dut.alu_out.data);
    end

    if (!reset && dut.mem_out.fu_mem_done) begin
      $display("[%0t] FU MEM DONE : rob=%0d pd=%0d data=0x%08h",
               $time, dut.mem_out.rob_fu_mem, dut.mem_out.p_mem, dut.mem_out.data);
    end

    if (!reset && dut.b_out.fu_b_done) begin
      $display("[%0t] FU BR  DONE : rob=%0d pd=%0d mispredict=%0b tag=%0d jalr_bne=%0b pc=0x%08h",
               $time,
               dut.b_out.rob_fu_b,
               dut.b_out.p_b,
               dut.b_out.mispredict,
               dut.b_out.mispredict_tag,
               dut.b_out.jalr_bne_signal,
               dut.b_out.pc);
    end
  end

  // ---------------- Global mispredict monitor (from ROB) ----------------
  logic [4:0] last_mispredict_tag;
  logic       seen_mispredict_for_tag;

  always_ff @(posedge clk) begin
    if (reset) begin
      last_mispredict_tag     <= '0;
      seen_mispredict_for_tag <= 1'b0;
    end else begin
      if (dut.mispredict) begin
        if (!seen_mispredict_for_tag || (dut.mispredict_tag != last_mispredict_tag)) begin
          $display("[%0t] *** GLOBAL MISPREDICT tag=%0d ***",
                   $time, dut.mispredict_tag);
          last_mispredict_tag     <= dut.mispredict_tag;
          seen_mispredict_for_tag <= 1'b1;
        end
      end
    end
  end

  // ---------------- Architectural state check (a0/a1) ----------------
  task automatic check_arch_state;
    logic [6:0]  p_x10, p_x11;
    logic [31:0] v_x10, v_x11;
    logic [31:0] exp_a0, exp_a1;

    p_x10 = dut.u_rename.u_map_table.map[10];
    p_x11 = dut.u_rename.u_map_table.map[11];

    v_x10 = dut.u_phys_reg.prf[p_x10];
    v_x11 = dut.u_phys_reg.prf[p_x11];

    $display("Final a0/x10: p=%0d val=0x%08h", p_x10, v_x10);
    $display("Final a1/x11: p=%0d val=0x%08h", p_x11, v_x11);

    exp_a0 = 32'h0000_0005;
    exp_a1 = 32'h0000_0005;

    if (v_x10 !== exp_a0) $error("a0/x10 mismatch: got 0x%08h, expected 0x%08h", v_x10, exp_a0);
    else                 $display("a0/x10 OK: 0x%08h", v_x10);

    if (v_x11 !== exp_a1) $error("a1/x11 mismatch: got 0x%08h, expected 0x%08h", v_x11, exp_a1);
    else                 $display("a1/x11 OK: 0x%08h", v_x11);
  endtask

  // ---------------- Main control: reset, run, end-early ----------------
  initial begin
    $display("=== Starting ooo_top integration test ===");

    exec_ready = 1'b1;

    reset = 1'b1;
    run_cycles(5);

    reset = 1'b0;
    $display("[%0t] Deassert reset", $time);
    $display("[%0t] Warm-up: letting instructions flow", $time);

    for (int cyc = 0; cyc < MAX_CYCLES; cyc++) begin
      run_cycles(1);

      if (seen_invalid_instr && drain_counter >= PIPE_DRAIN_CYCLES) begin
        $display("[%0t] Program appears done (no more valid instructions, pipe drained).",
                 $time);
        check_arch_state();
        $display("[%0t] Ending ooo_top integration test", $time);
        $finish;
      end
    end

    $error("Simulation timeout: did not reach quiescent state within %0d cycles.", MAX_CYCLES);
    dump_stall_snapshot();
    check_arch_state();
    $display("[%0t] Ending ooo_top integration test (timeout path)", $time);
    $finish;
  end

endmodule
