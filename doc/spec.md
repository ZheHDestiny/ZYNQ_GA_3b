# ZYNQ PS+PL 遗传算法搜索三体恒纪元初始条件规格说明（Spec）

> 版本：v1.1.1 Pure3 多目标轨道实验室
> 状态：受限四体仍是最终主目标；ZYNQ-7020 pure3 fallback 已完成 SD 冷启动、PS/DMA/PL、PC HTTP、多目标候选重排、自定义初态与 Web 动画闭环
> 输入依据：`ZYNQ_GA_3b/doc/requirements.md`、用户审核批注、用户补充说明“目标是复现《三体1》中魏成式从初始条件空间搜索稳定三体运动”
> 目标平台：正点原子领航者 ZYNQ 开发板，按 ZYNQ-7020 / `XC7Z020CLG400-2` 规划。

---

## 0. v0.2.3 目标修正说明

用户确认：工程目标不应停留在“纯三体系统自身稳定”，而应更贴近《三体1》中魏成式问题，即搜索能够产生长时间“恒纪元”窗口的初始条件。公开资料对三体世界的描述中，“恒纪元”可理解为行星被某一颗太阳相对稳定捕获、环境相对规律的时期；“乱纪元”则对应太阳升落无规律、环境剧烈变化的时期。

因此 v0.2.3 起，初版主目标正式调整为：

> **采用“三颗太阳 + 一个质量可忽略测试行星”的受限四体模型，在初始条件空间中搜索能产生长恒纪元窗口的初始条件。**

关键建模约束：

- 三颗太阳互相引力作用，构成真实三体动力学系统。
- 测试行星受三颗太阳引力影响。
- 测试行星质量近似为 0，**不反向影响三颗太阳**。
- 遗传算法搜索三颗太阳和测试行星的初始位置/速度。
- fitness 主目标从“纯三体稳定”升级为“恒纪元窗口足够长、行星不碰撞、不逃逸、光照/潮汐变化可接受”。

同时保留退化方案：

> 如果后续综合、实现或板上测试发现 ZYNQ-7020 资源/时序无法满足受限四体恒纪元搜索，则直接退化为**纯三体初始条件稳定性搜索**。纯三体方案不删除，作为资源不足时的 fallback profile。

与 v0.2.2 的关系：

- v0.2.2 已完成从“固定初值轨迹验证”到“初始条件空间搜索”的纠偏。
- v0.2.3 进一步把“稳定”的主评分目标具体化为“恒纪元”。
- 受限四体是初版主线；纯三体是降级保底线。

---

## 1. 项目目标与边界

### 1.1 总体目标

构建一个运行在 ZYNQ 上的 PS+PL 协同遗传算法搜索系统，初版主目标为“恒纪元搜索”：

1. 用户通过网页前端定义搜索空间，包括三颗太阳质量、太阳初始位置/速度范围、测试行星初始位置/速度范围、恒纪元判据、积分时长、遗传算法参数。
2. PC/Windows 后端或 WSL2 后端负责参数校验、无量纲归一化、搜索空间约束整理、任务组包。
3. ZYNQ PS 端板端代理负责接收任务包、配置 AXI4-Lite、管理 AXI DMA buffer、维护 cache 一致性。
4. ZYNQ PL 端 RTL 遗传算法加速器负责：
   - 生成或接收初始种群。
   - 将每个个体解码为一组三颗太阳 + 测试行星的候选初始条件。
   - 对三颗太阳做三体积分，同时对测试行星做受限四体积分。
   - 计算恒纪元适应度，包括行星生存性、主导太阳捕获稳定性、宜居距离、光照波动、潮汐风险等指标。
   - 在硬件内部完成选择、交叉、变异、精英保留和多代迭代。
5. 系统输出最优恒纪元初始条件、该条件下的轨迹摘要、恒纪元指标和性能统计。
6. 前端展示搜索过程、fitness 收敛曲线、最优恒纪元窗口以及最终三体/行星动画。

### 1.2 主线方案与退化方案

| 项目 | 主线：受限四体恒纪元搜索 | 退化：纯三体稳定性搜索 |
|---|---|---|
| 物理模型 | 三颗太阳 + 一个质量可忽略测试行星 | 仅三颗太阳 |
| 行星是否反向影响太阳 | 否 | 无行星 |
| 个体编码 | 太阳初值 + 行星初值 | 太阳初值 |
| fitness 主目标 | 最大化恒纪元持续时间，惩罚碰撞、逃逸、光照/潮汐剧变 | 三体自身不碰撞、不逃逸、守恒漂移小、可选周期/准周期 |
| 计算量 | 约为纯三体的 1.5x~2x | 最低资源版本 |
| 使用场景 | 项目默认主目标，最贴近魏成式问题 | ZYNQ-7020 资源/时序不满足时直接退化 |

### 1.3 本阶段范围

本阶段仍只完成规格修订：

- 将初版主目标改为“受限四体恒纪元搜索”。
- 保留纯三体稳定性搜索作为硬件资源不足时的 fallback profile。
- 修改数学模型、个体编码、适应度函数、数据格式、PL 模块和资源估算。
- 保留 ZYNQ-7020、AXI DMA、AXI4-Lite、Q16.16、2D Canvas 初版等已审核结论。
- 不提前编写 Verilog/C/Python/JavaScript 实现代码。

## 2. 平台与部署拓扑

### 2.1 目标硬件

本项目只按用户实际开发板 ZYNQ-7020 规划：

- 芯片：`XC7Z020CLG400-2`
- PL 逻辑单元约 85K
- BRAM 约 4.9Mbit
- 常用规划按 220 个 DSP48E1 估算
- PS：双核 Cortex-A9
- DDR3：1GB
- 连接：PS 千兆以太网、AXI HP、AXI DMA、AXI4-Lite

### 2.2 PC+PS+PL 三层拓扑

```text
PC Windows / WSL2 Ubuntu-22.04
  - Browser UI
  - Flask Host Backend
  - 软件参考模型
  - 搜索空间配置、日志、结果保存
        |
        | Ethernet: JSON/RPC + binary SearchTask/ResultPacket
        v
ZYNQ PS Linux
  - board_agent 硬件代理
  - AXI4-Lite 寄存器访问
  - AXI DMA buffer 管理
  - cache flush/invalidate
        |
        | AXI4-Lite + AXI DMA + IRQ
        v
ZYNQ PL
  - GA Stable-IC Search Accelerator
  - population BRAM
  - fitness lanes
  - selection/crossover/mutation
```

PC 依赖性说明：

| 阶段 | PC 依赖 | 说明 |
|---|---|---|
| 开发/调试 | 依赖 | Vivado、IDE、日志、参考模型主要在 PC 上运行 |
| 初版 Web 演示 | 默认依赖 | Windows/WSL2 运行 Flask 和前端，ZYNQ 作为硬件加速节点 |
| 单次硬件搜索 | 不依赖 PC 逐代参与 | 一旦任务下发，GA 多代迭代在 PL 内部完成 |
| 最终一体化部署 | 可降低 PC 依赖 | 后续可把 Flask 迁移到 ZYNQ PS，但不是初版目标 |

WSL2 Ubuntu-22.04 的定位：可选开发/构建辅助。初版不强制迁移后端到 WSL2；Windows 原生 Flask 后端可作为默认方案。

---

## 3. 数学问题定义

### 3.1 主线搜索目标：受限四体恒纪元

给定三颗太阳质量 `m0,m1,m2` 和初始条件搜索空间：

```text
sun_i:    r_i(0) = (x_i, y_i, z_i), v_i(0) = (vx_i, vy_i, vz_i), i=0..2
planet:   r_p(0) = (x_p, y_p, z_p), v_p(0) = (vx_p, vy_p, vz_p)
```

测试行星质量设为 0 或近似 0，不参与太阳系统反作用。寻找一组初始条件，使得积分时间 `T_eval` 内存在尽可能长的“恒纪元”窗口：

1. 三颗太阳自身不发生碰撞、不整体逃逸，能量漂移可控。
2. 测试行星不撞向任意太阳，不逃逸到系统外。
3. 行星在连续时间窗口内被同一颗主导太阳相对稳定捕获，主导太阳切换次数少。
4. 行星到主导太阳的距离处于可配置宜居范围 `[r_hab_min, r_hab_max]`。
5. 行星受到的等效光照 `flux` 波动不过大。
6. 潮汐风险不过大，即行星不同时过近于多颗太阳，且引力梯度不剧烈。

### 3.2 退化搜索目标：纯三体稳定性

如果受限四体主线在 ZYNQ-7020 上资源或时序不可接受，则退化为纯三体搜索：

```text
只搜索 sun_i 的初始位置/速度，不包含 planet
```

退化方案的 fitness 只包含：

- 太阳间碰撞惩罚；
- 太阳系统逃逸惩罚；
- 能量/角动量漂移；
- 可选周期/准周期回归误差。

退化方案不得改变项目目录和通信框架，只通过 `MODEL_MODE = restricted4 / pure3` 切换。

### 3.3 无量纲归一化

PC/后端在组包前做归一化：

- 质量基准：`M0`
- 长度基准：`L0`
- 时间基准：`T0 = sqrt(L0^3 / (G * M0))`
- 归一化后 PL 内部取 `G = 1`

PL 端只处理归一化后的定点数。

### 3.4 约束消元：降低搜索维度

三颗太阳完整初始状态包含 18 个连续变量。为降低维度，初版采用质心系约束编码：

- 三颗太阳质量固定，由用户输入。
- 个体直接编码 sun0 和 sun1 的位置/速度。
- sun2 由质心和总动量约束推导：

```text
r2 = -(m0*r0 + m1*r1) / m2
v2 = -(m0*v0 + m1*v1) / m2
```

测试行星不参与质心/总动量约束，直接编码其位置/速度。

因此主线 3D 受限四体默认 gene：

```text
sun0 r/v:   6 genes
sun1 r/v:   6 genes
planet r/v: 6 genes
TOTAL:      18 genes
```

2D 初版中：

```text
sun0 x,y,vx,vy:     4 genes
sun1 x,y,vx,vy:     4 genes
planet x,y,vx,vy:   4 genes
TOTAL:              12 genes
```

纯三体退化方案中：

```text
2D: 8 genes
3D: 12 genes
```

### 3.5 数值积分

PL 中采用速度 Verlet / Leapfrog 积分。

太阳三体积分：

```text
v_i(t + dt/2) = v_i(t) + 0.5 * a_i(t) * dt
r_i(t + dt)   = r_i(t) + v_i(t + dt/2) * dt
a_i(t + dt)   = force_sun_i(r_0,r_1,r_2)
v_i(t + dt)   = v_i(t + dt/2) + 0.5 * a_i(t + dt) * dt
```

