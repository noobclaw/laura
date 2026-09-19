# 参考保真审计(G8c 底稿)— OhmBench

> 本轮(2026-09-19,G2)覆盖的是**引擎**部分。编辑器部分(`circuitjs1`)只取交互规格,数字逻辑(`digitaljs`)M3 才读。
> 提审前须把「剩余」一栏清零(PIPELINE G8c 第 5 条)。

| 参考仓 | 许可证 | 本地位置 | 函数数 | 一致 | 有意偏离 | 漏掉→已补 | 剩余 |
|---|---|---|---|---|---|---|---|
| `SpiceSharp/SpiceSharp` | **MIT**(可移植 + 署名) | `D:\toolapp\_ref\SpiceSharp` | 7 | 5 | 2 | 0 | **2**(见下,均为 M2 项) |
| `sharpie7/circuitjs1` | **GPL-2.0**(只读规格,不复制代码) | `D:\toolapp\_ref\circuitjs1` | 2 | 0 | 2 | 0 | 0 |
| `tilk/digitaljs` | BSD-2 | 未克隆 | — | — | — | — | M3 |

---

## 一、SpiceSharp(MIT)— 逐条对照

### 1. `BiasingSimulation.IsConvergent()` → `CircuitSolver._converged`

| 项 | 原实现 | 我方 |
|---|---|---|
| 输入 | 本次解 / 上次解,按未知量类型分流 | 同 |
| 判据 | 电压量 `|n-o| > RELTOL*max(|n|,|o|) + VNTOL` 即未收敛;其余量用 `ABSTOL` | 同 |
| 常量 | RELTOL 1e-3 / VNTOL 1e-6 / ABSTOL 1e-12 | **逐字相同** |
| NaN | 抛异常 | **有意偏离**:返回「未收敛」。手机 app 不该因为用户画了个奇怪电路就崩;异常在这里没有接收者 |
| 精度 | double | 同 |

**实现**:`lib/tool/engine/solver.dart:_converged`。**一致(含一处有意偏离)**。

### 2. `Semiconductor.LimitJunction()`(= ngspice `DEVpnjlim`)→ `CircuitSolver._limitJunction`

| 项 | 原实现 | 我方 |
|---|---|---|
| 触发 | `vnew > vcrit && |vnew - vold| > 2*vte` | 同 |
| 正向分支 | `vold>0` 时 `arg=(vnew-vold)/vte`;`arg>0` → `vold+vte*(2+ln(arg-2))`,否则 `vold-vte*(2+ln(2-arg))` | **逐字相同**(并写下了「外层条件保证 `arg>0 ⟹ arg>2`,对数恒为实数」这一推理) |
| `vold<=0` 分支 | `vte*ln(vnew/vte)` | 同 |
| 负向分支 | `vnew<0` 时下界 `-vold-1`(vold>0)或 `2*vold-1` | 同 |
| `limited` 回传 | `ref bool check`,置位则本次迭代不算收敛 | **有意偏离(M2 待补,见剩余①)**:我方目前不把「本次限过压」回灌成「未收敛」。影响:限压生效的那一步可能被容差判成已收敛,理论上少一次迭代。实测 3.4e-6 V 误差,尚未观察到坏例,但**这是原实现里一条真实的安全带** |

**实现**:`solver.dart:_limitJunction`。

### 3. `Diodes/Biasing.Load()` → `CircuitSolver._loadDiode`

| 项 | 原实现 | 我方 |
|---|---|---|
| 三分支 | `vd >= -3*Vte` 正偏 / 无击穿或 `vd >= -BV` 反偏 / 击穿 | **逐字相同** |
| 正偏 | `cd = Is*(e^{vd/Vte}-1) + gmin*vd`;`gd = Is*e^{vd/Vte}/Vte + gmin` | 同 |
| 反偏 | `arg = (3*Vte/(vd*e))³`;`cd = -Is*(1+arg)+gmin*vd`;`gd = Is*3*arg/vd + gmin` | 同(含 `arg` 三次方这一步) |
| 击穿 | `evrev = e^{-(BV+vd)/Vte}` | 同 |
| 伴随源 | `cdeq = cd - gd*vd`,四角 `gd` + RHS `±cdeq` | 同 |
| 串联电阻 | 内部节点 `posPrime`,`gspr = 1/RS` | 同(`RS>0` 时才分配内部节点) |
| 并联/串联倍数 `m`/`n` | 支持 | **有意偏离**:M1 不做器件倍数,单器件单实例。用户在手机上画两个二极管比填一个参数快 |
| 初始化 | `IterationModes.Junction` 时 `vd = Vcrit` | 同(首次牛顿迭代用 `Vcrit`) |
| `Vcrit` | `Vte*ln(Vte/(√2*Is))` | **逐字相同** |
| 温度模型 | `Temperature.cs` 全套(带隙、结电容、`Is` 温漂) | **有意偏离(剩余②)**:我方只取 `Vt = k/q*T`、`Vte = N*Vt`、`Vcrit`,**不做温度扫描**。M1 固定 300.15K(SPICE 标称 27°C)。M2 若加温度参数须补 `Is` 的温漂式 |

