// Integracion de la CPU y los perifericos para la Nexys 4.
// La interfaz de framebuffer VGA se conserva para enlazar el modulo VGA
// cuando se integre; temporalmente su salida de video queda en negro.
module top #(
    parameter PROGRAM_FILE = "src/procesador/program.hex"
)(
    input  logic       clk_i,
    input  logic       rst_n_i,
    input  logic [6:0] controles_i,
    output logic [2:0] leds_estado_o,
    output logic [7:0] segmentos_o,
    output logic [7:0] anodos_o,
    output logic [4:0] video_o,
    input  logic       uart_rx_i,
    output logic       uart_tx_o,
    output logic       zumbador_o
);
    logic rst;
    logic [31:0] cpu_rdata, cpu_wdata, cpu_addr;
    logic cpu_we, cpu_re;
    logic [2:0] cpu_funct3;
    logic [2:0] select;
    logic we_mem, we_display, we_buzzer, we_buttons;
    logic we_pc, we_vga, we_uart, we_led;
    logic [31:0] rdata_mem, rdata_display, rdata_buzzer;
    logic [31:0] rdata_buttons, rdata_uart, rdata_vga, rdata_led;
    logic [1:0] reg_addr;

    assign rst = ~rst_n_i;
    assign reg_addr = cpu_addr[1:0];

    cpu #(.PROGRAM_FILE(PROGRAM_FILE)) u_cpu (
        .clk(clk_i), .rst(rst),
        .DataIn_i(cpu_rdata), .DataOut_o(cpu_wdata),
        .DataAddress_o(cpu_addr), .we_o(cpu_we), .re_o(cpu_re),
        .funct3_o(cpu_funct3)
    );

    traductor_direcciones u_address_decoder (
        .we_o(cpu_we), .DataAddress_i(cpu_addr), .select_o(select),
        .we_mem(we_mem), .we_displays(we_display), .we_buzzer(we_buzzer),
        .we_btns(we_buttons), .we_pc(we_pc), .we_vga(we_vga),
        .we_uart(we_uart), .we_led(we_led)
    );

    data_mem u_data_mem (
        .funct3M(cpu_funct3), .clk(clk_i), .WE(we_mem),
        .A(cpu_addr), .WD(cpu_wdata), .ReadDataM(rdata_mem)
    );

    Display_7_seg #(.FRECUENCIA_RELOJ_HZ(100_000_000)) u_display (
        .clk_i(clk_i), .rst_i(rst), .write_enable_i(we_display),
        .addr_i(reg_addr), .wdata_i(cpu_wdata), .rdata_o(rdata_display),
        .segmentos_o(segmentos_o), .anodos_o(anodos_o)
    );

    Buzzer #(.FRECUENCIA_RELOJ_HZ(100_000_000)) u_buzzer (
        .clk_i(clk_i), .rst_i(rst), .write_enable_i(we_buzzer),
        .addr_i(reg_addr), .wdata_i(cpu_wdata), .rdata_o(rdata_buzzer),
        .zumbador_o(zumbador_o)
    );

    Debouncer_Botones u_buttons (
        .clk_i(clk_i), .rst_i(rst), .write_enable_i(we_buttons),
        .addr_i(reg_addr), .wdata_i(cpu_wdata), .rdata_o(rdata_buttons),
        .controles_i(controles_i)
    );

    LED_Estado u_status_leds (
        .clk_i(clk_i), .rst_i(rst), .write_enable_i(we_led),
        .addr_i(reg_addr), .wdata_i(cpu_wdata), .rdata_o(rdata_led),
        .leds_o(leds_estado_o)
    );

    UART_Top #(.CLK_FREQ_HZ(100_000_000), .BAUD_RATE(115_200)) u_uart (
        .CLK(clk_i), .rst(rst), .addr_i(cpu_addr), .wdata_i(cpu_wdata),
        .we_UART(we_uart), .re_UART(cpu_re && select == 3'b100),
        .rdata_pc(rdata_uart), .rx_fisico(uart_rx_i), .tx_fisico(uart_tx_o)
    );

    // El framebuffer VGA del compañero se conectará aquí. Mantener el puerto
    // permite usar el XDC actual mientras ese módulo todavía no está integrado.
    assign rdata_vga = 32'b0;
    assign video_o = 5'b0;

    mux_arbitro u_read_mux (
        .select_i(select), .rdata_mem(rdata_mem),
        .rdata_displays(rdata_display), .rdata_buzzer(rdata_buzzer),
        .rdata_btns(rdata_buttons), .rdata_uart(rdata_uart),
        .rdata_vga(rdata_vga), .rdata_led(rdata_led), .DataIn_o(cpu_rdata)
    );
endmodule