太阳加速度：

```text
a_i = Σ(j != i) m_j * (r_j - r_i) / (|r_j - r_i|^2 + eps^2)^(3/2)
```

测试行星加速度：

```text
a_p = Σ(i=0..2) m_i * (r_i - r_p) / (|r_i - r_p|^2 + eps^2)^(3/2)
```

测试行星不出现在 `a_i` 中。这样每步只比纯三体多 3 个 planet-sun 距离/加速度贡献，计算量约增加 1.5x~2x，而不是完整四体的复杂耦合。

## 4. 遗传算法设计

### 4.1 个体编码

主线 v0.2.3 初版采用 2D 受限四体编码：

```text
ChromosomeRestricted4_2D = {
  sun0:    x0, y0, vx0, vy0,
  sun1:    x1, y1, vx1, vy1,
  planet:  xp, yp, vxp, vyp
}
```

共 12 个 signed Q16.16 gene。解码时推导 sun2：

```text
r2 = -(m0*r0 + m1*r1) / m2
v2 = -(m0*v0 + m1*v1) / m2
```

3D 增强版：

```text
ChromosomeRestricted4_3D = sun0(6) + sun1(6) + planet(6) = 18 genes
```

纯三体退化方案：

```text
ChromosomePure3_2D = sun0(4) + sun1(4) = 8 genes
ChromosomePure3_3D = sun0(6) + sun1(6) = 12 genes
```

### 4.2 搜索空间输入

用户输入每个 gene 的范围，而不是单个固定初值：

```text
x0_min <= x0 <= x0_max
...
vyp_min <= vyp <= vyp_max
```

也可以选择预设模板：

1. 恒纪元 2D 搜索：三太阳 + 测试行星，默认主线。
2. 近似稳定三体邻域 + 行星注入搜索。
3. 层级三星系统 + 行星轨道搜索。
4. 纯三体稳定性退化搜索。
5. 用户自定义质量和边界。

### 4.3 默认 GA 参数

| 参数 | 主线默认值 | 退化默认值 | 说明 |
|---|---:|---:|---|
| `MODEL_MODE` | `restricted4` | `pure3` | 受限四体主线 / 纯三体退化 |
| `DIM_MODE` | `2D` | `2D` | 初版先 2D |
| `POP` | 32 | 32 | 种群规模 |
| `MAX_GEN` | 100 | 100 | 最大代数 |
| `GENE_COUNT` | 12 | 8 | restricted4_2D / pure3_2D |
| `ELITE_COUNT` | 2 | 2 | 精英保留 |
| 锦标赛规模 | 3 | 3 | selection 使用 |
| 交叉概率 | 0.75 | 0.75 | gene 或 segment 粒度 |
| 变异概率 | 0.03/gene | 0.03/gene | 每 gene 变异概率 |
| `T_eval` | 10~100 normalized time | 10~100 | 稳定性评估时间窗 |
| `DT` | Q16.16 | Q16.16 | 积分步长 |
| `STEPS` | 512~1024 起步 | 1024 起步 | 主线计算更重，先从较短窗口开始 |

### 4.4 初始种群生成

两种模式：

1. **PL 生成模式，推荐初版主路径**
   - PS/PC 只传入 gene bounds、三颗太阳质量、恒纪元参数、随机种子。
   - PL 用 xorshift/LFSR 在边界内生成初始种群。
   - 优点：减少 DMA 输入量，更符合“硬件搜索”。

2. **Host seed population 模式**
   - PC 后端可传入部分或全部初始种群。
   - 用于从已知三体构型或手工设定行星轨道附近继续搜索。

### 4.5 选择、交叉、变异

| 操作 | 初版方案 | 硬件实现要点 |
|---|---|---|
| 精英保留 | 保留 fitness 最低的 1~2 个初始条件 | `best_index/best_fitness` 寄存器 |
| 选择 | 锦标赛选择 | RNG 生成候选 index，读取 fitness，比较选优 |
| 交叉 | 均匀交叉或按对象分段交叉 | 可按 sun0/sun1/planet 分段交换 |
| 变异 | 均匀扰动 + 衰减尺度 | RNG 生成扰动，按 generation 右移缩放 |
| 约束 | gene clamp | 保证变异后仍在用户给定 bounds 内 |
| 质心修复 | 推导 sun2 | 保持太阳三体质心和总动量约束 |

### 4.6 资源不满足时的退化策略

若出现以下情况之一：

- Vivado 综合后 DSP/LUT/BRAM 超过预算；
- 100 MHz 时序无法收敛；
- 受限四体 lane 只能做到极低频或极低并行度；
- 板上测试发现单代延时不可接受；

则不继续堆叠复杂降级，而是直接切换：

```text
MODEL_MODE = pure3
GENE_COUNT = 8   # 2D pure3
禁用 planet_integrator 与 heng_era_metric
使用 pure3_stability_metric
```

这样保留 FPGA 调度、种群并行评估、选择/交叉/变异闭环优势，只牺牲恒纪元测试行星目标。

## 5. 恒纪元适应度函数

### 5.1 核心思想

每个个体是一组候选初始条件。主线模式下，PL 对三颗太阳和一个质量可忽略测试行星积分 `STEPS` 步，在积分过程中累计“恒纪元”指标。硬件中仍使用“代价越小越好”。

### 5.2 主线基础代价

```text
cost =
  w_sun_coll    * sun_collision_penalty
+ w_sun_escape  * sun_escape_penalty
+ w_planet_coll * planet_collision_penalty
+ w_planet_esc  * planet_escape_penalty
+ w_capture     * capture_switch_penalty
+ w_hab         * habitable_distance_penalty
+ w_flux        * flux_variance_penalty
+ w_tidal       * tidal_penalty
+ w_heng        * heng_duration_penalty
+ w_energy      * sun_energy_drift_penalty
+ w_survive     * early_fail_penalty
```

其中主导目标为：最大化 `heng_duration`，即连续满足恒纪元条件的最长时间窗口。

### 5.3 太阳三体基础稳定性

三颗太阳本身必须先不过早崩溃：

```text
sun_collision: |r_i - r_j| < sun_d_min
sun_escape:    max(|r_i|, |r_i-r_j|) > sun_r_max
```

若太阳三体早期碰撞或逃逸，当前个体可直接 early reject，返回高 cost。

### 5.4 测试行星生存性

测试行星必须满足：

```text
planet_sun_distance_i > planet_d_min
|r_p| < planet_r_max
```

如果行星撞向太阳、过近掠过太阳或逃逸，给予大惩罚；严重情况 early terminate。

### 5.5 主导太阳捕获稳定性

定义行星当前主导太阳：

```text
dominant_sun(t) = argmin_i |r_p(t) - r_i(t)|
```

恒纪元倾向于在较长时间内由同一颗太阳主导。如果 `dominant_sun` 频繁切换，说明环境更接近乱纪元：

```text
capture_switch_penalty += number_of_dominant_sun_changes
```

### 5.6 宜居距离窗口

行星到主导太阳距离：

```text
r_dom = |r_p - r_dominant|
```

满足：

```text
r_hab_min <= r_dom <= r_hab_max
```

则该步计入恒纪元候选窗口；否则累加距离惩罚：

```text
habitable_distance_penalty += outside_range_error(r_dom)^2
```

### 5.7 光照稳定性

简化光照模型：

```text
flux = Σ_i luminosity_i / (|r_p - r_i|^2 + eps_flux)
```

初版可令 `luminosity_i` 与质量相关或由用户输入。恒纪元要求光照不过热、不过冷、波动不过大：

```text
flux_min <= flux <= flux_max
flux_variance over window is small
```

硬件实现可用累加 `flux_sum`、`flux_sq_sum`、`flux_min/max` 的方式近似方差。

### 5.8 潮汐风险

当行星同时靠近多颗太阳，或最近太阳与次近太阳距离差太小，可能对应剧烈潮汐/撕裂风险。初版用硬件友好的近似：

```text
tidal_score = max_i(m_i / d_i^3) + second_max_i(m_i / d_i^3)
```

若 `tidal_score > tidal_max`，累加惩罚。

### 5.9 恒纪元持续时间

每个积分步判断是否满足简化恒纪元条件：

```text
is_heng_step =
  planet_alive
  && sun_system_alive
  && dominant_sun_not_switching_too_often
  && r_hab_min <= r_dom <= r_hab_max
  && flux_min <= flux <= flux_max
  && tidal_score <= tidal_max
```

硬件维护两个计数器：

```text
current_heng_len
best_heng_len
```

若 `is_heng_step=1`，`current_heng_len += 1`；否则清零。最终：

```text
heng_duration_penalty = max(0, target_heng_steps - best_heng_len)^2
```

### 5.10 纯三体退化 fitness

退化模式禁用测试行星相关指标：

```text
cost_pure3 =
  w_sun_coll   * sun_collision_penalty
+ w_sun_escape * sun_escape_penalty
+ w_energy     * sun_energy_drift_penalty
+ w_period     * recurrence_penalty_optional
+ w_shape      * shape_stability_penalty_optional
```

该模式用于资源不足时保留硬件 GA 搜索框架。

## 6. 定点数与二进制格式

### 6.1 定点格式

初版采用用户已确认的：

```text
fix_t = signed Q16.16, 32-bit
```

所有输入边界、质量、位置、速度、dt、阈值、权重均按 Q16.16 或 Q0.16 打包。

### 6.2 状态打包

一个天体/行星状态统一使用 32 bytes：

```text
ObjectState = x,y,z,vx,vy,vz,mass_or_zero,reserved = 8 * int32 = 32 bytes
```

主线受限四体输出：

```text
Restricted4State = sun0 + sun1 + sun2 + planet = 4 * 32 = 128 bytes
```

纯三体退化输出：

```text
Pure3State = sun0 + sun1 + sun2 = 3 * 32 = 96 bytes
```

测试行星 `mass_or_zero = 0`，表示其不反向影响太阳。

### 6.3 Gene bounds 打包

每个 gene 有下界、上界、初始扰动尺度：

```text
GeneBound = {
  min_q16: int32,
  max_q16: int32,
  mutation_scale_q16: int32,
  flags: uint32
} = 16 bytes
```

默认主线：

```text
restricted4_2D: GENE_COUNT = 12 => GeneBounds = 192 bytes
restricted4_3D: GENE_COUNT = 18 => GeneBounds = 288 bytes
```

退化方案：

```text
pure3_2D: GENE_COUNT = 8  => GeneBounds = 128 bytes
pure3_3D: GENE_COUNT = 12 => GeneBounds = 192 bytes
```

