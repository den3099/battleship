`timescale 1ns/1ps
`default_nettype none
// Afirmacion asincrona; liberacion sincronizada en cada dominio de reloj.
module reset_sincrono (
    input  wire clk_i,
    input  wire reset_async_i,
    output wire reset_o
);
    (* ASYNC_REG = "TRUE" *) logic [1:0] etapas = 2'b11;
    always_ff @(posedge clk_i or posedge reset_async_i) begin
        if (reset_async_i) etapas <= 2'b11;
        else               etapas <= {etapas[0], 1'b0};
    end
    assign reset_o = etapas[1];
endmodule
`default_nettype wire
