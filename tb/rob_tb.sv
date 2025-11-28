`timescale 1ns/1ps
import types_pkg::*;

module rob_tb;

    // DUT I/O
    logic        clk, reset;
    logic        write_en;
    logic [6:0]  pd_new_in, pd_old_in;
    logic [31:0] pc_in;

    // FU completion signals
    logic        fu_alu_done;
    logic        fu_b_done;
    logic        fu_mem_done;
    logic [4:0]  rob_fu_alu;
    logic [4:0]  rob_fu_b;
    logic [4:0]  rob_fu_mem;

    logic        mispredict;
    logic [4:0]  mispredict_tag;

    // DUT outputs
    logic [6:0]  preg_old;
    logic        valid_retired;
    logic        full;
    logic [4:0]  ptr;          // write pointer from DUT (tail index)

    localparam int CLK_PERIOD = 10;

    // Clock
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // Helper: increment mod 16
    function automatic [4:0] inc16(input [4:0] x);
        return (x == 5'd15) ? 5'd0 : (x + 5'd1);
    endfunction

    // TB mirrors of head/tail so we don't rely on DUT internals for protocol
    logic [4:0] tb_wptr;  // next tag to allocate (tail mirror)
    logic [4:0] tb_rptr;  // next tag expected to retire (head mirror)

    // Occupancy calculation
    function automatic int occ(input [4:0] r, input [4:0] w);
        return (w >= r) ? (w - r) : (5'd16 - r + w);
    endfunction

    // Reset
    task automatic apply_reset;
        begin
            reset         = 1;
            write_en      = 0;
            pd_new_in     = '0;
            pd_old_in     = '0;
            pc_in         = '0;

            fu_alu_done   = 0;
            fu_b_done     = 0;
            fu_mem_done   = 0;
            rob_fu_alu    = '0;
            rob_fu_b      = '0;
            rob_fu_mem    = '0;

            mispredict    = 0;
            mispredict_tag= '0;

            tb_wptr       = '0;
            tb_rptr       = '0;

            repeat (3) @(posedge clk);
            reset = 0;
            @(posedge clk);

            if (occ(tb_rptr, tb_wptr) != 0 || full)
                $fatal(1, "[RESET] expected empty ROB, got occ=%0d full=%0b",
                       occ(tb_rptr, tb_wptr), full);

            $display("[%0t] Reset done.", $time);
        end
    endtask

    // Allocate: write into ROB tail
    task automatic alloc(output [4:0] tag_o,
                         input  [6:0] pd_new,
                         input  [6:0] pd_old,
                         input  [31:0] pc);
        begin
            if (full)
                $fatal(1, "[ALLOC] ROB full unexpectedly (occ=%0d)",
                       occ(tb_rptr, tb_wptr));

            tag_o     = tb_wptr;
            pd_new_in = pd_new;
            pd_old_in = pd_old;
            pc_in     = pc;
            write_en  = 1;

            @(posedge clk);           // allocate on this edge
            write_en  = 0;
            tb_wptr   = inc16(tb_wptr);

            $display("[%0t] ALLOC tag=%0d pc=0x%08h (TB occ-> %0d)",
                     $time, tag_o, pc, occ(tb_rptr, tb_wptr));

            @(posedge clk);           // cadence
        end
    endtask

    // Mark ROB entry complete via ALU FU
    task automatic complete_tag(input [4:0] tag);
        begin
            rob_fu_alu   = tag;
            fu_alu_done  = 1;
            @(posedge clk);
            fu_alu_done  = 0;
            rob_fu_alu   = '0;
            $display("[%0t] COMPLETE tag=%0d", $time, tag);
        end
    endtask

    // Expect no retire next cycle
    task automatic expect_no_retire_next;
        begin
            @(posedge clk);
            if (valid_retired)
                $fatal(1, "[NO_RET] Retired unexpectedly (head incomplete)");
        end
    endtask

    // Expect a specific retire (head only)
    task automatic expect_retire(input [4:0] exp_tag);
        int waitcycles = 0;
        begin
            // Sanity: TB model's head should match expected tag
            if (tb_rptr !== exp_tag) begin
                $fatal(1,
                    "[RETIRE] TB head (%0d) != exp_tag (%0d) before retire",
                    tb_rptr, exp_tag);
            end

            while (!valid_retired) begin
                @(posedge clk);
                if (waitcycles++ > 20) begin
                    $fatal(1,
                      "[RETIRE] Timeout waiting for tag %0d (TB head=%0d, TB tail=%0d, occ=%0d)",
                      exp_tag, tb_rptr, tb_wptr, occ(tb_rptr, tb_wptr));
                end
            end

            $display("[%0t] RETIRE tag=%0d", $time, tb_rptr);

            // TB head mirror advances on a retire
            tb_rptr = inc16(tb_rptr);
            @(posedge clk); // consume pulse
        end
    endtask

    // Mispredict (flush younger-than-branch)
    task automatic do_mispredict(input [4:0] tag);
        begin
            $display("[%0t] ---- MISPREDICT at tag=%0d ----", $time, tag);
            mispredict_tag = tag;
            mispredict     = 1;
            @(posedge clk);      // DUT recovery
            mispredict     = 0;
            mispredict_tag = '0;
            @(posedge clk);

            // TB tail mirror becomes branch+1
            tb_wptr = inc16(tag);
        end
    endtask

    // DUT
    rob dut (
        .clk,
        .reset,

        // from rename
        .write_en,
        .pd_new_in,
        .pd_old_in,
        .pc_in,

        // from FUs
        .fu_alu_done,
        .fu_b_done,
        .fu_mem_done,
        .rob_fu_alu,
        .rob_fu_b,
        .rob_fu_mem,
        .mispredict,
        .mispredict_tag,

        // outputs
        .preg_old,
        .valid_retired,
        .full,
        .ptr
    );

    // Sanity checks on internal ctr
    always @(posedge clk) if (!reset) begin
        assert (dut.ctr <= 16) else $fatal(1, "ctr overflow: %0d", dut.ctr);
        assert (full == (dut.ctr == 16))
            else $fatal(1, "full mismatch: full=%0b ctr=%0d",
                        full, dut.ctr);
    end

    // ---------------- Tests ----------------
    initial begin
        logic [4:0] t0, t1, t2, t3, t4, t5, newtag;
        int  need_to_full;
        int  push_to_nearfull;

        apply_reset();

        // TEST 1: OoO completion, in-order retirement
        $display("TEST 1: OoO completion, in-order retirement");

        alloc(t0, 7'h20, 7'h10, 32'h0000_1000); // tag 0
        alloc(t1, 7'h21, 7'h11, 32'h0000_1004); // tag 1
        alloc(t2, 7'h22, 7'h12, 32'h0000_1008); // tag 2

        // Complete out-of-order: t1 then t0
        complete_tag(t1);
        expect_no_retire_next;

        complete_tag(t0);
        expect_retire(t0);
        expect_retire(t1);

        // Finally complete and retire t2
        complete_tag(t2);
        expect_retire(t2);

        if (occ(tb_rptr, tb_wptr) != 0)
            $fatal(1, "[TEST1] ROB not empty at end (occ=%0d)",
                   occ(tb_rptr, tb_wptr));

        $display("------------------------------------------------------------------");

        // TEST 2: Mispredict flush (younger-than-branch squashed)
        $display("TEST 2: Mispredict flush");

        alloc(t3, 7'h33, 7'h23, 32'h0000_2000); // branch
        alloc(t4, 7'h34, 7'h24, 32'h0000_2004); // younger
        alloc(t5, 7'h35, 7'h25, 32'h0000_2008); // younger

        // Complete a younger entry that will be flushed
        complete_tag(t5);
        expect_no_retire_next;

        // Flush younger than branch
        do_mispredict(t3);

        // Only the branch remains live at head; complete & retire it
        complete_tag(t3);
        expect_retire(t3);

        // First new alloc should reuse tag = t3+1
        alloc(newtag, 7'h44, 7'h34, 32'h0000_200C);
        assert (newtag == inc16(t3))
            else $fatal(1,
                "[TEST2] expected new alloc at tag=%0d, got=%0d",
                inc16(t3), newtag);

        $display("------------------------------------------------------------------");

        // TEST 3: Wrap-around / full behavior
        $display("TEST 3: Wrap-around / full behavior");

        // Fill up to near full based on remaining occupancy
        need_to_full     = 16 - occ(tb_rptr, tb_wptr);
        push_to_nearfull = need_to_full - 1;

        for (int i = 0; i < push_to_nearfull; i++) begin
            alloc(newtag, 7'h50 + i, 7'h60, 32'h0000_3000 + i);
        end

        // One more to go full
        alloc(newtag, 7'h5F, 7'h6F, 32'h0000_3FFF);
        assert (full)
            else $fatal(1,
                "[TEST3] ROB should be full (occ=%0d)",
                occ(tb_rptr, tb_wptr));

        // Retire two heads
        complete_tag(tb_rptr);
        expect_retire(tb_rptr);

        complete_tag(tb_rptr);
        expect_retire(tb_rptr);

        assert (!full)
            else $fatal(1,
                "[TEST3] still full after two retires (occ=%0d)",
                occ(tb_rptr, tb_wptr));

        // Allocate again - should succeed now
        alloc(newtag, 7'h70, 7'h60, 32'h0000_4000);

        $display("------------------------------------------------------------------");
        $display("[PASS] All ROB tests completed.");
        $finish;
    end

endmodule