### 6.4 染色体打包

```text
ChromosomeBin = GENE_COUNT * int32
```

默认主线：

```text
restricted4_2D: ChromosomeBin = 12 * 4 = 48 bytes
POP=32 => 1536 bytes
```

退化方案：

```text
pure3_2D: ChromosomeBin = 8 * 4 = 32 bytes
POP=32 => 1024 bytes
```

主线加入测试行星后，染色体存储开销仍很小；主要额外资源消耗来自 planet-sun 加速度和恒纪元指标计算。

## 7. PS+PL 通信规格

### 7.1 总线与 IP

- `AXI4-Lite`：控制寄存器、状态寄存器、参数配置、启动/停止/中断。
- `AXI DMA MM2S`：SearchTask 从 PS DDR 到 PL。
- `AXI DMA S2MM`：SearchResult 从 PL 到 PS DDR。
- `AXI HP Port`：DMA 经 PS 高性能端口访问 DDR。
- `IRQ_F2P`：done/error/trace 中断，可选。

### 7.2 输入任务包 SearchTask

```text
SearchTask {
  Header                 128 bytes
  Masses                 3 * int32 Q16.16 + padding = 16 bytes
  ObjectiveParams        128 bytes
  GeneBounds             GENE_COUNT * 16 bytes
  OptionalSeedPopulation POP * GENE_COUNT * int32
}
```

`ObjectiveParams` 包含恒纪元阈值：`sun_d_min`、`sun_r_max`、`planet_d_min`、`planet_r_max`、`r_hab_min`、`r_hab_max`、`flux_min`、`flux_max`、`tidal_max`、`target_heng_steps`、各类权重等。

Header：

| Byte Offset | 字段 | 类型 | 描述 |
|---:|---|---|---|
| 0 | magic | uint32 | `0x5341475A`，近似 `ZGAS` |
| 4 | version | uint32 | `0x00020300` |
| 8 | header_bytes | uint32 | 128 |
| 12 | flags | uint32 | bit0 2D, bit1 host seed, bit2 trace enable, bit3 fallback allowed |
| 16 | model_mode | uint32 | 0 pure3，1 restricted4；默认 1 |
| 20 | pop_size | uint32 | 默认 32 |
| 24 | max_gen | uint32 | 最大代数 |
| 28 | gene_count | uint32 | restricted4_2D 默认 12；pure3_2D 默认 8 |
| 32 | steps | uint32 | 每个个体积分步数 |
| 36 | dt_q16 | int32 | Q16.16 |
| 40 | eps2_q16 | int32 | 引力软化因子平方 |
| 44 | mutation_rate_q16 | uint32 | Q0.16 |
| 48 | crossover_rate_q16 | uint32 | Q0.16 |
| 52 | seed0 | uint32 | RNG seed |
| 56 | seed1 | uint32 | RNG seed |
| 60 | trace_stride | uint32 | 每多少代输出一次摘要 |
| 64 | objective_mode | uint32 | 0 stable_era，1 bounded，2 periodic，3 quasi_periodic |
| 68 | target_heng_steps | uint32 | 目标恒纪元连续步数 |
| 72 | reserved | uint32[14] | 保留 |

### 7.3 输出结果包 SearchResult

```text
SearchResult {
  ResultHeader           128 bytes
  BestState              128 bytes for restricted4 / 96 bytes for pure3
  BestChromosome         GENE_COUNT * int32
  BestMetrics            160 bytes
  OptionalTrace          TraceRecord[]
}
```

ResultHeader：

| Byte Offset | 字段 | 类型 | 描述 |
|---:|---|---|---|
| 0 | magic | uint32 | `0x4F41475A`，近似 `ZGAO` |
| 4 | version | uint32 | `0x00020300` |
| 8 | status | uint32 | 0 ok，非 0 error |
| 12 | model_mode | uint32 | 0 pure3，1 restricted4 |
| 16 | generations_done | uint32 | 实际代数 |
| 20 | best_fitness_lo | uint32 | 最优 cost 低 32 bit |
| 24 | best_fitness_hi | uint32 | 最优 cost 高 32 bit |
| 28 | cycle_count_lo | uint32 | PL 周期数 |
| 32 | cycle_count_hi | uint32 | PL 周期数 |
| 36 | output_bytes | uint32 | 输出总字节数 |
| 40 | trace_count | uint32 | trace 条数 |
| 44 | fail_reason | uint32 | 若无可行解，说明主要失败原因 |
| 48 | fallback_used | uint32 | 0 no，1 pure3 fallback |
| 52 | reserved | uint32[19] | 保留 |

BestMetrics 建议包含：

| 字段 | 类型 | 描述 |
|---|---|---|
| best_heng_steps | uint32 | 最长连续恒纪元窗口 |
| survived_steps | uint32 | 未碰撞/未逃逸步数 |
| min_sun_distance | Q16.16 | 太阳间最小距离 |
| min_planet_sun_distance | Q16.16 | 行星到太阳最小距离 |
| max_planet_radius | Q16.16 | 行星最大系统尺度 |
| energy_drift | Q16.16 | 太阳三体能量相对漂移 |
| capture_switch_count | uint32 | 主导太阳切换次数 |
| flux_mean | Q16.16 | 平均光照 |
| flux_variance | Q16.16 | 光照波动 |
| max_tidal_score | Q16.16 | 最大潮汐风险 |
| recurrence_error | Q16.16 | 可选周期回归误差 |

### 7.4 AXI4-Lite 寄存器

| Offset | 名称 | R/W | 描述 |
|---:|---|---|---|
| 0x00 | CTRL | R/W | bit0 start, bit1 soft_reset, bit2 irq_en, bit3 abort, bit4 force_pure3 |
| 0x04 | STATUS | R | bit0 idle, bit1 busy, bit2 done, bit3 error, bit4 fallback_used |
| 0x08 | VERSION | R | `0x00020300` |
| 0x0C | ERROR_CODE | R | 错误码 |
| 0x10 | MODEL_MODE | R/W | 0 pure3，1 restricted4 |
| 0x14 | POP_SIZE | R/W | 种群规模 |
| 0x18 | MAX_GEN | R/W | 最大代数 |
| 0x1C | GENE_COUNT | R/W | gene 数 |
| 0x20 | STEPS | R/W | 每个个体积分步数 |
| 0x24 | DT_Q16 | R/W | 积分步长 |
| 0x28 | SEED0 | R/W | RNG seed0 |
| 0x2C | SEED1 | R/W | RNG seed1 |
| 0x30 | FLAGS | R/W | 2D/3D、目标模式、trace enable |
| 0x34 | BEST_FIT_LO | R | 当前最优 fitness 低 32 bit |
| 0x38 | BEST_FIT_HI | R | 当前最优 fitness 高 32 bit |
| 0x3C | CUR_GEN | R | 当前代数 |
| 0x40 | CYCLE_CNT_LO | R | cycle counter 低 32 bit |
| 0x44 | CYCLE_CNT_HI | R | cycle counter 高 32 bit |
| 0x48 | IRQ_STATUS | R/W1C | done/error/trace 中断状态 |
| 0x4C | BEST_INDEX | R | 当前最优个体编号 |
| 0x50 | VALID_COUNT | R | 当前代可行个体数量 |
| 0x54 | BEST_HENG_STEPS | R | 当前最优恒纪元连续步数 |

`ERROR_CODE`：

| 值 | 含义 |
|---:|---|
| 0 | 无错误 |
| 1 | SearchTask magic/version 错误 |
| 2 | `POP/GENE_COUNT/STEPS/MODEL_MODE` 超出支持范围 |
| 3 | Gene bounds 非法，min >= max |
| 4 | 输入 DMA 缺少 TLAST 或长度不足 |
| 5 | 输出通道 backpressure 超时 |
| 6 | 定点溢出或数值异常 |
| 7 | 用户 abort |
| 8 | restricted4 资源/配置不可用，已退化 pure3 |

### 7.5 板端启动时序

1. PC 后端生成 `SearchTask`。
2. PC 通过以太网发送给 ZYNQ PS `board_agent`。
3. `board_agent` 分配 input/output DMA buffer。
4. 写入 input buffer，flush input cache，invalidate output cache。
5. 先启动 AXI DMA S2MM 输出通道。
6. 再启动 AXI DMA MM2S 输入通道。
7. 写 AXI4-Lite 参数寄存器。
8. 写 `CTRL.start=1`。
9. PL 加载搜索空间、生成种群、按 `MODEL_MODE` 执行多代 GA。
10. PL 输出 `SearchResult`，置 done/irq。
11. `board_agent` invalidate output cache，解析结果并回传 PC。
12. PC 后端推送结果到前端。

## 8. PL RTL 模块规格

### 8.1 顶层模块

建议模块名：

```text
ga3b_heng_era_accel_top
```

顶层接口：

| 接口 | 方向 | 协议 | 说明 |
|---|---|---|---|
| `aclk` | in | clock | AXI/核心统一时钟 |
| `aresetn` | in | reset | 低有效复位 |
| `s_axi_ctrl` | slave | AXI4-Lite | 控制寄存器 |
| `s_axis_in` | slave | AXI4-Stream | SearchTask 输入 |
| `m_axis_out` | master | AXI4-Stream | SearchResult 输出 |
| `irq` | out | interrupt | done/error/trace |

### 8.2 模块划分

```text
ga3b_heng_era_accel_top
├── axi_lite_regs
├── search_task_unpacker
├── result_packer
├── ga_controller_fsm
├── gene_bounds_mem
├── objective_params_regs
├── population_mem
│   ├── population_A
│   ├── population_B
│   └── fitness_mem
├── population_init_engine
├── fitness_scheduler
│   ├── fitness_lane[0]
│   ├── fitness_lane[1]
│   └── ...
├── heng_era_fitness_lane
│   ├── chromosome_decoder
│   ├── sun3_integrator
│   ├── test_planet_integrator
│   ├── heng_era_metric_accumulator
│   └── cost_accumulator
├── pure3_fallback_fitness_lane
├── fitness_reduce
├── selection_engine
├── crossover_mutation_engine
├── rng_engine
└── debug_perf_counters
```

### 8.3 主状态机

| 状态 | 功能 |
|---|---|
| IDLE | 等待 start |
| LOAD_HEADER | 接收并校验 SearchTask header |
| LOAD_PARAMS | 接收质量、ObjectiveParams、gene bounds |
| CHECK_MODE | 检查 `MODEL_MODE` 和资源配置；必要时切换 pure3 fallback |
| INIT_POP | 由 PL RNG 生成种群，或加载 host seed population |
| EVAL | 并行评估候选初始条件 |
| REDUCE | 归约 best/mean/valid_count/best_heng_steps |
| SELECT | 锦标赛选择父代 |
| REPRODUCE | 交叉、变异、clamp，写下一代 |
| ELITE | 精英保留 |
| TRACE | 可选输出中间摘要 |
| CHECK_STOP | 判断 max_gen / fitness 阈值 / abort |
| OUTPUT | 输出最优初始条件、恒纪元指标或 pure3 指标 |
| DONE | done + irq |
| ERROR | error + irq |

