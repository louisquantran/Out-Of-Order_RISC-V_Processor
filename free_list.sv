module free_list#(
parameter int DEPTH = 128
)(
    input logic clk,
    input logic reset,
    
    // from ROB
    input logic write_en,
    input logic [6:0] data_in,
    
    input logic read_en,
    input logic mispredict,
    output logic empty,
    input logic [6:0] re_ptr,
    output logic [6:0] pd_new_out
);
    logic [6:0] list [0:127];
    logic [6:0]  w_ptr, r_ptr;  
    logic [7:0] ctr;
    
    assign pd_new_out = list[r_ptr];    
    assign empty = (ctr == 0);
    
    logic do_write;
    logic do_read;
    
    assign do_write = write_en && (ctr!=8'd128);
    assign do_read = read_en && (ctr!=0);
    
    logic [7:0] distance;
    always_comb begin 
        if (r_ptr >= re_ptr) begin
            distance = r_ptr - re_ptr;
        end else begin
            distance = DEPTH - re_ptr + r_ptr;
        end
    end
    always_ff @(posedge clk) begin
        if (reset) begin
        w_ptr    <= 7'd1;
        r_ptr    <= 7'd32;
        ctr      <= 7'd96;
        for (int i = 32; i <= 127; i++) begin
            list[i] <= i;
        end
        end else begin
            // Mispredict case
            if (mispredict) begin
                ctr <= ctr + distance;
                r_ptr <= re_ptr;
            end else begin
                if (do_read) begin
                    r_ptr <= (r_ptr == 127) ? 1 : r_ptr + 1;
                end
                
                if (do_write && data_in != '0) begin
                    w_ptr      <= (w_ptr == 127) ? 1 : w_ptr + 1;
                    list[w_ptr] <= data_in; 
                end
            
                unique case ({do_write, do_read})
                    2'b10: if (ctr < DEPTH) ctr <= ctr + 1'b1;
                    2'b01: ctr <= ctr - 1'b1;    
                    default: ctr <= ctr;          
                endcase
            end
        end
    end
endmodule
