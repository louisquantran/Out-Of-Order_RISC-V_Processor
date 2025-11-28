`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/31/2025 03:30:11 PM
// Design Name: 
// Module Name: Fetch
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

import types_pkg::*;

module fetch(
    // Upstream
    input logic [31:0] pc_in,
    
    // Downstream
    input logic ready_out,
    output logic valid_out,
    output fetch_data data_out
);
    logic [31:0] instr_icache;
        
    // Call i_cache
    i_cache i_cache_dut (
        .address(pc_in),
        .instruction(instr_icache)
    );
    
    assign data_out.pc = pc_in; 
    assign data_out.pc_4 = pc_in + 4;
    assign data_out.instr = instr_icache;
    assign valid_out = 1'b1;
endmodule