### 8.4 主线 Fitness lane 算子

每个 lane 输入一个候选初始条件，输出一个 cost：

```text
chromosome
 -> decode sun0/sun1/planet, derive sun2
 -> integrate sun3 + test planet for STEPS
 -> accumulate heng era metrics
 -> cost
```

伪流程：

```text
state0 = decode_restricted4_chromosome(chromosome, masses)
sun_state = state0.suns
planet_state = state0.planet
metrics = init_heng_metrics(state0)
for step in 1..STEPS:
    sun_state = verlet_step_sun3(sun_state, dt)
    planet_state = verlet_step_test_planet(planet_state, sun_state, dt)
    metrics.update_sun_collision_escape(sun_state)
    metrics.update_planet_collision_escape(planet_state, sun_state)
    metrics.update_capture_hab_flux_tidal(planet_state, sun_state)
    if step % ENERGY_STRIDE == 0:
        metrics.update_sun_energy(sun_state)
    if early_collision_or_escape:
        break
cost = heng_metrics_to_fitness(metrics)
```

### 8.5 退化 Fitness lane 算子

若 `MODEL_MODE=pure3`，禁用 `test_planet_integrator` 和 `heng_era_metric_accumulator`：

```text
chromosome
 -> decode sun0/sun1, derive sun2
 -> integrate sun3 for STEPS
 -> accumulate pure3 stability metrics
 -> cost_pure3
```

此时同样使用 GA 框架、BRAM 双缓冲、selection/crossover/mutation，只是 fitness lane 更小。

### 8.6 并行评估、选择、交叉的硬件含义

以 `POP=32`、`fitness_lane=2` 为例：

| 阶段 | 硬件算子 | 输入 | 输出 | 并行/流水方式 |
|---|---|---|---|---|
| 1 | `fitness_scheduler` | `population_A[0..31]` | lane 任务 | 给空闲 lane 分配个体 |
| 2 | `heng_era_fitness_lane[0..1]` | 候选太阳+行星初值 | fitness/metrics | 2 个候选同时积分评估 |
| 3 | `fitness_reduce` | 32 个 fitness | best/second/valid_count/best_heng | 比较器树或分批比较 |
| 4 | `selection_engine` | fitness_mem + RNG index | 父代 index | 锦标赛选择 |
| 5 | `crossover_mutation_engine` | 父代 gene | 子代 gene | gene 流式交叉、变异、clamp |
| 6 | `population_swap` | A/B buffer | 下一代 | 交换读写 bank |

### 8.7 硬件资源保护策略

为了避免受限四体主线破坏 FPGA 并行调度优势，RTL 必须保留编译期/运行期 profile：

| Profile | 说明 | 触发条件 |
|---|---|---|
| `restricted4_2lane` | 受限四体，2 lane，默认目标 | 资源/时序满足 |
| `restricted4_1lane` | 受限四体，1 lane | 2 lane 超资源但仍想保留恒纪元目标 |
| `pure3_2lane` | 纯三体，2 lane | 受限四体无法收敛或过慢 |
| `pure3_1lane` | 纯三体，1 lane | 最小保底 |

用户要求的原则是：如果硬件资源不满足，不做过多复杂裁剪，优先直接退化到纯三体问题，保留 GA 硬件闭环优势。

## 9. 资源与性能估算

### 9.1 v0.2.3 初版配置

| 配置项 | 主线默认值 | 退化默认值 | 说明 |
|---|---:|---:|---|
| `MODEL_MODE` | `restricted4` | `pure3` | 主线/退化 |
| fitness lane 数 | 2 | 2 | 若主线超限可先 1 lane，再退化 pure3 |
| `POP` | 32 | 32 | 种群规模 |
| `GENE_COUNT` | 12 | 8 | 2D restricted4 / 2D pure3 |
| `STEPS` | 512~1024 起步 | 1024 起步 | 主线先用较短窗口验证 |
| 定点格式 | Q16.16 | Q16.16 | 用户已确认 |
| PL 时钟 | 100 MHz | 100 MHz | 初版目标 |

### 9.2 粗略周期估算

定义：

- `P`：fitness lane 数量。
- `POP`：种群规模。
- `STEPS`：每个候选初始条件积分步数。
- `Cstep`：每个积分小步周期数。

纯三体估算：

```text
Cstep_pure3 ≈ 24 cycles
Cgen_pure3 ≈ ceil(32 / 2) * 1024 * 24 = 393,216 cycles
100 MHz 下约 3.93 ms / generation
```

受限四体主线估算：

```text
Cstep_restricted4 ≈ 36~48 cycles
Cgen_restricted4 ≈ ceil(32 / 2) * 1024 * (36~48)
                  ≈ 589,824 ~ 786,432 cycles
100 MHz 下约 5.9 ~ 7.9 ms / generation
```

因此加入质量可忽略测试行星后，计算量预计约为纯三体的 `1.5x~2x`。这对 ZYNQ-7020 仍可作为初版主目标，但必须通过综合和板上测试确认。

### 9.3 资源估算

| 模块 | restricted4 估算 | pure3 估算 | 说明 |
|---|---:|---:|---|
| AXI/packet/control | 2k~4k LUT | 2k~4k LUT | 控制和打包基本相同 |
| 种群/fitness/gene bounds | 4~10 BRAM | 4~8 BRAM | 染色体很小 |
| 2 个 fitness lane | 22k~40k LUT / 90~170 DSP | 18k~32k LUT / 70~140 DSP | 主线多 planet-sun pipeline 和恒纪元指标 |
| selection/crossover/mutation/RNG | 3k~6k LUT | 3k~6k LUT | GA 算子相同 |
| trace/debug/perf | 2~6 BRAM | 2~6 BRAM | 可裁剪 |
| 合计目标 | 30k~55k LUT / 100~180 DSP | 25k~47k LUT / 80~150 DSP | ZYNQ-7020 可尝试；以 Vivado 报告为准 |

### 9.4 退化判据

若满足任一条件，直接切换到 pure3 profile：

- restricted4_1lane 仍无法 100 MHz 时序收敛；
- DSP 或 LUT 占用超过目标上限且影响实现；
- 单代延时超过 pure3 的 2.5x；
- 恒纪元指标导致 lane 控制逻辑复杂到影响稳定性；
- 板上测试无法稳定完成 DMA/计算/回传闭环。

退化后仍保留：

```text
PL 内部 GA 多代闭环
BRAM 种群双缓冲
并行 fitness lane
硬件 selection/crossover/mutation
```

因此即使退化到纯三体问题，也不会丢失 FPGA 调度和并行验证框架。

## 10. PC/PS 软件与 Web 规格

### 10.1 PC Host Backend

Windows 原生 Flask 为默认运行方式；WSL2 Ubuntu-22.04 作为可选开发环境。

PC 端负责：

1. Web API 和前端静态资源。
2. 搜索空间配置和校验，包括太阳质量、测试行星边界、恒纪元阈值。
3. 单位归一化、Q16.16 量化。
4. 生成 `SearchTask`，包含 `MODEL_MODE=restricted4/pure3`。
5. 通过以太网调用 ZYNQ `board_agent`。
6. 接收 `SearchResult`。
7. 反归一化并展示最优初始条件、恒纪元窗口和轨迹。
8. 软件参考模型复算验证。

### 10.2 ZYNQ PS board_agent

板端代理负责：

1. 接收 PC 的 SearchTask。
2. 分配 DMA buffer。
3. 配置 AXI DMA 和 AXI4-Lite。
4. 等待 PL done/error。
5. 读取 SearchResult。
6. 回传 PC。

board_agent 不负责每代 GA 调度，避免 PS 成为性能瓶颈。

### 10.3 Web 前端

前端初版采用 2D Canvas。

功能：

- 输入三颗太阳质量和搜索范围。
- 输入测试行星初始位置/速度搜索范围。
- 支持固定某些 gene、搜索某些 gene。
- 支持选择 `restricted4` 主线或 `pure3` 退化模式。
- 支持配置恒纪元判据：宜居距离、光照范围、潮汐阈值、目标恒纪元持续时间。
- 展示 fitness 曲线、valid_count、best_heng_steps、best metrics。
- 展示最优初始条件。
- 播放三颗太阳和测试行星的 2D 轨迹动画。

### 10.4 API 示例

#### POST `/api/search_jobs`

```json
{
  "model_mode": "restricted4",
  "dimension": "2d",
  "masses": [1.0, 1.0, 1.0],
  "gene_bounds": {
    "sun0.x": [-2.0, 2.0],
    "sun0.y": [-2.0, 2.0],
    "sun0.vx": [-1.0, 1.0],
    "sun0.vy": [-1.0, 1.0],
    "sun1.x": [-2.0, 2.0],
    "sun1.y": [-2.0, 2.0],
    "sun1.vx": [-1.0, 1.0],
    "sun1.vy": [-1.0, 1.0],
    "planet.x": [-4.0, 4.0],
    "planet.y": [-4.0, 4.0],
    "planet.vx": [-2.0, 2.0],
    "planet.vy": [-2.0, 2.0]
  },
  "heng_era": {
    "target_heng_time": 5.0,
    "r_hab_min": 0.5,
    "r_hab_max": 3.0,
    "flux_min": 0.2,
    "flux_max": 4.0,
    "tidal_max": 20.0,
    "planet_d_min": 0.05,
    "planet_r_max": 10.0
  },
  "stability": {
    "t_eval": 20.0,
    "dt": 0.01,
    "sun_d_min": 0.05,
    "sun_r_max": 10.0,
    "softening": 0.001
  },
  "ga": {
    "population": 32,
    "generations": 100,
    "mutation_rate": 0.03,
    "crossover_rate": 0.75,
    "seed": 12345,
    "fallback_allowed": true
  }
}
```

响应：

```json
{
  "job_id": "uuid",
  "status": "queued"
}
```

#### GET `/api/search_jobs/<job_id>/result`

返回：

