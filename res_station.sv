`timescale 1ns / 1ps
import types_pkg::*;

module res_station(
    input logic clk,
    input logic reset,

    // from rename
    input rename_data r_data,

    // from fus
    input logic fu_ready,

    // from ROB
    input logic [4:0] rob_index_in,
    input logic mispredict,
    input logic [4:0] mispredict_tag,

    // from Dispatch
    input logic di_en,
    input logic preg_rtable [0:127],

    // Output
    output logic fu_issued,
    output logic full,
    output rs_data data_out
);

    rs_data rs_table [0:7];

    logic [2:0] free_idx, issue_idx, alloc_idx;
    logic has_free, can_issue, will_issue, will_dispatch, alloc_ok;

    logic [15:0] seq_ctr;
    logic [15:0] best_seq;

    // Helpers
    function automatic logic op_needs_ps1(input rs_data e);
        return !(e.Opcode == 7'h37 || e.Opcode == 7'h17 || e.Opcode == 7'h6F);
    endfunction

    function automatic logic op_needs_ps2(input rs_data e);
        return (e.Opcode == 7'h33) || (e.Opcode == 7'h23) || (e.Opcode == 7'h63);
    endfunction

    function automatic logic entry_ready(input rs_data e, input logic preg_rtable_l [0:127]);
        logic ps1_rdy, ps2_rdy;
        ps1_rdy = preg_rtable_l[e.ps1];
        ps2_rdy = preg_rtable_l[e.ps2];

        // Only require operands that the op actually uses
        if (op_needs_ps1(e) && !ps1_rdy) return 1'b0;
        if (op_needs_ps2(e) && !ps2_rdy) return 1'b0;
        return 1'b1;
    endfunction

    // find free slot + oldest ready slot
    always_comb begin
        // defaults
        has_free = 1'b0;
        free_idx = 3'd0;
        full = 1'b1;

        can_issue = 1'b0;
        issue_idx = 3'd0;
        best_seq = '1;

        // find free slot (valid==0 means free)
        for (int i = 0; i < 8; i++) begin
            if (!has_free && !rs_table[i].valid) begin
                has_free = 1'b1;
                free_idx = i[2:0];
                full = 1'b0;
            end
        end

        // pick oldest ready
        for (int i = 0; i < 8; i++) begin
            if (rs_table[i].valid) begin
                if (entry_ready(rs_table[i], preg_rtable)) begin
                    if (!can_issue || (rs_table[i].seq < best_seq)) begin
                        can_issue = 1'b1;
                        best_seq = rs_table[i].seq;
                        issue_idx = i[2:0];
                    end
                end
            end
        end
    end

    assign will_issue = can_issue && fu_ready;
    assign will_dispatch = di_en;

    // Allow dispatch even when full if we are issuing this cycle
    assign alloc_ok = has_free || will_issue;
    assign alloc_idx = has_free ? free_idx : issue_idx; // use freed slot if no free slot

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            for (int i = 0; i < 8; i++) rs_table[i] <= '0;
            seq_ctr <= '0;
            fu_issued <= 1'b0;
            data_out <= '0;

        end else begin
            fu_issued <= 1'b0;

            // Mispredict flush
            if (mispredict) begin
                automatic logic [4:0] start;
                start = (mispredict_tag == 5'd15) ? 5'd0 : (mispredict_tag + 5'd1);

                for (int i = 0; i < 8; i++) begin
                    if (rs_table[i].valid) begin
                        for (logic [4:0] j = start;
                             j != rob_index_in;
                             j = (j == 5'd15) ? 5'd0 : (j + 5'd1)) begin
                            if (rs_table[i].rob_index == j) begin
                                rs_table[i] <= '0;
                                break;
                            end
                        end
                    end
                end

            end else begin
                // Issue
                if (will_issue) begin
                    data_out <= rs_table[issue_idx];
                    rs_table[issue_idx] <= '0;
                    fu_issued <= 1'b1;
                end

                // Dispatch (into free or freed slot)
                if (will_dispatch && alloc_ok) begin
                    rs_table[alloc_idx] <= '0;

                    rs_table[alloc_idx].valid <= 1'b1;
                    rs_table[alloc_idx].seq <= seq_ctr;

                    rs_table[alloc_idx].pc <= r_data.pc;
                    rs_table[alloc_idx].rob_index <= rob_index_in;

                    rs_table[alloc_idx].Opcode <= r_data.Opcode;
                    rs_table[alloc_idx].func3 <= r_data.func3;
                    rs_table[alloc_idx].func7 <= r_data.func7;

                    rs_table[alloc_idx].fu <= r_data.fu;
                    rs_table[alloc_idx].pd <= r_data.pd_new;

                    rs_table[alloc_idx].ps1 <= r_data.ps1;
                    rs_table[alloc_idx].ps2 <= r_data.ps2;

                    rs_table[alloc_idx].imm <= r_data.imm[31:0];

                    seq_ctr <= seq_ctr + 16'd1;
                end
            end
        end
    end

endmodule
