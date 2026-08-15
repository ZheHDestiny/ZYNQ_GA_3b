# Profile-5 board and v1.1 full-stack validation

Date: 2026-08-15

## Board gate

- SD cold boot profile: `0x00000005`
- PING/INFO/SELFTEST: PASS
- UART/DMA deterministic soak: 100/100 PASS
- 100000-step request: protocol/accelerator execution PASS; selected candidate survived 3667 steps
- PC Profile-5 replay of that chromosome: 3667 steps, escape termination

The 100000-step request is not a 100000-step stable-solution result.

## Full-stack synchronization

- HTTP health, selftest, Profile-5 preset execution: PASS
- Long-survival preset exact genes/steps reproduction: PASS
- All four versioned templates: 32768/32768 and FPGA/PC step match
- Backend tests: 13 passed
- JavaScript syntax check: PASS

## Bounded performance probe

| Probe | Boundary | Time (ms) | Throughput (eval/s) |
|---|---|---:|---:|
| Zynq-7020 | complete GA + DMA + UART | 1090.30 | 264.15 |
| Python scalar | Profile-5 fixed-point/LUT fitness proxy | 69959.41 | 4.12 |
| NumPy batch | float64 smooth-force Leapfrog proxy | 1807.17 | 159.37 |

The FPGA is about 64.2x the scalar proxy and 1.66x the NumPy proxy for this
bounded workload. These are not algorithm-identical paths; see the API note.
