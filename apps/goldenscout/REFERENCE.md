# GoldenScout — 参考保真审计 (G8c)

> 审计日 2026-09-12。核对我方纯本地天文历算(`lib/tool/astro.dart`)对照业界参考实现,产出逐公式对照 + 对照测试。

## 汇总表

| 维度 | 数 | 说明 |
|---|---|---|
| 核心函数/公式 | 14 | 儒略日/太阳位置/月亮位置/恒星时/坐标变换/日出日落/晨昏/黄金蓝调/方位角/月相照亮率/月升落/极昼极夜 |
| **一致** | 11 | 与 Schlyter 规格 + SunCalc(Meeus)数值对照通过 |
| **有意偏离** | 3 | 月亮无视差项、位置返回几何高度(非视高度)、月相用黄经差近似 —— 均为产品理由,记录在案 |
| **漏掉→已补** | 0 | 无 |
| **真错→已修** | 0 | 未发现会导致日出时刻/方位超容差的错误 |
| **剩余** | 0 | 可提审 |

**结论:我方实现是 Paul Schlyter 低精度历表(sun ~1′、moon ~2′)的忠实 Dart 移植,核对无真错。** 日出日落、方位角、月相照亮率均在权威容差内(见对照测试)。三处「有意偏离」是移动端离线 + 摄影规划用途下的合理取舍,不影响事件时刻精度。

## 参考实现

