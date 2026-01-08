`timescale 1ns/1ps
import types_pkg::*;

module data_memory #(
    parameter int BYTE_DEPTH = 102400
)(
    input logic clk,
    input logic reset,

    // store commit
    input logic store_wb,
    input lsq lsq_in,

    // load request 
    input logic load_mem,
    input lsq lsq_load,

    // output 
    output mem_data data_out,
    output logic load_ready,
    output logic valid
);

    // Word-addressed memory 
    localparam int WORD_DEPTH = (BYTE_DEPTH + 3) / 4;
    localparam int WADDR_BITS = $clog2(WORD_DEPTH);

    (* ram_style = "block" *)
    logic [31:0] mem [0:WORD_DEPTH-1];

    logic [WADDR_BITS-1:0] waddr;
    logic [1:0] woff;

    always_comb begin
        waddr = lsq_in.addr[WADDR_BITS+1:2];
        woff = lsq_in.addr[1:0];
    end

    always_ff @(posedge clk) begin
        if (store_wb) begin
            if (lsq_in.sw_sh_signal == 1'b0) begin
                // sw
                mem[waddr][7:0] <= lsq_in.ps2_data[7:0];
                mem[waddr][15:8] <= lsq_in.ps2_data[15:8];
                mem[waddr][23:16] <= lsq_in.ps2_data[23:16];
                mem[waddr][31:24] <= lsq_in.ps2_data[31:24];
            end else begin
                // sh
                if (woff[1] == 1'b0) begin
                    mem[waddr][7:0] <= lsq_in.ps2_data[7:0];
                    mem[waddr][15:8] <= lsq_in.ps2_data[15:8];
                end else begin
                    mem[waddr][23:16] <= lsq_in.ps2_data[7:0];
                    mem[waddr][31:24] <= lsq_in.ps2_data[15:8];
                end
            end
        end
    end

    // Accept request only if not already pending
    logic rd_pending;
    logic [31:0] rdata_q;

    logic [WADDR_BITS-1:0] raddr_q;
    logic [1:0] roff_q;
    logic [2:0] func3_q;
    logic [4:0] rob_q;
    logic [6:0] pd_q;

    // Ready when no outstanding request
    assign load_ready = ~rd_pending;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            rd_pending <= 1'b0;
            valid <= 1'b0;
            data_out <= '0;

            raddr_q <= '0;
            roff_q <= '0;
            func3_q <= '0;
            rob_q <= '0;
            pd_q <= '0;
            rdata_q <= '0;

        end else begin
            // default
            valid <= 1'b0;
            data_out <= '0;

            // Response stage (for request accepted last cycle)
            if (rd_pending) begin
                valid <= 1'b1;
                data_out.fu_mem_ready <= 1'b1;
                data_out.fu_mem_done <= 1'b1;
                data_out.rob_fu_mem <= rob_q;
                data_out.p_mem <= pd_q;

                unique case (func3_q)
                    3'b010: data_out.data <= rdata_q; // lw
                    3'b100: begin                     // lbu
                        unique case (roff_q)
                            2'd0: data_out.data <= {24'b0, rdata_q[7:0]};
                            2'd1: data_out.data <= {24'b0, rdata_q[15:8]};
                            2'd2: data_out.data <= {24'b0, rdata_q[23:16]};
                            2'd3: data_out.data <= {24'b0, rdata_q[31:24]};
                        endcase
                    end
                    default: data_out.data <= 32'b0;
                endcase
            end

            // Clear pending by default, set again only when we accept a new req.
            rd_pending <= 1'b0;

            if (load_mem && load_ready && !store_wb && !lsq_load.store) begin
                rd_pending <= 1'b1;

                raddr_q <= lsq_load.addr[WADDR_BITS+1:2];
                roff_q <= lsq_load.addr[1:0];
                func3_q <= lsq_load.func3;
                rob_q <= lsq_load.rob_tag;
                pd_q <= lsq_load.pd;
                rdata_q <= mem[lsq_load.addr[WADDR_BITS+1:2]];
            end
        end
    end

endmodule
