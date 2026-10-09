module control_unit(
    input  logic [6:0] op,
    input  logic [2:0] funct3,
    input  logic [6:0] funct7,
    input  logic zero,
    input  logic less,
    input  logic [2:0] funct3E,

    output logic RegWriteD,
    output logic ALUSrcD,
    output logic [1:0] ResultSrcD,
    output logic [3:0] ImmSrcD,
    output logic [3:0] ALUControlD,
    output logic [1:0] PCSrcE,
    output logic MemWriteD
);

logic [1:0] ALUOp;
logic Jump;

main_decoder md(
    .op(op),
    .funct3E(funct3E),
    .zero(zero),
    .less(less),
    .Jump(Jump),

    .RegWriteD(RegWriteD),
    .MemWriteD(MemWriteD),
    .ALUSrcD(ALUSrcD),
    .ResultSrcD(ResultSrcD),
    .ImmSrcD(ImmSrcD),

    .ALUOp(ALUOp),
    .PCSrcE(PCSrcE)
);

alu_decoder ad(
    .ALUOp(ALUOp),
    .funct3(funct3),
    .funct7(funct7),
    .ALUControlD(ALUControlD)
);

endmodule