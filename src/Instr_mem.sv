module Instr_mem #(
    parameter DEPTH = 256
)(
    input  logic [31:0] A,     // Dirección (PC)
    output logic [31:0] RD     // Instrucción
);

    logic [31:0] mem [0:DEPTH-1];

    // Lectura combinacional
    assign RD = mem[A[31:2]];

//Pongo esto temporalmente para hacer una prueba rápida. Luego lo reemplazo por la lectura de un archivo con el programa a ejecutar.
    initial begin
        for (int i = 0; i < DEPTH; i++) begin
            mem[i] = 32'h00000013;
        end

        $readmemh("sim/program.hex", mem);
    end

    // Inicialización (para simulación)
    //initial begin
    //    $readmemh("sim/program.hex", mem);
    //end

endmodule