# ZYNQ PS+PL 遗传算法三体初始条件搜索加速器技术规格报告

> **项目版本**：Profile-5 Pure3 实板实现
>
> **目标平台**：正点原子领航者 V2，Zynq-7020（`xc7z020clg400-2`）
>
> **状态**：已完成 SD 冷启动、PS/DMA/PL/UART、PC HTTP 后端和 Web 动画闭环；本报告以当前可部署的 Pure3 Profile-5 为准。
>
> **更新依据**：当前 RTL、PS/PL 协议、Host Backend、`doc/test_results/` 和实板验收记录。

---

## 1. 摘要与项目边界

本项目实现一个面向三体初始条件空间的遗传搜索系统。用户从浏览器提交搜索参数，PC 侧 Flask 服务通过 USB UART 将任务交给 Zynq PS 的裸机 `board_agent`；PS 借助 AXI DMA 向 PL 下发任务；PL 在 FPGA 内部完成种群初始化、候选轨道积分、存活 fitness 计算、多代选择/交叉/变异和最优染色体归约；结果经相反路径返回，由 PC 用同一 Profile-5 数值规则重放并在网页展示轨迹与可解释指标。

项目的灵感来自“通过搜索初始条件发现特殊三体运动”的设想。它是有限精度、有限积分窗口的工程探索系统，不构成严格的天体力学稳定性证明、精确周期解证明或现实天文系统预测。

### 1.1 当前可部署范围

| 项目 | 当前状态 |
|---|---|
| 二维等质量纯三体（Pure3） | 已在 Zynq-7020 Profile-5 上部署并验收 |
| 8 个 Q16.16 初始条件基因 | 已部署 |
| Q32.32 状态、平滑力 LUT、缓存加速度 Leapfrog | 已部署 |
| 32 个体硬件 GA | 已部署 |
| PS UART/DMA、SD 冷启动裸机 agent | 已部署 |
| Flask API、PC 同规则重放、Web 动画 | 已部署 |
| 多起点 FPGA 生存搜索 + PC 多目标重排 | 已部署 |
| 受限四体“恒纪元”（三太阳+测试行星）RTL | 原型/后续目标，不是当前验收 bitstream |
| 四套独立硬件 fitness | 未部署；PL 当前仍是存活 fitness |

### 1.2 不应夸大的结论

- “长时生存”仅表示在指定步数内未碰撞或逃逸，**不表示无限稳定**。
- “近周期回归”是有限窗口构型误差，允许等质量天体标签交换，**不表示严格周期轨道**。
- 前端轨迹是 PC 用 FPGA 返回染色体进行的 Profile-5 重放，**不是从 PL 实时逐步上传的状态流**。
- 性能中的 Python/NumPy 项是 fitness-only 代理，**不能与含完整 GA、DMA、UART 的硬件测量宣传为严格等价的通用加速比**。

---

## 2. 系统架构与部署拓扑

### 2.1 三层协同结构

```text
┌─────────────────────────────────────────────────────────────────────┐
│ PC / Windows                                                        │
│  Browser UI ──HTTP──> Flask Backend                                 │
│  参数校验、结果 SQLite、Profile-5 重放、轨迹分类和 Canvas 动画        │
└───────────────────────────┬─────────────────────────────────────────┘
                            │ USB UART，115200 baud，文本命令/响应
┌───────────────────────────▼─────────────────────────────────────────┐
│ Zynq PS：standalone board_agent                                     │
│  UART 命令解析、DMA buffer、cache 维护、AXI DMA 启动和超时处理        │
└───────────────────────────┬─────────────────────────────────────────┘
                            │ AXI DMA MM2S / S2MM，AXI-Stream
┌───────────────────────────▼─────────────────────────────────────────┐
│ Zynq PL：Profile-5 Pure3 accelerator，100 MHz                       │
│  任务解析、GA 种群、Q32.32 Leapfrog fitness lanes、最优结果输出       │
└─────────────────────────────────────────────────────────────────────┘
```

