`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/17/2025 09:38:18 PM
// Design Name: 
// Module Name: dispatch
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


module dispatch(
    input logic clk,
    input logic reset,
    // Upstream
    input logic valid_in,
    input rename_data data_in,
    output logic ready_in,
    
    // Data from ROB
    input logic rob_full,
    input logic [4:0] rob_index_in,
    
    // Data from FU
    input logic mispredict,
    input logic [4:0] mispredict_tag,
    input logic [6:0] ps_alu_in,
    input logic [6:0] ps_mem_in,
    input logic ps_alu_ready,
    input logic ps_mem_ready,
    input logic fu_alu_ready,
    input logic fu_b_ready,
    input logic fu_mem_ready,
    
    // Output data from 3 RS
    output rs_data rs_alu,
    output rs_data rs_b,
    output rs_data rs_mem,
    
    output logic alu_issued,
    output logic b_issued,
    output logic mem_issued
);
    logic rs_alu_full = '0;
    logic rs_b_full = '0;
    logic rs_mem_full = '0;
    logic di_en_alu = '0;
    logic di_en_b = '0;
    logic di_en_mem = '0;
    
    rename_data data_q;
    assign data_q = data_in;
        
    always_comb begin
        ready_in = 1'b0;
        di_en_alu = 1'b0;
        di_en_b = 1'b0;
        di_en_mem = 1'b0;
        unique case (data_q.fu)
            2'b01: begin // ALU
                ready_in = !rob_full && !rs_alu_full;
                if (ready_in && valid_in)
                    di_en_alu = 1'b1;
            end
            2'b10: begin // BR
                ready_in = !rob_full && !rs_b_full;
                if (ready_in && valid_in)
                    di_en_b = 1'b1;
            end
            2'b11: begin // MEM
                ready_in = !rob_full && !rs_mem_full;
                if (ready_in && valid_in)
                    di_en_mem = 1'b1;
            end
            default: begin
                // e.g. x0-writes / NOP: only ROB capacity matters
                ready_in = !rob_full;
            end
        endcase
    end
    
    always_ff @(posedge clk) begin
        if (ps_alu_ready) begin
            $display("[%0t] SCOREBOARD: set preg_rtable[%0d]=1 (ALU)", $time, ps_alu_in);
        end
        if (di_en_alu && data_q.pd_new != 7'd0) begin
            $display("[%0t] SCOREBOARD: clear preg_rtable[%0d]=0 (dispatch ALU)", $time, data_q.pd_new);
        end
    end
    
    logic preg_rtable[0:127];
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            for (logic [7:0] i = 0; i < 128; i++) begin
                preg_rtable[i] <= 1'b1;
            end
        end else begin
            // set that preg to 0
            if (di_en_alu && data_q.pd_new != 7'd0) begin
                preg_rtable[data_q.pd_new] <= 1'b0;
            end
            if (di_en_mem && data_q.pd_new != 7'd0) begin
                preg_rtable[data_q.pd_new] <= 1'b0; 
            end
            if (ps_alu_ready) begin
                preg_rtable[ps_alu_in] <= 1'b1;
            end 
            if (ps_mem_ready) begin
                preg_rtable[ps_mem_in] <= 1'b1;
            end
        end
    end
    
    res_station res_alu (
        .clk(clk),
        .reset(reset),
        
        // From rename
        .r_data(data_q),
        
        // From fu_alu
        .mispredict(mispredict),
        .mispredict_tag(mispredict_tag),
        .fu_ready(fu_alu_ready),
        
        // from ROB
        .rob_index_in(rob_index_in),
        
        // From dispatch
        .di_en(di_en_alu),
        .preg_rtable(preg_rtable),
        
        // Output data
        .fu_issued(alu_issued),
        .full(rs_alu_full),
        .data_out(rs_alu)
    );
    
    res_station res_b (
        .clk(clk),
        .reset(reset),
        
        // From rename
        .r_data(data_q),
        
        // From fu_b
        .mispredict(mispredict),
        .mispredict_tag(mispredict_tag),
        .fu_ready(fu_b_ready),
        
        // from ROB
        .rob_index_in(rob_index_in),
        
        // From dispatch
        .di_en(di_en_b),
        .preg_rtable(preg_rtable),
        
        // Output data
        .fu_issued(b_issued),
        .full(rs_b_full),
        .data_out(rs_b)
    );
    
    res_station res_mem (
        .clk(clk),
        .reset(reset),
        
        // From rename
        .r_data(data_q),
        
        // From fu_mem
        .mispredict(mispredict),
        .mispredict_tag(mispredict_tag),
        .fu_ready(fu_mem_ready),
        
        // from ROB
        .rob_index_in(rob_index_in),
        
        // From dispatch
        .di_en(di_en_mem),
        .preg_rtable(preg_rtable),
        
        // Output data
        .fu_issued(mem_issued),
        .full(rs_mem_full),
        .data_out(rs_mem)
    );
    
endmodule
