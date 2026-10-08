module reg_file(
    input  logic clk,
    input  logic WE3,
    input  logic [4:0] A1, A2, A3,
    input  logic [31:0] WD3,
    output logic [31:0] RD1D, RD2D
);

    logic [31:0] regs [0:31];

    // Bypass WB->Decode: una instruccion puede leer un registro en el mismo
    // flanco en que la instruccion anterior lo escribe. Sin este bypass, el
    // registro decode/execute puede capturar el valor previo (p. ej. t4 en la
    // rutina de colocacion de barcos), aunque la escritura WB ocurra en ese
    // mismo ciclo.
    assign RD1D = (A1 == 5'd0) ? 32'b0 :
                  ((WE3 && (A1 == A3) && (A3 != 5'd0)) ? WD3 : regs[A1]);
    assign RD2D = (A2 == 5'd0) ? 32'b0 :
                  ((WE3 && (A2 == A3) && (A3 != 5'd0)) ? WD3 : regs[A2]);

    always_ff @(posedge clk) begin
        if (WE3 && (A3 != 5'd0)) begin
            regs[A3] <= WD3;
        end
    end

    initial begin
    integer i;
    for (i = 0; i < 32; i++) begin
        regs[i] = 0;
    end
end

endmodule
