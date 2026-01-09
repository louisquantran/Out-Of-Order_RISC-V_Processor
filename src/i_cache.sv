module i_cache (
    input  logic [31:0] address,
    output logic [31:0] instruction
);
    logic [7:0] instr_mem_hex [0:2207];
    logic [31:0] instr_mem [0:551];

    initial begin
        $readmemh("jswr.mem", instr_mem_hex);
        for (logic [9:0] i = 0; i <= 551; i++) begin
            automatic int base = i * 4;
            instr_mem[i] = {
                instr_mem_hex[base+3],
                instr_mem_hex[base+2],
                instr_mem_hex[base+1],
                instr_mem_hex[base]
            };
        end
    end
        
    assign instruction = instr_mem[address >> 2];
endmodule
