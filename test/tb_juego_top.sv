`timescale 1ns/1ps

// Prueba de integracion del juego sin depender de la VGA.
// Ejecutar con top.sv y todos los modulos de src cargados en Vivado Simulator.
module tb_juego_top #(
    parameter PROGRAM_FILE = "src/procesador/program.hex"
);
    localparam real CLK_PERIOD_NS = 10.0;
    localparam real UART_BIT_NS = 1.0e9 / 115200.0;

    logic clk_i = 1'b0;
    logic rst_n_i = 1'b0;
    logic [6:0] controles_i = 7'b0;
    logic [2:0] leds_estado_o;
    logic [7:0] segmentos_o, anodos_o;
    logic uart_rx_i = 1'b1;
    logic uart_tx_o, zumbador_o;

    logic [7:0] tx_frames [0:31][0:6];
    integer frame_count = 0;
    integer consumed_frames = 0;
    integer frame_idx;
    logic [7:0] rx_byte;
    logic stop_bit;

    top #(.PROGRAM_FILE(PROGRAM_FILE)) dut (
        .clk_i(clk_i), .rst_n_i(rst_n_i), .controles_i(controles_i),
        .leds_estado_o(leds_estado_o), .segmentos_o(segmentos_o),
        .anodos_o(anodos_o),
        .uart_rx_i(uart_rx_i), .uart_tx_o(uart_tx_o), .zumbador_o(zumbador_o)
    );

    always #(CLK_PERIOD_NS/2.0) clk_i = ~clk_i;

    // Decodifica las tramas 8N1 que transmite la FPGA.
    initial begin : monitor_fpga_uart
        forever begin
            @(negedge uart_tx_o);
            #(UART_BIT_NS * 1.5);
            for (int bit_index = 0; bit_index < 8; bit_index++) begin
                rx_byte[bit_index] = uart_tx_o;
                #(UART_BIT_NS);
            end
            stop_bit = uart_tx_o;
            if (stop_bit !== 1'b1)
                $fatal(1, "UART TX genero un bit de parada invalido");
            if (frame_count >= 32)
                $fatal(1, "Se excedio el buffer de tramas TX del testbench");
            tx_frames[frame_count][0] = rx_byte;
            for (int byte_index = 1; byte_index < 7; byte_index++) begin
                // Los bytes de una trama se transmiten consecutivamente; esperar
                // el siguiente bit de inicio y muestrear su byte.
                @(negedge uart_tx_o);
                #(UART_BIT_NS * 1.5);
                for (int bit_index = 0; bit_index < 8; bit_index++) begin
                    rx_byte[bit_index] = uart_tx_o;
                    #(UART_BIT_NS);
                end
                stop_bit = uart_tx_o;
                if (stop_bit !== 1'b1)
                    $fatal(1, "UART TX genero un bit de parada invalido");
                tx_frames[frame_count][byte_index] = rx_byte;
            end
            frame_count = frame_count + 1;
        end
    end

    task automatic press_button(input integer button_index);
        begin
            @(negedge clk_i);
            controles_i[button_index] = 1'b1;
            // El antirrebote de placa requiere 1,000,000 ciclos a 100 MHz.
            repeat (1_050_000) @(negedge clk_i);
            controles_i[button_index] = 1'b0;
            repeat (1_050_000) @(negedge clk_i);
        end
    endtask

    task automatic uart_send_byte(input logic [7:0] value);
        begin
            uart_rx_i = 1'b0;
            #(UART_BIT_NS);
            for (int bit_index = 0; bit_index < 8; bit_index++) begin
                uart_rx_i = value[bit_index];
                #(UART_BIT_NS);
            end
            uart_rx_i = 1'b1;
            #(UART_BIT_NS);
            // El receptor solo almacena un byte; espaciar bytes como la app PC.
            #2_000_000;
        end
    endtask

    task automatic uart_send_frame(
        input logic [7:0] message_type,
        input logic [7:0] d0, input logic [7:0] d1,
        input logic [7:0] d2, input logic [7:0] d3
    );
        logic [7:0] checksum;
        begin
            checksum = message_type ^ d0 ^ d1 ^ d2 ^ d3;
            uart_send_byte(8'hAA);
            uart_send_byte(message_type);
            uart_send_byte(d0);
            uart_send_byte(d1);
            uart_send_byte(d2);
            uart_send_byte(d3);
            uart_send_byte(checksum);
        end
    endtask

    task automatic expect_fpga_frame(
        input logic [7:0] message_type,
        input logic [7:0] d0, input logic [7:0] d1,
        input logic [7:0] d2, input logic [7:0] d3
    );
        logic [7:0] checksum;
        begin
            while (frame_count <= consumed_frames) @(posedge clk_i);
            frame_idx = consumed_frames;
            consumed_frames = consumed_frames + 1;
            checksum = message_type ^ d0 ^ d1 ^ d2 ^ d3;
            if (tx_frames[frame_idx][0] !== 8'hAA ||
                tx_frames[frame_idx][1] !== message_type ||
                tx_frames[frame_idx][2] !== d0 ||
                tx_frames[frame_idx][3] !== d1 ||
                tx_frames[frame_idx][4] !== d2 ||
                tx_frames[frame_idx][5] !== d3 ||
                tx_frames[frame_idx][6] !== checksum) begin
                $error("Trama FPGA inesperada en indice %0d: %02h %02h %02h %02h %02h %02h %02h",
                    frame_idx, tx_frames[frame_idx][0], tx_frames[frame_idx][1],
                    tx_frames[frame_idx][2], tx_frames[frame_idx][3],
                    tx_frames[frame_idx][4], tx_frames[frame_idx][5], tx_frames[frame_idx][6]);
                $fatal(1, "La trama UART no coincide con lo esperado");
            end
            $display("[%0t] UART FPGA -> PC: tipo %02h", $time, message_type);
        end
    endtask

    task automatic place_pc_ship(
        input logic [7:0] ship_id,
        input logic [7:0] row,
        input logic [7:0] column,
        input logic [7:0] orientation
    );
        begin
            uart_send_frame(8'h01, ship_id, row, column, orientation);
            expect_fpga_frame(8'h12, ship_id, 8'd1, 8'd0, 8'd0);
        end
    endtask

    initial begin : game_test
        // Libera el reset despues de permitir que todos los modulos se inicialicen.
        repeat (10) @(posedge clk_i);
        rst_n_i = 1'b1;
        repeat (20) @(posedge clk_i);

        // Inicio del juego con SW0 (control[4]).
        press_button(4);
        expect_fpga_frame(8'h11, 0, 0, 0, 0);

        // Jugador FPGA: barcos verticales de tamanos 2, 3 y 4.
        press_button(5); // barco 2 en la columna 0
        press_button(3); press_button(3); // mover a columna 2
        press_button(5); // barco 3
        press_button(3); press_button(3); // mover a columna 4
        press_button(5); // barco 4
        if (dut.u_data_mem.mem[64] !== 1 || dut.u_data_mem.mem[72] !== 1 ||
            dut.u_data_mem.mem[66] !== 2 || dut.u_data_mem.mem[74] !== 2 ||
            dut.u_data_mem.mem[82] !== 2 || dut.u_data_mem.mem[68] !== 3 ||
            dut.u_data_mem.mem[76] !== 3 || dut.u_data_mem.mem[84] !== 3 ||
            dut.u_data_mem.mem[92] !== 3)
            $fatal(1, "La colocacion de barcos del jugador FPGA no coincide con el tablero esperado");
        $display("[%0t] Colocacion del jugador FPGA correcta", $time);

        // Jugador PC: barcos horizontales sin traslape.
        place_pc_ship(0, 0, 4, 0); // dos celdas, indices 4 y 5
        place_pc_ship(1, 2, 0, 0); // tres celdas, indices 16..18
        place_pc_ship(2, 4, 0, 0); // cuatro celdas, indices 32..35
        if (dut.u_data_mem.mem[132] !== 1 || dut.u_data_mem.mem[133] !== 1 ||
            dut.u_data_mem.mem[144] !== 2 || dut.u_data_mem.mem[145] !== 2 ||
            dut.u_data_mem.mem[146] !== 2 || dut.u_data_mem.mem[160] !== 3 ||
            dut.u_data_mem.mem[161] !== 3 || dut.u_data_mem.mem[162] !== 3 ||
            dut.u_data_mem.mem[163] !== 3)
            $fatal(1, "La colocacion de barcos del jugador PC no coincide con el tablero esperado");
        $display("[%0t] Colocacion del jugador PC correcta", $time);

        // Ambos tableros estan listos: comienza la batalla y el turno 1.
        expect_fpga_frame(8'h13, 0, 0, 0, 0);
        expect_fpga_frame(8'h14, 1, 0, 0, 0);
        if (leds_estado_o !== 3'b010)
            $fatal(1, "El LED de estado no indica fase de batalla");

        // Jugador FPGA dispara a la celda (0,4), ocupada por la PC.
        press_button(5);
        expect_fpga_frame(8'h16, 0, 4, 1, 0);
        if (dut.u_data_mem.mem[132] !== 4)
            $fatal(1, "El impacto del jugador FPGA no se registro en RAM");
        expect_fpga_frame(8'h14, 2, 0, 0, 0);

        // La PC dispara a la celda (0,0), ocupada por el jugador FPGA.
        uart_send_frame(8'h02, 0, 0, 0, 0);
        expect_fpga_frame(8'h15, 0, 0, 1, 0);
        if (dut.u_data_mem.mem[64] !== 4)
            $fatal(1, "El impacto de la PC no se registro en RAM");
        $display("[%0t] PRUEBA GENERAL DEL JUEGO CORRECTA", $time);
        $finish;
    end

    initial begin : watchdog
        #2_000_000_000;
        $fatal(1, "Timeout del testbench general");
    end
endmodule
