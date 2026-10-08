`timescale 1ns / 1ps

module mux_arbitro_tb();

    // Declaración de señales
    logic [2:0]  select_i;
    logic [31:0] rdata_mem;
    logic [31:0] rdata_displays;
    logic [31:0] rdata_buzzer;
    logic [31:0] rdata_btns;
    logic [31:0] rdata_pc;
    logic [31:0] rdata_vga;
    logic [31:0] DataIn_o;

    // Contador de errores
    integer errores = 0;
    logic [31:0] valor_esperado;

    // Instancia del módulo a probar (DUT - Device Under Test)
    mux_arbitro dut (
        .select_i(select_i),
        .rdata_mem(rdata_mem),
        .rdata_displays(rdata_displays),
        .rdata_buzzer(rdata_buzzer),
        .rdata_btns(rdata_btns),
        .rdata_pc(rdata_pc),
        .rdata_vga(rdata_vga),
        .DataIn_o(DataIn_o)
    );

    // Bloque inicial de pruebas
    initial begin
        $display("==================================================");
        $display("   Iniciando Testbench de Mux Arbitro...");
        $display("==================================================");

        // Inicializar entradas de datos con patrones reconocibles
        rdata_mem      = 32'h1111_1111;
        rdata_displays = 32'h2222_2222;
        rdata_buzzer   = 32'h3333_3333;
        rdata_btns     = 32'h4444_4444;
        rdata_pc       = 32'h5555_5555;
        rdata_vga      = 32'h6666_6666;

        // Bucle para probar cada uno de los selectores posibles
        for (int i = 0; i < 8; i++) begin
            select_i = i[2:0];
            
            // Determinar el valor esperado internamente en el testbench
            case (select_i)
                3'b000: valor_esperado = rdata_mem;
                3'b001: valor_esperado = rdata_displays;
                3'b010: valor_esperado = rdata_buzzer;
                3'b011: valor_esperado = rdata_btns;
                3'b100: valor_esperado = rdata_pc;
                3'b101: valor_esperado = rdata_vga;
                default: valor_esperado = 32'h0000_0000;
            endcase

            #10; // Esperar un tiempo para la propagación combinacional

            // Autochequeo
            if (DataIn_o !== valor_esperado) begin
                $display("[ERROR] Select = %0b. Se esperaba %h pero se obtuvo %h", select_i, valor_esperado, DataIn_o);
                errores++;
            end else begin
                $display("[OK] Select = %0b. Salida correcta: %h", select_i, DataIn_o);
            end
        end

        // Reporte final
        $display("==================================================");
        if (errores == 0) begin
            $display(" [EXITO] Todas las pruebas pasaron sin errores.");
        end else begin
            $display(" [FALLO] Se encontraron %0d errores.", errores);
        end
        $display("==================================================");
        $finish;
    end

endmodule