"""Minimal PC transport client for the standalone GA3B UART board agent."""

from __future__ import annotations

import argparse
import time
from dataclasses import dataclass

import serial


@dataclass(frozen=True)
class AgentResponse:
    line: str

    @property
    def ok(self) -> bool:
        return self.line.startswith("GA3B_RSP OK ")


class Ga3bUartClient:
    def __init__(self, port: str, baudrate: int = 115200, timeout: float = 30.0):
        self.serial = serial.Serial(port, baudrate=baudrate, timeout=0.2)
        self.timeout = timeout
        self.serial.reset_input_buffer()

    def close(self) -> None:
        self.serial.close()

    def command(self, command: str, terminal: str | None = None) -> list[AgentResponse]:
        self.serial.write((command.strip() + "\n").encode("ascii"))
        self.serial.flush()
        deadline = time.monotonic() + self.timeout
        responses: list[AgentResponse] = []
        while time.monotonic() < deadline:
            raw = self.serial.readline()
            if not raw:
                continue
            line = raw.decode("ascii", errors="replace").strip()
            if not line.startswith("GA3B_RSP "):
                continue
            response = AgentResponse(line)
            responses.append(response)
            if not response.ok or terminal is None or terminal in line:
                return responses
        raise TimeoutError(f"timeout waiting for response to {command!r}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", required=True, help="USB UART, for example COM13")
    parser.add_argument("--timeout", type=float, default=30.0)
    parser.add_argument("command", nargs="*", default=["SELFTEST"])
    args = parser.parse_args()

    command = " ".join(args.command) if args.command else "SELFTEST"
    terminal = "SELFTEST_PASS" if command == "SELFTEST" else None
    client = Ga3bUartClient(args.port, timeout=args.timeout)
    try:
        responses = client.command(command, terminal=terminal)
    finally:
        client.close()
    for response in responses:
        print(response.line)
    return 0 if responses[-1].ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
