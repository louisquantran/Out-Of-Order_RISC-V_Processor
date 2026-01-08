`timescale 1ns / 1ps
import types_pkg::*;

module fu_branch(
    input logic clk,
    input logic reset,

    input logic [4:0] curr_rob_tag,
    input logic [4:0] mispredict_tag,

    // From RS
    input rs_data data_in,
    input logic   issued,

    // From PRF
    input logic [31:0] ps1_data,
    input logic [31:0] ps2_data,

    // Output
    output b_data data_out
);

    always_comb begin
        data_out = '0;

        data_out.fu_b_ready = 1'b1;
        data_out.fu_b_done = 1'b0;

        if (issued) begin
            // Default tags always in ROB domain
            data_out.rob_fu_b = data_in.rob_index;
            data_out.mispredict_tag = data_in.rob_index;
            data_out.hit_tag = data_in.rob_index; 

            if (data_in.Opcode == 7'b1100111) begin
                // JALR
                if (data_in.func3 == 3'b000) begin
                    data_out.pc = data_in.imm + ps1_data;
                    data_out.data = data_in.pc + 32'd4;
                    data_out.jalr_bne_signal = 1'b1;

                    data_out.p_b = data_in.pd;
                    data_out.mispredict = 1'b1;   // assume "not taken" 
                    data_out.hit = 1'b0;
                end

            end else if (data_in.Opcode == 7'b1100011) begin
                // BNE
                if (data_in.func3 == 3'b001) begin
                    if ((ps1_data - ps2_data) != 0) begin
                        // taken => mispredict (predict not-taken)
                        data_out.pc = (data_in.pc + data_in.imm) & {{31{1'b1}}, 1'b0};
                        data_out.jalr_bne_signal = 1'b1;

                        data_out.mispredict = 1'b1;
                        data_out.hit = 1'b0;
                    end else begin
                        // not-taken => hit
                        data_out.mispredict = 1'b0;
                        data_out.hit = 1'b1;
                        data_out.jalr_bne_signal = 1'b0;
                    end
                end
            end

            data_out.fu_b_done = 1'b1;
        end
    end

endmodule
