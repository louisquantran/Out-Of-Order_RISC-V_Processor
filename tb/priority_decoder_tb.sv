`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/29/2025 09:49:15 AM
// Design Name: 
// Module Name: priority_decoder_tb
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


module priority_decoder_tb;
    localparam int WIDTH = 4;

    logic [WIDTH-1:0]         in;
    logic [$clog2(WIDTH)-1:0] out;
    logic                     valid;

    // DUT
    priority_decoder #(.WIDTH(WIDTH)) dut (
        .in(in), .out(out), .valid(valid)
    );

    // Reference model: MSB has highest priority
    function automatic logic [$clog2(WIDTH)-1:0]
        ref_idx(input logic [WIDTH-1:0] x);
        logic [$clog2(WIDTH)-1:0] idx; idx = '0;
        for (int i = WIDTH-1; i >= 0; i--) begin
            if (x[i]) begin
                idx = i[$clog2(WIDTH)-1:0];
                break;
            end
        end
        return idx;
    endfunction

    function automatic logic ref_valid(input logic [WIDTH-1:0] x);
        return (x != '0);
    endfunction

    logic rv;
    logic [$clog2(WIDTH)-1:0] ri;
    initial begin
        automatic int errors = 0;
        for (int v = 0; v < (1<<WIDTH); v++) begin
            in = v[WIDTH-1:0];
            #10; // allow combinational settle
            rv = ref_valid(in);
            ri = ref_idx(in);
            if (valid !== rv || (rv && out !== ri)) begin
                $display("FAIL in=%b  exp_valid=%0d exp_out=%0d  got_valid=%0d got_out=%0d",
                         in, rv, ri, valid, out);
                errors++;
            end
        end
        if (errors) begin
            $display("TEST FAILED with %0d errors.", errors);
            $fatal(1);
        end else begin
            $display("TEST PASSED.");
            $finish;
        end
    end
endmodule

