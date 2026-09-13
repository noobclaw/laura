# REFERENCE — 参考保真审计(G8c)

星野叠加(astropile)的配准 / 叠加 / 帧质量 / **校准(M2)** 四条核心链路,逐函数对照五个参考仓核实。
参考仓在 `D:\toolapp\_ref\`,均为 `git clone --depth 1`。

## 汇总表

| 参考仓 | 许可证 | 核对项 | 一致 | 有意偏离 | 漏掉→已补 | 剩余 |
|---|---|---|---:|---:|---:|---:|
| astroalign (quatrope) | MIT | 11 | 9 | 1 | 1 | 0 |
| astra_lite (art-den) | MIT | 6 | 0 | 2 | 4 | 0 |
| OpenSkyStacker (Schubert) | MIT | 4 | 2 | 2 | 0 | 0 |
| als (deepskylog) | GPL-3.0（仅规格） | 4 | 2 | 2 | 0 | 0 |
| **DeepSkyStacker (M2 新增)** | **BSD-3** | **10** | **7** | **3** | **0** | **0** |
| **合计** | | **35** | **20** | **10** | **5** | **0** |

**剩余 = 0,满足 G8c 提审门槛。**
- 上一轮(2026-09-12)补齐了两处:① astroalign `_ransac` 的内点计数口径(A-7);② 整个 astra_lite 星点清晰度模块(`engine/quality.dart`)。
- 本轮(2026-09-13,M2)新增 §E:DeepSkyStacker 的 **κ-σ 剪切 / 最大值合成 / 暗场减除 / 平场归一化** 四组算法,对应 `engine/stack.dart` 与新建的 `engine/calibration.dart`。

## 许可证与署名

- **astroalign / OpenSkyStacker / astra_lite 均为 MIT(permissive)**:可对照移植 + 署名。三者已署名于 App「设置 > 关于」页(`lib/core/branding.dart:aboutText`)与商店文案(`store/listing.md` 中英「开源致谢 / Credits」段)。本应用为独立 Dart 实现,未复制任何一行源码。
- **als 为 GPL-3.0(copyleft)**:**仅阅读、仅用作规格(对齐失败判据、帧质量筛选流程),未复制任何代码与资源**;因此不在 App / 商店署名中出现,只在本文件记录规格来源。
- ⚠️ **DeepSkyStacker 的许可证要更正**(2026-09-13 实查):BACKLOG 与 M1 的 PLAN 依据 GitHub 的 `NOASSERTION` 标记把它记成「视同不可用」。**实际 `_ref/DSS/LICENSE` 是完整的 BSD 3-Clause**(© 2006–2019 LucCoiffier;© 2018–2025 David C. Partridge 等),**属 permissive,可对照移植 + 署名**。因此 M2 的 κ-σ 与暗场平场**不必**走「只读规格、从零重写」那条更严的路 —— 但**实际仍然是从零 Dart 实现、未复制任何一行 C++**(算法本身是教科书统计量,C++ 的 `CDynamicStats` / OpenMP / Qt 结构在移动端也无从照搬),署名按 BSD-3 要求加进「关于」页与 listing。
  **教训写进纪律**:GitHub 的 `NOASSERTION` 只说明它的自动识别器没认出来(DSS 的 LICENSE 文件里混了项目名),**不等于没有许可证 —— 必须打开仓库根目录的 LICENSE 亲眼看**。M1 因为这条把 DSS 整个排除在外,是一次代价为「多绕一圈」的误判。

---

## A. astroalign(MIT,© 2016 Martin Beroiz)— `astroalign.py`
对照我方 `engine/asterism.dart`(配准) / `engine/transform.dart`(相似变换最小二乘) / `engine/stars.dart`(星点检测) / `engine/warp.dart`(重采样)。

| # | 原仓函数 / 常量 | 输入→输出 / 关键常量 | 我方 文件:行号 | 判定 |
|---|---|---|---|---|
| 1 | `_find_sources`（astroalign.py:535） | 图→按 flux 降序星表;detection_sigma=5, min_area=5, `[:max_control_points]`=50 | `stars.dart:117 detectStars`（sigmaFactor=5, kMinStarArea=5, kMaxControlPoints=50, flux 降序） | **一致**(规格)。原仓用 `sep`（背景网格+去混叠），我方用行程连通域 + 3σ 直方图裁剪估背景 —— 手机内存下的等价实现,常量对齐。 |
| 2 | `_invariantfeatures`（:106） | 3 点→`[sides[2]/sides[1], sides[1]/sides[0]]` 即 `[L3/L2, L2/L1]`,L1≤L2≤L3 | `asterism.dart:157 _arrange` 末 `Asterism(a,b,c, l3/l2, l2/l1)`（r1=L3/L2, r2=L2/L1) | **一致** |
| 3 | `_arrangetriplet`（:118） | 顶点排序 a=L1∩L2, b=L2∩L3, c=L3∩L1 | `asterism.dart:157 _arrange`（`_sharedVertex(sides0,sides1)`=a … ) | **一致**(对照测试 3-4-5 三角形逐字断言) |
| 4 | `_generate_invariants`（:149） | KD-tree 每点取 `NUM_NEAREST_NEIGHBORS`=5 近邻,C(5,3)=10 三角形,去重 | `asterism.dart:120 buildAsterisms`（kNeighbours=5,三重循环 10 组,`seen` 去重） | **一致**。原仓 KD-tree,我方 n≤50 直接排序近邻 —— 数值等价。 |
| 5 | `find_transform`（:257） 参数 | max_control_points=50, PIXEL_TOL=2, MIN_MATCHES_FRACTION=0.8, `min_matches=max(1,min(10,int(N·0.8)))`, 匹配半径 r=0.1 | `asterism.dart:201 alignStars`（kMaxControlPoints=50, kPixelTolerance=2.0, kMinMatchFraction=0.8, `minMatches`:234, kInvariantRadius=0.1） | **一致**(常量逐一对齐) |
| 6 | `find_transform` 3 点特例（:376） | source/target 恰 3 点且 matches==1 时跳过 RANSAC 直接 fit | 无此特例；`alignStars` 末 `srcPts.length < 4 → tooFewMatches`（:332） | **有意偏离**(产品):手机连拍下 3 对点能解不能信,故最终强制 ≥4 对点,比原仓更严;3 星帧被判 `tooFewStars`/`tooFewMatches`。 |
| 7 | `_ransac`（:589） 内点判据 | `maybeinliers`=最小样本,阈值只作用于**其余**候选 `alsoinliers`,`len(alsoinliers) >= min_matches` 才接受;`good_data = maybe ∪ also` | `asterism.dart:252-265`：`inliers=[matches[i]]` 作样本、`others` 只数其余通过阈值者、`others >= minMatches` 判定、拟合用 `inliers`(含样本) | **漏掉→已补**。上一版把样本本身也计入阈值(`inliers.length>=minMatches`),min_matches==1 时单个三角形自证通过。本轮按原仓改为只数 `alsoinliers`。 |
| 8 | `_ransac` 精修（:636） | 接受后固定 3 轮:全体 `err<thresh` 重拟合 | `asterism.dart:270-280` 3 轮 `_triangleError<kPixelTolerance` 重拟合 | **一致** |
| 9 | `estimate_transform('similarity')`（skimage `_umeyama`） | 对应点→均匀缩放+旋转+平移最小二乘闭式 | `transform.dart:69 fitSimilarity`(中心化后 `c=Σ(x'u'+y'v')/Σ(x'²+y'²)`, `d=Σ(x'v'−y'u')/…`) | **一致**。即 Umeyama/Procrustes 的 4-DoF 闭式解,与 skimage `estimate_scale=True` 数值相同。 |
| 10 | `apply_transform`（:408，skimage `warp` order=1） | 变换+双线性插值重采样 | `warp.dart:15 warpRgb`(按 `t.inverse` 反向走双线性) | **一致**。原仓可选 order；我方固定双线性(星点本身已是数像素宽的模糊盘,双三次无可测收益,省 4× 算力)。 |
| 11 | `find_transform` 内点去重（:388） | 同一 source 点多重指派时保留重投影误差最小者 | `asterism.dart:290-310 bestForSource`(+额外 `bestForTarget` 双向去重) | **一致**。我方额外在 target 侧也去重,防两颗源星争同一参考星抬高匹配数 —— 更严,非偏离。 |

对照测试(`test/reference_test.dart`):
- `find_transform on the given-sources case`:原仓 `tests/test_align.py::test_find_transform_givensources` 的点集与参数(scale=1.5, α=π/8, t=(2,1))逐字搬来,要求恢复 scale/rot/tx/ty 误差 < 1e-6、rms < 1e-6。因原仓无合理性闸,测试用 `alignStars(minScale:0.5,maxScale:2.0,maxRotationDegrees:90)` 走同一码路(这三个参数即为此测试而加,生产默认仍是 0.8/1.25/45°)。
- `invariants are [L3/L2, L2/L1] …`:3-4-5 三角形逐字断言 r1=5/4、r2=4/3、a=1/b=2/c=0。
- 合成帧:随机星场 + 已知相似变换(3° 旋转、1.06 缩放、(17.3,−9.6) 平移),要求四角+中心逆变换回原点 < 0.5px、旋转 < 0.1°、scale 误差 < 0.002、rms < 0.5px。

## B. astra_lite(MIT,© 2023 Denis Artyomov)— `src/image/stars.rs`
对照我方**新建** `engine/quality.dart`。整模块为本轮补齐。

| # | 原仓函数 / 常量 | 输入→输出 / 关键常量 | 我方 文件:行号 | 判定 |
|---|---|---|---|---|
| 1 | `calc_common_star_image`（stars.rs:555） | 星表→「平均星」图:剔除 overexposed、按到中心距离 0.5/0.66/0.75/1.0/1e6 分环取(min 50 / max 100 颗),cutout `min(avg,32)·k` 取奇,逐输出像素对各星背景减+峰值归一后取**中位数**(`select_nth_unstable(len/2)`) | `quality.dart:74 measureStarShape`(kMinShapeStars=50, kMaxShapeStars=100, kMaxStarDiameter=32, k=kShapeMagnification=4, 同样五环, `_medianOf`=上中位数, 归一 `65535*(v-bg)/range`) | **漏掉→已补**。常量逐一对齐;cutout 尺寸原仓用每星包围盒 `avg_width/height`,我方行程检测器只存 `area` → 用等效圆半径 `3·(√(area/π)+1)` 近似(偏大,更保守,不影响 FWHM 面积口径)。overexposed 原仓有检测标志,我方用 `luma≥250` 近似(kSaturatedLuma)。 |
| 2 | `calc_fwhm`（:685） | `area = count(v ≥ u16::MAX/2)`;`2·√(area/π)/k` | `quality.dart:159 _fwhm`(阈值 `v≥32767`=65535/2, `2·√(area/π)/k`) | **漏掉→已补**(数值口径逐字一致) |
| 3 | `calc_hfd`（:653） | 通量质心→`2·(Σ dist·v / Σv)/k` | `quality.dart:170 _hfd` | **漏掉→已补**(一致) |
| 4 | `calc_ovality`（:699） | 过中心 `ANGLE_CNT`=32 方向的半高宽;最宽 − 与之垂直方向宽,`/k` | `quality.dart:197 _ovality`(kOvalityAngles=32, `angle=π·i/32`, minPos=(maxPos+16)%32, 阈值 v≥32767) | **漏掉→已补**(一致) |
| 5 | `FrameQuality.fwhm_is_ok`（frame_processing.rs:579） | `fwhm < max_fwhm`,`max_fwhm` 用户设、默认 5.0px 且默认**关闭**(`use_max_fwhm=false`) | `quality.dart:69 isBlurry`(`fwhm > kBlurFwhmRatio(2.0)·referenceFwhm`),接线于 `pipeline.dart:_alignFrame`,判 `AlignFailure.blurry` | **有意偏离**(产品):手机无固定像元尺度、无设置项,故改为**相对参考帧的 2.0×** 阈值而非绝对像素阈值;不可测(fwhm=0 或参考 0)一律不拒。 |
| 6 | `FrameQuality.ovality_is_ok`（:582） | `ovality < max_ovality`,默认 2.0 且默认关闭 | 仅测量并在报告里显示(`report_screen.dart`「拉长/Elongation」),**不自动拒帧** | **有意偏离**(产品):拉长帧对齐后仍可能有用,故只报告不拦截,避免误杀。 |

对照测试:高斯 PSF 的 FWHM≈2.355σ(σ=1.4 → 3.30px,容差 0.8)—— 这是 FWHM=2√(2ln2)·σ 的物理定义,验证了「平均星图+calc_fwhm」整链数值正确;失焦帧(σ 1.4→3.5)FWHM 比值 >2.0 触发 blur 闸、反向不触发;拖尾帧 ovality 明显增大;无星/仅饱和星报 `unmeasured`。

## C. OpenSkyStacker(MIT,© 2017 Benjamin Schubert)— `libstacker/src/imagestacker.cpp` / `util.cpp`
对照我方 `engine/stack.dart`。本轮未改动 stack.dart,仅核实。

| # | 原仓行为 | 细节 | 我方 文件:行号 | 判定 |
|---|---|---|---|---|
| 1 | 累加位深(util.cpp:749 `cv::add(...,CV_32F)`;imagestacker:349 `workingImage += image`) | 帧读入即转 **CV_32F 归一 [0,1]**,float 累加 | `stack.dart:143-148` mean 模式:8-bit 值 `sum += bands[...][at]` **整数累加**,`sum ~/ count` | **有意偏离**(产品):手机 JPEG 全程 8-bit,≤32 帧×255 整数无溢出、输出也 8-bit,float 归一无可见收益。 |
| 2 | `workingImage /= totalValidImages`（imagestacker:361） | 除以有效帧数 | `stack.dart:148 out[at]=sum ~/ count` | **一致**。原仓按整图统一除 totalValidImages;我方 `rowCoverage` 按**像素级实际覆盖数** count 除 —— 更精确,避免边缘变暗。 |
| 3 | `totalValidImages` 只计成功对齐帧(util.cpp:735/750;<2 报错) | 越界/未覆盖不计入 | `stack.dart` 覆盖区间 `rowCoverage`(未覆盖像素保持黑不计),截断帧(短读)`short[]` 从该带丢弃 | **一致** |
| 4 | 中值 | OSS 核心叠加**仅均值**,无中值 | `stack.dart:163 medianOf` + `StackMode.median`(count 奇取中、偶取双中均值) | **有意偏离**(增强):额外提供中值模式剔飞机/卫星/热点(Pro),原仓无此路径。 |

## D. als(GPL-3.0)— `src/als/stack.py`(**仅规格,未复制代码**)

| # | 原仓规格 | 细节 | 我方 文件:行号 | 判定 |
|---|---|---|---|---|
| 1 | `_find_transformation` 最小匹配闸(stack.py:364) | `len(matches[0]) < minimum_match_count` → `StackingError` 拒帧 | `asterism.dart:332` `srcPts.length < 4 → tooFewMatches`(叠加 RANSAC 的 minMatches 闸) | **一致**(规格) |
| 2 | 多比例子集重试(:346 ratios 10%/30%/100%) | 大图先在中心子集找变换、失败再放大 | 无 | **有意偏离**(产品):手机单帧全幅一次过,不做子集重试。 |
| 3 | 绿通道对齐(:351 `image.data[1]`) | 彩色图取绿通道配准 | 用 BT.601 luma(`stars.dart:57 rgbToLuma`) | **有意偏离**(产品) |
| 4 | 仅 ratio==1 时抛错(:378 catch `MaxIterError`) | 最终失败才判帧不可对齐 | `alignStars` 抛 `AlignException` → `pipeline._alignFrame` 映射为具体失败原因 | **一致**(规格:最终失败即拒帧) |

## E. DeepSkyStacker(**BSD-3**,© 2006-2019 LucCoiffier / © 2018-2025 D. C. Partridge 等)— M2 新增

对照我方 `engine/stack.dart`(κ-σ 与最大值)与 `engine/calibration.dart`(暗场/平场)。
读的文件:`DeepSkyStackerKernel/DSSTools.h`、`GreyMultiBitmap.cpp`、`BitmapExt.cpp`、`FlatFrame.cpp` / `FlatFrame.h`、`DeepSkyStacker/StackingParameters.cpp`、`RecommendedSettings.cpp`。

| # | 原仓函数 / 常量 | 输入→输出 / 关键常量 | 我方 文件:行号 | 判定 |
|---|---|---|---|---|
| 1 | `KappaSigmaClip`(DSSTools.h:606) | 排序后迭代 `lIteration` 轮:取当前窗口的均值 `m` 与**总体**标准差 `s`(`Sigma2` DSSTools.h:122,除以 `n` 不是 `n−1`),保留 `m−κs ≤ v ≤ m+κs`,窗口为空或本轮无剔除即停;结果 = 剩余值的均值 | `stack.dart:kappaSigmaClip`(排序后双端收缩,同一停机条件,结果取剩余均值) | **一致**。原仓每轮重建向量,我方因已排序改为「低端前缀 + 高端后缀」两个游标 —— 数值等价,单像素零分配(每像素都要跑一次,分配一次向量在 12 MP 上是 1200 万次) |
| 2 | `KappaSigmaClip` 空窗口 | 一轮把所有值都剔掉时 `bEnd = !lCurrentIndice` 结束循环,`DynStats.Average()` 对空集返回**有保护的 0**(`DynamicStats.h:45-50`),即这一像素被写成黑点 | `stack.dart`:`if (nhi <= nlo) break;` 丢弃这一轮、保留上一轮窗口 | **有意偏离**(健壮性)。⚠️ **2026-09-13 G8a 更正**:此格原写「对空集求平均 = 0/0 → NaN」是错的,原仓有除零保护、不产生 NaN;**它产生的是一个黑点**。偏离本身与理由都不变(成片上凭空出现的黑点比一个略偏的平均值更糟),只是原因描述现在准确了。测试 `a sample with no centre still returns a real number` 钉住 |
| 2b | `KappaSigmaClip` 的小样本 | 无特例:`n` 为几都照跑排序与迭代 | `stack.dart:kappaSigmaClip` 对 `count <= 2` 直接返回平均值、跳过剪切 | **一致**(等价捷径):`n=2` 时两个值各偏离均值恰好 1σ,`m ± 2σ` 必然同时容纳两者,迭代一轮即收敛到同一个平均值 —— 结果逐位相同,只是省掉排序。`n=0` 返回 0(原仓在此处是未定义行为) |
| 3 | κ 与迭代次数默认值 | `Stacking/Light_Kappa` = **2.0**、`Stacking/Light_Iteration` = **5**(StackingParameters.cpp:151-152) | `stack.dart:kKappa = 2.0`、`kKappaIterations = 5` | **一致**(逐字) |
| 4 | `Maximum`(DSSTools.h:106),经 `MBP_MAXIMUM`(GreyMultiBitmap.cpp:132) | 取该像素在所有帧里的最大值 | `stack.dart:stackBand` 的 `StackMode.max` 分支 | **一致**。我方额外把这个模式**与「跳过星点配准」绑定**(`pipeline.dart` 的 `trails` 分支):原仓的最大值合成仍走它的配准链路,而手机端「星轨」的产品定义就是不对齐 —— 记为下一条 |
| 5 | 最大值合成与配准的关系 | 原仓 `MBP_MAXIMUM` 之前照常做配准 | `pipeline.dart`:`StackMode.max` 时 `_alignFrame(trails: true)` 直接落盘、变换恒等,且参考帧不再因「太亮/星点太少」中止 | **有意偏离**(产品):对齐会把星轨这件事本身抵消掉;而月光下的地景本来就是这个模式的主体,用星点数当准入条件会把它挡在门外 |
| 6 | `CSubtractTask::process`(BitmapExt.cpp:1217,由 `CDarkFrame::Subtract` DarkFrame.cpp:1895 调用) | 逐通道 `tgt = max(minimum, tgt − src × factor)`,`factor` 默认 1.0、`minimum` 默认 0 | `calibration.dart:applyCalibration` 的 dark 分支(`v -= dark; if (v < 0) v = 0;`) | **一致**。我方不做 `factor`/`ShiftAndSubtract`:手机连拍没有 CCD 温度元数据可用来缩放暗场,也没有像素级偏移的场景 |
| 7 | `CFlatNormalization::Normalize`(FlatFrame.h:100)+ `ComputeFlatNormalization`(FlatFrame.cpp:119) | 先算主平场每通道的**全图均值**,再逐像素 `tgt *= mean[ch] / max(1.0, flat[ch])`,最后 `min(tgt, 255)` | `calibration.dart:measureFlatMeans`(逐通道全图均值)+ `applyCalibration` 的 flat 分支(`v * fm[ch] / max(1, d)`,上限 255) | **一致**(含 `max(1,·)` 与 255 上限两处边界)。我方只实现非 CFA 的 RGB 分支 —— 手机导出的是去马赛克后的 JPEG,拿不到 Bayer 阵列 |
| 8 | 主暗场/主平场的合成方式 | 默认 `MBP_AVERAGE`(StackingParameters.cpp:219/252);但**它自己的推荐引擎**在 2–15 张时推荐 `MBP_MEDIAN`(RecommendedSettings.cpp:570 / 634),>15 张才上 `MBP_MEDIANSIGMACLIP` | `calibration.dart:buildMasterRaw` 固定**中值**,并把每组校准帧封顶 `kMaxCalibrationFrames = 12` | **一致**(按原仓推荐档)。手机用户不会拍 16 张暗场,12 张封顶正好落在原仓推荐「中值」的区间里;一次漏光或反光被中值吃掉,被均值则会烙进整叠 |

| 9 | 主平场自身的校准(`MasterFrames.cpp:40-52`) | DSS 在 `ComputeFlatNormalization` **之前**先对主平场本身做 offset / dark-flat 减除,再算每通道均值 | `calibration.dart` 直接用**原始主平场**的均值归一,不对平场减任何东西 | **有意偏离**(产品):手机拍不出有意义的 bias/offset 帧(没有可控的最短曝光、没有恒温传感器),要求用户再拍一组 dark-flat 是把一个可选功能变成一道劝退门槛。代价:平场自身的暗电流没被扣掉,在手机平场的曝光量级下(均值几十到两百)这一项远小于测量噪声 |

**未采用的原仓能力(明记,避免下次重查)**:`MBP_MEDIANSIGMACLIP`(中值 κ-σ,>15 张才有意义)、`MBP_AUTOADAPTIVE`(自适应加权平均)、`MBP_ENTROPYAVERAGE`、bias/offset 帧与 dark-flat 帧(手机拍不出有意义的 bias)、`find_hot_pixels_in_master_dark` 式的坏点表(暗场直接相减已经覆盖同一批坏点)、`DetectFlatParts`。

对照测试(`test/calibration_test.dart` 11 项 + `test/engine_test.dart` 的 `kappa-sigma clipping` 6 项):
- 主暗场取中值:3 张一致 + 2 张漏光 → 主帧 = 12(中值),不是均值;
- 平场归一化:角落 50 / 中心 150、均值 100 → 校正后两处都是 100(暗角被抹平且整体亮度不变),即 §E-7 的公式在两侧同时成立;
- 暗场减除下溢钳零、平场结果上溢钳 255;
- κ-σ:干净样本不动、高/低离群各剔除一个、常数样本不除零、**5 张时离群值反而留下**(2σ 在小 n 下容不下,这是算法固有性质,已写进模式说明与测试名);
- 跨 `kCalibrationBandRows` 边界不留接缝(分带流式读的回归闸)。

---
最后核验(2026-09-13,M2):`flutter analyze` 0 issue;`flutter test` **77 通过**(含 `reference_test.dart` 11 项与 `calibration_test.dart` 11 项对照)。
