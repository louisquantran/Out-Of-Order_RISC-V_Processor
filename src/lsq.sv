`timescale 1ns / 1ps
import types_pkg::*;

module lsq(
    input logic clk,
    input logic reset,

    // allocation from dispatch
    input logic [4:0] dispatch_rob_tag,
    input logic dispatch_valid,
    input logic [31:0] dispatch_pc,

    // operands for addr/data fill
    input logic [31:0] ps1_data,
    input logic [31:0] imm_in,
    input logic [31:0] ps2_data,

    // mispredict flush
    input logic mispredict,
    input logic [31:0] mispredict_pc,

    // from RS to fill LSQ entry fields
    input logic issued,
    input rs_data data_in,

    // retirement from ROB
    input logic retired,
    input logic [4:0] rob_head,  

    // store commit out
    output logic store_wb,
    output lsq data_out,

    // forwarding out 
    output logic [31:0] load_forward_data,
    output logic [6:0] forward_load_pd,
    output logic [4:0] forward_rob_index,
    output logic load_forward_valid,

    // memory load request out 
    output lsq data_load,
    output logic load_mem,

    output logic [4:0] store_rob_tag,
    output logic store_lsq_done,
    output logic tag_full,

    // handshake from memory
    input logic load_ready,
    input logic mem_valid,
    input logic [4:0] mem_rob_tag
);

    lsq lsq_arr [0:7];
    logic [2:0] w_ptr, r_ptr;

    logic ld_sent [0:7];

    logic load_inflight;
    logic [4:0] inflight_rob_tag;

    assign tag_full = (lsq_arr[0].valid)
                   && (lsq_arr[1].valid)
                   && (lsq_arr[2].valid)
                   && (lsq_arr[3].valid)
                   && (lsq_arr[4].valid)
                   && (lsq_arr[5].valid)
                   && (lsq_arr[6].valid)
                   && (lsq_arr[7].valid);

    function automatic logic [2:0] nxt(input logic [2:0] p);
        return (p == 3'd7) ? 3'd0 : (p + 3'd1);
    endfunction

    logic [2:0] tmp_wptr;
    logic stop;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            w_ptr <= '0;
            r_ptr <= '0;

            store_wb <= 1'b0;
            data_out <= '0;

            store_lsq_done <= 1'b0;
            store_rob_tag <= '0;

            load_inflight <= 1'b0;
            inflight_rob_tag <= '0;

            for (int i=0; i<8; i++) begin
                lsq_arr[i] <= '0;
                ld_sent[i] <= 1'b0;
            end
        end else begin
            store_wb <= 1'b0;
            data_out <= '0;
            store_lsq_done <= 1'b0;
            // clear inflight when memory returns
            if (mem_valid) begin
                if (load_inflight && (mem_rob_tag == inflight_rob_tag)) begin
                    load_inflight <= 1'b0;
                end
            end

            // allocate LSQ entry in-order
            if (dispatch_valid && !tag_full && !mispredict) begin
                lsq_arr[w_ptr] <= '0;
                lsq_arr[w_ptr].valid <= 1'b1;
                lsq_arr[w_ptr].pc <= dispatch_pc;
                lsq_arr[w_ptr].rob_tag <= dispatch_rob_tag;
                lsq_arr[w_ptr].valid_data <= 1'b0;
                ld_sent[w_ptr] <= 1'b0;
                w_ptr <= nxt(w_ptr);
            end

            // fill entry when RS issues (addr/data become known)
            if (issued && !mispredict) begin
                for (int i=0; i<8; i++) begin
                    if (lsq_arr[i].valid && !lsq_arr[i].valid_data &&
                        lsq_arr[i].rob_tag == data_in.rob_index) begin

                        lsq_arr[i].addr <= ps1_data + imm_in;
                        lsq_arr[i].pc <= data_in.pc;
                        lsq_arr[i].pd <= data_in.pd;
                        lsq_arr[i].func3 <= data_in.func3;
                        lsq_arr[i].valid_data <= 1'b1;

                        if (data_in.Opcode == 7'b0100011) begin
                            // store
                            lsq_arr[i].store <= 1'b1;
                            lsq_arr[i].ps2_data <= ps2_data;
                            lsq_arr[i].sw_sh_signal <= (data_in.func3 == 3'b001); // sh=1, sw=0

                            store_rob_tag <= data_in.rob_index;
                            store_lsq_done <= 1'b1;
                        end else begin
                            // load
                            lsq_arr[i].store <= 1'b0;
                        end
                    end
                end
            end

            // retire (pop from head)
            if (retired) begin
                if (lsq_arr[r_ptr].valid && lsq_arr[r_ptr].valid_data &&
                    (rob_head == lsq_arr[r_ptr].rob_tag)) begin

                    if (lsq_arr[r_ptr].store) begin
                        store_wb <= 1'b1;
                        data_out <= lsq_arr[r_ptr];
                    end

                    lsq_arr[r_ptr] <= '0;
                    ld_sent[r_ptr] <= 1'b0;
                    r_ptr <= nxt(r_ptr);
                end
            end

            // mispredict flush
            if (mispredict) begin
                load_inflight <= 1'b0;
                inflight_rob_tag <= '0;

                tmp_wptr = w_ptr;
                stop     = 1'b0;

                for (int k=0; k<8; k++) begin
                    logic [2:0] last;
                    last = tmp_wptr - 3'd1;

                    if (!stop) begin
                        if (lsq_arr[last].valid && (lsq_arr[last].pc >= mispredict_pc)) begin
                            lsq_arr[last] <= '0;
                            ld_sent[last] <= 1'b0;
                            tmp_wptr = last;
                        end else begin
                            stop = 1'b1;
                        end
                    end
                end

                w_ptr <= tmp_wptr;
            end
        end
    end

    // Oldest pending load selection and forwarding/hazard check
    logic        cand_found;
    logic [2:0]  cand_idx;

    logic        need_mem;
    logic        dep_block;
    logic        can_fwd;
    logic [31:0] fwd_val;

    logic        fire_fwd;
    logic        fire_mem;

    // mark ld_sent and also mark inflight on clock
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            // handled above
        end else begin
            if (!mispredict) begin
                if (fire_fwd || fire_mem) begin
                    ld_sent[cand_idx] <= 1'b1;
                end
                if (fire_mem) begin
                    load_inflight <= 1'b1;
                    inflight_rob_tag <= lsq_arr[cand_idx].rob_tag;
                end
            end
        end
    end

    logic [2:0] q;
    always_comb begin
        // defaults
        load_forward_data = '0;
        forward_load_pd = '0;
        forward_rob_index = '0;
        load_forward_valid = 1'b0;

        data_load = '0;
        load_mem = 1'b0;

        cand_found = 1'b0;
        cand_idx = '0;

        need_mem = 1'b0;
        dep_block = 1'b0;
        can_fwd = 1'b0;
        fwd_val = '0;

        fire_fwd = 1'b0;
        fire_mem = 1'b0;

        if (!mispredict) begin
            // find oldest ready load (from r_ptr) that hasn't been sent
            logic [2:0] p;
            p = r_ptr;

            for (int step=0; step<8; step++) begin
                if (lsq_arr[p].valid) begin
                    if (!lsq_arr[p].valid_data) begin
                        break; // stop at unknown older op
                    end

                    if (!lsq_arr[p].store && !ld_sent[p]) begin
                        cand_found = 1'b1;
                        cand_idx = p;
                        break;
                    end
                end
                p = nxt(p);
            end

            // if we found a candidate load, scan older stores
            if (cand_found) begin
                logic [31:0] ld_addr;
                logic [2:0] ld_func3;
                logic [1:0] ld_off;

                ld_addr = lsq_arr[cand_idx].addr;
                ld_func3 = lsq_arr[cand_idx].func3;
                ld_off = ld_addr[1:0];

                need_mem = 1'b1;
                dep_block = 1'b0;
                can_fwd = 1'b0;
                fwd_val = '0;

                q = r_ptr;

                for (int step2 = 0; step2 < 8; step2++) begin
                    if (q == cand_idx) break;

                    if (lsq_arr[q].valid && lsq_arr[q].valid_data && lsq_arr[q].store) begin
                        logic [31:0] st_addr;
                        logic [1:0] st_off;
                        logic st_is_sw;
                        logic [31:0] st_word_base;
                        logic [31:0] ld_word_base;

                        st_addr = lsq_arr[q].addr;
                        st_off = st_addr[1:0];
                        st_is_sw = (lsq_arr[q].sw_sh_signal == 1'b0);

                        st_word_base = {st_addr[31:2], 2'b00};
                        ld_word_base = {ld_addr[31:2], 2'b00};

                        if (st_word_base == ld_word_base) begin
                            if (ld_func3 == 3'b010) begin
                                if (st_is_sw && (st_off == 2'b00) && (ld_off == 2'b00)) begin
                                    can_fwd = 1'b1;
                                    need_mem = 1'b0;
                                    fwd_val = lsq_arr[q].ps2_data;
                                end else begin
                                    dep_block = 1'b1;
                                    need_mem = 1'b0;
                                end
                            end else if (ld_func3 == 3'b100) begin
                                if (st_is_sw) begin
                                    can_fwd = 1'b1;
                                    need_mem = 1'b0;
                                    unique case (ld_off)
                                        2'd0: fwd_val = {24'b0, lsq_arr[q].ps2_data[7:0]};
                                        2'd1: fwd_val = {24'b0, lsq_arr[q].ps2_data[15:8]};
                                        2'd2: fwd_val = {24'b0, lsq_arr[q].ps2_data[23:16]};
                                        2'd3: fwd_val = {24'b0, lsq_arr[q].ps2_data[31:24]};
                                    endcase
                                end else begin
                                    logic [1:0] base;
                                    base = st_addr[1] ? 2'd2 : 2'd0;

                                    if (ld_off == base) begin
                                        can_fwd = 1'b1;
                                        need_mem = 1'b0;
                                        fwd_val = {24'b0, lsq_arr[q].ps2_data[7:0]};
                                    end else if (ld_off == (base + 2'd1)) begin
                                        can_fwd = 1'b1;
                                        need_mem = 1'b0;
                                        fwd_val = {24'b0, lsq_arr[q].ps2_data[15:8]};
                                    end
                                end
                            end

                            if (dep_block) break;
                        end
                    end

                    q = nxt(q);
                end

                // Output data
                forward_load_pd = lsq_arr[cand_idx].pd;
                forward_rob_index = lsq_arr[cand_idx].rob_tag;

                if (dep_block) begin
                    load_forward_valid = 1'b0;
                    load_mem = 1'b0;
                end else if (can_fwd) begin
                    load_forward_valid = 1'b1;
                    load_forward_data = fwd_val;
                    fire_fwd = 1'b1;
                end else if (need_mem && load_ready && !load_inflight) begin
                    load_mem = 1'b1;
                    data_load = lsq_arr[cand_idx];
                    fire_mem = 1'b1;
                end
            end
        end
    end

endmodule
