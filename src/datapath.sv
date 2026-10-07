module datapath(
    input logic clk,
    input logic rst,

    // Control signals desde control_unit
    input logic RegWriteD,
    input logic ALUSrcD,
    input logic MemWriteD,
    input logic [1:0] ResultSrcD,
    input logic [3:0] ALUControlD,
    input logic [3:0] ImmSrcD,
    input logic [1:0] PCSrcE, // Se deja por compatibilidad, pero ya no se usa con prediction

    output logic [31:0] InstrD,
    output logic zero,
    output logic less,
    output logic [2:0] funct3E,

    input  logic [31:0] DataIn_i,
    output logic [31:0] DataOut_o,
    output logic [31:0] DataAddress_o,
    output logic        we_o,
    output logic        re_o,

    output logic [2:0] funct3_o
);

    // ======================
    // Señales internas
    // ======================
    logic [31:0] PCTargetE, PCnext;
    logic [1:0] ForwardAE;
    logic [1:0] ForwardBE;

    // Fetch
    logic [31:0] PCplus4F;
    logic [31:0] PCF;
    logic [31:0] InstrF;

    // Branch prediction en Fetch
    logic        PredTakenF;
    logic [31:0] PredTargetF;

    // Decode
    logic [31:0] PCD;
    logic [31:0] PCPlus4D;
    logic [31:0] RD1D;
    logic [31:0] RD2D;
    logic [31:0] ImmExtD;
    logic        PredTakenD;
    logic [31:0] PredTargetD;
    logic        BranchD;
    logic        JalD;
    logic        JalrD;

    // Execute
    logic RegWriteE;
    logic ALUSrcE;
    logic MemWriteE;
    logic [1:0] ResultSrcE;
    logic [3:0] ALUControlE;
    logic [31:0] SrcBE;
    logic [31:0] RD1E;
    logic [31:0] RD2E;
    logic [4:0] Rs1E;
    logic [4:0] Rs2E;
    logic [31:0] SrcAForwardE;
    logic [31:0] RD2ForwardE;
    logic [31:0] PCE;
    logic [31:0] ImmExtE;
    logic [31:0] PCPlus4E;
    logic [4:0] RdE;
    logic [31:0] ALUResultE;
    logic [31:0] ALUResult_jalrE;
    logic        BranchE;
    logic        JalE;
    logic        JalrE;
    logic        PredTakenE;
    logic [31:0] PredTargetE;

    // Resultado real de branch / redireccion
    logic        BranchCondE;
    logic        ActualTakenE;
    logic        BranchMispredictE;
    logic        RedirectE;
    logic [31:0] CorrectPCE;

    // Hazard unit
    logic FlushD;
    logic FlushE;
    logic StallF;
    logic StallD;
    logic lwStall;

    // Memory
    logic RegWriteM;
    logic MemWriteM;
    logic [1:0] ResultSrcM;
    logic [31:0] ReadDataM;
    logic [2:0] funct3M;
    logic [31:0] ALUResultM;
    logic [31:0] WriteDataM;
    logic [4:0] RdM;
    logic [31:0] ImmExtM;
    logic [31:0] PCPlus4M;

    // Writeback
    logic RegWriteW;
    logic [1:0] ResultSrcW;
    logic [31:0] ReadDataW;
    logic [31:0] ALUResultW;
    logic [4:0] RdW;
    logic [31:0] ImmExtW;
    logic [31:0] PCPlus4W;
    logic [31:0] ResultW;

    // ======================
    // CONEXIONES EXTERNAS
    // ======================
    assign DataAddress_o = ALUResultM;
    assign DataOut_o     = WriteDataM;
    assign we_o          = MemWriteM;
    assign re_o          = (ResultSrcM == 2'b01);
    assign ReadDataM     = DataIn_i;
    assign funct3_o      = funct3M;

    // ======================
    // PC
    // ======================
    pc u_pc(
        .clk(clk),
        .rst(rst),
        .en(~StallF || RedirectE),
        .PCnext(PCnext),
        .PCF(PCF)
    );

    // ======================
    // PC + 4
    // ======================
    adder u_pc4(
        .in0(PCF),
        .in1(32'd4),
        .out(PCplus4F)
    );

    // ======================
    // Branch Predictor
    // ======================
    branch_predictor u_branch_predictor(
        .clk(clk),
        .rst(rst),

        .PCF(PCF),
        .PredTakenF(PredTakenF),
        .PredTargetF(PredTargetF),

        .UpdateE(BranchE),
        .PCE(PCE),
        .ActualTakenE(ActualTakenE),
        .ActualTargetE(PCTargetE)
    );

    // Si Execute corrige, manda el PC correcto.
    // Si no, usa el PC predicho por el predictor.
    assign PCnext = RedirectE ? CorrectPCE : PredTargetF;

    // ======================
    // Instruction Memory
    // ======================
    Instr_mem u_imem(
        .A(PCF),
        .RD(InstrF)
    );

    // ======================
    // Decodificacion local de tipo de salto/branch
    // ======================
    assign BranchD = (InstrD[6:0] == 7'b1100011);
    assign JalD    = (InstrD[6:0] == 7'b1101111);
    assign JalrD   = (InstrD[6:0] == 7'b1100111);

    // ======================
    // Register File
    // ======================
    reg_file u_regfile(
        .clk(clk),
        .WE3(RegWriteW),

        .A1(InstrD[19:15]),
        .A2(InstrD[24:20]),
        .A3(RdW),
        .WD3(ResultW),

        .RD1D(RD1D),
        .RD2D(RD2D)
    );

    // ======================
    // Immediate Extend
    // ======================
    Extend u_extend(
        .InstrD(InstrD),
        .ImmSrcD(ImmSrcD),
        .ImmExtD(ImmExtD)
    );

    // ======================
    // Branch Target (PC + Imm)
    // ======================
    adder u_pctarget(
        .in0(PCE),
        .in1(ImmExtE),
        .out(PCTargetE)
    );

    // ======================
    // Forwarding mux A
    // ======================
    mux41 u_forwardA(
        .sel(ForwardAE),
        .in0(RD1E),        // Sin forwarding
        .in1(ResultW),     // Desde WB
        .in2(ALUResultM),  // Desde MEM
        .in3(32'd0),
        .out(SrcAForwardE)
    );

    // ======================
    // Forwarding mux B
    // ======================
    mux41 u_forwardB(
        .sel(ForwardBE),
        .in0(RD2E),        // Sin forwarding
        .in1(ResultW),     // Desde WB
        .in2(ALUResultM),  // Desde MEM
        .in3(32'd0),
        .out(RD2ForwardE)
    );

    // ======================
    // ALU MUX
    // ======================
    mux21 u_alumux(
        .sel(ALUSrcE),
        .in0(RD2ForwardE),
        .in1(ImmExtE),
        .out(SrcBE)
    );

    // ======================
    // ALU
    // ======================
    ALU u_alu(
        .SrcA(SrcAForwardE),
        .SrcB(SrcBE),
        .ALUControl(ALUControlE),
        .ALUResultE(ALUResultE),
        .zero(zero),
        .less(less)
    );

    assign ALUResult_jalrE = {ALUResultE[31:1], 1'b0};

    // ======================
    // Resolver branch real en Execute
    // ======================
    always_comb begin
        case (funct3E)
            3'b000: BranchCondE = zero;       // BEQ
            3'b001: BranchCondE = ~zero;      // BNE
            3'b100: BranchCondE = less;       // BLT
            3'b101: BranchCondE = ~less;      // BGE
            default: BranchCondE = 1'b0;
        endcase
    end

    assign ActualTakenE = BranchE && BranchCondE;

    assign BranchMispredictE = BranchE &&
                               ((PredTakenE != ActualTakenE) ||
                               (ActualTakenE && (PredTargetE != PCTargetE)));

    always_comb begin
        if (BranchMispredictE) begin
            CorrectPCE = ActualTakenE ? PCTargetE : PCPlus4E;
        end
        else if (JalrE) begin
            CorrectPCE = ALUResult_jalrE;
        end
        else begin
            CorrectPCE = PCTargetE; // JAL
        end
    end

    assign RedirectE = BranchMispredictE || JalE || JalrE;

    // ======================
    // Result MUX
    // ======================
    mux41 u_resultmux(
        .sel(ResultSrcW),
        .in0(ALUResultW),
        .in1(ReadDataW),
        .in2(PCPlus4W),
        .in3(ImmExtW),
        .out(ResultW)
    );

    // ======================
    // Memoria de datos
    // ======================
    //data_mem u_dmem(
    //    .funct3M(funct3M),
    //    .clk(clk),
    //    .WE(MemWriteM),
    //    .A(ALUResultM),
    //    .WD(WriteDataM),
    //    .ReadDataM(ReadDataM)
    //);

    // ======================
    // Register Fetch-Decode
    // ======================
    register_fetch_decode u_rfd(
        .clk(clk),
        .rst(rst),
        .en(~StallD),
        .clear(FlushD),

        .InstrF(InstrF),
        .PCF(PCF),
        .PCPlus4F(PCplus4F),
        .PredTakenF(PredTakenF),
        .PredTargetF(PredTargetF),

        .InstrD(InstrD),
        .PCD(PCD),
        .PCPlus4D(PCPlus4D),
        .PredTakenD(PredTakenD),
        .PredTargetD(PredTargetD)
    );

    // ======================
    // Register Decode-Execute
    // ======================
    register_decode_execute u_rdr(
        .clk(clk),
        .rst(rst),
        .clear(FlushE),

        .RegWriteD(RegWriteD),
        .ALUSrcD(ALUSrcD),
        .MemWriteD(MemWriteD),
        .ResultSrcD(ResultSrcD),
        .ALUControlD(ALUControlD),

        .BranchD(BranchD),
        .JalD(JalD),
        .JalrD(JalrD),
        .PredTakenD(PredTakenD),
        .PredTargetD(PredTargetD),

        .funct3D(InstrD[14:12]),
        .RD1D(RD1D),
        .RD2D(RD2D),
        .Rs1D(InstrD[19:15]),
        .Rs2D(InstrD[24:20]),
        .PCD(PCD),
        .RdD(InstrD[11:7]),
        .ImmExtD(ImmExtD),
        .PCPlus4D(PCPlus4D),

        .RegWriteE(RegWriteE),
        .ALUSrcE(ALUSrcE),
        .MemWriteE(MemWriteE),
        .ResultSrcE(ResultSrcE),
        .ALUControlE(ALUControlE),

        .BranchE(BranchE),
        .JalE(JalE),
        .JalrE(JalrE),
        .PredTakenE(PredTakenE),
        .PredTargetE(PredTargetE),

        .funct3E(funct3E),
        .RD1E(RD1E),
        .RD2E(RD2E),
        .Rs1E(Rs1E),
        .Rs2E(Rs2E),
        .PCE(PCE),
        .RdE(RdE),
        .ImmExtE(ImmExtE),
        .PCPlus4E(PCPlus4E)
    );

    // ======================
    // Register Execute-Memory
    // ======================
    register_execute_mem u_rem(
        .clk(clk),
        .rst(rst),

        .RegWriteE(RegWriteE),
        .MemWriteE(MemWriteE),
        .ResultSrcE(ResultSrcE),

        .funct3E(funct3E),
        .ALUResultE(ALUResultE),
        .WriteDataE(RD2ForwardE),
        .RdE(RdE),
        .ImmExtE(ImmExtE),
        .PCPlus4E(PCPlus4E),

        .RegWriteM(RegWriteM),
        .MemWriteM(MemWriteM),
        .ResultSrcM(ResultSrcM),

        .funct3M(funct3M),
        .ALUResultM(ALUResultM),
        .WriteDataM(WriteDataM),
        .RdM(RdM),
        .ImmExtM(ImmExtM),
        .PCPlus4M(PCPlus4M)
    );

    // ======================
    // Register Memory-Write
    // ======================
    register_mem_write u_rmw(
        .clk(clk),
        .rst(rst),

        .RegWriteM(RegWriteM),
        .ResultSrcM(ResultSrcM),

        .ReadDataM(ReadDataM),
        .ALUResultM(ALUResultM),
        .RdM(RdM),
        .ImmExtM(ImmExtM),
        .PCPlus4M(PCPlus4M),

        .RegWriteW(RegWriteW),
        .ResultSrcW(ResultSrcW),

        .ReadDataW(ReadDataW),
        .ALUResultW(ALUResultW),
        .RdW(RdW),
        .ImmExtW(ImmExtW),
        .PCPlus4W(PCPlus4W)
    );

    // ======================
    // Hazard Unit
    // ======================
    HazardUnit hazard(
        .Rs1E(Rs1E),
        .Rs2E(Rs2E),
        .RdM(RdM),
        .RdW(RdW),
        .Rs1D(InstrD[19:15]),
        .Rs2D(InstrD[24:20]),
        .RdE(RdE),

        .RegWriteM(RegWriteM),
        .RegWriteW(RegWriteW),
        .RedirectE(RedirectE),
        .ResultSrcE(ResultSrcE),

        .ForwardAE(ForwardAE),
        .ForwardBE(ForwardBE),
        .FlushD(FlushD),
        .FlushE(FlushE),
        .StallF(StallF),
        .StallD(StallD),
        .lwStall(lwStall)
    );

endmodule
