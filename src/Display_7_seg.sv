// Periférico de cuatro dígitos decimales, dirección base 0x00010130.
// Registro 00: victorias P1 en [7:0], victorias P2 en [15:8], valores 0..99.
// Direcciones restantes reservadas. Segmentos {CA..CG,DP} y ánodos activos bajos.
module Display_7_seg #(
    parameter integer FRECUENCIA_RELOJ_HZ = 100_000_000,
    parameter integer REFRESCO_DIGITO_HZ = 1_000
) (
    input logic clk_i, input logic rst_i,
    input logic write_enable_i, input logic [1:0] addr_i,
    input logic [31:0] wdata_i, output logic [31:0] rdata_o,
    output logic [7:0] segmentos_o, output logic [7:0] anodos_o
);
    localparam integer DIVISION_BARRIDO = (FRECUENCIA_RELOJ_HZ/(REFRESCO_DIGITO_HZ*4) < 1) ? 1 : FRECUENCIA_RELOJ_HZ/(REFRESCO_DIGITO_HZ*4);
    localparam integer ANCHO_DIVISION = (DIVISION_BARRIDO < 2) ? 1 : $clog2(DIVISION_BARRIDO);
    logic [31:0] registro_datos;
    logic [ANCHO_DIVISION-1:0] contador_barrido;
    logic [1:0] digito;
    logic [3:0] valor_digito;
    logic [6:0] segmentos_encendidos;

    always_comb begin
        rdata_o = (addr_i==2'b00) ? registro_datos : 32'b0;
    end
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            registro_datos<='0; contador_barrido<='0; digito<='0;
        end else begin
            if (write_enable_i && addr_i==2'b00) begin
                registro_datos <= {16'b0,
                    ((wdata_i[15:8]>99) ? 8'd99 : wdata_i[15:8]),
                    ((wdata_i[7:0]>99) ? 8'd99 : wdata_i[7:0])};
            end
            if (contador_barrido==DIVISION_BARRIDO-1) begin
                contador_barrido<='0; digito<=digito+1'b1;
            end else contador_barrido<=contador_barrido+1'b1;
        end
    end
    always_comb begin
        case (digito)
            0: valor_digito=registro_datos[7:0]%10;
            1: valor_digito=(registro_datos[7:0]/10)%10;
            2: valor_digito=registro_datos[15:8]%10;
            default: valor_digito=(registro_datos[15:8]/10)%10;
        endcase
        case (valor_digito)
            0: segmentos_encendidos=7'b1111110; 1: segmentos_encendidos=7'b0110000;
            2: segmentos_encendidos=7'b1101101; 3: segmentos_encendidos=7'b1111001;
            4: segmentos_encendidos=7'b0110011; 5: segmentos_encendidos=7'b1011011;
            6: segmentos_encendidos=7'b1011111; 7: segmentos_encendidos=7'b1110000;
            8: segmentos_encendidos=7'b1111111; 9: segmentos_encendidos=7'b1111011;
            default: segmentos_encendidos=7'b0000000;
        endcase
        segmentos_o={~segmentos_encendidos,1'b1};
        anodos_o=8'hFF;
        anodos_o[digito]=1'b0;
    end
endmodule

