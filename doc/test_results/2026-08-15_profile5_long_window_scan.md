# Profile-5 long-window board scan

Date: 2026-08-15

## Why the first 100000-step request stopped at 3667

The first request used `max_gen=1`, mutation `4096`, crossover `49152`, and the
default seeds. It evaluated only 64 candidates. The returned candidate and the
Profile-5 PC replay both escaped at step 3667, so this was search under-sampling,
not a replay or integrator disagreement.

## Hyperparameter/seed scan

Using the previously qualified long-window seed pair
`2995967490 / 1001641397`:

| max_gen | mutation | crossover | requested | survived | termination |
|---:|---:|---:|---:|---:|---|
| 1 | 4096 | 49152 | 100000 | 3667 | escape (original default seeds) |
| 8 | 4096 | 49152 | 100000 | 11356 | escape |
| 16 | 12288 | 53248 | 100000 | 50811 | escape |
| 32 | 20480 | 57344 | 100000 | 100000 | full window |
| 64 | 20480 | 57344 | 100000 | 100000 | full window |

All four qualified seed pairs at `max_gen=64`, mutation `20480`, crossover
`57344` survived the complete 100000 and 131072-step windows with exact FPGA/PC
survived-step agreement.

The best chromosome was stable across the longer requests:

```text
Q16 genes: [-244, 40654, 3309, -5090, 20358, 65850, -397, 4024]
decoded:   [-0.0037231445, 0.6203308105, 0.0504913330, -0.0776672363,
             0.3106384277, 1.0047912598, -0.0060577393, 0.0614013672]
```

Confirmed complete windows: 262144, 524288, and 1048576 steps. At 1048576
steps the PC replay reported no failure, relative energy drift `1.27e-7`,
minimum pair distance `0.314`, compact fraction `1.0`, 68 close passes,
411.6 radians winding, and 215 angular-order exchanges.

## Practical ceiling encountered

A 2097152-step request did not return a physics result. The board agent returned
`code=-12`, which maps to exhaustion of `GA3B_DMA_TIMEOUT=200000000` while the
DMA/core was still busy. Therefore 1048576 is the maximum confirmed window in
this scan, not a demonstrated physical lifetime limit. The two-million-step
failure is an agent timeout and leaves the DMA channel busy; a physical cold
boot is required before the next DMA test.
