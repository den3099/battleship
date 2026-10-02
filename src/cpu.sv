module cpu (
    input  logic clk,
    input  logic rst,

    input  logic [31:0] DataIn_i,
    output logic [31:0] DataOut_o,
    output logic [31:0] DataAddress_o,
    output logic        we_o,
    output logic [2:0] funct3_o
);

    // ======================
    // Señales internas
    // ======================
    logic [31:0] InstrD;
    logic zero;
    logic less;
    logic [2:0] funct3E;

    logic RegWriteD;
    logic ALUSrcD;
    logic [1:0] ResultSrcD;
    logic MemWriteD;
    logic [3:0] ImmSrcD;
    logic [3:0] ALUControlD;
    logic [1:0] PCSrcE;

    // ======================
    // DATAPATH
    // ======================
    datapath dp(
        .clk(clk),
        .rst(rst),

        .RegWriteD(RegWriteD),
        .ALUSrcD(ALUSrcD),
        .ResultSrcD(ResultSrcD),
        .MemWriteD(MemWriteD),
        .ALUControlD(ALUControlD),
        .ImmSrcD(ImmSrcD),
        .PCSrcE(PCSrcE),

        .InstrD(InstrD),
        .zero(zero),
        .less(less),
        .funct3E(funct3E),

        .DataIn_i(DataIn_i),
        .DataAddress_o(DataAddress_o),
        .DataOut_o(DataOut_o),
        .we_o(we_o),
        .funct3_o(funct3_o)
    );

    // ======================
    // CONTROL UNIT
    // ======================
    control_unit cu(
        .op(InstrD[6:0]),
        .funct3(InstrD[14:12]),
        .funct7(InstrD[31:25]),
        .zero(zero),
        .less(less),
        .funct3E(funct3E),

        .RegWriteD(RegWriteD),
        .ALUSrcD(ALUSrcD),
        .ResultSrcD(ResultSrcD),
        .MemWriteD(MemWriteD),
        .ImmSrcD(ImmSrcD),
        .ALUControlD(ALUControlD),
        .PCSrcE(PCSrcE)
    );

endmodule