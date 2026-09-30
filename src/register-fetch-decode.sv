module register_fetch_decode (
    input  logic        clk,
    input  logic        rst,
    input  logic        StallD,
    input  logic        clear,

    input  logic [31:0] InstrF,
    input  logic [31:0] PCF,
    input  logic [31:0] PCPlus4F,

    // Informacion de prediccion que viaja con la instruccion
    input  logic        PredTakenF,
    input  logic [31:0] PredTargetF,

    output logic [31:0] InstrD,
    output logic [31:0] PCD,
    output logic [31:0] PCPlus4D,
    output logic        PredTakenD,
    output logic [31:0] PredTargetD
);

    logic en;
    assign en = ~StallD;

always_ff @(posedge clk or posedge rst)
begin
    if (rst || clear)
    begin
        // NOP: addi x0, x0, 0
        InstrD      <= 32'h00000013;
        PCD         <= 32'b0;
        PCPlus4D    <= 32'b0;
        PredTakenD  <= 1'b0;
        PredTargetD <= 32'b0;
    end
    else if (!StallD)
    begin
        InstrD      <= InstrF;
        PCD         <= PCF;
        PCPlus4D    <= PCPlus4F;
        PredTakenD  <= PredTakenF;
        PredTargetD <= PredTargetF;
    end
end

endmodule
