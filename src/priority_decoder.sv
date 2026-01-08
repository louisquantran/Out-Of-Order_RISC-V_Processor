`timescale 1ns / 1ps

module priority_decoder 
#(
    parameter WIDTH = 4
)(
    input wire [WIDTH-1:0] in,
    output logic [$clog2(WIDTH)-1:0] out,
    output logic valid
);
    logic [$clog2(WIDTH)-1:0] out_temp;
    logic val;
    always_comb begin
        out_temp = 0;
        val = 0;
        for (int i = WIDTH-1; i >= 0; i--) begin
            if (in[i] == 1) begin
                out_temp = i;
                val = 1;
                break;
            end 
        end
        out = out_temp;
        valid = val;
    end
endmodule
