from __future__ import annotations

import math
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from ga3b_hifi_reference import (GM_Q, ONE, inv_r3_coefficient_q,
                                 q16_genes, replay_hifi)


def test_log_lut_inv_r3_accuracy_and_continuity():
    gm = GM_Q / ONE
    for radius in (0.125, 0.2, 0.5, 0.9999, 1.0, 1.0001, 2.0, 4.0, 8.0):
        radius_q = round(radius * ONE)
        actual = inv_r3_coefficient_q(radius_q) / ONE
        expected = gm / radius**3
        assert abs(actual - expected) / expected < 2e-5


def test_leapfrog_figure8_exceeds_one_hundred_thousand_steps():
    velocity_scale = math.sqrt(1 / 256)
    genes = q16_genes([
        0.97000436, -0.24308753,
        0.466203685 * velocity_scale, 0.43236573 * velocity_scale,
        -0.97000436, 0.24308753,
        0.466203685 * velocity_scale, 0.43236573 * velocity_scale,
    ])
    result = replay_hifi(genes, 100_001, max_points=64, integrator="leapfrog")
    assert result["failure"] is None
    assert result["survived_steps"] == 100_001
    assert result["invariant_drift"]["relative_energy"] < 1e-4
