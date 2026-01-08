`timescale 1ns/1ps
import types_pkg::*;

module rob (
    input logic clk,
    input logic reset,

    // from Dispatch stage
    input logic write_en,
    input logic [6:0] pd_new_in,
    input logic [6:0] pd_old_in,
    input logic [31:0] pc_in,

    // from FUs
    input logic fu_alu_done,
    input logic fu_b_done,
    input logic fu_mem_done,
    input logic [4:0] rob_fu_alu,
    input logic [4:0] rob_fu_b,
    input logic [4:0] rob_fu_mem,
    input logic [4:0] store_rob_tag,
    input logic store_lsq_done,
    input logic br_mispredict,
    input logic [4:0] br_mispredict_tag,

    // Update free_list
    output logic [6:0] preg_old,
    output logic valid_retired,

    // Signal LSQ to put data into memory (RETIRING TAG!)
    output logic [4:0] head,

    // Global mispredict
    output logic mispredict,
    output logic [4:0] mispredict_tag,
    output logic [31:0] mispredict_pc,
    output logic [4:0] ptr,

    output logic full
);

    rob_data rob_table [0:15];

    logic [3:0] w_ptr, r_ptr;
    logic [4:0] ctr;

    logic [3:0] alu_tag, b_tag, mem_tag, st_tag, br_tag;

    assign alu_tag = rob_fu_alu[3:0];
    assign b_tag = rob_fu_b[3:0];
    assign mem_tag = rob_fu_mem[3:0];
    assign st_tag = store_rob_tag[3:0];
    assign br_tag = br_mispredict_tag[3:0];

    assign full = (ctr == 5'd16);
    assign ptr = {1'b0, w_ptr};

    assign mispredict = br_mispredict;
    assign mispredict_tag = br_mispredict_tag;
    assign mispredict_pc = rob_table[br_tag].pc;

    logic [4:0] head_q;
    assign head = head_q;

    logic do_write, do_retire;
    assign do_write = write_en && !full && !br_mispredict;

    assign do_retire = (ctr != 5'd0) &&
                       rob_table[r_ptr].valid &&
                       rob_table[r_ptr].complete &&
                       !br_mispredict;

    function automatic logic in_flush_region(
        input logic [3:0] idx,
        input logic [3:0] start,
        input logic [3:0] end_excl
    );
        if (start == end_excl) in_flush_region = 1'b0;
        else if (start < end_excl) in_flush_region = (idx >= start) && (idx < end_excl);
        else in_flush_region = (idx >= start) || (idx < end_excl);
    endfunction

    always_ff @(posedge clk) begin
        if (reset) begin
            w_ptr <= 4'd0;
            r_ptr <= 4'd0;
            ctr   <= 5'd0;

            preg_old       <= '0;
            valid_retired  <= 1'b0;
            head_q         <= 5'd0;

            for (int i = 0; i < 16; i++) rob_table[i] <= '0;

        end else begin
            valid_retired <= 1'b0;
            head_q <= {1'b0, r_ptr};

            if (fu_alu_done && rob_table[alu_tag].valid) rob_table[alu_tag].complete <= 1'b1;
            if (fu_b_done   && rob_table[b_tag].valid) rob_table[b_tag].complete   <= 1'b1;
            if (fu_mem_done && rob_table[mem_tag].valid) rob_table[mem_tag].complete <= 1'b1;
            if (store_lsq_done && rob_table[st_tag].valid) rob_table[st_tag].complete <= 1'b1;

            if (br_mispredict) begin
                logic [3:0] old_w;
                logic [3:0] re_ptr;
                logic [4:0] newcnt;

                old_w  = w_ptr;
                re_ptr = br_tag + 4'd1;

                if (re_ptr >= r_ptr) newcnt = {1'b0, re_ptr} - {1'b0, r_ptr};
                else newcnt = 5'd16 - {1'b0, r_ptr} + {1'b0, re_ptr};

                for (int j = 0; j < 16; j++) begin
                    if (in_flush_region(j[3:0], re_ptr, old_w)) begin
                        rob_table[j] <= '0;
                    end
                end

                w_ptr <= re_ptr;
                ctr <= newcnt;

            end else begin
                if (do_retire) begin
                    preg_old <= rob_table[r_ptr].pd_old;
                    valid_retired <= 1'b1;

                    rob_table[r_ptr] <= '0;
                    r_ptr <= r_ptr + 4'd1;
                end

                if (do_write) begin
                    rob_table[w_ptr].pd_new <= pd_new_in;
                    rob_table[w_ptr].pd_old <= pd_old_in;
                    rob_table[w_ptr].pc <= pc_in;
                    rob_table[w_ptr].complete <= 1'b0;
                    rob_table[w_ptr].valid <= 1'b1;
                    rob_table[w_ptr].rob_index <= w_ptr;

                    w_ptr <= w_ptr + 4'd1;
                end

                unique case ({do_retire, do_write})
                    2'b10: ctr <= ctr - 5'd1;
                    2'b01: ctr <= ctr + 5'd1;
                    default: ctr <= ctr;
                endcase
            end
        end
    end

endmodule
