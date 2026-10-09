module main_decoder(
    input  logic [6:0] op,
    input logic [2:0] funct3E,
    input logic zero,
    input logic less,
    output logic Jump,
    output logic RegWriteD,
    output logic MemWriteD,
    output logic ALUSrcD,
    output logic [1:0] ResultSrcD,
    output logic [3:0] ImmSrcD,
    output logic [1:0] ALUOp,
    output logic [1:0] PCSrcE
);
    logic Branch;
    logic BranchNE;
    logic BranchGE;
    logic BranchLT;

always_comb begin
    // valores por defecto
    RegWriteD = 0;
    ALUSrcD   = 0;
    Jump     = 0;
    ResultSrcD = 2'b00;
    Branch   = 0;
    BranchNE = 0;
    BranchGE = 0;
    BranchLT = 0;
    ImmSrcD   = 4'b0000;
    ALUOp    = 2'b00;
    MemWriteD = 0;

    case(op)

        // ======================
        // R-TYPE (ADD, SUB, AND, OR...)
        // ======================
        7'b0110011: begin
            RegWriteD = 1;
            ALUSrcD   = 0;
            ALUOp    = 2'b10;
        end

        // ======================
        // I-TYPE (ADDI, ANDI...)
        // ======================
        7'b0010011: begin
            RegWriteD = 1;
            ALUSrcD   = 1;
            ImmSrcD   = 4'b0000; // I-type
            ALUOp    = 2'b10;
        end

        // ======================
        // LOAD (LW, lb, lh, lbu, lhu)
        // ======================
        7'b0000011: begin
            RegWriteD = 1;
            ALUSrcD   = 1;
            ResultSrcD = 2'b01;
            ImmSrcD   = 4'b0000; // I-type
            ALUOp    = 2'b00; // suma
        end

        // ======================
        // STORE (SW)
        // ======================
        7'b0100011: begin
            ALUSrcD   = 1;
            ImmSrcD   = 4'b0001; // S-type
            ALUOp    = 2'b00;
            MemWriteD = 1; 
        end

        // ======================
        // BRANCH (BEQ, BNEQ)
        // ======================
        7'b1100011: begin
            ImmSrcD = 4'b0010;
            ALUOp  = 2'b01;
            case(funct3E)
                3'b000: Branch   = 1; // BEQ
                3'b001: BranchNE = 1; // BNE
                3'b101: BranchGE = 1; // BGE
                3'b100: BranchLT = 1; // BLT
            endcase
        end
        // ======================
        // Jump (jal)
        // ======================
        7'b1101111: begin 
            RegWriteD = 1;
            ResultSrcD = 2'b10;
            ImmSrcD   = 4'b0011; // J-type
            ALUOp    = 2'b00;
            Jump     = 1;
        end
        // ======================
        // JALR
        // ======================
        7'b1100111: begin
            RegWriteD = 1;
            ALUSrcD   = 1;       // <<<<<< IMPORTANTE
            ResultSrcD = 2'b10;  // guarda PC+4
            ImmSrcD   = 4'b0000; // I-type
            ALUOp    = 2'b00;   // suma
            Jump     = 1;
        end
        // ======================
        // LUI
        // ======================
        7'b0110111: begin
            RegWriteD = 1;
            ResultSrcD = 2'b11;
            ImmSrcD   = 4'b0100;  // U-type
        end
    endcase
end

always @(*) begin
    PCSrcE = 2'b00;

    // ======================
    // JALR
    // ======================
    if (op == 7'b1100111)
        PCSrcE = 2'b10;

    // ======================
    // BRANCHES
    // ======================
    else if (Branch && zero)
        PCSrcE = 2'b01;

    else if (BranchNE && ~zero)
        PCSrcE = 2'b01;

    else if (BranchLT && less)
        PCSrcE = 2'b01;

    else if (BranchGE && ~less)
        PCSrcE = 2'b01;

    // ======================
    // JAL
    // ======================
    else if (Jump)
        PCSrcE = 2'b01;
    end

endmodule