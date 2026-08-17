# ZYNQ_GA_3b：Zynq 三体初始条件遗传搜索加速器

> 面向《三体》中“在初始条件空间寻找特殊三体运动”这一设想的 PS+PL 协同实验项目。

本项目在正点原子领航者 V2（Zynq-7020，`xc7z020clg400-2`）上实现三体问题初始条件的遗传搜索、实板 UART/DMA 加速和 Web 轨迹展示。当前可部署主线是 **Profile-5 Pure3**：在三颗等质量天体、质心与总动量为零的约束下，搜索具有长时生存、近掠、纠缠或近周期回归特征的二维初始条件。

完整技术细节见 [doc/spec.md](doc/spec.md)，实板 Web 演示步骤见 [doc/v1_1_web_demo.md](doc/v1_1_web_demo.md)。

## 演示视频

<video width="100%" autoplay loop muted playsinline controls>
  <source src="https://github.com/ZheHDestiny/ZYNQ_GA_3b/raw/refs/heads/main/video/%E6%BC%94%E7%A4%BA%E6%95%88%E6%9E%9C.mp4" type="video/mp4">
  您的浏览器不支持 HTML5 视频；请通过下方链接播放。
</video>

[无法播放时，点击观看实际上板演示视频（`video/演示效果.mp4`）](video/%E6%BC%94%E7%A4%BA%E6%95%88%E6%9E%9C.mp4)

> 视频按浏览器自动播放策略要求设置为静音（`muted`），并启用 `autoplay`、`loop` 和 `playsinline`。GitHub README 的 HTML 净化策略可能会过滤 `<video>` 或其属性；若页面未显示播放器，请使用上方直链，或将视频上传为 GitHub user-attachment 后替换 `source` 地址。

## 物理建模基础

系统采用二维、无量纲化的牛顿三体模型。三颗天体质量相等，前两颗天体的位置和速度由 8 个输入基因决定，第三颗由质心和总动量约束推导：

```text
r₂ = −r₀ − r₁
v₂ = −v₀ − v₁
```

因此搜索空间同时排除了整体平移和整体漂移。当前硬件使用 `GM = 1/256`、`dt = 1/256`，碰撞阈值为两体 L1 距离 `< 0.125`，任一位置分量绝对值超过 `8.0` 判为逃逸。力项使用平滑的 `GM/r³` 查找表近似；状态以 Q32.32 表示，浏览器和协议输入使用 Q16.16。

物理标签均是**有限积分窗口内的工程分类**：

- **长时生存**：未发生碰撞或逃逸；
- **安全擦掠**：在存活条件下出现具有安全裕量的近心事件；
- **三星纠缠**：角序交换、绕质心转动和紧凑驻留等指标较显著；
- **近周期回归**：允许等质量天体标签交换后的末态构型接近初态。

它们不等价于无限稳定轨道或严格数学周期解。

## 方法与系统架构

```text
浏览器 Web UI
  │ HTTP / JSON
  ▼
Flask Host Backend（PC）
  │ COM UART，115200 baud
  ▼
裸机 board_agent（Zynq PS）
  │ AXI DMA MM2S / S2MM
  ▼
Profile-5 Pure3 FPGA 加速器（Zynq PL，100 MHz）
  │
  ├─ 32 个体硬件遗传算法：初始化、选择、交叉、变异、精英保留
  ├─ Q32.32 平滑 LUT 缓存加速度 Leapfrog 积分
  └─ 生存 fitness 与最优染色体输出
```

一次任务下发后，种群初始化、多代演化、个体积分与 fitness 比较都在 PL 内部完成；PS 负责 DMA 和 UART 协议，PC 后端负责请求校验、持久化、同规则轨迹重放、可解释指标计算及前端展示。

当前四种前端目标的实现边界如下：PL 原生 fitness 是“存活优先”；安全擦掠、三星纠缠和近周期回归采用**多次 FPGA 生存搜索 + PC Profile-5 同规则重放/物理指标重排**。这不是四套独立的原生 RTL fitness。

## 实际上板状态

已验收的运行链路：

```text
Micro SD 冷启动 BOOT.BIN
  → standalone board_agent
  → AXI DMA
  → Profile-5 Pure3 PL
  → UART 回传
  → Flask / Web 轨迹动画
```

