module alu_decoder(
    input  logic [1:0] ALUOp,
    input  logic [2:0] funct3,
    input  logic [6:0] funct7,
    output logic [3:0] ALUControlD
);

always @(*) begin

    case(ALUOp)

        // ======================
        // LOAD / STORE → SUMA
        // ======================
        2'b00: ALUControlD = 4'b0000;

        // ======================
        // BRANCH → RESTA
        // ======================
        2'b01: ALUControlD = 4'b0001;

        // ======================
        // R-type / I-type
        // ======================
        2'b10: begin
            case(funct3)

                // ADD / SUB / ADDI
                3'b000: begin
                    if (funct7 == 7'b0100000)
                        ALUControlD = 4'b0001; // SUB
                    else
                        ALUControlD = 4'b0000; // ADD / ADDI
                end
                // AND / ANDI
                3'b111: ALUControlD = 4'b0010;

                // OR / ORI
                3'b110: ALUControlD = 4'b0011;

                // XOR / XORI
                3'b100: ALUControlD = 4'b0100;

                // SLT / SLTI
                3'b010: ALUControlD = 4'b0101;

                // SLTU / SLTIU
                3'b011: ALUControlD = 4'b1011;

                // SLL / SLLI
                3'b001: ALUControlD = 4'b0110;

                // SRL / SRA / SRLI / SRAI
                3'b101: begin
                    if (funct7 == 7'b0100000)
                        ALUControlD = 4'b1001; // SRA / SRAI
                    else
                        ALUControlD = 4'b1000; // SRL / SRLI
                end

                default: ALUControlD = 4'b0000;
            endcase
        end

        default: ALUControlD = 4'b0000;

    endcase
end

endmodule