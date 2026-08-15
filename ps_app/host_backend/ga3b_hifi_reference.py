"""Profile-5 high-precision smooth-force Pure3 reference/replay model.

Its fixed-point path mirrors the deployed Q32.32, normalized inverse-r^3 LUT,
cached-acceleration Leapfrog lane closely enough to require exact survived-step
agreement in board tests.  The NumPy benchmark below is intentionally a
float64 proxy and does not claim LUT bit equivalence.
"""

from __future__ import annotations

import math
import time


FRAC_BITS = 32
ONE = 1 << FRAC_BITS
DT_SHIFT = 8                 # dt = 1/256, identical physical time scale
GM_Q = 1 << 24               # GM = 1/256, matched near r=1 to the old lane
COLLISION_L1_Q = 8192 << 16  # 0.125 promoted from Q16.16 to Q32.32
ESCAPE_ABS_Q = 524288 << 16  # 8.0 promoted from Q16.16 to Q32.32
MIN_RADIUS_Q = COLLISION_L1_Q
MANTISSA_BITS = 10
MANTISSA_SIZE = 1 << MANTISSA_BITS


def round_shift(value: int, shift: int) -> int:
    """Round a signed integer to nearest while shifting right."""
    if shift <= 0:
        return value << (-shift)
    half = 1 << (shift - 1)
    return (value + half) >> shift if value >= 0 else -((-value + half) >> shift)


def signed_u32(value: int) -> int:
    value &= 0xFFFFFFFF
    return value - 0x100000000 if value & 0x80000000 else value


def q16_to_q32(value: int) -> int:
    return signed_u32(value) << 16


def _make_inv_mantissa3_lut() -> tuple[int, ...]:
    # 1025 endpoints permit linear interpolation over 1024 mantissa cells.
    return tuple(round((1.0 / (1.0 + index / MANTISSA_SIZE) ** 3) * ONE)
                 for index in range(MANTISSA_SIZE + 1))


INV_MANTISSA3_LUT = _make_inv_mantissa3_lut()


def inv_r3_coefficient_q(radius_q: int) -> int:
    """Return quantized GM/r^3 in Q32 using log-normalized LUT interpolation."""
    radius_q = max(MIN_RADIUS_Q, radius_q)
    msb = radius_q.bit_length() - 1
    exponent = msb - FRAC_BITS
    normalized = radius_q << (FRAC_BITS - msb) if msb <= FRAC_BITS else radius_q >> (msb - FRAC_BITS)
    fraction = normalized - ONE
    cell_shift = FRAC_BITS - MANTISSA_BITS
    index = min(MANTISSA_SIZE - 1, fraction >> cell_shift)
    remainder = fraction & ((1 << cell_shift) - 1)
    left = INV_MANTISSA3_LUT[index]
    right = INV_MANTISSA3_LUT[index + 1]
    inv_m3 = left + round_shift((right - left) * remainder, cell_shift)
    coefficient = round_shift(GM_Q * inv_m3, FRAC_BITS)
    scale_shift = 3 * exponent
    return round_shift(coefficient, scale_shift) if scale_shift >= 0 else coefficient << (-scale_shift)


def acceleration(pos: list[list[int]]) -> list[list[int]]:
    acc = [[0, 0], [0, 0], [0, 0]]
    for a, b in ((0, 1), (0, 2), (1, 2)):
        dx = pos[b][0] - pos[a][0]
        dy = pos[b][1] - pos[a][1]
        radius_q = math.isqrt(dx * dx + dy * dy)
        coefficient = inv_r3_coefficient_q(radius_q)
        fx = round_shift(dx * coefficient, FRAC_BITS)
        fy = round_shift(dy * coefficient, FRAC_BITS)
        acc[a][0] += fx; acc[a][1] += fy
        acc[b][0] -= fx; acc[b][1] -= fy
    return acc


def failed(pos: list[list[int]]) -> str | None:
    for a, b in ((0, 1), (0, 2), (1, 2)):
        if abs(pos[b][0] - pos[a][0]) + abs(pos[b][1] - pos[a][1]) < COLLISION_L1_Q:
            return "collision"
    if any(abs(x) > ESCAPE_ABS_Q or abs(y) > ESCAPE_ABS_Q for x, y in pos):
        return "escape"
    return None


