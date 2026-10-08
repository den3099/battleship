//------------------------------------------------------------------------------
// MODULO : UART_RX_Core
// FUNCION: Receptor serie 8N1 con sobremuestreo x16.
//          Sin cambios funcionales vs. la version VHDL.
//
// DESCRIPCION DETALLADA
//   1) rx_fisico es asincrono: pasa por 2 flip-flops (rx_sync_); la FSM usa
//      rx_sync_[1] (muestra estable).
//   2) La FSM avanza solo con baud_tick y solo si rx_enable=1. Con
//      rx_enable=0 se fuerza a RX_IDLE pero rx_data_ CONSERVA el ultimo byte
//      (Registros lo lee estable).
//
//   FSM (rx_state_):
//     RX_IDLE : espera rx_sync_[1]=0 (posible start).
//     RX_START: cuenta 8 ticks (mitad del bit). Si la linea volvio a 1 era
//               ruido -> RX_IDLE; si sigue en 0 -> RX_DATA.
//     RX_DATA : cada 16 ticks (centro de cada bit) guarda la linea en
//               shift_reg_[bit_idx_], bit_idx_ = 0..7 (LSB primero).
//     RX_STOP : 16 ticks despues (centro del stop) copia shift_reg_ a rx_data_,
//               emite pulso solicitar_rx_ y pulso rx_frame_err_ (=1 si el stop
//               no es 1). Ambos pulsos salen en el MISMO ciclo; Control usa esa
//               coincidencia para DESCARTAR el byte erroneo [CORRECCION 3].
//
// FLUJO
//   pin rx_fisico --> [sync 2FF] --> FSM
//   Control --rx_enable--> [RX]     Baud_Gen --baud_tick--> [RX]
//   [RX] --rx_data[7:0]--> Registros
//   [RX] --solicitar_rx, rx_frame_err--> Control
//
// REGISTROS (sufijo _): rx_sync_, rx_state_, tick_cnt_, bit_idx_, shift_reg_,
//                       rx_data_, solicitar_rx_, rx_frame_err_
//------------------------------------------------------------------------------
module UART_RX_Core (
    input  logic       CLK,
    input  logic       rst,
    input  logic       rx_enable,       // desde Control
    input  logic       baud_tick,       // desde Baud_Gen
    input  logic       rx_fisico,       // linea serie
    output logic [7:0] rx_data,         // hacia Registros
    output logic       solicitar_rx,    // hacia Control (pulso 1 CLK)
    output logic       rx_frame_err     // hacia Control (pulso 1 CLK)
);

    typedef enum logic [1:0] {RX_IDLE, RX_START, RX_DATA, RX_STOP} rx_state_t;

    rx_state_t   rx_state_      = RX_IDLE;
    logic [1:0]  rx_sync_       = 2'b11;
    logic [3:0]  tick_cnt_      = 4'd0;
    logic [2:0]  bit_idx_       = 3'd0;
    logic [7:0]  shift_reg_     = 8'd0;
    logic [7:0]  rx_data_       = 8'd0;
    logic        solicitar_rx_  = 1'b0;
    logic        rx_frame_err_  = 1'b0;

    always_ff @(posedge CLK) begin
        // sincronizador (rx_sync_[1] = muestra mas antigua)
        rx_sync_      <= {rx_sync_[0], rx_fisico};
        // pulsos: por defecto 0 en cada ciclo
        solicitar_rx_ <= 1'b0;
        rx_frame_err_ <= 1'b0;

        if (rst) begin
            rx_state_  <= RX_IDLE;
            rx_sync_   <= 2'b11;
            tick_cnt_  <= 4'd0;
            bit_idx_   <= 3'd0;
            shift_reg_ <= 8'd0;
            rx_data_   <= 8'd0;
        end else if (!rx_enable) begin
            rx_state_  <= RX_IDLE;          // aborta; rx_data_ se conserva
            tick_cnt_  <= 4'd0;
            bit_idx_   <= 3'd0;
        end else if (baud_tick) begin
            case (rx_state_)

                RX_IDLE: begin
                    tick_cnt_ <= 4'd0;
                    bit_idx_  <= 3'd0;
                    if (!rx_sync_[1]) rx_state_ <= RX_START;
                end

                RX_START: begin
                    if (rx_sync_[1]) begin                 // falsa alarma
                        rx_state_ <= RX_IDLE;
                    end else if (tick_cnt_ == 4'd7) begin  // mitad del start
                        tick_cnt_ <= 4'd0;
                        bit_idx_  <= 3'd0;
                        rx_state_ <= RX_DATA;
                    end else begin
                        tick_cnt_ <= tick_cnt_ + 4'd1;
                    end
                end

                RX_DATA: begin
                    if (tick_cnt_ == 4'd15) begin          // centro del bit
                        tick_cnt_            <= 4'd0;
                        shift_reg_[bit_idx_] <= rx_sync_[1];
                        if (bit_idx_ == 3'd7) rx_state_ <= RX_STOP;
                        else                  bit_idx_  <= bit_idx_ + 3'd1;
                    end else begin
                        tick_cnt_ <= tick_cnt_ + 4'd1;
                    end
                end

                RX_STOP: begin
                    if (tick_cnt_ == 4'd15) begin          // centro del stop
                        tick_cnt_     <= 4'd0;
                        rx_data_      <= shift_reg_;
                        solicitar_rx_ <= 1'b1;             // byte completo
                        rx_frame_err_ <= ~rx_sync_[1];     // stop debe ser 1
                        rx_state_     <= RX_IDLE;
                    end else begin
                        tick_cnt_ <= tick_cnt_ + 4'd1;
                    end
                end

                default: rx_state_ <= RX_IDLE;
            endcase
        end
    end

    assign rx_data      = rx_data_;
    assign solicitar_rx = solicitar_rx_;
    assign rx_frame_err = rx_frame_err_;

endmodule
