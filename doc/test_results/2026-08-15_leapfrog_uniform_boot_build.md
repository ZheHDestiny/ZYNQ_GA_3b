# Cached-Leapfrog + Uniform GA P1 Build

Date: 2026-08-15

## Scope

- High-fidelity cached-acceleration Leapfrog selected (`INTEGRATOR_MODE=1`).
- GA population initialization mapped uniformly over each complete bound.
- PS + AXI DMA + accelerator implemented for `xc7z020clg400-2` at 100 MHz.
- Standalone platform regenerated from the new XSA.
- Profile-aware UART/DMA agent and FSBL rebuilt.
- `BOOT.BIN` generated; no SD card was modified in this step.

## Verification

| Check | Result |
|---|---|
| Uniform initialization XSim | PASS; lower/upper quartile occupancy 4/7 for gene0 |
| Cached-Leapfrog two-task AXI XSim | PASS; 14/14 result words identical |
| Setup timing | WNS +0.539 ns, TNS 0 |
| Hold timing | WHS +0.057 ns, THS 0 |
| DRC | 0 errors |
| LUT | 12,304 / 53,200 (23.13%) |
| FF | 9,027 / 106,400 (8.48%) |
| BRAM tile | 6 / 140 (4.29%) |
| DSP | 13 / 220 (5.91%) |

## Deliverables and SHA-256

```text
BOOT.BIN
B6664CBF9B1DB8A11DC08E2D509E1B2B50CE94F8BBD5FCD3727DA900D6BBDD14

ga3b_v1_min.bit
3ED91ADE9C9903ED61ACD759F8A77DD196065B1AF3D36A31D79DBC41B2E7B260

ga3b_v1_min.xsa
31FB9C89F292A80A46DB33F6A7EDD69A140BB148D6AB215CA06110E08C596CBB

ga3b_uart_board_agent.elf
1A776994DAD81F1CC89FD25F4191732A40EC3F233593657C9287086287BF3FE3
```

`BOOT.BIN` path:

```text
vivado/runs/v1_min_bd/artifacts/sd_boot/BOOT.BIN
```

Board validation remains pending. Expected cold-boot profile is `0x00000005`.
