#!/usr/bin/env python3
"""Interfaz de PC para el Jugador 2 del proyecto Batalla Naval."""

from __future__ import annotations

import argparse
import queue
import threading
import time
import tkinter as tk
from tkinter import messagebox, ttk

try:
    import serial
    from serial.tools import list_ports
except ImportError:  # Permite abrir la ayuda incluso si falta pyserial.
    serial = None
    list_ports = None

BAUD = 115_200
SOF = 0xAA
PLACEMENT_START = 0x11
PLACE_SHIP = 0x01
PLACE_REPLY = 0x12
BATTLE_START = 0x13
TURN = 0x14
SHOT_RESULT = 0x15
SHOT_RECEIVED = 0x16
GAME_OVER = 0x17
SHIP_SIZES = (2, 3, 4)
REASONS = {0: "sin rechazo", 1: "traslape", 2: "fuera del tablero", 3: "ID u orientación inválidos"}


def make_frame(message_type: int, d0: int = 0, d1: int = 0,
               d2: int = 0, d3: int = 0) -> bytes:
    payload = [message_type, d0, d1, d2, d3]
    checksum = 0
    for value in payload:
        if not 0 <= value <= 0xFF:
            raise ValueError("Cada campo de una trama debe estar entre 0 y 255")
        checksum ^= value
    return bytes([SOF, *payload, checksum])


class FrameParser:
    """Parser de tramas AA + tipo + cuatro datos + XOR."""

    def __init__(self) -> None:
        self.buffer = bytearray()

    def feed(self, value: int) -> tuple[int, int, int, int, int] | None:
        if not self.buffer:
            if value == SOF:
                self.buffer.append(value)
            return None
        self.buffer.append(value)
        if len(self.buffer) < 7:
            return None
        frame = bytes(self.buffer)
        self.buffer.clear()
        check = 0
        for item in frame[1:6]:
            check ^= item
        if check != frame[6]:
            # Recupera una posible sincronización que aparezca dentro del flujo.
            last_sof = frame.rfind(bytes([SOF]), 1)
            if last_sof >= 0:
                self.buffer.extend(frame[last_sof:])
            return None
        return tuple(frame[1:6])