```json
{
  "model_mode": "restricted4",
  "fallback_used": false,
  "best_initial_condition": {
    "suns": [
      {"mass": 1.0, "pos": [0.1, 0.2, 0.0], "vel": [0.3, -0.1, 0.0]},
      {"mass": 1.0, "pos": [-0.2, 0.4, 0.0], "vel": [-0.2, 0.2, 0.0]},
      {"mass": 1.0, "pos": [0.1, -0.6, 0.0], "vel": [-0.1, -0.1, 0.0]}
    ],
    "planet": {"mass": 0.0, "pos": [1.0, 0.0, 0.0], "vel": [0.0, 0.8, 0.0]}
  },
  "metrics": {
    "fitness": 1234,
    "best_heng_time": 5.7,
    "best_heng_steps": 570,
    "capture_switch_count": 1,
    "flux_variance": 0.03,
    "max_tidal_score": 4.2,
    "sun_energy_drift": 0.002
  },
  "trajectory": []
}
```

## 11. 验证计划

### 11.1 软件参考模型

PC 端必须实现同等问题定义的参考模型：

- 同样的 restricted4 / pure3 模式切换。
- 同样的初始条件解码和 sun2 推导。
- 同样的 Verlet 积分。
- 同样的测试行星受限积分。
- 同样的恒纪元指标和 pure3 退化指标。
- 对 PL 输出的最优初始条件做复算验证。

### 11.2 RTL 仿真

测试层次：

1. `rng_engine_tb`
2. `chromosome_decoder_tb`
3. `force_pair_pipeline_tb`
4. `invsqrt_unit_tb`
5. `sun3_integrator_tb`
6. `test_planet_integrator_tb`
7. `heng_era_metric_accumulator_tb`
8. `pure3_fallback_fitness_lane_tb`
9. `fitness_lane_tb`
10. `selection_engine_tb`
11. `crossover_mutation_engine_tb`
12. `ga_core_tb`
13. `axi_stream_packet_tb`
14. `ga3b_heng_era_accel_top_tb`

### 11.3 板级测试

1. AXI4-Lite 寄存器读写。
2. DMA SearchTask/SearchResult loopback。
3. 单个 pure3 候选初始条件 fitness 测试。
4. 单个 restricted4 候选初始条件恒纪元 fitness 测试。
5. 小种群 restricted4 搜索：`POP=8, GEN=5, STEPS=128`。
6. 标准 restricted4 搜索：`POP=32, GEN=100, STEPS=512~1024`。
7. pure3 fallback 搜索：`POP=32, GEN=100, STEPS>=1024`。
8. PC -> PS -> PL -> PS -> PC 端到端测试。
9. Web 2D 动画展示。

### 11.4 验收指标

| 指标 | 初版目标 |
|---|---:|
| 能从搜索空间中产生并评估候选初始条件 | 必须 |
| restricted4 模式能输出最优太阳+测试行星初值 | 必须 |
| PL 内部完成多代 GA，不需要 PC/PS 每代调度 | 必须 |
| 恒纪元指标可解释：best_heng_steps、capture_switch、flux、tidal | 必须 |
| 资源不足时可切换 pure3 fallback | 必须 |
| 软件参考模型可复算 PL 最优解 | 必须 |
| 前端可展示三颗太阳 + 测试行星的 2D 动画 | 必须 |

## 12. 建议项目目录结构

审核通过后建议创建：

```text
ZYNQ_GA_3b/
├── doc/
│   ├── requirements.md
│   ├── spec.md
│   ├── resource_notes.md
│   └── verification_plan.md
├── rtl/
│   ├── top/
│   ├── axi/
│   ├── ga_core/
│   ├── math/
│   └── tb/
├── sim/
│   ├── golden_model/
│   └── test_vectors/
├── ps_app/
│   ├── host_backend/
│   ├── board_agent/
│   └── common/
├── web/
│   ├── static/
│   └── templates/
├── vivado/
│   ├── constraints/
│   ├── ip_repo/
│   └── scripts/
└── scripts/
    ├── build/
    └── run/
```

当前阶段只修订 `doc/spec.md`，不提前写代码。

---

## 13. FPGA 加速机制与 GPU 对比评估

本节回答项目启动前必须明确的问题：ZYNQ PS+PL 到底如何实现硬件加速、相对 GPU 的优势来自哪里、是否可能在端到端延时上胜出。

### 13.1 FPGA/PL 加速来自哪里

本项目中 PL 加速不是来自“更高 TFLOPS”，而是来自定制数据通路和任务闭环：

1. **定制流水线**  
   太阳三体积分、测试行星受限积分、距离计算、反平方根近似、碰撞/逃逸判断、恒纪元指标和 fitness 累加被做成固定结构流水线。数据按节拍流动，不需要 CPU/GPU 那样取指、调度通用指令。

2. **低精度定点计算**  
   初版采用 Q16.16 定点。FPGA 可以用 DSP + LUT 做刚好够用的乘加、比较、clamp、近似 `invsqrt`，不必为 IEEE FP32/FP64 的通用语义付出全部代价。

3. **算法内循环留在 PL**  
   一次 SearchTask 下发后，PL 内部完成多代 GA：

   ```text
   生成候选初值 -> 受限四体积分评估 -> 恒纪元评分 -> 选择 -> 交叉 -> 变异 -> 下一代
   ```

   PS/PC 不参与每一代调度，减少 host-device 往返。

4. **片上 BRAM 保存种群和 fitness**  
   种群、fitness、gene bounds 尽量放在 BRAM 中，避免每代从 DDR 反复搬运。

5. **早停与剪枝可以硬连线**  
   若候选初值早期碰撞或逃逸，fitness lane 可提前终止并返回高 cost。对于大量无效候选，这种 early reject 可以节省很多无意义积分。

6. **确定性低抖动**  
   FPGA pipeline 的延时更可控，适合固定规模、固定时序、低抖动任务。

### 13.2 为什么不能只用 TFLOPS 比较

GPU 的 TFLOPS 是浮点吞吐指标，适合衡量大规模 FP32/FP64 乘加吞吐。本项目更合理的指标是：

```text
每秒可评估候选初始条件数量
time_per_candidate = 积分步数 * 每步周期 / 时钟频率
end_to_end_latency = 任务组包 + 传输 + 硬件搜索 + 结果回传 + 可视化处理
```

FPGA 的优势通常体现在：

- 固定点而非浮点；
- 小批量、低延时而非超大吞吐；
- 自定义 early exit；
- 数据常驻片上；
- 无 GPU kernel launch/runtime 调度链路，或调度链路极短。

因此，“同等算力评估只看 TFLOPS”对 FPGA 不公平，也不能说明本项目真实端到端表现。应比较 **每焦耳有效候选评估数、单任务端到端延时、最早找到可行稳定解的时间**。

### 13.3 粗略性能上限估算

按 v0.2.3 主线受限四体初版配置：

```text
POP = 32
fitness_lane = 2
STEPS = 1024
Cstep ≈ 36~48 cycles
PL clock = 100 MHz 
```
**用户注：这里时钟可以考虑倍频吗？**

单代周期估算：

```text
Cgen ≈ ceil(32 / 2) * 1024 * (36~48) = 589,824~786,432 cycles
单代约 5.9~7.9 ms
100 代约 0.59~0.79 s + DMA/控制/网络开销
```

该估算说明：受限四体恒纪元主线在 ZYNQ-7020 上仍可尝试，但必须接受其定位是低功耗、确定性、可解释的硬件搜索器，而不是高吞吐 GPU 的替代品。若资源或时序不满足，直接退化到 pure3 profile。

### 13.4 与通用 GPU 的端到端对比结论

#### 情况 A：对比未优化 GPU，且任务规模较小

FPGA 可能有优势，原因是：

- GPU kernel launch、runtime 初始化、数据拷贝、Python/CUDA 框架调度可能占据主要延时；
- FPGA 可以在 PL 中常驻 GA pipeline；
- 若很多候选很快碰撞/逃逸，FPGA early reject 有利。

但若当前拓扑是 PC 通过以太网访问 ZYNQ，则网络往返会吃掉一部分低延时优势。因此小任务低延时对比时，应优先评估 **ZYNQ PS 本地触发 PL**，而不是 PC 每次通过网络触发。

#### 情况 B：对比优化过的 GPU

若 GPU 使用 CUDA/C++、批量评估、常驻 kernel、CUDA Graphs、persistent kernel、预分配显存、减少 CPU-GPU 往返，则 ZYNQ-7020 很难在非平凡规模上取得端到端延时优势。

原因：

- 高端 GPU 或中端独显的并行资源远大于 ZYNQ-7020；
- 三体/受限四体候选评估天然适合 GPU 批量并行：每个候选初始条件可映射到线程块或线程组；
- runtime 优化后，GPU launch 和调度开销可降到很低；
- 当 `POP * GEN * STEPS` 足够大时，计算吞吐主导总时间，GPU 的大规模并行会压过 ZYNQ-7020 的定制流水线优势。

#### 情况 C：对比同功耗/嵌入式场景

若比较对象不是桌面高端 GPU，而是同功耗、同体积、同成本级别的嵌入式计算平台，FPGA 更有机会在以下方面取得优势：

- 单任务确定性延时；
- 每瓦有效候选评估数；
- 小批量低抖动；
- 不依赖大型 GPU runtime；
- 可与传感/控制链路直接流式连接。

但这仍需要实测，不能在 spec 阶段保证必胜。

### 13.5 可靠结论

对本项目，必须采用以下务实结论：

1. **ZYNQ-7020 PL 的加速价值成立，但不是因为它比 GPU 有更高算力。**  
   它的价值在于定制流水线、固定点、片上数据复用、早停剪枝、确定性延时和 PS+PL 闭环。

2. **若对比桌面/高端通用 GPU，并且 GPU 代码经过认真优化，本设计大概率无法在大规模搜索吞吐上胜出。**  
   尤其当 `POP * GEN * STEPS` 很大时，GPU 会更强。

3. **本设计可能取得端到端优势的窗口是：小到中等任务规模、低延时优先、候选早停比例高、PS 本地触发 PL、数据不频繁跨网络、GPU 侧未使用 persistent/graph 等深度 runtime 优化。**

4. **当 GPU 加入 runtime 优化后，FPGA 的端到端优势上限主要只剩三类：**
   - 更低抖动和更确定的实时性；
   - 更好的能效；
   - 针对固定点/剪枝/特殊 fitness 的定制效率。

5. **因此本项目不应承诺“普遍比 GPU 更快”。**  
   更合理的项目目标是：

   > 在 ZYNQ-7020 上实现一个可解释、低功耗、确定性、PS+PL 闭环的遗传算法恒纪元初值搜索加速器，并通过 pure3 fallback 与 CPU/GPU 基线比较，找出其适用边界。

### 13.6 后续必须设置的基准测试

为了避免空泛比较，后续 v1.0/v1.1 必须至少提供三组 baseline：