- **算法规格来源**:Paul Schlyter,*How to compute planetary positions*(公开规格,无标准仓;`astro.dart` 文件头已注明移植自此)。
- **数值对照源**:[mourner/suncalc](https://github.com/mourner/suncalc)(**BSD-2-Clause**),已 clone 到 `D:\toolapp\_ref\suncalc`。基于 Meeus《Astronomical Algorithms》ch.15/25/47/48,业界最广用的日照/月相库。
- **署名(BSD-2)**:对照测试 `test/astro_reference_test.dart` 的期望数值由运行 SunCalc v3 生成并转录。**未复制 SunCalc 任何一行代码**(我方为独立的 Schlyter 移植,只转录了它输出的期望数字作为外部真值);SunCalc 版权归 Volodymyr Agafonkin,BSD-2-Clause。「关于」页可保留对 Schlyter 的致谢。

## 逐公式对照

| # | 公式 | 我方(astro.dart) | 参考 | 判定 |
|---|---|---|---|---|
| 1 | 儒略/Schlyter 日数 | `dayNumber` L30-41(`367Y − 7(Y+(M+9)/12)/4 + 275M/9 + D − 730530 + UT/24`) | Schlyter 日数规格;SunCalc 用 J2000 天数,数学等价 | **一致** — 测试 `dayNumber` epoch=1.0 |
| 2 | 黄赤交角 | `_obliquity` L44(`23.4393 − 3.563e-7·d`) | Schlyter;Meeus 22.2 一阶项相同量级 | **一致** |
| 3 | 太阳赤经/赤纬 | `_sunEquatorial` L93-116(近点角 1 次迭代 + 黄道→赤道旋转) | Meeus ch.25(SunCalc `sunCoords`) | **一致** — 对照测试 alt/az ≤0.2°/0.5° |
| 4 | 恒星时 (LST) | `_localSiderealTime` L67-76(Schlyter GMST0 = Ls/15+12h + UT + λ/15) | Meeus 12.4(SunCalc `siderealTime`) | **一致** — 方位角/时角对照通过反证 |
| 5 | 赤道→地平坐标 | `_toHorizontal` L79-90 | SunCalc `altitude`/`azimuth` | **一致** |
| 6 | 太阳方位角(真北基准,顺时针) | `_toHorizontal` L86-88(`az = atan2(−cosδ·sinH, sinδ·cosφ − cosδ·cosH·sinφ)`) | SunCalc `atan2(sinH, cosH·sinφ − tanδ·cosφ)+180°`,同为真北顺时针 | **一致** — NY 16:00Z 140.48°、London 春分 177.45° 均 ≤0.5° |
| 7 | 日出日落阈值 | `SunAltitudes.sunrise = −0.833°` L256(折射 34′ + 视半径 16′) | SunCalc `[-0.833,'sunrise']` L103,同值 | **一致** |
| 8 | 民用晨昏 | `civil = −6.0°` L257 | SunCalc `[-6,'dawn','dusk']` | **一致** — NY dawn/dusk ≤1min |
| 9 | 黄金/蓝调时段 | `goldenHigh = +6°`、`goldenLow = −4°` L258-259 | SunCalc `[6,'goldenHour…']`;蓝调 −4°~−6° 为摄影惯例 | **一致** — NY 黄金 +6° 起止 ≤1min |
| 10 | 日出日落解算 | `computeDayLight` L360-439:以**平太阳正午为中心**采样 1440 点几何高度、线性插值阈值穿越 | SunCalc 用 Meeus ch.15 时角直解;两者都对**几何高度**比 −0.833°(折射不进位置只进阈值) | **一致** — NY/London/北京/雷克雅未克/特罗姆瑟均 ≤1~3min |
| 11 | 极昼/极夜判定 | L417-418(`polarDay = minAlt > −0.833`;`polarNight = noonAlt < −0.833`) | SunCalc `alwaysUp/alwaysDown`(noonAlt vs riseSet 阈值),逻辑同构 | **一致** — 特罗姆瑟极夜/雷克雅未克午夜太阳测试通过 |
| 12 | 月亮赤经/赤纬 | `_moonEquatorial` L120-188(Schlyter 主摄动项:出差/二均差/年差…12 经度项 + 5 纬度项,近点角 2 次迭代) | Meeus ch.47 截断 ELP-2000(SunCalc 60+60 项 `moonLon/moonLat`) | **有意偏离**(见下 A) |
| 13 | 月相照亮率 | `moonPhase` L216-242(`illum = (1−cos(黄经差))/2`) | SunCalc 用完整相角(距离几何,Meeus ch.48) | **有意偏离**(见下 B)— 4 日期照亮率对照 ≤0.02 |
| 14 | 月升月落 | `computeMoonTimes` L473-506(5 分步采样几何高度、阈值 `+0.125°` 近似地平) | SunCalc `moonHeight`(视高度 + 视差 + 半径 + 折射,过 0) | **有意偏离**(见下 C) |

## 有意偏离(产品理由,非「没看到」)

**A. 月亮位置不含地心视差**(#12)。SunCalc `getMoonPosition` 用 `earthRadius/dist·cos(h)` 把月亮沿垂直圈下压 ~57′(视差),我方 `_toHorizontal` 返回**地心**高度。理由:视差对**月亮方位角为零**(只压高度),对摄影「月亮在哪个方位」的核心用途无影响;对月升落时刻的影响已用 #14 的阈值常数近似吸收。月亮位置精度因此约 ~2′(经度)+ 视差残差,对规划足够。

**B. 月相照亮率用黄经差近似**(#13)。用日月**黄经差**(elongation)代替完整相角,忽略月亮黄纬(±5°)。理由:黄纬对照亮率的影响 < 0.01;四个测试日期(蛾眉/盈凸/近满/亏)对照 SunCalc 完整相角**误差均 ≤0.006 < 0.02 容差**,近满月(0.996)也吻合。近似值省去距离几何,代码更小。

**C. 月升落用单一地平阈值 +0.125°**(#14)。SunCalc 逐点算视高度(含随距离变化的半径 + 视差 + 折射)再牛顿精修;我方对**地心几何高度**用固定阈值 `+0.125°` 近似「视差 ~57′ − 折射 34′ − 半径 16′」的净和。理由:视差随月地距离在 54′~61′ 变动,故月升落时刻可能偏差数分钟 —— 但月升落是摄影规划中容差最宽的量(不像日出需精确),用途上可接受。**注:因此月升落未纳入 ≤1min 对照,只保留 `astro_test.dart` 的形状/单调性断言。** 若未来要收紧,按 SunCalc `moonHeight` 补视差项即可,规格已在此记录。

## 对照测试

`test/astro_reference_test.dart`(11 例,全绿):

| 组 | 地点/日期 | 量 | 容差 | 结果 |
|---|---|---|---|---|
| 太阳位置 | 纽约 2026-06-21 16:00Z / 伦敦春分 12:00Z / 纽约日出瞬时 | 方位角、高度角 | az ≤0.5°、alt ≤0.2° | ✅ |
| 日出日落 | 纽约 / 伦敦 2026-06-21 (UTC) | 日出/日落 + 黄金 +6° + 民用 −6° | ≤1 min | ✅(NY 日落跨日 +1 亦对) |
| 正午高度 | 纽约 72.73° / 伦敦 61.94° | 当日峰值高度 | ≤0.2° | ✅ |
| 月相照亮率 | 4 个 UTC 日期(0.406/0.826/0.996/0.264) | illuminated fraction + waxing | ≤0.02 | ✅ |

期望值由 `D:\toolapp\_ref\suncalc` 运行 `getPosition`/`getTimes`/`getMoonIllumination` 生成并转录。既有 `test/daylight_reference_test.dart`(timeanddate.com 真值)与 `test/astro_test.dart`(单位/形状/极区)保留不动。

**验收**:`flutter analyze` → No issues found;`flutter test` → 全 36 例通过(+11 本轮新增)。
