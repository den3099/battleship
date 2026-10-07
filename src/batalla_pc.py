#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
batalla_pc.py - Aplicacion de PC del JUGADOR 2 (Batalla Naval, EL3313 Proyecto 3)
=================================================================================

La PC es una TERMINAL DE ENTRADA/SALIDA REMOTA SIN LOGICA DE JUEGO.  No decide
impactos, traslapes, turnos, hundimientos ni victoria: traduce lo que escribe el
usuario a tramas UART y muestra lo que la FPGA informa.  Todo el juego corre en
el RISC-V (rv32i) de la FPGA.

1. FLUJO DE SENALES (UART de 4.o nivel: Registros, Control, RX, TX, Baud Gen.)
-----------------------------------------------------------------------------
  PC -> FPGA
    ser.write() -> puente USB-UART -> rx_fisico -> [sincronizador 2FF]
      -> RX (baud_tick, rx_enable) -> rx_data[7:0]
      -> Registros (activar_rx -> estados[4:0]: RX_VALID=1)
      -> CPU lee 0x0001_0048 (rdata_pc[31:0]) -> rx_leido -> RX_VALID=0
  FPGA -> PC
    CPU escribe 0x0001_0044 (wdata_i, we_pc) -> Registros: tx_data[7:0]
      -> solicitar_tx -> Control -> activar_tx -> TX (baud_tick)
      -> tx_fisico -> puente USB-UART -> ser.read()
      tx_done -> Control -> TX libre
  Mapa de registros: Control/Estado 0x0001_0040, Datos TX 0x0001_0044,
  Datos RX 0x0001_0048.  Al programa de la PC solo le llegan TX_fisico (lo que
  la FPGA transmite) y RX_fisico (lo que la PC le envia).

  Restricciones que este programa respeta:
   * 115200 baudios, 8N1, sin control de flujo (Baud Generator fijo).
   * El RX de la FPGA guarda UN solo byte (sin FIFO): se envia un byte a la vez
     con una pausa entre bytes (--gap-ms, 2 ms por defecto) y un comando a la
     vez esperando su respuesta (stop-and-wait).
   * Un byte con stop bit invalido (rx_frame_err) se descarta en la FPGA: la
     trama llega incompleta y no hay respuesta.  La PC lo detecta por TIMEOUT
     (1.5 s) y REINTENTA (max. 3 reintentos).  Ambos son configurables.
   * La FPGA descarta cualquier byte que no sea un mensaje valido, asi que la
     PC solo transmite tramas validas (encode() las valida).

2. PROTOCOLO DE APLICACION (trama fija de 7 bytes)
-------------------------------------------------
      0xAA | TYPE | D0 | D1 | D2 | D3 | CHK        CHK = TYPE^D0^D1^D2^D3
  Todo campo distinto del delimitador es < 0x80, de modo que 0xAA solo aparece
  como delimitador; la resincronizacion consiste en descartar bytes hasta el
  siguiente 0xAA.  Campos no usados van en 0.

  PC->FPGA  0x01 PLACE  D0=id barco(0..2) D1=fila(0..7) D2=col(0..7) D3=orient(0=H,1=V)
            0x02 SHOT   D0=fila D1=col
            0x03 HELLO  (solo valido en colocacion; la FPGA responde 0x11)
  FPGA->PC  0x11 PLACEMENT_START  inicio de partida o BTN_RST (PC reinicia todo)
            0x12 PLACE_ACK        D0=id D1=0 ok / 1 traslape / 2 fuera de tablero
            0x13 BATTLE_START
            0x14 TURN             D0=1 (Jugador 1) / 2 (Jugador 2)
            0x15 SHOT_RESULT      D0=fila D1=col D2=0 fallo/1 impacto/2 hundido (propio)
            0x16 SHOT_RECEIVED    D0=fila D1=col D2=resultado (disparo de J1 sobre mi tablero)
            0x17 GAME_OVER        D0=ganador D1=disparos J1 D2=disparos J2
                                  D3=(hundidos por J1 << 2) | hundidos por J2
            0x18 SHOT_IGNORED     D0=fila D1=col (casilla repetida; no consume turno)
  Orientacion: 0=H extiende el barco hacia columnas crecientes; 1=V hacia filas
  crecientes, a partir de la casilla inicial.

3. REGLA DE IDEMPOTENCIA (REQUISITO PARA EL LADO FPGA / ENSAMBLADOR)
------------------------------------------------------------------
  Un PLACE con un id YA colocado REEMPLAZA al anterior (se borran las casillas
  previas de ese id antes de validar traslape).  Asi, si se pierde el PLACE_ACK y
  la PC reintenta, no se produce un falso "traslape" contra el propio barco.
  (Ver la lista completa de requisitos para la FPGA al final de la entrega.)

4. ESTRUCTURA DEL ARCHIVO
-------------------------
  Capa de protocolo : encode(), FrameParser
  Capa serial       : SerialLink (pyserial), SimLink (doble de prueba)
  Modelo + FSM      : Model, App  (UN solo consumidor de eventos; es el unico que
                      cambia el estado y el unico que escribe en el puerto)
  Hilos productores : Reader (puerto -> cola), InputThread (teclado -> cola);
                      solo ENCOLAN eventos.
  Vista             : ConsoleView (consola) y TkView (Tkinter, dos grillas 8x8);
                      unico lugar de impresion/dibujo.

Dependencias: solo pyserial (y tkinter para la GUI).  Python 3.9+.

Uso:
  python batalla_pc.py --list-ports
  python batalla_pc.py --port COM3 --log evidencia.log          (Windows)
  python batalla_pc.py --port /dev/ttyUSB0 --log evidencia.log  (Linux)
  python batalla_pc.py --sim                (MODO SIMULADO, ver SimLink)