| baseline | 作用 |
|---|---|
| Python/NumPy 或 C++ CPU 单线程 | 证明硬件加速基本有效 |
| C++ CPU 多线程 | 对比普通多核优化水平 |
| GPU baseline，可选 CUDA/OpenCL/CuPy | 评估与通用 GPU 的真实差距 |

统一指标：

```text
candidate_eval_per_second
end_to_end_latency_ms
energy_per_candidate，可选
best_fitness_vs_time
time_to_first_valid_solution
```

只有在这些指标实测后，才能严肃声明 FPGA 相对 GPU 的优势或劣势。

---
## 14. 风险与待确认问题

### 14.1 技术风险

1. **受限四体恒纪元搜索空间巨大**  
   解决：初版采用 2D、质心系消元、预设搜索空间、可选 seed population。

2. **测试行星增加计算量**  
   解决：行星质量可忽略，不反向影响太阳；计算量约为 pure3 的 1.5x~2x；若资源/时序不满足直接退化 pure3。

3. **长期恒纪元需要很长积分时间**  
   解决：PL 初版用有限时间窗找候选解，再由 PC 软件参考模型做更长时间复验。

4. **定点误差与混沌敏感性**  
   解决：Q16.16 初版验证可行性；必要时局部模块提高精度或使用分段缩放。

5. **恒纪元 fitness 指标可能过度简化**  
   解决：初版使用硬件友好的主导太阳、宜居距离、光照波动、潮汐阈值和持续窗口；后续再增强物理模型。

6. **资源超限**  
   解决：优先尝试 restricted4_2lane；若不满足，可尝试 restricted4_1lane；若仍不满足，直接 pure3 fallback，保留 GA 硬件闭环优势。

### 14.2 用户审核结论与当前决策

1. 工程目标已改为：**搜索稳定/恒纪元初始条件**，而不是验证单个固定初始条件。**（用户回答：是）**
2. 初版接受“质量固定，位置/速度搜索”的设定。**（是）**
3. 初版接受太阳三体“质心系约束编码”：编码 sun0/sun1，sun2 由质心和总动量约束推导。**（是）**
4. 初版稳定目标改为：**主线采用“三颗太阳 + 一个质量可忽略测试行星”的受限四体恒纪元搜索**。恒纪元评分优先于单纯 bounded/periodic/quasi-periodic。**（根据本轮讨论更新）**
5. 初版先做 2D 搜索，跑通后再开放完整 3D 搜索。**（是）**
6. 必须保留纯三体稳定性搜索作为退化方案：如果受限四体在 ZYNQ-7020 上资源/时序不满足，直接退化 pure3。**（本轮新增确认）**

## 15. 版本路线

### v0.1：规格草案（已完成）

- 初次整理 PS+PL GA 加速系统。

### v0.2：规格修订（已完成但目标存在偏差）

- 扩充并行评估、硬件选择、寄存器和 PC+PS+PL 拓扑。
- 但仍偏向“固定初始状态下的轨迹检查点搜索/验证”。

### v0.2.2：目标修正版（已完成）

- 明确本项目目标为“从初始条件空间中搜索稳定三体运动解”。
- 删除旧主线中的固定 `S0` + 轨迹检查点个体设定。
- 将个体编码改为候选初始条件。
- 将 fitness 改为稳定性评估。

### v0.2.3：恒纪元目标修正版（当前）

- 初版主目标改为“三颗太阳 + 一个质量可忽略测试行星”的受限四体模型。
- 搜索能产生长恒纪元窗口的初始条件。
- 修改恒纪元 fitness：行星生存、主导太阳捕获、宜居距离、光照波动、潮汐风险、恒纪元持续时间。
- 更新数据包、寄存器、PL 模块、资源估算、Web API 和验证计划。
- 明确保留 pure3 纯三体稳定性搜索作为资源不足时的退化方案。
- 仍不编写 RTL/PS/后端/前端代码。

### v0.3：RTL 实现与 7020 资源验证（已完成阶段性实现）

- 已实现 restricted4 恒纪元搜索核心 RTL，但完整配置在 xc7z020 上资源严重超限，保留为后续架构优化主线，不作为当前上板版本。
- 完成 `sun3_integrator`、`test_planet_integrator`、`heng_era_metric_accumulator`、`pure3_fallback_fitness_lane`。
- 完成 fitness lane、选择、交叉、变异、AXI DMA 接口。
- 已完成模块级和顶层仿真；当前可布线版本为 1-lane pure3 resource-fit fallback。

### v1.0：最小可实现版本（硬件闭环与寄存器探针已完成）

- 已生成并验证 `ga3b_v1_min.bit`、`ga3b_v1_min.xsa`，目标器件为 `xc7z020clg400-2`。
- 已完成 PS7 + AXI DMA + AXI4-Lite + pure3 PL 顶层连接、综合、布局布线和 DRC。
- 100 MHz post-route 时序通过：WNS `+0.410 ns`、TNS `0`；LUT 使用率 `63.35%`。
- 已提供 standalone `ga3b_dma_smoke.c` 和 Linux `/dev/mem` 只读寄存器探针。
- 已通过 SSH/SCP 在领航者 V2 开发板使用 FPGA Manager 动态加载 bitstream；寄存器实测 `version=0x00010000`、`profile=0x00000003`，输出 `GA3B_REG_PROBE_PASS`。
- 已通过 XSCT API 从 XSA 创建 `ga3b_v1_platform`、`standalone_domain` 和 `ga3b_dma_smoke` 应用工程；BSP 已生成并包含 AXI DMA 驱动。
- 已使用 Vitis 生成的 BSP、链接脚本与 ARM bare-metal 工具链完成 ELF 编译验证：`ELF32 ARM`，入口 `0x00100000`，输出 `GA3B_VITIS_BUILD_PASS`。
- 已于 2026-08-10 通过 JTAG/XSDB 下载 bitstream 和 standalone ELF，并由 COM12 自动捕获到 `GA3B_DMA_SMOKE_PASS`。实测结果头为 `0x52534C54`，`steps=16`，未出现 DMA timeout 或协议错误。
- 尚待完成：固定 seed 的多次重复性/结果一致性测试；随后可选择 standalone board_agent 路线，或实现 Linux DMA 驱动/UIO 与常驻 board_agent，完成 PC -> PS -> PL -> PS -> PC 端到端测试。

### v1.1：Web 演示版本（已完成 Pure3 最小闭环）

- 已完成 Windows Flask Host Backend、UART 单实例所有权与断线重连。
- 已完成同源 HTTP API：健康检查、自检、搜索和性能探针。
- 已完成 2D Canvas 三体轨迹动画、搜索参数输入、返回基因和板端指标展示。
- 已完成 FPGA 端到端、朴素 Python 与 NumPy 批处理三类性能探针。
- 当前展示严格对应 7020 上的 Pure3 resource-fit fallback；受限四体行星动画留待资源优化版实现。

### v2.0：性能优化版本

- 多 fitness lane。
- 更高精度 fixed-point/invsqrt。
- 更长时间恒纪元评估。
- 3D WebGL/Three.js 可视化。
- 更复杂的光照/潮汐/气候近似模型。

---

## 16. v1.0 板级部署、Vitis 自动化与下一阶段

### 16.1 当前板级环境与已验证事实

- 开发板：正点原子领航者（V2）ZYNQ-7020，器件 `xc7z020clg400-2`。
- SSH 入口：主机别名 `zynq`，当前 Linux 为 `Linux 5.4.0-xilinx-v2020.2`，ARMv7。
- FPGA Manager：`/sys/class/fpga_manager/fpga0`，加载后状态为 `operating`。
- Linux 镜像原设备树把 `0x43C00000` 声明为 Digilent AXI PWM；加载 GA3B 前必须从 `dglnt-pwm` 驱动解绑，避免旧驱动访问 GA3B 寄存器。
- Linux 在线探针只验证 AXI4-Lite 可达性、版本和 profile，不等价于 AXI DMA 数据通路验证。

板端探针实测：

```text
FPGA_STATE=operating
GA3B register probe: base=0x43c00000 version=0x00010000
profile=0x00000003 status=0x00000100 raw=0x00000000
GA3B_REG_PROBE_PASS
```

### 16.2 可交付文件

```text
vivado/runs/v1_min_bd/artifacts/ga3b_v1_min.bit
vivado/runs/v1_min_bd/artifacts/ga3b_v1_min.xsa
vivado/runs/v1_min_bd/artifacts/ga3b_v1_min.bit.bin
vivado/runs/v1_min_bd/artifacts/ga3b_reg_probe
ps_app/board_agent/linux/ga3b_reg_probe.c
ps_app/board_agent/standalone/ga3b_dma_smoke.c
ps_app/board_agent/standalone/ga3b_uart_board_agent.c
ps_app/host_backend/ga3b_uart_client.py
scripts/vitis/create_v1_min_standalone.tcl
scripts/run/build_v1_min_standalone.ps1
scripts/run/build_v1_uart_board_agent.ps1
vitis_workspace/v1_min_standalone/ga3b_dma_smoke/ga3b_dma_smoke.elf
vitis_workspace/v1_min_standalone/ga3b_uart_board_agent/ga3b_uart_board_agent.elf
```

其中 `.bit.bin` 由 Bootgen `-arch zynq -process_bitstream bin` 生成，供 Linux FPGA Manager 使用；`.xsa` 供 Vitis/XSCT 创建 standalone 平台和 BSP。

### 16.3 Vitis API/CLI 自动化要求

Vitis 工程不要求手工点击 GUI。Vitis 2023.2 可使用 XSCT Tcl API 完成：

1. 从 `ga3b_v1_min.xsa` 创建 `ps7_cortexa9_0 + standalone` 平台；
2. 生成 BSP 和启动域；
3. 创建 Empty Application；
4. 导入 `ga3b_dma_smoke.c` 与 `ga3b_protocol.h`；
5. 编译并检查 ELF 是否生成；
6. 后续通过 XSDB/JTAG 下载 bitstream、初始化 PS、下载 ELF 并运行。

自动化入口为：

```powershell
& "<Vitis>/2023.2/bin/xsct.bat" scripts/vitis/create_v1_min_standalone.tcl
```

Vitis workspace 属于可再生输出，不应作为核心源代码提交；应提交 XSA 生成脚本、XSCT Tcl、C 源码及测试结果摘要。

本机 Vitis 2023.2 的 Eclipse workspace 服务在一次被外部超时中断后出现过 `Invalid Workspace`；清理生成 workspace 后，平台/API 创建可恢复。为降低 Eclipse 服务的不确定性，当前还提供 `scripts/run/build_v1_min_standalone.ps1`：它直接复用 XSCT 已生成的 BSP、`libxil.a`、`lscript.ld` 与 `Xilinx.spec` 完成确定性 ELF 编译。

