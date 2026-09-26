module traductor_direcciones (
    input  logic        we_o,
    input  logic [31:0] DataAddress_i,

    output logic [2:0]  select_o,

    output logic        we_mem,
    output logic        we_displays,
    output logic        we_buzzer,
    output logic        we_btns,
    output logic        we_pc,
    output logic        we_vga
);

    localparam MEMORIA = 1'b0;
    localparam PERIFERICOS = 1'b1;

    logic Direcciones;

    always_comb begin
        Direcciones = 0;
        case(DataAddress_i[16])
                1'b0: Direcciones = MEMORIA;
                1'b1: Direcciones = PERIFERICOS;
                default: Direcciones = MEMORIA;
        endcase
    end

    always_comb begin
        we_mem      = 1'b0;
        we_displays = 1'b0;
        we_buzzer   = 1'b0;
        we_btns     = 1'b0;
        we_pc       = 1'b0;
        we_vga      = 1'b0;
        select_o    = 3'b111;

        case(Direcciones)
            MEMORIA: begin
                select_o = 3'b000;
                if (we_o) begin
                    we_mem = 1'b1;
                end
            end

            PERIFERICOS: begin
                case(DataAddress_i[15:0]) inside
                    [16'h1000:16'h17FF]: begin
                        select_o = 3'b101;
                        if (we_o) begin
                            we_vga = 1'b1;
                        end
                    end

                    16'h0040,
                    16'h0044,
                    16'h0048: begin
                        select_o = 3'b100;
                        if (we_o) begin
                            we_pc = 1'b1;
                        end
                    end

                    16'h0120: begin
                        select_o = 3'b011;
                        if (we_o) begin
                            we_btns = 1'b1;
                        end
                    end

                    16'h0130,
                    16'h0138: begin
                        select_o = 3'b001;
                        if (we_o) begin
                            we_displays = 1'b1;
                        end
                    end

                    16'h0140: begin
                        select_o = 3'b010;
                        if (we_o) begin
                            we_buzzer = 1'b1;
                        end
                    end

                    default: select_o = 3'b111;
                endcase
            end

            default: begin
                select_o = 3'b111;
                we_mem = 1'b0;
                we_displays = 1'b0;
                we_buzzer = 1'b0;
                we_btns = 1'b0;
                we_pc = 1'b0;
                we_vga = 1'b0;
            end
        endcase
    end

endmodule