// Periférico de zumbador, dirección base 0x00010140.
// Registro único 00: escribir [2:0] = 0 silencio, 1 impacto, 2 fallo,
// 3 barco hundido, 4 colocación inválida, 5 victoria.
// Leer [2:0] devuelve el último evento y el bit 8 indica ocupado.
// Salida activa en alto; conectar un transductor externo con su manejador.
module Buzzer #(
    parameter integer FRECUENCIA_RELOJ_HZ = 100_000_000
) (
    input logic clk_i, input logic rst_i,
    input logic write_enable_i, input logic [1:0] addr_i,
    input logic [31:0] wdata_i, output logic [31:0] rdata_o,
    output logic zumbador_o
);
    localparam integer DIVISION_MS=(FRECUENCIA_RELOJ_HZ/1000<1)?1:FRECUENCIA_RELOJ_HZ/1000;
    localparam integer ANCHO_MS=(DIVISION_MS<2)?1:$clog2(DIVISION_MS);
    logic [ANCHO_MS-1:0] contador_ms;
    logic [15:0] duracion_ms, tiempo_transcurrido;
    logic [31:0] divisor_tono, contador_tono;
    logic tono;
    logic [31:0] registro_control;

    always_comb begin
        rdata_o=(addr_i==2'b00)?registro_control:32'b0;
        zumbador_o=tono && registro_control[8];
    end
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            contador_ms<='0; duracion_ms<=0; tiempo_transcurrido<=0;
            divisor_tono<=1; contador_tono<=0; tono<=0; registro_control<=0;
        end else begin
            if (write_enable_i && addr_i==2'b00) begin
                registro_control<=0;
                registro_control[2:0]<=(wdata_i[2:0]<=5)?wdata_i[2:0]:3'b000;
                registro_control[8]<=(wdata_i[2:0]!=0 && wdata_i[2:0]<=5);
                tiempo_transcurrido<=0;
                case (wdata_i[2:0])
                    1: begin duracion_ms<=180; divisor_tono<=FRECUENCIA_RELOJ_HZ/500; end
                    2: begin duracion_ms<=100; divisor_tono<=FRECUENCIA_RELOJ_HZ/250; end
                    3: begin duracion_ms<=420; divisor_tono<=FRECUENCIA_RELOJ_HZ/1000; end
                    4: begin duracion_ms<=260; divisor_tono<=FRECUENCIA_RELOJ_HZ/333; end
                    5: begin duracion_ms<=700; divisor_tono<=FRECUENCIA_RELOJ_HZ/500; end
                    default: begin duracion_ms<=0; divisor_tono<=1; end
                endcase
            end
            if (contador_ms==DIVISION_MS-1) begin
                contador_ms<=0;
                if (duracion_ms!=0) begin
                    if (tiempo_transcurrido+1>=duracion_ms) begin
                        duracion_ms<=0; registro_control[8]<=0; tono<=0;
                    end else tiempo_transcurrido<=tiempo_transcurrido+1'b1;
                    if (registro_control[2:0]==5)
                        divisor_tono<=((tiempo_transcurrido/100)%2)?FRECUENCIA_RELOJ_HZ/1000:FRECUENCIA_RELOJ_HZ/500;
                end
            end else contador_ms<=contador_ms+1'b1;
            if (registro_control[8]) begin
                if (contador_tono>=divisor_tono-1) begin contador_tono<=0; tono<=~tono; end
                else contador_tono<=contador_tono+1'b1;
            end else contador_tono<=0;
        end
    end
endmodule

