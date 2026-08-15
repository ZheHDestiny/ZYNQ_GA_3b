"""Run candidate template seeds on the profile-5 board and record classifications."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "ps_app" / "host_backend"))

from ga3b_service import Ga3bBoardService, SearchRequest  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", default="COM13")
    parser.add_argument("--timeout", type=float, default=600.0)
    parser.add_argument("--presets", type=Path, default=ROOT / "ps_app" / "host_backend" /
                        "presets" / "trajectory_templates.json")
    parser.add_argument("--output", type=Path, default=ROOT / "doc" / "test_results" /
                        "v1_profile5_preset_scan.json")
    args = parser.parse_args()
    presets = json.loads(args.presets.read_text(encoding="utf-8"))
    service = Ga3bBoardService(args.port, timeout=args.timeout)
    records = []
    try:
        health = service.health()
        if health.get("hardware", {}).get("profile_decimal") != 5:
            raise RuntimeError(f"profile-5 board required: {health}")
        for preset in presets:
            result = service.search(SearchRequest.from_json(preset),
                                    preset["fitness_profile"], 1)
            records.append({"preset": preset, "result": result})
            print("GA3B_PROFILE5_PRESET", preset["id"],
                  result["classification"]["id"], result["result"]["steps"],
                  result["result"]["replay_consistency"]["steps_match"], flush=True)
    finally:
        service.close()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps({"hardware_profile": 5, "records": records},
                                      ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"GA3B_PROFILE5_PRESET_SCAN_PASS {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
