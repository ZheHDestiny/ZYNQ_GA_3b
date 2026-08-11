# v1 SD 物理冷启动与 UART 连续任务验收

- 日期：2026-08-11
- 开发板：正点原子领航者（V2）ZYNQ-7020
- 启动方式：Micro SD，`BOOT_CFG=OFF/OFF`，断电后重新上电
- JTAG：不参与启动或测试
- 通信：COM13，115200-8-N-1
- 镜像：`vivado/runs/v1_min_bd/artifacts/sd_boot/BOOT.BIN`

## 测试命令

```powershell
python -B ga3b_uart_soak.py `
  --port COM13 `
  --count 100 `
  --report ..\..\doc\test_results\v1_sd_boot_uart_soak.json
```

## 结果

```text
GA3B_UART_SOAK_PASS
iterations=100
elapsed_seconds=2.760201
average_seconds=0.027602
magic=0x52534C54
status=0x00000002
best_idx=0
fitness=0x00000001_00000010
steps=16
gene0..7=FFFE7F50 FFFE0000 FFFF0A63 FFFF0000 FFFE0000 FFFE5EA1 FFFF062A FFFF1455
```

100 次结果一致，未出现 DMA timeout、UART 协议错误或结果漂移。机器可读原始报告见 `v1_sd_boot_uart_soak.json`。

## 验收结论

`BOOT.BIN` 已通过真实 SD 物理冷启动，并建立了 PC UART 到 PS board_agent、AXI DMA、pure3 PL 再返回 PC 的可重复数据闭环。该结果满足开发 HTTP 后端与 Web 前端的硬件/传输基础条件，但不等同于 HTTP API 和 Web UI 已实现。
