"""Parsing and JSON models for the GA3B UART protocol."""

from __future__ import annotations

import re
from dataclasses import asdict, dataclass


RESULT_RE = re.compile(r"([a-zA-Z0-9_]+)=(0x[0-9A-Fa-f]+|[0-9]+)")


def signed_u32(value: int) -> int:
    value &= 0xFFFFFFFF
    return value - 0x100000000 if value & 0x80000000 else value


@dataclass(frozen=True)
class SearchResult:
    magic: int
    status: int
    best_idx: int
    fitness: int
    steps: int
    genes: tuple[int, ...]

    @classmethod
    def from_uart_line(cls, line: str) -> "SearchResult":
        if "GA3B_RSP OK RESULT " not in line:
            raise ValueError(f"not a GA3B RESULT line: {line!r}")
        fields = {key: int(value, 0) for key, value in RESULT_RE.findall(line)}
        required = {"magic", "status", "best_idx", "fitness_hi", "fitness_lo", "steps"}
        missing = sorted(required - fields.keys())
        if missing:
            raise ValueError(f"RESULT missing fields: {missing}")
        genes = tuple(fields[f"gene{i}"] & 0xFFFFFFFF for i in range(8))
        return cls(
            magic=fields["magic"],
            status=fields["status"],
            best_idx=fields["best_idx"],
            fitness=((fields["fitness_hi"] & 0xFFFFFFFF) << 32)
            | (fields["fitness_lo"] & 0xFFFFFFFF),
            steps=fields["steps"],
            genes=genes,
        )

    def to_dict(self) -> dict:
        data = asdict(self)
        data["fitness_hex"] = f"0x{self.fitness:016X}"
        data["fitness_decimal"] = self.fitness
        data["genes"] = [signed_u32(item) / 65536.0 for item in self.genes]
        data["genes_raw"] = [f"0x{item:08X}" for item in self.genes]
        data["genes_q16_signed"] = [signed_u32(item) for item in self.genes]
        data["stable"] = bool(self.fitness >> 32)
        return data


def parse_info_line(line: str) -> dict:
    fields = {key: int(value, 0) for key, value in RESULT_RE.findall(line)}
    return {
        "protocol": fields.get("protocol"),
        "version_decimal": fields.get("version", 0),
        "profile_decimal": fields.get("profile", 0),
        "status_decimal": fields.get("status", 0),
        "version": f"0x{fields.get('version', 0):08X}",
        "profile": f"0x{fields.get('profile', 0):08X}",
        "status": f"0x{fields.get('status', 0):08X}",
        "raw": f"0x{fields.get('raw', 0):08X}",
    }
