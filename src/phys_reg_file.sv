`timescale 1ns / 1ps

module phys_reg_file(
    input logic clk,
    input logic reset,
    
    // from FUs
    input logic write_alu_en,
    input logic [31:0] data_alu_in,
    input logic [6:0] pd_alu_in,
    
    input logic write_b_en,
    input logic [31:0] data_b_in,
    input logic [6:0] pd_b_in,
    
    input logic write_mem_en,
    input logic [31:0] data_mem_in,
    input logic [6:0] pd_mem_in,
    
    // from RS
    input logic read_en_alu,
    input logic read_en_b,
    input logic read_en_mem,
    
    input logic [6:0] ps1_in_alu,
    input logic [6:0] ps2_in_alu,
    input logic [6:0] ps1_in_b,
    input logic [6:0] ps2_in_b,
    input logic [6:0] ps1_in_mem, 
    input logic [6:0] ps2_in_mem,
    
    // Output data
    output logic [31:0] ps1_out_alu,
    output logic [31:0] ps2_out_alu,
    output logic [31:0] ps1_out_b,
    output logic [31:0] ps2_out_b,
    output logic [31:0] ps1_out_mem,
    output logic [31:0] ps2_out_mem
);
    logic [31:0] prf [0:127];
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            for (logic [7:0] i = 0; i < 128; i++) begin
                prf[i] <= '0;
            end
        end else begin
            if (write_alu_en && pd_alu_in != '0) begin
                prf[pd_alu_in] <= data_alu_in;
            end
            if (write_b_en && pd_b_in != '0) begin
                prf[pd_b_in] <= data_b_in;
            end
            if (write_mem_en && pd_mem_in != '0) begin
                prf[pd_mem_in] <= data_mem_in;
            end
        end
    end
    always_comb begin
        ps1_out_alu = '0;
        ps2_out_alu = '0;
        ps1_out_b = '0;
        ps2_out_b = '0;
        ps1_out_mem = '0;
        ps2_out_mem = '0;
        if (!reset) begin
            if (read_en_alu) begin
                ps1_out_alu = prf[ps1_in_alu];
                ps2_out_alu = prf[ps2_in_alu];
            end
            if (read_en_b) begin
                ps1_out_b = prf[ps1_in_b];
                ps2_out_b = prf[ps2_in_b];
            end
            if (read_en_mem) begin
                ps1_out_mem = prf[ps1_in_mem];
                ps2_out_mem = prf[ps2_in_mem];
            end
        end
    end
endmodule
