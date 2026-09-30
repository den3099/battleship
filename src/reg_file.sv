module reg_file(
    input  logic clk,
    input  logic WE3,
    input  logic [4:0] A1, A2, A3,
    input  logic [31:0] WD3,
    output logic [31:0] RD1D, RD2D
);

    logic [31:0] regs [0:31];

    assign RD1D = (A1 == 5'd0) ? 32'b0 : regs[A1];
    assign RD2D = (A2 == 5'd0) ? 32'b0 : regs[A2];

    always_ff @(posedge clk) begin
        if (WE3 && (A3 != 5'd0)) begin
            regs[A3] <= WD3;
        end
    end

    initial begin
    integer i;
    for (i = 0; i < 32; i++) begin
        regs[i] = 0;
    end
end

endmodule