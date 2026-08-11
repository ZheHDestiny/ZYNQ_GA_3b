# 2026-08-11 v1-min repeatability acceptance

## RTL fixes

1. Added explicit wait states for the registered population-BRAM address/output
   latency in evaluation and reproduction reads.
2. Changed the task-magic transition to require `TVALID && TREADY`; the old
   implementation consumed a new magic while `TREADY` was still low after the
   previous result packet.
3. Updated the testbench to send two equal tasks without reset and compare all
   14 result words.

## RTL simulation

```text
TB_PASS pure3_rf_repeat words=14
fitness=00000001_00000010 steps=16
```

## Post-route implementation

```text
Device: xc7z020clg400-2
Clock: 100 MHz / 10 ns
WNS: +0.296 ns
TNS: 0.000 ns
LUT: 33,705 / 53,200 (63.36%)
FF: 24,528 / 106,400 (23.05%)
BRAM tile: 2 / 140 (1.43%)
DRC errors: 0
```

The LUT count changed from the stale cached build's 33,701 to 33,705, providing
an additional provenance check that the repaired custom RTL entered the routed
image.

## Board acceptance

```text
GA3B_UART_SOAK_PASS
port=COM13
iterations=100
elapsed_seconds=2.806238
average_seconds=0.028062
```

All 100 fixed-seed results were byte-for-byte identical. The accepted result:

```text
magic=0x52534C54 status=0x00000002 best_idx=0
fitness_hi=0x00000001 fitness_lo=0x00000010 steps=16
gene0=0xFFFE7F50 gene1=0xFFFE0000 gene2=0xFFFF0A63 gene3=0xFFFF0000
gene4=0xFFFE0000 gene5=0xFFFE5EA1 gene6=0xFFFF062A gene7=0xFFFF1455
```

Machine-readable output is in `doc/test_results/v1_uart_soak_latest.json`.

## SD boot image

`vivado/runs/v1_min_bd/artifacts/sd_boot/BOOT.BIN` was generated and parsed by
Bootgen. It contains exactly three images in this order:

1. `ga3b_v1_fsbl.elf` (bootloader),
2. `ga3b_v1_min.bit`,
3. `ga3b_uart_board_agent.elf` at load/entry address `0x00100000`.

Generation and structural parsing passed. Physical SD cold-boot validation is
still required before claiming boot-media acceptance.

SHA-256 provenance:

```text
BOOT.BIN                  2CE3FA0B60699378EEA1B624211FB0F60202237A3716961A2B42282334948DBE
ga3b_v1_min.bit           DF63A0D6F573928104AB2F4DDE3E098E9DCD07B0FC66F9A968BB301A7F346159
ga3b_v1_fsbl.elf          515A9EA4A3F342AD93E5C1022E3F3C5F669B35D2BC2255FABB9C1BC49A276E1F
ga3b_uart_board_agent.elf D6BE730E6ACB2A4E43F423A58EE35A9B6777C2371CCF975B5506D887BAFFF9E3
```
