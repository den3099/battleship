`timescale 1ns/1ps
module traductor_direcciones_tb;
    logic we_o;
    logic [31:0] DataAddress_i;
    logic [2:0] select_o;
    logic we_mem, we_displays, we_buzzer, we_btns, we_pc, we_vga, we_uart, we_led;
    integer errores = 0;

    traductor_direcciones dut (.*);

    task automatic check(input logic [31:0] addr, input logic write_en,
                         input logic [2:0] expected_select,
                         input logic [7:0] expected_we, input string label);
        logic [7:0] actual_we;
        begin
            DataAddress_i = addr;
            we_o = write_en;
            #1;
            actual_we = {we_mem,we_displays,we_buzzer,we_btns,we_pc,we_vga,we_uart,we_led};
            if (select_o !== expected_select || actual_we !== expected_we) begin
                $error("%s: sel %b/%b, we %b/%b", label, select_o, expected_select, actual_we, expected_we);
                errores++;
            end
        end
    endtask

    initial begin
        check(32'h0000_2000, 1, 3'b000, 8'b1000_0000, "RAM write");
        check(32'h0000_2000, 0, 3'b000, 8'b0, "RAM read");
        check(32'h0001_0040, 1, 3'b100, 8'b0000_0010, "UART control write");
        check(32'h0001_0048, 0, 3'b100, 8'b0, "UART RX read");
        check(32'h0001_0120, 1, 3'b011, 8'b0001_0000, "buttons");
        check(32'h0001_0130, 1, 3'b001, 8'b0100_0000, "display");
        check(32'h0001_0138, 1, 3'b110, 8'b0000_0001, "status LEDs");
        check(32'h0001_0140, 1, 3'b010, 8'b0010_0000, "buzzer");
        check(32'h0001_1000, 1, 3'b101, 8'b0000_0100, "VGA lower bound");
        check(32'h0001_17ff, 1, 3'b101, 8'b0000_0100, "VGA upper bound");
        check(32'h0001_9999, 1, 3'b111, 8'b0, "unmapped peripheral");
        if (errores) $fatal(1, "%0d address decoder checks failed", errores);
        $display("Address decoder checks passed");
        $finish;
    end
endmodule
