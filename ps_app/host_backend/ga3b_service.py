"""Thread-safe board ownership and high-level GA3B operations."""

from __future__ import annotations

import threading
import time
import math
from dataclasses import dataclass

from ga3b_models import SearchResult, parse_info_line
from ga3b_reference import (
    FITNESS_PROFILES,
    assess_profile_match,
    classify_trajectory,
    score_trajectory,
    select_display_window,
    trajectory_metrics,
)
from ga3b_hifi_reference import (
    benchmark_hifi_numpy,
    benchmark_hifi_scalar,
    replay_hifi,
)
from ga3b_uart_client import Ga3bUartClient


@dataclass(frozen=True)
class SearchRequest:
    max_gen: int = 2
    steps: int = 256
    mutation_q16: int = 0x1000
    crossover_q16: int = 0xC000
    seed0: int = 0x12345678
    seed1: int = 0x87654321

    @classmethod
    def from_json(cls, data: dict) -> "SearchRequest":
        def number(name: str, default: int) -> int:
            value = data.get(name, default)
            return int(value, 0) if isinstance(value, str) else int(value)

        def probability_q16(percent_name: str, q16_name: str, default: int) -> int:
            """Accept browser percentages while preserving the Q16 API/RTL contract."""
            if percent_name not in data:
                return number(q16_name, default)
            try:
                percent = float(data[percent_name])
            except (TypeError, ValueError) as exc:
                raise ValueError(f"{percent_name} must be a number in 0..100") from exc
            if not math.isfinite(percent) or not 0.0 <= percent <= 100.0:
                raise ValueError(f"{percent_name} must be in 0..100")
            # Q0.16 has no exact representation for 1.0. Saturate 100% to
            # 0xffff; all other percentages use nearest-integer encoding.
            return min(65535, int(round(percent * 65536.0 / 100.0)))

        request = cls(
            max_gen=number("max_gen", 2), steps=number("steps", 256),
            mutation_q16=probability_q16("mutation_percent", "mutation_q16", 0x1000),
            crossover_q16=probability_q16("crossover_percent", "crossover_q16", 0xC000),
            seed0=number("seed0", 0x12345678), seed1=number("seed1", 0x87654321),
        )
        if not 1 <= request.max_gen <= 256:
            raise ValueError("max_gen must be in 1..256 for the HTTP service")
        if not 1 <= request.steps <= 131072:
            raise ValueError("steps must be in 1..131072 for the HTTP service")
        if not 0 <= request.mutation_q16 <= 65535 or not 0 <= request.crossover_q16 <= 65535:
            raise ValueError("Q16 rates must be in 0..65535")
        if not -0x80000000 <= request.seed0 <= 0xFFFFFFFF or not -0x80000000 <= request.seed1 <= 0xFFFFFFFF:
            raise ValueError("seeds must fit signed or unsigned 32-bit range")
        return cls(request.max_gen, request.steps, request.mutation_q16,
                   request.crossover_q16, request.seed0 & 0xFFFFFFFF,
                   request.seed1 & 0xFFFFFFFF)

    @property
    def candidate_evals(self) -> int:
        # RTL evaluates generation zero, then max_gen reproduced generations.
        return 32 * (self.max_gen + 1)

    def command(self) -> str:
        return (f"RUN {self.max_gen} {self.steps} {self.mutation_q16} "
                f"{self.crossover_q16} {self.seed0} {self.seed1}")


