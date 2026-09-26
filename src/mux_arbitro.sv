module mux_arbitro (
    input  logic [2:0]  select_i,

    input  logic [31:0] rdata_mem,
    input  logic [31:0] rdata_displays,
    input  logic [31:0] rdata_buzzer,
    input  logic [31:0] rdata_btns,
    input  logic [31:0] rdata_pc,
    input  logic [31:0] rdata_vga,

    output logic [31:0] DataIn_o
);

    always_comb begin
        case (select_i)
            3'b000: DataIn_o = rdata_mem;
            3'b001: DataIn_o = rdata_displays;
            3'b010: DataIn_o = rdata_buzzer;
            3'b011: DataIn_o = rdata_btns;
            3'b100: DataIn_o = rdata_pc;
            3'b101: DataIn_o = rdata_vga;
            default: DataIn_o = 32'h0000_0000;
        endcase
    end

endmodule