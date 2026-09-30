module tb_cpu;

    logic clk;
    logic rst;

    // Instancia CPU
    cpu dut(
        .clk(clk),
        .rst(rst)
    );

    // ======================
    // Clock
    // ======================
    initial clk = 0;
    always #5 clk = ~clk; // periodo = 10

    // ======================
    // Reset
    // ======================
    initial begin
        rst = 1;
        repeat (2) @(posedge clk); // 2 ciclos en reset
        rst = 0;
    end

    // ======================
    // MONITOR POR CICLO
    // ======================
    always @(posedge clk) begin
        if (!rst) begin
            $display("\n==============================");
            $display("CYCLE");
            $display("Instr   = %h", dut.InstrD);
            $display("RS1     = %0d", dut.dp.RD1D);
            $display("RS2     = %0d", dut.dp.RD2D);
            $display("Result  = %0d", dut.dp.ResultW);
            $display("zero    = %b", dut.zero);

            $display("---- REGISTERS ----");
            $display("x1=%0d x2=%0d x3=%0d x4=%0d",
                dut.dp.u_regfile.regs[1],
                dut.dp.u_regfile.regs[2],
                dut.dp.u_regfile.regs[3],
                dut.dp.u_regfile.regs[4]);

            $display("x5=%0d x6=%0d x7=%0d x8=%0d",
                dut.dp.u_regfile.regs[5],
                dut.dp.u_regfile.regs[6],
                dut.dp.u_regfile.regs[7],
                dut.dp.u_regfile.regs[8]);

            $display("x9=%0d x10=%0d x11=%0d x12=%0d",
                dut.dp.u_regfile.regs[9],
                dut.dp.u_regfile.regs[10],
                dut.dp.u_regfile.regs[11],
                dut.dp.u_regfile.regs[12]);

            $display("x13=%0d x14=%0d x15=%0d x16=%0d",
                dut.dp.u_regfile.regs[13],
                dut.dp.u_regfile.regs[14],
                dut.dp.u_regfile.regs[15],
                dut.dp.u_regfile.regs[16]);

            // DEBUG CONTROL
        end
    end

    // ======================
    // FINALIZACIÓN
    // ======================
    initial begin
        $dumpfile("sim/wave.vcd");
        $dumpvars(0, tb_cpu);
        repeat (40) @(posedge clk); // corre 20 ciclos
        $finish;
    end

endmodule