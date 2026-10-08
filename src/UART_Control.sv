//------------------------------------------------------------------------------
// MODULO : UART_Control
// FUNCION: Coordina Registros, TX, RX y Baud_Gen.
//
// CAMBIO vs. VHDL
//   [CORRECCION 3] Si solicitar_rx llega junto con rx_frame_err (byte con stop
//   invalido), el byte se DESCARTA: no sube rx_valid_, el RX sigue escuchando
//   y solo se marca err_flag_. La PC lo detecta por timeout y reintenta, tal
//   como asume batalla_pc.py.
//
// DESCRIPCION DETALLADA (tres procesos independientes: UART full-duplex)
//   (A) FSM de TRANSMISION (tx_ctrl_state_)
//       TXC_IDLE : espera solicitar_tx=1 (nivel mantenido por Registros).
//                  -> activar_tx_=1, tx_busy_=1 -> TXC_RUN. (tx_busy_ es el
//                  "acuse": Registros baja solicitar_tx al ver estados[0]=1.)
//       TXC_RUN  : espera tx_done=1 -> activar_tx_=0, tx_busy_=0,
//                  tx_done_flag_=1 -> TXC_CLEAR.
//       TXC_CLEAR: espera tx_done=0 y vuelve a TXC_IDLE (evita leer un done viejo).
//   (B) FSM de RECEPCION (rx_ctrl_state_)
//       RXC_LISTEN: rx_enable_=1. Al llegar solicitar_rx SIN error de trama:
//                   rx_enable_=0 (congela rx_data), rx_valid_=1 -> RXC_HOLD.
//                   Con error de trama: descarta y sigue en RXC_LISTEN.
//       RXC_HOLD  : espera rx_leido (pulso de Registros al LEER 0x0001_0048)
//                   -> rx_valid_=0, rx_enable_=1 -> RXC_LISTEN.
//   (C) err_flag_: se pone en 1 con rx_frame_err y se limpia con clr_error.
//
//   estados[4:0] hacia Registros:
//     [0] TX ocupado   [1] TX termino   [2] RX escuchando
//     [3] dato RX valido (pendiente de leer)   [4] error de trama
//   baud_en = activar_tx_ | rx_enable_ ; activar_rx = rx_enable_.
//
// FLUJO
//   Registros: solicitar_tx, rx_leido, clr_error ---> Control
//   Control  : activar_rx, estados[4:0]           ---> Registros
//   TX: tx_done ---> Control      Control: activar_tx ---> TX
//   RX: solicitar_rx, rx_frame_err ---> Control   Control: rx_enable ---> RX
//   Control: baud_en ---> Baud_Gen
//
// REGISTROS (sufijo _): tx_ctrl_state_, rx_ctrl_state_, activar_tx_,
//   rx_enable_, tx_busy_, tx_done_flag_, rx_valid_, err_flag_
//------------------------------------------------------------------------------
module UART_Control (
    input  logic       CLK,
    input  logic       rst,
    // desde Registros
    input  logic       solicitar_tx,
    input  logic       rx_leido,
    input  logic       clr_error,
    // hacia Registros
    output logic       activar_rx,
    output logic [4:0] estados,
    // con TX
    input  logic       tx_done,
    output logic       activar_tx,
    // con RX
    input  logic       solicitar_rx,
    input  logic       rx_frame_err,
    output logic       rx_enable,
    // hacia Baud_Gen
    output logic       baud_en
);

    typedef enum logic [1:0] {TXC_IDLE, TXC_RUN, TXC_CLEAR} tx_ctrl_t;
    typedef enum logic       {RXC_LISTEN = 1'b0, RXC_HOLD = 1'b1} rx_ctrl_t;

    tx_ctrl_t tx_ctrl_state_ = TXC_IDLE;
    rx_ctrl_t rx_ctrl_state_ = RXC_LISTEN;

    logic activar_tx_   = 1'b0;
    logic rx_enable_    = 1'b1;     // RX escucha desde el reset
    logic tx_busy_      = 1'b0;
    logic tx_done_flag_ = 1'b0;
    logic rx_valid_     = 1'b0;
    logic err_flag_     = 1'b0;

    // (A) Control de transmision
    always_ff @(posedge CLK) begin
        if (rst) begin
            tx_ctrl_state_ <= TXC_IDLE;
            activar_tx_    <= 1'b0;
            tx_busy_       <= 1'b0;
            tx_done_flag_  <= 1'b0;
        end else begin
            case (tx_ctrl_state_)
                TXC_IDLE: if (solicitar_tx) begin
                    activar_tx_    <= 1'b1;
                    tx_busy_       <= 1'b1;
                    tx_done_flag_  <= 1'b0;
                    tx_ctrl_state_ <= TXC_RUN;
                end
                TXC_RUN: if (tx_done) begin
                    activar_tx_    <= 1'b0;
                    tx_busy_       <= 1'b0;
                    tx_done_flag_  <= 1'b1;
                    tx_ctrl_state_ <= TXC_CLEAR;
                end
                TXC_CLEAR: if (!tx_done) tx_ctrl_state_ <= TXC_IDLE;
                default:   tx_ctrl_state_ <= TXC_IDLE;
            endcase
        end
    end

    // (B) Control de recepcion
    always_ff @(posedge CLK) begin
        if (rst) begin
            rx_ctrl_state_ <= RXC_LISTEN;
            rx_enable_     <= 1'b1;
            rx_valid_      <= 1'b0;
        end else begin
            case (rx_ctrl_state_)
                RXC_LISTEN: begin
                    rx_enable_ <= 1'b1;
                    if (solicitar_rx && !rx_frame_err) begin   // byte bueno
                        rx_enable_     <= 1'b0;                // congela rx_data
                        rx_valid_      <= 1'b1;
                        rx_ctrl_state_ <= RXC_HOLD;
                    end
                    // si rx_frame_err=1 el byte se descarta (sigue escuchando)
                end
                RXC_HOLD: if (rx_leido) begin
                    rx_valid_      <= 1'b0;
                    rx_enable_     <= 1'b1;
                    rx_ctrl_state_ <= RXC_LISTEN;
                end
                default: rx_ctrl_state_ <= RXC_LISTEN;
            endcase
        end
    end

    // (C) Flag de error de trama (pegajoso hasta clr_error)
    always_ff @(posedge CLK) begin
        if (rst)               err_flag_ <= 1'b0;
        else if (rx_frame_err) err_flag_ <= 1'b1;
        else if (clr_error)    err_flag_ <= 1'b0;
    end

    // Salidas
    assign activar_tx = activar_tx_;
    assign rx_enable  = rx_enable_;
    assign activar_rx = rx_enable_;
    assign baud_en    = activar_tx_ | rx_enable_;
    assign estados    = {err_flag_, rx_valid_, rx_enable_, tx_done_flag_, tx_busy_};

endmodule
