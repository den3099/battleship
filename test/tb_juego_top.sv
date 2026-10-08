`timescale 1ns/1ps

// Banco de pruebas de integracion para top. No depende de la VGA ni escribe
// en ella. Comprueba el arranque, colocacion de ambos tableros, disparos,
// hundimientos y el fin de juego con victoria/derrota usando UART y botones.
module tb_juego_top #(
    // XSim ejecuta desde <usuario>/Battleship/Battleship.sim/sim_1/behav/xsim.
    // Desde ahí esta ruta llega al program.hex de la carpeta compartida del
    // proyecto, sin espacios ni caracteres especiales en el parámetro de xelab.
    parameter string PROGRAM_FILE =
        "../../../../../Documents/ChatGPT/Battleship/src/procesador/program.hex"
);
    localparam integer CLK_FREQ_HZ = 100_000_000;
    localparam integer SIM_BAUD_RATE = 1_000_000;
    localparam integer SIM_DEBOUNCE_CYCLES = 8;
    localparam real CLK_PERIOD_NS = 10.0;
    localparam real UART_BIT_NS = 1.0e9 / SIM_BAUD_RATE;
    localparam integer WAIT_LIMIT = 20_000;

    logic clk_i = 1'b0;
    logic rst_n_i = 1'b0;
    logic [6:0] controles_i = 7'b0;
    logic [2:0] leds_estado_o;
    logic [7:0] segmentos_o, anodos_o;
    logic [4:0] video_o;
    logic uart_rx_i = 1'b1;
    logic uart_tx_o, zumbador_o;

    integer tests_run = 0;
    integer tests_passed = 0;
    integer tests_failed = 0;
    integer checks_in_case = 0;
    integer errors_in_case = 0;
    logic case_active = 1'b0;
    string current_case = "";
    logic simulation_done = 1'b0;
    logic [7:0] tx_stream [0:4095];
    logic tx_stop_stream [0:4095];
    integer tx_byte_count = 0;
    integer consumed_tx_bytes = 0;

    top #(
        .PROGRAM_FILE(PROGRAM_FILE),
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE(SIM_BAUD_RATE),
        .BUTTON_DEBOUNCE_CYCLES(SIM_DEBOUNCE_CYCLES)
    ) dut (
        .clk_i(clk_i), .rst_n_i(rst_n_i), .controles_i(controles_i),
        .leds_estado_o(leds_estado_o), .segmentos_o(segmentos_o),
        .anodos_o(anodos_o), .video_o(video_o), .uart_rx_i(uart_rx_i),
        .uart_tx_o(uart_tx_o), .zumbador_o(zumbador_o)
    );

    always #(CLK_PERIOD_NS/2.0) clk_i = ~clk_i;

    // Captura UART continuamente para no perder un byte cuya transmisión
    // empiece mientras el PC termina de enviar la última trama RX.
    initial begin : monitor_uart_tx
        logic [7:0] value;
        logic observed_stop;
        forever begin
            @(negedge uart_tx_o);
            #(UART_BIT_NS * 1.5);
            for (integer bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                value[bit_index] = uart_tx_o;
                #(UART_BIT_NS);
            end
            observed_stop = uart_tx_o;
            if (tx_byte_count < 4096) begin
                tx_stream[tx_byte_count] = value;
                tx_stop_stream[tx_byte_count] = observed_stop;
                tx_byte_count = tx_byte_count + 1;
            end
        end
    end

    task automatic report_check(input logic ok, input string label,
                                input string expected, input string observed);
        begin
            if (case_active) begin
                checks_in_case = checks_in_case + 1;
                if (ok !== 1'b1) begin
                    errors_in_case = errors_in_case + 1;
                    $display("  [DETALLE FAIL] %s | esperado=%s observado=%s",
                             label, expected, observed);
                end
            end
        end
    endtask

    task automatic begin_case(input string label);
        begin
            current_case = label;
            checks_in_case = 0;
            errors_in_case = 0;
            case_active = 1'b1;
            $display("\n[PRUEBA %0d] %s", tests_run + 1, current_case);
        end
    endtask

    task automatic finish_case(input string expected, input string observed);
        begin
            case_active = 1'b0;
            tests_run = tests_run + 1;
            if (errors_in_case == 0) begin
                tests_passed = tests_passed + 1;
                $display("[PASS %0d] %s | %s | validaciones=%0d",
                         tests_run, current_case, observed, checks_in_case);
            end else begin
                tests_failed = tests_failed + 1;
                $display("[FAIL %0d] %s | esperado=%s observado=%s | errores=%0d/%0d",
                         tests_run, current_case, expected, observed,
                         errors_in_case, checks_in_case);
            end
        end
    endtask

    task automatic wait_button(input integer index, input logic level,
                               output logic reached);
        integer cycles;
        begin
            reached = 1'b0;
            cycles = 0;
            while (!reached && cycles < 100) begin
                @(negedge clk_i);
                cycles = cycles + 1;
                reached = (dut.u_buttons.registro_estado[index] === level);
            end
        end
    endtask

    task automatic wait_cpu_button_read(input integer index, input logic level,
                                        output logic reached);
        integer cycles;
        begin
            reached = 1'b0;
            cycles = 0;
            while (!reached && cycles < WAIT_LIMIT) begin
                @(negedge clk_i);
                cycles = cycles + 1;
                if (dut.cpu_re && dut.cpu_addr === 32'h0001_0120 &&
                    dut.rdata_buttons[index] === level)
                    reached = 1'b1;
            end
        end
    endtask

    // La lectura del bus aparece antes de que la instruccion termine de
    // actualizar el registro software s4/x20. Esperarlo evita que dos pulsos
    // consecutivos se fusionen para el detector de flanco del firmware.
    task automatic wait_cpu_button_latched(input integer index, input logic level,
                                           output logic reached);
        integer cycles;
        begin
            reached = 1'b0;
            cycles = 0;
            while (!reached && cycles < WAIT_LIMIT) begin
                @(negedge clk_i);
                cycles = cycles + 1;
                reached = (dut.u_cpu.dp.u_regfile.regs[20][index] === level);
            end
        end
    endtask

    task automatic press_game_button(input integer index,
                                      input integer target_register,
                                      input logic [31:0] target_value,
                                      input string action_label);
        logic reached_local;
        begin
            @(negedge clk_i);
            controles_i[index] = 1'b1;
            wait_button(index, 1'b1, reached_local);
            report_check(reached_local,
                         $sformatf("Antirrebote acepta boton %0d", index), "estado=1",
                         $sformatf("estado=%b", dut.u_buttons.registro_estado[index]));
            if (reached_local) begin
                wait_cpu_button_read(index, 1'b1, reached_local);
                report_check(reached_local,
                             $sformatf("CPU lee boton %0d presionado", index), "bit=1",
                             $sformatf("estado=%07b", dut.rdata_buttons[6:0]));
                if (reached_local) begin
                    wait_cpu_button_latched(index, 1'b1, reached_local);
                    report_check(reached_local,
                                 $sformatf("Firmware registra boton %0d presionado", index),
                                 "s4/x20.bit=1",
                                 $sformatf("s4/x20=%08h", dut.u_cpu.dp.u_regfile.regs[20]));
                end
            end
            // Mantiene el botón activo hasta que el firmware registre la
            // acción, evitando soltarlo antes de que la FSM de software actúe.
            if (reached_local && target_register >= 0)
                expect_cpu_register(target_register, target_value, action_label);
            else if (reached_local) begin
                // Para acciones cuyo registro no cambia (p. ej. disparar),
                // deja tiempo al firmware para procesar el evento. La trama
                // UART posterior valida el resultado observable de la acción.
                repeat (1000) @(negedge clk_i);
                report_check(1'b1, action_label, "evento procesado por CPU",
                             "boton estable durante 1000 ciclos");
            end else
                report_check(1'b0, action_label, $sformatf("%0d", target_value),
                             "el antirrebote/CPU no acepto el boton");
            controles_i[index] = 1'b0;
            wait_button(index, 1'b0, reached_local);
            report_check(reached_local,
                         $sformatf("Antirrebote libera boton %0d", index), "estado=0",
                         $sformatf("estado=%b", dut.u_buttons.registro_estado[index]));
            if (reached_local) begin
                wait_cpu_button_read(index, 1'b0, reached_local);
                report_check(reached_local,
                             $sformatf("CPU lee boton %0d liberado", index), "bit=0",
                             $sformatf("estado=%07b", dut.rdata_buttons[6:0]));
                if (reached_local && index != 5) begin
                    wait_cpu_button_latched(index, 1'b0, reached_local);
                    report_check(reached_local,
                                 $sformatf("Firmware registra boton %0d liberado", index),
                                 "s4/x20.bit=0",
                                 $sformatf("s4/x20=%08h", dut.u_cpu.dp.u_regfile.regs[20]));
                end
            end
        end
    endtask

    task automatic expect_cpu_register(input integer index,
                                       input logic [31:0] expected,
                                       input string label);
        logic [31:0] observed;
        integer cycles;
        begin
            observed = dut.u_cpu.dp.u_regfile.regs[index];
            cycles = 0;
            while (observed !== expected && cycles < WAIT_LIMIT) begin
                @(negedge clk_i);
                cycles = cycles + 1;
                observed = dut.u_cpu.dp.u_regfile.regs[index];
            end
            report_check(observed === expected, label,
                         $sformatf("%0d", expected),
                         $sformatf("%0d tras %0d ciclos", observed, cycles));
        end
    endtask

    task automatic expect_ram_word(input integer index,
                                   input logic [31:0] expected,
                                   input string label);
        logic [31:0] observed;
        integer cycles;
        begin
            observed = dut.u_data_mem.mem[index];
            cycles = 0;
            while (observed !== expected && cycles < WAIT_LIMIT) begin
                @(negedge clk_i);
                cycles = cycles + 1;
                observed = dut.u_data_mem.mem[index];
            end
            report_check(observed === expected, label,
                         $sformatf("%0d", expected),
                         $sformatf("%0d (RAM[%0d], %0d ciclos)", observed, index, cycles));
        end
    endtask

    task automatic print_cpu_debug(input string label);
        begin
            $display("[DEBUG %s] PCF=%08h PCD=%08h InstrD=%08h addr=%08h WE=%b WD=%08h funct3=%03b",
                     label, dut.u_cpu.dp.PCF, dut.u_cpu.dp.PCD,
                     dut.u_cpu.dp.InstrD, dut.cpu_addr, dut.cpu_we,
                     dut.cpu_wdata, dut.cpu_funct3);
            $display("[DEBUG %s] s1/x9=%0d cursor/s5/x21=%0d baseJ1/s6/x22=%08h a0/x10=%08h t3=%08h t4=%08h t5=%08h",
                     label, dut.u_cpu.dp.u_regfile.regs[9],
                     dut.u_cpu.dp.u_regfile.regs[21],
                     dut.u_cpu.dp.u_regfile.regs[22],
                     dut.u_cpu.dp.u_regfile.regs[10],
                     dut.u_cpu.dp.u_regfile.regs[28],
                     dut.u_cpu.dp.u_regfile.regs[29],
                     dut.u_cpu.dp.u_regfile.regs[30]);
            $display("[DEBUG %s] botones=%07b s4/x20=%08h RAM64=%08h RAM66=%08h RAM68=%08h RAM72=%08h RAM74=%08h RAM76=%08h",
                     label, dut.u_buttons.registro_estado[6:0],
                     dut.u_cpu.dp.u_regfile.regs[20],
                     dut.u_data_mem.mem[64], dut.u_data_mem.mem[66],
                     dut.u_data_mem.mem[68], dut.u_data_mem.mem[72],
                     dut.u_data_mem.mem[74], dut.u_data_mem.mem[76]);
        end
    endtask

    task automatic uart_send_byte(input logic [7:0] value);
        begin
            uart_rx_i = 1'b0;
            #(UART_BIT_NS);
            for (integer bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                uart_rx_i = value[bit_index];
                #(UART_BIT_NS);
            end
            uart_rx_i = 1'b1;
            #(UART_BIT_NS);
            repeat (200) @(negedge clk_i);
        end
    endtask

    task automatic uart_send_frame(input logic [7:0] message_type,
                                   input logic [7:0] d0, d1, d2, d3);
        logic [7:0] checksum;
        begin
            checksum = message_type ^ d0 ^ d1 ^ d2 ^ d3;
            $display("[UART PC->FPGA] AA %02h %02h %02h %02h %02h",
                     message_type, d0, d1, d2, d3);
            uart_send_byte(8'hAA);
            uart_send_byte(message_type);
            uart_send_byte(d0);
            uart_send_byte(d1);
            uart_send_byte(d2);
            uart_send_byte(d3);
            uart_send_byte(checksum);
        end
    endtask

    task automatic expect_tx_frame(input logic [7:0] message_type,
                                   input logic [7:0] d0, d1, d2, d3,
                                   input string label,
                                   output logic frame_ok);
        logic [7:0] expected [0:6];
        logic [7:0] checksum;
        integer base_index;
        integer cycles;
        begin
            checksum = message_type ^ d0 ^ d1 ^ d2 ^ d3;
            expected[0] = 8'hAA;
            expected[1] = message_type;
            expected[2] = d0;
            expected[3] = d1;
            expected[4] = d2;
            expected[5] = d3;
            expected[6] = checksum;
            frame_ok = 1'b0;
            base_index = consumed_tx_bytes;
            cycles = 0;
            while ((tx_byte_count < base_index + 7) && cycles < WAIT_LIMIT) begin
                @(negedge clk_i);
                cycles = cycles + 1;
            end
            frame_ok = (tx_byte_count >= base_index + 7);
            if (frame_ok) begin
                frame_ok = 1'b1;
                for (integer frame_byte = 0; frame_byte < 7; frame_byte = frame_byte + 1) begin
                    if (tx_stream[base_index + frame_byte] !== expected[frame_byte] ||
                        tx_stop_stream[base_index + frame_byte] !== 1'b1) begin
                        frame_ok = 1'b0;
                        $display("  [UART MISMATCH] %s byte%0d esperado=%02h observado=%02h stop=%b",
                                 label, frame_byte, expected[frame_byte],
                                 tx_stream[base_index + frame_byte],
                                 tx_stop_stream[base_index + frame_byte]);
                    end
                end
                consumed_tx_bytes = base_index + 7;
            end else begin
                $display("  [UART TIMEOUT] %s: llegaron %0d de 7 bytes",
                         label, tx_byte_count - base_index);
                // Descarta bytes parciales para que el siguiente diagnóstico
                // empiece desde el primer byte nuevo observado.
                consumed_tx_bytes = tx_byte_count;
            end
            if (frame_ok) begin
                report_check(1'b1, label,
                             $sformatf("AA %02h %02h %02h %02h %02h %02h",
                                       message_type,d0,d1,d2,d3,checksum),
                             "trama completa y checksum correcto");
            end else begin
                report_check(1'b0, label,
                             $sformatf("AA %02h %02h %02h %02h %02h %02h",
                                       message_type,d0,d1,d2,d3,checksum),
                             "bytes/stop/checksum no coinciden");
            end
        end
    endtask

    // En batalla el firmware vuelve a anunciar TURN mientras espera botones.
    // Descarta solo esas tramas repetidas, validando su formato, hasta hallar
    // el evento esperado (por ejemplo SHOT_RECEIVED).
    task automatic expect_tx_frame_after_turns(input logic [7:0] message_type,
                                               input logic [7:0] d0, d1, d2, d3,
                                               input logic [7:0] turn_player,
                                               input string label,
                                               output logic frame_ok);
        logic [7:0] expected_turn_checksum;
        logic turn_ok;
        logic done;
        integer skipped_turns;
        integer cycles;
        begin
            expected_turn_checksum = 8'h14 ^ turn_player;
            skipped_turns = 0;
            done = 1'b0;
            frame_ok = 1'b0;
            while (!done) begin
                cycles = 0;
                while ((tx_byte_count < consumed_tx_bytes + 7) &&
                       cycles < WAIT_LIMIT) begin
                    @(negedge clk_i);
                    cycles = cycles + 1;
                end

                if (tx_byte_count < consumed_tx_bytes + 7) begin
                    $display("  [UART TIMEOUT] %s: no llegó la trama esperada", label);
                    report_check(1'b0, label, "trama UART esperada", "timeout");
                    consumed_tx_bytes = tx_byte_count;
                    done = 1'b1;
                end else if (tx_stream[consumed_tx_bytes] == 8'hAA &&
                             tx_stream[consumed_tx_bytes+1] == 8'h14 &&
                             tx_stream[consumed_tx_bytes+2] == turn_player) begin
                    turn_ok = (tx_stream[consumed_tx_bytes+3] == 0) &&
                              (tx_stream[consumed_tx_bytes+4] == 0) &&
                              (tx_stream[consumed_tx_bytes+5] == 0) &&
                              (tx_stream[consumed_tx_bytes+6] == expected_turn_checksum);
                    for (integer b = 0; b < 7; b = b + 1)
                        if (tx_stop_stream[consumed_tx_bytes+b] !== 1'b1)
                            turn_ok = 1'b0;
                    if (turn_ok)
                        report_check(1'b1, "Trama TURN repetida mientras espera",
                                     $sformatf("AA 14 %02h 00 00 00 %02h",
                                               turn_player, expected_turn_checksum),
                                     "trama TURN valida");
                    else
                        report_check(1'b0, "Trama TURN repetida mientras espera",
                                     $sformatf("AA 14 %02h 00 00 00 %02h",
                                               turn_player, expected_turn_checksum),
                                     "trama TURN corrupta");
                    consumed_tx_bytes = consumed_tx_bytes + 7;
                    skipped_turns = skipped_turns + 1;
                end else begin
                    expect_tx_frame(message_type, d0, d1, d2, d3,
                                    label, frame_ok);
                    done = 1'b1;
                end
            end
            if (skipped_turns > 0)
                $display("  [UART] %0d anuncios TURN=%0d repetidos validados", 
                         skipped_turns, turn_player);
        end
    endtask

    task automatic move_battle_cursor_to(input integer target_cell);
        integer current_cell;
        integer current_row;
        integer current_col;
        integer target_row;
        integer target_col;
        begin
            current_cell = dut.u_cpu.dp.u_regfile.regs[21];
            target_row = target_cell / 8;
            target_col = target_cell % 8;
            $display("  [CURSOR] movimiento de celda %0d a celda %0d",
                     current_cell, target_cell);

            current_row = current_cell / 8;
            while (current_row < target_row) begin
                current_cell = current_cell + 8;
                press_game_button(1, 21, current_cell,
                                  $sformatf("Cursor baja a celda %0d", current_cell));
                current_row = current_row + 1;
            end
            while (current_row > target_row) begin
                current_cell = current_cell - 8;
                press_game_button(0, 21, current_cell,
                                  $sformatf("Cursor sube a celda %0d", current_cell));
                current_row = current_row - 1;
            end

            current_col = current_cell % 8;
            while (current_col < target_col) begin
                current_cell = current_cell + 1;
                press_game_button(3, 21, current_cell,
                                  $sformatf("Cursor derecha a celda %0d", current_cell));
                current_col = current_col + 1;
            end
            while (current_col > target_col) begin
                current_cell = current_cell - 1;
                press_game_button(2, 21, current_cell,
                                  $sformatf("Cursor izquierda a celda %0d", current_cell));
                current_col = current_col - 1;
            end
        end
    endtask

    // Ejecuta un impacto de J1 y, salvo que gane la partida, hace que J2
    // responda con un disparo fallido para devolver el turno a J1.
    task automatic j1_hit_for_victory(input integer cell_index,
                                      input logic [7:0] row,
                                      input logic [7:0] col,
                                      input logic [7:0] hit_result,
                                      input logic [31:0] ram_value,
                                      input integer miss_column,
                                      input logic final_hit);
        logic frame_ok;
        begin
            move_battle_cursor_to(cell_index);
            $display("  [J1] Dispara a fila=%0d columna=%0d (celda=%0d)",
                     row, col, cell_index);

            press_game_button(5, -1, 0,
                              $sformatf("J1 dispara a (%0d,%0d)", row, col));
            expect_tx_frame_after_turns(8'h16, row, col, hit_result, 0, 8'd1,
                                        $sformatf("Impacto J1 (%0d,%0d)", row, col),
                                        frame_ok);
            expect_ram_word(128 + cell_index, ram_value,
                            $sformatf("RAM J2 celda (%0d,%0d)", row, col));
            if (hit_result == 2)
                $display("  [HUNDIDO] J1 hunde barco al acertar (%0d,%0d)", row, col);
            else
                $display("  [IMPACTO] J1 acierta (%0d,%0d); el barco sigue a flote", row, col);

            if (!final_hit) begin
                expect_tx_frame(8'h14, 8'd2, 0, 0, 0, "TURN J2", frame_ok);
                uart_send_frame(8'h02, 8'd7, miss_column[7:0], 0, 0);
                expect_tx_frame(8'h15, 8'd7, miss_column[7:0], 0, 0,
                                "Disparo fallido de J2", frame_ok);
                expect_tx_frame(8'h14, 8'd1, 0, 0, 0, "TURN vuelve a J1", frame_ok);
                wait_cpu_button_latched(5, 1'b0, frame_ok);
                $display("  [J2] Dispara a (7,%0d): agua; turno vuelve a J1", miss_column);
                report_check(frame_ok,
                             "Firmware rearma BTNC para el siguiente disparo",
                             "s4/x20.bit5=0",
                             $sformatf("s4/x20=%08h", dut.u_cpu.dp.u_regfile.regs[20]));
            end
        end
    endtask

    initial begin : run_game_test
        logic reached;
        logic tx_start_seen;

        $display("============================================================");
        $display("INICIO tb_juego_top | sin pruebas VGA");
        $display("ROM: %s", PROGRAM_FILE);
        $display("Baud UART=%0d | debounce=%0d ciclos", SIM_BAUD_RATE,
                 SIM_DEBOUNCE_CYCLES);
        $display("============================================================");

        begin_case("Arranque, reset y mensaje PLACEMENT_START");
        #1;
        report_check(dut.u_cpu.dp.u_imem.mem[0] === 32'h0030_0113,
                     "ROM cargada", "mem[0]=00300113",
                     $sformatf("mem[0]=%08h", dut.u_cpu.dp.u_imem.mem[0]));
        if (dut.u_cpu.dp.u_imem.mem[0] !== 32'h0030_0113) begin
            $display("[ABORT] ROM ausente/incorrecta. Corrige PROGRAM_FILE antes de seguir.");
            finish_case("ROM valida e inicio UART", "ROM ausente/incorrecta");
            print_summary();
            simulation_done = 1'b1;
            $finish;
        end

        repeat (10) @(posedge clk_i);
        rst_n_i = 1'b1;
        repeat (100) @(posedge clk_i);
        report_check(leds_estado_o === 3'b001, "LED de colocacion tras reset",
                     "001", $sformatf("%03b", leds_estado_o));

        // SW0 (bit 4) inicia el firmware y debe producir AA 11 00 00 00 00 11.
        @(negedge clk_i);
        controles_i[4] = 1'b1;
        wait_button(4, 1'b1, reached);
        report_check(reached, "Antirrebote acepta SW0", "estado=1",
                     $sformatf("estado=%b", dut.u_buttons.registro_estado[4]));
        tx_start_seen = 1'b0;
        if (reached) begin
            wait_cpu_button_read(4, 1'b1, reached);
            report_check(reached, "CPU lee SW0 presionado", "bit 4=1",
                         $sformatf("estado=%07b", dut.rdata_buttons[6:0]));
            repeat (100) @(negedge clk_i);
            controles_i[4] = 1'b0;
            wait_button(4, 1'b0, reached);
            report_check(reached, "Antirrebote libera SW0", "estado=0",
                         $sformatf("estado=%b", dut.u_buttons.registro_estado[4]));

            expect_tx_frame(8'h11, 0, 0, 0, 0, "PLACEMENT_START", tx_start_seen);

            if (!tx_start_seen) begin
                $display("[DEBUG CPU] PCF=%08h PCD=%08h InstrD=%08h addr=%08h re=%b rdata=%08h",
                         dut.u_cpu.dp.PCF, dut.u_cpu.dp.PCD, dut.u_cpu.dp.InstrD,
                         dut.cpu_addr, dut.cpu_re, dut.cpu_rdata);
                $display("[DEBUG BTN] controles=%07b estado=%07b s4/x20=%08h",
                         controles_i, dut.u_buttons.registro_estado[6:0],
                         dut.u_cpu.dp.u_regfile.regs[20]);
                $display("[DEBUG UART] estado=%08h tx_req=%b tx_activo=%b tx_busy=%b tx_data=%02h tx=%b",
                         dut.rdata_uart,
                         dut.u_uart.u_registros.solicitar_tx_,
                         dut.u_uart.u_control.activar_tx_,
                         dut.u_uart.u_control.tx_busy_,
                         dut.u_uart.u_registros.tx_data_, uart_tx_o);
            end

        end else begin
            report_check(1'b0, "Inicio UART de PLACEMENT_START",
                         "flanco de inicio", "SW0 no llego a estado estable");
        end
        if (tx_start_seen)
            finish_case("LED=001 y trama AA 11 ... 11",
                        "LED de colocacion y PLACEMENT_START correctos");
        else
            finish_case("LED=001 y trama AA 11 ... 11",
                        "no se recibio PLACEMENT_START");

        // Continúa solo si se observó la primera trama del firmware.
        if (tx_start_seen) begin
            begin_case("Colocacion de los tres barcos de J1 por botones");
            repeat (100) @(negedge clk_i);
            expect_cpu_register(9, 2, "J1 inicia con barco de tamano 2");
            expect_cpu_register(21, 0, "Cursor J1 inicia en celda 0");

            // J1 coloca los barcos verticales en las columnas 0, 2 y 4.
            press_game_button(5, 9, 3, "J1 confirma barco 1 (tamano 2)");
            expect_ram_word(64, 1, "J1 barco 1: celda (0,0)");
            expect_ram_word(72, 1, "J1 barco 1: celda (1,0)");

            press_game_button(3, 21, 1, "Cursor J1 llega a columna 1");
            press_game_button(3, 21, 2, "Cursor J1 llega a columna 2");
            press_game_button(5, 9, 4, "J1 confirma barco 2 (tamano 3)");
            expect_ram_word(66, 2, "J1 barco 2: celda (0,2)");
            expect_ram_word(74, 2, "J1 barco 2: celda (1,2)");
            expect_ram_word(82, 2, "J1 barco 2: celda (2,2)");

            press_game_button(3, 21, 3, "Cursor J1 llega a columna 3");
            press_game_button(3, 21, 4, "Cursor J1 llega a columna 4");
            press_game_button(5, 9, 5, "J1 confirma barco 3 (tamano 4)");
            expect_ram_word(68, 3, "J1 barco 3: celda (0,4)");
            expect_ram_word(76, 3, "J1 barco 3: celda (1,4)");
            expect_ram_word(84, 3, "J1 barco 3: celda (2,4)");
            expect_ram_word(92, 3, "J1 barco 3: celda (3,4)");

            if (errors_in_case != 0)
                print_cpu_debug("J1 colocacion; revisar antes de batalla");

            finish_case("cursor 0,2,4 y nueve celdas correctas en RAM J1",
                        $sformatf("cursor=%0d tamano_siguiente=%0d; RAM J1 verificada",
                                  dut.u_cpu.dp.u_regfile.regs[21],
                                  dut.u_cpu.dp.u_regfile.regs[9]));

            // J2 coloca por UART barcos horizontales de tamanos 2, 3 y 4.
            begin_case("Colocacion UART de los barcos de J2 y sus ACK");
            uart_send_frame(8'h01, 8'd0, 8'd0, 8'd4, 8'd0);
            expect_tx_frame(8'h12, 8'd0, 8'd1, 8'd0, 8'd0,
                           "ACK colocacion J2 barco 0", reached);
            uart_send_frame(8'h01, 8'd1, 8'd2, 8'd0, 8'd0);
            expect_tx_frame(8'h12, 8'd1, 8'd1, 8'd0, 8'd0,
                           "ACK colocacion J2 barco 1", reached);
            uart_send_frame(8'h01, 8'd2, 8'd4, 8'd0, 8'd0);
            expect_tx_frame(8'h12, 8'd2, 8'd1, 8'd0, 8'd0,
                           "ACK colocacion J2 barco 2", reached);

            expect_ram_word(132, 1, "J2 barco 1: celda (0,4)");
            expect_ram_word(133, 1, "J2 barco 1: celda (0,5)");
            expect_ram_word(144, 2, "J2 barco 2: celda (2,0)");
            expect_ram_word(145, 2, "J2 barco 2: celda (2,1)");
            expect_ram_word(146, 2, "J2 barco 2: celda (2,2)");
            expect_ram_word(160, 3, "J2 barco 3: celda (4,0)");
            expect_ram_word(161, 3, "J2 barco 3: celda (4,1)");
            expect_ram_word(162, 3, "J2 barco 3: celda (4,2)");
            expect_ram_word(163, 3, "J2 barco 3: celda (4,3)");

            finish_case("3 ACK tipo 12 y nueve celdas correctas en RAM J2",
                        "ACKs y RAM J2 verificados");

            if (tests_failed == 0) begin
                begin_case("Transicion a batalla, BATTLE_START y turno J1");
                expect_tx_frame(8'h13, 0, 0, 0, 0, "BATTLE_START", reached);
                expect_tx_frame(8'h14, 8'd1, 0, 0, 0, "Turno inicial J1", reached);
                report_check(leds_estado_o === 3'b010, "LED indica fase de batalla",
                             "010", $sformatf("%03b", leds_estado_o));
                finish_case("BATTLE_START, TURN=J1 y LED=010",
                            $sformatf("LED=%03b; tramas de inicio correctas", leds_estado_o));

                // J1 dispara a (0,4), ocupada por el primer barco de J2.
                begin_case("Disparo de J1: impacto en J2 y cambio de turno");
                press_game_button(5, -1, 0, "J1 confirma disparo");
                // El firmware anuncia TURN al inicio de cada iteracion de
                // fase_partida. Tras el TURN inicial puede emitir otra trama
                // TURN=J1 antes de procesar el boton de disparo.
                expect_tx_frame(8'h14, 8'd1, 0, 0, 0,
                                "TURN J1 antes de procesar disparo", reached);
                expect_tx_frame(8'h16, 8'd0, 8'd4, 8'd1, 8'd0,
                                "SHOT_RECEIVED impacto J1", reached);
                expect_ram_word(132, 4, "J2 celda (0,4) marcada como impacto");
                expect_tx_frame(8'h14, 8'd2, 0, 0, 0, "Turno cambia a J2", reached);
                finish_case("SHOT_RECEIVED impacto y TURN=J2; RAM J2[0,4]=4",
                            "trama de impacto, celda y turno verificados");

                // J2 dispara a (0,0), ocupada por el primer barco de J1.
                begin_case("Disparo de J2 por UART: impacto en J1");
                uart_send_frame(8'h02, 8'd0, 8'd0, 8'd0, 8'd0);
                expect_tx_frame(8'h15, 8'd0, 8'd0, 8'd1, 8'd0,
                                "SHOT_RESULT impacto J2", reached);
                expect_ram_word(64, 4, "J1 celda (0,0) marcada como impacto");
                expect_tx_frame(8'h14, 8'd1, 0, 0, 0,
                                "Turno vuelve a J1", reached);
                wait_cpu_button_latched(5, 1'b0, reached);
                report_check(reached,
                             "Firmware rearma BTNC tras el disparo de J1",
                             "s4/x20.bit5=0",
                             $sformatf("s4/x20=%08h", dut.u_cpu.dp.u_regfile.regs[20]));
                finish_case("SHOT_RESULT impacto y RAM J1[0,0]=4",
                            "respuesta UART y celda impactada verificadas");

                begin_case("Victoria J1, derrota J2, barco hundido y GAME_OVER");
                // Los impactos acumulados cubren los 9 segmentos de J2:
                // (0,4) ya fue alcanzado en la prueba anterior; faltan estos 8.
                j1_hit_for_victory(5,  0, 5, 2, 4, 7, 0); // hunde barco de 2
                j1_hit_for_victory(16, 2, 0, 1, 5, 6, 0);
                j1_hit_for_victory(17, 2, 1, 1, 5, 5, 0);
                j1_hit_for_victory(18, 2, 2, 2, 5, 4, 0); // hunde barco de 3
                j1_hit_for_victory(32, 4, 0, 1, 6, 3, 0);
                j1_hit_for_victory(33, 4, 1, 1, 6, 2, 0);
                j1_hit_for_victory(34, 4, 2, 1, 6, 1, 0);
                j1_hit_for_victory(35, 4, 3, 2, 6, 0, 1); // victoria total
                expect_tx_frame(8'h17, 8'd1, 0, 0, 8'd12,
                                "GAME_OVER: gana J1 y pierde J2", reached);
                $display("  [GAME OVER] ganador=J1, derrotado=J2, barcos hundidos=3");
                report_check(leds_estado_o === 3'b100,
                             "LED de partida terminada", "100",
                             $sformatf("%03b", leds_estado_o));
                expect_ram_word(1, 1, "Contador de victorias J1");
                expect_ram_word(2, 0, "Contador de victorias J2");
                finish_case("GAME_OVER ganador=J1, 9 impactos, LED=100 y marcador 1-0",
                            "J1 victoria; J2 derrota; 3 barcos hundidos");
            end else begin
                $display("[SKIP] Batalla: no se inicia porque las pruebas de colocacion J1 fallaron.");
            end
        end

        $display("");
        print_summary();
        simulation_done = 1'b1;
        $finish;
    end

    task automatic print_summary;
        begin
            $display("============================================================");
            $display("RESUMEN tb_juego_top: ejecutadas=%0d correctas=%0d errores=%0d",
                     tests_run, tests_passed, tests_failed);
            if (tests_failed == 0)
                $display("RESULTADO: TODAS LAS PRUEBAS PASARON");
            else
                $display("RESULTADO: REVISAR LAS LINEAS [FAIL]");
            $display("============================================================");
        end
    endtask

    initial begin : watchdog
        #10_000_000;
        if (!simulation_done) begin
            tests_run = tests_run + 1;
            tests_failed = tests_failed + 1;
            $display("[WATCHDOG] La simulacion excedio 10 ms; revisar ROM/UART.");
            print_summary();
            simulation_done = 1'b1;
            $finish;
        end
    end
endmodule
