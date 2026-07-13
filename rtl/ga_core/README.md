# GA core RTL v0.3

This directory contains the first implementation drop for the GA stable / heng-era initial-condition search core.

## Files

- `ga3b_ga_core.v`
  - Population initialization from gene bounds.
  - Two fitness-lane dispatch.
  - Best reduction.
  - Elite copy, parent selection, crossover, mutation, clamp.
  - `model_mode=1` for restricted4 heng-era search and `model_mode=0` for pure3 fallback.

- `ga3b_heng_era_fitness_lane_stub.v`
  - Despite the historical `_stub` filename, this file now contains a synthesizable v0.3 fitness evaluator.
  - Implements a Q16.16 2D sun-three integrator plus massless test-planet integrator.
  - Accumulates hardware-friendly heng-era metrics: collision/escape, dominant sun capture, habitable radius window, flux/tidal proxies, longest heng window.
  - Uses a simplified softened inverse-r2 force approximation; future math RTL should replace this with an invsqrt/LUT+Newton-Raphson force pipeline.

- `ga3b_rng_xorshift32.v`
  - Small xorshift32 PRNG module.

- `filelist.f`
  - RTL compile file list.

## Testbench

See `../tb/tb_ga3b_ga_core_smoke.v` for a smoke test that loads gene bounds, starts a small restricted4 GA run, and checks `done/error/best_fitness`.