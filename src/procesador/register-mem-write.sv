module register_mem_write (
    input  logic        clk,
    input  logic        rst,

    input  logic [31:0] ReadDataM,
    input  logic [31:0] ALUResultM,
    input  logic [31:0] ImmExtM,
    input  logic [31:0] PCPlus4M,
    input  logic [4:0]  RdM,
    input  logic        RegWriteM,
    input  logic [1:0]  ResultSrcM,

    output logic [31:0] ReadDataW,
    output logic [31:0] ALUResultW,
    output logic [31:0] ImmExtW,
    output logic [31:0] PCPlus4W,
    output logic [4:0]  RdW,
    output logic        RegWriteW,
    output logic [1:0]  ResultSrcW
);

always_ff @(posedge clk or posedge rst) begin

    if(rst) begin
        ReadDataW  <= 32'b0;
        ALUResultW <= 32'b0;
        ImmExtW    <= 32'b0;
        PCPlus4W   <= 32'b0;
        RdW        <= 5'b0;
        RegWriteW  <= 1'b0;
        ResultSrcW <= 2'b0;
    end
    else begin
        ReadDataW  <= ReadDataM;
        ALUResultW <= ALUResultM;
        ImmExtW    <= ImmExtM;
        PCPlus4W   <= PCPlus4M;
        RdW        <= RdM;
        RegWriteW  <= RegWriteM;
        ResultSrcW <= ResultSrcM;
    end

end

endmodule