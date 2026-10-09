// Periférico de LED de estado, dirección base 0x00010138.
// Registro único 00: 0 colocación, 1 batalla, 2 resultado en bits [1:0].
// Direcciones restantes reservadas. LD0..LD2 son activos en alto.
module LED_Estado (
    input logic clk_i, input logic rst_i,
    input logic write_enable_i, input logic [1:0] addr_i,
    input logic [31:0] wdata_i, output logic [31:0] rdata_o,
    output logic [2:0] leds_o
);
    logic [31:0] registro_estado;
    always_ff @(posedge clk_i) begin
        if (rst_i) registro_estado<='0;
        else if (write_enable_i && addr_i==2'b00)
            registro_estado<={30'b0,((wdata_i[1:0]<=2)?wdata_i[1:0]:2'b00)};
    end
    always_comb begin
        rdata_o=(addr_i==2'b00)?registro_estado:32'b0;
        case (registro_estado[1:0])
            0: leds_o=3'b001;
            1: leds_o=3'b010;
            2: leds_o=3'b100;
            default: leds_o=3'b001;
        endcase
    end
endmodule

