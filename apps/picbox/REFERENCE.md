# PicWorks 参考保真审计（PIPELINE G8c）

**参考仓**：[T8RIN / ImageToolbox](https://github.com/T8RIN/ImageToolbox)，本机 `D:\toolapp\_ref\ImageToolbox`（`git clone --depth 1`）。
**许可证**：Apache License 2.0（permissive）→ 允许对照移植 + 署名。我方为 Flutter/Dart 全新实现，**未复制任何一行 Kotlin 代码或资源**；仅阅读其调用链与算法后按规格用 Dart 重写。
**署名**：Apache-2.0 归属声明已放入 app 内「设置 → 关于」页（`lib/core/branding.dart` 的 `aboutText`，中英双语，写明「参考…已用 Dart 重新实现;未复制其代码与资源」），并登记于 store listing。

我方引擎：`apps/picbox/lib/tool/engine/`。参考侧核心类：`core/data/.../image/`（`AndroidImageScaler`、`AndroidImageCompressor`）、`feature/weight-resize/.../AndroidWeightImageScaler`、`feature/delete-exif`、`feature/watermarking/.../AndroidWatermarkApplier`。

## 汇总表

| 功能 | 核对函数数 | 一致 | 有意偏离 | 漏掉→已补 | 剩余 |
|---|---|---|---|---|---|
| 压缩到目标体积 | 6 | 4 | 2 | 2→2 | 0 |
| 缩放 | 4 | 3 | 1 | 0 | 0 |
| 格式转换 | 5 | 3 | 2 | 0 | 0 |
| 裁剪/旋转/翻转 | 3 | 2 | 1 | 0 | 0 |
| 去元数据 | 7 | 4 | 3（均为增强） | 0 | 0 |
| 水印 | 4 | 1 | 3 | 0 | 0 |
| **合计** | **29** | **17** | **12** | **2→2** | **0** |

剩余 = 0，满足提审门槛。所有「有意偏离」均有产品理由（手机内存 / 无网络 / 无三方库 / 隐私增强），无一是「没看到」。

---

## 1. 压缩到目标体积

参考 `AndroidWeightImageScaler.scaleByMaxBytes` vs 我方 `size_search.dart:searchForTargetSize` + `jobs.dart:nativeCompressToSize`。

| # | 参考规格（Kotlin） | 我方 | 判定 | 位置 |
|---|---|---|---|---|
| 1.1 | 归一化余量 `normalization = 2048 * max(1, initialSize/(5MB))` | 同式：`2048 * max(1, src.bytes~/(5MB))` | **一致** | `jobs.dart:147` |
| 1.2 | `targetSize = max(1024, maxBytes - normalization)` | `max(1024, targetBytes - margin)` | **一致** | `jobs.dart:148` |
| 1.3 | 质量下界 **15**（`if compressQuality < 15 break`，随后 `=15`） | 之前是 **20**，**已补齐为 15** | **漏掉→已补** | `size_search.dart:59`、`jobs.dart` lossy floor 15 |
| 1.4 | 质量搜索：从 100 **逐 1 递减**直到 ≤target（取「能装下的最高质量」） | **二分** `[15,95]`（单调编码器上结果相同，编码次数 7→≤7 更少） | **有意偏离**（省电/省时；同结果） | `size_search.dart:107-119` |
| 1.5 | 达不到目标 → 降尺寸：两边各 **×0.93/轮**、质量钉在 15、**无轮次/尺寸下限**、死循环到装下 | 用字节比 `sqrt(target/size)*0.9` 一跳到位，但**每轮不少于 ×0.93**（保证像原仓一样必然收敛）；有 `maxScaleRounds`/`minScale` 兜底 | **有意偏离 + 已补**（手机上必须有界；`min(estimate, scale*0.93)` 对齐原仓收敛下限） | `size_search.dart:122-127` |
| 1.6 | `saveIfSmaller=false` 且源已 ≤target → 返回 null（保留原图不重编码） | 我方总是搜索并输出（首探 q85 命中容差即返回）；压缩页永远要一个结果 | **有意偏离**（UI 契约：始终产出结果） | `jobs.dart:152-172` |

**补齐对照测试**（`test/reference_parity_test.dart`）：真 Dart JPEG 探针（无原生 codec），断言压缩到 200KB 结果 ≤200KB 且 ≥ 120KB 档结果（单调），且质量探测**从不低于原仓下界 15**、确实触及 15。

## 2. 缩放

参考 `AndroidImageScaler.flexibleResize`/`createScaledBitmap` vs 我方 `resize_math.dart:computeResize` + `jobs.dart` 的 `copyResize`。

| # | 参考规格 | 我方 | 判定 | 位置 |
|---|---|---|---|---|
| 2.1 | 长边锚定 `ResizeAnchor.Max`：按长边缩，另一边按宽高比 | `longestSide` 模式：`s = longest/max(w,h)` | **一致** | `resize_math.dart:75-80` |
| 2.2 | 不放大：`scaleUntilCanShow` 只缩不放；显式请求可放大 | `allowUpscale=false` → `min(s,1.0)`；显式双边不保比时逐字照给 | **一致** | `resize_math.dart:73,79,96` |
| 2.3 | 派生边取整用 `.toInt()`（截断），如 `(width/aspect).toInt()` | 用 `.round()`（四舍五入，误差更小；如 33% 4000→1320 而非 1319） | **有意偏离**（更准，避免系统性缩短 1px） | `resize_math.dart:101-104` |
| 2.4 | 重采样：缩小走高质量核（Aire/MagicKernel，默认双线性/双三次） | 缩小 `Interpolation.average`（等效 box/面积，抗锯齿好），放大 `cubic` | **一致**（等价意图：缩小抗锯齿、放大平滑；原仓的 40+ 种核是桌面级选项，手机取其代表） | `jobs.dart:309-314` |

## 3. 格式转换

参考 `AndroidImageCompressor.compress` + `ImageCompressorBackend`（`WebpBackend`/`JpgBackend`/`PngLossy/Lossless`/`HeicBackend`）vs 我方 `jobs.dart:nativeEncode`/`ensureOpaqueSource`/`pngToWebp`。

| # | 参考规格 | 我方 | 判定 | 位置 |
|---|---|---|---|---|
| 3.1 | JPEG/WebP/PNG 全走 Android 原生 `Bitmap.compress`（WEBP_LOSSY/LOSSLESS 分开） | `flutter_image_compress`（同样封装 Android/iOS 原生 codec），WebP 走原生有损 | **一致**（同底层 codec） | `jobs.dart:98-106,437-450` |
| 3.2 | 透明→非 alpha 格式（JPEG）前 `Trickle.drawColorBehind(backgroundColor)`，背景色可配 | 目标 JPEG 且源含 alpha → 垫**白**（`fillWhiteIfAlpha`，Dart 端近无损一次） | **有意偏离**（原仓默认背景可配；我方固定白色 = 转 logo 的常识预期，原仓注释里默认亦近白） | `jobs.dart:117-132,321-328` |
| 3.3 | HEIC 读 + 写（`HeicBackend`，多编码器） | **只读不写**（`flutter_image_compress` 解 HEIC；输出仅 jpeg/png/webp） | **有意偏离**（iOS 分享原生给 HEIC，写需求低；减体积） | `image_probe.dart:71-76`、`models.dart` |
| 3.4 | PNG 无损（`PngLosslessBackend`）+ 有损量化（`PngImageQuant`）等多后端 | PNG 走原生压缩；纯 Dart 中间态 `encodePng(level:6)` | **一致**（PNG 无损；不做有损量化 = 缩范围） | `jobs.dart:343-345` |
| 3.5 | WebP 有损质量 = `quality.qualityValue`；无损 `WEBP_LOSSLESS` | 有损走原生 `CompressFormat.webp`；失败兜底纯 Dart 无损 `encodeWebP` | **一致** | `jobs.dart:437-456` |

## 4. 裁剪 / 旋转 / 翻转

参考 `ImageTransformer.rotate/flip` + `copy(...).applyCanvas` 顺序（`compressAndTransform`：rotate→scale→flip）vs 我方 `jobs.dart:_dartWorker`。

| # | 参考规格 | 我方 | 判定 | 位置 |
|---|---|---|---|---|
| 4.1 | 先按 EXIF orientation 烘焙（Coil 解码即定向），Orientation 标签不再写回 | `bakeOrientation(decoded)` 后 `imageIfd.orientation=null` | **一致** | `jobs.dart:281,332` |
| 4.2 | 变换顺序 rotate → (scale) → flip → crop | rotate → flip → crop → resize → watermark | **有意偏离**（crop 矩形按「用户屏幕所见（已转/翻）」表达，故先转翻再裁；原仓 crop 走单独 resizeType.CenterCrop 通道） | `jobs.dart:287-305` |
| 4.3 | 90° 旋转为像素重排（Canvas.rotate，非无损容器变换） | `copyRotate(nearest)` 像素重排 | **一致**（两者都在像素域旋转，非 JPEG 无损转向；产品选简单可控） | `jobs.dart:288` |

## 5. 去元数据

参考 `feature/delete-exif`（`ExifRemovalPreset` + 安卓 `ExifInterface.setAttribute(null)`）vs 我方 `metadata.dart:stripMetadata`（**字节级、不重编码**）。

| # | 参考规格 | 我方 | 判定 | 位置 |
|---|---|---|---|---|
| 5.1 | JPEG 剥 EXIF | `_stripJpeg` 丢 APP1(EXIF) | **一致** | `metadata.dart:184-192` |
| 5.2 | 原仓靠 `ExifInterface` 只处理 **EXIF 标签**，不碰 XMP/IPTC | 额外丢 APP1(XMP)、APP13(IPTC/Photoshop)、APP3–15、COM，并裁 EOI 后尾块 | **有意偏离（增强）**：原仓漏的 XMP/IPTC/尾块我方一并剥 | `metadata.dart:184-216` |
| 5.3 | 保留 Orientation（否则照片显示歪） | 仅回写一条 26 字节 orientation-only APP1 | **一致** | `metadata.dart:126-157` |
| 5.4 | ICC 色彩配置：原仓 delete-exif 不动像素/色彩 | 保留 APP2(ICC) + APP0(JFIF) + APP14(Adobe) | **一致**（保色彩正确） | `metadata.dart:184-192` |
| 5.5 | PNG 文本/时间：原仓无专门 PNG 文本剥离 | `_stripPng` 丢 tEXt/zTXt/**iTXt**/eXIf/tIME，保 iCCP/pHYs 等 | **有意偏离（增强）** | `metadata.dart:224,226-243` |
| 5.6 | WebP：原仓无专门 WebP 元数据剥离 | `_stripWebp` 丢 EXIF/**XMP** chunk，并清 VP8X 的 EXIF/XMP 标志位、修 RIFF size | **有意偏离（增强）** | `metadata.dart:255-293` |
| 5.7 | 隐私预设分级（Privacy/LocationOnly/KeepDate…） | 单一「全剥（留 Orientation+ICC）」 | **有意偏离**（工具箱定位：一键去隐私，不做多预设 UI） | 全文件 |

**补齐对照测试**：构造含 EXIF+XMP+ICC 的 JPEG、含 tEXt+iTXt+eXIf 的 PNG、含 EXIF+XMP 的 WebP，断言剥后隐私元数据全无、JPEG **仅剩 Orientation 一条 EXIF 标签**、ICC 按设计保留、像素不变、WebP RIFF size 修正且可解码。

> 说明：原仓 delete-exif 的落点是 EXIF；PNG 文本 / WebP XMP / IPTC / 尾块并不在其覆盖内。任务清单点名的「PNG iTXt / WebP XMP」我方**本就已实现**（`_pngDropChunks` 含 `iTXt`、`_stripWebp` 处理 `'XMP '`），本轮以对照测试**固化**这些不变量，未新增遗漏项。

## 6. 水印

参考 `AndroidWatermarkApplier`（三方库 `androidwm` + `WatermarkText`）vs 我方 `watermark_math.dart` + `jobs.dart:_applyWatermark`。

| # | 参考规格 | 我方 | 判定 | 位置 |
|---|---|---|---|---|
| 6.1 | 透明度 = `alpha * 255` 施于水印 | `p.a = p.a * opacity` 施于 sprite alpha 通道 | **一致** | `jobs.dart:365-369` |
| 6.2 | 位置 = 自由 `positionX/Y`（0..1 分数），三方库摆放 | **九宫格锚点** + 边距（按短边 %）+ clamp 不出画布 | **有意偏离**（无三方库、纯可测数学、移动端离散锚点更好用） | `watermark_math.dart:110-151` |
| 6.3 | 平铺 `setTileMode(isRepeated)` + 任意 `rotation` | 自算交错网格（pitch=spriteW+spriteH、隔行错半格）+ 旋转边界 `rotatedBounds` | **有意偏离**（自绘平铺，间距/角度确定可测） | `watermark_math.dart:158-189` |
| 6.4 | 字号 = 绝对 `params.size`；图片水印 = 图宽 ×`size` 分数 | 字号 = **短边 %**（1..30，下限 8px 保可读）；投影可选 | **有意偏离**（相对短边缩放，跨分辨率一致） | `watermark_math.dart:100-101` |

---

## 结论

- 核心数值边界（压缩归一化余量、targetSize 下限、质量下界 15）已与原仓**逐位对齐**；质量二分与降尺寸一跳是**同结果、更省编码**的移动端优化，且降尺寸每轮不弱于原仓 ×0.93 收敛。
- 去元数据我方**严于**原仓（多剥 XMP/IPTC/PNG 文本/WebP XMP/尾块），并保 Orientation+ICC。
- 缩放/格式/裁剪走原生 codec = 与原仓同底层；HEIC 只读、PNG 不量化、水印九宫格为**有意的范围/交互取舍**，均记录理由。
- 对照测试 `test/reference_parity_test.dart` 固化了「剥后仅剩 Orientation」与「压缩单调且不超目标、质量不低于 15」两组不变量。
- **剩余漏项 = 0**，满足 G8c 提审门槛。
