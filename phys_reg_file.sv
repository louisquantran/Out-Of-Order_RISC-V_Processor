`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/13/2025 05:54:38 PM
// Design Name: 
// Module Name: phys_reg_file
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


module phys_reg_file(
    input logic clk,
    input logic reset,
    
    // from ROB
    input logic write_en,
    input logic [31:0] data_in,
    input logic [7:0] pd_in
);
    logic [31:0] prf [0:127];
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            for (logic [7:0] i = 0; i < 128; i++) begin
                prf[i] <= '0;
            end
        end else begin
            if (write_en) begin
                prf[pd_in] <= data_in;
            end
        end
    end
endmodule
