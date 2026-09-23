# OhmBench 电路台 — 商店文案(M1,1.0.0)

> 状态:**M1 定稿,待真机验收**(2026-09-22 工厂轮)。每一句都已对照 1.0 包里的实现核对(G8a ⑧);M2 功能(交流扫频、晶体管/运放、iPad 布局、脉冲源)**一句都没写**。
> ⚠️ 提交前先建 **English (U.S.)** 本地化并填全;ASC 主语言 English (U.S.)。
> ⚠️ 竞品名只进关键词字段,正文和截图不点名。
> ⚠️ 本格特有:「无广告 / 离线 / 买断」三句同格产品已经说过(PLAN §二),所以主打句用 **作品丢不了** 与 **算得对**;那三句只作为事实放在描述后段。
> ⏳ G8b(提审前):`store/aso.md` 用 iTunes Search API 实打 10–15 个主词后,再定关键词字段。

---

## English (U.S.) — primary

**Name (30)**
```
Circuit Simulator Lab: OhmBench
```
(30 chars. `OhmBench` has no exact-name match on the US store as of 2026-09-19.)

**Subtitle (30)**
```
Nothing lost. Numbers right.
```

**Promotional Text (170)**
```
Draw a circuit with your finger, press play and watch charge flow through it. Every number is solved the way desktop SPICE solves it, and nothing needs a connection.
```

**Description**
```
OhmBench is a circuit simulator you can actually edit on a phone. Draw a schematic, press play, and watch it run: wires glow with their voltage, charge flows through every branch, and a scope traces whatever you tap.

THE NUMBERS ARE THE POINT
The solver is modified nodal analysis with Newton iteration and trapezoidal integration — the method, and the tolerances, desktop SPICE uses. A resistive divider is exact. An RC curve lands on the analytic answer. A diode bias point agrees with the Shockley equation to a hundredth of a millivolt. When a circuit has no trustworthy answer — a shorted source, a solve that will not converge — OhmBench says so and shows no numbers at all, instead of inventing one.

BUILT FOR FINGERS, NOT A MOUSE
Parts snap to the grid, so a part that looks connected is connected. Drag a part and it moves; a tap that wobbles selects instead of nudging your circuit apart. Pull a wire straight off a pin, or turn on wire mode and draw anywhere. Drop a pin anywhere along a wire and it joins there. Long-press and drag to select a group and move it as one.

A LIVE BENCH
Press play and the circuit keeps running. Flip a switch and the capacitor charges from the voltage it had a moment ago. Tap a wire to scope its voltage, tap a part to scope its current. Every run plays back over four seconds — a microsecond ring slowed down, a slow RC sped up — and the scope says by how much.

NOTHING YOU BUILD IS LOST
Every change is saved as you make it, and again whenever you leave the app. Hundreds of steps of undo and redo, and the undo button tells you what it will take back. Rename, duplicate and delete circuits (with undo).

WORKS IN AIRPLANE MODE
OhmBench makes no network connections. It works on a plane, in a basement, in a lab with no signal.

WHAT YOU CAN BUILD (1.0)
Resistors, capacitors, inductors, diodes, switches, DC and sine voltage sources, current sources and ground. Four ready-to-run examples — a voltage divider, RC charging, a half-wave rectifier and an LC tank — that open as scratch circuits, so trying them never uses up a save.

FREE AND PRO
The free app is a real app: one saved circuit with up to twelve parts (ground is free), the same engine and the same accuracy, the full scope and full undo. One purchase removes both limits for good.

Circuit engine algorithms ported from SpiceSharp (MIT licence), © 2017 svenboulanger.
```

**Keywords (100, comma-separated, no words already in name/subtitle)** — draft, confirm in G8b
```
spice,electronics,schematic,breadboard,ohm,resistor,capacitor,diode,oscilloscope,physics,icircuit
```

**What's New (1.0.0)**
```
First release.
```

**Screenshot captions (EN, 5 × 1284×2778)**
1. `Draw it. Run it.` — the running rectifier with charge dots and scope (first screen = the ad)
2. `Every number, SPICE-grade` — divider with probe readout
3. `Flip a switch mid-run` — RC charging on the scope
4. `Drag from a pin to wire it` — wire preview from a pin
5. `Saved at every step` — library with circuits + undo label

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
用手指画一张电路图,按下播放,看电荷在导线里流动。每个数都按桌面 SPICE 的方法求解,全程不需要网络。
```

**描述**
```
电路台是一个真能在手机上编辑的电路仿真器。画一张原理图,按下播放,看它跑起来:导线按电压发光,电荷沿每条支路流动,点到哪里示波器就画哪里。

数,才是重点
求解器用改进节点法 + 牛顿迭代 + 梯形积分,与桌面 SPICE 同一套方法、同一套容差。分压器是精确解;RC 曲线落在解析解上;二极管工作点与肖克利方程吻合到百分之一毫伏。遇到没有可信解的电路 —— 电源被短接、求解不收敛 —— 电路台会直说,并且一个数都不显示,绝不编一个给你看。

为手指做的,不是为鼠标做的
元件吸附栅格,看起来连上了就是真的连上了。拖动元件它就跟着走;手指轻微抖动只会选中,不会把电路挪散。从引脚直接拉出导线,或打开连线模式在任意处画。引脚落在导线的任意一点都算接上。长按拖出方框,可以整组选中一起移动。

一张活的实验台
按下播放,电路就一直在跑。拨一下开关,电容会从它上一刻的电压继续充电。点导线看它的电压,点元件看它的电流。每次运行都在四秒内播完 —— 微秒级的振荡放慢,慢悠悠的 RC 加快 —— 示波器会标出快放或慢放了多少倍。

你画的东西不会丢
每一次改动都会立刻保存,离开应用时再保存一次。数百步撤销与重做,撤销按钮会告诉你它要撤回什么。电路可以重命名、复制、删除(删除也能撤销)。

飞行模式照样用
电路台不建立任何网络连接。飞机上、地下室、没信号的实验室都照常可用。

1.0 能画什么
电阻、电容、电感、二极管、开关、直流与正弦电压源、电流源、接地。自带 4 个能直接运行的示例:分压器、RC 充电、半波整流、LC 振荡。示例以草稿打开,随便试不占保存名额,喜欢哪个再存下来。

免费版与 Pro
免费版是真能用的版本:保存 1 张电路图、每张最多 12 个元件(接地不算),同一个引擎、同一套精度,示波器与撤销全都不阉割。一次买断永久解除这两个上限。

电路引擎算法移植自 SpiceSharp(MIT 许可),© 2017 svenboulanger。
```

**关键词(100)**
```
电路,仿真,模拟,电子,原理图,面包板,欧姆,电阻,电容,二极管,示波器,物理
```

**更新说明(1.0.0)**
```
首个版本。
```

---

## 定价

- 免费下载 + Pro 一次性买断 **$4.99 / ¥28**,商品 ID `com.noobclaw.ohmbench.pro_unlock`(非消耗型)。
- App 内价格一律取商店下发的本地化价(`ProPriceText`),$4.99 只是商店未响应时的兜底。
