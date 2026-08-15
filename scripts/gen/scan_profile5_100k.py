"""Run a bounded Profile-5 100k-step GA hyperparameter scan on the board."""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "ps_app" / "host_backend"))

from ga3b_hifi_reference import replay_hifi  # noqa: E402
from ga3b_models import SearchResult  # noqa: E402
from ga3b_service import Ga3bBoardService, SearchRequest  # noqa: E402


KNOWN_SEEDS = [
    ("long_seed", 2995967490, 1001641397),
    ("close_seed", 1674287602, 2454635381),
    ("braid_seed", 2755326718, 882239138),
    ("recurrence_seed", 2686439567, 303573010),
]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", default="COM13")
    parser.add_argument("--timeout", type=float, default=600.0)
    parser.add_argument("--steps", type=int, default=100000)
    parser.add_argument("--max-gen", type=int, default=64)
    parser.add_argument("--mutation", type=int, default=20480)
    parser.add_argument("--crossover", type=int, default=57344)
    parser.add_argument("--names", nargs="*", default=None,
                        help="optional subset of seed labels")
    parser.add_argument("--output", type=Path, default=ROOT / "doc" / "test_results" /
                        "v1_profile5_100k_hyper_scan.json")
    args = parser.parse_args()
    service = Ga3bBoardService(args.port, timeout=args.timeout)
    records = []
    try:
        health = service.health()
        if health.get("hardware", {}).get("profile_decimal") != 5:
            raise RuntimeError(f"profile-5 board required: {health}")
        selected = [item for item in KNOWN_SEEDS
                    if args.names is None or item[0] in args.names]
        if not selected:
            raise ValueError("--names did not select any known seed")
        for name, seed0, seed1 in selected:
            request = SearchRequest(args.max_gen, args.steps, args.mutation,
                                    args.crossover, seed0, seed1)
            started = time.perf_counter()
            response = service._command(request.command())[-1]
            elapsed = time.perf_counter() - started
            if not response.ok or " OK RESULT " not in response.line:
                record = {"name": name, "request": request.__dict__,
                          "elapsed_seconds": elapsed, "error": response.line}
                records.append(record)
                args.output.parent.mkdir(parents=True, exist_ok=True)
                args.output.write_text(json.dumps({"profile": 5, "records": records},
                                                  ensure_ascii=False, indent=2),
                                       encoding="utf-8")
                print("GA3B_100K_SCAN_ERROR", name, response.line, flush=True)
                continue
            result = SearchResult.from_uart_line(response.line)
            replay = replay_hifi(list(result.genes), args.steps, max_points=1)
            record = {
                "name": name, "request": request.__dict__, "elapsed_seconds": elapsed,
                "result": result.to_dict(), "pc_survived_steps": replay["survived_steps"],
                "pc_failure": replay["failure"],
                "steps_match": replay["survived_steps"] == result.steps,
            }
            records.append(record)
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(json.dumps({"profile": 5, "records": records},
                                              ensure_ascii=False, indent=2), encoding="utf-8")
            print("GA3B_100K_SCAN", name, result.steps, replay["failure"],
                  f"{elapsed:.3f}s", "MATCH" if record["steps_match"] else "MISMATCH",
                  flush=True)
    finally:
        service.close()
    successful = [item for item in records if "result" in item]
    if not successful:
        print("GA3B_100K_SCAN_FAIL no successful result", args.output)
        return 2
    best = max(successful, key=lambda item: item["result"]["steps"])
    print("GA3B_100K_SCAN_PASS", best["name"], best["result"]["steps"], args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
