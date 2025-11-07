module ICache (
    input  logic [31:0] address,
    output logic [31:0] instruction
);
    logic [31:0] instr_mem [0:551];

    initial begin
        $readmemh("program.mem", instr_mem);
    end
    
    assign instruction = instr_mem[address >> 2];
endmodule