**实现**:`solver.dart:_loadDiode` / `_diodeCurrent` / `netlist.dart:DiodeModel`。

### 4. `BiasingSimulation.IterateGminStepping()` → `CircuitSolver._gminStepping`

| 项 | 原实现 | 我方 |
|---|---|---|
| 起点 | `gmin<=0` 时取 1e-12,再 `*10` 共 `steps` 次 | 同(`gmin * 10^steps`,默认 steps=10 → 1e-2) |
| 迭代 | 每步解一次,解作为下一步初值;任一步失败即整体失败 | 同 |
| 收尾 | 还原原 gmin 再解一次 | 同 |
| 对角 gmin 变体 | `IterateDiagonalGminStepping` | **有意偏离**:未实现。它是前者失败后的第二道,我方用「源阶梯」顶上;两者在 SPICE 里本就是可选项 |

### 5. `BiasingSimulation.IterateSourceStepping()` → `CircuitSolver._sourceStepping`

因子 `step/steps` 从 0 升到 1,逐步解、以上一步为初值 —— **一致**。

### 6. `Trapezoidal.Instance.DerivativeInstance` 系数 → 电容/电感伴随模型

| 阶 | 原系数 | 我方 |
|---|---|---|
| 1(后向欧拉) | `1/delta`,`-1/delta` | 首步用:电容 `Geq=C/h, Ieq=Geq*v_{n-1}`;电感 `Req=L/h, Veq=-Req*i_{n-1}` |
| 2(梯形) | `1/delta/(1-xmu)`,`xmu/(1-xmu)`,`xmu=0.5` | 之后用:电容 `Geq=2C/h, Ieq=Geq*v_{n-1}+i_{n-1}`;电感 `Req=2L/h, Veq=-(Req*i_{n-1}+v_{n-1})` |

**一致**(`xmu=0.5` 展开即 `2/h`)。**有意偏离**:原实现有变阶 + 局部截断误差变步长(`SpiceMethod` + `NodeTruncation`),我方 M1 **固定步长**——见 PLAN §四(手机上可预测比自适应更重要),M2 补。

### 7. 矩阵求解 `SparseRealSolver` + `ModifiedNodalAnalysisHelper` → `MnaSystem.solve`

| 项 | 原实现 | 我方 |
|---|---|---|
| 结构 | 稀疏 + Markowitz 排序 + 预排序 | **有意偏离**:稠密 + 部分选主元。规模理由见 PLAN §四 |
| 奇异判据 | `AbsolutePivotThreshold = 1e-13` | **逐字相同**(`MnaSystem.pivotThreshold`) |
| 接地行 | 求解后把 0 号变量清零 | 同(接地节点索引 -1,根本不进矩阵) |

---

## 二、circuitjs1(GPL-2.0)— 只取规格,未复制任何代码

**声明:仅阅读其行为并写成下表规格,按规格用 Dart 从零实现;未复制任何一行代码,未移植任何资源文件。**

| 规格 | 原行为(读 `CirSim.java`) | 我方 |
|---|---|---|
| 栅格吸附 | `snapGrid(x) = (x + gridRound) & gridMask`,位运算吸附到 2 的幂栅格 | **有意偏离**:文档坐标本身就是整数格(`GridPoint`),吸附发生在像素→格的换算处(`SchematicGeometry.snap`),**存储层不存在未吸附的坐标** |
| 抓取半径 | `POSTGRABSQ = 25`(平方像素,即 5px 半径) | **有意偏离**:5px 是鼠标口径,手指按不中。我方 `kTouchRadiusPixels = 22`(Apple 44pt 目标的一半),且**按缩放换算成格**,缩放后手感不变 |
| 拖拽模式 | `MODE_DRAG_ALL / ROW / COLUMN / SELECTED / POST` 五种,靠菜单切换 | 我方不做模式切换(模式正是「找不到菜单」类差评的来源):点引脚=拉线,点元件=拖动,点空白=框选 |

---

## 三、剩余项(提审前须清零 → 目前 2 条,均已排进 M2)

1. **限压回灌收敛标志**:`LimitJunction` 置位 `check` 后,原实现强制该次迭代不算收敛。补法:`_loadDiode` 记录 `limited`,`_converged` 与之相与。
2. **二极管温度模型**:只有 `Vt/Vte/Vcrit`,没有 `Is` 温漂与结电容温漂。补法:按 `Diodes/Temperature.cs` 的式子实现,并加一条对照测试(同一器件 27°C 与 85°C 的 `Is` 之比)。

## 四、署名

- 「关于」页与 `store/listing.md` 须写:**Circuit engine algorithms ported from SpiceSharp (MIT), © 2017 svenboulanger.**
- `circuitjs1` 为 GPL-2.0,**仅按规格重写,未复制代码与资源**,因此不构成衍生作品,不署名、不引用其代码。
