# OhmBench — G2 spike 独立审计(2026-09-19,只读 agent)

> ✅ **2026-09-22 工厂轮:P0 + 全部 P1 已修,P2-7/8/10/11/12/14/15 已修**;每条都有回归测试(`test/engine/audit_regressions_test.dart`、`test/schematic/audit_regressions_test.dart`)。P2-9(gmin 阶梯单级失败即放弃)、P2-13(每次迭代分配 n²)、P2-16(电容白占支路)留到 M2 实测后再定。
> 审计确认为正确的部分:全部 MNA 戳记符号、二极管三段加载、`_limitJunction`、电容/电感两种积分的伴随模型、历史传递顺序、同一 `CircuitSolver` 先 `operatingPoint()` 再 `transient()` 的状态复用。

## P0

1. **主元阈值只有绝对判据,高阻电路被误判「悬空」,再被 1GΩ 兜底算出一个错得离谱却 `converged: true` 的数。**
   `linear_system.dart` `pivotThreshold = 1e-13` 直接比原始主元;SpiceSharp 永远配一个**相对**判据(`largest * 1e-3`)。
   触发:10V 源 + 两个 **1e14 Ω** 电阻分压 → 应为 5 V,实得 ≈1e-4 V,只带一个 `floatingNodesTiedToGround` 的提示。
   瞬态同病:**1 fF 电容 @ 10 ms 步长**(`geq = 1e-13`)波形读成一条平线。
   修:选主元与回代都改成 `best > largest * 1e-3 && best > 1e-300`;兜底电导须远小于电路里最小的真实电导,且这条路径必须带一个「答案可能被改变」的提示。

## P1

2. **牛顿可能只线性化一次就宣布收敛**:缺 SpiceSharp 的 `iterno != 1` 守卫。`start != null` 时第 1 次迭代的 `previous` 是别的上下文的种子。波及 gmin 阶梯每一级、以及**每一个瞬态步**(二极管陡然导通的那一步)。修:`_newton` 里收敛判定加 `iteration > 1`。
3. **限压从不否决收敛**:`LimitJunction` 的 `limited` 标志被丢掉 → 报出的节点电压与 `_deviceCurrents` 重算的肖克利电流不自洽(输出违反 KCL)。同时缺二极管的器件级电流收敛检验。(REFERENCE.md「剩余①」已记,此处升为 M1 前必修。)
4. **0 Ω 电阻在矩阵里导通(1e6 S),读数却硬报 0 A** → 屏幕上串联两电阻电流不等。修:两处共用一个常量。
5. **元件拖到导线上会被静默短路**:两脚都落在同一根线上 → 同节点,无任何提示。修:`NetlistBuild` 增 `shortedPartIds`,**不改 T 型接点规则**。
6. **非正元件值被静默改写**(`max(farads, 1e-18)`);负电阻直接戳负电导;`onResistance: 0` 戳出 Infinity。修:在网表边界校验并报诊断。

## P2

7. `OperatingPoint.iterations` 是假的(成功报 0)。 8. 兜底重试后 `singular`/`didNotConverge` 标签可能标错。 9. gmin 阶梯失败一级就整体放弃(原实现会 break 后再试一次);`gmin: 0` 时最后一级真跑在 0。 10. 两种阶梯兜底丢掉了 shunt,「悬空 + 硬结」的电路永远解不出。 11. 瞬态 t=0 用 `dcValue` 而非 `at(0)`,`phase=90°` 的正弦源会凭空阶跃。 12. **拖拽一过阈值就瞬移一整格(缩小时两格)**—— 正是本文件号称要治的「moving them seems impossible」;修:记下 arming 时的位移,对 `(delta − armingDelta)` 取整。 13. `solve()` 注释写「in place」实为拷贝;每次迭代分配 n² 个 double,有 GC 压力。 14. `copyWith` 无法清除 `valueOverride`。 15. `Infinity` 进 JSON 后整份文件读不回来 → 入口处 `isFinite` 守卫。 16. 每个电容白占一行支路未知量,M2 前实测。

## 测试质量(会在代码写错时照样通过的测试)

- 「反串二极管(源阶梯)」从不断言 `op.notes`,实际走的是直接牛顿 —— **`_gminStepping` / `_sourceStepping` 全套测试零覆盖**,而 P1-2、P2-9、P2-10 都在这段里。
- 「不是假零」断言 `abs() < 1e-6`,假零也能过;应对 `≈ -5.01e-12` 做双侧带。
- RC / RL / 放电三条一阶测试的容差**宽到删掉梯形积分、只留后向欧拉也能过**;只有 LC 测试真能区分两种积分。收紧到梯形真实误差的约 10 倍。
- 「触控半径随缩放」只断言 `isA<PartHit>()`,应同时断言 `pinIndex`。
- 缺:`didNotConverge` 的测试(「绝不编数」这条核心承诺目前没人验)、元件压线、零/负/极大/极小值、同一 solver 先 OP 后瞬态。
