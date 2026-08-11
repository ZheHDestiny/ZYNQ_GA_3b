# GA3B v1.1 HTTP/Web 全栈实板验收

- 日期：2026-08-11
- 开发板：正点原子领航者 V2，Zynq-7020
- 启动：已验收的 SD bare-metal `BOOT.BIN`
- 板端链路：UART -> PS board_agent -> AXI DMA -> Pure3 PL
- PC 服务：Flask，同源静态 Web

## 自动测试

```text
pytest: 3 passed
JavaScript syntax: PASS
GET /api/health: PASS
POST /api/search: PASS
POST /api/performance/probe: PASS
```

健康探针识别 `port=COM13`、`version=0x00010000`、`profile=0x00000003`、`accelerator_ready=true`。

256 步搜索：

```text
elapsed_ms=31.5829
survived_steps=256
trajectory_frames=257
trajectory_failure=None
```

## 性能探针

`max_gen=2` 对应 RTL 的 `32 * (2 + 1) = 96` 次候选评估。

| steps | 探针 | 边界 | 平均延时 | 吞吐 |
|---:|---|---|---:|---:|
| 16 | Zynq-7020 FPGA | 完整 GA + DMA + UART | 28.33 ms | 3389 eval/s |
| 16 | Python scalar | fitness-only 代理 | 25.52 ms | 3761 eval/s |
| 16 | NumPy batch | 向量化 fitness-only 代理 | 4.63 ms | 20724 eval/s |
| 256 | Zynq-7020 FPGA | 完整 GA + DMA + UART | 31.11 ms | 3086 eval/s |
| 256 | Python scalar | fitness-only 代理 | 304.15 ms | 316 eval/s |
| 256 | NumPy batch | 向量化 fitness-only 代理 | 44.78 ms | 2144 eval/s |
| 1024 | Zynq-7020 FPGA | 完整 GA + DMA + UART | 36.23 ms | 2649 eval/s |
| 1024 | Python scalar | fitness-only 代理 | 1180.07 ms | 81 eval/s |
| 1024 | NumPy batch | 向量化 fitness-only 代理 | 192.87 ms | 498 eval/s |

原始 JSON：`v1_1_http_board_e2e.json`、`v1_1_search_256.json`、`v1_1_performance_probe_256.json`、`v1_1_performance_probe_1024.json`。

这些数据确认较长积分窗口能摊薄 UART 固定开销；它们不构成相对算法等价 CPU/GPU 实现的最终性能结论。
