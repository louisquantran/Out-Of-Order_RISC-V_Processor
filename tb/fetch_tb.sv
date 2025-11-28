`timescale 1ns/1ps
import types_pkg::*;

module fetch_tb;

  // Clock / Reset 
  localparam CLK_PERIOD = 10; 
  logic clk = 0;
  logic reset = 1;
  always #(CLK_PERIOD/2) clk = ~clk;

  // Golden program image 
  localparam int MEM_DEPTH = 552;
  logic [31:0] golden_mem [0:MEM_DEPTH-1];

  // DUT side signals 
  // PC generator -> Fetch
  logic [31:0] pc_reg, pc_in;

  // Fetch outputs
  logic        valid_fetch_out;
  fetch_data   data_fetch_out;
  logic        ready_fetch_in;   

  // Skid buffer outputs
  logic        ready_skid_out;   
  logic        valid_skid_out;
  fetch_data   data_skid_out;

  // Instantiate DUTs
  Fetch u_fetch (
    .pc_in     (pc_in),
    .ready_out (ready_fetch_in),    
    .valid_out (valid_fetch_out),
    .data_out  (data_fetch_out)
  );

  skid_buffer #(.T(fetch_data)) u_skid (
    .clk       (clk),
    .reset     (reset),
    .valid_in  (valid_fetch_out),
    .data_in   (data_fetch_out),
    .ready_in  (ready_fetch_in),   
    .ready_out (ready_skid_out), 
    .valid_out (valid_skid_out),
    .data_out  (data_skid_out)
  );

wire up_acc = valid_fetch_out && ready_fetch_in;

always_ff @(posedge clk or posedge reset) begin
  if (reset) begin
    pc_reg <= 32'h0;
    pc_in  <= 32'h0;
  end else begin
    automatic logic [31:0] pc_next = up_acc ? (pc_reg + 32'd4) : pc_reg;
    // Present the PC we're committing for this cycle (eliminates duplicate accepts)
    pc_in  <= pc_next;
    pc_reg <= pc_next;
  end
end



  // Self-checks/Assertions 
  // Ensure Fetch is always asserting valid (per your module)
  always_ff @(posedge clk) if (!reset) begin
    assert (valid_fetch_out === 1'b1)
      else $fatal(1, "Fetch valid_out deasserted unexpectedly.");
  end

  // hold or +4 only
  always_ff @(posedge clk) if (!reset) begin
    assert (pc_reg == $past(pc_reg) || pc_reg == $past(pc_reg) + 32'd4)
      else $fatal(1, "PC stepped by non-4 amount.");
  end

  // When skid is full and downstream is not ready, upstream must not advance 
  always_ff @(posedge clk) if (!reset) begin
    if (!ready_fetch_in && !ready_skid_out)
      assert (!up_acc);
  end

  // Golden checks: whenever downstream accepts, verify payload
  always_ff @(posedge clk) if (!reset) begin
    if (valid_skid_out && ready_skid_out) begin
      automatic int idx = data_skid_out.pc >> 2;
      // pc_4 correctness
      assert (data_skid_out.pc_4 == data_skid_out.pc + 32'd4)
        else $fatal(1, "pc_4 mismatch: pc=%h pc_4=%h", data_skid_out.pc, data_skid_out.pc_4);
      // instruction matches program.mem
      assert (golden_mem[idx] === data_skid_out.instr)
        else $fatal(1, "Instr mismatch @PC=%h: got %h exp %h",
                    data_skid_out.pc, data_skid_out.instr, golden_mem[idx]);
      $display("[%0t] ACCEPT  PC=%08h  INSTR=%08h", $time, data_skid_out.pc, data_skid_out.instr);
    end
  end

  // Test sequencing
  initial begin
    $dumpfile("tb_fetch_pipeline_fixed.vcd");
    $dumpvars(0, tb_fetch_pipeline_fixed);

    // Load golden
    $readmemh("program.mem", golden_mem);
    // Quick sanity on first entries
    for (int i = 0; i < 8; i++)
      if (^golden_mem[i] === 1'bx)
        $fatal(1, "program.mem not found/unreadable (golden_mem[%0d] is X).", i);

    // Reset sequence
    ready_skid_out = 1'b0;   
    repeat (4) @(posedge clk);
    reset = 1'b0;

    $display("           Start Test Sequence             ");

    // Test 1: Downstream always Ready (Fast Path) 
    $display("\n--- Test 1: Downstream always Ready (Fast Path) ---");
    $display("Expect instructions at 0x00, 0x04, 0x08, 0x0C to pass through.");
    ready_skid_out = 1'b1;
    repeat (6) @(posedge clk);

    // Test 2: Sustained stall then release 
    $display("\n--- Test 2: Downstream Not Ready (Backpressure Test) ---");
    // Assert stall for 2 cycles while buffer is empty -> first cycle stores D0, PC advances; second holds.
    ready_skid_out = 1'b0;
    @(posedge clk); $display("Time:%0t | Stall-C1: store D0 (pc=%08h) -> PC advances next=%08h; ready_in=%b",
                             $time, pc_in, pc_reg, ready_fetch_in);
    @(posedge clk); $display("Time:%0t | Stall-C2: skid holds; PC stalls at %08h; ready_in=%b",
                             $time, pc_reg, ready_fetch_in);

    // Release stall -> drain and resume pass-through
    ready_skid_out = 1'b1;
    @(posedge clk); $display("Time:%0t | Release: drain D0; upstream accepted again; PC next=%08h; ready_in=%b",
                             $time, pc_reg, ready_fetch_in);
    repeat (3) @(posedge clk);

    // Test 3: One-cycle stall (hidden from Fetch) 
    $display("\n--- Test 3: One-cycle Stall (Hidden) ---");
    ready_skid_out = 1'b0;   // 1-cycle stall -> store one beat, PC still advances
    @(posedge clk);
    ready_skid_out = 1'b1;   // immediately ready again -> drain + pass-through same cycle
    @(posedge clk);
    repeat (3) @(posedge clk);

    $display("             End Test Sequence             ");
    $finish;
  end

endmodule