### 16.4 下一阶段验收顺序

1. **Standalone DMA smoke test（已通过）**：JTAG/XSDB 下载并运行 Vitis 生成的 ELF，COM12 实测输出 `GA3B_DMA_SMOKE_PASS`。
2. **DMA 结果一致性**：将板端 14-word SearchResult 与 RTL testbench/软件参考模型逐字段比较。
3. **重复性与稳定性**：固定 seed 连续运行至少 100 次，要求无 DMA timeout、协议错误或结果漂移。
4. **Linux 正式接入**：为当前 Linux 设备树增加 GA3B、AXI DMA、reserved-memory/UIO 或正式内核驱动节点；不要用 `/dev/mem` 实现生产 DMA。
5. **board_agent**：实现本地 PS 常驻服务，一次加载 PL 后接受多个搜索任务，避免每个任务重新配置 FPGA。
6. **PC 端到端**：完成 PC -> SSH/TCP -> board_agent -> DMA -> PL -> DMA -> board_agent -> PC 闭环。
7. **性能基线**：记录单任务延时、候选评估吞吐、首次有效解时间，并与 CPU/GPU baseline 对比。

当前 v1.0 状态定义为“bitstream、AXI4-Lite 板级探针及 standalone DMA 单次 smoke test 已通过；重复性、软件参考一致性与 PC 全栈验收待完成”。单次 smoke test 通过不得表述为完整算法端到端验证全部完成。

### 16.5 Standalone UART 常驻 board_agent（2026-08-11）

为避免每次搜索都通过 JTAG 重新下载 ELF，并为 PC 后端/Web 前端提供稳定的板端边界，新增常驻 bare-metal UART board_agent：

- 板端源码：`ps_app/board_agent/standalone/ga3b_uart_board_agent.c`；
- PC 串口传输客户端：`ps_app/host_backend/ga3b_uart_client.py`；
- 确定性构建入口：`scripts/run/build_v1_uart_board_agent.ps1`；
- 构建产物：`vitis_workspace/v1_min_standalone/ga3b_uart_board_agent/ga3b_uart_board_agent.elf`。

第一版采用 115200-8-N-1 ASCII 行协议，板端支持：

```text
PING
INFO
STATUS
RESET
SELFTEST
RUN <max_gen> <steps> <mutation_q16> <crossover_q16> <seed0> <seed1>
```

响应统一以 `GA3B_RSP OK` 或 `GA3B_RSP ERR` 开头。`RUN`/`SELFTEST` 经 AXI DMA 调用 PL，返回 fitness、steps 和 8 个 pure3 gene。该协议是 PC 后端接入前的传输层，不是最终 HTTP API；后续 Flask/FastAPI 只需把搜索作业映射为串口命令并解析响应。

本地 ARM GCC 构建已于 2026-08-11 通过。更换连接线并重新插拔后，JTAG 已恢复，可枚举 `APU`、两个 Cortex-A9 与 `xc7z020`。随后完成一次 bitstream/新 ELF 下载：`PING`、`INFO` 和第一次 DMA `SELFTEST` 均通过，但第二次相同固定 seed 的 `SELFTEST` 出现 best chromosome 漂移；fitness 与 steps 保持一致。100 次验收因此在第 2 次停止，详见 `doc/test_results/2026-08-11_v1_uart_board_test_fail.md`。

该次失败把故障边界集中到重复任务状态、BRAM 读取与结果包握手，而不是 JTAG、UART 基本通信或 DMA 首次可达性。后续修复与最终验收见 16.6；本段保留为历史故障记录。

USB 串口号不是稳定接口标识，脚本和 PC 后端必须允许通过参数指定端口，不能硬编码 `COM12`。

### 16.6 连续任务修复、100 次验收与设计契约（2026-08-11）

重复任务漂移已定位并修复：

1. population BRAM 的上层地址寄存器与 RAM 输出寄存器构成两拍读延迟，原 FSM 少等待一拍；现已为评估读取和繁殖父代读取增加显式 wait 状态。
2. 结果包结束后 `TREADY` 尚低的第一个 `IDLE` 周期，原 RTL 仅依据 `TVALID` 提前消费下一任务 magic；现已强制所有 AXI-Stream beat 仅在 `TVALID && TREADY` 时转移。
3. pure3 顶层 testbench 现连续发送两个完全相同任务且中间不复位，逐字比较两个 14-word SearchResult。

验证结果：

```text
RTL: TB_PASS pure3_rf_repeat, 14/14 words identical
Post-route: 100 MHz, WNS +0.296 ns, TNS 0
Utilization: LUT 33705 (63.36%), FF 24528 (23.05%), BRAM 2 (1.43%)
DRC: 0 errors
Board: fixed seed 100/100 PASS, no timeout/protocol error/result drift
```

机器可读板测结果为 `doc/test_results/v1_uart_soak_latest.json`，完整记录为 `doc/test_results/2026-08-11_v1_uart_repeatability_pass.md`。

已生成：

```text
vivado/runs/v1_min_bd/artifacts/sd_boot/BOOT.BIN
```

Bootgen 已确认该镜像按顺序包含 FSBL、新 bitstream 和 UART board_agent ELF。SD 断电冷启动与免 JTAG 运行已于 2026-08-11 完成板级验收，结果见 16.7。

本工程从本节起以 `doc/design_contract.md` 为规范性硬件契约。契约至少覆盖 AXI `valid && ready`、同步 BRAM 显式延迟、连续任务可重入、固定 seed 确定性、Vivado OOC 缓存来源和 100 次板级验收。单次 smoke test 不再允许作为完整可重入验收。

### 16.7 SD 物理冷启动与全栈基础验收（2026-08-11）

开发板已在 `BOOT_CFG=OFF/OFF`、FAT32 Micro SD 根目录放置当前 `BOOT.BIN` 的条件下完成真实断电冷启动；测试过程中不依赖 JTAG 下载。冷启动后，PC 通过 COM13、115200-8-N-1 与常驻 UART board_agent 通信，并对固定 seed 连续执行 100 次 `SELFTEST`：

```text
GA3B_UART_SOAK_PASS
iterations: 100
elapsed_seconds: 2.760201
average_seconds: 0.027602
fitness: 0x00000001_00000010
steps: 16
result drift / DMA timeout / protocol error: 0
```

机器可读记录为 `doc/test_results/v1_sd_boot_uart_soak.json`，人工验收摘要为 `doc/test_results/2026-08-11_v1_sd_cold_boot_pass.md`。

该结果确认以下全栈构建基础已经成立：

```text
SD -> FSBL -> PL bitstream + bare-metal board_agent
PC -> UART -> PS board_agent -> AXI DMA -> pure3 PL -> AXI DMA -> PS -> UART -> PC
```

该结果本身不等同于 Web 全栈完成；随后实现并验收的 v1.1 HTTP/Web 闭环见第 17 节。运行时 Micro SD 应保留在板上用于冷启动；JTAG 仅用于调试和重新下载，不是正常运行依赖。当前 bare-metal 镜像不提供 Linux/SSH。

### 17. v1.1 PC HTTP 后端与 Web 演示（2026-08-11）

v1.1 已在不修改 SD 卡 bare-metal 镜像的前提下完成。PC 后端独占 USB UART，并把板端 ASCII 协议映射为同源 HTTP API：

```text
GET  /api/health
POST /api/selftest
POST /api/search
POST /api/performance/probe
```

实现文件：

```text
ps_app/host_backend/ga3b_api.py
ps_app/host_backend/ga3b_service.py
ps_app/host_backend/ga3b_models.py
ps_app/host_backend/ga3b_reference.py
web/templates/index.html
web/static/styles.css
web/static/app.js
scripts/run/run_v1_web_demo.ps1
```

Web 前端提供开发板在线状态、搜索参数、板端自检、最优基因、fitness、存活步数、候选吞吐和 Canvas 三体轨迹动画。动画不是 PL 内部状态的实时采样，而是使用 FPGA 返回的 8 个 Q16.16 初始条件，按 `ga3b_pure3_rf_fitness_lane.v` 的近似力、非阻塞更新顺序、碰撞和逃逸阈值在 PC 端确定性重放；第三颗太阳由质心和总动量约束推导。

启动入口：

```powershell
.\scripts\run\run_v1_web_demo.ps1 -Port COM13
```

浏览器入口为 `http://127.0.0.1:8000/`。后端运行期间，不允许其它串口终端或脚本同时占用 COM13。

实板 HTTP 端到端验收已通过：`/api/health` 正确识别 `version=0x00010000`、`profile=0x00000003`；`/api/search` 在 256 步任务中返回 256/256 存活轨迹，端到端约 31.58 ms。测试记录见 `doc/test_results/2026-08-11_v1_1_fullstack_pass.md`。

性能探针必须遵守如下计量边界：

- FPGA：完整 GA 初始化、32 个体、多代评估、选择/繁殖、AXI DMA 与 UART 往返；
- Python scalar：对 FPGA 返回染色体执行同款定点 fitness 的串行工作负载代理；
- NumPy batch：相同 fitness 工作负载的批量向量化代理。

后两者没有执行与 RTL 完全相同的 GA 选择/繁殖，因此只能作为软件计算压力探针，不能直接宣称为算法等价 speedup。实测 `max_gen=2, steps=1024` 时，FPGA 完整端到端约 36.23 ms / 2649 eval/s，Python scalar 约 1180.07 ms / 81 eval/s，NumPy batch 约 192.87 ms / 498 eval/s。在很短的 16-step 任务中，UART 固定开销会使 FPGA 不占优势；该交叉现象必须保留并如实展示。

### 18. v1.1.1 多目标轨道选择、自定义初态与 UI 重构（2026-08-11）

前端提供四套具有明确判据的轨道目标：

| profile | 物理含义 | 判据摘要 | 默认硬件候选数 |
|---|---|---|---:|
| `survival` | 长时生存 | 无碰撞、无逃逸并完成窗口 | 1 |
| `close_pass` | 安全擦掠 | 完整存活，至少一次 0.25–1.25 距离的安全近掠 | 6 |
| `braid` | 三星纠缠 | 存活、绕质心转角、角序换位与紧凑驻留 | 8 |
| `recurrence` | 近周期回归 | 完整存活、末态构型接近初态且尺度漂移较小 | 8 |

