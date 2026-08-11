# 2026-08-11 connectivity and UART board-agent report

## Connectivity check

| Interface | Result | Evidence |
|---|---|---|
| USB UART | Partial pass | CH340 enumerated as `COM13` and the port opened successfully at 115200 baud. It was previously `COM12`; a passive read and an active CR/LF probe both returned zero bytes, so the converter works but no running PS program/Linux console response was observed. |
| JTAG | Fail/not present | Windows connected-device listing contained CH340 only. XSCT connected to `hw_server`, but `targets` returned an empty list. No bitstream/ELF download was attempted. |
| SSH | Fail/not present | `zynq.local` did not resolve. The only active LAN neighbor, `192.168.3.35`, refused TCP port 22 and was not the running board Linux endpoint. |

These results indicate that the USB UART interface is present, while the board
is not currently visible through the external JTAG downloader and its Linux
image is not currently reachable over Ethernet. This is a physical/boot-state
blocker for a new functional board run, not an RTL test failure.

## Work completed locally

- Added persistent standalone `ga3b_uart_board_agent.c`.
- Added line commands `PING`, `INFO`, `STATUS`, `RESET`, `SELFTEST`, and `RUN`.
- Added PC-side PySerial transport `ga3b_uart_client.py`.
- Added deterministic Vitis BSP/GCC build script.
- ARM ELF build passed:

```text
GA3B_UART_AGENT_BUILD_PASS:
vitis_workspace/v1_min_standalone/ga3b_uart_board_agent/ga3b_uart_board_agent.elf
```

The ELF size is 226,984 bytes. A functional board run remains pending until
JTAG targets are visible again (or Linux/FPGA Manager is restored and a suitable
loading route is available).
