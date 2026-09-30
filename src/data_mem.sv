module data_mem(
    input logic [2:0] funct3M,
    input logic clk,       
    input logic WE,        //Este es el dato 'MemWrite'
    input logic [31:0] A,  //Este es el dato 'ALUResultM'
    input logic [31:0] WD, //Este es el dato 'WriteDataM'
    output logic [31:0] ReadDataM //Este es el dato que sale de la 'Data Memory'
);

    logic [31:0] mem [0:255];
    logic [31:0] word;
    logic [1:0] byte_offset;

    assign word = mem[A[31:2]];
    assign byte_offset = A[1:0];

    // ==========================
    // READ (LOAD)
    // ==========================
    always @(*) begin
        case (funct3M)

            // LB
            3'b000: begin
                case (byte_offset)
                    2'b00: ReadDataM = {{24{word[7]}},  word[7:0]};
                    2'b01: ReadDataM = {{24{word[15]}}, word[15:8]};
                    2'b10: ReadDataM = {{24{word[23]}}, word[23:16]};
                    2'b11: ReadDataM = {{24{word[31]}}, word[31:24]};
                endcase
            end

            // LH
            3'b001: begin
                case (byte_offset[1])
                    1'b0: ReadDataM = {{16{word[15]}}, word[15:0]};
                    1'b1: ReadDataM = {{16{word[31]}}, word[31:16]};
                endcase
            end

            // LW
            3'b010: ReadDataM = word;

            // LBU
            3'b100: begin
                case (byte_offset)
                    2'b00: ReadDataM = {24'b0, word[7:0]};
                    2'b01: ReadDataM = {24'b0, word[15:8]};
                    2'b10: ReadDataM = {24'b0, word[23:16]};
                    2'b11: ReadDataM = {24'b0, word[31:24]};
                endcase
            end

            // LHU
            3'b101: begin
                case (byte_offset[1])
                    1'b0: ReadDataM = {16'b0, word[15:0]};
                    1'b1: ReadDataM = {16'b0, word[31:16]};
                endcase
            end

            default: ReadDataM = 32'd0;
        endcase
    end

    // ==========================
    // WRITE (STORE)
    // ==========================
    always_ff @(posedge clk) begin
        if (WE) begin
            case (funct3M)

                // SB
                3'b000: begin
                    case (byte_offset)
                        2'b00: mem[A[31:2]][7:0]   <= WD[7:0];
                        2'b01: mem[A[31:2]][15:8]  <= WD[7:0];
                        2'b10: mem[A[31:2]][23:16] <= WD[7:0];
                        2'b11: mem[A[31:2]][31:24] <= WD[7:0];
                    endcase
                end

                // SH
                3'b001: begin
                    case (byte_offset[1])
                        1'b0: mem[A[31:2]][15:0]  <= WD[15:0];
                        1'b1: mem[A[31:2]][31:16] <= WD[15:0];
                    endcase
                end

                // SW
                3'b010: begin
                    mem[A[31:2]] <= WD;
                end

            endcase
        end
    end

    // ==========================
    // INIT
    // ==========================
    initial begin
        integer i;
        for (i = 0; i < 256; i++) begin
            mem[i] = 0;
        end
    end

endmodule