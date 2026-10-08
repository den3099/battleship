module branch_predictor #(
    parameter ENTRIES = 64,
    parameter INDEX_BITS = $clog2(ENTRIES),
    parameter TAG_BITS = 32 - INDEX_BITS - 2
)(
    input  logic        clk,
    input  logic        rst,

    // Consulta en Fetch
    input  logic [31:0] PCF,
    output logic        PredTakenF,
    output logic [31:0] PredTargetF,

    // Actualización en Execute
    input  logic        UpdateE,
    input  logic [31:0] PCE,
    input  logic        ActualTakenE,
    input  logic [31:0] ActualTargetE
);

    logic               valid  [ENTRIES-1:0];
    logic               taken  [ENTRIES-1:0];
    logic [31:0]         target [ENTRIES-1:0];
    logic [TAG_BITS-1:0] tag    [ENTRIES-1:0];

    logic [INDEX_BITS-1:0] indexF, indexE;
    logic [TAG_BITS-1:0]   tagF, tagE;
    logic hitF;

    integer i;

    assign indexF = PCF[INDEX_BITS+1:2];
    assign tagF   = PCF[31:INDEX_BITS+2];

    assign indexE = PCE[INDEX_BITS+1:2];
    assign tagE   = PCE[31:INDEX_BITS+2];

    assign hitF = valid[indexF] && (tag[indexF] == tagF);

    assign PredTakenF  = hitF && taken[indexF];
    assign PredTargetF = PredTakenF ? target[indexF] : (PCF + 32'd4);

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < ENTRIES; i = i + 1) begin
                valid[i]  <= 1'b0;
                taken[i]  <= 1'b0;
                target[i] <= 32'b0;
                tag[i]    <= '0;
            end
        end else begin
            if (UpdateE) begin
                valid[indexE]  <= 1'b1;
                tag[indexE]    <= tagE;
                taken[indexE]  <= ActualTakenE;
                target[indexE] <= ActualTargetE;
            end
        end
    end

endmodule