Comandos durante la partida: r (redibujar), hello (reenviar HELLO), salir.
"""

import argparse
import collections
import datetime
import os
import queue
import random
import re
import sys
import threading
import time

try:                                    # pyserial es opcional hasta que se use
    import serial
    import serial.tools.list_ports
except ImportError:                     # pragma: no cover
    serial = None

# ---------------------------------------------------------------------------
# CAPA DE PROTOCOLO
# ---------------------------------------------------------------------------
SOF = 0xAA
FRAME_LEN = 7
MAX_FIELD = 0x7F

T_PLACE, T_SHOT, T_HELLO = 0x01, 0x02, 0x03
T_PLACEMENT_START, T_PLACE_ACK, T_BATTLE_START, T_TURN = 0x11, 0x12, 0x13, 0x14
T_SHOT_RESULT, T_SHOT_RECEIVED, T_GAME_OVER, T_SHOT_IGNORED = 0x15, 0x16, 0x17, 0x18

TYPE_NAMES = {
    T_PLACE: "PLACE", T_SHOT: "SHOT", T_HELLO: "HELLO",
    T_PLACEMENT_START: "PLACEMENT_START", T_PLACE_ACK: "PLACE_ACK",
    T_BATTLE_START: "BATTLE_START", T_TURN: "TURN", T_SHOT_RESULT: "SHOT_RESULT",
    T_SHOT_RECEIVED: "SHOT_RECEIVED", T_GAME_OVER: "GAME_OVER",
    T_SHOT_IGNORED: "SHOT_IGNORED",
}

BOARD = 8
ROWS = "ABCDEFGH"
SHIP_SIZES = (4, 3, 2)                  # ids 0, 1, 2
RES_TXT = {0: "agua", 1: "impacto", 2: "impacto y hundido"}
ACK_TXT = {1: "traslape con otro barco", 2: "fuera del tablero"}

Frame = collections.namedtuple("Frame", "type d raw")   # d = (D0, D1, D2, D3)


def checksum(type_, d0, d1, d2, d3):
    return type_ ^ d0 ^ d1 ^ d2 ^ d3


def encode(type_, d0=0, d1=0, d2=0, d3=0):
    """Arma una trama de 7 bytes.  Valida que TYPE y D0..D3 esten en 0..0x7F
    (asi 0xAA solo aparece como delimitador).  Lanza ValueError si no."""
    fields = (type_, d0, d1, d2, d3)
    for v in fields:
        if not isinstance(v, int) or isinstance(v, bool) or v < 0 or v > MAX_FIELD:
            raise ValueError("campo fuera de 0..0x7F: %r" % (v,))
    return bytes([SOF, type_, d0, d1, d2, d3, checksum(*fields)])


def encode_place(ship_id, row, col, orient):
    if not (0 <= ship_id < len(SHIP_SIZES)):
        raise ValueError("id de barco fuera de 0..2")
    if not (0 <= row < BOARD and 0 <= col < BOARD):
        raise ValueError("casilla fuera de tablero")
    if orient not in (0, 1):
        raise ValueError("orientacion debe ser 0 (H) o 1 (V)")
    return encode(T_PLACE, ship_id, row, col, orient)


def encode_shot(row, col):
    if not (0 <= row < BOARD and 0 <= col < BOARD):
        raise ValueError("casilla fuera de tablero")
    return encode(T_SHOT, row, col)


def encode_hello():
    return encode(T_HELLO)


def cell_name(row, col):
    return "%s%d" % (ROWS[row], col + 1)


def describe(frame):
    """Texto legible de una trama (para el log)."""
    n = TYPE_NAMES.get(frame.type, "TYPE_0x%02X" % frame.type)
    return "%s d=%s" % (n, list(frame.d))


def hexdump(data):
    return " ".join("%02X" % b for b in data)


class FrameParser:
    """Ensambla tramas a partir de bytes sueltos.

    * Fuera de trama descarta todo byte distinto de 0xAA (basura).
    * Dentro de una trama, un 0xAA o un byte >= 0x80 significa que la trama
      anterior quedo truncada/corrupta: se descarta y se resincroniza.
    * Descarta tramas con checksum malo.
    Eventos devueltos por feed(): ('frame', Frame), ('bad_chk', bytes),
    ('resync', bytes_descartados), ('garbage', bytes).
    Contadores: ok, bad_chk, resyncs, garbage_bytes.
    """

    def __init__(self):
        self.buf = bytearray()
        self.ok = 0
        self.bad_chk = 0
        self.resyncs = 0
        self.garbage_bytes = 0

    def feed(self, data):
        events = []
        garbage = bytearray()

        def flush_garbage():
            if garbage:
                events.append(("garbage", bytes(garbage)))
                garbage.clear()

        for b in bytes(data):
            if not self.buf:
                if b == SOF:
                    flush_garbage()
                    self.buf.append(b)
                else:
                    garbage.append(b)
                    self.garbage_bytes += 1
                continue
            if b == SOF:                           # SOF dentro de trama: resync
                flush_garbage()
                events.append(("resync", bytes(self.buf)))
                self.resyncs += 1
                self.buf = bytearray([SOF])
                continue
            if b > MAX_FIELD:                      # byte invalido dentro de trama
                events.append(("resync", bytes(self.buf) + bytes([b])))
                self.resyncs += 1
                self.buf = bytearray()
                continue
            self.buf.append(b)
            if len(self.buf) == FRAME_LEN:
                raw = bytes(self.buf)
                self.buf = bytearray()
                if checksum(*raw[1:6]) == raw[6]:
                    self.ok += 1
                    events.append(("frame", Frame(raw[1], tuple(raw[2:6]), raw)))
                else:
                    self.bad_chk += 1
                    events.append(("bad_chk", raw))
        flush_garbage()
        return events


# ---------------------------------------------------------------------------
# LOG (evidencia de comunicacion bidireccional)
# ---------------------------------------------------------------------------
class Logger:
    """Registra cada TX/RX con marca de tiempo y volcado hexadecimal."""

    def __init__(self, path=None):
        self.lock = threading.Lock()
        self.f = open(path, "a", encoding="utf-8") if path else None

    def _w(self, tag, text):
        if not self.f:
            return
        ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]
        with self.lock:
            self.f.write("%s %-4s %s\n" % (ts, tag, text))
            self.f.flush()

    def tx(self, data, note=""):
        self._w("TX", "%-23s ; %s" % (hexdump(data), note))

    def rx(self, tag, data, note=""):
        self._w(tag, "%-23s ; %s" % (hexdump(data), note))

    def event(self, text):
        self._w("EVT", text)

    def close(self):
        with self.lock:
            if self.f:
                self.f.close()
                self.f = None


# ---------------------------------------------------------------------------
# CAPA SERIAL
# ---------------------------------------------------------------------------
class SerialLink:
    """Puerto serie real: 115200 8N1, sin control de flujo."""
    BAUD = 115200

    def __init__(self, port):
        if serial is None:
            raise RuntimeError("Falta pyserial: instale con  pip install pyserial")
        self.port = port
        self.ser = serial.Serial(
            port=port, baudrate=self.BAUD, bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE, stopbits=serial.STOPBITS_ONE,
            xonxoff=False, rtscts=False, dsrdtr=False,
            timeout=0.05, write_timeout=1.0)
        self.label = "%s %d 8N1" % (port, self.BAUD)

    def send(self, data, gap_s):
        """Un byte a la vez con pausa (el RX de la FPGA no tiene FIFO)."""
        for b in data:
            self.ser.write(bytes([b]))
            self.ser.flush()
            if gap_s > 0:
                time.sleep(gap_s)

    def read(self, timeout):
        self.ser.timeout = timeout
        first = self.ser.read(1)
        if not first:
            return b""
        n = self.ser.in_waiting
        return first + (self.ser.read(n) if n else b"")

    def close(self):
        try:
            self.ser.close()
        except Exception:
            pass


def serial_errors():
    errs = [OSError]
    if serial is not None:
        errs.append(serial.SerialException)
    return tuple(errs)


class SimLink:
    """*** DOBLE DE PRUEBA DE LA FPGA - NO FORMA PARTE DE LA ENTREGA FINAL ***

    Imita al RISC-V del lado de la FPGA para probar interfaz y flujo sin
    tarjeta (--sim).  Si aqui hay logica de juego es porque simula a la FPGA;
    la app real de PC (App) no tiene ninguna.  El Jugador 1 es un bot que
    coloca y dispara al azar.  Inyeccion de fallas para las pruebas:
      mute              : no responde nada (FPGA muda)
      lose_responses=n  : pierde las proximas n respuestas (ACK perdido)
      corrupt_cmds=n    : se come 1 byte de los proximos n comandos (rx_frame_err)
      noise             : antepone bytes basura a cada respuesta
      inject_reset()    : simula BTN_RST (PLACEMENT_START)
    """
    label = "SIMULADO"

    def __init__(self, seed=None, first_turn=1, noise=False):
        self.rng = random.Random(seed)
        self.parser = FrameParser()
        self.out = queue.Queue()
        self.mute = False
        self.lose_responses = 0
        self.corrupt_cmds = 0
        self.noise = noise
        self.first_turn = first_turn
        self.closed = False
        self.rx_log = []                 # comandos validos que "llegaron" a la FPGA
        self._reset_game()

    # -- E/S como un Link -------------------------------------------------
    def send(self, data, gap_s):
        data = bytes(data)
        if self.corrupt_cmds > 0 and len(data) == FRAME_LEN:
            self.corrupt_cmds -= 1
            data = data[:3] + data[4:]   # un byte menos: trama truncada
        for ev, payload in self.parser.feed(data):
            if ev == "frame":
                self.rx_log.append(payload)
                self._on_command(payload)

    def read(self, timeout):
        try:
            first = self.out.get(timeout=timeout)
        except queue.Empty:
            return b""
        data = bytearray([first])
        try:
            while True:
                data.append(self.out.get_nowait())
        except queue.Empty:
            pass
        return bytes(data)

    def close(self):
        self.closed = True

    # -- utilidades de prueba -----------------------------------------------
    def inject_reset(self):
        self._reset_game()
        self._emit(encode(T_PLACEMENT_START))

    def inject_garbage(self, data):
        for b in data:
            self.out.put(b)

    # -- logica simulada de la FPGA ------------------------------------------
    def _reset_game(self):
        self.phase = "placement"
        self.p2 = {}                     # id -> set de casillas
        self.p1 = self._random_fleet()   # lista de sets
        self.p1_hits = set()
        self.p2_hits = set()
        self.p2_shots_taken = set()      # casillas que ya disparo el Jugador 2
        self.p1_shots_taken = set()
        self.shots = {1: 0, 2: 0}
        self.turn = 0

    def _random_fleet(self):
        while True:
            used, fleet, ok = set(), [], True
            for size in SHIP_SIZES:
                cells = self._cells(size, self.rng.randrange(BOARD),
                                    self.rng.randrange(BOARD), self.rng.randrange(2))
                if cells is None or used & set(cells):
                    ok = False
                    break
                used |= set(cells)
                fleet.append(set(cells))
            if ok:
                return fleet

    @staticmethod
    def _cells(size, row, col, orient):
        cells = [(row + (i if orient else 0), col + (0 if orient else i))
                 for i in range(size)]
        if any(r >= BOARD or c >= BOARD for r, c in cells):
            return None
        return cells

    def _emit(self, frame_bytes):
        if self.mute:
            return
        if self.lose_responses > 0:
            self.lose_responses -= 1
            return
        if self.noise:
            for _ in range(self.rng.randint(1, 3)):
                b = self.rng.randrange(256)
                self.out.put(b if b != SOF else 0x55)
        for b in frame_bytes:
            self.out.put(b)

    def _on_command(self, f):
        if f.type == T_HELLO:
            if self.phase == "placement":
                self._emit(encode(T_PLACEMENT_START))
        elif f.type == T_PLACE and self.phase == "placement":
            self._on_place(*f.d)
        elif f.type == T_SHOT and self.phase == "battle" and self.turn == 2:
            self._on_shot(f.d[0], f.d[1])
        # cualquier otra cosa: descartada sin afectar la partida

    def _on_place(self, sid, row, col, orient):
        if sid >= len(SHIP_SIZES) or orient > 1:
            return                                   # trama invalida: se descarta
        cells = self._cells(SHIP_SIZES[sid], row, col, orient)
        if cells is None:
            return self._emit(encode(T_PLACE_ACK, sid, 2))
        others = set()
        for k, v in self.p2.items():
            if k != sid:                             # idempotencia: reemplaza al propio
                others |= v
        if others & set(cells):
            return self._emit(encode(T_PLACE_ACK, sid, 1))
        self.p2[sid] = set(cells)
        self._emit(encode(T_PLACE_ACK, sid, 0))
        if len(self.p2) == len(SHIP_SIZES):
            self.phase = "battle"
            self._emit(encode(T_BATTLE_START))
            self._next_turn(self.first_turn)

    def _sunk(self, fleet, hits):
        return sum(1 for s in fleet if s <= hits)

    def _next_turn(self, who):
        self.turn = who
        self._emit(encode(T_TURN, who))
        if who == 1:
            self._p1_fire()

    def _p1_fire(self):
        free = [(r, c) for r in range(BOARD) for c in range(BOARD)
                if (r, c) not in self.p1_shots_taken]
        r, c = self.rng.choice(free)
        self.p1_shots_taken.add((r, c))
        self.shots[1] += 1
        mine = set().union(*self.p2.values())
        res = 0
        if (r, c) in mine:
            self.p2_hits.add((r, c))
            res = 2 if any((r, c) in s and s <= self.p2_hits
                           for s in self.p2.values()) else 1
        self._emit(encode(T_SHOT_RECEIVED, r, c, res))
        if self._sunk(list(self.p2.values()), self.p2_hits) == len(SHIP_SIZES):
            return self._game_over(1)
        self._next_turn(2)

    def _on_shot(self, row, col):
        if row >= BOARD or col >= BOARD:
            return
        if (row, col) in self.p2_shots_taken:
            return self._emit(encode(T_SHOT_IGNORED, row, col))
        self.p2_shots_taken.add((row, col))
        self.shots[2] += 1
        res = 0
        for s in self.p1:
            if (row, col) in s:
                self.p1_hits.add((row, col))
                res = 2 if s <= self.p1_hits else 1
        self._emit(encode(T_SHOT_RESULT, row, col, res))
        if self._sunk(self.p1, self.p1_hits) == len(SHIP_SIZES):
            return self._game_over(2)
        self._next_turn(1)

    def _game_over(self, winner):
        self.phase = "over"
        by_j1 = self._sunk(list(self.p2.values()), self.p2_hits)
        by_j2 = self._sunk(self.p1, self.p1_hits)
        self._emit(encode(T_GAME_OVER, winner, self.shots[1], self.shots[2],
                          (by_j1 << 2) | by_j2))


# ---------------------------------------------------------------------------
# HILOS PRODUCTORES (solo encolan eventos)
# ---------------------------------------------------------------------------
class Reader(threading.Thread):
    """Lee el puerto, ensambla tramas y las encola.  Nunca escribe."""

    def __init__(self, link, parser, q, log):
        super().__init__(daemon=True, name="reader")
        self.link, self.parser, self.q, self.log = link, parser, q, log
        self.stop = threading.Event()

    def run(self):
        while not self.stop.is_set():
            try:
                data = self.link.read(0.05)
            except serial_errors() as e:
                self.q.put(("error", "Se perdio la conexion con el puerto (%s)." % e))
                return
            except Exception as e:           # puerto cerrado/desconectado
                if not self.stop.is_set():
                    self.q.put(("error", "Error de lectura del puerto (%s)." % e))
                return
            if not data:
                continue
            for kind, payload in self.parser.feed(data):
                if kind == "frame":
                    self.log.rx("RX", payload.raw, describe(payload))
                    self.q.put(("rx", payload))
                elif kind == "bad_chk":
                    self.log.rx("RX!", payload, "checksum malo, descartada")
                elif kind == "resync":
                    self.log.rx("RX~", payload, "trama truncada, resincroniza")
                else:
                    self.log.rx("RX?", payload, "bytes basura descartados")


class InputThread(threading.Thread):
    """Lee lineas del teclado y las encola.  Nunca imprime."""

    def __init__(self, q):
        super().__init__(daemon=True, name="input")
        self.q = q

    def run(self):
        while True:
            line = sys.stdin.readline()
            if line == "":
                self.q.put(("eof",))
                return
            self.q.put(("line", line))


# ---------------------------------------------------------------------------
# ENTRADA DEL USUARIO: parseo y validacion (antes de transmitir)
# ---------------------------------------------------------------------------
RE_SHOT = re.compile(r"^\s*([A-Za-z])\s*(\d+)\s*$")
RE_PLACE = re.compile(r"^\s*([A-Za-z])\s*(\d+)\s*[,;\s]?\s*([A-Za-z])\s*$")
MSG_RANGE = "Coordenada fuera de rango (filas A-H, columnas 1-8)."


def _coord(letter, digits):
    """-> (fila, col) o None si esta fuera de rango."""
    row = ord(letter.upper()) - ord("A")
    col = int(digits) - 1
    if 0 <= row < BOARD and 0 <= col < BOARD:
        return row, col
    return None


def parse_shot(text):
    """-> ('ok',(fila,col)) | ('fmt',msg) | ('range',msg)"""
    m = RE_SHOT.match(text)
    if not m:
        return "fmt", "Formato invalido. Escriba fila y columna, por ejemplo C5."
    rc = _coord(m.group(1), m.group(2))
    return ("ok", rc) if rc else ("range", MSG_RANGE)


def parse_place(text):
    """-> ('ok',(fila,col,orient)) | ('fmt',msg) | ('range',msg)"""
    m = RE_PLACE.match(text)
    if not m:
        return "fmt", "Formato invalido. Escriba casilla y orientacion, por ejemplo A1 H."
    o = m.group(3).upper()
    if o not in ("H", "V"):
        return "fmt", "Formato invalido: la orientacion debe ser H o V (ej. A1 H)."
    rc = _coord(m.group(1), m.group(2))
    if not rc:
        return "range", MSG_RANGE
    return "ok", (rc[0], rc[1], 0 if o == "H" else 1)


# ---------------------------------------------------------------------------
# MODELO (solo datos que informa la FPGA) Y MAQUINA DE ESTADOS
# ---------------------------------------------------------------------------
CONECTANDO, COLOCACION, ESPERA_BATALLA = "CONECTANDO", "COLOCACION", "ESPERA_BATALLA"
TURNO_PROPIO, TURNO_RIVAL, FIN = "TURNO_PROPIO", "TURNO_RIVAL", "FIN"

PHASE_TXT = {CONECTANDO: "conectando", COLOCACION: "colocacion",
             ESPERA_BATALLA: "espera de batalla", TURNO_PROPIO: "batalla",
             TURNO_RIVAL: "batalla", FIN: "fin"}
TURN_TXT = {TURNO_PROPIO: "TU TURNO", TURNO_RIVAL: "TURNO DEL JUGADOR 1 (FPGA)"}


class Model:
    """Tablero propio (barcos confirmados + disparos recibidos) y tablero
    rival (solo resultados de MIS disparos).  Nunca la flota del Jugador 1."""

    def __init__(self):
        self.own_ships = {}          # id -> [(r,c)]  solo tras PLACE_ACK 0
        self.own_shots = {}          # (r,c) -> resultado (disparos de J1)
        self.rival_shots = {}        # (r,c) -> resultado (mis disparos)
        self.rival_sunk = 0
        self.own_sunk = 0
        self.summary = None          # dict tras GAME_OVER

    def next_ship(self):
        for i in range(len(SHIP_SIZES)):
            if i not in self.own_ships:
                return i
        return None

    def own_symbol(self, r, c):
        res = self.own_shots.get((r, c))
        if res is not None:
            return "o" if res == 0 else "X"
        for cells in self.own_ships.values():
            if (r, c) in cells:
                return "B"
        return "~"

    def rival_symbol(self, r, c):
        res = self.rival_shots.get((r, c))
        if res is None:
            return "~"
        return "o" if res == 0 else "X"


class Pending:
    """Comando enviado que espera respuesta (stop-and-wait)."""

    def __init__(self, kind, data, key, params=None):
        self.kind, self.data, self.key, self.params = kind, data, key, params
        self.attempts = 0
        self.deadline = 0.0


DIAG = ("La FPGA no responde tras %d reintentos. Revise: (1) el puerto elegido, "
        "(2) TX/RX cruzados en el XDC, (3) 115200 baudios 8N1, "
        "(4) que el programa del RISC-V este corriendo.")


class App:
    """Maquina de estados del cliente.  UNICO consumidor de la cola de eventos,
    unico que cambia el estado y unico que escribe en el puerto.

    Eventos: ('rx',Frame) ('line',str) ('error',str) ('quit',) ('eof',)
    Las transiciones de estado las causan SOLO mensajes de la FPGA.
    """

    def __init__(self, link, view, log=None, timeout=1.5, retries=3, gap_s=0.002,
                 sim=False):
        self.link, self.view = link, view
        self.log = log or Logger(None)
        self.timeout, self.retries, self.gap_s = timeout, retries, gap_s
        self.sim = sim
        self.q = queue.Queue()
        self.parser = FrameParser()
        self.reader = Reader(link, self.parser, self.q, self.log)
        self.state = CONECTANDO
        self.conn = "CONECTANDO"
        self.model = Model()
        self.pending = None
        self.msgs = collections.deque(maxlen=8)
        self.dup_ignored = 0
        self.unknown = 0
        self.frames_seen = 0
        self.done = False
        self.exit_code = 0
        self.dirty = True

    # -- ciclo de vida ------------------------------------------------------
    def start(self):
        self.reader.start()
        self.say("Conectando con la FPGA (%s)..." % self.link.label)
        self.send_hello()

    def stop(self):
        self.reader.stop.set()
        self.reader.join(timeout=1.0)
        self.link.close()
        self.log.event("cierre ordenado: ok=%d bad_chk=%d resyncs=%d garbage=%d"
                       % (self.parser.ok, self.parser.bad_chk,
                          self.parser.resyncs, self.parser.garbage_bytes))
        self.log.close()

    def run(self):
        """Bucle principal para la consola."""
        try:
            self.start()
            while self.step(0.05):
                pass
        except KeyboardInterrupt:
            self.say("Interrumpido por el usuario (Ctrl+C). Cerrando...")
            self.view.render(self)
        finally:
            self.stop()
        return self.exit_code

    def step(self, wait=0.05):
        """Procesa eventos pendientes (espera hasta `wait` s el primero).
        Devuelve False cuando la app debe terminar."""
        if self.done:
            return False
        t = wait
        if self.pending:
            t = max(0.0, min(wait, self.pending.deadline - time.monotonic()))
        try:
            ev = self.q.get(timeout=t) if t > 0 else self.q.get_nowait()
        except queue.Empty:
            ev = None
        n = 0
        while ev is not None and n < 100:
            self.dispatch(ev)
            n += 1
            try:
                ev = self.q.get_nowait()
            except queue.Empty:
                ev = None
        self.check_pending()
        if self.dirty:
            self.view.render(self)
            self.dirty = False
        return not self.done

    def dispatch(self, ev):
        kind = ev[0]
        if kind == "rx":
            self.on_frame(ev[1])
        elif kind == "line":
            self.on_line(ev[1])
        elif kind == "error":
            self.conn = "DESCONECTADO"
            self.say("ERROR: " + ev[1] + " Cerrando la aplicacion.")
            self.exit_code = 1
            self.done = True
        elif kind in ("quit", "eof"):
            self.done = True
        self.dirty = True

    # -- mensajes -----------------------------------------------------------
    def say(self, text):
        self.msgs.append(text)
        self.dirty = True

    # -- transmision (stop-and-wait con reintentos) --------------------------
    def _write(self, p):
        p.attempts += 1
        try:
            self.link.send(p.data, self.gap_s)
        except serial_errors() as e:
            self.pending = None
            self.dispatch(("error", "No se pudo escribir en el puerto (%s)." % e))
            return False
        note = "%s intento %d" % (TYPE_NAMES[p.data[1]], p.attempts)
        self.log.tx(p.data, note)
        p.deadline = time.monotonic() + self.timeout
        return True

    def transmit(self, kind, data, key, params=None):
        p = Pending(kind, data, key, params)
        self.pending = p
        self._write(p)
        self.dirty = True

    def send_hello(self):
        self.transmit("HELLO", encode_hello(), None)

    def check_pending(self):
        p = self.pending
        if not p or self.done or time.monotonic() < p.deadline:
            return
        if p.attempts <= self.retries:                      # reintento
            self.say("Sin respuesta; reintento %d de %d..." % (p.attempts, self.retries))
            self._write(p)
            self.dirty = True
            return
        self.pending = None                                  # se agotaron
        self.dirty = True
        if self.frames_seen == 0:
            self.conn = "SIN RESPUESTA"
            self.say(DIAG % self.retries)
        elif p.kind == "HELLO":
            self.say("HELLO sin respuesta: es normal si la partida ya esta en "
                     "batalla (la FPGA solo responde en colocacion).")
        else:
            self.conn = "SIN RESPUESTA"
            self.say(DIAG % self.retries)
            self.say("Puede volver a intentar la entrada o escribir 'hello'.")

    # -- mensajes de la FPGA --------------------------------------------------
    def reset_game(self, why):
        self.model = Model()
        self.pending = None
        self.msgs.clear()
        self.state = COLOCACION
        self.say(why)

    def on_frame(self, f):
        self.frames_seen += 1
        self.conn = "OK"
        t, d = f.type, f.d
        if t == T_PLACEMENT_START:
            self.reset_game("Inicio de colocacion (partida nueva o BTN_RST). "
                            "Tableros reiniciados.")
        elif t == T_PLACE_ACK:
            self.on_place_ack(d[0], d[1])
        elif t == T_BATTLE_START:
            if self.state != FIN:
                if self.pending and self.pending.kind != "SHOT":
                    self.pending = None
                self.state = ESPERA_BATALLA
                self.say("Comienza la batalla.")
        elif t == T_TURN:
            self.on_turn(d[0])
        elif t == T_SHOT_RESULT:
            self.on_shot_result(d[0], d[1], d[2])
        elif t == T_SHOT_RECEIVED:
            self.on_shot_received(d[0], d[1], d[2])
        elif t == T_GAME_OVER:
            self.on_game_over(d)
        elif t == T_SHOT_IGNORED:
            self.on_shot_ignored(d[0], d[1])
        else:
            self.unknown += 1

    def on_place_ack(self, sid, code):
        p = self.pending
        if not (p and p.kind == "PLACE" and p.key == sid):
            self.dup_ignored += 1                      # ACK duplicado/tardio
            return
        self.pending = None
        if code == 0:
            row, col, orient = p.params
            size = SHIP_SIZES[sid]
            cells = [(row + (i if orient else 0), col + (0 if orient else i))
                     for i in range(size)]
            self.model.own_ships[sid] = cells           # reemplaza si ya existia
            self.say("Barco %d (tamano %d) colocado en %s, %s."
                     % (sid + 1, size, cell_name(row, col), "V" if orient else "H"))
            if self.model.next_ship() is None:
                self.state = ESPERA_BATALLA
                self.say("Flota completa. Esperando al Jugador 1...")
            else:
                self.state = COLOCACION
        else:
            self.say("Colocacion rechazada: %s. Intente de nuevo con el barco %d."
                     % (ACK_TXT.get(code, "codigo %d" % code), sid + 1))

    def on_turn(self, who):
        if self.state == FIN or who not in (1, 2):
            return
        if self.pending and self.pending.kind == "HELLO":
            self.pending = None
        self.state = TURNO_PROPIO if who == 2 else TURNO_RIVAL
        self.say("Es tu turno: elige una casilla del tablero rival." if who == 2
                 else "Turno del Jugador 1 (FPGA).")

    def _valid_cell(self, r, c):
        if r < BOARD and c < BOARD:
            return True
        self.unknown += 1
        return False

    def on_shot_result(self, r, c, res):
        if not self._valid_cell(r, c) or res > 2:
            return
        p = self.pending
        if p and p.kind == "SHOT" and p.key == (r, c):
            self.pending = None
        prev = self.model.rival_shots.get((r, c))
        self.model.rival_shots[(r, c)] = res
        if res == 2 and prev != 2:
            self.model.rival_sunk += 1
        self.say("Tu disparo a %s: %s." % (cell_name(r, c), RES_TXT[res]))
        if self.state == TURNO_PROPIO:        # el disparo consumio el turno;
            self.state = TURNO_RIVAL          # un TURN posterior lo confirma/corrige

    def on_shot_ignored(self, r, c):
        p = self.pending
        retried = bool(p and p.kind == "SHOT" and p.key == (r, c) and p.attempts > 1)
        if p and p.kind == "SHOT" and p.key == (r, c):
            self.pending = None
        extra = " (puede ser un reintento cuya respuesta se perdio)" if retried else ""
        self.say("Casilla %s ya disparada: se ignora y no consume turno.%s"
                 % (cell_name(r, c), extra))

    def on_shot_received(self, r, c, res):
        if not self._valid_cell(r, c) or res > 2:
            return
        prev = self.model.own_shots.get((r, c))
        self.model.own_shots[(r, c)] = res
        if res == 2 and prev != 2:
            self.model.own_sunk += 1
        self.say("El Jugador 1 disparo a %s: %s." % (cell_name(r, c), RES_TXT[res]))

    def on_game_over(self, d):
        self.pending = None
        self.state = FIN
        self.model.summary = {
            "winner": d[0], "shots1": d[1], "shots2": d[2],
            "sunk_by_1": (d[3] >> 2) & 0x3, "sunk_by_2": d[3] & 0x3}
        self.say("FIN DE LA PARTIDA.")

    # -- entradas del usuario -------------------------------------------------
    def expecting_input(self):
        """'place' | 'shot' | None  (para la vista y las pruebas)."""
        if self.pending or self.done:
            return None
        if self.state == COLOCACION and self.model.next_ship() is not None:
            return "place"
        if self.state == TURNO_PROPIO:
            return "shot"
        return None

    def on_line(self, text):
        s = text.strip()
        low = s.lower()
        if not s:
            return
        if low in ("salir", "exit", "quit"):
            self.say("Saliendo...")
            self.done = True
            return
        if low == "r":
            return                                        # solo redibuja
        if low == "hello":
            if self.pending:
                self.say("Espere: hay un comando en curso.")
            else:
                self.say("Reenviando HELLO...")
                self.send_hello()
            return
        if self.pending:
            self.say("Espere la respuesta de la FPGA antes de ingresar otro dato.")
            return
        kind = self.expecting_input()
        if kind == "place":
            self.user_place(s)
        elif kind == "shot":
            self.user_shot(s)
        elif self.state == FIN:
            self.say("La partida termino. Pulse BTN_RST en la FPGA para reiniciar.")
        elif self.state == TURNO_RIVAL:
            self.say("No es tu turno.")
        elif self.state == ESPERA_BATALLA:
            self.say("Flota completa: espere a que inicie la batalla.")
        else:
            self.say("Aun no hay conexion con la FPGA (use 'hello' para reintentar).")

    def user_place(self, s):
        kind, val = parse_place(s)
        if kind != "ok":
            self.say(val)
            return
        row, col, orient = val
        sid = self.model.next_ship()
        self.transmit("PLACE", encode_place(sid, row, col, orient), sid, val)

    def user_shot(self, s):
        kind, val = parse_shot(s)
        if kind != "ok":
            self.say(val)
            return
        self.transmit("SHOT", encode_shot(*val), val)

    # -- texto de prompt para las vistas ---------------------------------------
    def prompt(self):
        if self.done:
            return ""
        if self.pending:
            return "Esperando respuesta de la FPGA..."
        k = self.expecting_input()
        if k == "place":
            i = self.model.next_ship()
            return ("Barco %d/%d (tamano %d). Casilla inicial y orientacion (ej. A1 H): "
                    % (i + 1, len(SHIP_SIZES), SHIP_SIZES[i]))
        if k == "shot":
            return "Tu disparo (ej. C5): "
        return ""


# ---------------------------------------------------------------------------
# VISTA: CONSOLA (unico lugar de impresion)
# ---------------------------------------------------------------------------
class ConsoleView:
    COLORS = {"X": "\033[31m", "o": "\033[36m", "B": "\033[32m", "~": "\033[34m"}

    def __init__(self, out=None, clear=True, color=None):
        self.out = out or sys.stdout
        self.clear = clear
        self.color = self.out.isatty() if color is None else color
        self.lock = threading.Lock()

    def _sym(self, s):
        return self.COLORS[s] + s + "\033[0m" if self.color else s

    def board_rows(self, symbol_fn):
        rows = ["    " + " ".join(str(c + 1) for c in range(BOARD))]
        for r in range(BOARD):
            rows.append(" %s  " % ROWS[r]
                        + " ".join(self._sym(symbol_fn(r, c)) for c in range(BOARD)))
        return rows

    def header(self, app):
        turn = TURN_TXT.get(app.state, "-")
        return "FASE: %s | TURNO: %s | CONEXION: %s" % (
            PHASE_TXT[app.state], turn, app.conn)

    def frame_text(self, app):
        m = app.model
        L = ["=" * 56, " BATALLA NAVAL - JUGADOR 2", "=" * 56, self.header(app)]
        if app.state == TURNO_PROPIO:
            L.append(">>>>>>>>>>  TU TURNO  <<<<<<<<<<")
        elif app.state == TURNO_RIVAL:
            L.append("..........  TURNO DEL JUGADOR 1 (FPGA)  ..........")
        if app.sim:
            L.append("[MODO SIMULADO: doble de prueba de la FPGA, no es la entrega final]")
        L.append("")
        own = self.board_rows(m.own_symbol)
        riv = self.board_rows(m.rival_symbol)
        L.append("   TU TABLERO                  TABLERO RIVAL")
        for a, b in zip(own, riv):
            plain = re.sub(r"\033\[[0-9;]*m", "", a)
            L.append(a + " " * (28 - len(plain)) + b)
        L.append("")
        L.append("~ agua   B barco propio   X impacto   o fallo")
        L.append("Hundidos: rivales %d/%d | tuyos %d/%d" % (
            m.rival_sunk, len(SHIP_SIZES), m.own_sunk, len(SHIP_SIZES)))
        L.append("")
        for t in app.msgs:
            L.append(" * " + t)
        if m.summary:
            s = m.summary
            L += ["", "-" * 56,
                  " GANADOR: %s" % ("JUGADOR 2 (TU)" if s["winner"] == 2
                                     else "JUGADOR 1 (FPGA)"),
                  " Disparos totales: Jugador 1 = %d, Jugador 2 = %d"
                  % (s["shots1"], s["shots2"]),
                  " Barcos hundidos: por Jugador 1 = %d, por Jugador 2 = %d"
                  % (s["sunk_by_1"], s["sunk_by_2"]),
                  " Pulse BTN_RST en la FPGA para reiniciar la partida.",
                  "-" * 56]
        L.append("")
        L.append("Comandos: r (redibujar) | hello (reenviar HELLO) | salir")
        return "\n".join(L)

    def render(self, app):
        text = self.frame_text(app)
        prompt = app.prompt()
        with self.lock:                               # unico punto de impresion
            if self.clear:
                self.out.write("\033[2J\033[H")
            self.out.write(text + "\n" + prompt)
            if not prompt:
                self.out.write("\n")
            self.out.flush()


# ---------------------------------------------------------------------------
# VISTA: Tkinter (dos grillas de 8x8, barra de turno que cambia de color)
# ---------------------------------------------------------------------------
class TkView:
    BAR = {TURNO_PROPIO: "#2e7d32", TURNO_RIVAL: "#ef6c00", FIN: "#1565c0"}
    CELL = {"~": ("#0d47a1", "#bbdefb"), "B": ("#2e7d32", "#ffffff"),
            "X": ("#c62828", "#ffffff"), "o": ("#455a64", "#ffffff")}

    def __init__(self):
        import tkinter as tk                 # import tardio: tkinter es opcional
        self.tk = tk
        self.root = tk.Tk()
        self.root.title("Batalla Naval - Jugador 2")
        self.app = None
        self.bar = tk.Label(self.root, text="", font=("Helvetica", 16, "bold"),
                            fg="white", bg="#546e7a", pady=8)
        self.bar.pack(fill="x")
        self.info = tk.Label(self.root, text="", anchor="w")
        self.info.pack(fill="x", padx=8)
        boards = tk.Frame(self.root)
        boards.pack(padx=8, pady=6)
        self.own = self._grid(boards, 0, "TU TABLERO", False)
        self.riv = self._grid(boards, 1, "TABLERO RIVAL (clic para disparar)", True)
        self.legend = tk.Label(self.root, text="~ agua   B barco propio   "
                               "X impacto   o fallo")
        self.legend.pack()
        self.listbox = tk.Listbox(self.root, height=8, width=70)
        self.listbox.pack(padx=8, pady=4, fill="x")
        self.prompt = tk.Label(self.root, text="", anchor="w")
        self.prompt.pack(fill="x", padx=8)
        self.entry = tk.Entry(self.root)
        self.entry.pack(fill="x", padx=8, pady=(0, 8))
        self.entry.bind("<Return>", self._enter)
        self.root.protocol("WM_DELETE_WINDOW", self._close)

    def _grid(self, parent, col, title, clickable):
        tk = self.tk
        fr = tk.Frame(parent, padx=10)
        fr.grid(row=0, column=col)
        tk.Label(fr, text=title, font=("Helvetica", 11, "bold")).grid(
            row=0, column=0, columnspan=BOARD + 1)
        for c in range(BOARD):
            tk.Label(fr, text=str(c + 1)).grid(row=1, column=c + 1)
        cells = {}
        for r in range(BOARD):
            tk.Label(fr, text=ROWS[r]).grid(row=r + 2, column=0)
            for c in range(BOARD):
                lb = tk.Label(fr, text="~", width=3, height=1, relief="ridge",
                              font=("Courier", 14, "bold"))
                lb.grid(row=r + 2, column=c + 1)
                if clickable:
                    lb.bind("<Button-1>", lambda e, r=r, c=c: self._click(r, c))
                cells[(r, c)] = lb
        return cells

    def _click(self, r, c):
        if self.app:
            self.app.q.put(("line", cell_name(r, c)))

    def _enter(self, _ev):
        if self.app:
            self.app.q.put(("line", self.entry.get()))
        self.entry.delete(0, "end")

    def _close(self):
        if self.app:
            self.app.q.put(("quit",))

    def render(self, app):
        m = app.model
        self.bar.config(text=TURN_TXT.get(app.state, PHASE_TXT[app.state].upper()),
                        bg=self.BAR.get(app.state, "#546e7a"))
        self.info.config(text="FASE: %s | TURNO: %s | CONEXION: %s%s" % (
            PHASE_TXT[app.state], TURN_TXT.get(app.state, "-"), app.conn,
            "   [MODO SIMULADO]" if app.sim else ""))
        for grid, fn in ((self.own, m.own_symbol), (self.riv, m.rival_symbol)):
            for (r, c), lb in grid.items():
                s = fn(r, c)
                fg, bg = self.CELL[s]
                lb.config(text=s, fg=fg, bg=bg)
        self.listbox.delete(0, "end")
        for t in app.msgs:
            self.listbox.insert("end", t)
        if m.summary:
            s = m.summary
            self.listbox.insert("end", "GANADOR: %s | disparos J1=%d J2=%d | hundidos "
                                "por J1=%d, por J2=%d | BTN_RST reinicia." % (
                                    "JUGADOR 2 (TU)" if s["winner"] == 2 else "JUGADOR 1",
                                    s["shots1"], s["shots2"], s["sunk_by_1"], s["sunk_by_2"]))
        self.listbox.see("end")
        self.prompt.config(text=app.prompt() or "Comandos: r, hello, salir")

    def run(self, app):
        self.app = app
        app.start()

        def pump():
            if app.step(0.0):
                self.root.after(30, pump)
            else:
                app.view.render(app)
                self.root.after(600, self.root.destroy)

        self.root.after(30, pump)
        try:
            self.root.mainloop()
        except KeyboardInterrupt:
            pass
        finally:
            app.stop()
        return app.exit_code


# ---------------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------------
def list_ports():
    if serial is None:
        print("Falta pyserial: instale con  pip install pyserial")
        return 1
    ports = list(serial.tools.list_ports.comports())
    if not ports:
        print("No se encontraron puertos serie.")
    for p in sorted(ports):
        print("%-14s %s" % (p.device, p.description))
    return 0


def build_parser():
    ap = argparse.ArgumentParser(
        description="Aplicacion de PC del Jugador 2 - Batalla Naval (UART 115200 8N1)")
    ap.add_argument("--port", help="COMx (Windows) o /dev/ttyUSBx (Linux)")
    ap.add_argument("--sim", action="store_true",
                    help="MODO SIMULADO con un doble de prueba de la FPGA (no es entrega final)")
    ap.add_argument("--list-ports", action="store_true", help="lista los puertos y sale")
    ap.add_argument("--log", metavar="ARCHIVO", help="registra TX/RX con hora y hexadecimal")
    ap.add_argument("--gap-ms", type=float, default=2.0,
                    help="pausa entre bytes enviados, en ms (def. 2)")
    ap.add_argument("--timeout", type=float, default=1.5,
                    help="timeout de respuesta en segundos (def. 1.5)")
    ap.add_argument("--retries", type=int, default=3, help="reintentos maximos (def. 3)")
    ap.add_argument("--ui", choices=("auto", "gui", "consola"), default="auto",
                    help="interfaz: Tkinter o consola (auto = Tkinter si esta disponible)")
    ap.add_argument("--seed", type=int, default=None, help="semilla del simulador")
    return ap


def pick_ui(choice):
    if choice == "consola":
        return "consola"
    try:
        import tkinter  # noqa: F401
        if choice == "gui" or os.name == "nt" or os.environ.get("DISPLAY"):
            return "gui"
    except ImportError:
        if choice == "gui":
            print("Tkinter no esta disponible; se usa la consola.")
    return "consola"


def main(argv=None):
    args = build_parser().parse_args(argv)
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="replace")
    if args.list_ports:
        return list_ports()
    if args.sim:
        if serial is None:
            print("Falta pyserial: instale con  pip install pyserial")
            return 1
        link = SimLink(seed=args.seed)
    else:
        if not args.port:
            print("Indique --port COMx / /dev/ttyUSBx (use --list-ports para ver los disponibles).")
            return 2
        if serial is None:
            print("Falta pyserial: instale con  pip install pyserial")
            return 1
        try:
            link = SerialLink(args.port)
        except serial_errors() as e:
            print("No se pudo abrir el puerto %s: %s" % (args.port, e))
            return 1
    log = Logger(args.log)
    ui = pick_ui(args.ui)
    view = TkView() if ui == "gui" else ConsoleView()
    app = App(link, view, log=log, timeout=args.timeout, retries=args.retries,
              gap_s=args.gap_ms / 1000.0, sim=args.sim)
    if ui == "gui":
        return view.run(app)
    InputThread(app.q).start()
    code = app.run()
    print()
    return code


if __name__ == "__main__":
    sys.exit(main())
