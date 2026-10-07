`timescale 1ns/1ps
`default_nettype none
// 640x480 visibles, 800x525 total. 25 MHz -> 59.524 cuadros/s.
// Izquierda: 8x8 casillas de 54x60 px (432x480).
// Derecha: 13x30 celdas de 16x16 px (208x480).
// Solo existe UN tablero. No se alterna entre tablero y panel.
module controlador_vga #(
    parameter logic [2:0] COLOR_REJILLA = 3'b111
) (
    input  wire        clk_25,
    input  wire        rst_i,
    output wire        video_en_o,
    output logic [8:0] video_addr_o,
    input  wire [31:0] video_data_i,
    output logic [4:0] screen_o  // [4]=R,[3]=G,[2]=B,[1]=HS,[0]=VS
);
    logic [9:0] horizontal, vertical;
    wire visible = (horizontal < 10'd640) && (vertical < 10'd480);
    wire hs = !((horizontal >= 10'd656) && (horizontal < 10'd752));
    wire vs = !((vertical >= 10'd490) && (vertical < 10'd492));
    wire en_tablero = horizontal < 10'd432;
    logic [2:0] columna_tablero, fila_tablero;
    logic [9:0] x_casilla, y_casilla;
    wire [9:0] x_panel = horizontal - 10'd432;
    wire [8:0] fila_panel = {4'b0, vertical[8:4]};
    wire [8:0] columna_panel = {5'b0, x_panel[7:4]};
    integer k;

    // Comparaciones con constantes: evita divisores generales por 54 y 60.
    always_comb begin
        columna_tablero = 3'd0;
        fila_tablero = 3'd0;
        for (k = 1; k < 8; k = k + 1) begin
            if (horizontal >= 10'(54*k)) columna_tablero = 3'(k);
            if (vertical   >= 10'(60*k)) fila_tablero = 3'(k);
        end
        x_casilla = horizontal - (10'(columna_tablero) * 10'd54);
        y_casilla = vertical - (10'(fila_tablero) * 10'd60);
        video_addr_o = 9'd0;
        if (visible) begin
            if (en_tablero)
                video_addr_o = {3'b000, fila_tablero, columna_tablero};
            else
                video_addr_o = 9'd64 + (fila_panel << 3)
                               + (fila_panel << 2) + fila_panel + columna_panel;
        end
    end
    assign video_en_o = visible && !rst_i;
    wire rejilla = (x_casilla == 10'd0) || (x_casilla == 10'd53)
                 || (y_casilla == 10'd0) || (y_casilla == 10'd59);

    logic visible_d, hs_d, vs_d, tablero_d, rejilla_d;
    logic [2:0] glifo_x_d, glifo_y_d;
    wire tinta;
    fuente_5x7 fuente (
        .ascii_i(video_data_i[9:3]), .x_i(glifo_x_d), .y_i(glifo_y_d),
        .pixel_o(tinta)
    );
    logic [2:0] rgb;
    always_comb begin
        rgb = 3'b000;
        if (visible_d) begin
            if (tablero_d)
                rgb = rejilla_d ? COLOR_REJILLA : video_data_i[2:0];
            else if (video_data_i[10])
                rgb = tinta ? video_data_i[2:0] : video_data_i[13:11];
            else
                rgb = video_data_i[2:0];
        end
    end

    always_ff @(posedge clk_25) begin
        if (rst_i) begin
            horizontal <= 10'd0;
            vertical <= 10'd0;
            visible_d <= 1'b0;
            hs_d <= 1'b1;
            vs_d <= 1'b1;
            tablero_d <= 1'b0;
            rejilla_d <= 1'b0;
            glifo_x_d <= 3'd0;
            glifo_y_d <= 3'd0;
            screen_o <= 5'b00011;
        end else begin
            if (horizontal == 10'd799) begin
                horizontal <= 10'd0;
                if (vertical == 10'd524) vertical <= 10'd0;
                else                    vertical <= vertical + 10'd1;
            end else horizontal <= horizontal + 10'd1;

            // Etapa 1: acompana la lectura sincrona de la memoria.
            visible_d <= visible;
            hs_d <= hs;
            vs_d <= vs;
            tablero_d <= en_tablero;
            rejilla_d <= rejilla;
            glifo_x_d <= x_panel[3:1];  // Duplica cada pixel de la fuente.
            glifo_y_d <= vertical[3:1];
            // Etapa 2: RGB y sincronismos siempre avanzan juntos.
            screen_o <= {rgb, hs_d, vs_d};
        end
    end
endmodule
`default_nettype wire
