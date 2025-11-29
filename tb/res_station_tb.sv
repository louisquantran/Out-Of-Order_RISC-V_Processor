`timescale 1ns / 1ps
import types_pkg::*;

module res_station_tb;

    // Clock / reset
    logic clk;
    logic reset;

    // DUT inputs
    rename_data r_data_tb;

    logic       mispredict_tb;
    logic [4:0] mispredict_tag_tb;
    logic       fu_ready_tb;

    logic [4:0] rob_index_in_tb;
    logic       di_en_tb;

    logic preg_rtable_tb [0:127];   // operand-ready table (scoreboard)

    // DUT outputs
    logic   fu_issued_tb;
    logic   full_tb;
    rs_data data_out_tb;

    // Instantiate DUT (matches latest res_station)
    res_station dut (
        .clk          (clk),
        .reset        (reset),
        .r_data       (r_data_tb),
        .fu_ready     (fu_ready_tb),
        .rob_index_in (rob_index_in_tb),
        .mispredict   (mispredict_tb),
        .mispredict_tag(mispredict_tag_tb),
        .di_en        (di_en_tb),
        .preg_rtable  (preg_rtable_tb),
        .fu_issued    (fu_issued_tb),
        .full         (full_tb),
        .data_out     (data_out_tb)
    );

    // Clock generation: 100 MHz
    initial clk = 0;
    always #5 clk = ~clk;

    // Simple RS dump helper (hierarchical access to rs_table inside DUT)
    task automatic dump_rs(input string tag);
        $display("RS dump (%s) @ time %0t", tag, $time);
        for (int i = 0; i < 8; i++) begin
            $display("RS[%0d]: valid=%0b ready=%0b rob=%0d ps1=%0d ps1_r=%0b ps2=%0d ps2_r=%0b pd=%0d fu=%0d Opcode=%0b",
                     i,
                     dut.rs_table[i].valid,
                     dut.rs_table[i].ready,
                     dut.rs_table[i].rob_index,
                     dut.rs_table[i].ps1,
                     dut.rs_table[i].ps1_ready,
                     dut.rs_table[i].ps2,
                     dut.rs_table[i].ps2_ready,
                     dut.rs_table[i].pd,
                     dut.rs_table[i].fu,
                     dut.rs_table[i].Opcode);
        end
        $display("  full=%0b fu_issued=%0b", full_tb, fu_issued_tb);
    endtask

    // Apply reset
    task automatic apply_reset();
        begin
            reset             = 1'b1;
            mispredict_tb     = 1'b0;
            mispredict_tag_tb = '0;
            fu_ready_tb       = 1'b0;
            di_en_tb          = 1'b0;

            // Clear tables
            for (int i = 0; i < 128; i++) preg_rtable_tb[i] = 1'b0;

            // Clear r_data
            r_data_tb = '0;

            // Hold reset for a few cycles
            repeat (4) @(posedge clk);
            reset = 1'b0;
            @(posedge clk);
        end
    endtask

    // Dispatch one instruction into RS
    task automatic dispatch_instr(
        input [6:0] ps1,
        input [6:0] ps2,
        input [6:0] pd,
        input [4:0] rob_index,
        input       ps1_ready_init,
        input       ps2_ready_init,
        input [1:0] fu_id
    );
        begin
            // Set rename_data fields
            r_data_tb.ps1     = ps1;
            r_data_tb.ps2     = ps2;
            r_data_tb.pd_new  = pd;
            r_data_tb.imm     = 33'h0_DEAD_BEEF; // imm is 33 bits in typedef
            r_data_tb.pd_old  = 7'h00;           // not used here
            r_data_tb.rob_tag = rob_index;       // if used elsewhere

            // fields now stored inside rename_data
            r_data_tb.fu      = fu_id;
            r_data_tb.Opcode  = 7'b0110011;      // R-type example
            r_data_tb.func3   = 3'b000;
            r_data_tb.func7   = 7'b0000000;

            // ROB index seen by RS at dispatch time
            rob_index_in_tb   = rob_index;

            // Initialize operand-ready table (sampled at dispatch + later wakeup)
            preg_rtable_tb[ps1] = ps1_ready_init;
            preg_rtable_tb[ps2] = ps2_ready_init;

            di_en_tb = 1'b1;
            @(posedge clk);
            di_en_tb = 1'b0;
            @(posedge clk); // allow RS to update
        end
    endtask

    // "Broadcast" a ps: in this design we just mark it ready in preg_rtable
    task automatic broadcast_ps(input [6:0] ps);
        begin
            $display("CDB broadcast: mark preg_rtable[%0d]=1 at time %0t", ps, $time);
            preg_rtable_tb[ps] = 1'b1;
            @(posedge clk); // let RS see the new ready bit
        end
    endtask

    // FU requests an instruction (one-cycle pulse on fu_ready)
    task automatic mark_fu_ready();
        begin
            fu_ready_tb = 1'b1;
            @(posedge clk);
            fu_ready_tb = 1'b0;
            @(posedge clk);
        end
    endtask

    // Drive a one-cycle mispredict
    task automatic do_mispredict(input [4:0] mis_tag, input [4:0] rob_tail);
        begin
            mispredict_tag_tb = mis_tag;
            rob_index_in_tb   = rob_tail;  // treat as ROB tail pointer for flush range
            mispredict_tb     = 1'b1;
            @(posedge clk);
            mispredict_tb     = 1'b0;
            @(posedge clk);
        end
    endtask
    int valid_cnt4;
    int valid_cnt7;
    bit seen_14;
    bit seen_15;
    initial begin
        $display("Starting res_station_tb");
        
        // TEST 1: basic dispatch + wakeup
        apply_reset();
        dump_rs("after reset");

        $display("\nTEST 1: two instructions, second depends on ps=13");

        // I0: rob_index = 3, ps1=10, ps2=11, pd=20, operands ready
        dispatch_instr(7'd10, 7'd11, 7'd20, 5'd3, 1'b1, 1'b1, 2'd0);

        // I1: rob_index = 5, ps1=12, ps2=13, ps2 not ready yet
        dispatch_instr(7'd12, 7'd13, 7'd21, 5'd5, 1'b1, 1'b0, 2'd0);

        dump_rs("after two dispatches");

        // Now broadcast ps2 for I1 (ps = 13)
        $display("\nBroadcasting ps=13 to wake up I1");
        broadcast_ps(7'd13);
        dump_rs("after ps broadcast");

        // TEST 2: No issue when FU doesn't request (fu_ready=0)
        $display("\nTEST 2: no issue when FU does not request");
        // RS currently has entries; fu_ready stays 0.
        repeat (5) @(posedge clk);
        dump_rs("after 5 cycles with fu_ready=0");

        if (dut.rs_table[0].valid !== 1'b1 ||
            dut.rs_table[1].valid !== 1'b1)
            $error("TEST 2 FAILED: some entries were cleared even though fu_ready=0");
        else if (fu_issued_tb !== 1'b0)
            $error("TEST 2 FAILED: fu_issued should stay 0 when fu_ready=0.");
        else
            $display("TEST 2 OK: no entries cleared and no issue when fu_ready=0 (time=%0t)", $time);

        // TEST 3: Issue when only younger is ready
        $display("\nTEST 3: issue when only younger is ready");
        apply_reset();   // start clean

        // I0 (older): rob=3, ps2 not ready -> not issueable
        dispatch_instr(7'd10, 7'd30, 7'd40, 5'd3, 1'b1, 1'b0, 2'd0);

        // I1 (younger): rob=5, fully ready (operands)
        dispatch_instr(7'd12, 7'd13, 7'd41, 5'd5, 1'b1, 1'b1, 2'd0);

        dump_rs("before issue (older not ready, younger ready)");

        // FU requests an instruction
        mark_fu_ready();
        dump_rs("after one issue request (FU)");

        // Oldest READY is RS[1] (I1), RS[0] is not ready
        if (dut.rs_table[0].valid !== 1'b1)
            $error("TEST 3 FAILED: older non-ready entry (RS[0]) should remain valid.");
        else
            $display("TEST 3 OK: older non-ready entry still valid (time=%0t)", $time);

        if (dut.rs_table[1].valid !== 1'b0)
            $error("TEST 3 FAILED: younger ready entry (RS[1]) should have been issued and cleared.");
        else
            $display("TEST 3 OK: younger ready entry cleared on issue (time=%0t)", $time);

        // TEST 4: mispredict flushes only younger ROB entries
        $display("\n TEST 4: mispredict flush younger ROB entries");
        apply_reset();

        // Four entries with ROB indices 0,1,2,3
        dispatch_instr(7'd1,  7'd10, 7'd20, 5'd0, 1'b1, 1'b1, 2'd0);
        dispatch_instr(7'd2,  7'd11, 7'd21, 5'd1, 1'b1, 1'b1, 2'd0); // mispred branch (older)
        dispatch_instr(7'd3,  7'd12, 7'd22, 5'd2, 1'b1, 1'b1, 2'd0); // younger
        dispatch_instr(7'd4,  7'd13, 7'd23, 5'd3, 1'b1, 1'b1, 2'd0); // younger

        dump_rs("before mispredict (ROB=0,1,2,3)");

        // Mispredict at ROB=1, ROB tail = 4 => younger: 2,3
        do_mispredict(5'd1, 5'd4);
        dump_rs("after mispredict at ROB=1, tail=4");

        valid_cnt4 = 0;
        for (int i = 0; i < 8; i++) begin
            if (dut.rs_table[i].valid) begin
                valid_cnt4++;
                if (dut.rs_table[i].rob_index == 5'd2 ||
                    dut.rs_table[i].rob_index == 5'd3)
                    $error("TEST 4 FAILED: younger ROB entry %0d still valid in RS[%0d].",
                           dut.rs_table[i].rob_index, i);
            end
        end

        if (valid_cnt4 != 2)
            $error("TEST 4 FAILED: expected 2 valid entries (ROB 0,1) after flush, got %0d.", valid_cnt4);
        else
            $display("TEST 4 OK: younger ROB entries (2,3) flushed, older (0,1) preserved (time=%0t)", $time);

        // TEST 5: Full behavior (8 entries)
        $display("\nTEST 5: full behavior (8 entries)");
        apply_reset();

        // Fill all 8 entries (FU not requesting, so nothing issues)
        for (int i = 0; i < 8; i++) begin
            dispatch_instr(
                7'd10 + i,      // ps1
                7'd20 + i,      // ps2
                7'd30 + i,      // pd
                i[4:0],         // rob_index
                1'b1,           // ps1_ready_init
                1'b1,           // ps2_ready_init
                2'd0            // fu_id
            );
        end

        dump_rs("after filling 8 entries");

        if (full_tb !== 1'b1)
            $error("TEST 5 FAILED: full should be 1 when all 8 entries are valid.");
        else
            $display("TEST 5 OK: full asserted with 8 valid entries (time=%0t)", $time);

        // Attempt one more dispatch; should not corrupt existing entries
        $display("Attempting to dispatch when full...");
        dispatch_instr(7'd99, 7'd98, 7'd97, 5'd15,
                       1'b1, 1'b1, 2'd0);
        dump_rs("after extra dispatch attempt while full");

        // Simple check: first entry should still be whatever it was
        if (dut.rs_table[0].ps1 == 7'd10 &&
            dut.rs_table[0].pd  == 7'd30)
            $display("TEST 5 OK: entries not corrupted by extra dispatch while full (time=%0t)", $time);
        else
            $error("TEST 5 FAILED: RS[0] appears corrupted by dispatch when full.");

        // TEST 6: CDB wakeup with multiple dependents
        $display("\nTEST 6: CDB wakeup with multiple dependents");
        apply_reset();

        // ps1 initially NOT ready, ps2 ready
        preg_rtable_tb[30] = 1'b0;  // producer of ps1 not done yet
        preg_rtable_tb[40] = 1'b1;
        preg_rtable_tb[41] = 1'b1;
        preg_rtable_tb[42] = 1'b1;

        // Three entries depending on ps1=30
        dispatch_instr(7'd30, 7'd40, 7'd60, 5'd1, 1'b0, 1'b1, 2'd0);

        dispatch_instr(7'd30, 7'd41, 7'd61, 5'd2,
                       1'b0, 1'b1, 2'd0);

        dispatch_instr(7'd30, 7'd42, 7'd62, 5'd3,
                       1'b0, 1'b1, 2'd0);

        dump_rs("before CDB broadcast (all waiting on ps1=30)");

        // Now producer of ps1=30 completes and broadcasts on CDB
        $display("Broadcasting ps=30 (CDB) to wake all dependents");
        broadcast_ps(7'd30);
        dump_rs("after CDB broadcast ps=30");

        mark_fu_ready();
        dump_rs("after CDB broadcast + FU request");

        // Check: all entries with ps1=30 should have ps1_ready=1
        for (int i = 0; i < 3; i++) begin
            if (dut.rs_table[i].ps1 == 7'd30) begin
                if (!dut.rs_table[i].ps1_ready)
                    $error("TEST 6 FAILED: RS[%0d] did not set ps1_ready after CDB broadcast.", i);
            end
        end
        $display("TEST 6: CDB multiple dependents check done (time=%0t)", $time);

        // TEST 7: mispredict with ROB index wrap-around
        $display("\n=== TEST 7: mispredict with ROB index wrap-around ===");
        apply_reset();

        // Dispatch 4 entries with ROB=14,15,0,1
        dispatch_instr(7'd50, 7'd60, 7'd70, 5'd14, 1'b1, 1'b1, 2'd0);
        dispatch_instr(7'd51, 7'd61, 7'd71, 5'd15, 1'b1, 1'b1, 2'd0);
        dispatch_instr(7'd52, 7'd62, 7'd72, 5'd0,  1'b1, 1'b1, 2'd0);
        dispatch_instr(7'd53, 7'd63, 7'd73, 5'd1,  1'b1, 1'b1, 2'd0);

        dump_rs("before mispredict (ROB=14,15,0,1)");

        // ROB tail = 2 (next alloc after 0,1); mispredict at 15 => younger are 0,1.
        do_mispredict(5'd15, 5'd2);
        dump_rs("after mispredict at ROB=15, tail=2");

        valid_cnt7 = 0;
        seen_14 = 0;
        seen_15 = 0;
        for (int i = 0; i < 8; i++) begin
            if (dut.rs_table[i].valid) begin
                valid_cnt7++;
                if (dut.rs_table[i].rob_index == 5'd0 ||
                    dut.rs_table[i].rob_index == 5'd1)
                    $error("TEST 7 FAILED: younger wrapped ROB entry %0d still valid in RS[%0d].",
                           dut.rs_table[i].rob_index, i);
                if (dut.rs_table[i].rob_index == 5'd14) seen_14 = 1;
                if (dut.rs_table[i].rob_index == 5'd15) seen_15 = 1;
            end
        end

        if (!seen_14 || !seen_15)
            $error("TEST 7 FAILED: older entries (14,15) should be preserved. seen_14=%0b seen_15=%0b",
                   seen_14, seen_15);
        else
            $display("TEST 7 OK: wrap-around mispredict flushed 0,1 and preserved 14,15 (time=%0t)", $time);

        // Done
        #100;
        $display("All tests finished.");
        $finish;
    end

endmodule
