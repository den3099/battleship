module HazardUnit (
    input logic [4:0] Rs1E,
    input logic [4:0] Rs2E,
    input logic [4:0] RdM,
    input logic [4:0] RdW,
    input logic [4:0] Rs1D,
    input logic [4:0] Rs2D,
    input logic [4:0] RdE,

    input logic RegWriteW,
    input logic RegWriteM,
    input logic RedirectE,
    input logic [1:0] ResultSrcE,

    output logic [1:0] ForwardAE,
    output logic [1:0] ForwardBE,
    output logic FlushD,
    output logic FlushE,
    output logic StallF,
    output logic StallD,
    output logic lwStall
);

// Forward para SrcA
always_comb begin
    if (((Rs1E == RdM) && RegWriteM) && (Rs1E != 5'b0)) begin
        ForwardAE = 2'b10;   // Desde Memory
    end
    else if (((Rs1E == RdW) && RegWriteW) && (Rs1E != 5'b0)) begin
        ForwardAE = 2'b01;   // Desde WriteBack
    end
    else begin
        ForwardAE = 2'b00;   // Sin forwarding
    end
end

// Forward para SrcB
always_comb begin
    if (((Rs2E == RdM) && RegWriteM) && (Rs2E != 5'b0)) begin
        ForwardBE = 2'b10;   // Desde Memory
    end
    else if (((Rs2E == RdW) && RegWriteW) && (Rs2E != 5'b0)) begin
        ForwardBE = 2'b01;   // Desde WriteBack
    end
    else begin
        ForwardBE = 2'b00;   // Sin forwarding
    end
end

// Load-use hazard
assign lwStall = ResultSrcE[0] &&
                 (RdE != 5'b0) &&
                 ((Rs1D == RdE) || (Rs2D == RdE));

assign StallF = lwStall;
assign StallD = lwStall;

// Con branch prediction, no se limpia por "branch taken".
// Se limpia solo cuando Execute redirige el PC por misprediction, jal o jalr.
assign FlushD = RedirectE;
assign FlushE = lwStall | RedirectE;

endmodule
