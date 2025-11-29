`timescale 1ns / 1ps

import types_pkg::*;

module dispatch_tb;

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

        // NOTE: name fixes here
        .ps_alu_in      (ps_in_alu),
        .ps_mem_in      (ps_in_mem),
        .ps_b_in        (ps_in_b),

        .ps_alu_ready   (ps_alu_ready),
        .ps_b_ready     (ps_b_ready),
        .ps_mem_ready   (ps_mem_ready),
        .fu_alu_ready   (fu_alu_ready),
        .fu_b_ready     (fu_b_ready),
        .fu_mem_ready   (fu_mem_ready),

        .rs_alu         (rs_alu),
        .rs_b           (rs_b),
        .rs_mem         (rs_mem),

        // name fixes: issued -> dispatched
        .alu_issued     (alu_dispatched),
        .b_issued       (b_dispatched),
        .mem_issued     (mem_dispatched)
    );

    // Clock Generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;  // 10 ns period
    end

    // -------- Helpers to peek ALU RS inside dispatch --------
    task automatic dump_rs_alu(input string tag);
        $display("ALU RS dump (%s) @ time %0t", tag, $time);
        for (int i = 0; i < 8; i++) begin
            $display("ALU_RS[%0d]: valid=%0b ready=%0b rob=%0d ps1=%0d ps2=%0d pd=%0d",
                     i,
                     uut.res_alu.rs_table[i].valid,
                     uut.res_alu.rs_table[i].ready,
                     uut.res_alu.rs_table[i].rob_index,
                     uut.res_alu.rs_table[i].ps1,
                     uut.res_alu.rs_table[i].ps2,
                     uut.res_alu.rs_table[i].pd);
        end
    endtask

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

    // Same as above, but with explicit ROB tag for mispredict tests
    task automatic dispatch_op_with_tag(
        input logic [1:0] fu_type,
        input logic [6:0] pd_dest,
        input logic [4:0] rob_tag
    );
        begin
            @(posedge clk);
            while (!ready_in) begin
                @(posedge clk);
            end

            rob_index_in    = rob_tag;

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

            @(posedge clk);

            $display("[%0t] DISPATCH_OP_TAG fu=%0b pd_new=%0d rob=%0d ready_in=%0b",
                     $time, fu_type, pd_dest, rob_index_in, ready_in);

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

    // One-cycle mispredict pulse: rob_index_in plays role of ROB tail
    task automatic do_mispredict(input logic [4:0] mis_tag,
                                 input logic [4:0] rob_tail);
        begin
            @(posedge clk);
            mispredict_tag = mis_tag;
            rob_index_in   = rob_tail;
            mispredict     = 1'b1;
            $display("[%0t] MISPREDICT tag=%0d tail=%0d", $time, mis_tag, rob_tail);
            @(posedge clk);
            mispredict     = 1'b0;
            @(posedge clk);
        end
    endtask

    // Main Test Sequence
    int valid_cnt10 = 0;
    bit seen14 = 0;
    bit seen15 = 0;
    int valid_cnt9 = 0;
    initial begin
        init_signals();
        reset_dut();
        
        $display("Starting Dispatch Module Test (no mispredict)");

        // CASE 0: FU = 2'b00 hits default case (no RS, no preg_rtable change)
        $display("Test 0: FU=2'b00 (default case, no RS)");
        dispatch_op(2'b00, 7'd4);

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
        dispatch_op(2'b01, 7'd21); // 3rd ALU
        dispatch_op(2'b01, 7'd22); // 4th ALU
        dispatch_op(2'b01, 7'd23); // 5th ALU
        dispatch_op(2'b01, 7'd24); // 6th ALU
        dispatch_op(2'b01, 7'd25); // 7th ALU
        dispatch_op(2'b01, 7'd26); // 8th ALU → RS should now be full
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

        // MISPREDICT TESTS
        $display("\n=== Starting Mispredict Tests ===");
        reset_dut();

        // ---- Test 9: simple mispredict flush (non-wrap) ----
        $display("Test 9: ALU mispredict flush (ROB=0,1,2,3; mispred=1, tail=4)");
        // Dispatch 4 ALU ops with explicit ROB tags
        dispatch_op_with_tag(2'b01, 7'd40, 5'd0);
        dispatch_op_with_tag(2'b01, 7'd41, 5'd1); // mispred here
        dispatch_op_with_tag(2'b01, 7'd42, 5'd2); // younger
        dispatch_op_with_tag(2'b01, 7'd43, 5'd3); // younger

        dump_rs_alu("before mispredict T9");

        // Mispredict at ROB=1, tail=4 => younger = {2,3}
        do_mispredict(5'd1, 5'd4);

        dump_rs_alu("after mispredict T9");

        valid_cnt9 = 0;
        for (int i = 0; i < 8; i++) begin
            if (uut.res_alu.rs_table[i].valid) begin
                valid_cnt9++;
                if (uut.res_alu.rs_table[i].rob_index == 5'd2 ||
                    uut.res_alu.rs_table[i].rob_index == 5'd3)
                    $error("T9 FAIL: younger ROB %0d survived in ALU_RS[%0d].",
                           uut.res_alu.rs_table[i].rob_index, i);
            end
        end
        if (valid_cnt9 != 2)
            $error("T9 FAIL: expected 2 valid entries (ROB 0,1) after flush, got %0d.", valid_cnt9);
        else
            $display("T9 PASS: younger ROB entries 2,3 flushed; 0,1 preserved.");

        // ---- Test 10: mispredict with ROB wrap-around ----
        $display("Test 10: ALU mispredict with ROB wrap-around (14,15,0,1; mispred=15, tail=2)");
        reset_dut();

        // Dispatch 4 ALU ops: ROB = 14, 15, 0, 1
        dispatch_op_with_tag(2'b01, 7'd50, 5'd14);
        dispatch_op_with_tag(2'b01, 7'd51, 5'd15); // mispred here
        dispatch_op_with_tag(2'b01, 7'd52, 5'd0);  // younger (wrapped)
        dispatch_op_with_tag(2'b01, 7'd53, 5'd1);  // younger (wrapped)

        dump_rs_alu("before mispredict T10");

        // Tail=2 means ROB contents [15+1=0 .. 1] are younger
        do_mispredict(5'd15, 5'd2);

        dump_rs_alu("after mispredict T10");

        valid_cnt10 = 0;
        seen14 = 0;
        seen15 = 0;
        for (int i = 0; i < 8; i++) begin
            if (uut.res_alu.rs_table[i].valid) begin
                valid_cnt10++;
                if (uut.res_alu.rs_table[i].rob_index == 5'd0 ||
                    uut.res_alu.rs_table[i].rob_index == 5'd1)
                    $error("T10 FAIL: younger wrapped ROB %0d survived in ALU_RS[%0d].",
                           uut.res_alu.rs_table[i].rob_index, i);
                if (uut.res_alu.rs_table[i].rob_index == 5'd14) seen14 = 1;
                if (uut.res_alu.rs_table[i].rob_index == 5'd15) seen15 = 1;
            end
        end
        if (!seen14 || !seen15)
            $error("T10 FAIL: older entries (14,15) should remain. seen14=%0b seen15=%0b", seen14, seen15);
        else
            $display("T10 PASS: wrapped younger (0,1) flushed; older (14,15) preserved.");

        $display("\nAll Tests Complete (including mispredict).");
        $finish;
    end

endmodule
