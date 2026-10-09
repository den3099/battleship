`timescale 1ns/1ps
`default_nettype none


module periferico_vga #(
    parameter logic [31:0] BASE_ADDR = 32'h0001_1000,
    parameter INIT_FILE = ""
) (
    input  wire        clk_i,
    input  wire        clk_25,
    input  wire        rst_i,
    input  wire [31:0] addr_i,
    input  wire [31:0] wdata_i,
    input  wire        we_vga,
    output wire [31:0] rdata_o,
    output wire [4:0]  screen_o
);
    wire rst_cpu, rst_pixel;
    reset_sincrono reset_cpu (
        .clk_i(clk_i), 
        .reset_async_i(rst_i), 
        .reset_o(rst_cpu)
    );
    reset_sincrono reset_video (
        .clk_i(clk_25), 
        .reset_async_i(rst_i), 
        .reset_o(rst_pixel)
    );

    wire [31:0] offset = addr_i - BASE_ADDR;
    wire valida = (addr_i >= BASE_ADDR) && (offset < 32'd2048)
                  && (offset[1:0] == 2'b00) && !rst_cpu;
    wire [31:0] dato_cpu, dato_video;
    wire [8:0] addr_video;
    wire en_video;
    logic valida_d;
    always_ff @(posedge clk_i) begin
        if (rst_cpu) valida_d <= 1'b0;
        else         valida_d <= valida;
    end
    // Lectura sincrona: dato de la direccion presentada ANTES del flanco.
    assign rdata_o = (valida_d && !rst_cpu) ? dato_cpu : 32'b0;

    memoria_video #(.INIT_FILE(INIT_FILE)) vram (
        .clk_cpu_i(clk_i), 
        .cpu_en_i(valida), 
        .cpu_we_i(we_vga),
        .cpu_addr_i(offset[10:2]), 
        .cpu_data_i(wdata_i),
        .cpu_data_o(dato_cpu), 
        .clk_video_i(clk_25),
        .video_en_i(en_video), 
        .video_addr_i(addr_video),
        .video_data_o(dato_video)
    );

    controlador_vga controlador (
        .clk_25(clk_25), 
        .rst_i(rst_pixel), 
        .video_en_o(en_video),
        .video_addr_o(addr_video), 
        .video_data_i(dato_video),
        .screen_o(screen_o)
    );
endmodule
`default_nettype wire
