`timescale 1ns/1ps
//------------------------------------------------------------------------------
// TESTBENCH : tb_UART_Top  (solo simulacion)  [CORRECCION 5]
//
// FASE 1 - LOOPBACK: tx_fisico -> rx_fisico. Escribe bytes en 0x0001_0044,
//          espera RX_VALID (ESTADO bit 3), lee 0x0001_0048 (genera rx_leido)
//          y compara. Prueba el rearme del RX.
// FASE 2 - COMPORTAMIENTO DE LA PC: un "pc_send_byte" a 115200 8N1 envia la
//          trama HELLO de batalla_pc.py (AA 03 00 00 00 00 03), UN byte a la
//          vez con pausa de 2 ms (--gap-ms del .py), y el "CPU" lee cada byte.
// FASE 3 - ERROR DE TRAMA: byte con stop invalido -> NO debe subir RX_VALID,
//          debe marcar error (ESTADO bit 4); se limpia escribiendo 0x2 en
//          0x0001_0040 y luego el RX recibe un byte bueno (sigue vivo).
// Resultado final en la consola TCL: "PRUEBA OK" o "PRUEBA CON ERRORES".
//------------------------------------------------------------------------------
module tb_UART_Top;

    localparam real CLK_PERIOD_NS = 62.5;                 // 16 MHz
    localparam real BIT_NS        = 1.0e9 / 115200.0;     // 8680.56 ns

    localparam logic [31:0] ADDR_CTRL = 32'h0001_0040;
    localparam logic [31:0] ADDR_TX   = 32'h0001_0044;
    localparam logic [31:0] ADDR_RX   = 32'h0001_0048;

    logic        CLK = 1'b0;
    logic        rst = 1'b1;
    logic [31:0] addr_i  = 32'd0;
    logic [31:0] wdata_i = 32'd0;
    logic        we_UART = 1'b0;
    logic        re_UART = 1'b0;
    logic [31:0] rdata_pc;
    logic        rx_fisico, tx_fisico;
    logic        rx_pc = 1'b1;           // linea que maneja la "PC"
    logic        loopback_en = 1'b1;
    int          errors = 0;

    assign rx_fisico = loopback_en ? tx_fisico : rx_pc;

    UART_Top #(.CLK_FREQ_HZ(16_000_000), .BAUD_RATE(115_200)) dut (
        .CLK(CLK), .rst(rst),
        .addr_i(addr_i), .wdata_i(wdata_i),
        .we_UART(we_UART), .re_UART(re_UART), .rdata_pc(rdata_pc),
        .rx_fisico(rx_fisico), .tx_fisico(tx_fisico)
    );

    always #(CLK_PERIOD_NS / 2.0) CLK = ~CLK;

    // ---------------- tareas de bus (el "RISC-V") ----------------
    task automatic bus_write(input logic [31:0] a, input logic [31:0] d);
        @(posedge CLK); #1;
        addr_i = a; wdata_i = d; we_UART = 1'b1;
        @(posedge CLK); #1;
        we_UART = 1'b0;
    endtask

    task automatic bus_read(input logic [31:0] a, output logic [31:0] d);
        @(posedge CLK); #1;
        addr_i = a; re_UART = 1'b1;
        #5; d = rdata_pc;                 // lectura combinacional
        @(posedge CLK); #1;
        re_UART = 1'b0;
    endtask

    task automatic check(input string msg, input logic cond);
        if (!cond) begin
            errors++;
            $error("FALLO: %s", msg);
        end
    endtask

    // Sondea ESTADO hasta que el bit idx valga val
    task automatic wait_status(input int idx, input logic val,
                               input int max_polls, output logic ok);
        logic [31:0] s;
        int n;
        n = 0; ok = 1'b0;
        while ((n < max_polls) && !ok) begin
            bus_read(ADDR_CTRL, s);
            if (s[idx] === val) ok = 1'b1;
            n++;
        end
    endtask

    // ---------------- la "PC": envia un byte 8N1 a 115200 ----------------
    task automatic pc_send_byte(input logic [7:0] b, input logic bad_stop);
        rx_pc = 1'b0; #(BIT_NS);                       // start
        for (int i = 0; i < 8; i++) begin              // datos LSB primero
            rx_pc = b[i]; #(BIT_NS);
        end
        if (bad_stop) begin                            // stop invalido
            rx_pc = 1'b0; #(0.6 * BIT_NS);
            rx_pc = 1'b1; #(0.4 * BIT_NS);
        end else begin
            rx_pc = 1'b1; #(BIT_NS);                   // stop
        end
    endtask

    // ---------------- FASE 1: un byte por loopback ----------------
    task automatic send_and_check(input logic [7:0] b);
        logic [31:0] s, d;
        logic ok;
        wait_status(0, 1'b0, 50000, ok);  check("TX libre", ok);
        bus_write(ADDR_TX, {24'd0, b});
        wait_status(3, 1'b1, 50000, ok);  check("RX_VALID tras loopback", ok);
        bus_read(ADDR_CTRL, s);           check("sin error de trama", s[4] == 1'b0);
        bus_read(ADDR_RX, d);             // esta lectura genera rx_leido
        check("dato recibido == enviado", d[7:0] == b);
        $display("[%0t] loopback 0x%02h -> 0x%02h", $time, b, d[7:0]);
        repeat (4) @(posedge CLK);
    endtask

    // ---------------- secuencia principal ----------------
    logic [7:0]  hello [0:6] = '{8'hAA, 8'h03, 8'h00, 8'h00, 8'h00, 8'h00, 8'h03};
    logic [31:0] s, d;
    logic        ok;

    initial begin
        rst = 1'b1;
        repeat (10) @(posedge CLK);
        #1 rst = 1'b0;
        repeat (10) @(posedge CLK);

        bus_read(ADDR_CTRL, s);
        check("activar_rx=1 tras reset", s[7] == 1'b1);

        // FASE 1
        send_and_check(8'hA5);
        send_and_check(8'h3C);          // RX rearmado
        send_and_check(8'h00);
        send_and_check(8'hFF);

        // FASE 2: trama HELLO desde la "PC", 1 byte a la vez, pausa 2 ms
        loopback_en = 1'b0;
        rx_pc = 1'b1;
        repeat (20) @(posedge CLK);
        for (int i = 0; i < 7; i++) begin
            pc_send_byte(hello[i], 1'b0);
            wait_status(3, 1'b1, 1000, ok);  check("RX_VALID por byte de la PC", ok);
            bus_read(ADDR_RX, d);
            check("byte de HELLO correcto", d[7:0] == hello[i]);
            $display("[%0t] PC->FPGA byte %0d = 0x%02h", $time, i, d[7:0]);
            #2000000;                    // 2 ms (--gap-ms)
        end

        // FASE 3: stop invalido -> descartado + error marcado
        pc_send_byte(8'h55, 1'b1);
        #(2.0 * BIT_NS);
        bus_read(ADDR_CTRL, s);
        check("byte con stop invalido NO sube RX_VALID", s[3] == 1'b0);
        check("error de trama marcado",                  s[4] == 1'b1);
        bus_write(ADDR_CTRL, 32'h0000_0002);             // clr_error
        repeat (4) @(posedge CLK);
        bus_read(ADDR_CTRL, s);
        check("error limpiado", s[4] == 1'b0);

        // recuperacion: el RX sigue funcionando
        pc_send_byte(8'h3C, 1'b0);
        wait_status(3, 1'b1, 1000, ok);  check("RX vivo tras error", ok);
        bus_read(ADDR_RX, d);
        check("byte posterior al error correcto", d[7:0] == 8'h3C);

        if (errors == 0) $display("PRUEBA OK");
        else             $display("PRUEBA CON ERRORES: %0d", errors);
        $finish;
    end

    // watchdog (200 ms)
    initial begin
        #200000000;
        $error("Timeout de simulacion");
        $finish;
    end

endmodule
