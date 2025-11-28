`timescale 1ns / 1ps
import types_pkg::*;

module rename_tb;

    // ---------------- Clock & reset ----------------
    logic clk = 0;
    logic reset = 1;
    always #5 clk = ~clk;  // 100 MHz

    // ---------------- DUT I/O ----------------
    logic        valid_in;
    decode_data  data_in;
    logic        ready_in;

    // From ROB (free list returns older phys regs)
    logic        write_en;
    logic [6:0]  rob_data_in;

    // Mispredict from ROB
    logic        mispredict;

    // Downstream
    rename_data  data_out;
    logic        valid_out;
    logic        ready_out;

    // ---------------- Instantiate DUT ----------------
    rename dut (
        .clk         (clk),
        .reset       (reset),

        // Upstream
        .valid_in    (valid_in),
        .data_in     (data_in),
        .ready_in    (ready_in),

        // From ROB
        .write_en    (write_en),
        .rob_data_in (rob_data_in),

        // Mispredict
        .mispredict  (mispredict),

        // Downstream
        .data_out    (data_out),
        .valid_out   (valid_out),
        .ready_out   (ready_out)
    );

    // ---------------- Opcodes (RV32I) ----------------
    localparam [6:0] OP_IMM = 7'b0010011; // I-type ALU
    localparam [6:0] OP     = 7'b0110011; // R-type ALU
    localparam [6:0] LOAD   = 7'b0000011; // Load
    localparam [6:0] STORE  = 7'b0100011; // Store (no rd write)

    // ---------------- Helper macro -------------------
`ifndef CHECK
`define CHECK(MSG, COND) \
    if (!(COND)) begin \
        $error("CHECK FAILED: %s (time=%0t)", MSG, $time); \
    end else begin \
        $display("CHECK OK   : %s (time=%0t)", MSG, $time); \
    end
`endif

    // ---------------- Drive one uop ------------------
    // Drives one instruction into rename, waits until it is
    // accepted (valid_in && ready_in), then waits for valid_out
    // and samples data_out.
    task automatic drive_uop(
        input  logic [6:0]  opc,
        input  logic [4:0]  rs1,
        input  logic [4:0]  rs2,
        input  logic [4:0]  rd,
        input  logic [31:0] imm
    );
        begin
            // Present instruction
            valid_in        = 1'b1;
            data_in         = '0;
            data_in.pc      = 32'h0000_1000;   // arbitrary
            data_in.Opcode  = opc;
            data_in.rs1     = rs1;
            data_in.rs2     = rs2;
            data_in.rd      = rd;
            data_in.imm     = imm;

            // ALUOp/fu for completeness (rename doesn't really care)
            unique case (opc)
                OP_IMM: begin
                    data_in.ALUOp = 3'b011;
                    data_in.fu    = 2'b01;
                end
                OP: begin
                    data_in.ALUOp = 3'b010;
                    data_in.fu    = 2'b01;
                end
                LOAD,
                STORE: begin
                    data_in.ALUOp = 3'b000;
                    data_in.fu    = 2'b11;
                end
                default: begin
                    data_in.ALUOp = 3'b000;
                    data_in.fu    = 2'b00;
                end
            endcase

            // Always ready downstream for this helper
            ready_out = 1'b1;

            // Wait for rename to "fire" the input (valid_in && ready_in)
            do @(posedge clk);
            while (!(valid_in && ready_in));

            // Drop valid_in so we don't keep injecting
            valid_in = 1'b0;

            // Wait until output becomes valid
            do @(posedge clk);
            while (!valid_out);

            // Give one extra cycle between transactions
            @(posedge clk);
        end
    endtask

    // ---------------- Test sequence ------------------
    integer wait_cycles;
    initial begin
        logic [6:0] pd_new_1;
        logic [6:0] pd_new_2;

        // Init
        valid_in    = 1'b0;
        ready_out   = 1'b1;
        data_in     = '0;
        mispredict  = 1'b0;
        write_en    = 1'b0;
        rob_data_in = '0;

        // Reset
        repeat (3) @(posedge clk);
        reset = 1'b0;
        @(posedge clk);

        $display("---- Test 1: First writer (ADDI x5, x1, imm) ----");
        // Assume at reset: map[xN] = N, free_list gives non-zero pd.
        drive_uop(OP_IMM, /*rs1*/5'd1, /*rs2*/5'd2, /*rd*/5'd5,
                  32'h0000_0001);

        // NOTE: valid_out is a one-cycle pulse; by the time we get here,
        // it may have dropped back to 0. We already waited on it inside
        // drive_uop, so we do NOT assert valid_out again here.
        `CHECK("ps1==map[x1]==1",            data_out.ps1 == 7'd1);
        `CHECK("ps2==map[x2]==2",            data_out.ps2 == 7'd2);
        `CHECK("pd_old==map[x5]==5",         data_out.pd_old == 7'd5);

        pd_new_1 = data_out.pd_new;
        `CHECK("pd_new allocated (!= old mapping)",
               pd_new_1 !== data_out.pd_old);
        `CHECK("pd_new != 0 (assuming p0 reserved for x0)",
               pd_new_1 != 7'd0);

        $display("---- Test 2: Dependent writer (LOAD x6, 0(x5)) ----");
        // rs1 = x5 should see the new mapping from Test 1.
        drive_uop(LOAD, /*rs1*/5'd5, /*rs2*/5'd0, /*rd*/5'd6,
                  32'h0);

        `CHECK("ps1==new x5 mapping (pd_new_1)",
               data_out.ps1 == pd_new_1);
        `CHECK("pd_old==map[x6]==6", data_out.pd_old == 7'd6);

        pd_new_2 = data_out.pd_new;
        `CHECK("second pd_new allocated and different from first",
               (pd_new_2 != pd_new_1) && (pd_new_2 != 7'd0));

        $display("---- Test 3: Backpressure on ready_out ----");
        // Present the instruction
        valid_in        = 1'b1;
        data_in         = '0;
        data_in.pc      = 32'h0000_2000;
        data_in.Opcode  = OP;
        data_in.rs1     = 5'd6;      // should map to pd_new_2
        data_in.rs2     = 5'd0;
        data_in.rd      = 5'd7;
        data_in.imm     = '0;
        data_in.ALUOp   = 3'b010;
        data_in.fu      = 2'b01;

        // First cycle: downstream not ready
        ready_out = 1'b0;
        @(posedge clk);

        // Drop valid_in now
        valid_in = 1'b0;

        // Wait until valid_out asserts
        wait_cycles = 0;
        while (!valid_out) begin
            @(posedge clk);
            if (wait_cycles++ > 10) begin
                $fatal(1, "Timeout waiting for valid_out during backpressure test");
            end
        end

        // While ready_out==0, valid_out should stay asserted.
        `CHECK("valid_out stays high while ready_out=0", valid_out == 1'b1);

        // And mapping for x6 should be pd_new_2.
        `CHECK("backpressure: ps1==mapping of x6 (pd_new_2)",
               data_out.ps1 == pd_new_2);

        // Now release downstream
        ready_out = 1'b1;
        @(posedge clk);

        // After one more cycle, valid_out is allowed to drop
        @(posedge clk);
        `CHECK("valid_out eventually de-asserts after ready_out=1",
               valid_out == 1'b0);

        $display("---- Test 4: STORE x2 -> 0(x1) (no pd allocation) ----");
        // STORE should NOT allocate a new pd (Opcode == 0100011).
        drive_uop(STORE, /*rs1*/5'd1, /*rs2*/5'd2, /*rd*/5'd0,
                  32'h0);

        `CHECK("STORE ps1==map[x1]==1", data_out.ps1 == 7'd1);
        `CHECK("STORE ps2==map[x2]==2", data_out.ps2 == 7'd2);
        `CHECK("STORE pd_new==0 (no allocation)", data_out.pd_new == 7'd0);
        `CHECK("STORE pd_old==map[x0]==0",        data_out.pd_old == 7'd0);

        $display("---- Test 5: rd==x0 (no pd allocation) ----");
        // ADDI x0, x1, imm: should NOT allocate, x0 is hardwired.
        drive_uop(OP_IMM, /*rs1*/5'd1, /*rs2*/5'd0, /*rd*/5'd0,
                  32'h1234);

        `CHECK("x0 write: pd_new==0 (no alloc)", data_out.pd_new == 7'd0);
        `CHECK("x0 write: pd_old==map[x0]==0",    data_out.pd_old == 7'd0);

        $display("---- NOTE: mispredict / checkpoint tests ----");
        $display("rename currently only has a mispredict input.");
        $display("Once you expose branch tag / checkpoint ports,");
        $display("we can extend this TB to exercise full recovery.");

        $display("All basic rename tests completed.");
        $finish;
    end

endmodule
