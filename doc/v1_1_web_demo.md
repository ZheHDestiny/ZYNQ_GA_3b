# GA3B v1.1 Web 前端演示操作指南

## 1. 接线和启动条件

1. Micro SD 保持插在开发板中，卡根目录使用已验收的 `BOOT.BIN`。
2. `BOOT_CFG` 两个开关均为 `OFF`。
3. USB UART 连接电脑；本次枚举为 COM13。
4. JTAG 不需要连接；网线和 SSH 也不是该 bare-metal 演示的依赖。
5. 关闭 PuTTY、串口助手和其它 `ga3b_uart_client.py` 进程，确保 COM13 未被占用。

断电重新上电后，可先执行：

```powershell
cd F:\ZYNQ\ZYNQ_GA_3b
python -B ps_app\host_backend\ga3b_uart_client.py --port COM13 PING
```

预期：`GA3B_RSP OK PONG`。测试后该命令会自行退出，不会常驻占用串口。

## 2. 启动全栈演示

在仓库根目录执行：

```powershell
.\scripts\run\run_v1_web_demo.ps1 -Port COM13
```

脚本会启动 Flask 后端并打开 `http://127.0.0.1:8000/`。终端出现以下文字即表示 HTTP 服务已启动：

```text
GA3B_WEB_READY http://127.0.0.1:8000 UART=COM13
```

按 `Ctrl+C` 停止后端并释放 COM13。若不希望自动打开浏览器：

```powershell
.\scripts\run\run_v1_web_demo.ps1 -Port COM13 -NoBrowser
```

## 3. 前端功能测试

1. 顶栏应显示 `COM13 · FPGA 就绪`，板端状态为 `ONLINE`。
2. 点击“运行板端自检”，预期弹出 `SELFTEST PASS`。
3. 保持默认 `max_gen=2, steps=256`，点击“启动 FPGA 搜索”。
4. 预期显示端到端延时、fitness、存活步数、候选吞吐、8 个 Q16.16 初始条件和三颗太阳轨迹动画。
5. 可暂停、播放或拖动时间轴检查轨迹。
6. 点击“运行对比”运行 FPGA、Python scalar 与 NumPy 三类性能探针。

性能探针不继承搜索表单参数，而是使用固定的 `max_gen=8, steps=8192, hardware_runs=2` 和固定 seed；典型等待约 6 秒。这样既能让计算量超过 UART 固定开销并显示 FPGA 吞吐优势，也避免误把 32768/65536 步长轨迹请求用于软件代理而阻塞页面。

## 4. PowerShell API 测试

后端运行时，另开 PowerShell：

```powershell
Invoke-RestMethod http://127.0.0.1:8000/api/health

Invoke-RestMethod -Method Post http://127.0.0.1:8000/api/selftest `
  -ContentType application/json -Body '{}'

Invoke-RestMethod -Method Post http://127.0.0.1:8000/api/search `
  -ContentType application/json `
  -Body '{"max_gen":2,"steps":256,"mutation_q16":4096,"crossover_q16":49152,"seed0":305419896,"seed1":-2023406815}'
```

PowerShell 中不能直接输入 `GET /api/health`；应使用 `Invoke-RestMethod` 或 `curl.exe`。

## 5. 当前演示边界

- 开发板实际执行的是 Zynq-7020 可布线的 Pure3 resource-fit GA，不是 restricted4 行星版本。
- Canvas 是使用 FPGA 返回初态进行的 RTL 同规则 PC 重放，不是从 PL 逐拍流出的实时轨迹。
- FPGA 性能数据包含 DMA、UART 和完整 GA；Python/NumPy 是 fitness-only 代理，界面不会把它们包装成严格等价的加速比。

## 6. 模范解、结果保存和十进制参数

点击“选择模范解”，可在长时生存、安全擦掠、三星纠缠和近周期回归四套实测固定 seed 之间选择。“上板复现”会重新向 FPGA 发出任务。建议保持 `32768` 步并使用高亮窗口观看主要事件；点击轨迹右上角的 `HIGHLIGHT/FULL` 标签可切换完整轨迹。

每次搜索和自定义重放自动写入 `doc/test_results/ga3b_results.sqlite3`。可以通过 `GET /api/results` 获取历史摘要，再用 `GET /api/results/<id>` 读取完整结果。

界面参数均为十进制：位置和速度是 Q16.16 解码物理值；旁边的 Q16 整数等于物理值乘 65536；变异率/交叉率的实际概率为输入值除以 65536；seed 是有符号 32 位十进制，但送入 FPGA 时保持相同二进制位；fitness 是无符号 64 位十进制。
