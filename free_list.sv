module free_list(
    input logic clk,
    input logic reset,
    
    // from ROB
    input logic write_en,
    input logic [6:0] data_in,
    
    input logic read_en,
    input logic mispredict,
    output logic empty,
    input logic [6:0] re_list [0:95],
    input logic [6:0] re_r_ptr,
    input logic [6:0] re_w_ptr,
    output logic [6:0] pd_new_out,
    output logic [6:0] list_out [0:95],
    output logic [6:0] r_ptr_out,
    output logic [6:0] w_ptr_out
);
    logic [6:0] list [0:95];
    logic [6:0]  w_ptr, r_ptr; 
    
    assign list_out = list;
    assign r_ptr_out = r_ptr;
    assign w_ptr_out = w_ptr;
      
    logic [7:0] ctr;
    
    assign pd_new_out = list[r_ptr];    
    assign empty = (ctr == 0);
    
    logic do_write;
    logic do_read;
    
    assign do_write = write_en && (ctr!=8'd96);
    assign do_read = read_en && (ctr!=0);
    
    logic [7:0] distance;
    always_comb begin
        if (r_ptr >= re_r_ptr) begin
            distance = r_ptr - re_r_ptr;
        end else begin
            distance = 96 - re_r_ptr + r_ptr;
        end
    end
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
        w_ptr    <= 7'd0;
        r_ptr    <= 7'd0;
        ctr      <= 7'd96;
        for (int i = 0; i <= 95; i++) begin
            list[i] <= i+32;
        end
        end else begin
            // Mispredict case
            if (mispredict) begin
                ctr <= ctr + distance;
                r_ptr <= re_r_ptr;
                w_ptr <= re_w_ptr;
                list <= re_list;
            end else begin
                if (do_read) begin
                    r_ptr <= (r_ptr == 95) ? 0 : r_ptr + 1;
                    ctr <= ctr - 1'b1;
                end
                if (do_write && data_in != '0) begin
                    w_ptr      <= (w_ptr == 95) ? 0 : w_ptr + 1;
                    list[w_ptr] <= data_in; 
                    ctr <= ctr + 1'b1;
                end
            end
        end
    end
endmodule