日常演示从 Micro SD 冷启动 `BOOT.BIN`，其中包含 FSBL、已验收 bitstream 和 standalone `board_agent` ELF。JTAG 是开发/恢复工具，不是演示必要条件；当前演示也不依赖以太网或 SSH。

### 2.2 责任划分

| 层级 | 职责 |
|---|---|
| Browser | 参数输入、运行状态、结果表、Canvas 轨迹与播放控制 |
| Flask Host Backend | HTTP API、串口独占、参数限制、UART 调度、结果持久化、PC 重放/指标/重排 |
| PS `board_agent` | UART 协议、DMA 缓冲区和 cache 一致性、加速器启动、结果回传 |
| PL | 人群生成、积分、fitness、选择、交叉、变异、精英保留和最优个体输出 |

PC 不逐代参与 GA。一次任务下发后，PL 完整运行该任务的种群演化；PC 在结果返回后才进行轨迹重放和展示分类。

---

## 3. 物理模型与数值规则

### 3.1 受约束二维等质量纯三体模型

当前 Profile-5 是三颗等质量天体的二维系统。输入只编码天体 α 和 β 的位置、速度；天体 γ 由质心与总动量约束推导：

```text
r₂ = −r₀ − r₁
v₂ = −v₀ − v₁
```

完整输入染色体为：

```text
[x0, y0, vx0, vy0, x1, y1, vx1, vy1]
```

这 8 个值均以有符号 Q16.16 传输；内部积分状态提升为 Q32.32。约束将总质心及总动量锁定为零，避免搜索退化为整体移动。

### 3.2 归一化模型与边界

当前物理/实现参数：

| 参数 | 值 | 说明 |
|---|---:|---|
| 质量 | 三体等质量 | Profile-5 固定模型 |
| `GM` | `1/256` | 归一化引力参数 |
| `dt` | `1/256` | 积分步长 |
| 力模型 | 平滑 `GM/r³` LUT | 1025 个插值端点 |
| 碰撞 | L1 两体距离 `< 0.125` | 提前终止 |
| 逃逸 | 任一位置分量 `abs(value) > 8.0` | 提前终止 |
| 输入基因 | Q16.16，32 位 | 浏览器/协议输入 |
| 内部状态 | Q32.32，64 位 | 积分状态 |

平滑/LUT 力模型是为了固定点资源、可预测时序和硬件一致性而作的工程近似，不能与无软化、高精度浮点 Newton 三体数值解混为一谈。

### 3.3 缓存加速度 Leapfrog

Profile-5 使用缓存加速度 Leapfrog（kick-drift-kick 类型）以改善长期积分守恒特性：

```text
v(t + dt/2) = v(t) + a(t) · dt/2
r(t + dt)   = r(t) + v(t + dt/2) · dt
a(t + dt)   = F(r(t + dt))
v(t + dt)   = v(t + dt/2) + a(t + dt) · dt/2
```

加速度来自三对两体相互作用的平滑逆三次项。相对于早期显式欧拉实现，Leapfrog 减少长期数值能量漂移，是当前 100 MHz 可部署路线的关键数值升级。

### 3.4 有限窗口物理标签

硬件对每个候选以生存步数为主要依据；PC 重放从轨迹中统计附加指标：

| 标签 | PC 解释性判据概述 |
|---|---|
| 长时生存 | 窗口内未碰撞、未逃逸 |
| 安全擦掠 | 生存前提下存在多次安全近心事件 |
| 三星纠缠 | 绕质心角度、角序交换、紧凑驻留与径向漂移的综合指标 |
| 近周期回归 | 允许标签交换的末态/初态构型回归误差 |

除长时生存外，当前流程是多次 FPGA 生存搜索后由 PC 重放计算指标并重排候选。返回结果会包含 `profile_match`，当最优候选不满足所选标签时，前端应明确告警。

---

