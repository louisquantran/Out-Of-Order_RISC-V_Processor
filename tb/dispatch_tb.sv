`timescale 1ns / 1ps

import types_pkg::*;

module tb_dispatch;

    // Signals
    logic clk;
    logic reset;
    
    // Upstream (Rename)
    logic       valid_in;
    rename_data data_in;
    logic       ready_in;
    
    // ROB
    logic       rob_full;
    logic [4:0] rob_index_in;
    
    // FU / CDB Broadcast
    logic       mispredict;
    logic [4:0] mispredict_tag;
    
    logic [6:0] ps_in_alu;
    logic       ps_alu_ready;
    logic       fu_alu_ready;
    
    logic [6:0] ps_in_b;
    logic       ps_b_ready;
    logic       fu_b_ready;
    
    logic [6:0] ps_in_mem;
    logic       ps_mem_ready;
    logic       fu_mem_ready;
    
    // Outputs
    rs_data rs_alu, rs_b, rs_mem;
    logic   alu_dispatched, b_dispatched, mem_dispatched;

    // DUT
    dispatch uut (
        .clk            (clk),
        .reset          (reset),
        .valid_in       (valid_in),
        .data_in        (data_in),
        .ready_in       (ready_in),
        .rob_full       (rob_full),
        .rob_index_in   (rob_index_in),
        .mispredict     (mispredict),
        .mispredict_tag (mispredict_tag),
        .ps_in_alu      (ps_in_alu),
        .ps_in_b        (ps_in_b),
        .ps_in_mem      (ps_in_mem),
        .ps_alu_ready   (ps_alu_ready),
        .ps_b_ready     (ps_b_ready),
        .ps_mem_ready   (ps_mem_ready),
        .fu_alu_ready   (fu_alu_ready),
        .fu_b_ready     (fu_b_ready),
        .fu_mem_ready   (fu_mem_ready),
        .rs_alu         (rs_alu),
        .rs_b           (rs_b),
        .rs_mem         (rs_mem),
        .alu_dispatched (alu_dispatched),
        .b_dispatched   (b_dispatched),
        .mem_dispatched (mem_dispatched)
    );

    // Clock Generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;  // 10 ns period
    end

    // Tasks

    task init_signals();
        valid_in       = 0;
        data_in        = '0;
        rob_full       = 0;
        rob_index_in   = 5'd0;

        mispredict     = 0;
        mispredict_tag = 5'd0;
        
        ps_in_alu      = '0;
        ps_in_b        = '0;
        ps_in_mem      = '0;

        ps_alu_ready   = 0;
        ps_b_ready     = 0;
        ps_mem_ready   = 0;
        
        fu_alu_ready   = 0; 
        fu_b_ready     = 0;
        fu_mem_ready   = 0;
    endtask

    task reset_dut();
        reset = 1;
        @(posedge clk);
        @(posedge clk);
        reset = 0;
        @(posedge clk);
    endtask

    // Safe ready/valid: hold data stable through the accept edge
    task automatic dispatch_op(
        input logic [1:0] fu_type,
        input logic [6:0] pd_dest
    );
        begin
            // Wait until ready_in is high
            @(posedge clk);
            while (!ready_in) begin
                @(posedge clk);
            end

            // Drive struct while ready is high *before* the next edge
            data_in         = '0;
            data_in.fu      = fu_type;
            data_in.pd_new  = pd_dest;
            data_in.ps1     = 7'd10;
            data_in.ps2     = 7'd11;
            data_in.Opcode  = 7'b0110011;
            data_in.func3   = 3'b000;
            data_in.func7   = 7'b0000000;
            data_in.imm     = '0;

            valid_in        = 1'b1;

            // On this posedge, valid & ready are both 1 → accept
            @(posedge clk);

            rob_index_in    = rob_index_in + 5'd1;
            $display("[%0t] DISPATCH_OP fu=%0b pd_new=%0d rob=%0d ready_in=%0b",
                     $time, fu_type, pd_dest, rob_index_in, ready_in);

            // Now drop valid and clear data on the *next* cycle
            valid_in        = 1'b0;
            data_in         = '0;
            @(posedge clk);
        end
    endtask

    // CDB broadcast: mark a physical register as ready
    task automatic broadcast_ps(
        input logic [6:0] preg,
        input bit to_alu,
        input bit to_b,
        input bit to_mem
    );
        begin
            @(posedge clk);
            ps_in_alu    = to_alu ? preg : '0;
            ps_in_b      = to_b   ? preg : '0;
            ps_in_mem    = to_mem ? preg : '0;

            ps_alu_ready = to_alu;
            ps_b_ready   = to_b;
            ps_mem_ready = to_mem;

            $display("[%0t] BROADCAST preg %0d (alu=%0b, br=%0b, mem=%0b)",
                     $time, preg, to_alu, to_b, to_mem);

            @(posedge clk);
            ps_alu_ready = 0;
            ps_b_ready   = 0;
            ps_mem_ready = 0;
            ps_in_alu    = '0;
            ps_in_b      = '0;
            ps_in_mem    = '0;
        end
    endtask

    // Main Test Sequence
    initial begin
        init_signals();
        reset_dut();
        
        $display("=== Starting Dispatch Module Test (no mispredict) ===");

        // CASE 0: FU = 2'b00 hits default case (no RS, no preg_rtable change)
        $display("Test 0: FU=2'b00 (default case, no RS)");
        dispatch_op(2'b00, 7'd4);
        // Optional: assert(uut.preg_rtable[4] == 1'b1);

        // CASE 1: Dispatch to ALU (FU = 01) → PR[5] busy
        $display("Test 1: Dispatch ALU Operation");
        dispatch_op(2'b01, 7'd5);
        @(posedge clk);
        if (uut.preg_rtable[5] == 1'b0) 
            $display("PASS: PR[5] marked busy (0) in table.");
        else 
            $error("FAIL: PR[5] should be busy.");

        // CASE 2: Dispatch to BRANCH (FU = 10) - no dest register
        $display("Test 2: Dispatch Branch Operation (no dest)");
        dispatch_op(2'b10, 7'd0);   // branch doesn't have pd_new
        @(posedge clk);
        // No preg_rtable busy check here for branch - architecturally no dest.

        // CASE 3: Dispatch to MEMORY (FU = 11) → treat as load, PR[7] busy
        $display("Test 3: Dispatch Memory Operation (load-like, has dest)");
        dispatch_op(2'b11, 7'd7);
        @(posedge clk);
        if (uut.preg_rtable[7] == 1'b0) 
            $display("PASS: PR[7] marked busy (0) in table (MEM dest).");
        else 
            $error("FAIL: PR[7] should be busy for MEM dest.");

        // CASE 4: ROB Full Stalling
        $display("Test 4: ROB Full Backpressure");
        @(posedge clk);
        rob_full = 1;
        @(posedge clk);
        if (ready_in == 0) 
            $display("PASS: ready_in dropped when ROB is full.");
        else 
            $error("FAIL: ready_in should be low when ROB is full.");
        rob_full = 0;
        @(posedge clk);

        // CASE 5: Reservation Station Full (ALU RS)
        $display("Test 5: RS ALU Fill and Stalling (capacity exercise)");
        // ALU RS depth = 8. We already inserted 1 ALU op in Test 1 (pd=5).
        // Add 7 more ALU instructions to reach full = 8 entries total.
        dispatch_op(2'b01, 7'd20); // 2nd ALU
        if (uut.preg_rtable[20] == 1'b0) 
            $display("PASS: PR[20] marked busy (0) in table.");
        else 
            $error("FAIL: PR[20] should be busy.");
        dispatch_op(2'b01, 7'd21); // 3rd ALU
        if (uut.preg_rtable[20] == 1'b0) 
            $display("PASS: PR[21] marked busy (0) in table.");
        else 
            $error("FAIL: PR[21] should be busy.");
        dispatch_op(2'b01, 7'd22); // 4th ALU
        if (uut.preg_rtable[22] == 1'b0) 
            $display("PASS: PR[22] marked busy (0) in table.");
        else 
            $error("FAIL: PR[22] should be busy.");
        dispatch_op(2'b01, 7'd23); // 5th ALU
        if (uut.preg_rtable[23] == 1'b0) 
            $display("PASS: PR[23] marked busy (0) in table.");
        else 
            $error("FAIL: PR[23] should be busy.");
        dispatch_op(2'b01, 7'd24); // 6th ALU
        if (uut.preg_rtable[24] == 1'b0) 
            $display("PASS: PR[24] marked busy (0) in table.");
        else 
            $error("FAIL: PR[24] should be busy.");
        dispatch_op(2'b01, 7'd25); // 7th ALU
        if (uut.preg_rtable[25] == 1'b0) 
            $display("PASS: PR[25] marked busy (0) in table.");
        else 
            $error("FAIL: PR[25] should be busy.");
        dispatch_op(2'b01, 7'd26); // 8th ALU → RS should now be full
        if (uut.preg_rtable[26] == 1'b0) 
            $display("PASS: PR[26] marked busy (0) in table.");
        else 
            $error("FAIL: PR[26] should be busy.");
        @(posedge clk);
        if (uut.rs_alu_full == 1'b1)
            $display("PASS: ALU RS detected full after 8 ALU inserts.");
        else
            $error("FAIL: ALU RS should be full after 8 ALU inserts.");

        // CASE 6: CDB Broadcast (Writeback) Logic
        $display("Test 6: CDB Broadcast (Writeback) Logic");
        // Mark ALU PR[5] ready, and MEM PR[7] ready
        broadcast_ps(7'd5, 1'b1, 1'b0, 1'b0); // ALU broadcast
        broadcast_ps(7'd7, 1'b0, 1'b0, 1'b1); // MEM broadcast

        @(posedge clk);
        if (uut.preg_rtable[5] == 1'b1) 
            $display("PASS: PR[5] set to ready (1) after ALU broadcast.");
        else 
            $error("FAIL: PR[5] should be ready.");

        if (uut.preg_rtable[7] == 1'b1) 
            $display("PASS: PR[7] set to ready (1) after MEM broadcast.");
        else 
            $error("FAIL: PR[7] should be ready.");

        // CASE 7: Simultaneous Dispatch and Broadcast on same tag
        $display("Test 7: Simultaneous Dispatch & Broadcast on same tag");
        @(posedge clk);
        data_in         = '0;
        data_in.fu      = 2'b01;
        data_in.pd_new  = 7'd30;
        data_in.ps1     = 7'd12;
        data_in.ps2     = 7'd13;
        data_in.Opcode  = 7'b0110011;
        data_in.func3   = 3'b000;
        data_in.func7   = 7'b0000000;
        data_in.imm     = '0;

        valid_in        = 1'b1;
        ps_in_alu       = 7'd30;
        ps_alu_ready    = 1'b1;

        @(posedge clk);
        valid_in        = 1'b0;
        ps_alu_ready    = 1'b0;
        data_in         = '0;
        ps_in_alu       = '0;
        rob_index_in    = rob_index_in + 5'd1;

        @(posedge clk);
        if (uut.preg_rtable[30] == 1'b1)
            $display("PASS: PR[30] ready after simultaneous alloc+broadcast (broadcast wins).");
        else
            $display("INFO: PR[30] busy (0) after simultaneous alloc+broadcast (alloc wins).");

        // CASE 8: Execution Unit Ready (Issue from RS, drain ALU RS)
        $display("Test 8: Execution Unit Ready (Issue from RS)");
        fu_alu_ready = 1'b1;   // ALU FU now ready to pull from RS
        repeat (10) @(posedge clk);
        fu_alu_ready = 1'b0;
        @(posedge clk);

        if (uut.rs_alu_full == 1'b0)
            $display("PASS: ALU RS no longer full after draining.");
        else
            $error("FAIL: ALU RS should have drained.");

        $display("All Tests Complete (no mispredict exercised)");
        $finish;
    end

endmodule