def invariants(pos: list[list[int]], vel: list[list[int]]) -> dict:
    p = [[x / ONE, y / ONE] for x, y in pos]
    v = [[x / ONE, y / ONE] for x, y in vel]
    kinetic = 0.5 * sum(vx * vx + vy * vy for vx, vy in v)
    potential = 0.0
    for a, b in ((0, 1), (0, 2), (1, 2)):
        potential -= (GM_Q / ONE) / math.dist(p[a], p[b])
    angular_momentum = sum(x * vy - y * vx for (x, y), (vx, vy) in zip(p, v))
    return {"energy": kinetic + potential, "kinetic": kinetic,
            "potential": potential, "angular_momentum": angular_momentum}


def replay_hifi(genes_raw: list[int] | tuple[int, ...], steps: int,
                max_points: int = 720, integrator: str = "leapfrog") -> dict:
    """Replay with Q32.32 state, smooth 1/r^3 LUT force, and symplectic update."""
    if integrator not in ("symplectic_euler", "leapfrog"):
        raise ValueError("integrator must be symplectic_euler or leapfrog")
    if steps <= 0:
        raise ValueError("steps must be positive")
    g = [q16_to_q32(item) for item in genes_raw]
    pos = [[g[0], g[1]], [g[4], g[5]], [-g[0] - g[4], -g[1] - g[5]]]
    vel = [[g[2], g[3]], [g[6], g[7]], [-g[2] - g[6], -g[3] - g[7]]]
    initial_invariants = invariants(pos, vel)
    stride = max(1, (steps + max_points - 1) // max_points)
    frames = [{"step": 0, "bodies": [[x / ONE, y / ONE] for x, y in pos]}]
    survived = 0
    failure = None

    for step in range(steps):
        acc = acceleration(pos)
        if integrator == "symplectic_euler":
            for body in range(3):
                vel[body][0] += round_shift(acc[body][0], DT_SHIFT)
                vel[body][1] += round_shift(acc[body][1], DT_SHIFT)
                pos[body][0] += round_shift(vel[body][0], DT_SHIFT)
                pos[body][1] += round_shift(vel[body][1], DT_SHIFT)
        else:
            for body in range(3):
                pos[body][0] += (round_shift(vel[body][0], DT_SHIFT) +
                                 round_shift(acc[body][0], 2 * DT_SHIFT + 1))
                pos[body][1] += (round_shift(vel[body][1], DT_SHIFT) +
                                 round_shift(acc[body][1], 2 * DT_SHIFT + 1))
            next_acc = acceleration(pos)
            for body in range(3):
                vel[body][0] += round_shift(acc[body][0] + next_acc[body][0], DT_SHIFT + 1)
                vel[body][1] += round_shift(acc[body][1] + next_acc[body][1], DT_SHIFT + 1)

        failure = failed(pos)
        if failure is None:
            survived += 1
        if (step + 1) % stride == 0 or step + 1 == steps or failure is not None:
            frames.append({"step": step + 1,
                           "bodies": [[x / ONE, y / ONE] for x, y in pos]})
        if failure is not None:
            break

    final_invariants = invariants(pos, vel)
    energy_scale = max(abs(initial_invariants["energy"]), 1e-30)
    momentum_delta = abs(final_invariants["angular_momentum"] - initial_invariants["angular_momentum"])
    invariant_drift = {
        "relative_energy": abs(final_invariants["energy"] - initial_invariants["energy"]) / energy_scale,
        "absolute_angular_momentum": momentum_delta,
        "relative_angular_momentum": (momentum_delta / abs(initial_invariants["angular_momentum"])
                                      if abs(initial_invariants["angular_momentum"]) > 1e-12 else None),
    }
    return {"frames": frames, "survived_steps": survived, "failure": failure,
            "requested_steps": steps, "integrator": integrator,
            "model": "Q32.32 smooth-log-LUT GM/r^3",
            "dt": 1.0 / (1 << DT_SHIFT), "gm": GM_Q / ONE,
            "lut_entries": len(INV_MANTISSA3_LUT),
            "initial_invariants": initial_invariants,
            "final_invariants": final_invariants,
            "invariant_drift": invariant_drift}


def q16_genes(values: list[float] | tuple[float, ...]) -> list[int]:
    return [round(value * 65536.0) & 0xFFFFFFFF for value in values]


def benchmark_hifi_scalar(genes_raw: list[int], steps: int, candidates: int) -> dict:
    """Measure the profile-5 fixed-point fitness workload without the GA."""
    started = time.perf_counter()
    checksum = 0
    for _ in range(candidates):
        checksum += replay_hifi(genes_raw, steps, max_points=1,
                                integrator="leapfrog")["survived_steps"]
    elapsed = max(time.perf_counter() - started, 1e-12)
    return {
        "name": "Python scalar HiFi",
        "kind": "profile-5 fixed-point fitness-only proxy",
        "elapsed_ms": elapsed * 1000,
        "candidate_evals": candidates,
        "candidate_evals_per_second": candidates / elapsed,
        "checksum": checksum,
        "model": "Q32.32 smooth-LUT cached Leapfrog",
    }


def benchmark_hifi_numpy(genes_raw: list[int], steps: int, candidates: int) -> dict:
    """Vectorized float64 proxy for the same smooth-force Leapfrog physics.

    It deliberately does not claim bit equivalence with the Q32.32/LUT RTL.
    Its role is to represent a runtime/vectorized software implementation at
    the same candidate count and requested time window.
    """
    try:
        import numpy as np
    except ImportError:
        return {"name": "NumPy batch HiFi", "kind": "fitness-only proxy",
                "available": False}

    g = np.asarray([signed_u32(item) / 65536.0 for item in genes_raw], dtype=np.float64)
    pos = np.empty((candidates, 3, 2), dtype=np.float64)
    vel = np.empty_like(pos)
    pos[:, 0, :] = g[[0, 1]]
    pos[:, 1, :] = g[[4, 5]]
    pos[:, 2, :] = -pos[:, 0, :] - pos[:, 1, :]
    vel[:, 0, :] = g[[2, 3]]
    vel[:, 1, :] = g[[6, 7]]
    vel[:, 2, :] = -vel[:, 0, :] - vel[:, 1, :]
    dt = 1.0 / 256.0
    gm = 1.0 / 256.0
    alive = np.ones(candidates, dtype=bool)
    survived = np.zeros(candidates, dtype=np.int64)

    def batch_acceleration(state):
        acc = np.zeros_like(state)
        for a, b in ((0, 1), (0, 2), (1, 2)):
            delta = state[:, b, :] - state[:, a, :]
            radius = np.maximum(np.sqrt(np.sum(delta * delta, axis=1)), 0.125)
            force = delta * (gm / (radius * radius * radius))[:, None]
            acc[:, a, :] += force
            acc[:, b, :] -= force
        return acc

    started = time.perf_counter()
    acc = batch_acceleration(pos)
    for _ in range(steps):
        pos += vel * dt + acc * (0.5 * dt * dt)
        next_acc = batch_acceleration(pos)
        vel += (acc + next_acc) * (0.5 * dt)
        acc = next_acc
        collision = np.zeros(candidates, dtype=bool)
        for a, b in ((0, 1), (0, 2), (1, 2)):
            delta = np.abs(pos[:, b, :] - pos[:, a, :])
            collision |= np.sum(delta, axis=1) < 0.125
        escape = np.any(np.abs(pos) > 8.0, axis=(1, 2))
        alive &= ~(collision | escape)
        survived += alive
        if not np.any(alive):
            break
    elapsed = max(time.perf_counter() - started, 1e-12)
    return {
        "name": "NumPy batch HiFi",
        "kind": "float64 smooth-force Leapfrog fitness-only proxy",
        "elapsed_ms": elapsed * 1000,
        "candidate_evals": candidates,
        "candidate_evals_per_second": candidates / elapsed,
        "checksum": int(np.sum(survived)),
        "model": "float64 GM/r^3 cached Leapfrog (not LUT-bit-exact)",
    }