## 4. 遗传算法设计

### 4.1 种群和确定性

当前默认种群大小为 32。候选评估数量为：

```text
candidate_evals = 32 × (max_gen + 1)
```

初代第 0 个体为各基因区间中点，其他个体在完整 `[min, max)` 范围内由全 32 位 PRNG 均匀生成。硬件 RNG 初态为：

```text
rng_init = seed0 XOR swap16(seed1)
```

Web/API 任务的第一个多起点候选严格采用用户 seed；附加候选使用确定性的派生 seed。因此相同 build、任务参数和 seed 应给出位一致的结果。

### 4.2 演化算子

| 算子 | 当前实现 |
|---|---|
| Fitness | 生存优先，碰撞/逃逸提前终止 |
| 选择 | 硬件随机选择/比较，保留最优个体 |
| 交叉 | 基于 Q0.16 交叉概率逐基因选择父本 |
| 变异 | 基于 Q0.16 变异概率的定点扰动，并 clamp 至基因边界 |
| 精英保留 | 每代保留当前最优染色体 |
| 双缓冲 | 种群 A/B bank 轮换，避免繁殖时覆盖当前代 |

浏览器以百分数 `0.00%..100.00%` 输入概率，后端编码规则为：

```text
q16 = round(percent × 65536 / 100)
100% → 65535
```

直接 API 仍兼容 `mutation_q16` 与 `crossover_q16`。

### 4.3 参数与服务限制

HTTP 服务接受 `max_gen=1..256`、`steps=1..131072`，并根据经实板校准的保守模型拒绝估算超过 600 秒的同步请求。推荐长窗口搜索参数之一为：

```text
max_gen = 32
mutation = 31.25% (20480)
crossover = 87.50% (57344)
seed0 = 2995967490
seed1 = 1001641397
```

在 100000 步消融中，`max_gen=32` 和 64 均找到存活完整窗口的候选；8 代和 16 代分别只达到 11356 与 50811 步，说明该搜索问题对演化深度和参数具有显著敏感性。

---

## 5. PL RTL 结构

### 5.1 Profile-5 相关目录

```text
rtl/pure3_core/
├── ga3b_pure3_hifi_fitness_lane.v    # Profile-5 fitness lane
├── ga3b_pure3_hifi_force_pair.v      # 两体力项
├── ga3b_pure3_inv_r3_lut.v           # 平滑逆三次 LUT
├── ga3b_pure3_rf_accel_top.v          # Pure3 AXI-Stream 加速器顶层
├── ga3b_pure3_rf_fitness_lane.v       # Resource-fit lane
└── ga3b_pure3_rf_ga_core.v            # Pure3 GA 核心
```

历史/原型模块位于 `rtl/ga_core/`，包括 `ga3b_heng_era_fitness_lane.v`、`ga3b_test_planet_integrator.v` 与通用 GA 核心；它们用于受限四体恒纪元方向的探索，不应与当前 Profile-5 已验收硬件混淆。

### 5.2 加速器数据路径

```text
AXI-Stream task input
  → task parser / 参数寄存器
  → population initialization
  → population A/B BRAM
  → fitness scheduler
  → Pure3 HiFi fitness lane
       → Q32.32 状态
       → r^-3 LUT / force pairs
       → cached-acceleration Leapfrog
       → survived_steps / fitness
  → reduction / elite / selection / crossover / mutation
  → AXI-Stream result output
```

核心时钟目标为 100 MHz。任务局部状态必须在每次启动时重新初始化，包括 RNG、代数/个体索引、best fitness、best chromosome、错误与流水线有效位；结果不得依赖上一任务的 RAM 内容、回压历史或 seed。

### 5.3 AXI-Stream 契约

`doc/design_contract.md` 定义的约束适用于已实现硬件：

