`timescale 1ns / 1ps
import types_pkg::*;

module fus(
    input logic clk,
    input logic reset,

    // From Dispatch
    input logic dispatch_valid,
    input logic [4:0]  dispatch_rob_tag,
    input logic [31:0] lsq_dispatch_pc,
    output logic lsq_full_out,

    // From Reservation Stations
    input logic alu_issued,
    input rs_data alu_rs_data,
    input logic b_issued,
    input rs_data b_rs_data,
    input logic mem_issued,
    input rs_data mem_rs_data,

    // From ROB
    input logic retired,
    input logic [4:0] rob_head,
    input logic [4:0] curr_rob_tag,
    input logic mispredict,
    input logic [4:0] mispredict_tag,
    input logic [31:0] mispredict_pc,

    // PRF
    input logic [31:0] ps1_alu_data,
    input logic [31:0] ps2_alu_data,
    input logic [31:0] ps1_b_data,
    input logic [31:0] ps2_b_data,
    input logic [31:0] ps1_mem_data,
    input logic [31:0] ps2_mem_data,

    // From FU branch to ROB
    output logic br_mispredict,
    output logic [4:0] br_mispredict_tag,

    // Outputs
    output alu_data alu_out,
    output b_data b_out,
    output mem_data mem_out,

    output logic [4:0] store_rob_tag,
    output logic store_lsq_done
);

    // branch status to ROB
    assign br_mispredict = b_out.mispredict;
    assign br_mispredict_tag = b_out.mispredict_tag;

    fu_alu u_alu (
        .clk(clk),
        .reset(reset),

        .curr_rob_tag(curr_rob_tag),
        .mispredict(mispredict),
        .mispredict_tag(mispredict_tag),

        .issued(alu_issued),
        .data_in(alu_rs_data),
        .ps1_data(ps1_alu_data),
        .ps2_data(ps2_alu_data),

        .data_out(alu_out)
    );

    fu_mem u_mem (
        .clk(clk),
        .reset(reset),

        // From ROB
        .retired(retired),
        .rob_head(rob_head),

        .curr_rob_tag(curr_rob_tag),
        .mispredict(mispredict),
        .mispredict_tag(mispredict_tag),
        .mispredict_pc(mispredict_pc),

        // From Dispatch (LSQ allocation)
        .dispatch_valid(dispatch_valid),
        .dispatch_rob_tag(dispatch_rob_tag),
        .lsq_dispatch_pc(lsq_dispatch_pc),
        .lsq_full_out(lsq_full_out),

        // From RS and PRF
        .issued(mem_issued),
        .data_in(mem_rs_data),
        .ps1_data(ps1_mem_data),
        .ps2_data(ps2_mem_data),

        // Outputs
        .data_out(mem_out),
        .store_rob_tag(store_rob_tag),
        .store_lsq_done(store_lsq_done)
    );

    fu_branch u_branch (
        .clk(clk),
        .reset(reset),

        .curr_rob_tag(curr_rob_tag),
        .mispredict_tag(mispredict_tag),

        .issued(b_issued),
        .data_in(b_rs_data),

        .ps1_data(ps1_b_data),
        .ps2_data(ps2_b_data),

        .data_out(b_out)
    );

endmodule
