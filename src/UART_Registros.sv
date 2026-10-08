//------------------------------------------------------------------------------
// MODULO : UART_Registros
// FUNCION: Interfaz de bus del RISC-V hacia la UART.
//
// CAMBIOS vs. VHDL
//   [CORRECCION 1] Bus de 32 bits y mapa de direcciones de batalla_pc.py:
//        0x0001_0040  Control/Estado
//        0x0001_0044  Datos TX
//        0x0001_0048  Datos RX
//   [CORRECCION 2] Nueva entrada re_UART: leer 0x0001_0048 genera el pulso
//        rx_leido (libera el RX, RX_VALID -> 0) sin escritura adicional.
//
// MAPA DE REGISTROS (el byte util va en los bits [7:0]; el resto = 0)
//   +--------------+---------+------------------------------------------------+
//   | Direccion    | Acceso  | Contenido                                      |
//   +--------------+---------+------------------------------------------------+
//   | 0x0001_0040  | R       | ESTADO: [7]=activar_rx  [6:5]=0                |
//   |              |         |  [4]=error trama [3]=RX_VALID [2]=RX escuchando|
//   |              |         |  [1]=TX termino  [0]=TX ocupado/peticion pend. |
//   | 0x0001_0040  | W       | CONTROL: [1]=1 -> pulso clr_error              |
//   |              |         |          [0]=1 -> pulso rx_leido (respaldo)    |
//   | 0x0001_0044  | W (R)   | TX_DATA: escribir = cargar byte y pedir envio  |
//   | 0x0001_0048  | R       | RX_DATA: leer = obtener byte + pulso rx_leido  |
//   +--------------+---------+------------------------------------------------+
//
//   Handshake de TX: escribir en 0x44 solo se acepta si no hay peticion
//   pendiente (solicitar_tx_=0) y TX no esta ocupado (estados[0]=0); si no, se
//   IGNORA (el software debe sondear ESTADO[0]). solicitar_tx_ es un NIVEL: sube
//   con la escritura y baja cuando Control acusa con estados[0]=1.
//   rx_leido_ y clr_error_ son pulsos de 1 CLK. La lectura (rdata_pc) es
//   combinacional segun addr_i.
//
// FLUJO
//   RISC-V --addr_i, wdata_i, we_UART, re_UART--> [Registros] --rdata_pc--> RISC-V
//   [Registros] --solicitar_tx, rx_leido, clr_error--> Control
//   Control --activar_rx, estados[4:0]--> [Registros]
//   RX --rx_data[7:0]--> [Registros]     [Registros] --tx_data--> TX
//
// REGISTROS (sufijo _): tx_data_, rx_data_, solicitar_tx_, rx_leido_, clr_error_
//------------------------------------------------------------------------------
module UART_Registros (
    input  logic        CLK,
    input  logic        rst,
    // bus del RISC-V
    input  logic [31:0] addr_i,
    input  logic [31:0] wdata_i,
    input  logic        we_UART,
    input  logic        re_UART,
    output logic [31:0] rdata_pc,
    // hacia Control
    output logic        solicitar_tx,
    output logic        rx_leido,
    output logic        clr_error,
    // desde Control
    input  logic        activar_rx,
    input  logic [4:0]  estados,
    // con RX / TX
    input  logic [7:0]  rx_data,
    output logic [7:0]  tx_data
);

    localparam logic [31:0] ADDR_CTRL = 32'h0001_0040;
    localparam logic [31:0] ADDR_TX   = 32'h0001_0044;
    localparam logic [31:0] ADDR_RX   = 32'h0001_0048;

    logic [7:0] tx_data_      = 8'd0;
    logic [7:0] rx_data_      = 8'd0;
    logic       solicitar_tx_ = 1'b0;
    logic       rx_leido_     = 1'b0;
    logic       clr_error_    = 1'b0;

    // Escritura / lectura con efecto lateral
    always_ff @(posedge CLK) begin
        if (rst) begin
            tx_data_      <= 8'd0;
            rx_data_      <= 8'd0;
            solicitar_tx_ <= 1'b0;
            rx_leido_     <= 1'b0;
            clr_error_    <= 1'b0;
        end else begin
            // pulsos por defecto en 0
            rx_leido_  <= 1'b0;
            clr_error_ <= 1'b0;

            // captura sincronica del dato recibido
            rx_data_ <= rx_data;

            // acuse: Control ya marco TX ocupado -> baja la peticion
            if (solicitar_tx_ && estados[0]) solicitar_tx_ <= 1'b0;

            if (we_UART) begin
                case (addr_i)
                    ADDR_TX: if (!solicitar_tx_ && !estados[0]) begin
                        tx_data_      <= wdata_i[7:0];
                        solicitar_tx_ <= 1'b1;
                    end
                    ADDR_CTRL: begin
                        rx_leido_  <= wdata_i[0];
                        clr_error_ <= wdata_i[1];
                    end
                    default: ;
                endcase
            end

            // [CORRECCION 2] leer RX_DATA libera el receptor
            if (re_UART && (addr_i == ADDR_RX)) rx_leido_ <= 1'b1;
        end
    end

    // Lectura (combinacional)
    always_comb begin
        case (addr_i)
            ADDR_TX:   rdata_pc = {24'd0, tx_data_};
            ADDR_RX:   rdata_pc = {24'd0, rx_data_};
            ADDR_CTRL: rdata_pc = {24'd0, activar_rx, 2'b00,
                                   estados[4:1], (estados[0] | solicitar_tx_)};
            default:   rdata_pc = 32'd0;
        endcase
    end

    assign solicitar_tx = solicitar_tx_;
    assign rx_leido     = rx_leido_;
    assign clr_error    = clr_error_;
    assign tx_data      = tx_data_;

endmodule
