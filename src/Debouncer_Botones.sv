// Periférico de botones del Jugador 1, dirección base 0x00010120.
// Registro único en dirección 00: bit 0 arriba, 1 abajo, 2 izquierda,
// 3 derecha, 4 seleccionar/girar, 5 confirmar, 6 reiniciar partida.
// Direcciones 01, 10 y 11 reservadas. Reinicio síncrono activo alto.
// Nexys 4: BTNU/BTND/BTNL/BTNR, SW0, SW1 y BTN C, respectivamente.
module Debouncer_Botones #(
    parameter integer CICLOS_ANTIRREBOTE = 1_000_000
) (
    input logic clk_i, input logic rst_i,
    input logic write_enable_i, input logic [1:0] addr_i,
    input logic [31:0] wdata_i, output logic [31:0] rdata_o,
    input logic [6:0] controles_i
);
    localparam integer ANCHO_CONTADOR = (CICLOS_ANTIRREBOTE < 2) ? 1 : $clog2(CICLOS_ANTIRREBOTE);
    (* ASYNC_REG = "TRUE" *) logic [6:0] sincronizador_meta;
    (* ASYNC_REG = "TRUE" *) logic [6:0] sincronizador;
    logic [ANCHO_CONTADOR-1:0] contador_estable [0:6];
    logic [31:0] registro_estado;
    integer indice;

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            sincronizador_meta <= '0;
            sincronizador <= '0;
            registro_estado <= '0;
            for (indice=0; indice<7; indice=indice+1)
                contador_estable[indice] <= '0;
        end else begin
            sincronizador_meta <= controles_i;
            sincronizador <= sincronizador_meta;
            for (indice=0; indice<7; indice=indice+1) begin
                if (sincronizador[indice] == registro_estado[indice])
                    contador_estable[indice] <= '0;
                else if (CICLOS_ANTIRREBOTE <= 1 || contador_estable[indice] == CICLOS_ANTIRREBOTE-1) begin
                    registro_estado[indice] <= sincronizador[indice];
                    contador_estable[indice] <= '0;
                end else contador_estable[indice] <= contador_estable[indice] + 1'b1;
            end
        end
    end

    always_comb begin
        rdata_o = 32'b0;
        if (addr_i == 2'b00) rdata_o = registro_estado;
    end
    // Periférico de solo lectura; las entradas de escritura se conservan
    // para mantener la interfaz estándar de 32 bits.
endmodule

