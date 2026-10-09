//------------------------------------------------------------------------------
// MODULO : UART_Top
// FUNCION: Integra los 5 bloques del diagrama (solo conexiones, sin logica).
//
// CAMBIOS vs. VHDL [CORRECCION 4]: bus de 32 bits, se agrega re_UART y la
// salida de lectura rdata_pc[31:0].
//
// INTERCONEXION
//   Registros --solicitar_tx, rx_leido, clr_error--> Control
//   Control   --activar_rx, estados[4:0]----------> Registros
//   Registros --tx_data[7:0]---------------------> TX
//   RX        --rx_data[7:0]----------------------> Registros
//   Control   --activar_tx--> TX      TX --tx_done--> Control
//   Control   --rx_enable---> RX
//   RX        --solicitar_rx, rx_frame_err--------> Control
//   Control   --baud_en-----> Baud_Gen --baud_tick--> TX y RX
//
// Pines: rx_fisico <- pin TX del puente USB-UART ; tx_fisico -> pin RX del puente
//        (cruce que debe quedar correcto en el .xdc).
// [CORRECCION 7] Ajustar CLK_FREQ_HZ al reloj real de la placa.
//------------------------------------------------------------------------------
module UART_Top #(
    parameter int CLK_FREQ_HZ = 16_000_000,   // <-- AJUSTAR
    parameter int BAUD_RATE   = 115_200
)(
    input  logic        CLK,
    input  logic        rst,
    // bus del RISC-V
    input  logic [31:0] addr_i,
    input  logic [31:0] wdata_i,
    input  logic        we_UART,
    input  logic        re_UART,
    output logic [31:0] rdata_pc,
    // pines serie
    input  logic        rx_fisico,
    output logic        tx_fisico
);

    logic       solicitar_tx, rx_leido, clr_error;
    logic       activar_rx;
    logic [4:0] estados;
    logic [7:0] tx_data, rx_data;
    logic       activar_tx, tx_done;
    logic       rx_enable, solicitar_rx, rx_frame_err;
    logic       baud_en, baud_tick;

    UART_Registros u_registros (
        .CLK(CLK), .rst(rst),
        .addr_i(addr_i), .wdata_i(wdata_i),
        .we_UART(we_UART), .re_UART(re_UART), .rdata_pc(rdata_pc),
        .solicitar_tx(solicitar_tx), .rx_leido(rx_leido), .clr_error(clr_error),
        .activar_rx(activar_rx), .estados(estados),
        .rx_data(rx_data), .tx_data(tx_data)
    );

    UART_Control u_control (
        .CLK(CLK), .rst(rst),
        .solicitar_tx(solicitar_tx), .rx_leido(rx_leido), .clr_error(clr_error),
        .activar_rx(activar_rx), .estados(estados),
        .tx_done(tx_done), .activar_tx(activar_tx),
        .solicitar_rx(solicitar_rx), .rx_frame_err(rx_frame_err),
        .rx_enable(rx_enable),
        .baud_en(baud_en)
    );

    UART_Baud_Gen #(.CLK_FREQ_HZ(CLK_FREQ_HZ), .BAUD_RATE(BAUD_RATE)) u_baud (
        .CLK(CLK), .rst(rst), .baud_en(baud_en), .baud_tick(baud_tick)
    );

    UART_TX_Core u_tx (
        .CLK(CLK), .rst(rst),
        .activar_tx(activar_tx), .baud_tick(baud_tick),
        .tx_data(tx_data), .tx_done(tx_done), .tx_fisico(tx_fisico)
    );

    UART_RX_Core u_rx (
        .CLK(CLK), .rst(rst),
        .rx_enable(rx_enable), .baud_tick(baud_tick), .rx_fisico(rx_fisico),
        .rx_data(rx_data),
        .solicitar_rx(solicitar_rx), .rx_frame_err(rx_frame_err)
    );

endmodule
