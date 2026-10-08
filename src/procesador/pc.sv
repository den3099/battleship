module pc(
    input logic clk,
    input logic rst,
    input logic StallF,

    input logic [31:0] PCnext,
    output logic [31:0] PCF
);

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            PCF <= 32'b0;
        end else if (en) begin
            PCF <= PCnext;
        end
    end
endmodule
