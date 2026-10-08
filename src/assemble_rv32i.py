#!/usr/bin/env python3
"""Small two-pass assembler for the RV32I subset used by rtl/programa.asm."""

from __future__ import annotations

import argparse
import re
from pathlib import Path

REGISTERS = {"zero": 0, "ra": 1, "sp": 2, "gp": 3, "tp": 4}
REGISTERS.update({f"t{i}": r for i, r in enumerate((5, 6, 7))})
REGISTERS.update({"s0": 8, "fp": 8, "s1": 9})
REGISTERS.update({f"a{i}": 10 + i for i in range(8)})
REGISTERS.update({f"s{i}": 16 + i for i in range(2, 12)})
REGISTERS.update({"t3": 28, "t4": 29, "t5": 30, "t6": 31})

R_FUNCTS = {
    "add": (0b000, 0b0000000), "sub": (0b000, 0b0100000),
    "sll": (0b001, 0b0000000), "slt": (0b010, 0b0000000),
    "sltu": (0b011, 0b0000000), "xor": (0b100, 0b0000000),
    "srl": (0b101, 0b0000000), "sra": (0b101, 0b0100000),
    "or": (0b110, 0b0000000), "and": (0b111, 0b0000000),
}
I_FUNCTS = {"addi": 0b000, "slti": 0b010, "sltiu": 0b011,
            "xori": 0b100, "ori": 0b110, "andi": 0b111}
BRANCH_FUNCTS = {"beq": 0b000, "bne": 0b001,
                 "blt": 0b100, "bge": 0b101}
LOAD_FUNCTS = {"lb": 0b000, "lh": 0b001, "lw": 0b010,
               "lbu": 0b100, "lhu": 0b101}
STORE_FUNCTS = {"sb": 0b000, "sh": 0b001, "sw": 0b010}
SHIFT_FUNCTS = {"slli": (0b001, 0b0000000),
                "srli": (0b101, 0b0000000),
                "srai": (0b101, 0b0100000)}
NOP = 0x00000013
MEMORY_OPERAND = re.compile(r"^\s*([^()]*)\s*\(\s*([^()]+)\s*\)\s*$")


def number(token: str) -> int:
    return int(token.strip(), 0)


def reg(token: str) -> int:
    token = token.strip().lower()
    if token.startswith("x") and token[1:].isdigit():
        value = int(token[1:])
    elif token in REGISTERS:
        value = REGISTERS[token]
    else:
        raise ValueError(f"registro desconocido: {token}")
    if not 0 <= value <= 31:
        raise ValueError(f"registro fuera de rango: {token}")
    return value


def signed(value: int, bits: int, what: str) -> int:
    low, high = -(1 << (bits - 1)), (1 << (bits - 1)) - 1
    if not low <= value <= high:
        raise ValueError(f"{what} fuera de rango de {bits} bits: {value}")
    return value & ((1 << bits) - 1)


def clean_source(path: Path) -> list[tuple[int, str]]:
    result = []
    for line_no, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.split("#", 1)[0].strip()
        if line:
            result.append((line_no, line))
    return result


def parse(lines: list[tuple[int, str]]) -> tuple[dict[str, int], list[tuple[int, int, str]]]:
    labels: dict[str, int] = {}
    instructions: list[tuple[int, int, str]] = []
    pc = 0
    for line_no, original in lines:
        text = original
        while ":" in text:
            label, _, rest = text.partition(":")
            label = label.strip()
            if not re.fullmatch(r"[A-Za-z_.$][\w.$]*", label):
                raise ValueError(f"línea {line_no}: etiqueta inválida: {label}")
            if label in labels:
                raise ValueError(f"línea {line_no}: etiqueta duplicada: {label}")
            labels[label] = pc
            text = rest.strip()
            if not text:
                break
        if not text or text.startswith("."):
            continue
        instructions.append((line_no, pc, text))
        pc += 4
    return labels, instructions


def operands(text: str) -> tuple[str, list[str]]:
    parts = text.split(None, 1)
    mnemonic = parts[0].lower()
    args = [] if len(parts) == 1 else [x.strip() for x in parts[1].split(",")]
    return mnemonic, args


def branch_offset(token: str, pc: int, labels: dict[str, int]) -> int:
    target = labels[token] if token in labels else number(token)
    offset = target - pc if token in labels else target
    if offset & 1:
        raise ValueError(f"desplazamiento de branch no alineado: {offset}")
    return signed(offset, 13, "desplazamiento branch")


