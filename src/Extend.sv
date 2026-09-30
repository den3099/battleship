module Extend (
    input logic [31:0] InstrD,
    input logic [3:0] ImmSrcD,
    output logic [31:0] ImmExtD
);

always @(*) begin
    case (ImmSrcD)

        // Instrucción tipo I
        4'b0000: ImmExtD = {{20{InstrD[31]}}, InstrD[31:20]};

        // Instrucción tipo S
        4'b0001: ImmExtD = {{20{InstrD[31]}}, InstrD[31:25], InstrD[11:7]};

        // B-TYPE (BEQ, BNE)
        4'b0010: ImmExtD = {{19{InstrD[31]}}, InstrD[31], 
                           InstrD[7], InstrD[30:25],
                           InstrD[11:8], 1'b0};

        // Instrucción tipo J
         4'b0011: ImmExtD = {{11{InstrD[31]}}, InstrD[31],
                           InstrD[19:12], InstrD[20],
                           InstrD[30:21], 1'b0};

        // Instrucción tipo U
        4'b0100: ImmExtD = {InstrD[31:12], 12'b0};

        default: ImmExtD = 32'd0;

    endcase
end

endmodule