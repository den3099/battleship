module register_decode_execute (
    input  logic        clk,
    input  logic        rst,
    input  logic        clear,

    input  logic        RegWriteD,
    input  logic [1:0]  ResultSrcD,
    input  logic        MemWriteD,
    input  logic [3:0]  ALUControlD,
    input  logic        ALUSrcD,

    input  logic        BranchD,
    input  logic        JalD,
    input  logic        JalrD,
    input  logic        PredTakenD,
    input  logic [31:0] PredTargetD,

    input  logic [2:0]  funct3D,
    input  logic [31:0] RD1D,
    input  logic [31:0] RD2D,
    input  logic [4:0]  Rs1D,
    input  logic [4:0]  Rs2D,
    input  logic [31:0] PCD,
    input  logic [4:0]  RdD,
    input  logic [31:0] ImmExtD,
    input  logic [31:0] PCPlus4D,

    output logic        RegWriteE,
    output logic [1:0]  ResultSrcE,
    output logic        MemWriteE,
    output logic [3:0]  ALUControlE,
    output logic        ALUSrcE,

    output logic        BranchE,
    output logic        JalE,
    output logic        JalrE,
    output logic        PredTakenE,
    output logic [31:0] PredTargetE,

    output logic [2:0]  funct3E,
    output logic [31:0] RD1E,
    output logic [31:0] RD2E,
    output logic [4:0]  Rs1E,
    output logic [4:0]  Rs2E,
    output logic [31:0] PCE,
    output logic [4:0]  RdE,
    output logic [31:0] ImmExtE,
    output logic [31:0] PCPlus4E
);

always_ff @(posedge clk or posedge rst)
begin
    if (rst || clear)
    begin
        RegWriteE   <= 1'b0;
        ResultSrcE  <= 2'b0;
        MemWriteE   <= 1'b0;
        ALUControlE <= 4'b0;
        ALUSrcE     <= 1'b0;

        BranchE     <= 1'b0;
        JalE        <= 1'b0;
        JalrE       <= 1'b0;
        PredTakenE  <= 1'b0;
        PredTargetE <= 32'b0;

        funct3E     <= 3'b0;
        RD1E        <= 32'b0;
        RD2E        <= 32'b0;
        Rs1E        <= 5'b0;
        Rs2E        <= 5'b0;
        PCE         <= 32'b0;
        RdE         <= 5'b0;
        ImmExtE     <= 32'b0;
        PCPlus4E    <= 32'b0;
    end
    else
    begin
        RegWriteE   <= RegWriteD;
        ResultSrcE  <= ResultSrcD;
        MemWriteE   <= MemWriteD;
        ALUControlE <= ALUControlD;
        ALUSrcE     <= ALUSrcD;

        BranchE     <= BranchD;
        JalE        <= JalD;
        JalrE       <= JalrD;
        PredTakenE  <= PredTakenD;
        PredTargetE <= PredTargetD;

        funct3E     <= funct3D;
        RD1E        <= RD1D;
        RD2E        <= RD2D;
        Rs1E        <= Rs1D;
        Rs2E        <= Rs2D;
        PCE         <= PCD;
        RdE         <= RdD;
        ImmExtE     <= ImmExtD;
        PCPlus4E    <= PCPlus4D;
    end
end

endmodule