def encode(line_no: int, pc: int, text: str, labels: dict[str, int]) -> int:
    mnemonic, args = operands(text)
    try:
        if mnemonic == "nop":
            if args:
                raise ValueError("nop no recibe operandos")
            return NOP
        if mnemonic == "ret":
            if args:
                raise ValueError("ret no recibe operandos")
            return 0x00008067
        if mnemonic == "j":
            if len(args) != 1:
                raise ValueError("uso: j etiqueta")
            mnemonic, args = "jal", ["zero", args[0]]

        if mnemonic in R_FUNCTS:
            if len(args) != 3:
                raise ValueError(f"uso: {mnemonic} rd, rs1, rs2")
            rd, rs1, rs2 = map(reg, args)
            funct3, funct7 = R_FUNCTS[mnemonic]
            return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | 0x33

        if mnemonic in I_FUNCTS or mnemonic in SHIFT_FUNCTS:
            if len(args) != 3:
                raise ValueError(f"uso: {mnemonic} rd, rs1, inmediato")
            rd, rs1 = reg(args[0]), reg(args[1])
            if mnemonic in SHIFT_FUNCTS:
                funct3, funct7 = SHIFT_FUNCTS[mnemonic]
                shamt = number(args[2])
                if not 0 <= shamt <= 31:
                    raise ValueError(f"shamt fuera de rango: {shamt}")
                imm = (funct7 << 5) | shamt
            else:
                funct3 = I_FUNCTS[mnemonic]
                imm = signed(number(args[2]), 12, "inmediato")
            return (imm << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | 0x13

        if mnemonic in LOAD_FUNCTS:
            if len(args) != 2:
                raise ValueError(f"uso: {mnemonic} rd, offset(rs1)")
            match = MEMORY_OPERAND.match(args[1])
            if not match:
                raise ValueError(f"operando de memoria inválido: {args[1]}")
            imm, rs1, rd = signed(number(match.group(1) or "0"), 12, "offset"), reg(match.group(2)), reg(args[0])
            return (imm << 20) | (rs1 << 15) | (LOAD_FUNCTS[mnemonic] << 12) | (rd << 7) | 0x03

        if mnemonic in STORE_FUNCTS:
            if len(args) != 2:
                raise ValueError(f"uso: {mnemonic} rs2, offset(rs1)")
            match = MEMORY_OPERAND.match(args[1])
            if not match:
                raise ValueError(f"operando de memoria inválido: {args[1]}")
            imm, rs1, rs2 = signed(number(match.group(1) or "0"), 12, "offset"), reg(match.group(2)), reg(args[0])
            return (((imm >> 5) & 0x7f) << 25) | (rs2 << 20) | (rs1 << 15) | (STORE_FUNCTS[mnemonic] << 12) | ((imm & 0x1f) << 7) | 0x23

        if mnemonic in BRANCH_FUNCTS:
            if len(args) != 3:
                raise ValueError(f"uso: {mnemonic} rs1, rs2, etiqueta")
            rs1, rs2 = reg(args[0]), reg(args[1])
            imm = branch_offset(args[2], pc, labels)
            return (((imm >> 12) & 1) << 31) | (((imm >> 5) & 0x3f) << 25) | (rs2 << 20) | (rs1 << 15) | (BRANCH_FUNCTS[mnemonic] << 12) | (((imm >> 1) & 0xf) << 8) | (((imm >> 11) & 1) << 7) | 0x63

        if mnemonic == "jal":
            if len(args) == 1:
                rd, target = 1, args[0]
            elif len(args) == 2:
                rd, target = reg(args[0]), args[1]
            else:
                raise ValueError("uso: jal [rd,] etiqueta")
            target_addr = labels[target] if target in labels else number(target)
            offset = target_addr - pc if target in labels else target_addr
            if offset & 1:
                raise ValueError(f"desplazamiento jal no alineado: {offset}")
            imm = signed(offset, 21, "desplazamiento jal")
            return (((imm >> 20) & 1) << 31) | (((imm >> 1) & 0x3ff) << 21) | (((imm >> 11) & 1) << 20) | (((imm >> 12) & 0xff) << 12) | (rd << 7) | 0x6f

        if mnemonic == "jalr":
            if len(args) == 1:
                rd, rs1, immediate = 1, 1, args[0]
            elif len(args) == 2:
                rd, rs1, immediate = 1, reg(args[0]), args[1]
            elif len(args) == 3:
                rd, rs1, immediate = reg(args[0]), reg(args[1]), args[2]
            else:
                raise ValueError("uso: jalr [rd,] rs1, inmediato")
            imm = signed(number(immediate), 12, "inmediato jalr")
            return (imm << 20) | (rs1 << 15) | (rd << 7) | 0x67

        raise ValueError(f"instrucción no soportada: {mnemonic}")
    except (ValueError, KeyError) as error:
        raise ValueError(f"línea {line_no}: {error}") from error


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=Path("rtl/programa.asm"))
    parser.add_argument("--output", type=Path, default=Path("rtl/procesador/program.hex"))
    parser.add_argument("--depth", type=int, default=2048,
                        help="palabras de ROM a emitir (por defecto 2048 = 8 KiB)")
    args = parser.parse_args()
    if args.depth < 1:
        parser.error("--depth debe ser mayor que cero")

    labels, instructions = parse(clean_source(args.input))
    if len(instructions) > args.depth:
        parser.error(f"el programa usa {len(instructions)} palabras y supera ROM de {args.depth}")
    words = [encode(line_no, pc, text, labels) for line_no, pc, text in instructions]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("".join(f"{word:08x}\n" for word in words + [NOP] * (args.depth - len(words))), encoding="ascii")
    print(f"Generadas {len(words)} instrucciones ({len(words) * 4} bytes) en {args.output}; imagen rellenada a {args.depth} palabras.")


if __name__ == "__main__":
    main()
