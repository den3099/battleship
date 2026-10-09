//------------------------------------------------------------------------------
// MODULO : UART_Baud_Gen
// FUNCION: Base de tiempo de la UART (sin cambios funcionales vs. la version VHDL).
//
// DESCRIPCION DETALLADA
//   Produce un pulso de UN ciclo de CLK (baud_tick) con frecuencia
//   16 x BAUD_RATE. Lo usan TX (cuenta 16 ticks por bit) y RX (muestrea 16
//   veces por bit para capturar en el centro).
//
//   Acumulador de fase (NCO):
//     cada CLK:  acc_next = acc_ + 16*BAUD_RATE
//     si acc_next >= CLK_FREQ_HZ -> baud_tick_=1 y acc_ = acc_next - CLK_FREQ_HZ
//   El promedio de ticks es exacto (16 MHz/115200/16 = 8.68 ciclos: unos
//   intervalos duran 8 y otros 9). Un divisor entero (9) daria 111111 baud.
//
//   baud_en = 0 -> acc_ en 0 y baud_tick en 0 (el generador se detiene).
//
// [CORRECCION 7] CLK_FREQ_HZ debe ser la frecuencia REAL del reloj de la placa.
//
// FLUJO: Control --baud_en--> [Baud_Gen] --baud_tick--> TX y RX
// REGISTROS (sufijo _): acc_, baud_tick_
//------------------------------------------------------------------------------
module UART_Baud_Gen #(
    parameter int CLK_FREQ_HZ = 16_000_000,   // <-- AJUSTAR al reloj de la placa
    parameter int BAUD_RATE   = 115_200
)(
    input  logic CLK,
    input  logic rst,          // reset sincrono, activo en 1
    input  logic baud_en,      // desde Control
    output logic baud_tick     // hacia TX y RX (16 x baud)
);

    localparam logic [31:0] STEP   = 32'(BAUD_RATE * 16);
    localparam logic [31:0] CLK_HZ = 32'(CLK_FREQ_HZ);

    logic [31:0] acc_      = 32'd0;
    logic        baud_tick_ = 1'b0;
    logic [31:0] acc_next;

    assign acc_next = acc_ + STEP;

    always_ff @(posedge CLK) begin
        if (rst || !baud_en) begin
            acc_       <= 32'd0;
            baud_tick_ <= 1'b0;
        end else if (acc_next >= CLK_HZ) begin
            acc_       <= acc_next - CLK_HZ;
            baud_tick_ <= 1'b1;                 // tick de 1 ciclo
        end else begin
            acc_       <= acc_next;
            baud_tick_ <= 1'b0;
        end
    end

    assign baud_tick = baud_tick_;

endmodule