当前 SD 镜像中的 PL 仍只实现 `survival` fitness。为避免把软件标签伪装成新的硬件能力，其余目标采用兼容的 multi-start 流程：后端用派生 seed 执行多次真实 FPGA GA 搜索，再用 RTL 同规则轨迹重放计算近掠次数、最小间距、绕转角、换位次数、紧凑驻留率、回归误差和径向漂移，按所选目标重排。响应必须返回 `profile_match`；若最佳候选仍未满足目标判据，前端明确显示“仅为当前候选中的最优近似”，不得显示为目标已达成。

新增接口：

```text
GET  /api/capabilities
POST /api/estimate
POST /api/custom-replay
```

HTTP 服务限制为 `max_gen<=256`、`steps<=65536`、单次 multi-start 候选数 `<=16`、预计同步请求不超过 600 秒。前端在估算完成前禁用提交；后端再次执行相同约束，客户端校验不能作为安全边界。四类长轨迹演示推荐使用 `32768 steps`；`65536` 是请求上限，但不会消除当前积分器约 2.1–2.2 万步后常见的逃逸。

自定义初态接受 `x0,y0,vx0,vy0,x1,y1,vx1,vy1`，太阳 2 由等质量质心和总动量约束推导。输入位置限制为 `[-2,2]`，速度限制为 `[-1,1]`，初始任意两体 L1 距离不得低于 RTL 碰撞阈值 0.125，自定义步数不超过 131072，预计 PC 同步计算不超过 2 秒。由于当前 UART/任务协议不能将单条染色体直接注入 fitness lane，自定义模式明确标记为 `PC RTL-COMPATIBLE REPLAY`，不能标记为 FPGA 执行。

UI 视觉基线参考 NASA Eyes 的沉浸式深空视图、仪器化信息层次和面向公众的交互式探索方式，但不复制其标识、图像或页面资产。新版采用全屏深空画布、半透明任务控制台、目标卡片、底部遥测、质心准星和统一青蓝/琥珀/紫色天体编码。新增 0.25×、0.5×、1×、2×、4×、8× 播放速度。

已知科学限制：当前 GA 初始化表达式仍对搜索下界有偏置，PL 力模型也是为 7020 资源适配的分段近似；经典牛顿三体 8 字初态在该近似模型中不能保证长期周期。下一硬件版本应先修复全范围均匀初始化，再把至少 `close_pass`/`braid` 的累积指标下沉到 RTL fitness，之后才能把四套目标称为四套原生 FPGA fitness。

#### 18.1 事件高亮窗口与网页内帮助

完整长轨迹中的后期背离会扩大画布尺度，使早期近掠或纠缠几乎不可见。后端现从最多 720 个完整重放采样帧中选择最多 240 个连续帧作为展示窗口：`close_pass` 优先覆盖安全近心点，`braid` 优先覆盖绕转和紧凑段，`recurrence` 优先覆盖局部回归段，`survival` 优先覆盖有界且具有运动量的区段。窗口不重排帧、不删除中间物理时间，也不修改完整 fitness、存活步数或目标判据。前端必须显示 `HIGHLIGHT start-end / FULL start-end`，且允许点击标签切换完整轨迹与高亮窗口，防止把高亮片段误认为完整稳定窗口。

顶部导航现具备真实行为：轨道实验滚动到主视图，性能遥测滚动到性能探针，系统信息读取 `/api/health` 与 `/api/capabilities` 并显示板卡/服务限制，使用指南打开网页内 README。网页 README 必须说明后端启动、目标含义、承载估算、高亮窗口、目标吻合、自定义初态和静态页面无法直接访问 FPGA 的排障方式。

#### 18.2 v1.1.2 结果库、模范解与有限窗口分类

后端将每次 FPGA 搜索和 PC 自定义重放自动保存到本地 SQLite：`doc/test_results/ga3b_results.sqlite3`。新增接口为 `GET /api/results`、`GET /api/results/<id>`、`GET /api/presets` 和 `POST /api/presets/<id>/run`。数据库属于运行数据并由 Git 忽略；四套模范解定义保存在受版本控制的 `ps_app/host_backend/presets/trajectory_templates.json`。

模范解均来自 2026-08-11 的真实板端 32768-step 扫描，固定输入 seed、演化参数和窗口。点击“上板复现”会再次发送 `RUN`，并非播放静态伪造结果。分类器按末态回归误差/径向漂移、累计绕转/角序交换、安全近掠次数和实际生存步数依次判定 `near_recurrence`、`three_body_braid`、`safe_close_pass`、`long_survival`。这些是可审计的有限窗口现象标签；特别是当前“近周期回归”只是四类候选中最接近回归的近似，不得宣称为严格周期解。

前端不再向普通用户显示十六进制。位置和速度显示为 Q16.16 解码后的有符号十进制物理量，并附带有符号 Q16 整数；fitness 显示为无符号 64 位十进制；mutation/crossover 输入为十进制 Q16 概率，概率等于输入值除以 65536；seed 显示为有符号十进制，在服务端按相同 32 位二进制补码送入 FPGA。

实板参数扫描结论：12 组 32768-step 搜索的最佳染色体生存约 20886–21902 步；另 16 组 65536-step 搜索仍在约 21099–22126 步终止。提高请求窗口只允许观察更晚的失败，不会自动修复当前显式积分和分段力近似的能量漂移。原始记录见 `doc/test_results/v1_template_scan_32768.json` 与 `doc/test_results/v1_template_scan_65536.json`。

性能探针采用与长轨迹搜索解耦的标准交互负载：前端固定提交 `max_gen=8, steps=8192, hardware_runs=2` 和固定 seed；后端硬限制为最多 8 代、8192 步和 3 次板端采样。该规模应在真实 7020 板上形成可见的 FPGA 吞吐优势，同时保持典型墙钟时间在约 10 秒以内；不得直接继承 32768/65536 步页面参数。探针按钮必须提供运行中、成功和失败状态，并展示每个探针的 eval/s、实际耗时和 FPGA 相对软件吞吐倍数。初始条件和轨迹指标必须实现为可切换页签，不能只使用无事件的视觉按钮。

### 18.3 缓存加速度 Leapfrog 与均匀 GA 初始化的 P1 集成（2026-08-15）

P1 硬件交付物已切换为高精度平滑力、辛积分 LUT 和缓存加速度 Leapfrog，硬件 profile 为 `5`。GA 初代种群不再使用“下界加 16 位有符号扰动”，而采用全 32 位 PRNG 的无偏区间映射：

```text
gene = min + floor((max - min) * random_u32 / 2^32)
```

个体 0 仍保留为区间中点，个体 1～31 在每个基因的完整 `[min,max)` 范围内均匀初始化。该乘法只处于初始化路径，不改变 fitness lane 的逐步积分顺序。板端协议新增并固化：`3=legacy pure3_rf`、`4=高精度辛 Euler`、`5=高精度缓存 Leapfrog`。新版 board agent 只接受 profile 4/5，本轮生成的镜像必须报告 profile 5；检测到旧 profile 3 时必须拒绝启动 DMA 服务，避免软硬件版本错配。

本地验证结果：

```text
uniform-init TB: PASS（gene0 低四分位 4 个，高四分位 7 个）
cached-Leapfrog AXI 双任务 TB: PASS（14/14 words 一致）
100 MHz setup WNS: +0.539 ns，TNS: 0
100 MHz hold WHS: +0.057 ns，THS: 0
DRC: 0 errors
LUT: 12304 / 53200 (23.13%)
FF: 9027 / 106400 (8.48%)
BRAM: 6 / 140 (4.29%)
DSP: 13 / 220 (5.91%)
```

新 XSA 已用于重建 standalone BSP 和 UART/DMA board-agent ELF，随后与 FSBL、profile-5 bitstream 一起重建：

```text
vivado/runs/v1_min_bd/artifacts/sd_boot/BOOT.BIN
```

本节的板级门槛已于 2026-08-15 通过：Micro SD 物理冷启动后 `INFO` 报告 `profile=0x00000005`，`PING`、`SELFTEST` 均通过，固定结果的 UART/DMA soak 为 100/100。详细全栈同步与验收见 18.4。

### 18.4 Profile-5 板级验收与 v1.1 全栈同步（2026-08-15）

板级验收结果：

```text
PING: PONG
INFO: protocol=1 version=0x00010000 profile=0x00000005 status=0x00000100 raw=0
SELFTEST: PASS
UART/DMA soak: 100/100 PASS, 2.903431 s, average 0.029034 s
RUN(max_gen=1, steps=100000): valid result, survived_steps=3667
```

最后一项只证明 100000 步请求、DMA 和新积分 lane 可以执行；它没有找到 100000 步稳定解，不能被解读成十万步科学目标已经完成。对该染色体的 Profile-5 PC 重放同样在 3667 步因逃逸终止，证明本次短生存并非前端旧积分器造成的显示漂移。

v1.1 后端与 Web 已同步到硬件 profile 5：

- v1.1 全栈健康检查要求 profile 5，并显示 `pure3_hifi_leapfrog_cached`；profile 4 只保留为板端回退，不得与缓存 Leapfrog 前端混用；
- 搜索结果采用 Q32.32、平滑力 LUT、缓存加速度 Leapfrog 的 PC 同规则重放；
- 每次搜索返回 FPGA/PC `survived_steps` 一致性探针；
- 自定义初态明确标为 `PC PROFILE-5 LEAPFROG REPLAY`，不冒充 PL 直接执行；
- 搜索积分上限为 131072；
- 四个演示模板均替换为 profile-5 实板固定 seed/染色体，并检查精确复现；
- 性能探针改用 Profile-5 标量参考与 float64 NumPy Leapfrog 代理，页面明确标注比较边界。

四个模板在实板上再次扫描，均满足：固定染色体一致、硬件/PC 生存步数一致、完整运行 32768 步。分类分别为长时生存、安全擦掠、三星纠缠和近周期回归；这些都是有限窗口演示标签，不构成无限稳定或严格周期证明。

标准 HTTP 性能探针（288 candidates，8192-step cap，2 次硬件采样）：

```text
Zynq-7020 FPGA complete GA+DMA+UART: 264.15 eval/s, 1090.30 ms
Python scalar Profile-5 reference:     4.12 eval/s, 69959.41 ms
NumPy float64 batch proxy:            159.37 eval/s, 1807.17 ms
```

因此该探针下 FPGA 完整链路约为标量参考的 64.2 倍、NumPy 代理的 1.66 倍。两条软件路径不含 GA 选择/繁殖和传输，NumPy 也不与 LUT 位精确等价，所以该结果只能作为当前有界工作负载的端到端诊断，不得外推为通用加速比。

验收记录：

```text
doc/test_results/v1_hifi_leapfrog_sd_soak.json
doc/test_results/v1_profile5_preset_scan.json
doc/test_results/v1_profile5_performance_probe.json
```
