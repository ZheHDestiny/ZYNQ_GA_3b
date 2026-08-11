"""Run the GA3B UART protocol smoke test and fixed-seed repeatability soak."""

from __future__ import annotations

import argparse
import json
import time
from pathlib import Path

from ga3b_uart_client import Ga3bUartClient


def require_ok(lines: list, marker: str) -> None:
    if not lines or not lines[-1].ok or marker not in lines[-1].line:
        rendered = "\n".join(item.line for item in lines)
        raise RuntimeError(f"missing {marker!r} in response:\n{rendered}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", required=True)
    parser.add_argument("--count", type=int, default=100)
    parser.add_argument("--timeout", type=float, default=30.0)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    if args.count <= 0:
        parser.error("--count must be positive")

    client = Ga3bUartClient(args.port, timeout=args.timeout)
    started = time.monotonic()
    baseline_result: str | None = None
    try:
        ping = client.command("PING")
        require_ok(ping, "PONG")
        info = client.command("INFO")
        require_ok(info, "INFO")

        for iteration in range(1, args.count + 1):
            responses = client.command("SELFTEST", terminal="SELFTEST_PASS")
            require_ok(responses, "SELFTEST_PASS")
            results = [item.line for item in responses if " OK RESULT " in item.line]
            if len(results) != 1:
                raise RuntimeError(f"iteration {iteration}: expected one RESULT, got {results!r}")
            if baseline_result is None:
                baseline_result = results[0]
            elif results[0] != baseline_result:
                raise RuntimeError(
                    f"iteration {iteration}: fixed-seed result drift\n"
                    f"baseline: {baseline_result}\ncurrent:  {results[0]}"
                )
            if iteration == 1 or iteration % 10 == 0:
                print(f"GA3B_SOAK_PROGRESS {iteration}/{args.count}", flush=True)
    finally:
        client.close()

    elapsed = time.monotonic() - started
    report = {
        "status": "PASS",
        "port": args.port,
        "iterations": args.count,
        "elapsed_seconds": round(elapsed, 6),
        "average_seconds": round(elapsed / args.count, 6),
        "result": baseline_result,
    }
    print("GA3B_UART_SOAK_PASS " + json.dumps(report, ensure_ascii=True))
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
