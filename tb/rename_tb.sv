import types_pkg::*;

// 2. TESTBENCH
module rename_tb;

    // Signals
    logic clk;
    logic reset;

    // Upstream (Decode -> Rename)
    logic valid_in;
    decode_data data_in;
    logic ready_in;

    // From ROB (Commit/Retire)
    logic write_en;
    logic [6:0] rob_data_in;

    // Mispredict
    logic mispredict;

    // Downstream (Rename -> Dispatch/Issue)
    rename_data data_out;
    logic valid_out;
    logic ready_out;

    // DUT Instantiation
    rename dut (
        .clk(clk),
        .reset(reset),
        .valid_in(valid_in),
        .data_in(data_in),
        .ready_in(ready_in),
        .write_en(write_en),
        .rob_data_in(rob_data_in),
        .mispredict(mispredict),
        .data_out(data_out),
        .valid_out(valid_out),
        .ready_out(ready_out)
    );

    // Clock Generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // Safety Watchdog
    initial begin
        #30000; // Increased timeout for longer tests
        $display("\n[TB] ERROR: Simulation Timed Out! Potential deadlock or infinite loop.");
        $stop;
    end

    // Constants
    localparam logic [6:0] OP_BRANCH = 7'b1100011;
    localparam logic [6:0] OP_ALU    = 7'b0110011;

    // Tasks definition
    
    task sys_reset();
        $display("\n[TB] System Reset");
        reset = 1;
        valid_in = 0;
        data_in = '0;
        write_en = 0;
        rob_data_in = '0;
        mispredict = 0;
        ready_out = 0;
        repeat (5) @(posedge clk);
        #1; // Align away from edge
        reset = 0;
        @(posedge clk);
    endtask

    task send_inst(
        input logic [6:0] opcode,
        input logic [4:0] rd,
        input logic [4:0] rs1,
        input logic [4:0] rs2,
        output logic [6:0] allocated_pd
    );
        int timeout_ctr;
        timeout_ctr = 0;

        // Wait for DUT to be ready (Handle Empty Free List case)
        while (!ready_in) begin
            @(posedge clk);
            timeout_ctr++;
            if (timeout_ctr > 20) begin
                $error("[TB] ERROR: Time out waiting for ready_in. Free List likely Empty/Deadlocked!");
                $stop;
            end
        end
        
        // Drive Inputs slightly after clock edge to avoid races
        #1;
        valid_in = 1;
        data_in.pc     = 32'h1000;
        data_in.rs1    = rs1;
        data_in.rs2    = rs2;
        data_in.rd     = rd;
        data_in.imm    = 32'h0;
        data_in.ALUOp  = 3'b0;
        data_in.Opcode = opcode;
        data_in.fu     = 2'b0;
        data_in.func3  = 3'b0;
        data_in.func7  = 7'b0;
        ready_out = 1; 

        // Handshake
        @(posedge clk);
        #1;
        valid_in = 0;
        
        // Wait for output valid
        while(!valid_out) @(posedge clk);
        
        allocated_pd = data_out.pd_new;
        $display("[TB] Issued Inst: Op=%b Rd=%0d -> Alloc P%0d", opcode, rd, data_out.pd_new);
    endtask

    task retire_reg(input logic [6:0] preg);
        int ctr_before, ctr_after;
        logic internal_we;
        
        $display("[TB] RETIRING Physical Register: %0d", preg);
        
        // Peek internal state before
        ctr_before = dut.u_free_list.ctr; 
        
        @(posedge clk);
        // CRITICAL FIX: Add #1 delay to assert inputs AFTER clock edge
        // This prevents the DUT from sampling the old '0' values if it samples on the same edge.
        #1;
        write_en = 1;
        rob_data_in = preg;
        
        @(posedge clk);
        // Hold logic for one full cycle, then clear after next edge
        #1;
        write_en = 0;
        rob_data_in = '0;
        
        // Wait one cycle for logic to settle
        @(posedge clk); 
        #1; // Wait for update
        
        // Peek internal state after
        ctr_after = dut.u_free_list.ctr;
        // Also peek the internal wire to see if the AND gate logic worked
        internal_we = dut.fl_write_en;
        
        $display("[TB] DEBUG: Free List CTR before=%0d, after=%0d", ctr_before, ctr_after);
        
        if (ctr_after == ctr_before) begin
            $error("[TB] FAILURE: Retire did not increment free list counter! Logic ignored the write.");
            $display("[TB] DEBUG HINT: fl_write_en inside DUT was seen as: %b", internal_we);
        end else begin
            $display("[TB] SUCCESS: Retire accepted. Counter incremented.");
        end
    endtask

    // Main Test Procedure
    logic [6:0] captured_pd, p1_allocation;
    integer i;
    logic found_recycled;
    logic [6:0] last_speculative_pd;

    initial begin
        sys_reset();

        // TEST CASE 1: Basic Allocation
        $display("\n[TB] === Test Case 1: Basic Allocation ===");
        
        send_inst(OP_ALU, 5'd1, 5'd2, 5'd3, captured_pd);
        assert(captured_pd == 32) else $error("Expected P32, got P%0d", captured_pd);

        send_inst(OP_ALU, 5'd4, 5'd1, 5'd0, captured_pd);
        assert(captured_pd == 33) else $error("Expected P33, got P%0d", captured_pd);

        // TEST CASE 2: Register Recycling
        $display("\n[TB] === Test Case 2: Register Recycling (Full Loop) ===");
        
        // 1. Flush until we hit P50
        $display("[TB] Flushing Free List up to P50...");
        do begin
            send_inst(OP_ALU, 5'd5, 5'd0, 5'd0, captured_pd);
        end while (captured_pd != 50);
        
        $display("[TB] P50 allocated. Now let's retire P50 back to the free list.");
        
        // 2. Retire P50
        retire_reg(7'd50);

        // 3. Consume free list to force wrap-around
        $display("[TB] Consuming entire free list to force wrap-around...");
        
        found_recycled = 0;
        // The list size is ~96. We loop enough to cover it.
        for(i=0; i<110; i++) begin
            send_inst(OP_ALU, 5'd6, 5'd0, 5'd0, captured_pd);
            
            if (captured_pd == 50) begin
                found_recycled = 1;
                $display("[TB] SUCCESS: P50 was successfully recycled and re-allocated at iteration %0d!", i);
                break;
            end
        end

        if (!found_recycled) 
            $error("[TB] FAILURE: P50 never reappeared after retiring!");

        // RESET FOR NEXT TEST CASE
        // Since we exhausted the free list in Case 2, we must reset the system
        // to refill the free list for Case 3.
        sys_reset();

        // TEST CASE 3: Misprediction Recovery
        $display("\n[TB] Test Case 3: Branch Misprediction Recovery");

        // Setup R1 -> known mapping
        send_inst(OP_ALU, 5'd1, 5'd0, 5'd0, p1_allocation); 
        $display("[TB] Setup: R1 is mapped to P%0d", p1_allocation);
        
        // Branch (Checkpoint)
        send_inst(OP_BRANCH, 5'd0, 5'd1, 5'd2, captured_pd); 
        
        // Speculative pollution
        send_inst(OP_ALU, 5'd1, 5'd0, 5'd0, captured_pd); 
        last_speculative_pd = captured_pd;
        $display("[TB] Speculative: R1 re-mapped to P%0d", captured_pd);
        
        // Trigger Mispredict
        $display("[TB] TRIGGERING MISPREDIC");
        @(posedge clk);
        #1;
        mispredict = 1;
        @(posedge clk);
        #1;
        mispredict = 0;
        @(posedge clk);

        // Verify Recovery
        $display("[TB] Checking Post-Recovery Allocation...");
        send_inst(OP_ALU, 5'd11, 5'd0, 5'd0, captured_pd);
        
        // Heuristic check: Did the allocation pointer jump back?
        // If it jumped back, the new PD should be significantly smaller than the last speculative one
        // (wrapping logic aside).
        if (captured_pd > last_speculative_pd && captured_pd < last_speculative_pd + 5)
            $warning("[TB] Warning: Allocation continued forward.");
        else
            $display("[TB] Free List Pointer seems to have jumped back (Good).");

        $display("[TB] Checking Map Table Restoration for R1...");
        
        wait(ready_in);
        @(posedge clk);
        #1;
        valid_in = 1;
        data_in.pc     = 32'h1000;
        data_in.rs1    = 5'd1;
        data_in.rs2    = 5'd0;
        data_in.rd     = 5'd0; 
        data_in.imm    = 32'h0;
        data_in.ALUOp  = 3'b0;
        data_in.Opcode = OP_ALU;
        ready_out = 1;
        @(posedge clk);
        #1;
        valid_in = 0;
        
        while(!valid_out) @(posedge clk);
        
        if (data_out.ps1 == p1_allocation) 
            $display("[TB] SUCCESS: R1 map restored to P%0d", p1_allocation);
        else 
            $error("[TB] FAILURE: R1 map is P%0d, expected P%0d", data_out.ps1, p1_allocation);

        #100;
        $display("\n[TB] All Tests Complete ");
        $stop;
    end

endmodule