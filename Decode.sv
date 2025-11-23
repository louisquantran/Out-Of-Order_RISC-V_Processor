`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/01/2025 03:35:10 PM
// Design Name: 
// Module Name: Decode
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

import types_pkg::*;

module decode(
    // Upstream
    input logic [31:0] instr,
    input logic [31:0] pc_in,
    input logic valid_in,
    output logic ready_in,
    
    // Downstream 
    input logic ready_out,
    output logic valid_out,
    output decode_data data_out
);      
    imm_gen imm_gen_dut (
        .instr(instr),
        .imm(data_out.imm)
    );
    
    signal_decode decoder(
        .instr(instr),
        .rs1(data_out.rs1),
        .rs2(data_out.rs2),
        .rd(data_out.rd),
        .ALUOp(data_out.ALUOp),
        .Opcode(data_out.Opcode),
        .fu(data_out.fu),
        .func3(data_out.func3),
        .func7(data_out.func7)
    );
  
    assign data_out.pc = pc_in;
    assign valid_out = valid_in;
    assign ready_in = ready_out || !valid_out;
    
endmodule
