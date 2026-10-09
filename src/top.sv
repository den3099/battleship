// Integracion de la CPU y los perifericos para la Nexys 4.
// Integracion VGA: solo este modulo original fue modificado.
// video_o = {R[3:0], G[3:0], B[3:0], HS, VS}; usar el XDC adjunto.
module top #(
    parameter string PROGRAM_FILE = "src/procesador/program.hex",
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer BAUD_RATE = 115_200,
    parameter integer BUTTON_DEBOUNCE_CYCLES = 1_000_000
)(
    input  logic       clk_i,
    input  logic       rst_n_i,
    input  logic [6:0] controles_i,
    output logic [2:0] leds_estado_o,
    output logic [7:0] segmentos_o,
    output logic [7:0] anodos_o,
    output logic [13:0] video_o,
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

    // El sistema conserva su reloj de 100 MHz; solo los pixeles usan 25 MHz.
    // Recursos nativos de Artix-7: no requieren generar un IP Clocking Wizard.
    wire clk_pixel_raw, clk_pixel;
    wire clk_vga_feedback_raw, clk_vga_feedback;
    wire vga_locked;
    wire rst_vga;
    wire [4:0] screen_vga;

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

    Display_7_seg #(.FRECUENCIA_RELOJ_HZ(CLK_FREQ_HZ)) u_display (
        .clk_i(clk_i), .rst_i(rst), .write_enable_i(we_display),
        .addr_i(reg_addr), .wdata_i(cpu_wdata), .rdata_o(rdata_display),
        .segmentos_o(segmentos_o), .anodos_o(anodos_o)
    );

    Buzzer #(.FRECUENCIA_RELOJ_HZ(CLK_FREQ_HZ)) u_buzzer (
        .clk_i(clk_i), .rst_i(rst), .write_enable_i(we_buzzer),
        .addr_i(reg_addr), .wdata_i(cpu_wdata), .rdata_o(rdata_buzzer),
        .zumbador_o(zumbador_o)
    );

    Debouncer_Botones #(.CICLOS_ANTIRREBOTE(BUTTON_DEBOUNCE_CYCLES)) u_buttons (
        .clk_i(clk_i), .rst_i(rst), .write_enable_i(we_buttons),
        .addr_i(reg_addr), .wdata_i(cpu_wdata), .rdata_o(rdata_buttons),
        .controles_i(controles_i)
    );

    LED_Estado u_status_leds (
        .clk_i(clk_i), .rst_i(rst), .write_enable_i(we_led),
        .addr_i(reg_addr), .wdata_i(cpu_wdata), .rdata_o(rdata_led),
        .leds_o(leds_estado_o)
    );

    UART_Top #(.CLK_FREQ_HZ(CLK_FREQ_HZ), .BAUD_RATE(BAUD_RATE)) u_uart (
        .CLK(clk_i), .rst(rst), .addr_i(cpu_addr), .wdata_i(cpu_wdata),
        .we_UART(we_uart), .re_UART(cpu_re && select == 3'b100),
        .rdata_pc(rdata_uart), .rx_fisico(uart_rx_i), .tx_fisico(uart_tx_o)
    );

    // MMCM: 100 MHz * 10 / 40 = 25 MHz; VCO = 1000 MHz.
    // Fase de 45 grados a 25 MHz = 5 ns nominales: separa los flancos
    // de lectura de video de las escrituras CPU (cada 10 ns).
    // La separacion fisica se debe confirmar con timing en Vivado.
    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKIN1_PERIOD(10.0),
        .DIVCLK_DIVIDE(1),
        .CLKFBOUT_MULT_F(10.0),
        .CLKFBOUT_PHASE(0.0),
        .CLKOUT0_DIVIDE_F(40.0),
        .CLKOUT0_DUTY_CYCLE(0.5),
        .CLKOUT0_PHASE(45.0),
        .STARTUP_WAIT("FALSE")
    ) u_vga_mmcm (
        .CLKIN1(clk_i),
        .CLKFBIN(clk_vga_feedback),
        .CLKFBOUT(clk_vga_feedback_raw),
        .CLKFBOUTB(),
        .CLKOUT0(clk_pixel_raw), .CLKOUT0B(),
        .CLKOUT1(), .CLKOUT1B(),
        .CLKOUT2(), .CLKOUT2B(),
        .CLKOUT3(), .CLKOUT3B(),
        .CLKOUT4(), .CLKOUT5(), .CLKOUT6(),
        .LOCKED(vga_locked),
        .PWRDWN(1'b0), .RST(rst)
    );

    BUFG u_vga_feedback_buf (
        .I(clk_vga_feedback_raw), .O(clk_vga_feedback)
    );
    BUFG u_vga_pixel_buf (
        .I(clk_pixel_raw), .O(clk_pixel)
    );

    // Los dos sincronizadores de reset ya estan dentro de periferico_vga.
    // LOCKED solo retiene al VGA; los demas perifericos mantienen su reset.
    assign rst_vga = rst || !vga_locked;

    periferico_vga #(.BASE_ADDR(32'h0001_1000)) u_vga (
        .clk_i(clk_i), .clk_25(clk_pixel), .rst_i(rst_vga),
        .addr_i(cpu_addr), .wdata_i(cpu_wdata), .we_vga(we_vga),
        .rdata_o(rdata_vga), .screen_o(screen_vga)
    );

    // El periferico entrega RGB de un bit por canal. Replicar cada bit
    // alimenta los cuatro pines de cada DAC de la Nexys 4 (8 colores).
    assign video_o = {{4{screen_vga[4]}}, {4{screen_vga[3]}},
                      {4{screen_vga[2]}}, screen_vga[1:0]};

    mux_arbitro u_read_mux (
        .select_i(select), .rdata_mem(rdata_mem),
        .rdata_displays(rdata_display), .rdata_buzzer(rdata_buzzer),
        .rdata_btns(rdata_buttons), .rdata_uart(rdata_uart),
        .rdata_vga(rdata_vga), .rdata_led(rdata_led), .DataIn_o(cpu_rdata)
    );
endmodule