1. 仅在时钟上升沿的 `TVALID && TREADY` 时发生传输。
2. 回压期间，生产端必须保持 `TDATA`、`TLAST`、`TVALID` 不变。
3. `TLAST` 仅在任务/结果最后一个 word 置位。
4. 同步 BRAM 的读延迟必须由 FSM 显式处理，不能在同周期消费刚发出的地址。
5. 一个结果包完成后，下一任务无需重新配置 FPGA 或重启 PS。
6. 同 seed、同任务、同 build 应产生位一致 Pure3 结果；板端持续 agent 验收要求至少 100 个任务全部一致且无协议错误。

### 5.4 资源与时序

Profile-5 已验收 100 MHz 实现的资源结果：

| 资源 | 使用 / 可用 | 占比 |
|---|---:|---:|
| LUT | 12304 / 53200 | 23.13% |
| FF | 9027 / 106400 | 8.48% |
| BRAM | 6 / 140 | 4.29% |
| DSP | 13 / 220 | 5.91% |
| Setup WNS / TNS | +0.539 ns / 0 | 时序通过 |
| Hold WHS / THS | +0.057 ns / 0 | 时序通过 |
| DRC errors | 0 | 通过 |

这组结果说明当前单/低并行度的 Profile-5 Pure3 路线在 Zynq-7020 上保有较大资源余量；它不代表更复杂的受限四体多目标 fitness 同样可以无修改地部署。

---

## 6. PS、DMA 和 UART 通信

### 6.1 PS/PL 数据路径

`board_agent` 负责：

1. 接收 UART `RUN` 命令并校验范围；
2. 写入任务 buffer；
3. 对输入 buffer 执行 cache flush、对输出 buffer 执行 invalidate；
4. 先启动 AXI DMA S2MM，再启动 MM2S；
5. 等待加速器/DMA 完成或超时；
6. 解析结果并通过 UART 返回 `GA3B_RSP` 行。

启动 S2MM 在 MM2S 之前，保证 PL 输出不会因接收端未就绪而丢失。UART 是当前板端外部控制通道；DMA 负责 PS DDR 与 PL AXI-Stream 之间的数据搬运。

### 6.2 操作命令

常用板端命令：

```text
PING
INFO
SELFTEST
RUN <max_gen> <steps> <mutation_q16> <crossover_q16> <seed0> <seed1>
```

Flask 服务通过 `Ga3bUartClient` 串行化对 COM 端口的访问，避免多个 HTTP 请求/串口工具并发争用。

### 6.3 任务与结果语义

输入包含代数、步数、两个 Q0.16 概率和两个 32 位 seed；输出包含状态/错误、最优 fitness、存活步数及 8 个最优 Q16.16 基因。主机随后使用这些原始基因进行同规则重放。

`INFO` 应显示协议版本和当前 profile。Host Backend 只把 Profile 5（`pure3_hifi_leapfrog_cached`）认定为模型一致的 ready 状态，避免旧 profile 被误展示为当前实现。

---

## 7. PC HTTP、重放与 Web 前端

### 7.1 Host Backend

`ps_app/host_backend/` 中的 Flask 服务拥有串口并提供：

```text
GET  /api/health
GET  /api/capabilities
POST /api/selftest
POST /api/estimate
POST /api/search
POST /api/custom-replay
POST /api/performance/probe
GET  /api/presets
POST /api/presets/<id>/run
GET  /api/results
```

搜索结果和自定义重放写入本地 SQLite：`doc/test_results/ga3b_results.sqlite3`。数据库是运行产物，被 Git 忽略；版本化的预设在 `ps_app/host_backend/presets/trajectory_templates.json`。

### 7.2 同规则重放

Host 端 `ga3b_hifi_reference.py` 以 Profile-5 的 Q32.32、平滑 LUT 和 Leapfrog 规则重放 FPGA 返回的染色体。结果响应包含：

```text
replay_consistency.hardware_survived_steps
replay_consistency.pc_survived_steps
replay_consistency.steps_match
```

