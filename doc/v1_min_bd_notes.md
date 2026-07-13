# v1.0 minimal PS/PL/AXI DMA integration notes

## Scope

This is the first board-connectable v1.0 path. It connects the already routed
`pure3_rf` fallback accelerator to Zynq PS through AXI DMA and a small AXI4-Lite
control/status register bank.

The restricted4 Heng-era RTL remains present, but it is **not** the default v1.0
block-design target yet because the previous implementation exceeded ZYNQ-7020
resources/timing. The minimal bitstream path therefore uses the pure3 fallback
profile that has already closed timing at 1 lane / 100 MHz.

## Hardware datapath

```text
PS DDR
  ^                          |
  | AXI HP0                  | AXI HP0
  |                          v
AXI DMA S2MM <--- M_AXIS  ga3b_v1_min_accel_top  S_AXIS <--- AXI DMA MM2S
                         |
                         | AXI4-Lite status/control
                         v
                      PS M_AXI_GP0
```

## Added files

- `rtl/top/ga3b_v1_min_accel_top.v`
  - Instantiates `ga3b_pure3_rf_accel_top`.
  - Exposes AXI4-Stream task/result ports for AXI DMA.
  - Adds a minimal AXI4-Lite register bank.
  - Provides `irq_out` for PS interrupt wiring.
- `rtl/top/filelist_v1_min.f`
- `vivado/scripts/create_v1_min_bd.tcl`
  - Creates PS7 + AXI DMA + interconnect + reset + interrupt concat + accelerator BD.
- `scripts/run/run_v1_min_bd.ps1`
  - Runs the Vivado BD creation script.
- `ps_app/common/ga3b_protocol.h`
- `ps_app/board_agent/standalone/ga3b_dma_smoke.c`
- `ps_app/board_agent/standalone/README.md`

## AXI4-Lite register map

Base address is assigned by Vivado; the script tries to reserve `0x43C00000` for
`ga3b_accel_0/S_AXI`.

| Offset | Name | Description |
|---:|---|---|
| `0x00` | CTRL | bit0 enable, bit1 irq_enable, bit2 clear_done W1P, bit3 soft_reset W1P |
| `0x04` | STATUS | bit0 done_latched, bit1 proto_error_latched, bit2 raw_done, bit3 irq_out, bit8 enabled |
| `0x08` | VERSION | `0x00010000` |
| `0x0c` | PROFILE | `0x00000003` = pure3 resource-fit fallback |
| `0x10` | RAW | bit0 raw_done, bit1 raw_proto_error |

## DMA packet profile

The PL stream wrapper currently uses the same compact smoke-test packet as the
existing pure3 RTL simulation:

```text
word0  magic = 0x47413342  // GA3B
word1  (GENE_COUNT << 2) | (POP << 8), currently 8 genes / 32 population
word2  max_gen
word3  steps_limit
word4  {crossover_rate_q16, mutation_rate_q16}
word5  seed0
word6  seed1
then   8 * {min_q16, max_q16, mutation_scale_q16}
```

Result packet:

```text
word0  magic = 0x52534C54  // RSLT
word1  status/current generation
word2  best_index
word3  best_fitness[31:0]
word4  best_fitness[63:32]
word5  best_heng_steps / survived steps
word6+ best chromosome genes
```

## Known limitations

1. This is a minimal endpoint, not the final Linux `board_agent` daemon.
2. The AXI4-Lite slave is a small single-beat register bank intended for PS
   driver accesses; task/result payloads still go through DMA.
3. The BD is board-agnostic. If the target board needs a vendor PS7 preset, apply
   that preset in Vivado after script generation.
4. The v1.0 default is pure3 fallback. Restricted4 end-to-end remains blocked by
   resource/timing work.