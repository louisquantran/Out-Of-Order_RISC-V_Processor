`timescale 1ns / 1ps
import types_pkg::*;

module rename(
    input logic clk,
    input logic reset,

    input logic valid_in,
    input decode_data data_in,
    output logic ready_in,

    input logic write_en,
    input logic [6:0] rob_data_in,

    input logic [4:0] rob_next_tag,

    input logic mispredict,
    input logic [4:0] mispredict_tag,

    input logic hit,
    input logic [4:0] hit_tag,

    output rename_data data_out,
    output logic valid_out,
    input logic ready_out
);

    logic branch, jalr;
    assign branch = (data_in.Opcode == 7'b1100011);
    assign jalr = (data_in.Opcode == 7'b1100111);

    // Writes a destination physical reg?
    wire write_pd = (data_in.Opcode != 7'b0100011) && // store
                    (data_in.Opcode != 7'b1100011) && // branch
                    (data_in.rd != 5'd0);

    wire rename_en = ready_in && valid_in;

    // Free-list interface enables
    wire fl_write_en = write_en && (rob_data_in != 7'b0);
    logic read_en, update_en;
    assign read_en = write_pd && rename_en;
    assign update_en = write_pd && rename_en;

    logic [0:31] [6:0] map;
    logic [0:31] [6:0] re_map;

    logic [6:0] r_ptr_list, w_ptr_list;
    logic [6:0] re_r_ptr,   re_w_ptr;

    logic [6:0] preg;
    logic empty;

    rename_checkpoint [7:0] checkpoint;
    logic capture;
    logic [3:0] index;
    logic [3:0] oldest;

    assign ready_in = (ready_out || !valid_out) && (!empty || !write_pd);

    always_comb begin
        re_map = map;
        re_r_ptr = r_ptr_list;
        re_w_ptr = w_ptr_list;

        if (mispredict) begin
            // restore from checkpoint that matches mispredict_tag
            for (int i = 0; i < 8; i++) begin
                if (checkpoint[i].valid && checkpoint[i].rob_tag == mispredict_tag) begin
                    re_map = checkpoint[i].re_map;
                    re_r_ptr = checkpoint[i].re_r_ptr;
                    re_w_ptr = checkpoint[i].re_w_ptr;
                    break;
                end
            end
        end
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            data_out <= '0;
            valid_out <= 1'b0;

            checkpoint <= '0;
            capture <= 1'b0;
            index <= '0;
            oldest <= '0;

        end else if (mispredict) begin
            data_out <= '0;
            valid_out <= 1'b0;

            // Clear the mispredicted branch checkpoint entry
            for (int i = 0; i < 8; i++) begin
                if (checkpoint[i].valid && checkpoint[i].rob_tag == mispredict_tag) begin
                    if (i[3:0] == oldest) begin
                        checkpoint <= '0;
                        oldest <= '0;
                    end else begin
                        checkpoint[i] <= '0;
                    end
                    break;
                end
            end

            capture <= 1'b0;

        end else begin
            if (valid_out && ready_out) begin
                valid_out <= 1'b0;
            end

            if (rename_en && (branch || jalr)) begin
                logic [6:0] r_ptr_snap_tmp;

                r_ptr_snap_tmp = r_ptr_list;
                if (write_pd) begin
                    r_ptr_snap_tmp = (r_ptr_list == 7'd127) ? 7'd1 : (r_ptr_list + 7'd1);
                end

                capture <= jalr;

                for (int i = 0; i < 8; i++) begin
                    if (!checkpoint[i].valid) begin
                        checkpoint[i].valid <= 1'b1;
                        checkpoint[i].pc <= data_in.pc;
                        checkpoint[i].rob_tag <= rob_next_tag;

                        checkpoint[i].re_map <= map;
                        checkpoint[i].re_r_ptr <= r_ptr_snap_tmp;
                        checkpoint[i].re_w_ptr <= w_ptr_list;

                        index <= i[3:0];
                        break;
                    end
                end
            end

            if (capture) begin
                checkpoint[index].re_map <= map;
                capture <= 1'b0;
            end

            if (hit) begin
                for (int i = 0; i < 8; i++) begin
                    if (checkpoint[i].valid && checkpoint[i].rob_tag == hit_tag) begin
                        checkpoint[i] <= '0;
                        oldest <= oldest + 4'd1;
                        break;
                    end
                end

            end else if (rename_en) begin
                // Produce renamed uop
                data_out.pc <= data_in.pc;
                data_out.ps1 <= map[data_in.rs1];
                data_out.ps2 <= map[data_in.rs2];
                data_out.pd_old <= map[data_in.rd];
                data_out.imm <= data_in.imm;

                // ROB-domain tag
                data_out.rob_tag <= rob_next_tag;

                data_out.fu <= data_in.fu;
                data_out.ALUOp <= data_in.ALUOp;
                data_out.Opcode <= data_in.Opcode;
                data_out.func3 <= data_in.func3;
                data_out.func7 <= data_in.func7;

                if (write_pd) data_out.pd_new <= preg;
                else data_out.pd_new <= '0;

                valid_out <= 1'b1;
            end
        end
    end

    map_table u_map_table(
        .clk(clk),
        .reset(reset),
        .branch(branch),
        .mispredict(mispredict),
        .update_en(update_en),
        .rd(data_in.rd),
        .pd_new(preg),
        .re_map(re_map),
        .map(map)
    );

    free_list u_free_list(
        .clk(clk),
        .reset(reset),
        .mispredict(mispredict),
        .write_en(fl_write_en),
        .data_in(rob_data_in),
        .read_en(read_en),
        .empty(empty),
        .re_r_ptr(re_r_ptr),
        .re_w_ptr(re_w_ptr),
        .pd_new_out(preg),
        .r_ptr_out(r_ptr_list),
        .w_ptr_out(w_ptr_list)
    );
endmodule
