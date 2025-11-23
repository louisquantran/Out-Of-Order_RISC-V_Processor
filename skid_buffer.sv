`timescale 1ns / 1ps

import types_pkg::*;

module skid_buffer#(
    parameter type T = logic [31:0]
)(
    input logic clk,
    input logic reset,
    
    // Upstream
    input logic valid_in,
    input T data_in,
    output logic ready_in,
    
    // Downstream
    input logic ready_out,
    output logic valid_out,
    output T data_out
);
    T data_out_hold;
    logic full;
    
    assign ready_in = ~full;
    assign valid_out = (full) ? 1'b1 : valid_in;
    assign data_out = (full) ? data_out_hold : data_in;
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            data_out_hold <= '0;
            full <= 1'b0;
        end else begin
            if (!ready_out && valid_in && !full) begin
                full <= 1'b1;
                data_out_hold <= data_in;
            end else if (ready_out && full) begin
                full <= 1'b0;
            end
        end
    end
endmodule
