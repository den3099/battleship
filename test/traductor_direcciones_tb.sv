`timescale 1ns / 1ps

module traductor_direcciones_tb();

    // Señales de entrada
    logic        we_o;
    logic [31:0] DataAddress_i;

    // Señales de salida
    logic [2:0]  select_o;
    logic        we_mem;
    logic        we_displays;
    logic        we_buzzer;
    logic        we_btns;
    logic        we_pc;
    logic        we_vga;

    integer errores = 0;

    // Instancia del módulo (DUT)
    traductor_direcciones dut (
        .we_o(we_o),
        .DataAddress_i(DataAddress_i),
        .select_o(select_o),
        .we_mem(we_mem),
        .we_displays(we_displays),
        .we_buzzer(we_buzzer),
        .we_btns(we_btns),
        .we_pc(we_pc),
        .we_vga(we_vga)
    );

    // Tarea reutilizable para inyectar un escenario y auto-chequear
    // vector_we_esperado: {mem, displays, buzzer, btns, pc, vga}
    task test_traductor(
        input logic [31:0] addr,
        input logic we_in,
        input logic [2:0]  sel_esperado,
        input logic [5:0]  vector_we_esperado, 
        input string nombre_prueba
    );
        begin
            DataAddress_i = addr;
            we_o = we_in;
            #10; // Espera para propagación

            // Empaquetar las salidas we reales para fácil comparación
            automatic logic [5:0] we_reales = {we_mem, we_displays, we_buzzer, we_btns, we_pc, we_vga};

            if (select_o !== sel_esperado || we_reales !== vector_we_esperado) begin
                $display("[ERROR] %s | Addr: %h, WE: %b", nombre_prueba, addr, we_in);
                $display("        Esperado -> Sel: %b, WEs(M,D,Bz,Bt,P,V): %b", sel_esperado, vector_we_esperado);
                $display("        Obtenido -> Sel: %b, WEs(M,D,Bz,Bt,P,V): %b", select_o, we_reales);
                errores++;
            end else begin
                $display("[OK] %s", nombre_prueba);
            end
        end
    endtask

    initial begin
        $display("=============================================================");
        $display("   Iniciando Testbench de Traductor de Direcciones...");
        $display("=============================================================");

        // --- PRUEBAS DE MEMORIA (Bit 16 = 0) ---
        // addr, we, select_esperado, WEs_esperados: {mem, disp, buzz, btns, pc, vga}, nombre
        test_traductor(32'h0000_1234, 1'b0, 3'b000, 6'b000000, "Lectura Memoria");
        test_traductor(32'h0000_FFFF, 1'b1, 3'b000, 6'b100000, "Escritura Memoria");

        // --- PRUEBAS DE PERIFÉRICOS (Bit 16 = 1) ---
        
        // VGA (0x1000 a 0x17FF)
        test_traductor(32'h0001_1000, 1'b1, 3'b101, 6'b000001, "Escritura VGA Límite Inferior");
        test_traductor(32'h0001_1450, 1'b0, 3'b101, 6'b000000, "Lectura VGA Dentro del Rango");
        test_traductor(32'h0001_17FF, 1'b1, 3'b101, 6'b000001, "Escritura VGA Límite Superior");

        // UART PC (0x0040, 0x0044, 0x0048)
        test_traductor(32'h0001_0040, 1'b1, 3'b100, 6'b000010, "Escritura UART PC Control/Estado");
        test_traductor(32'h0001_0044, 1'b1, 3'b100, 6'b000010, "Escritura UART PC Datos TX");
        test_traductor(32'h0001_0048, 1'b0, 3'b100, 6'b000000, "Lectura UART PC Datos RX");

        // BTNS (0x0120)
        test_traductor(32'h0001_0120, 1'b0, 3'b011, 6'b000000, "Lectura Botones");

        // DISPLAYS (0x0130, 0x0138)
        test_traductor(32'h0001_0130, 1'b1, 3'b001, 6'b010000, "Escritura Display 7 Segmentos");
        test_traductor(32'h0001_0138, 1'b1, 3'b001, 6'b010000, "Escritura Display LED Estado");

        // BUZZER (0x0140)
        test_traductor(32'h0001_0140, 1'b1, 3'b010, 6'b001000, "Escritura Buzzer");

        // PERIFÉRICO NO REGISTRADO
        test_traductor(32'h0001_9999, 1'b1, 3'b111, 6'b000000, "Caso Default");

        $display("=============================================================");
        if (errores == 0) begin
            $display(" [EXITO] Todas las pruebas pasaron sin errores.");
        end else begin
            $display(" [FALLO] Se encontraron %0d errores.", errores);
        end
        $display("=============================================================");
        
        $finish;
    end

endmodule