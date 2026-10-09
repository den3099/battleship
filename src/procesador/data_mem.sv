module data_mem #(
    parameter logic [31:0] BASE_ADDR = 32'h0000_2000,
    parameter integer DEPTH_WORDS = 1024
)(
    input logic [2:0] funct3M,
    input logic clk,       
    input logic WE,        //Este es el dato 'MemWrite'
    input logic [31:0] A,  //Este es el dato 'ALUResultM'
    input logic [31:0] WD, //Este es el dato 'WriteDataM'
    output logic [31:0] ReadDataM //Este es el dato que sale de la 'Data Memory'
);

    localparam integer DEPTH_BYTES = DEPTH_WORDS * 4;
    localparam integer INDEX_WIDTH = (DEPTH_WORDS < 2) ? 1 : $clog2(DEPTH_WORDS);

    logic [31:0] mem [0:DEPTH_WORDS-1];
    logic [31:0] word;
    logic [1:0] byte_offset;
    logic [INDEX_WIDTH-1:0] word_index;
    logic address_valid;

    always_comb begin
        address_valid = (A >= BASE_ADDR) && (A < BASE_ADDR + DEPTH_BYTES);
        word_index = INDEX_WIDTH'((A - BASE_ADDR) >> 2);
        byte_offset = A[1:0];
        word = 32'b0;
        if (address_valid) word = mem[word_index];
    end

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
        if (WE && address_valid) begin
            case (funct3M)

                // SB
                3'b000: begin
                    case (byte_offset)
                        2'b00: mem[word_index][7:0]   <= WD[7:0];
                        2'b01: mem[word_index][15:8]  <= WD[7:0];
                        2'b10: mem[word_index][23:16] <= WD[7:0];
                        2'b11: mem[word_index][31:24] <= WD[7:0];
                    endcase
                end

                // SH
                3'b001: begin
                    case (byte_offset[1])
                        1'b0: mem[word_index][15:0]  <= WD[15:0];
                        1'b1: mem[word_index][31:16] <= WD[15:0];
                    endcase
                end

                // SW
                3'b010: begin
                    mem[word_index] <= WD;
                end

            endcase
        end
    end

    // ==========================
    // INIT
    // ==========================
    initial begin
        integer i;
        for (i = 0; i < DEPTH_WORDS; i++) begin
            mem[i] = 0;
        end
    end

endmodule
