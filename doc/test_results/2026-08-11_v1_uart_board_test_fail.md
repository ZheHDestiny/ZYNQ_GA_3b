# 2026-08-11 v1 UART board-agent functional test

## Result

**FAIL — fixed-seed result drift on the second `SELFTEST`.**

This was the single functional board-test run for this iteration. Per the
project simulation/board-test iteration policy, no RTL or board-agent fix was
made and no second functional run was started in the same conversation.

## Stages that passed

```text
PYTHON_SYNTAX_PASS
GA3B_UART_AGENT_BUILD_PASS
GA3B_XSDB_CONNECTED
GA3B_CPU0_STOPPED
GA3B_BITSTREAM_PROGRAMMED
GA3B_PS7_INITIALIZED
GA3B_UART_AGENT_DOWNLOADED
GA3B_CPU0_RUNNING
GA3B_SOAK_PROGRESS 1/100
```

Therefore JTAG programming, PS7 initialization, ELF download, UART `PING`,
UART `INFO`, the first DMA `SELFTEST`, and the first complete 14-word result
transfer all worked.

## Failure evidence

The fitness and step count remained equal, but the returned chromosome changed
between identical fixed-seed requests:

```text
iteration 1:
fitness_hi=0x00000001 fitness_lo=0x00000010 steps=16
gene0=0xFFFF0000 gene1=0xFFFF0A09 gene2=0x00000000 gene3=0xFFFE7F50
gene4=0xFFFE0000 gene5=0xFFFF0A63 gene6=0xFFFF0000 gene7=0xFFFE0000

iteration 2:
fitness_hi=0x00000001 fitness_lo=0x00000010 steps=16
gene0=0xFFFF0000 gene1=0xFFFF0A09 gene2=0xFFFF0000 gene3=0x00000000
gene4=0x00000000 gene5=0x00000000 gene6=0x00000000 gene7=0x00000000
```

The 100-run acceptance test stopped at iteration 2. A bootable SD `BOOT.BIN`
was deliberately not produced from this image, because doing so would package
a version that has not passed repeatability validation.

## Initial fault boundary

The stable result header/fitness combined with changing genes narrows the likely
fault to repeated-task state reset, best-chromosome storage/update, or result
packet serialization. It does not currently look like a JTAG, UART framing, or
basic DMA reachability failure. The next iteration should add a focused
two-consecutive-task RTL testbench and inspect reset/handshake behavior before
another board run.
