`timescale 1ns / 1ps
import types_pkg::*;

module dispatch(
    input logic clk,
    input logic reset,

    // Upstream
    input logic valid_in,
    input rename_data data_in,
    output logic ready_in,

    // LSQ backpressure
    input logic lsq_full_in,

    // LSQ allocation outputs
    output logic lsq_alloc_valid_out,
    output logic [4:0] lsq_dispatch_rob_tag,
    output logic [31:0] lsq_dispatch_pc,

    // Data from ROB
    input logic rob_full,
    input logic [4:0] rob_index_in,
    input logic mispredict,
    input logic [4:0] mispredict_tag,

    // Data from FU (PRF wakeups)
    input logic [6:0] ps_alu_in,
    input logic [6:0] ps_mem_in,
    input logic [6:0] ps_b_in,
    input logic ps_b_ready,
    input logic ps_alu_ready,
    input logic ps_mem_ready,
    input logic fu_alu_ready,
    input logic fu_b_ready,
    input logic fu_mem_ready,

    // Output data from 3 RS
    output rs_data rs_alu,
    output rs_data rs_b,
    output rs_data rs_mem,

    output logic alu_issued,
    output logic b_issued,
    output logic mem_issued
);
    logic dispatch_handshake;
    assign dispatch_handshake = valid_in && ready_in;

    logic is_loadstore;
    assign is_loadstore = (data_in.Opcode == 7'b0000011) || (data_in.Opcode == 7'b0100011);

    // only allocate LSQ on load/store and when actually accepted
    assign lsq_alloc_valid_out = is_loadstore && dispatch_handshake && !mispredict;

    always_comb begin
        if (lsq_alloc_valid_out) begin
            lsq_dispatch_rob_tag = data_in.rob_tag;
            lsq_dispatch_pc = data_in.pc;
        end else begin
            lsq_dispatch_rob_tag = '0;
            lsq_dispatch_pc = '0;
        end
    end

    logic rs_alu_full, rs_b_full, rs_mem_full;
    logic di_en_alu, di_en_b, di_en_mem;

    rename_data data_q;
    assign data_q = data_in;

    always_comb begin
        // defaults
        ready_in = 1'b0;
        di_en_alu = 1'b0;
        di_en_b = 1'b0;
        di_en_mem = 1'b0;

        if (mispredict) begin
            ready_in = 1'b1;  
        end else begin
            unique case (data_q.fu)
                2'b01: begin // alu
                    ready_in = !rob_full && !rs_alu_full;
                    if (ready_in && valid_in) di_en_alu = 1'b1;
                end

                2'b10: begin // br
                    ready_in = !rob_full && !rs_b_full;
                    if (ready_in && valid_in) di_en_b = 1'b1;
                end

                2'b11: begin // mem
                    ready_in = !rob_full && !rs_mem_full && !lsq_full_in;
                    if (ready_in && valid_in) di_en_mem = 1'b1;
                end

                default: begin
                    ready_in = !rob_full;
                end
            endcase
        end
    end

    logic preg_rtable [0:127];

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            for (int i = 0; i < 128; i++) begin
                preg_rtable[i] <= 1'b1;
            end
        end else if (mispredict) begin
            for (int i = 0; i < 128; i++) begin
                preg_rtable[i] <= 1'b1;
            end
        end else begin
            if (di_en_alu && (data_q.pd_new != 7'd0)) begin
                preg_rtable[data_q.pd_new] <= 1'b0;
            end

            if (di_en_mem && (data_q.pd_new != 7'd0) && (data_q.Opcode != 7'b0100011)) begin
                preg_rtable[data_q.pd_new] <= 1'b0;
            end

            if (di_en_b && (data_q.pd_new != 7'd0) && (data_q.Opcode == 7'b1100111)) begin
                preg_rtable[data_q.pd_new] <= 1'b0;
            end

            if (ps_b_ready)   preg_rtable[ps_b_in]   <= 1'b1;
            if (ps_alu_ready) preg_rtable[ps_alu_in] <= 1'b1;
            if (ps_mem_ready) preg_rtable[ps_mem_in] <= 1'b1;
        end
    end

    res_station res_alu (
        .clk(clk), .reset(reset),
        .r_data(data_q),
        .mispredict(mispredict),
        .mispredict_tag(mispredict_tag),
        .fu_ready(fu_alu_ready),
        .rob_index_in(rob_index_in),
        .di_en(di_en_alu),
        .preg_rtable(preg_rtable),
        .fu_issued(alu_issued),
        .full(rs_alu_full),
        .data_out(rs_alu)
    );

    res_station res_b (
        .clk(clk), .reset(reset),
        .r_data(data_q),
        .mispredict(mispredict),
        .mispredict_tag(mispredict_tag),
        .fu_ready(fu_b_ready),
        .rob_index_in(rob_index_in),
        .di_en(di_en_b),
        .preg_rtable(preg_rtable),
        .fu_issued(b_issued),
        .full(rs_b_full),
        .data_out(rs_b)
    );

    res_station res_mem (
        .clk(clk), .reset(reset),
        .r_data(data_q),
        .mispredict(mispredict),
        .mispredict_tag(mispredict_tag),
        .fu_ready(fu_mem_ready),
        .rob_index_in(rob_index_in),
        .di_en(di_en_mem),
        .preg_rtable(preg_rtable),
        .fu_issued(mem_issued),
        .full(rs_mem_full),
        .data_out(rs_mem)
    );

endmodule
