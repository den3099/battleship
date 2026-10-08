//------------------------------------------------------------------------------
// MODULO : UART_TX_Core
// FUNCION: Transmisor serie 8N1 (1 start, 8 datos LSB primero, 1 stop).
//          Sin cambios funcionales vs. la version VHDL.
//
// DESCRIPCION DETALLADA
//   Convierte tx_data[7:0] en la trama serie tx_fisico. La FSM corre a CLK
//   pero AVANZA solo con baud_tick=1; cada bit dura 16 ticks (tick_cnt_ 0..15).
//
//   FSM (tx_state_):
//     TX_IDLE : linea en 1. Espera activar_tx=1 Y baud_tick=1 (asi el start
//               dura exactamente 16 ticks). Copia tx_data a data_reg_ y baja
//               tx_fisico_ (bit de start).
//     TX_START: 16 ticks en 0; luego saca el bit 0.
//     TX_DATA : saca bit_idx_ = 0..7, 16 ticks por bit; tras el 7 pone 1 (stop).
//     TX_STOP : 16 ticks en 1; luego tx_done_=1.
//     TX_DONE : tx_done_ se mantiene en 1 (handshake de NIVEL) hasta que
//               Control baje activar_tx; entonces vuelve a TX_IDLE.
//
// FLUJO
//   Registros --tx_data[7:0]--> [TX] --tx_fisico--> pin
//   Control   --activar_tx----> [TX] --tx_done---> Control
//   Baud_Gen  --baud_tick-----> [TX]
//
// REGISTROS (sufijo _): tx_state_, tick_cnt_, bit_idx_, data_reg_,
//                       tx_fisico_, tx_done_
//------------------------------------------------------------------------------
module UART_TX_Core (
    input  logic       CLK,
    input  logic       rst,
    input  logic       activar_tx,      // desde Control
    input  logic       baud_tick,       // desde Baud_Gen
    input  logic [7:0] tx_data,         // desde Registros
    output logic       tx_done,         // hacia Control
    output logic       tx_fisico        // linea serie
);

    typedef enum logic [2:0] {TX_IDLE, TX_START, TX_DATA, TX_STOP, TX_DONE} tx_state_t;

    tx_state_t   tx_state_  = TX_IDLE;
    logic [3:0]  tick_cnt_  = 4'd0;
    logic [2:0]  bit_idx_   = 3'd0;
    logic [7:0]  data_reg_  = 8'd0;
    logic        tx_fisico_ = 1'b1;     // reposo = 1
    logic        tx_done_   = 1'b0;

    always_ff @(posedge CLK) begin
        if (rst) begin
            tx_state_  <= TX_IDLE;
            tick_cnt_  <= 4'd0;
            bit_idx_   <= 3'd0;
            data_reg_  <= 8'd0;
            tx_fisico_ <= 1'b1;
            tx_done_   <= 1'b0;
        end else begin
            case (tx_state_)

                TX_IDLE: begin
                    tx_fisico_ <= 1'b1;
                    tx_done_   <= 1'b0;
                    tick_cnt_  <= 4'd0;
                    bit_idx_   <= 3'd0;
                    if (activar_tx && baud_tick) begin
                        data_reg_  <= tx_data;     // congela el dato
                        tx_fisico_ <= 1'b0;        // bit de START
                        tx_state_  <= TX_START;
                    end
                end

                TX_START: begin
                    if (baud_tick) begin
                        if (tick_cnt_ == 4'd15) begin
                            tick_cnt_  <= 4'd0;
                            bit_idx_   <= 3'd0;
                            tx_fisico_ <= data_reg_[0];   // LSB primero
                            tx_state_  <= TX_DATA;
                        end else begin
                            tick_cnt_ <= tick_cnt_ + 4'd1;
                        end
                    end
                end

                TX_DATA: begin
                    if (baud_tick) begin
                        if (tick_cnt_ == 4'd15) begin
                            tick_cnt_ <= 4'd0;
                            if (bit_idx_ == 3'd7) begin
                                tx_fisico_ <= 1'b1;       // bit de STOP
                                tx_state_  <= TX_STOP;
                            end else begin
                                bit_idx_   <= bit_idx_ + 3'd1;
                                tx_fisico_ <= data_reg_[bit_idx_ + 3'd1];
                            end
                        end else begin
                            tick_cnt_ <= tick_cnt_ + 4'd1;
                        end
                    end
                end

                TX_STOP: begin
                    if (baud_tick) begin
                        if (tick_cnt_ == 4'd15) begin
                            tick_cnt_ <= 4'd0;
                            tx_done_  <= 1'b1;            // trama terminada
                            tx_state_ <= TX_DONE;
                        end else begin
                            tick_cnt_ <= tick_cnt_ + 4'd1;
                        end
                    end
                end

                TX_DONE: begin
                    tx_done_ <= 1'b1;
                    if (!activar_tx) begin               // Control ya vio el done
                        tx_done_  <= 1'b0;
                        tx_state_ <= TX_IDLE;
                    end
                end

                default: tx_state_ <= TX_IDLE;
            endcase
        end
    end

    assign tx_fisico = tx_fisico_;
    assign tx_done   = tx_done_;

endmodule