class BattleshipPC:
    def __init__(self, root: tk.Tk, initial_port: str | None = None,
                 byte_gap_ms: float = 2.0) -> None:
        self.root = root
        self.root.title("Batalla Naval - Jugador 2")
        self.root.minsize(820, 610)
        self.byte_gap = max(0.0, byte_gap_ms / 1000.0)
        self.serial_port = None
        self.stop_event = threading.Event()
        self.tx_queue: queue.Queue[bytes] = queue.Queue()
        self.rx_queue: queue.Queue[tuple[int, int, int, int, int] | str] = queue.Queue()
        self.io_thread: threading.Thread | None = None

        self.ship_id = 0
        self.placement_active = False
        self.pending_placement: tuple[int, list[tuple[int, int]]] | None = None
        self.turn = 0
        self.pending_shot: tuple[int, int] | None = None
        self.own_board = [[0 for _ in range(8)] for _ in range(8)]
        self.rival_board = [[0 for _ in range(8)] for _ in range(8)]
        self.own_cells: set[tuple[int, int]] = set()
        self.shots_fired = 0
        self.shots_received = 0
        self.hits_made = 0
        self.hits_received = 0

        self.port_var = tk.StringVar(value=initial_port or "")
        self.status_var = tk.StringVar(value="Desconectado")
        self.phase_var = tk.StringVar(value="Esperando conexión y señal de inicio")
        self.ship_var = tk.StringVar(value="Esperando inicio de colocación")
        self.row_var = tk.StringVar(value="0")
        self.col_var = tk.StringVar(value="0")
        self.orientation_var = tk.StringVar(value="Horizontal")
        self.shot_row_var = tk.StringVar(value="0")
        self.shot_col_var = tk.StringVar(value="0")

        self._build_ui()
        self.refresh_ports()
        self.root.after(50, self._drain_events)
        self.root.protocol("WM_DELETE_WINDOW", self.close)

    def _build_ui(self) -> None:
        connection = ttk.LabelFrame(self.root, text="Conexión UART")
        connection.pack(fill="x", padx=10, pady=8)
        ttk.Label(connection, text="Puerto:").pack(side="left", padx=(8, 3), pady=7)
        self.port_combo = ttk.Combobox(connection, textvariable=self.port_var, width=18)
        self.port_combo.pack(side="left", padx=4)
        ttk.Button(connection, text="Actualizar", command=self.refresh_ports).pack(side="left", padx=4)
        self.connect_button = ttk.Button(connection, text="Conectar", command=self.connect)
        self.connect_button.pack(side="left", padx=4)
        ttk.Label(connection, textvariable=self.status_var).pack(side="left", padx=12)

        ttk.Label(self.root, textvariable=self.phase_var, font=("Segoe UI", 12, "bold")).pack(anchor="w", padx=14)

        boards = ttk.Frame(self.root)
        boards.pack(fill="both", expand=True, padx=10, pady=6)
        self.own_cells_ui = self._make_board(boards, "Mi tablero (Jugador 2)", 0)
        self.rival_cells_ui = self._make_board(boards, "Tablero rival conocido", 1)

        controls = ttk.Frame(self.root)
        controls.pack(fill="x", padx=10, pady=4)
        place_box = ttk.LabelFrame(controls, text="Colocación de flota")
        place_box.pack(side="left", fill="both", expand=True, padx=(0, 5))
        ttk.Label(place_box, textvariable=self.ship_var).grid(row=0, column=0, columnspan=6, sticky="w", padx=7, pady=5)
        ttk.Label(place_box, text="Fila").grid(row=1, column=0, padx=5)
        ttk.Spinbox(place_box, from_=0, to=7, width=4, textvariable=self.row_var).grid(row=1, column=1)
        ttk.Label(place_box, text="Columna").grid(row=1, column=2, padx=5)
        ttk.Spinbox(place_box, from_=0, to=7, width=4, textvariable=self.col_var).grid(row=1, column=3)
        ttk.Combobox(place_box, textvariable=self.orientation_var, values=("Horizontal", "Vertical"),
                     state="readonly", width=12).grid(row=1, column=4, padx=5)
        self.place_button = ttk.Button(place_box, text="Enviar barco", command=self.send_placement, state="disabled")
        self.place_button.grid(row=1, column=5, padx=6, pady=5)

        shot_box = ttk.LabelFrame(controls, text="Disparo")
        shot_box.pack(side="left", fill="both", expand=True, padx=(5, 0))
        ttk.Label(shot_box, text="Fila").grid(row=0, column=0, padx=5)
        ttk.Spinbox(shot_box, from_=0, to=7, width=4, textvariable=self.shot_row_var).grid(row=0, column=1)
        ttk.Label(shot_box, text="Columna").grid(row=0, column=2, padx=5)
        ttk.Spinbox(shot_box, from_=0, to=7, width=4, textvariable=self.shot_col_var).grid(row=0, column=3)
        self.shot_button = ttk.Button(shot_box, text="Disparar", command=self.send_shot, state="disabled")
        self.shot_button.grid(row=0, column=4, padx=8, pady=5)

        log_frame = ttk.LabelFrame(self.root, text="Eventos")
        log_frame.pack(fill="x", padx=10, pady=(2, 9))
        self.log = tk.Text(log_frame, height=5, wrap="word", state="disabled")
        self.log.pack(fill="x", padx=5, pady=5)

    def _make_board(self, parent: ttk.Frame, title: str, column: int):
        frame = ttk.LabelFrame(parent, text=title)
        frame.grid(row=0, column=column, sticky="nsew", padx=5)
        parent.columnconfigure(column, weight=1)
        for idx in range(8):
            ttk.Label(frame, text=str(idx)).grid(row=0, column=idx + 1, padx=3)
            ttk.Label(frame, text=str(idx)).grid(row=idx + 1, column=0, pady=2)
        cells = []
        for row in range(8):
            cell_row = []
            for col in range(8):
                label = tk.Label(frame, text="·", width=3, height=1, relief="ridge",
                                 bg="#dbeafe", font=("Segoe UI", 11, "bold"))
                label.grid(row=row + 1, column=col + 1, padx=1, pady=1)
                cell_row.append(label)
            cells.append(cell_row)
        return cells

    def refresh_ports(self) -> None:
        ports = [] if list_ports is None else [item.device for item in list_ports.comports()]
        self.port_combo["values"] = ports
        if not self.port_var.get() and ports:
            self.port_var.set(ports[0])

    def connect(self) -> None:
        if serial is None:
            messagebox.showerror("Falta pyserial", "Instala las dependencias con: python -m pip install -r app_pc/requirements.txt")
            return
        port = self.port_var.get().strip()
        if not port:
            messagebox.showwarning("Puerto requerido", "Selecciona o escribe el puerto COM del adaptador USB-UART.")
            return
        try:
            self.serial_port = serial.Serial(port, BAUD, timeout=0.05, write_timeout=1)
        except serial.SerialException as error:
            messagebox.showerror("No se pudo abrir el puerto", str(error))
            return
        self.stop_event.clear()
        self.io_thread = threading.Thread(target=self._serial_worker, daemon=True)
        self.io_thread.start()
        self.status_var.set(f"Conectado a {port} · {BAUD} baudios")
        self.connect_button.configure(text="Desconectar", command=self.disconnect)
        self._log(f"Puerto {port} abierto a {BAUD} baudios.")

    def disconnect(self) -> None:
        self.stop_event.set()
        if self.serial_port is not None:
            try:
                self.serial_port.close()
            except Exception:
                pass
            self.serial_port = None
        self.status_var.set("Desconectado")
        self.connect_button.configure(text="Conectar", command=self.connect)
        self.place_button.configure(state="disabled")
        self.shot_button.configure(state="disabled")

    def _serial_worker(self) -> None:
        parser = FrameParser()
        try:
            while not self.stop_event.is_set():
                try:
                    byte = self.serial_port.read(1)
                    if byte:
                        frame = parser.feed(byte[0])
                        if frame is not None:
                            self.rx_queue.put(frame)
                    frame_to_send = self.tx_queue.get_nowait()
                except queue.Empty:
                    continue
                except Exception as error:
                    self.rx_queue.put(f"Error UART: {error}")
                    break
                for value in frame_to_send:
                    if self.stop_event.is_set():
                        break
                    self.serial_port.write(bytes([value]))
                    if self.byte_gap:
                        time.sleep(self.byte_gap)
        finally:
            if self.serial_port is not None:
                try:
                    self.serial_port.close()
                except Exception:
                    pass
                self.serial_port = None

    def _queue_frame(self, message_type: int, d0: int = 0, d1: int = 0,
                     d2: int = 0, d3: int = 0) -> None:
        if self.serial_port is None:
            messagebox.showwarning("Sin conexión", "Conecta primero el puerto UART.")
            return
        self.tx_queue.put(make_frame(message_type, d0, d1, d2, d3))

    def send_placement(self) -> None:
        if not self.placement_active or self.ship_id >= len(SHIP_SIZES) or self.pending_placement:
            return
        try:
            row, col = int(self.row_var.get()), int(self.col_var.get())
        except ValueError:
            messagebox.showwarning("Coordenadas inválidas", "Fila y columna deben ser enteros entre 0 y 7.")
            return
        orientation = 0 if self.orientation_var.get() == "Horizontal" else 1
        size = SHIP_SIZES[self.ship_id]
        cells = [(row, col + step) if orientation == 0 else (row + step, col) for step in range(size)]
        if not all(0 <= r < 8 and 0 <= c < 8 for r, c in cells):
            messagebox.showwarning("Fuera del tablero", "El barco no cabe desde esa casilla con esa orientación.")
            return
        if any(cell in self.own_cells for cell in cells):
            messagebox.showwarning("Traslape", "El barco se superpone con otro barco ya colocado.")
            return
        self.pending_placement = (self.ship_id, cells)
        self._queue_frame(PLACE_SHIP, self.ship_id, row, col, orientation)
        self.place_button.configure(state="disabled")
        self._log(f"Enviado barco {self.ship_id} (tamaño {size}), fila {row}, columna {col}, {self.orientation_var.get().lower()}.")

    def send_shot(self) -> None:
        if self.turn != 2 or self.pending_shot is not None:
            return
        try:
            row, col = int(self.shot_row_var.get()), int(self.shot_col_var.get())
        except ValueError:
            messagebox.showwarning("Coordenadas inválidas", "Fila y columna deben ser enteros entre 0 y 7.")
            return
        if not (0 <= row < 8 and 0 <= col < 8):
            messagebox.showwarning("Coordenadas inválidas", "Fila y columna deben estar entre 0 y 7.")
            return
        if self.rival_board[row][col] != 0:
            messagebox.showwarning("Casilla repetida", "Esa casilla ya fue atacada.")
            return
        self.pending_shot = (row, col)
        self._queue_frame(0x02, row, col, 0, 0)
        self.shot_button.configure(state="disabled")
        self._log(f"Disparo enviado a ({row}, {col}).")

    def _drain_events(self) -> None:
        while True:
            try:
                event = self.rx_queue.get_nowait()
            except queue.Empty:
                break
            if isinstance(event, str):
                self._log(event)
                self.status_var.set("Error en el puerto; revisa la conexión")
            else:
                self._handle_frame(event)
        self.root.after(50, self._drain_events)

    def _handle_frame(self, frame: tuple[int, int, int, int, int]) -> None:
        msg, d0, d1, d2, d3 = frame
        if msg == PLACEMENT_START:
            self.placement_active = True
            self.ship_id = 0
            self.pending_placement = None
            self.pending_shot = None
            self.turn = 0
            self.own_board = [[0 for _ in range(8)] for _ in range(8)]
            self.rival_board = [[0 for _ in range(8)] for _ in range(8)]
            self.own_cells.clear()
            self.shots_fired = self.shots_received = 0
            self.hits_made = self.hits_received = 0
            self._render_boards()
            self.phase_var.set("Colocación: espera y coloca tus 3 barcos")
            self._update_ship_controls()
            self._log("La FPGA inició la fase de colocación.")
        elif msg == PLACE_REPLY:
            if self.pending_placement is None:
                self._log(f"Respuesta de colocación recibida sin solicitud pendiente (ID {d0}).")
                return
            expected_id, cells = self.pending_placement
            if d0 != expected_id:
                self._log(f"Respuesta para ID {d0}; se esperaba ID {expected_id}.")
                return
            self.pending_placement = None
            if d1 == 1:
                for row, col in cells:
                    self.own_cells.add((row, col))
                    self.own_board[row][col] = 1
                self.ship_id += 1
                self._log(f"Barco {d0} aceptado.")
            else:
                reason = REASONS.get(d2, f"código {d2}")
                self._log(f"Barco {d0} rechazado: {reason}. Corrige la ubicación y reintenta.")
            self._render_boards()
            self._update_ship_controls()
        elif msg == BATTLE_START:
            self.placement_active = False
            self.phase_var.set("Batalla")
            self._update_ship_controls()
            self._log("La FPGA indicó el inicio de la batalla.")
        elif msg == TURN:
            self.turn = d0
            who = "Jugador 2 (tú)" if d0 == 2 else "Jugador 1" if d0 == 1 else f"jugador {d0}"
            self.phase_var.set(f"Turno activo: {who}")
            self.shot_button.configure(state="normal" if d0 == 2 and self.pending_shot is None else "disabled")
            self._log(f"Turno de {who}.")
        elif msg == SHOT_RESULT:
            row, col, result = d0, d1, d2
            self.pending_shot = None
            self.turn = 0  # Espera el siguiente mensaje TURN antes de habilitar otro disparo.
            if 0 <= row < 8 and 0 <= col < 8:
                self.rival_board[row][col] = 2 if result else 3
                self.shots_fired += 1
                self.hits_made += int(bool(result))
                self._render_boards()
            self._log(f"Tu disparo a ({row}, {col}): {'impacto' if result else 'fallo'}.")
            self.shot_button.configure(state="disabled")
        elif msg == SHOT_RECEIVED:
            row, col, result = d0, d1, d2
            if 0 <= row < 8 and 0 <= col < 8:
                self.own_board[row][col] = 2 if result else 3
                self.shots_received += 1
                self.hits_received += int(bool(result))
                self._render_boards()
            self._log(f"El Jugador 1 disparó a ({row}, {col}): {'impacto' if result else 'fallo'}.")
        elif msg == GAME_OVER:
            self.turn = 0
            self.shot_button.configure(state="disabled")
            winner = "Jugador 1" if d0 == 1 else "Jugador 2" if d0 == 2 else f"jugador {d0}"
            self.phase_var.set(f"Partida terminada · Ganador: {winner}")
            self._log(f"Fin de partida. Ganador: {winner}. Disparos tuyos: {self.shots_fired}; impactos tuyos: {self.hits_made}; recibidos: {self.shots_received} ({self.hits_received} impactos).")
        elif msg == 0x03:
            self._log("UART HELLO recibido.")
        else:
            self._log(f"Mensaje UART no reconocido: tipo=0x{msg:02X}, datos={d0:02X} {d1:02X} {d2:02X} {d3:02X}.")

    def _update_ship_controls(self) -> None:
        enabled = self.placement_active and self.ship_id < 3 and self.pending_placement is None
        self.place_button.configure(state="normal" if enabled else "disabled")
        if self.ship_id < 3:
            self.ship_var.set(f"Barco {self.ship_id} de 3 · tamaño {SHIP_SIZES[self.ship_id]}")
        elif self.placement_active:
            self.ship_var.set("Flota colocada; esperando que ambos jugadores terminen")
        else:
            self.ship_var.set("Colocación inactiva")

    def _render_boards(self) -> None:
        styles = {
            0: ("·", "#dbeafe"), 1: ("B", "#9ca3af"),
            2: ("X", "#ef4444"), 3: ("O", "#facc15"),
        }
        for row in range(8):
            for col in range(8):
                text, color = styles[self.own_board[row][col]]
                self.own_cells_ui[row][col].configure(text=text, bg=color)
                text, color = styles[self.rival_board[row][col]]
                self.rival_cells_ui[row][col].configure(text=text, bg=color)

    def _log(self, text: str) -> None:
        self.log.configure(state="normal")
        self.log.insert("end", text + "\n")
        self.log.see("end")
        self.log.configure(state="disabled")

    def close(self) -> None:
        self.disconnect()
        self.root.destroy()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", help="Puerto serie, por ejemplo COM5")
    parser.add_argument("--gap-ms", type=float, default=2.0,
                        help="pausa entre bytes UART (2 ms por defecto para el sondeo del CPU)")
    args = parser.parse_args()
    root = tk.Tk()
    BattleshipPC(root, args.port, args.gap_ms)
    root.mainloop()


if __name__ == "__main__":
    main()
