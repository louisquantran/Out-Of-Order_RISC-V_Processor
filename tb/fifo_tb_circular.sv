`timescale 1ns/1ps

module fifo_tb_circular;
    // DUT params / types 
    typedef logic [31:0] T_t;
    localparam int DEPTH = 8;

    // DUT I/O
    logic clk, reset;
    logic write_en, read_en;
    T_t  write_data, read_data;
    logic full, empty;

    // DUT 
    circular_buffer #(
        .T     (T_t),
        .DEPTH (DEPTH)
    ) dut (
        .clk        (clk),
        .reset      (reset),
        .write_en   (write_en),
        .write_data (write_data),
        .read_en    (read_en),
        .read_data  (read_data),
        .full       (full),
        .empty      (empty)
    );

    // Clock & Reset 
    initial clk = 0;
    always #5 clk = ~clk; // 100 MHz

    task automatic do_reset();
        begin
            reset      = 1;
            write_en   = 0;
            read_en    = 0;
            write_data = '0;
            repeat (3) @(posedge clk);
            reset = 0;
            @(posedge clk);
        end
    endtask

    // Scoreboard (models drop-oldest on full
    T_t model_q[$];

    task automatic push(input T_t d);
        begin : t_push
            if (full) begin
                $fatal(1, "TB push() called while FULL at time=%0t", $time);
            end
            write_data = d;
            write_en   = 1;
            read_en    = 0;
            @(posedge clk);
            write_en = 0;
            model_q.push_back(d);
        end
    endtask

    // Intentionally push while FULL (no read) -> DUT drops oldest then writes new
    task automatic push_overwrite(input T_t d);
        begin : t_push_ov
            if (!full || read_en) begin
                $fatal(1, "push_overwrite requires FULL and no read at time=%0t", $time);
            end
            write_data = d;
            write_en   = 1;
            read_en    = 0;
            // Model: drop oldest, then append
            if (model_q.size() > 0) void'(model_q.pop_front());
            model_q.push_back(d);
            @(posedge clk);
            write_en = 0;
        end
    endtask

    task automatic pop();
        T_t got;
        T_t exp;
        begin : t_pop
            if (empty) begin
                $fatal(1, "TB pop() called while EMPTY at time=%0t", $time);
            end
            write_en = 0;
            read_en  = 1;
            @(posedge clk);
            read_en = 0;
            got = read_data;
            if (model_q.size() == 0) begin
                $fatal(1, "Model underflow at time=%0t", $time);
            end
            exp = model_q.pop_front();
            if (got !== exp) begin
                $error("POP MISMATCH: exp=0x%08x got=0x%08x @%0t", exp, got, $time);
                $fatal(2);
            end
        end
    endtask

    // Simple mixed push+pop helper 
    task automatic push_pop(input T_t d);
        T_t got;
        T_t exp;
        begin : t_push_pop
            // Only do true simultaneous push+pop when not full and not empty
            if (!full && !empty) begin
                write_data = d;
                write_en   = 1;
                read_en    = 1;
                @(posedge clk);
                write_en = 0;
                read_en  = 0;

                // Model: enqueue then dequeue (head comes out)
                model_q.push_back(d);
                got = read_data;
                exp = model_q.pop_front();
                if (got !== exp) begin
                    $error("RW MISMATCH: exp=0x%08x got=0x%08x @%0t", exp, got, $time);
                    $fatal(2);
                end
            end else if (!full) begin
                push(d);
            end else if (!empty) begin
                pop();
            end
        end
    endtask

    // Simple coverage
    covergroup cg @(posedge clk);
        coverpoint full;
        coverpoint empty;
    endgroup
    cg cov = new;

    // Test Sequence
    int n = 0;
    initial begin
        $display("[%0t] Start", $time);
        do_reset();

        // 1) Fill to FULL
        while (!full) begin
            push(T_t'(32'h1111_0000 + n));
            n++;
        end
        $display("[%0t] Reached FULL with %0d items (model_q.size=%0d)",
                 $time, n, model_q.size());

        // 2) Intentional overwrite-on-full a few times (drop-oldest semantics)
        //    We won't use random; just do 3 overwrites.
        for (int k = 0; k < 3; k++) begin
            if (!full) $fatal(1, "Expected FULL before overwrite at time=%0t", $time);
            push_overwrite(T_t'(32'hAAAA_0000 + k));
            if (!full) $fatal(1, "Should remain FULL after overwrite at time=%0t", $time);
        end

        // 3) Drain all and check order
        while (!empty) begin
            pop();
        end
        $display("[%0t] Drained EMPTY (model_q.size=%0d)", $time, model_q.size());

        // 4) Wrap-around with mixed push/pop (small deterministic sequence)
        //    Fill half, then do a few push_pop operations to exercise pointers.
        for (int i = 0; i < DEPTH/2; i++) begin
            push(T_t'(32'h2222_0000 + i));
        end

        // A few push_pop operations
        for (int j = 0; j < 4; j++) begin
            push_pop(T_t'(32'h3333_0000 + j));
        end

        // Drain remaining
        while (!empty) begin
            pop();
        end

        // Final check
        if (model_q.size() != 0) begin
            $error("Model queue not empty at end: size=%0d", model_q.size());
            $fatal(4);
        end

        $display("[%0t] TEST PASSED (model_q.size=%0d)", $time, model_q.size());
        $finish;
    end

endmodule