固定模板验收要求硬件/PC 生存步数一致。由于轨迹没有从 PL 流式回传，Canvas 始终应标识为“由返回染色体重放”。

### 7.3 Web 功能

`web/templates/index.html` 和 `web/static/` 提供：

- 四种目标选择、搜索参数和复现实验 seed；
- 实板自检、性能遥测、系统 profile 信息；
- 固定模板实板复现；
- 事件高亮窗口/全轨迹切换、暂停、时间轴与 0.25×–8× 播放；
- 自定义初态的 PC Profile-5 重放；
- 结果与物理指标显示。

自定义初态受前后端共同限制：位置在 `[-2, 2]`、速度在 `[-1, 1]`、初始 L1 距离至少为 `0.125`、步数不超过 `131072`。当前协议不支持把用户自定义的单一染色体直接注入 PL lane，因此该路径必须清楚标为 `PC PROFILE-5 LEAPFROG REPLAY`。

---

## 8. 构建、部署和运行

### 8.1 主要工程位置

| 路径 | 作用 |
|---|---|
| `rtl/pure3_core/` | 当前 Pure3 Profile-5 RTL |
| `rtl/ga_core/` | 通用 GA/受限四体原型 RTL |
| `rtl/top/`、`rtl/axi/` | 顶层和接口封装 |
| `rtl/tb/` | 仿真 testbench/filelist |
| `vivado/scripts/` | BD、综合、实现、导出 Tcl |
| `scripts/run/` | PowerShell 构建、上板、Web 演示脚本 |
| `ps_app/board_agent/standalone/` | 裸机 PS agent |
| `ps_app/common/` | 协议头文件 |
| `ps_app/host_backend/` | Flask、UART、参考模型、测试 |
| `web/` | 浏览器前端 |
| `doc/test_results/` | 可提交的 JSON/Markdown 验收摘要 |

### 8.2 Web 演示

将 `COM13` 替换为实际枚举端口：

```powershell
cd F:\ZYNQ\ZYNQ_GA_3b
python -B ps_app\host_backend\ga3b_uart_client.py --port COM13 PING
.\scripts\run\run_v1_web_demo.ps1 -Port COM13
```

启动脚本会开启 Flask 并打开 `http://127.0.0.1:8000/`。应先关闭 PuTTY、串口助手等任何占用 COM 端口的程序。详细演示操作见 [v1_1_web_demo.md](v1_1_web_demo.md)。

### 8.3 本地回归

```powershell
python -B -m pytest ps_app\host_backend\tests -q
node --check web\static\app.js
```

已记录的后端/前端回归结果是 `14 passed` 和 JavaScript syntax PASS。构建有效性还要求：所有 custom RTL 早于对应 DCP/顶层 checkpoint、模块修改后失效相关 Vivado IP cache、100 MHz 后路由 `WNS >= 0`/`TNS = 0`、DRC 无错误。

Bitstream、XSA、BOOT.BIN、Vivado/Vitis 中间目录、ELF、SQLite、缓存和日志是本地生成物，不应强制加入 Git；换机时通过已提交的 Tcl/PowerShell 脚本重新生成。

---

## 9. 实板验收与效果

### 9.1 冷启动与稳定性

物理 SD 冷启动验收记录：

```text
PING: PONG
INFO: protocol=1 version=0x00010000 profile=0x00000005
SELFTEST: PASS
UART/DMA soak: 100/100 PASS
```

四个 Profile-5 固定模板已在实板完成 32768 步，均满足：

1. FPGA 返回染色体与版本化模板一致；
2. FPGA `survived_steps` 与 PC 重放完全一致；
3. 前端可分别展示长时生存、安全擦掠、三星纠缠和近周期回归的有限窗口特征。

### 9.2 长窗口候选

推荐 seed 为：

```text
seed0 = 2995967490
seed1 = 1001641397
```

一个高质量候选的 Q16 整数染色体：

```text
[-244, 40654, 3309, -5090, 20358, 65850, -397, 4024]
```

