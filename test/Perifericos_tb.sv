`timescale 1ns/1ps
module Perifericos_tb;
    logic reloj=0;
    always #5 reloj=~reloj;
    logic reinicio=1;

    logic [1:0] direccion_display=0;
    logic escritura_display=0;
    logic [31:0] dato_escritura_display=0, dato_lectura_display;
    logic [7:0] segmentos, anodos;
    Display_7_seg #(.FRECUENCIA_RELOJ_HZ(40), .REFRESCO_DIGITO_HZ(2)) visualizador (
        .clk_i(reloj), .rst_i(reinicio), .write_enable_i(escritura_display),
        .addr_i(direccion_display), .wdata_i(dato_escritura_display),
        .rdata_o(dato_lectura_display), .segmentos_o(segmentos), .anodos_o(anodos)
    );

    logic escritura_led=0;
    logic [1:0] direccion_led=0;
    logic [31:0] dato_escritura_led=0, dato_lectura_led;
    logic [2:0] leds;
    LED_Estado indicador(.clk_i(reloj), .rst_i(reinicio),
        .write_enable_i(escritura_led), .addr_i(direccion_led),
        .wdata_i(dato_escritura_led), .rdata_o(dato_lectura_led), .leds_o(leds));

    logic escritura_zumbador=0;
    logic [1:0] direccion_zumbador=0;
    logic [31:0] dato_escritura_zumbador=0, dato_lectura_zumbador;
    logic salida_zumbador;
    Buzzer #(.FRECUENCIA_RELOJ_HZ(1000)) avisador(.clk_i(reloj), .rst_i(reinicio),
        .write_enable_i(escritura_zumbador), .addr_i(direccion_zumbador),
        .wdata_i(dato_escritura_zumbador), .rdata_o(dato_lectura_zumbador),
        .zumbador_o(salida_zumbador));

    logic [1:0] direccion_botones=0;
    logic escritura_botones=0;
    logic [31:0] dato_escritura_botones=0;
    logic [31:0] dato_lectura_botones;
    logic [6:0] controles=0;
    Debouncer_Botones #(.CICLOS_ANTIRREBOTE(3)) botones(.clk_i(reloj), .rst_i(reinicio),
        .write_enable_i(escritura_botones), .addr_i(direccion_botones), .wdata_i(dato_escritura_botones),
        .rdata_o(dato_lectura_botones), .controles_i(controles));

    integer total_pruebas=0, pruebas_correctas=0, errores_encontrados=0;
    task automatic verificar(input logic condicion, input string mensaje);
        total_pruebas=total_pruebas+1;
        if (condicion===1'b1) begin
            pruebas_correctas=pruebas_correctas+1;
            $display("Prueba %0d: %s - CORRECTA", total_pruebas, mensaje);
        end else begin
            errores_encontrados=errores_encontrados+1;
            $display("Prueba %0d: %s - ERROR", total_pruebas, mensaje);
        end
    endtask
    task automatic escribir_display(input logic [31:0] valor);
        @(negedge reloj); direccion_display=0; dato_escritura_display=valor; escritura_display=1;
        @(negedge reloj); escritura_display=0;
    endtask
    task automatic escribir_fase(input logic [1:0] fase);
        @(negedge reloj); direccion_led=0; dato_escritura_led={30'b0,fase}; escritura_led=1;
        @(negedge reloj); escritura_led=0;
    endtask
    task automatic escribir_evento(input logic [2:0] evento);
        @(negedge reloj); direccion_zumbador=0; dato_escritura_zumbador={29'b0,evento}; escritura_zumbador=1;
        @(negedge reloj); escritura_zumbador=0;
    endtask

    integer indice, flancos_impacto, flancos_fallo, flancos_hundido, flancos_invalido;
    logic salida_anterior;
    initial begin
        repeat (3) @(negedge reloj);
        reinicio=0;

        // Las primeras dos pruebas ilustran ingreso y reinicio de LED_Estado.
        escribir_fase(1); #1;
        $display("  wdata_i = %08h, rdata_o = %08h, leds_o = 0x%0h", dato_escritura_led, dato_lectura_led, leds);
        verificar(dato_lectura_led===1 && leds===3'b010, "Ingreso de dato LED_Estado");
        @(negedge reloj); reinicio=1; @(negedge reloj); #1;
        $display("  rdata_o despues del reinicio LED_Estado = %08h", dato_lectura_led);
        verificar(dato_lectura_led===0 && leds===3'b001, "Reseteo de registro LED_Estado");
        reinicio=0;

        // El periferico integrado rechaza un pulso breve y acepta uno estable.
        controles[0]=1; repeat (2) @(negedge reloj); controles[0]=0; repeat (6) @(negedge reloj);
        direccion_botones=0; #1; verificar(dato_lectura_botones[0]===0, "rechazo de rebote breve");
        controles[0]=1; repeat (8) @(negedge reloj);
        #1; $display("  rdata_o Debouncer_Botones = %08h", dato_lectura_botones);
        verificar(dato_lectura_botones[0]===1, "Lectura de pulsacion estable Debouncer_Botones");
        controles[0]=0; repeat (8) @(negedge reloj);
        #1; verificar(dato_lectura_botones[0]===0, "filtrado de liberacion");
        controles=7'b1000101; repeat (8) @(negedge reloj);
        direccion_botones=0; #1;
        $display("  wdata esperado = 00000045, rdata_o = %08h", dato_lectura_botones);
        verificar(dato_lectura_botones[6:0]===7'b1000101, "Lectura del registro de estado Debouncer_Botones");
        direccion_botones=1; #1; verificar(dato_lectura_botones===0, "direccion reservada de botones");
        @(negedge reloj); escritura_botones=1; dato_escritura_botones=32'hFFFF_FFFF;
        repeat (2) @(negedge reloj); escritura_botones=0; direccion_botones=0; #1;
        verificar(dato_lectura_botones[6:0]===7'b1000101, "escritura ignorada en direccion reservada de botones");

        // Registro explicito de fase y sus tres estados LED.
        direccion_led=0; #1; verificar(dato_lectura_led===0 && leds===3'b001, "fase inicial de colocacion");
        escribir_fase(1); #1;
        $display("  wdata_i = 00000001, rdata_o = %08h, leds_o = 0x%0h", dato_escritura_led, dato_lectura_led, leds);
        verificar(dato_lectura_led===1 && leds===3'b010, "Ingreso de dato LED_Estado");
        escribir_fase(2); #1; verificar(dato_lectura_led===2 && leds===3'b100, "fase de resultado");
        escribir_fase(3); #1; verificar(dato_lectura_led===0 && leds===3'b001, "fase invalida saneada");
        direccion_led=2; #1; verificar(dato_lectura_led===0, "direccion reservada de LED");
        @(negedge reloj); dato_escritura_led=32'd1; escritura_led=1;
        @(negedge reloj); escritura_led=0; direccion_led=0; #1;
        verificar(dato_lectura_led===0, "escritura ignorada en direccion reservada de LED");

        // Registro de puntajes, saturacion y barrido de los cuatro digitos.
        escribir_display({16'b0,8'd7,8'd42});
        direccion_display=0; #1;
        $display("  wdata_i = 0000072A, rdata_o = %08h", dato_lectura_display);
        verificar(dato_lectura_display===32'h0000_072A, "Ingreso y lectura del registro Display_7_seg");
        @(negedge reloj); direccion_display=1; dato_escritura_display=32'hFFFF_FFFF; escritura_display=1;
        @(negedge reloj); escritura_display=0; direccion_display=0; #1;
        verificar(dato_lectura_display===32'h0000_072A, "escritura ignorada en direccion reservada de pantalla");
        escribir_display({16'b0,8'd180,8'd255});
        #1; verificar(dato_lectura_display===32'h0000_6363, "saturacion de puntajes a 99");
        escribir_display({16'b0,8'd7,8'd42});
        for (indice=0; indice<4; indice=indice+1) begin
            wait (anodos[indice]===1'b0); #1;
            case (indice)
                0: verificar(segmentos===8'b0010_0101, "unidades P1 muestran 2");
                1: verificar(segmentos===8'b1001_1001, "decenas P1 muestran 4");
                2: verificar(segmentos===8'b0001_1111, "unidades P2 muestran 7");
                3: verificar(segmentos===8'b0000_0011, "decenas P2 muestran 0");
            endcase
            @(negedge reloj);
        end
        verificar(anodos[7:4]===4'b1111, "digitos no usados deshabilitados");

        // Codigos del registro del zumbador y tonos con frecuencias distintas.
        escribir_evento(1); #1;
        $display("  wdata_i = 00000001, rdata_o = %08h", dato_lectura_zumbador);
        verificar(dato_lectura_zumbador[2:0]===1 && dato_lectura_zumbador[8]===1, "Ingreso de evento en Buzzer");
        flancos_impacto=0; salida_anterior=salida_zumbador;
        repeat (40) begin @(negedge reloj); if (salida_zumbador && !salida_anterior) flancos_impacto=flancos_impacto+1; salida_anterior=salida_zumbador; end
        escribir_evento(2); #1; verificar(dato_lectura_zumbador[2:0]===2, "codigo de fallo");
        flancos_fallo=0; salida_anterior=salida_zumbador;
        repeat (40) begin @(negedge reloj); if (salida_zumbador && !salida_anterior) flancos_fallo=flancos_fallo+1; salida_anterior=salida_zumbador; end
        escribir_evento(3); #1; verificar(dato_lectura_zumbador[2:0]===3, "codigo de barco hundido");
        flancos_hundido=0; salida_anterior=salida_zumbador;
        repeat (40) begin @(negedge reloj); if (salida_zumbador && !salida_anterior) flancos_hundido=flancos_hundido+1; salida_anterior=salida_zumbador; end
        escribir_evento(4); #1; verificar(dato_lectura_zumbador[2:0]===4, "codigo de colocacion invalida");
        flancos_invalido=0; salida_anterior=salida_zumbador;
        repeat (40) begin @(negedge reloj); if (salida_zumbador && !salida_anterior) flancos_invalido=flancos_invalido+1; salida_anterior=salida_zumbador; end
        escribir_evento(5); #1; verificar(dato_lectura_zumbador[2:0]===5 && dato_lectura_zumbador[8]===1, "evento de victoria");
        @(negedge reloj); direccion_zumbador=3; dato_escritura_zumbador=0; escritura_zumbador=1;
        @(negedge reloj); escritura_zumbador=0; direccion_zumbador=0; #1;
        verificar(dato_lectura_zumbador[2:0]===5, "escritura ignorada en direccion reservada del zumbador");
        verificar(flancos_impacto>0 && flancos_fallo>0 && flancos_hundido>0 && flancos_invalido>0, "cada evento produce sonido");
        verificar(flancos_impacto!=flancos_fallo && flancos_fallo!=flancos_hundido && flancos_hundido!=flancos_invalido,
            "tonos diferentes para los eventos comprobados");
        escribir_evento(0); #1; verificar(dato_lectura_zumbador[2:0]===0 && dato_lectura_zumbador[8]===0 && salida_zumbador===0, "Orden de silencio Buzzer");
        direccion_zumbador=3; #1; verificar(dato_lectura_zumbador===0, "direccion reservada del zumbador");

        // Reinicio sincrono: limpiar cada registro y comprobar su lectura.
        controles=0; escritura_display=0; escritura_led=0; escritura_zumbador=0;
        direccion_botones=0; direccion_display=0; direccion_led=0; direccion_zumbador=0;
        @(negedge reloj); reinicio=1; @(negedge reloj); #1;
        $display("  rdata_o despues del reinicio: botones=%08h pantalla=%08h LED=%08h buzzer=%08h",
            dato_lectura_botones, dato_lectura_display, dato_lectura_led, dato_lectura_zumbador);
        verificar(dato_lectura_botones===0, "Reseteo del registro Debouncer_Botones");
        verificar(dato_lectura_display===0, "Reseteo del registro Display_7_seg");
        verificar(dato_lectura_led===0 && leds===3'b001, "Reseteo del registro LED_Estado");
        verificar(dato_lectura_zumbador===0 && salida_zumbador===0, "Reseteo del registro Buzzer");
        reinicio=0;

        $display("");
        $display("Resumen de simulacion:");
        $display("  Pruebas ejecutadas: %0d", total_pruebas);
        $display("  Pruebas correctas:  %0d", pruebas_correctas);
        $display("  Errores encontrados: %0d", errores_encontrados);
        if (errores_encontrados==0) $display("CORRECTO: todas las pruebas finalizaron satisfactoriamente.");
        else $fatal(1, "La simulacion encontro %0d errores.", errores_encontrados);
        $finish;
    end
endmodule


