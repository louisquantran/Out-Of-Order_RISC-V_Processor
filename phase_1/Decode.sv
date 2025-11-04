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


module Decode(
    input logic clk,
    input logic reset,
    
    input logic [31:0] instruction,
    input logic [31:0] PC_in,
    input logic valid_in,
    input logic ready_out,
    
    output logic ready_in,
    output logic valid_out,
    output logic [31:0] PC_out,
    
    output logic [4:0] rs1,
    output logic [4:0] rs2,
    output logic [4:0] rd,
    output logic [31:0] imm,
    output logic [2:0] ALUOp,
    output logic [6:0] Opcode
);
    logic [31:0] PC_out_hold;
    logic [4:0] rs1_hold;
    logic [4:0] rs2_hold;
    logic [4:0] rd_hold;
    logic [31:0] imm_hold;
    logic [2:0] ALUOp_hold;
    logic [6:0] Opcode_hold;
    
    logic [4:0] rs1_now;
    logic [4:0] rs2_now;
    logic [4:0] rd_now;
    logic [31:0] imm_now;
    logic [2:0] ALUOp_now;
    logic [6:0] Opcode_now;
        
    ImmGen immgen_dut (
        .instruction(instruction),
        .imm(imm_now)
    );
    
    always_comb begin
        Opcode_now = instruction[6:0];
        // We only support a few instructions, therefore the decoded signals will not fully cover every instruction
        case (Opcode_now) 
            // imm_now is already calculated
            // I-type
            7'b0010011: begin
                rs1_now = instruction[19:15];
                rs2_now = 5'b0;
                rd_now = instruction[11:7];
                ALUOp_now = 3'b000;
            end
            // LUI
            7'b0110111: begin
                rs1_now = 5'b0;
                rs2_now = 5'b0;
                rd_now = instruction[11:7];
                ALUOp_now = 3'b101;
            end
            // R-type
            7'b0110011: begin
                rs1_now = instruction[19:15];
                rs2_now = instruction[24:20];
                rd_now = instruction[11:7];
                ALUOp_now = 3'b001;
            end 
            // L-type
            7'b0000011: begin
                rs1_now = instruction[19:15];
                rs2_now = 5'b0;
                rd_now = instruction[11:7];
                ALUOp_now = 3'b010;
            end
            // S-type
            7'b0100011: begin
                rs1_now = instruction[19:15];
                rs2_now = instruction[24:20];
                rd_now = 5'b0;
                ALUOp_now = 3'b011;
            end
            // BNE
            7'b1100011: begin
                rs1_now = instruction[19:15];
                rs2_now = instruction[24:20];
                rd_now = 5'b0;
                ALUOp_now = 3'b100;
            end
            // J-type
            7'b1100111: begin
                rs1_now = instruction[19:15];
                rs2_now = 5'b0;
                rd_now = instruction[11:7];
                ALUOp_now = 3'b110;
            end
        endcase
    end
    
    // skid buffer part
    // Assign output signals accordingly
    logic full;
    always_comb begin
        valid_out = full;
        ready_in = (~full);
        // if stall, assign hold values
        if (full) begin
            rs1 = rs1_hold;
            rs2 = rs2_hold;
            rd = rd_hold;
            imm = imm_hold;
            ALUOp = ALUOp_hold;
            Opcode = Opcode_hold;
            PC_out = PC_out_hold;
        // if not stall, assign current values
        end else begin
            rs1 = rs1_now;
            rs2 = rs2_now;
            rd = rd_now;
            imm = imm_now;
            ALUOp = ALUOp_now;
            Opcode = Opcode_now;
            PC_out = PC_in;
        end
    end
    
    always_ff @(posedge clk) begin 
        // reset
        if (reset) begin 
            rs1_now <= 5'b0;
            rs2_now <= 5'b0;
            rd_now <= 5'b0;
            imm_now <= 32'b0;
            ALUOp_now <= 3'b0;
            Opcode_now <= 7'b0;
            full <= 1'b0;
        end else begin
            // hold when valid_in and not full
            if (!ready_out && valid_in && !full) begin
                full <= 1'b1;
                
                rs1_hold <= rs1_now;
                rs2_hold <= rs2_now;
                rd_hold <= rd_now;
                imm_hold <= imm_now;
                ALUOp_hold <= ALUOp_now;
                Opcode_hold <= Opcode_now;
            // reset full state when ready_out signal is 1
            end else if (ready_out && full) begin
                full <= 1'b0;
            end
        end
    end 
endmodule