- SD 冷启动不依赖 JTAG、SSH 或网线；实际演示通过 USB UART 与 PC 相连。
- 实板已通过 `PING`、`INFO`、`SELFTEST`，并完成 UART/DMA 持久 agent 的 `100/100 PASS` soak 验证。
- 四套固定模板均已在实板完整运行 32768 步；返回染色体与模板一致，FPGA 的 `survived_steps` 与 PC Profile-5 重放一致。
- 经过搜索得到的一个候选已在 FPGA 与 PC 中通过 100000、131072、262144、524288 和 1048576 步复现。百万步 PC 重放的相对能量漂移为 `1.27e-7`，最小两体距离为 `0.314`。

启动已配置的实板 Web 演示（将 `COM13` 改为实际端口）：

```powershell
cd F:\ZYNQ\ZYNQ_GA_3b
.\scripts\run\run_v1_web_demo.ps1 -Port COM13
```

浏览器打开 `http://127.0.0.1:8000/`。开始前请关闭占用该串口的串口工具。

## 实测效果

标准性能探针使用固定工作负载：`max_gen=8`、`steps=8192`、288 个候选、两次实板采样。

| 路径 | 测量范围 | 耗时 | 吞吐 |
|---|---|---:|---:|
| Zynq-7020 FPGA | 完整 GA + DMA + UART | 1090.30 ms | 264.15 eval/s |
| Python 标量参考 | Profile-5 定点 fitness-only 代理 | 69959.41 ms | 4.12 eval/s |
| NumPy float64 | 浮点 Leapfrog fitness-only 代理 | 1807.17 ms | 159.37 eval/s |

在该工作负载下，实板端到端吞吐约为 Python 标量参考的 **64.2×**，约为 NumPy 代理的 **1.66×**。但软件两项只测 fitness 代理，不含硬件 GA 的选择/繁殖及 UART/DMA，且 NumPy 并非 LUT 位精确模型；这些数值不能被表述为严格算法等价的通用加速比。

## 当前能力与限制

- 已部署：Pure3 Profile-5、32 个体 GA、Q32.32 Leapfrog、PC Web 展示、固定模板复现、多起点搜索及 PC 指标重排。
- 保留但未作为当前验收 bitstream 部署：三太阳加测试行星的受限四体“恒纪元”原型 RTL。它是科学目标和后续方向，不能宣传为当前实板能力。
- Web 同步搜索上限为 131072 步。更长窗口已通过直接 UART 验证；2,097,152 步会耗尽现有 DMA 超时，需物理冷启动恢复，不应作为常规演示路径。
- 轨迹动画由 PC 根据 FPGA 返回的最优染色体进行 Profile-5 规则重放，不是 PL 内部状态的逐拍流式输出。

## 目录结构

```text
.
├── doc/
│   ├── spec.md                         # 完整技术报告与实现规格
│   ├── 目前情况.md                      # 当前交接、验收和已知问题
│   ├── v1_1_web_demo.md                 # 实板 Web 演示操作
│   └── test_results/                    # 可提交的测试摘要与性能数据
├── rtl/
│   ├── pure3_core/                      # Profile-5 Pure3 积分、LUT、GA 核心
│   ├── ga_core/                         # 早期/受限四体和通用 GA RTL
│   ├── axi/                             # AXI-Stream 与控制接口
│   ├── top/                             # PL 顶层封装
│   └── tb/                              # RTL 仿真 testbench 与 filelist
├── ps_app/
│   ├── board_agent/standalone/          # 裸机 UART、DMA 板端代理
│   ├── common/                          # PS/PL 通信协议
│   └── host_backend/                    # Flask、UART 客户端、参考模型与测试
├── web/                                 # HTML/CSS/JavaScript Web 仪表板
├── vivado/                              # Block Design、约束和构建 Tcl
├── scripts/                             # PowerShell 构建、上板和演示脚本
└── video/演示效果.mp4                   # 上板演示视频
```

## 开发检查

```powershell
python -B -m pytest ps_app\host_backend\tests -q
node --check web\static\app.js
```

生成的 bitstream、XSA、BOOT.BIN、Vivado/Vitis 中间产物、数据库和日志不纳入 Git；请通过已提交的 Tcl 与 PowerShell 脚本在本地重新生成。

## 远程仓库

- Remote：<https://github.com/ZheHDestiny/ZYNQ_GA_3b>
- Branch：`main`

本次文档更新时，远程 `main` 与本地 `HEAD` 均指向 `90f911b`；但当前工作树含有尚未提交的开发改动，提交前请自行检查 `git status --short` 与 `git diff --check`。
