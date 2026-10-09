`timescale 1ns/1ps
`default_nettype none
// 512 PALABRAS de 32 bits, no un framebuffer de pixeles.
// A: lectura/escritura a clk_cpu_i; B: solo lectura a clk_video_i.
// No hay reset del arreglo: el reset del periferico conserva el contenido.
// Inicializacion de configuracion: tablero azul y panel negro.
module memoria_video #(
    parameter INIT_FILE = ""
) (
    input  wire        clk_cpu_i,
    input  wire        cpu_en_i,
    input  wire        cpu_we_i,
    input  wire [8:0]  cpu_addr_i,
    input  wire [31:0] cpu_data_i,
    output logic [31:0] cpu_data_o,
    input  wire        clk_video_i,
    input  wire        video_en_i,
    input  wire [8:0]  video_addr_i,
    output logic [31:0] video_data_o
);
    (* ram_style = "block" *) logic [31:0] memoria [0:511];
    integer i;
    initial begin
        for (i = 0; i < 512; i = i + 1)
            memoria[i] = (i < 64) ? 32'h0000_0001 : 32'h0000_0000;
        if (INIT_FILE != "") $readmemh(INIT_FILE, memoria);
    end

    // Write-first solo en el propio puerto A. Guarda los 32 bits.
    always @(posedge clk_cpu_i) begin
        if (cpu_en_i) begin
            if (cpu_we_i) begin
                memoria[cpu_addr_i] <= cpu_data_i;
                cpu_data_o <= cpu_data_i;
            end else begin
                cpu_data_o <= memoria[cpu_addr_i];
            end
        end
    end
    always @(posedge clk_video_i) begin
        if (video_en_i) video_data_o <= memoria[video_addr_i];
    end
    // Una colision A-escribe/B-lee no define el dato leido por B en BRAM.
    // El modelo RTL NO simula la indeterminacion fisica de esa colision.
    // Ver docs/GUIA_VGA.md: relacion de relojes y margen entre flancos.
endmodule
`default_nettype wire
