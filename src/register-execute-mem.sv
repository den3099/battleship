module register_execute_mem (
    input logic clk,
    input logic rst,

    input logic       RegWriteE,
    input logic [1:0] ResultSrcE,
    input logic       MemWriteE,

    input logic [2:0]  funct3E,
    input logic [31:0] ALUResultE,
    input logic [31:0] WriteDataE,
    input logic [4:0]  RdE,
    input logic [31:0] ImmExtE,
    input logic [31:0] PCPlus4E,

    output logic       RegWriteM,
    output logic [1:0] ResultSrcM,
    output logic       MemWriteM,

    output logic [2:0]  funct3M,
    output logic [31:0] ALUResultM,
    output logic [31:0] WriteDataM,
    output logic [4:0]  RdM,
    output logic [31:0] ImmExtM,
    output logic [31:0] PCPlus4M
);

always_ff @(posedge clk or posedge rst)
begin
    if(rst)
    begin
        RegWriteM  <= 0;
        ResultSrcM <= 0;
        MemWriteM  <= 0;

        funct3M    <= 0;
        ALUResultM <= 0;
        WriteDataM <= 0;
        RdM        <= 0;
        ImmExtM    <= 0;
        PCPlus4M   <= 0;
    end
    else
    begin
        RegWriteM  <= RegWriteE;
        ResultSrcM <= ResultSrcE;
        MemWriteM  <= MemWriteE;

        funct3M    <= funct3E;
        ALUResultM <= ALUResultE;
        WriteDataM <= WriteDataE;
        RdM        <= RdE;
        ImmExtM    <= ImmExtE;
        PCPlus4M   <= PCPlus4E;
    end
end

endmodule