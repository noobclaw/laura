# OhmBench 电路台 — 商店文案(**M1 未交付,本文件为草稿**)

> 🔴 **状态:草稿,不得提交。** 2026-09-19 的工厂轮只做了 G2 立项评审与引擎 spike,**M1 的 UI 一行都还没写**。
> PIPELINE G8a ⑧ 的规矩是「文案里的每一条卖点都必须在包里真的存在且可达」——所以这里只写 **M1 计划交付且已在 PLAN.md 的验收表里绑死** 的功能,
> 并在每段后标注它依赖哪个里程碑。**M1 出包后须逐句复核一遍再定稿。**
>
> ⚠️ 提交前必须先建 **English (U.S.)** 本地化并填全(铁律 `feedback_store_listing_must_have_enus`);ASC 主语言一律 English (U.S.)。
> ⚠️ 措辞纪律:正文与截图文案里**不得**出现「取代 iCircuit」「iCircuit alternative」这类指名竞品的表述;竞品名只进关键词字段。
> ⚠️ **本格特有的一条**(2026-09-19 实查):同格的 `Logic Circuit Simulator Pro` 描述里已有「Ad-Free & Offline Mode ... without ads or connectivity limitations」,
> `iCircuit` 描述里已有「a complete app with a one-time purchase」——**「无广告 / 离线 / 买断」这三句已经被人说过了**(而且说了没做到,见 PLAN §二)。
> 所以主打句**不能**是这三句;主句用**没有人说过、而且可验证**的两条:**作品丢不了** 与 **算得对**。

---

## English (U.S.) — 主语言

**Name (30)** — 主词优先 + 品牌;`OhmBench` 今日实查美区零逐字同名
```
Circuit Simulator Lab: OhmBench
```
(30 字符整,含空格。备选:`Circuit Sim & SPICE: OhmBench`)

**Subtitle (30)**
```
Nothing lost. Numbers right.
```
(28 字符。备选:`Offline SPICE that keeps work`)

**Promotional Text (170)**
```
Draw a circuit with your finger and watch the voltages settle. Every number matches SPICE, every edit is undoable, and nothing you build needs an account or a connection.
```

**Description**(M1 口径)
```
OhmBench is a circuit simulator for the phone and tablet you already carry. Draw a schematic, tap run, and see what every node is doing.

THE NUMBERS ARE THE POINT
The solver is modified nodal analysis with Newton iteration and trapezoidal integration — the same method, and the same tolerances, desktop SPICE uses. A resistive divider is exact. An RC curve lands on the analytic answer. A diode bias point agrees with the Shockley equation to a hundredth of a millivolt. And when a circuit genuinely has no answer, OhmBench says it did not converge instead of showing you a number it made up.

BUILT FOR FINGERS, NOT FOR A MOUSE
Parts snap to the grid, so a component that looks connected is connected. Drag a part and it moves; a tap that wobbles selects instead of nudging your circuit apart. Pull a wire straight off a pin. Drop a pin anywhere along a wire and it joins there — no hunting for an endpoint.

NOTHING YOU BUILD IS EVER LOST
Rename projects. Undo and redo without running into a floor. Close the app, kill it, come back — the circuit is where you left it, because it is saved the moment it changes.

IT CANNOT PHONE HOME
OhmBench ships without permission to use the internet at all. It works in airplane mode on a plane, in a basement, in a lab with no signal. No account, no cloud, no subscription, no ads, no tracking.

WHAT YOU CAN BUILD (v1)
Resistors, capacitors, inductors, diodes, switches, DC / sine / pulse sources and ground. Operating point and transient analysis, a probe for any node or branch, and a scope trace you can read.

FREE AND PRO
The free app is a real app: twelve parts on the canvas and one saved project, with full accuracy, full undo and the full scope. One purchase — no subscription — removes both limits forever.

Circuit engine algorithms ported from SpiceSharp (MIT), © 2017 svenboulanger.
```

**Keywords (100, 逗号无空格, 不重复标题/副标题已含词)** — 提审前须按 G8b 用 iTunes API 实打一遍
```
spice,electronics,schematic,breadboard,ohm,resistor,capacitor,diode,transient,oscilloscope,eleclab,icircuit
```
(草稿 97 字符;`icircuit` 是竞品名,按 G8b 第 2 条只进关键词字段 —— 与 autosnore/goldenscout 同口径,若被以 5.2.1 驳回元数据,删词重交即可)

**What's New (v1.0)**
```
First release.
```

**截图文案(英文,5 张,1284×2778)**
1. `Every number matches SPICE` + 画布上的分压器与探针读数
2. `Drag it. It moves.` + 手指拖动元件、栅格吸附
3. `Drop a wire anywhere on a wire` + T 型接点高亮
4. `Undo has no floor` + 撤销栈
5. `No account. No connection. No ads.` + 飞行模式图标 + 权限清单

---

## 简体中文(zh-Hans)

**名称(30)**
```
电路台 OhmBench:离线电路仿真
```

**副标题(30)**
```
算得对,作品丢不了
```

**宣传文本(170)**
```
用手指画一张电路图,立刻看到每个节点的电压。每个数都和 SPICE 对得上,每一步都能撤销,全程不需要账号,也不需要网络。
```

**描述**(M1 口径)
```
电路台是给手机和平板做的电路仿真器。画一张原理图,点运行,看清每个节点在做什么。

数,才是重点
求解器用改进节点法 + 牛顿迭代 + 梯形积分,与桌面 SPICE 同一套方法、同一套容差。分压器是精确解;RC 曲线落在解析解上;二极管工作点与肖克利方程吻合到百分之一毫伏。而当一个电路本来就无解时,电路台会告诉你「未收敛」,不会编一个数给你看。

为手指做的,不是为鼠标做的
元件吸附到栅格 —— 看起来连上了就是真的连上了。拖动元件它就跟着走;手指轻微抖动只会选中,不会把电路挪散。导线可以直接从引脚上拉出来。引脚落在导线的任意一点都算接上,不用去找端点。

你画的东西不会丢
项目可以重命名。撤销和重做没有步数下限。关掉、杀掉、再回来,电路还在原处 —— 因为它在改动的那一刻就已经存好了。

它连不上网
电路台出厂就没有联网权限。飞机上、地下室、没有信号的实验室都照常可用。无账号、无云端、无订阅、无广告、无追踪。

v1 能画什么
电阻、电容、电感、二极管、开关、直流源 / 正弦源 / 脉冲源、接地与导线。工作点分析与瞬态分析,任意节点或支路的探针,以及一条看得懂的示波器曲线。

免费版与 Pro
免费版是真能用的版本:画布 12 个元件、保存 1 份作品,精度、撤销、示波器全都不阉割。一次买断(不是订阅)永久解除这两个上限。

电路引擎算法移植自 SpiceSharp(MIT),© 2017 svenboulanger。
```

**关键词(100)**
```
电路,仿真,模拟,电子,原理图,面包板,欧姆,电阻,电容,二极管,示波器,离线
```

**更新说明(v1.0)**
```
首个版本。
```

---

## 待办(M1 出包后)

1. 逐句复核本文件与实际包的一致性(G8a ⑧),删掉任何 M1 没做到的句子
2. `store/aso.md`:用 iTunes Search API 实打 10–15 个主词,记命中数 / 付费在位者数 / 头部评价量
3. 截图:按上面 5 句各出中英两套
4. 图标:1024 源图(§ PLAN 十的 198° 色相)+ Android 5 档 + iOS 全尺寸 + 512 + 1024×500
