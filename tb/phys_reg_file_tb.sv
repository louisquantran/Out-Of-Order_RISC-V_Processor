`timescale 1ns/1ps

module phys_reg_file_tb;

    // DUT ports 
    logic        clk;
    logic        reset;

    // Write ports (ALU + BR + MEM)
    logic        write_alu_en;
    logic [31:0] data_alu_in;
    logic [6:0]  pd_alu_in;

    logic        write_b_en;
    logic [31:0] data_b_in;
    logic [6:0]  pd_b_in;

    logic        write_mem_en;
    logic [31:0] data_mem_in;
    logic [6:0]  pd_mem_in;

    // Read enables
    logic        read_en_alu;
    logic        read_en_b;
    logic        read_en_mem;

    // ALU read ports
    logic [6:0]  ps1_in_alu;
    logic [6:0]  ps2_in_alu;
    logic [31:0] ps1_out_alu;
    logic [31:0] ps2_out_alu;

    // Branch read ports
    logic [6:0]  ps1_in_b;
    logic [6:0]  ps2_in_b;
    logic [31:0] ps1_out_b;
    logic [31:0] ps2_out_b;

    // MEM read ports
    logic [6:0]  ps1_in_mem;
    logic [6:0]  ps2_in_mem;
    logic [31:0] ps1_out_mem;
    logic [31:0] ps2_out_mem;

    // DUT instantiation
    phys_reg_file dut (
        .clk         (clk),
        .reset       (reset),

        .write_alu_en (write_alu_en),
        .data_alu_in  (data_alu_in),
        .pd_alu_in    (pd_alu_in),

        .write_b_en   (write_b_en),
        .data_b_in    (data_b_in),
        .pd_b_in      (pd_b_in),

        .write_mem_en (write_mem_en),
        .data_mem_in  (data_mem_in),
        .pd_mem_in    (pd_mem_in),

        .read_en_alu (read_en_alu),
        .read_en_b   (read_en_b),
        .read_en_mem (read_en_mem),

        .ps1_in_alu  (ps1_in_alu),
        .ps2_in_alu  (ps2_in_alu),
        .ps1_in_b    (ps1_in_b),
        .ps2_in_b    (ps2_in_b),
        .ps1_in_mem  (ps1_in_mem),
        .ps2_in_mem  (ps2_in_mem),

        .ps1_out_alu (ps1_out_alu),
        .ps2_out_alu (ps2_out_alu),
        .ps1_out_b   (ps1_out_b),
        .ps2_out_b   (ps2_out_b),
        .ps1_out_mem (ps1_out_mem),
        .ps2_out_mem (ps2_out_mem)
    );

    // 100 MHz clock
    initial clk = 0;
    always #5 clk = ~clk;

    // Simple check macro (guarded so we don't redefine)
`ifndef CHECK
`define CHECK(MSG, COND) \
    if (!(COND)) begin \
        $error("CHECK FAILED: %s (time=%0t)", MSG, $time); \
    end else begin \
        $display("CHECK OK   : %s (time=%0t)", MSG, $time); \
    end
`endif

    // Display helper
    task automatic show_all(input string label);
        $display("[%0t] %s", $time, label);
        $display("  ALU: ps1_out_alu = 0x%08h, ps2_out_alu = 0x%08h",
                 ps1_out_alu, ps2_out_alu);
        $display("  BR : ps1_out_b   = 0x%08h, ps2_out_b   = 0x%08h",
                 ps1_out_b, ps2_out_b);
        $display("  MEM: ps1_out_mem = 0x%08h, ps2_out_mem = 0x%08h",
                 ps1_out_mem, ps2_out_mem);
    endtask

    initial begin
        $display("Starting phys_reg_file_tb");

        // Reset
        reset        = 1'b1;
        write_alu_en = 1'b0;
        data_alu_in  = '0;
        pd_alu_in    = '0;

        write_b_en   = 1'b0;
        data_b_in    = '0;
        pd_b_in      = '0;

        write_mem_en = 1'b0;
        data_mem_in  = '0;
        pd_mem_in    = '0;

        read_en_alu  = 1'b0;
        read_en_b    = 1'b0;
        read_en_mem  = 1'b0;

        ps1_in_alu   = '0;
        ps2_in_alu   = '0;
        ps1_in_b     = '0;
        ps2_in_b     = '0;
        ps1_in_mem   = '0;
        ps2_in_mem   = '0;

        repeat (4) @(posedge clk);
        reset = 1'b0;
        @(posedge clk);

        // TEST 1: After reset, all zeros (read via ALU)
        ps1_in_alu  = 7'd5;
        ps2_in_alu  = 7'd10;
        read_en_alu = 1'b1;
        #1;
        show_all("TEST 1: After reset (expect zeros)");
        `CHECK("After reset: ps1_out_alu == 0", ps1_out_alu == 32'h0);
        `CHECK("After reset: ps2_out_alu == 0", ps2_out_alu == 32'h0);
        read_en_alu = 1'b0;

        // TEST 2: MEM write, ALU read
        @(posedge clk);
        pd_mem_in    = 7'd5;
        data_mem_in  = 32'hDEAD_BEEF;
        write_mem_en = 1'b1;
        @(posedge clk);   // write into PRF
        write_mem_en = 1'b0;

        ps1_in_alu  = 7'd5;
        ps2_in_alu  = 7'd0;
        read_en_alu = 1'b1;
        #1;
        show_all("TEST 2: MEM write to reg 5, ALU read");
        `CHECK("MEM->ALU: reg5 == 0xDEADBEEF", ps1_out_alu == 32'hDEAD_BEEF);
        `CHECK("MEM->ALU: ps2_out_alu still 0", ps2_out_alu == 32'h0);
        read_en_alu = 1'b0;

        // TEST 3: ALU write, ALU read
        @(posedge clk);
        pd_alu_in    = 7'd6;
        data_alu_in  = 32'hA5A5_1234;
        write_alu_en = 1'b1;
        @(posedge clk);
        write_alu_en = 1'b0;

        ps1_in_alu  = 7'd6;
        ps2_in_alu  = 7'd0;
        read_en_alu = 1'b1;
        #1;
        show_all("TEST 3: ALU write to reg 6, ALU read");
        `CHECK("ALU->ALU: reg6 == 0xA5A51234", ps1_out_alu == 32'hA5A5_1234);
        read_en_alu = 1'b0;

        // TEST 4: Read & write same cycle (ALU, same addr)
        // With your RTL (seq write + comb read), read sees NEW value.
        @(posedge clk);
        // Initialize reg 7 to something via MEM
        pd_mem_in    = 7'd7;
        data_mem_in  = 32'h1111_2222;
        write_mem_en = 1'b1;
        @(posedge clk);
        write_mem_en = 1'b0;

        // Now same cycle read_en_alu + write_alu_en to reg 7
        ps1_in_alu   = 7'd7;
        ps2_in_alu   = 7'd0;
        read_en_alu  = 1'b1;
        pd_alu_in    = 7'd7;
        data_alu_in  = 32'hCCCC_DDDD;
        write_alu_en = 1'b1;
        @(posedge clk);        // write happens, read sees new value
        #1;
        show_all("TEST 4: ALU read/write same cycle on reg 7");
        `CHECK("RAW same cycle: reg7 == 0xCCCCDDDD", ps1_out_alu == 32'hCCCC_DDDD);
        read_en_alu  = 1'b0;
        write_alu_en = 1'b0;

        // TEST 5: MEM write, read via all three ports
        @(posedge clk);
        pd_mem_in    = 7'd9;
        data_mem_in  = 32'h5566_7788;
        write_mem_en = 1'b1;
        @(posedge clk);
        write_mem_en = 1'b0;

        ps1_in_alu  = 7'd9;
        ps1_in_b    = 7'd9;
        ps1_in_mem  = 7'd9;
        ps2_in_alu  = 7'd0;
        ps2_in_b    = 7'd0;
        ps2_in_mem  = 7'd0;
        read_en_alu = 1'b1;
        read_en_b   = 1'b1;
        read_en_mem = 1'b1;
        #1;
        show_all("TEST 5: MEM write to reg 9, read via ALU/BR/MEM");
        `CHECK("MEM->ALU: reg9 == 0x55667788", ps1_out_alu == 32'h5566_7788);
        `CHECK("MEM->BR : reg9 == 0x55667788", ps1_out_b   == 32'h5566_7788);
        `CHECK("MEM->MEM: reg9 == 0x55667788", ps1_out_mem == 32'h5566_7788);
        read_en_alu = 1'b0;
        read_en_b   = 1'b0;
        read_en_mem = 1'b0;

        // TEST 6: ALU write, read via all three ports
        @(posedge clk);
        pd_alu_in    = 7'd12;
        data_alu_in  = 32'hCAFEBABE;
        write_alu_en = 1'b1;
        @(posedge clk);
        write_alu_en = 1'b0;

        ps1_in_alu  = 7'd12;
        ps1_in_b    = 7'd12;
        ps1_in_mem  = 7'd12;
        ps2_in_alu  = 7'd0;
        ps2_in_b    = 7'd0;
        ps2_in_mem  = 7'd0;
        read_en_alu = 1'b1;
        read_en_b   = 1'b1;
        read_en_mem = 1'b1;
        #1;
        show_all("TEST 6: ALU write to reg 12, read via ALU/BR/MEM");
        `CHECK("ALU->ALU: reg12 == 0xCAFEBABE", ps1_out_alu == 32'hCAFEBABE);
        `CHECK("ALU->BR : reg12 == 0xCAFEBABE", ps1_out_b   == 32'hCAFEBABE);
        `CHECK("ALU->MEM: reg12 == 0xCAFEBABE", ps1_out_mem == 32'hCAFEBABE);
        read_en_alu = 1'b0;
        read_en_b   = 1'b0;
        read_en_mem = 1'b0;

        $display("\nAll phys_reg_file tests completed.");
        $finish;
    end

endmodule
