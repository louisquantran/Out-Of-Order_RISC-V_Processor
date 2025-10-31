`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/29/2025 10:59:10 AM
// Design Name: 
// Module Name: skid_buffer
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


module skid_buffer_struct
#(
    parameter type T = logic
)(
    input logic clk,
    input logic reset,
    
    // upstream (producer -> skid)
    input logic valid_in,
    output logic ready_in,
    input T data_in,
    
    // downstream (skid -> consumer)
    output logic valid_out,
    input logic ready_out,
    output T data_out 
);
    T temp = 0;
    logic full = 0;
    
    assign ready_in = ~full;
    assign valid_out = (full) ? 1'b1 : valid_in;
    assign data_out = (full) ? temp : data_in;
    
    always_ff @(posedge clk) begin 
        if (reset) begin
            full <= 1'b0;
            temp <= '0;
        end else begin
            // store
            if (!ready_out && valid_in && !full) begin
                temp <= data_in;
                full <= 1'b1;
            // take this out
            end else if (ready_out && full) begin
                full <= 1'b0;
            end
        end
    end
endmodule
