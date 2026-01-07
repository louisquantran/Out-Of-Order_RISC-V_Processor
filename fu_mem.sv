`timescale 1ns / 1ps
import types_pkg::*;

module fu_mem(
    input logic clk,
    input logic reset,

    // From ROB
    input logic retired,
    input logic [4:0] rob_head,

    input logic [4:0] curr_rob_tag,
    input logic mispredict,
    input logic [4:0] mispredict_tag,
    input logic [31:0] mispredict_pc,

    // From Dispatch
    input logic dispatch_valid,
    input logic [4:0] dispatch_rob_tag,
    input logic [31:0] lsq_dispatch_pc,

    // From RS and PRF
    input logic issued,
    input rs_data data_in,
    input logic [31:0] ps1_data,
    input logic [31:0] ps2_data,

    // Output data
    output mem_data data_out,
    output logic lsq_full_out,
    output logic [4:0] store_rob_tag,
    output logic store_lsq_done
);

    logic store_wb;
    lsq lsq_store_payload;
    lsq lsq_load_req;
    logic lsq_full;

    logic [31:0] fwd_data;
    logic [6:0] fwd_pd;
    logic [4:0] fwd_rob;
    logic fwd_valid;

    logic load_mem;
    logic load_ready;
    logic mem_valid;
    mem_data mem_out;

    assign lsq_full_out = lsq_full;

    lsq u_lsq (
        .clk(clk),
        .reset(reset),

        .dispatch_rob_tag(dispatch_rob_tag),
        .dispatch_valid(dispatch_valid),
        .dispatch_pc(lsq_dispatch_pc),

        .ps1_data(ps1_data),
        .imm_in(data_in.imm),
        .ps2_data(ps2_data),

        .mispredict(mispredict),
        .mispredict_pc(mispredict_pc),

        .issued(issued),
        .data_in(data_in),

        .retired(retired),
        .rob_head(rob_head),

        .store_wb(store_wb),
        .data_out(lsq_store_payload),

        .load_forward_data(fwd_data),
        .forward_load_pd(fwd_pd),
        .forward_rob_index(fwd_rob),
        .load_forward_valid(fwd_valid),

        .data_load(lsq_load_req),
        .load_mem(load_mem),

        .store_rob_tag(store_rob_tag),
        .store_lsq_done(store_lsq_done),
        .tag_full(lsq_full),

        .load_ready(load_ready),
        .mem_valid(mem_valid),
        .mem_rob_tag(mem_out.rob_fu_mem)
    );

    data_memory u_dmem (
        .clk(clk),
        .reset(reset),

        .store_wb(store_wb),
        .lsq_in(lsq_store_payload),

        .load_mem(load_mem),
        .lsq_load(lsq_load_req),

        .data_out(mem_out),
        .load_ready(load_ready),
        .valid(mem_valid)
    );

    always_comb begin
        data_out = '0;

        data_out.fu_mem_ready = 1'b1;
        data_out.fu_mem_done = 1'b0;

        if (issued && (data_in.Opcode == 7'b0100011) && lsq_full) begin
            data_out.fu_mem_ready = 1'b0;
        end

        if (!mispredict) begin
            if (fwd_valid) begin
                data_out.fu_mem_done = 1'b1;
                data_out.data = fwd_data;
                data_out.p_mem = fwd_pd;
                data_out.rob_fu_mem = fwd_rob;
            end else if (mem_valid) begin
                data_out.fu_mem_done = 1'b1;
                data_out.fu_mem_ready = 1'b1;

                data_out.data = mem_out.data;
                data_out.p_mem = mem_out.p_mem;
                data_out.rob_fu_mem = mem_out.rob_fu_mem;
            end
        end
    end

endmodule
