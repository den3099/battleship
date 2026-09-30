module ALU (
    input logic [31:0] SrcA,
    input logic [31:0] SrcB,
    input logic [3:0] ALUControl,
    output logic [31:0] ALUResultE,
    output logic zero,
    output logic less
);

always @(*) begin
    case (ALUControl)
        default: ALUResultE = 32'd0;
        4'b0000: ALUResultE = SrcA + SrcB; //Esta es la operacion de suma
        4'b0001: ALUResultE = SrcA - SrcB; //Esta es la operacion de resta
        4'b0101: ALUResultE = ($signed(SrcA) < $signed(SrcB)) ? 32'd1 : 32'd0; //Esta es la operacion set less than 
        4'b0011: ALUResultE = SrcA | SrcB; //Esta es la operacion de OR
        4'b0010: ALUResultE = SrcA & SrcB; //Esta es la operacion de AND
        4'b0100: ALUResultE = SrcA ^ SrcB; //Esta es la operacion de XOR
        4'b0110: ALUResultE = SrcA << SrcB[4:0]; //Esta es la operacion de Shift Logical Left
        4'b1000: ALUResultE = SrcA >> SrcB[4:0]; //Esta es la operacion de Shift Logical Right
        4'b1001: ALUResultE = $signed(SrcA) >>> SrcB[4:0]; //Esta es la operacion de Shift Right Arithmetic
        4'b1011: ALUResultE = (SrcA < SrcB) ? 32'd1 : 32'd0; //Esta es la op SIN unsigned
        4'b1010: ALUResultE = SrcB; // Esta es la  operacion del LUI, que simplemente pasa el valor de SrcB a la salida
    endcase
    zero = (ALUResultE == 32'd0);
    less = ($signed(SrcA) < $signed(SrcB));
end

endmodule