`timescale 1ns/1ps
import types_pkg::*;

module ooo_top (
    input  logic clk,
    input  logic reset,
    input  logic exec_ready
);

    // PC generator
    logic [31:0] pc_reg;
    
    // Fetch 
    fetch_data fetch_out;
    logic      v_fetch;
    logic      r_to_fetch;  
    
    fetch u_fetch (
        .pc_in     (pc_reg),
        .ready_out (r_to_fetch),
        .valid_out (v_fetch),
        .data_out  (fetch_out)
    ); 
    
    wire fetch_fire = (v_fetch & ~reset) && r_to_fetch;
    
    // Skid buffer from Fetch to Decode
    fetch_data sb_f_out;
    logic      v_sb;
    logic      r_from_decode; 
    
    skid_buffer #(.T(fetch_data)) u_fb (
        .clk       (clk),
        .reset     (reset),
        .valid_in  (v_fetch & ~reset),
        .data_in   (fetch_out),
        .ready_in  (r_to_fetch),
        .ready_out (r_from_decode),
        .valid_out (v_sb),
        .data_out  (sb_f_out)
    );
    
    // Post-Decode skid buffer 
    decode_data sb_d_out;
    logic       r_sb_to_decode;  
    logic       v_dsb;
    
    // Decode 
    decode_data decode_out;
    logic       v_decode;
    
    decode u_decode (
    // Upstream
        .instr     (sb_f_out.instr),
        .pc_in     (sb_f_out.pc),
        .valid_in  (v_sb),
        .ready_in  (r_from_decode),
        
        // Downstream to post-Decode skid
        .ready_out (r_sb_to_decode),
        .valid_out (v_decode),
        .data_out  (decode_out)
    );
    
    // From Rename to Skid Buffer
    logic r_to_sb_d;
    
    // Post-Decode Skid Buffer
    skid_buffer #(.T(decode_data)) u_db (
        .clk       (clk),
        .reset     (reset),
        // Upstream 
        .valid_in  (v_decode),
        .data_in   (decode_out),
        .ready_in  (r_sb_to_decode),
        // Downstream 
        .ready_out (r_to_sb_d),
        .valid_out (v_dsb),
        .data_out  (sb_d_out)
    );
    
    // Post-Rename Skid Buffer
    logic r_sb_to_r;
    
    // From Rename to Skid Buffer
    rename_data rename_out;
    logic r_to_bf_di;
    
    // DISPATCH SIGNALS:
    // ROB
    logic rob_full;
    logic [4:0] rob_index;
    logic [4:0] mispredict_tag;
    logic mispredict;
    // Update free_list
    logic [6:0] preg_old;
    logic valid_retired;
    // Signal LSQ
    logic [4:0] rob_head;
    
    // FU
    alu_data alu_out;
    b_data b_out;
    mem_data mem_out;
    
    // Output data from 3 RS
    rs_data rs_alu;
    rs_data rs_b;
    rs_data rs_mem;
    
    logic alu_issued;
    logic b_issued;
    logic mem_issued;
    
    rename u_rename (
        .clk(clk),
        .reset(reset),
        
        // Data from skid buffer
        // Upstream
        .valid_in(v_dsb),
        .data_in(sb_d_out),
        .ready_in(r_to_sb_d),
        
        // From ROB
        .write_en(valid_retired),
        .rob_data_in(preg_old),
        .mispredict(mispredict),
        
        // Downstream
        .data_out(rename_out),
        .valid_out(r_to_bf_di),
        .ready_out(r_sb_to_r)
    );
    

    // From Dispatch to Skid Buffer
    logic r_di_to_sb;
    
    // From Skid Buffer to Dispatch
    logic v_sb_to_di;
    rename_data sb_to_di_out;
    
    skid_buffer #(.T(rename_data)) u_rb (
        .clk(clk),
        .reset(reset),
        
        // Rename to Skid Buffer
        .valid_in(r_to_bf_di),
        .data_in(rename_out),
        .ready_in(r_sb_to_r),
        
        // Dispatch to Skid Buffer
        .ready_out(r_di_to_sb),
        .valid_out(v_sb_to_di),
        .data_out(sb_to_di_out)
    );
    
    dispatch u_dispatch (
        .clk(clk),
        .reset(reset),
        
        // Skid Buffer to Dispatch
        .valid_in(v_sb_to_di),
        .data_in(sb_to_di_out),
        .ready_in(r_di_to_sb),
        
        // Data from ROB
        .rob_full(rob_full),
        .rob_index_in(rob_index),
        .mispredict_tag(mispredict_tag), 
        .mispredict(mispredict),
        
        // Data from FU
        .ps_alu_in(alu_out.p_alu),
        .ps_b_in(b_out.p_b),
        .ps_mem_in(mem_out.p_mem),
        .ps_alu_ready(alu_out.fu_alu_done),
        .ps_b_ready(b_out.fu_b_done),
        .ps_mem_ready(mem_out.fu_mem_done),
        .fu_alu_ready(alu_out.fu_alu_ready),
        .fu_b_ready(b_out.fu_b_ready),
        .fu_mem_ready(mem_out.fu_mem_ready),
        
        // Output data from 3 RS
        .rs_alu(rs_alu),
        .rs_b(rs_b),
        .rs_mem(rs_mem),
        
        .alu_issued(alu_issued),
        .b_issued(b_issued),
        .mem_issued(mem_issued)
    );
    
    // Enable signal from Skid Buffer and Dispatch
    logic rob_write_en;
    assign rob_write_en = r_di_to_sb && v_sb_to_di;
    
    
    // ROB
    rob u_rob (
        .clk(clk),
        .reset(reset),
        
        // From Dispatch
        .write_en(rob_write_en),
        .pd_new_in(sb_to_di_out.pd_new),
        .pd_old_in(sb_to_di_out.pd_old),
        .pc_in(sb_to_di_out.pc),
        
        // From FUs
        .fu_alu_done(alu_out.fu_alu_done),
        .fu_b_done(b_out.fu_b_done),
        .fu_mem_done(mem_out.fu_mem_done), 
        .rob_fu_alu(alu_out.rob_fu_alu),
        .rob_fu_mem(mem_out.rob_fu_mem),
        .rob_fu_b(b_out.rob_fu_b),
        .br_mispredict(b_out.mispredict),
        .br_mispredict_tag(b_out.mispredict_tag),
        
        
        // Update free_list
        .preg_old(preg_old),
        .valid_retired(valid_retired),
        
        // Signal LSQ
        .head(rob_head),
        
        // Mispredict 
        .mispredict(mispredict),
        .mispredict_tag(mispredict_tag),
        .ptr(rob_index),
        
        .full(rob_full)
    );
    
    // Read data from physical register file
    logic [31:0] ps1_out_alu;
    logic [31:0] ps2_out_alu;
    logic [31:0] ps1_out_b;
    logic [31:0] ps2_out_b;
    logic [31:0] ps1_out_mem;
    logic [31:0] ps2_out_mem;
    
    phys_reg_file u_phys_reg (
        .clk(clk),
        .reset(reset),
        
        // From FU ALU
        .write_alu_en(alu_out.fu_alu_done),
        .data_alu_in(alu_out.data),
        .pd_alu_in(alu_out.p_alu),
        
        // From FU Branch
        .write_b_en(b_out.fu_b_done),
        .data_b_in(b_out.data),
        .pd_b_in(b_out.p_b),
        
        // From FU Mem
        .write_mem_en(mem_out.fu_mem_done),
        .data_mem_in(mem_out.data),
        .pd_mem_in(mem_out.p_mem),
        
        // From RS
        .read_en_alu(alu_issued),
        .read_en_b(b_issued),
        .read_en_mem(mem_issued),
        
        .ps1_in_alu(rs_alu.ps1),
        .ps2_in_alu(rs_alu.ps2),
        .ps1_in_b(rs_b.ps1),
        .ps2_in_b(rs_b.ps2),
        .ps1_in_mem(rs_mem.ps1),
        .ps2_in_mem(rs_mem.ps2),
        
        // Output data
        .ps1_out_alu(ps1_out_alu),
        .ps2_out_alu(ps2_out_alu),
        .ps1_out_b(ps1_out_b),
        .ps2_out_b(ps2_out_b),
        .ps1_out_mem(ps1_out_mem),
        .ps2_out_mem(ps2_out_mem)
    );
    
    fus u_fus(
        .clk(clk),
        .reset(reset),
        
        // From RSs
        .alu_issued(alu_issued),
        .alu_rs_data(rs_alu),
        .b_issued(b_issued),
        .b_rs_data(rs_b),
        .mem_issued(mem_issued),
        .mem_rs_data(rs_mem),
        
        // From ROB
        .retired(valid_retired),
        .rob_head(rob_head),
        .curr_rob_tag(rob_index),
        .mispredict(mispredict),
        .mispredict_tag(mispredict_tag),
        
        // PRF 
        .ps1_alu_data(ps1_out_alu),
        .ps2_alu_data(ps2_out_alu),
        .ps1_b_data(ps1_out_b),
        .ps2_b_data(ps2_out_b),
        .ps1_mem_data(ps1_out_mem),
        .ps2_mem_data(ps2_out_mem),
        
        // From FU branch
        .br_mispredict(b_out.mispredict),
        .br_mispredict_tag(b_out.mispredict_tag),
        
        // Output data
        .alu_out(alu_out),
        .b_out(b_out),
        .mem_out(mem_out)
    );
    
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            pc_reg <= 32'h0000_0000;
        end else if (fetch_fire) begin
            if (b_out.fu_b_done && b_out.jalr_bne_signal) begin
                pc_reg <= b_out.pc;
            end else begin
                pc_reg <= pc_reg + 4;
            end
        end
    end
endmodule
