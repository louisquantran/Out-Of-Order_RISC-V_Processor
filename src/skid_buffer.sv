`timescale 1ns / 1ps
import types_pkg::*;

module skid_buffer#(
    parameter type T = logic [31:0]
)(
    input logic clk,
    input logic reset,
    input logic mispredict,

    // Upstream
    input logic valid_in,
    input T data_in,
    output logic ready_in,

    // Downstream
    input logic ready_out,
    output logic valid_out,
    output T data_out
);
    T hold;
    logic full;

    always_comb begin
        if (mispredict || reset) begin
            valid_out = 1'b0;
            data_out = '0;
            ready_in = 1'b1; 
        end else begin
            valid_out = full ? 1'b1 : valid_in;
            data_out = full ? hold : data_in;

            ready_in = (!full) || ready_out;
        end
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            full <= 1'b0;
            hold <= '0;
        end else if (mispredict) begin
            full <= 1'b0;
            hold <= '0;
        end else begin
            if (ready_out && full) begin
                if (valid_in) begin
                    hold <= data_in;
                    full <= 1'b1;
                end else begin
                    full <= 1'b0;
                end
            end
            else if (!ready_out && valid_in && !full) begin
                hold <= data_in;
                full <= 1'b1;
            end
        end
    end
endmodule