class Ga3bBoardService:
    def __init__(self, port: str, timeout: float = 30.0):
        self.port = port
        self.timeout = timeout
        self._client: Ga3bUartClient | None = None
        self._lock = threading.Lock()
        self.last_error: str | None = None

    def close(self) -> None:
        with self._lock:
            self._disconnect()

    def _disconnect(self) -> None:
        if self._client is not None:
            try:
                self._client.close()
            finally:
                self._client = None

    def _command(self, command: str, terminal: str | None = None):
        with self._lock:
            for attempt in range(2):
                try:
                    if self._client is None:
                        self._client = Ga3bUartClient(self.port, timeout=self.timeout)
                    result = self._client.command(command, terminal=terminal)
                    self.last_error = None
                    return result
                except Exception as exc:
                    self.last_error = str(exc)
                    self._disconnect()
                    if attempt:
                        raise

    def health(self) -> dict:
        started = time.perf_counter()
        try:
            pong = self._command("PING")[-1].line
            info_line = self._command("INFO")[-1].line
            hardware = parse_info_line(info_line)
            profile = hardware["profile_decimal"]
            profile_names = {3: "pure3_rf_legacy", 4: "pure3_hifi_symplectic",
                             5: "pure3_hifi_leapfrog_cached"}
            # v1.1 replay, templates and probes are synchronized to profile 5.
            # Profile 4 remains a valid board-agent fallback but must not be
            # presented by this service as model-consistent.
            ready = profile == 5
            return {"status": "ok" if ready else "profile_mismatch",
                    "board_connected": True, "accelerator_ready": ready,
                    "transport": "uart", "port": self.port,
                    "profile_name": profile_names.get(profile, "unknown"),
                    "latency_ms": (time.perf_counter() - started) * 1000,
                    "pong": pong, "hardware": hardware,
                    "trajectory_model": ("Q32.32 smooth-LUT cached Leapfrog"
                                         if profile == 5 else "profile mismatch")}
        except Exception as exc:
            return {"status": "degraded", "board_connected": False, "accelerator_ready": False,
                    "transport": "uart", "port": self.port, "error": str(exc)}

    def selftest(self) -> dict:
        started = time.perf_counter()
        responses = self._command("SELFTEST", terminal="SELFTEST_PASS")
        result_line = next(item.line for item in responses if " OK RESULT " in item.line)
        if "SELFTEST_PASS" not in responses[-1].line:
            raise RuntimeError(responses[-1].line)
        return {"status": "PASS", "elapsed_ms": (time.perf_counter() - started) * 1000,
                "result": SearchResult.from_uart_line(result_line).to_dict()}

    @staticmethod
    def estimate_search(request: SearchRequest, candidate_count: int) -> dict:
        # Conservative admission model.  Long-lived populations make runtime
        # depend primarily on the requested integration window, while GA and
        # UART add a smaller term.  It deliberately overestimates fast-failing
        # populations instead of accepting a request that can monopolize COM.
        # Calibrated conservatively from the physical Zynq-7020 board. Runtime
        # is strongly data-dependent because unstable lanes terminate early.
        # Profile-5 physical-board calibration (2026-08-15): a 64-generation,
        # 100000-step long-lived run costs roughly 40--50 s per multi-start;
        # eight starts plus PC replay measured 457.3 s.  Use a conservative
        # upper estimate rather than the former 124.7 s underestimate.
        per_candidate_seconds = (0.75 + request.steps / 2500.0 +
                                 request.max_gen * 0.25 + request.steps / 50_000.0)
        return {"candidate_count": candidate_count,
                "estimated_seconds": round(per_candidate_seconds * candidate_count, 3),
                "estimated_board_eval_count": request.candidate_evals * candidate_count,
                "limit_seconds": 600.0,
                "estimate_model": "profile5_conservative_board_plus_pc_replay_v2",
                "calibration_reference_seconds": 457.332}

    def capabilities(self) -> dict:
        return {
            "fitness_profiles": [{"id": key, **value} for key, value in FITNESS_PROFILES.items()],
            "limits": {"max_gen": 256, "steps": 131072, "candidate_count": 16,
                       "custom_steps": 131072, "request_budget_seconds": 600.0,
                       "position_abs": 2.0, "velocity_abs": 1.0,
                       "collision_l1_min": 0.125},
            "hardware_profile": {"id": 5, "name": "pure3_hifi_leapfrog_cached"},
            "trajectory_model": {
                "state": "Q32.32", "force": "smooth normalized inverse-r^3 LUT",
                "integrator": "cached-acceleration Leapfrog", "dt": 1.0 / 256.0,
                "bit_exact_survival_checked": True,
            },
            "ga_initialization": "uniform_u32_full_bounds_with_midpoint_elite",
            "input_encoding": {
                "probabilities": "browser percent 0.00..100.00; backend decodes to Q0.16",
                "seed0": "RNG reproducibility primary word",
                "seed1": "RNG reproducibility mixing word",
                "seed_mix": "seed0 XOR swap16(seed1) initializes xorshift32",
            },
            "custom_execution": "pc_profile5_replay",
            "custom_execution_note": (
                "Custom states are validated and replayed by the PC with the profile-5 Q32.32 "
                "smooth-LUT cached-Leapfrog model. "
                "The current protocol does not inject a chromosome directly into PL."
            ),
        }

    @staticmethod
    def _derived_seed(seed: int, index: int) -> int:
        value = (seed + 0x9E3779B9 * index) & 0xFFFFFFFF
        value ^= value << 13 & 0xFFFFFFFF
        value ^= value >> 17
        value ^= value << 5 & 0xFFFFFFFF
        return value & 0xFFFFFFFF

    def search(self, request: SearchRequest, profile: str = "survival",
               candidate_count: int | None = None) -> dict:
        if profile not in FITNESS_PROFILES:
            raise ValueError(f"fitness_profile must be one of {sorted(FITNESS_PROFILES)}")
        if candidate_count is None:
            candidate_count = int(FITNESS_PROFILES[profile]["recommended_candidates"])
        if not 1 <= candidate_count <= 16:
            raise ValueError("candidate_count must be in 1..16")
        estimate = self.estimate_search(request, candidate_count)
        if estimate["estimated_seconds"] > estimate["limit_seconds"]:
            raise ValueError(
                f"estimated load {estimate['estimated_seconds']:.1f}s exceeds "
                f"{estimate['limit_seconds']:.0f}s service budget"
            )

        started = time.perf_counter()
        ranked = []
        total_board_evals = 0
        for index in range(candidate_count):
            # Candidate zero is the exact user/preset seed.  Additional
            # multi-start candidates are deterministically derived from it.
            candidate_request = SearchRequest(
                max_gen=request.max_gen, steps=request.steps,
                mutation_q16=request.mutation_q16, crossover_q16=request.crossover_q16,
                seed0=(request.seed0 if index == 0 else
                       self._derived_seed(request.seed0, index)),
                seed1=(request.seed1 if index == 0 else
                       self._derived_seed(request.seed1, index + 0x101)),
            )
            responses = self._command(candidate_request.command())
            if not responses[-1].ok:
                raise RuntimeError(responses[-1].line)
            result = SearchResult.from_uart_line(responses[-1].line)
            trajectory = replay_hifi(list(result.genes), request.steps,
                                     integrator="leapfrog")
            score, metrics = score_trajectory(profile, trajectory)
            ranked.append((score, index, result, trajectory, metrics, candidate_request))
            total_board_evals += candidate_request.candidate_evals
        ranked.sort(key=lambda item: item[0], reverse=True)
        score, selected_index, result, trajectory, metrics, selected_request = ranked[0]
        elapsed = time.perf_counter() - started
        payload = result.to_dict()
        payload["trajectory"] = trajectory
        payload["display_trajectory"] = select_display_window(trajectory, profile)
        payload["profile_score"] = score
        payload["trajectory_metrics"] = metrics
        payload["replay_consistency"] = {
            "hardware_survived_steps": result.steps,
            "pc_survived_steps": trajectory["survived_steps"],
            "steps_match": result.steps == trajectory["survived_steps"],
            "model": trajectory["model"],
        }
        payload["profile_match"] = assess_profile_match(profile, metrics)
        classification = classify_trajectory(metrics, result.steps, profile)
        payload["classification"] = classification
        return {"status": "PASS", "elapsed_ms": elapsed * 1000,
                "candidate_evals": total_board_evals,
                "candidate_evals_per_second": total_board_evals / elapsed,
                "fitness_profile": {"id": profile, **FITNESS_PROFILES[profile]},
                "candidate_count": candidate_count, "selected_candidate": selected_index,
                "load_estimate": estimate, "request": request.__dict__,
                "selected_seeds": {"seed0": selected_request.seed0, "seed1": selected_request.seed1},
                "ranking": [{"rank": i+1, "score": item[0], "candidate": item[1],
                             "survived_ratio": item[4]["survived_ratio"]}
                            for i, item in enumerate(ranked[:5])],
                "classification": classification, "result": payload}

    def custom_replay(self, data: dict) -> dict:
        try:
            values = [float(data[name]) for name in
                      ("x0", "y0", "vx0", "vy0", "x1", "y1", "vx1", "vy1")]
            steps = int(data.get("steps", 4096))
        except (KeyError, TypeError, ValueError) as exc:
            raise ValueError("custom state requires eight finite numeric values") from exc
        if any(not math.isfinite(value) for value in values):
            raise ValueError("custom state values must be finite")
        if not 1 <= steps <= 131072:
            raise ValueError("custom steps must be in 1..131072")
        for index in (0, 1, 4, 5):
            if abs(values[index]) > 2.0:
                raise ValueError("x/y inputs must be within [-2, 2]")
        for index in (2, 3, 6, 7):
            if abs(values[index]) > 1.0:
                raise ValueError("velocity inputs must be within [-1, 1]")
        bodies = ((values[0], values[1]), (values[4], values[5]),
                  (-values[0]-values[4], -values[1]-values[5]))
        for a, b in ((0,1),(0,2),(1,2)):
            if abs(bodies[b][0]-bodies[a][0]) + abs(bodies[b][1]-bodies[a][1]) < 0.125:
                raise ValueError("initial bodies violate the RTL collision threshold")
        estimated = steps / 50_000.0
        if estimated > 5.0:
            raise ValueError("custom replay exceeds the 5 second synchronous CPU budget")
        genes = [int(round(value * 65536.0)) & 0xFFFFFFFF for value in values]
        started = time.perf_counter()
        trajectory = replay_hifi(genes, steps, integrator="leapfrog")
        metrics = trajectory_metrics(trajectory)
        classification = classify_trajectory(metrics, trajectory["survived_steps"])
        return {"status": "PASS", "execution_target": "pc_profile5_replay",
                "elapsed_ms": (time.perf_counter()-started)*1000,
                "estimated_seconds": round(estimated, 3), "steps": steps,
                "genes": values, "genes_raw": [f"0x{value:08X}" for value in genes],
                "derived_body2": {"x": bodies[2][0], "y": bodies[2][1],
                                  "vx": -values[2]-values[6], "vy": -values[3]-values[7]},
                "trajectory": trajectory,
                "display_trajectory": select_display_window(trajectory, "braid"),
                "trajectory_metrics": metrics, "classification": classification}

    def benchmark(self, request: SearchRequest, hardware_runs: int = 3) -> dict:
        if not 1 <= hardware_runs <= 20:
            raise ValueError("hardware_runs must be in 1..20")
        timings = []
        last = None
        for _ in range(hardware_runs):
            started = time.perf_counter()
            responses = self._command(request.command())
            elapsed = time.perf_counter() - started
            if not responses[-1].ok:
                raise RuntimeError(responses[-1].line)
            last = SearchResult.from_uart_line(responses[-1].line)
            timings.append(elapsed)
        assert last is not None
        average = sum(timings) / len(timings)
        candidates = request.candidate_evals
        genes = list(last.genes)
        return {
            "status": "PASS",
            "workload": {"max_gen": request.max_gen, "steps": request.steps,
                         "hardware_candidate_evals": candidates, "hardware_runs": hardware_runs},
            "probes": [
                {"name": "Zynq-7020 FPGA", "kind": "complete GA + DMA + UART end-to-end",
                 "elapsed_ms": average * 1000, "candidate_evals": candidates,
                 "candidate_evals_per_second": candidates / average,
                 "samples_ms": [item * 1000 for item in timings]},
                benchmark_hifi_scalar(genes, request.steps, candidates),
                benchmark_hifi_numpy(genes, request.steps, candidates),
            ],
            "comparison_note": (
                "FPGA probe includes population initialization, GA selection/reproduction, AXI DMA and UART. "
                "Python scalar replays the profile-5 fixed-point fitness; NumPy uses the same smooth-force "
                "Leapfrog physics in float64 but is not LUT-bit-exact. Both omit GA selection/reproduction "
                "and transport, so they remain diagnostic proxies rather than algorithm-identical speedups."
            ),
        }
