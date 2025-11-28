`timescale 1ns / 1ps

import types_pkg::*;

module decode_tb;

  // Local "clock" only for scheduling in TB (decode itself is combinational)
  logic        clk;
  logic        reset;

  // DUT I/O
  logic [31:0] instr;
  logic [31:0] pc_in;
  logic        valid_in;
  logic        ready_in;   // output from decode
  logic        ready_out;  // input to decode
  logic        valid_out;
  decode_data  data_out;

  // Instantiate DUT (name must match: 'decode', not 'Decode')
  decode dut (
    .instr     (instr),
    .pc_in     (pc_in),
    .valid_in  (valid_in),
    .ready_in  (ready_in),
    .ready_out (ready_out),
    .valid_out (valid_out),
    .data_out  (data_out)
  );

  // Simple clock for TB bookkeeping
  initial begin
    clk = 0;
    forever #5 clk = ~clk;  // 100 MHz
  end

  // One test vector describing an instruction and expected decode result
  typedef struct {
    string       name;
    logic [31:0] pc;
    logic [31:0] instr;
    logic [4:0]  rs1;
    logic [4:0]  rs2;
    logic [4:0]  rd;
    logic [31:0] imm;
    logic [2:0]  aluop;
    logic [6:0]  opcode;
    // NOTE: fu_mem / fu_alu removed; decode_data now has a single 'fu' field.
  } decode_test_t;

  // Collection of tests
  decode_test_t tests[$];
  int num_errors = 0;

  // Task to run one decode test
  task automatic run_one (decode_test_t t);
  begin
    $display("\n--- Running test: %s ---", t.name);

    // "Reset" TB-side state before each test
    reset     = 1'b1;
    valid_in  = 1'b0;
    ready_out = 1'b0;
    instr     = 32'h0;
    pc_in     = 32'h0;
    @(posedge clk);

    reset = 1'b0;

    // Drive instruction into DUT
    instr     = t.instr;
    pc_in     = t.pc;
    valid_in  = 1'b1;
    ready_out = 1'b1;  // downstream ready

    // Wait a little for combinational decode to settle
    #1;

    // Basic validity check
    if (!valid_out) begin
      $error("Test '%s': valid_out == 0 (expected 1)", t.name);
      num_errors++;
    end

    // Check fields
    if (data_out.pc !== t.pc) begin
      $error("Test '%s': pc mismatch. Got 0x%08h, expected 0x%08h",
             t.name, data_out.pc, t.pc);
      num_errors++;
    end

    if (data_out.rs1 !== t.rs1) begin
      $error("Test '%s': rs1 mismatch. Got %0d, expected %0d",
             t.name, data_out.rs1, t.rs1);
      num_errors++;
    end

    if (data_out.rs2 !== t.rs2) begin
      $error("Test '%s': rs2 mismatch. Got %0d, expected %0d",
             t.name, data_out.rs2, t.rs2);
      num_errors++;
    end

    if (data_out.rd !== t.rd) begin
      $error("Test '%s': rd mismatch. Got %0d, expected %0d",
             t.name, data_out.rd, t.rd);
      num_errors++;
    end

    if (data_out.imm !== t.imm) begin
      $error("Test '%s': imm mismatch. Got 0x%08h, expected 0x%08h",
             t.name, data_out.imm, t.imm);
      num_errors++;
    end

    if (data_out.ALUOp !== t.aluop) begin
      $error("Test '%s': aluop mismatch. Got %0b, expected %0b",
             t.name, data_out.ALUOp, t.aluop);
      num_errors++;
    end

    if (data_out.Opcode !== t.opcode) begin
      $error("Test '%s': opcode mismatch. Got %07b, expected %07b",
             t.name, data_out.Opcode, t.opcode);
      num_errors++;
    end

    if (num_errors == 0)
      $display("Test '%s' PASSED.", t.name);

    // Drop inputs before next test
    valid_in  = 1'b0;
    ready_out = 1'b0;
    @(posedge clk);
  end
  endtask

  initial begin
    // 1) I-type ADDI x5, x6, -1
    tests.push_back('{
      name  : "I-type ADDI x5, x6, -1",
      pc    : 32'h0000_0000,
      instr : 32'hFFF3_0293,
      rs1   : 5'd6,
      rs2   : 5'd0,
      rd    : 5'd5,
      imm   : 32'hFFFF_FFFF,   // sign-extended -1
      aluop : 3'b011,          // from your signal_decode for 0010011
      opcode: 7'b0010011
    });

    // 2) LUI x3, 0xABCDE000
    //    opcode 0110111, U-type
    //    instr = 32'hABCDE1B7
    tests.push_back('{
      name  : "U-type LUI x3, 0xABCDE000",
      pc    : 32'h0000_0004,
      instr : 32'hABCDE1B7,
      rs1   : 5'd0,
      rs2   : 5'd0,
      rd    : 5'd3,
      imm   : 32'hABCDE_000,   // upper 20 bits << 12
      aluop : 3'b100,
      opcode: 7'b0110111
    });

    // 3) ADD x3, x4, x5
    //    opcode 0110011, R-type
    //    instr = 32'h0052_01B3
    tests.push_back('{
      name  : "R-type ADD x3, x4, x5",
      pc    : 32'h0000_0008,
      instr : 32'h0052_01B3,
      rs1   : 5'd4,
      rs2   : 5'd5,
      rd    : 5'd3,
      imm   : 32'h0000_0000,   // R-type, ImmGen should give 0
      aluop : 3'b010,
      opcode: 7'b0110011
    });

    // 4) LW x10, -16(x8)
    //    opcode 0000011, I-type load
    //    instr = 32'hFF04_2503
    tests.push_back('{
      name  : "Load LW x10, -16(x8)",
      pc    : 32'h0000_000C,
      instr : 32'hFF04_2503,
      rs1   : 5'd8,
      rs2   : 5'd0,
      rd    : 5'd10,
      imm   : 32'hFFFF_FFF0,   // -16
      aluop : 3'b000,
      opcode: 7'b0000011
    });

    // 5) SW x5, 8(x8)
    //    opcode 0100011, S-type
    //    instr = 32'h0054_2423
    tests.push_back('{
      name  : "Store SW x5, 8(x8)",
      pc    : 32'h0000_0010,
      instr : 32'h0054_2423,
      rs1   : 5'd8,
      rs2   : 5'd5,
      rd    : 5'd0,
      imm   : 32'h0000_0008,
      aluop : 3'b000,
      opcode: 7'b0100011
    });

    // 6) BNE x1, x2, 16
    //    opcode 1100011, B-type, offset +16 bytes
    //    instr = 32'h0020_9863
    tests.push_back('{
      name  : "Branch BNE x1, x2, +16",
      pc    : 32'h0000_0014,
      instr : 32'h0020_9863,
      rs1   : 5'd1,
      rs2   : 5'd2,
      rd    : 5'd0,
      imm   : 32'h0000_0010,   // +16, as a signed immediate
      aluop : 3'b001,
      opcode: 7'b1100011
    });

    // 7) JALR x1, 12(x0)
    //    opcode 1100111, I-type
    //    instr = 32'h00C0_00E7
    tests.push_back('{
      name  : "JALR x1, 12(x0)",
      pc    : 32'h0000_0018,
      instr : 32'h00C0_00E7,
      rs1   : 5'd0,
      rs2   : 5'd0,
      rd    : 5'd1,
      imm   : 32'h0000_000C,
      aluop : 3'b110,
      opcode: 7'b1100111
    });

    // Initial idle state
    reset     = 1'b0;
    valid_in  = 1'b0;
    ready_out = 1'b0;
    instr     = 32'h0;
    pc_in     = 32'h0;
    @(posedge clk);

    foreach (tests[i]) begin
      run_one(tests[i]);
    end

    if (num_errors == 0)
      $display("\nAll %0d decode tests PASSED", tests.size());
    else
      $display("\nDecode tests completed with %0d errors", num_errors);

    $finish;
  end

endmodule
