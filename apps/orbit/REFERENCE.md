# Orbit — Reference Fidelity Audit (G8c)

**App**: Orbit (卫星过境预报) — SGP4/SDP4 轨道推演 + 过境几何 + 可见性
**审计日期**: 2026-09-12
**参考源(权威标准)**: [brandon-rhodes/python-sgp4](https://github.com/brandon-rhodes/python-sgp4) — MIT License, Copyright © 2012–2024 Brandon Rhodes. 这是 Vallado C++ SGP4 的官方 Python 移植,含 `sgp4/SGP4-VER.TLE` 官方验证向量与 `sgp4/tcppver.out` 期望位置/速度。本机克隆:`D:\toolapp\_ref\python-sgp4`。
**署名**: python-sgp4 为 permissive(MIT),本 app「关于」页与 store listing 应署名。核心 SGP4 是按 Vallado 公开算法的独立 Dart 实现;对照测试中的期望数字直接抄自 `tcppver.out`(允许),**未复制任何一行 Python/C++ 代码**。

---

## 汇总表

| | 数 |
|---|---|
| 核对的核心函数 | 14 |
| 一致(数值级对齐) | 11 |
| 有意偏离(有产品理由) | 3 |
| 漏掉 → 已补 | 0 |
| **错误 → 已修** | **0** |
| 剩余未解决 | 0 |

**结论**:我方 SGP4 近地分支是 Vallado/python-sgp4 的**逐系数忠实移植**。官方验证向量(sat 88888、sat 00005)在 **1e-3 km(1 米)位置 / 1e-6 km/s 速度**容差下全部通过 —— 比 SGP4 标准的 ~0.1 km「算对」判据紧三个数量级。**未发现会导致过境时刻/方位算错的真错误。** 三处「有意偏离」都是产品取舍(不做深空 SDP4、观测者用 WGS-84、观测/光照层是 python-sgp4 范围外的标准天文公式),已在下方记录留作下一版参考。

---

## 逐函数对照

我方文件:
- `lib/tool/sgp4.dart` — TLE 解析 + SGP4 近地传播
- `lib/tool/astro.dart` — GMST / 帧变换 / look angles / 可见性

### A. 初始化与常量

| # | 项目 | python-sgp4 | 我方 文件:行 | 判定 |
|---|---|---|---|---|
| 1 | WGS-72 常量 `mu=398600.8` `radiusearthkm=6378.135` `j2/j3/j4` `xke=60/√(R³/mu)` `j3oj2` | `getgravconst('wgs72')` propagation.py:2035+ | `Wgs72` sgp4.dart:22-35 | **一致**(逐值相同;`xke`/`vkmpersec` 公式一致) |
| 2 | 恢复原始平均运动(去 Kozai):`ak`、`d1`、`del` 两次迭代、`no = no_kozai/(1+del)` | `sgp4init` propagation.py:1159-1180 | `_init` sgp4.dart:266-271 | **一致** |
| 3 | 大气阻力常数 `ss/qzms24`、近地点 <156/98km 降级、`eta/coef/coef1`、`cc1..cc5`、`cc3` | `sgp4init` propagation.py:1384-1520 | `_init` sgp4.dart:255-339 | **一致** |
| 4 | 长期率 `mdot/argpdot/nodedot`、`omgcof/xmcof/nodecf`、`t2cof`、`xlcof/aycof`(含极点奇异保护)、`delmo/sinmao/x7thm1` | `sgp4init` propagation.py:1520-1560 | `_init` sgp4.dart:341-371 | **一致**(`cosio+1` 奇异保护同 Vallado sgp4fix) |
| 5 | `simple` 阻力模型判定(近地点 < 220km)+ `d2/d3/d4/t3cof/t4cof/t5cof` | `sgp4init` propagation.py:1422/1560+ | `_init` sgp4.dart:374-396 | **一致** |
| 6 | `usable`/衰减判定(`rp<1`、`no<=0`) | error flags | sgp4.dart:280-282 | **一致**(等价拒绝) |

### B. 主传播 `sgp4(tsince)`

| # | 项目 | python-sgp4 | 我方 文件:行 | 判定 |
|---|---|---|---|---|
| 7 | 长期更新 `xmdf/argpdf/nodedf`、非简单模型下 `delomg/delm`、`tempa/tempe/templ`、阻力多项式 `d2..d4/t3..t5cof` | `sgp4` propagation.py:1707-1745 | `propagate` sgp4.dart:404-427 | **一致** |
| 8 | `am/nm/em` 更新 + 衰减守卫(`em>=1`、`em<-0.001`、`em<1e-6` 夹取、`am<=0`) | propagation.py:1777-1795 | sgp4.dart:429-446 | **一致**(边界处理逐条对应) |
| 9 | 长周期项 `axnl/aynl/xl` | propagation.py:1845-1852 | sgp4.dart:448-452 | **一致** |
| 10 | Kepler 迭代(Newton,`±0.95` 步长钳位,≤10 次,阈值 1e-12) | propagation.py:1856-1873 | sgp4.dart:454-468 | **一致** |
| 11 | 短周期项 `mrt/su/xnode/xinc/mvt/rvdot`、`mrt<1` 拒绝、方向向量 U/V、乘 `radiusearthkm`/`vkmpersec` 输出 TEME 位置/速度 | propagation.py:1875-1930 | sgp4.dart:470-525 | **一致** |

### C. 时间 / 帧 / 观测 / 可见性

| # | 项目 | python-sgp4 | 我方 文件:行 | 判定 |
|---|---|---|---|---|
| 12 | GMST(`gstime`,IAU-82 系数 `-6.2e-6/0.093104/(876600·3600+8640184.812866)/67310.54841`,`/240·deg2rad %2π`) | `gstime` propagation.py:1986-1998 | `gmstRadians` astro.dart:23-33 | **一致**(系数逐个相同,含 <0 加 2π) |
| 13 | 深空判定(周期 ≥ 225 分走 SDP4) | `sgp4init` method='d' if 2π/no_kozai ≥ 225 | `isDeepSpace` sgp4.dart:73;载入端 `catalog.dart:32`/`store.dart:236` 拒绝 | **有意偏离**(见下 §偏离1) |
| 14 | TEME→ECEF / geodetic / look angles / 太阳位置 / 地影 / 星等 | python-sgp4 **不含**(纯传播器) | astro.dart:50-226 | **有意偏离**(见下 §偏离3) |

---

## 有意偏离(产品理由,留作下一版参考)

**偏离 1 — 不实现 SDP4 深空分支。** python-sgp4 有完整 `_dspace`/`_dpper` 月-日引力共振项。Orbit 只做近地分支,并在 TLE 载入时以 `isDeepSpace`(周期 ≥ 225 分)**拒绝**深空对象,而非静默产出错误结果。
理由:本 app 是给肉眼/望远镜看 LEO 过境用的(ISS、Starlink、哈勃…),GEO/Molniya 这类深空对象既不适合过境观测,SDP4 又会显著增加代码面与出错面。边界已守死(`sgp4.dart` 库注释 + 载入端两处过滤 + `passes.dart:121` `!sat.usable` 早退)。**下一版若要覆盖深空,须按 python-sgp4 `_dspace`/`_dpper` 规格补 SDP4,并加对应 `SGP4-VER.TLE` 深空用例(如 sat 04632/08195/11801)对照测试。**

**偏离 2 — 观测者位置用 WGS-84 椭球,卫星侧保持 WGS-72。** `astro.dart:17` `earthRadiusKm=6378.137`、`_flattening=1/298.257223563`。卫星侧(`Wgs72`)必须用 WGS-72,因为 TLE 是对它拟合的。两椭球赤道半径差 2 米,远低于 TLE 噪声。理由:观测者地理坐标本就该用现代 WGS-84,混用不产生可觉察误差。

**偏离 3 — 观测/光照层是 python-sgp4 范围外的标准天文公式。** GMST 之外的 TEME→ECEF、topocentric look angles(方位/仰角/距离)、低精度太阳位置、圆柱地影 `isSunlit`、标准星等公式,python-sgp4 都不提供(它只算 TEME 状态向量)。这些是教科书级公式(Vallado 观测章 / satellite.js 同款)。**已由构造性单测锁定基准正确**:天顶=90° 仰角、正北=方位 0°、正东=方位 90°(`sgp4_test.dart` time-and-frames 组);太阳位置对北半球仲夏伦敦正午 ~62° 仰角。satellite.js 可作二次参考,本轮未克隆(look-angle 约定已由上述单测证伪等价)。

---

## 对照测试

新增 `test/sgp4_reference_test.dart`:

1. **sat 88888**(近地正常阻力例)—— t = 0/120/360/720/1440 min 五个时刻的 TEME 位置(km)与速度(km/s),期望值抄自 `tcppver.out`。**通过**(位置 <1e-3 km、速度 <1e-6 km/s)。
2. **sat 00005**(高偏心 e=0.186 近地例)—— t = 0/360/720/1080/1440 min 五个时刻,期望值抄自 `tcppver.out`。**通过**(同容差)。
3. **ISS 真实 TLE(25544)过境几何合理性**—— 伦敦观测站 24 小时、30 秒步长:方位 ∈[0,360]、仰角 ∈[-90,90]、地平线以上时斜距 <2600 km,且一天内至少一次过境、最高仰角 >20°;并核对星下点纬度不超过轨道倾角、高度落在 380–460 km 带内。**通过**。

**容差说明**:忠实的双精度传播器可把官方向量复现到亚米级;取 1e-3 km / 1e-6 km/s 作断言阈值,任一系数抄错都无法蒙混通过。

---

## 验证

- `flutter analyze` — **No issues found**
- `flutter test` — **42/42 全绿**(含新增对照测试 3 组 + 原有 39 项)
