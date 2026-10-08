`timescale 1ns/1ps
module mux_arbitro_tb;
    logic [2:0] select_i;
    logic [31:0] rdata_mem, rdata_displays, rdata_buzzer, rdata_btns;
    logic [31:0] rdata_uart, rdata_vga, rdata_led, DataIn_o;
    integer errores = 0;

    mux_arbitro dut (.*);

    initial begin
        rdata_mem=32'h1111_1111; rdata_displays=32'h2222_2222;
        rdata_buzzer=32'h3333_3333; rdata_btns=32'h4444_4444;
        rdata_uart=32'h5555_5555; rdata_vga=32'h6666_6666;
        rdata_led=32'h7777_7777;
        for (int i=0; i<8; i++) begin
            select_i=i[2:0]; #1;
            case (select_i)
                3'b000: if (DataIn_o!==rdata_mem) errores++;
                3'b001: if (DataIn_o!==rdata_displays) errores++;
                3'b010: if (DataIn_o!==rdata_buzzer) errores++;
                3'b011: if (DataIn_o!==rdata_btns) errores++;
                3'b100: if (DataIn_o!==rdata_uart) errores++;
                3'b101: if (DataIn_o!==rdata_vga) errores++;
                3'b110: if (DataIn_o!==rdata_led) errores++;
                default: if (DataIn_o!==32'b0) errores++;
            endcase
        end
        if (errores) $fatal(1, "%0d mux checks failed", errores);
        $display("Read mux checks passed");
        $finish;
    end
endmodule