对应十进制初值：

```text
[-0.0037231445, 0.6203308105, 0.0504913330, -0.0776672363,
  0.3106384277, 1.0047912598, -0.0060577393, 0.0614013672]
```

该候选已在 FPGA 和 PC 通过 100000、131072、262144、524288 和 1048576 步。百万步 PC 指标为：

| 指标 | 结果 |
|---|---:|
| relative energy drift | `1.27e-7` |
| minimum pair distance | `0.314` |
| compact fraction | `100%` |
| close passes | `68` |
| winding | `411.6 rad` |
| angular-order exchanges | `215` |

这些指标只描述该固定近似模型与有限精度重放中的行为。独立高精度浮点/多精度复核仍是未来工作。

### 9.3 性能探针

标准探针工作负载：`max_gen=8`、`steps=8192`、`hardware_candidate_evals=288`、两次硬件运行。

| 路径 | 类型 | 耗时 | 吞吐 |
|---|---|---:|---:|
| Zynq-7020 FPGA | 完整 GA + DMA + UART | 1090.30 ms | 264.15 eval/s |
| Python scalar HiFi | Profile-5 定点 fitness-only 代理 | 69959.41 ms | 4.12 eval/s |
| NumPy batch HiFi | float64 fitness-only 代理 | 1807.17 ms | 159.37 eval/s |

硬件与 Python 标量代理的吞吐比约为 64.2×；与 NumPy 代理的比约为 1.66×。比较边界很重要：FPGA 结果包含完整 GA、DMA 和 UART，Python/NumPy 不包含 GA 选择/繁殖或传输；NumPy 也不是 LUT 位精确模型。因此它们是诊断性基准，而不是算法等价的通用加速宣称。

---

## 10. 已知问题和后续路线图

1. **长窗口 DMA 超时**：2,097,152 步请求可耗尽 `GA3B_DMA_TIMEOUT=200000000`；此后 DMA 可能保持 Busy，软件 `RESET` 无法恢复，需要物理断电冷启动。应改为定时器/中断驱动的可配置超时，并在超时时同时复位 DMA。
2. **同步 HTTP 上限**：当前 Web 限制为 131072 步，以避免长任务独占 HTTP 请求。应把长窗口搜索改为异步 job，提供轮询/结果查询与取消能力。
3. **分层 fitness**：可采用短窗口硬件淘汰、长窗口晋级及 PC/高精度复核，降低稀有长稳候选的搜索成本。
4. **硬件多目标**：安全擦掠、纠缠、回归目前在 PC 重排。后续可按资源/时序预算将部分度量逐步下沉到 PL，而非把它们伪称为已实现能力。
5. **自定义状态注入**：扩展协议使任意用户染色体可直接进入 PL lane，消除当前 custom replay 的 PC-only 边界。
6. **受限四体恒纪元**：三太阳+质量可忽略测试行星仍是与“恒纪元”设想更接近的科学方向。重新启动该路线前，需独立进行 Zynq-7020 资源、时序和数值验证，不能替代当前 Pure3 交付描述。
7. **科学复核**：对长窗口候选进行独立高精度浮点或多精度积分，区分有限精度周期锁定与具有物理意义的长期稳定/准周期结构。

---

## 11. Git 与远程仓库状态

仓库远程为：

```text
origin  https://github.com/ZheHDestiny/ZYNQ_GA_3b.git
branch  main
```

本文档更新时，`git ls-remote origin refs/heads/main` 返回的远程 `main` 与本地 `HEAD` 均为 `90f911b0b375a5f914fb1cd33a30f2ba5904c363`。这说明未观察到远程领先提交；但工作树存在未提交的开发改动，提交前应运行：

```powershell
git status --short
git diff --check
git status --ignored --short
```

不要用 `git add -f` 将 Vivado/Vitis 生成物、bitstream、BOOT.BIN、SQLite 或本地工具副本强制纳入仓库。
