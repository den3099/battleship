module Instr_mem #(
    parameter DEPTH = 2048,
    parameter string INIT_FILE = "src/procesador/program.hex"
)(
    input  logic [31:0] A,     // Dirección (PC)
    output logic [31:0] RD     // Instrucción
);

    localparam integer ADDR_WIDTH = (DEPTH < 2) ? 1 : $clog2(DEPTH);
    logic [31:0] mem [0:DEPTH-1];
    logic [ADDR_WIDTH-1:0] word_index;

    // ROM de instrucciones byte-addressed desde el vector de reset 0x0.
    assign word_index = A[ADDR_WIDTH+1:2];
    assign RD = (A < DEPTH*4) ? mem[word_index] : 32'h0000_0013;

    initial begin
        for (int i = 0; i < DEPTH; i++) begin
            mem[i] = 32'h00000013;
        end

        $readmemh(INIT_FILE, mem);
    end
endmodule
