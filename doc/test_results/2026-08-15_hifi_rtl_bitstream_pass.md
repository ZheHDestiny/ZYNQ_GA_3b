# High-fidelity Pure3 RTL and bitstream comparison (2026-08-15)

Target: `xc7z020clg400-2`, complete PS7 + AXI DMA + GA3B PL design at 100 MHz.

## Functional correction

The original high-fidelity RTL failed after 20 steps because the descending
MSB priority encoder returned zero for some non-power-of-two `r^2` values near
the Q32 radix boundary.  The resulting exponent scaling grossly amplified the
force.  The encoder was replaced by an ascending overwrite priority encoder.

The normalization path was then split with an explicit `r2_stage` register.
This removed the 26-level `r2 sum -> priority encoder -> barrel shift` path.
The population RAM ports were split into separate clocked processes so Vivado
infers BRAM instead of dissolving the two memories into LUTs and flip-flops.

## Functional tests

| Test | Symplectic Euler | Cached Leapfrog |
|---|---:|---:|
| Fixed force vectors (`r=0.5, 1, 2, sqrt(2)` and non-boundary vectors) | PASS | shared datapath |
| Quantized figure-eight, requested steps | 100,000 | 100,000 |
| Survived steps | 100,000 | 100,000 |
| XSim result | PASS | PASS |

## OOC synthesis

| Variant | LUT | Registers | BRAM tile | DSP | WNS @ 100 MHz |
|---|---:|---:|---:|---:|---:|
| Smooth force + symplectic Euler | 7,919 (14.89%) | 4,878 (4.58%) | 4 (2.86%) | 9 (4.09%) | +1.137 ns |
| Smooth force + cached Leapfrog | 9,635 (18.11%) | 5,177 (4.87%) | 4 (2.86%) | 9 (4.09%) | +1.137 ns |

## Complete PS + DMA post-route

| Variant | LUT | Registers | BRAM tile | DSP | Setup WNS | Hold WNS | Bitstream |
|---|---:|---:|---:|---:|---:|---:|---|
| Smooth force + symplectic Euler | 10,644 (20.01%) | 8,651 (8.13%) | 6 (4.29%) | 9 (4.09%) | +0.204 ns | +0.046 ns | PASS |
| Smooth force + cached Leapfrog | 12,349 (23.21%) | 8,950 (8.41%) | 6 (4.29%) | 9 (4.09%) | +0.190 ns | +0.031 ns | PASS |

Both implementation runs completed with zero DRC errors, zero critical
warnings, and all user timing constraints met.  The reported DRC warnings are
primarily standard AXI FIFO messages plus BRAM/DSP methodology recommendations.

## Local artifacts

- `vivado/runs/v1_min_bd/variant_artifacts/hifi_symplectic/`
- `vivado/runs/v1_min_bd/variant_artifacts/hifi_leapfrog_cached/`

Bitstream SHA-256:

- Symplectic: `E68F4A0E25A6292B6035214EA3FFD16BB2DA725BE64E0044D9E585FF75924F5F`
- Leapfrog: `07B5C3358724D272CF10E009D729CD78B91120AC7873C566A039D49CCE1F35A1`

The generic `vivado/runs/v1_min_bd/artifacts/ga3b_v1_min.bit` currently points
to the final cached-Leapfrog implementation.  No SD card or board was changed
as part of this run.
