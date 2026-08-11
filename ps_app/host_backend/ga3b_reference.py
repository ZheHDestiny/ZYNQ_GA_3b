"""Bit-oriented Pure3 trajectory replay and honest software performance probes."""

from __future__ import annotations

import time
import math


ESCAPE_ABS = 524288
COLLISION_L1 = 8192


def i32(value: int) -> int:
    value &= 0xFFFFFFFF
    return value - 0x100000000 if value & 0x80000000 else value


def force_shift(dx: int, dy: int) -> int:
    l1 = abs(dx) + abs(dy)
    if l1 < 8192:
        return 4
    if l1 < 16384:
        return 5
    if l1 < 32768:
        return 6
    if l1 < 65536:
        return 7
    if l1 < 131072:
        return 8
    if l1 < 262144:
        return 9
    if l1 < 524288:
        return 10
    return 11


def _failed(pos: list[list[int]]) -> bool:
    for a, b in ((0, 1), (0, 2), (1, 2)):
        if abs(pos[b][0] - pos[a][0]) + abs(pos[b][1] - pos[a][1]) < COLLISION_L1:
            return True
    return any(abs(x) > ESCAPE_ABS or abs(y) > ESCAPE_ABS for x, y in pos)


def replay_trajectory(genes_raw: list[int] | tuple[int, ...], steps: int,
                      max_points: int = 720) -> dict:
    """Replay the approximate Q16.16 RTL integrator and return sampled positions."""
    g = [i32(item) for item in genes_raw]
    pos = [[g[0], g[1]], [g[4], g[5]], [i32(-g[0] - g[4]), i32(-g[1] - g[5])]]
    vel = [[g[2], g[3]], [g[6], g[7]], [i32(-g[2] - g[6]), i32(-g[3] - g[7])]]
    stride = max(1, (steps + max_points - 1) // max_points)
    frames = [{"step": 0, "bodies": [[x / 65536.0, y / 65536.0] for x, y in pos]}]
    survived = 0
    failure = None

    for step in range(steps):
        acc = [[0, 0], [0, 0], [0, 0]]
        for a, b in ((0, 1), (0, 2), (1, 2)):
            dx = i32(pos[b][0] - pos[a][0])
            dy = i32(pos[b][1] - pos[a][1])
            shift = force_shift(dx, dy)
            fx, fy = i32(dx >> shift), i32(dy >> shift)
            acc[a][0], acc[a][1] = i32(acc[a][0] + fx), i32(acc[a][1] + fy)
            acc[b][0], acc[b][1] = i32(acc[b][0] - fx), i32(acc[b][1] - fy)
        old_vel = [item[:] for item in vel]
        for body in range(3):
            vel[body][0] = i32(vel[body][0] + (acc[body][0] >> 8))
            vel[body][1] = i32(vel[body][1] + (acc[body][1] >> 8))
            pos[body][0] = i32(pos[body][0] + (old_vel[body][0] >> 8))
            pos[body][1] = i32(pos[body][1] + (old_vel[body][1] >> 8))
        if _failed(pos):
            failure = "collision_or_escape"
        else:
            survived += 1
        if (step + 1) % stride == 0 or step + 1 == steps or failure:
            frames.append({"step": step + 1, "bodies": [[x / 65536.0, y / 65536.0] for x, y in pos]})
        if failure:
            break
    return {"frames": frames, "survived_steps": survived, "failure": failure,
            "model": "RTL Q16.16 replay", "requested_steps": steps}


def scalar_fitness(genes_raw: list[int] | tuple[int, ...], steps: int) -> int:
    return replay_trajectory(genes_raw, steps, max_points=1)["survived_steps"]


def benchmark_scalar(genes_raw: list[int], steps: int, candidates: int) -> dict:
    started = time.perf_counter()
    checksum = 0
    for _ in range(candidates):
        checksum += scalar_fitness(genes_raw, steps)
    elapsed = time.perf_counter() - started
    return {"name": "Python scalar", "kind": "fitness-only proxy", "elapsed_ms": elapsed * 1000,
            "candidate_evals": candidates, "candidate_evals_per_second": candidates / elapsed,
            "checksum": checksum}


def benchmark_numpy(genes_raw: list[int], steps: int, candidates: int) -> dict:
    """Batch-vectorized replay. It intentionally measures fitness only, not Python GA logic."""
    try:
        import numpy as np
    except ImportError:
        return {"name": "NumPy batch", "kind": "fitness-only proxy", "available": False}

    g = np.asarray([i32(item) for item in genes_raw], dtype=np.int64)
    pos = np.empty((candidates, 3, 2), dtype=np.int64)
    vel = np.empty_like(pos)
    pos[:, 0, :] = g[[0, 1]]; pos[:, 1, :] = g[[4, 5]]; pos[:, 2, :] = -pos[:, 0, :] - pos[:, 1, :]
    vel[:, 0, :] = g[[2, 3]]; vel[:, 1, :] = g[[6, 7]]; vel[:, 2, :] = -vel[:, 0, :] - vel[:, 1, :]
    alive = np.ones(candidates, dtype=bool)
    survived = np.zeros(candidates, dtype=np.int64)
    started = time.perf_counter()
    for _ in range(steps):
        acc = np.zeros_like(pos)
        for a, b in ((0, 1), (0, 2), (1, 2)):
            delta = pos[:, b, :] - pos[:, a, :]
            l1 = np.abs(delta[:, 0]) + np.abs(delta[:, 1])
            shift = np.select(
                [l1 < 8192, l1 < 16384, l1 < 32768, l1 < 65536, l1 < 131072,
                 l1 < 262144, l1 < 524288], [4, 5, 6, 7, 8, 9, 10], default=11)
            force = np.right_shift(delta, shift[:, None])
            acc[:, a, :] += force; acc[:, b, :] -= force
        old_vel = vel.copy()
        vel += np.right_shift(acc, 8)
        pos += np.right_shift(old_vel, 8)
        collision = np.zeros(candidates, dtype=bool)
        for a, b in ((0, 1), (0, 2), (1, 2)):
            d = pos[:, b, :] - pos[:, a, :]
            collision |= (np.abs(d[:, 0]) + np.abs(d[:, 1])) < COLLISION_L1
        escaped = (np.abs(pos) > ESCAPE_ABS).any(axis=(1, 2))
        alive &= ~(collision | escaped)
        survived += alive
    elapsed = time.perf_counter() - started
    return {"name": "NumPy batch", "kind": "vectorized fitness-only proxy", "available": True,
            "elapsed_ms": elapsed * 1000, "candidate_evals": candidates,
            "candidate_evals_per_second": candidates / elapsed, "checksum": int(survived.sum())}


FITNESS_PROFILES = {
    "survival": {
        "name": "长时生存",
        "short": "稳定即可",
        "description": "最大化无碰撞、无逃逸的存活窗口；允许三体相互远离。",
        "physics": "有限时间有界性与碰撞约束",
        "recommended_candidates": 1,
        "recommended_steps": 32768,
    },
    "close_pass": {
        "name": "安全擦掠",
        "short": "持续近掠但不碰撞",
        "description": "在完整存活前提下奖励多次安全近距离掠过，并惩罚贴近碰撞阈值。",
        "physics": "近心点事件、碰撞裕量与有限时间生存",
        "recommended_candidates": 6,
        "recommended_steps": 32768,
    },
    "braid": {
        "name": "三星纠缠",
        "short": "互相换位并保持紧凑",
        "description": "奖励绕质心转角、角序换位和紧凑驻留，抑制单调背离。",
        "physics": "质心系角动、排列交换与均方半径",
        "recommended_candidates": 8,
        "recommended_steps": 32768,
    },
    "recurrence": {
        "name": "近周期回归",
        "short": "末态回到初态附近",
        "description": "奖励位置形状在窗口末端回归，同时要求全程存活且保持有界。",
        "physics": "Poincaré 回归误差与构型尺度漂移",
        "recommended_candidates": 8,
        "recommended_steps": 32768,
    },
}


def trajectory_metrics(trajectory: dict) -> dict:
    """Extract physically interpretable, scale-normalized metrics from replay frames."""
    frames = trajectory["frames"]
    requested = max(1, int(trajectory["requested_steps"]))
    survived_ratio = min(1.0, trajectory["survived_steps"] / requested)
    pair_series = [[], [], []]
    radii = []
    total_path = 0.0
    total_winding = 0.0
    exchange_count = 0
    previous_angles = None
    previous_bodies = None

    for frame in frames:
        bodies = frame["bodies"]
        for index, (a, b) in enumerate(((0, 1), (0, 2), (1, 2))):
            pair_series[index].append(math.dist(bodies[a], bodies[b]))
        radii.append(math.sqrt(sum(x*x + y*y for x, y in bodies) / 3.0))
        angles = [math.atan2(y, x) for x, y in bodies]
        if previous_angles is not None:
            for current, previous in zip(angles, previous_angles):
                total_winding += abs((current - previous + math.pi) % (2 * math.pi) - math.pi)
            old_order = sorted(range(3), key=lambda i: previous_angles[i])
            new_order = sorted(range(3), key=lambda i: angles[i])
            if old_order != new_order:
                exchange_count += 1
        if previous_bodies is not None:
            total_path += sum(math.dist(a, b) for a, b in zip(previous_bodies, bodies))
        previous_angles = angles
        previous_bodies = bodies

    all_pairs = [value for series in pair_series for value in series]
    min_pair = min(all_pairs)
    mean_pair = sum(all_pairs) / len(all_pairs)
    max_radius = max(radii)
    mean_radius = sum(radii) / len(radii)
    compact_fraction = sum(radius <= 3.0 for radius in radii) / len(radii)

    # Count local pair-distance minima in a safe close-pass band.  The RTL L1
    # collision threshold is 0.125; 0.25 keeps a measurable safety margin.
    close_passes = 0
    for series in pair_series:
        for index in range(1, len(series) - 1):
            value = series[index]
            if 0.25 <= value <= 1.25 and value < series[index-1] and value <= series[index+1]:
                close_passes += 1

    initial = frames[0]["bodies"]
    final = frames[-1]["bodies"]
    # Compare all permutations because equal-mass choreography may exchange body labels.
    permutations = ((0,1,2),(0,2,1),(1,0,2),(1,2,0),(2,0,1),(2,1,0))
    initial_scale = max(0.25, math.sqrt(sum(x*x+y*y for x,y in initial) / 3.0))
    recurrence_error = min(
        math.sqrt(sum((final[i][0]-initial[p[i]][0])**2 +
                      (final[i][1]-initial[p[i]][1])**2 for i in range(3)) / 3.0)
        / initial_scale for p in permutations
    )
    radial_drift = abs(radii[-1] - radii[0]) / max(0.25, radii[0])
    collision_margin = max(0.0, min_pair - 0.125)
    return {
        "survived_ratio": survived_ratio, "min_pair_distance": min_pair,
        "mean_pair_distance": mean_pair, "max_rms_radius": max_radius,
        "mean_rms_radius": mean_radius, "compact_fraction": compact_fraction,
        "close_pass_count": close_passes, "winding_radians": total_winding,
        "exchange_count": exchange_count, "path_length": total_path,
        "recurrence_error": recurrence_error, "radial_drift": radial_drift,
        "collision_margin": collision_margin,
    }


def score_trajectory(profile: str, trajectory: dict) -> tuple[float, dict]:
    if profile not in FITNESS_PROFILES:
        raise ValueError(f"unknown fitness profile: {profile}")
    m = trajectory_metrics(trajectory)
    survival = m["survived_ratio"]
    hard_survival = 12.0 * survival
    if profile == "survival":
        score = hard_survival - 0.15 * m["radial_drift"]
    elif profile == "close_pass":
        safe_margin = min(1.0, m["collision_margin"] / 0.25)
        score = (hard_survival + 1.4 * min(6, m["close_pass_count"]) +
                 1.2 / (0.35 + m["mean_pair_distance"]) + 0.8 * safe_margin -
                 1.5 * max(0.0, 0.25 - m["min_pair_distance"]))
    elif profile == "braid":
        score = (hard_survival + 1.8 * m["compact_fraction"] +
                 0.35 * min(12.0, m["winding_radians"]) +
                 0.65 * min(8, m["exchange_count"]) -
                 1.4 * m["radial_drift"] - 0.1 * m["mean_pair_distance"])
    else:
        score = (hard_survival + 4.0 / (0.25 + m["recurrence_error"]) +
                 1.4 * m["compact_fraction"] + 0.12 * min(10.0, m["winding_radians"]) -
                 1.8 * m["radial_drift"])
    # A failed candidate must never beat a complete survivor through visual terms.
    if survival < 1.0:
        score -= 20.0 * (1.0 - survival)
    return score, m


def assess_profile_match(profile: str, metrics: dict) -> dict:
    """Do not label a best-available trajectory as matching a profile unless it qualifies."""
    checks = {
        "survival": (metrics["survived_ratio"] >= 1.0,
                     "完整存活窗口"),
        "close_pass": (metrics["survived_ratio"] >= 1.0 and
                       metrics["close_pass_count"] >= 1 and
                       metrics["min_pair_distance"] >= 0.25,
                       "完整存活，至少一次 0.25–1.25 安全近掠"),
        "braid": (metrics["survived_ratio"] >= 0.75 and
                  metrics["winding_radians"] >= math.pi and
                  metrics["exchange_count"] >= 1 and
                  metrics["compact_fraction"] >= 0.25,
                  "存活≥75%，累计绕转≥π，发生换位且紧凑驻留≥25%"),
        "recurrence": (metrics["survived_ratio"] >= 1.0 and
                       metrics["recurrence_error"] <= 0.35 and
                       metrics["radial_drift"] <= 0.35,
                       "完整存活，回归误差与构型尺度漂移均≤0.35"),
    }
    matched, criterion = checks[profile]
    return {"matched": matched, "criterion": criterion,
            "label": "目标吻合" if matched else "仅为当前候选中的最优近似"}


TRAJECTORY_CLASSES = {
    "long_survival": "长时生存",
    "safe_close_pass": "安全擦掠",
    "three_body_braid": "三星纠缠",
    "near_recurrence": "近周期回归",
    "unclassified": "未归类轨迹",
}


def classify_trajectory(metrics: dict, survived_steps: int = 0) -> dict:
    """Apply transparent finite-window labels; this is not a stability proof."""
    if (metrics["recurrence_error"] <= 4.0 and metrics["radial_drift"] <= 3.2
            and survived_steps >= 16000):
        ident, confidence = "near_recurrence", 0.72
        reasons = [f"末态归一化回归误差 {metrics['recurrence_error']:.3f}",
                   f"径向漂移 {metrics['radial_drift']:.3f}"]
    elif ((metrics["winding_radians"] >= 7.0 or metrics["exchange_count"] >= 6)
          and survived_steps >= 16000):
        ident, confidence = "three_body_braid", 0.82
        reasons = [f"累计绕转 {metrics['winding_radians']:.2f} rad",
                   f"角序交换 {metrics['exchange_count']} 次"]
    elif (metrics["close_pass_count"] >= 3 and metrics["min_pair_distance"] >= 0.25
          and survived_steps >= 16000):
        ident, confidence = "safe_close_pass", 0.86
        reasons = [f"安全近掠 {metrics['close_pass_count']} 次",
                   f"最小间距 {metrics['min_pair_distance']:.3f}"]
    elif survived_steps >= 20000:
        ident = "long_survival"
        confidence = min(0.95, 0.65 + (survived_steps - 20000) / 20000.0)
        reasons = [f"无碰撞/逃逸生存 {survived_steps} 步"]
    else:
        ident, confidence = "unclassified", 0.35
        reasons = ["尚未达到四类演示规则中的任一组阈值"]
    return {"id": ident, "name": TRAJECTORY_CLASSES[ident],
            "confidence": round(confidence, 3), "reasons": reasons,
            "finite_window_only": True}


def select_display_window(trajectory: dict, profile: str,
                          max_frames: int = 240) -> dict:
    """Select a continuous event-rich animation window without changing physics results.

    Full-run metrics and survived_steps remain untouched.  This only prevents a
    late escape from forcing the camera to scale away an earlier close pass or
    braid.  Returned frame steps retain their original absolute indices.
    """
    frames = trajectory["frames"]
    if len(frames) <= max_frames:
        selected = frames
        start = 0
    else:
        size = max_frames
        best_score = -float("inf")
        start = 0
        for left in range(0, len(frames) - size + 1, max(1, size // 24)):
            window = frames[left:left+size]
            pair_min = float("inf")
            radii = []
            path = 0.0
            winding = 0.0
            recurrence = 0.0
            previous = None
            previous_angles = None
            for frame in window:
                bodies = frame["bodies"]
                pair_min = min(pair_min, *(math.dist(bodies[a], bodies[b])
                                           for a,b in ((0,1),(0,2),(1,2))))
                radii.append(math.sqrt(sum(x*x+y*y for x,y in bodies)/3.0))
                angles = [math.atan2(y,x) for x,y in bodies]
                if previous is not None:
                    path += sum(math.dist(a,b) for a,b in zip(previous,bodies))
                    winding += sum(abs((a-b+math.pi)%(2*math.pi)-math.pi)
                                   for a,b in zip(angles,previous_angles))
                previous, previous_angles = bodies, angles
            recurrence = sum(math.dist(a,b) for a,b in zip(window[0]["bodies"],
                                                            window[-1]["bodies"])) / 3.0
            mean_radius = sum(radii)/len(radii)
            compact = sum(r <= 3.0 for r in radii)/len(radii)
            if profile == "close_pass":
                # Prefer a safe near encounter centered in a moving window.
                score = 5.0/(0.20+abs(pair_min-0.45)) + path/(1+mean_radius)
            elif profile == "braid":
                score = 2.2*winding + 2.0*compact + path/(1+mean_radius) - .4*mean_radius
            elif profile == "recurrence":
                score = 4.0/(0.20+recurrence) + 1.3*winding + compact - .25*mean_radius
            else:
                score = 2.0*compact + path/(1+mean_radius) - .3*mean_radius
            if score > best_score:
                best_score, start = score, left
        selected = frames[start:start+size]
    return {
        "frames": selected,
        "window_start_step": selected[0]["step"],
        "window_end_step": selected[-1]["step"],
        "full_start_step": frames[0]["step"],
        "full_end_step": frames[-1]["step"],
        "full_frame_count": len(frames),
        "display_frame_count": len(selected),
        "is_highlight_window": len(selected) < len(frames),
        "selection_profile": profile,
        "note": "连续物理轨迹高亮窗口；完整存活与 fitness 指标未截断",
    }
