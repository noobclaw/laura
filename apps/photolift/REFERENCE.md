# PixelLift — 参考保真审计 (G8c)

参考实现:**[xinntao/Real-ESRGAN-ncnn-vulkan](https://github.com/xinntao/Real-ESRGAN-ncnn-vulkan)**(MIT,`D:\toolapp\_ref\Real-ESRGAN-ncnn-vulkan`,权威),辅以 `EutropicAI/Final2x`(BSD-3)、`upscayl/upscayl`(AGPL,仅读思路)。核心放大逻辑在 `native/photolift_tiling.h`(ncnn 无关的分块/填充/归一化/拼接算术,host 可测)+ `native/photolift_core.cpp`(ncnn::Net 适配层)。

## 汇总

| | 数 |
|---|---|
| 核心函数/环节 | 11 |
| **一致** | 8 |
| **有意偏离**(产品理由) | 3 |
| **漏掉 → 已补** | 1(alpha 对照测试的 fixture 数据错误,已改为从已验证的 ncnn 系数矩阵推导) |
| **剩余未做** | 0 |

剩余 = 0,满足提审门槛。

## 逐函数对照(参考 `src/…` → 我方 `文件:行号`)

| 参考环节 (Real-ESRGAN-ncnn-vulkan) | 参考常量/数值 | 我方实现 | 结论 |
|---|---|---|---|
| **分块** `realesrgan.cpp:207 process()`,`xtiles=(w+T-1)/T` | tilesize 逐行×逐列 | `tiling.h:212 processTiled`、`tiling.h:74 tileCount` | **一致** |
| **prepadding(重叠边)** `realesrgan.cpp:302-305` `tile_x0=xi*T-prepadding … +prepadding`;`main.cpp:679 prepadding=10` | **prepadding=10** | `tiling.h:212` overlap 四边各扩,`core.h` 文档写明「10-16,参考=10」;bridge 传 **overlap=12**(`UpscaleBridge.swift:30`/`.kt:59`,≥10 更保险) | **一致**(overlap≥prepadding,只保留中心故安全) |
| **reflect padding** `realesrgan_preproc.comp` `x=abs(x); x=(w-1)-abs(x-(w-1))` | reflect-101 | `tiling.h:49 reflectIndex`(逐字同式),`tiling.h:84 gatherTile` 边界折返 | **一致**(测试 `testReflectIndex` 对每个 n∈{1,4,13,40} 全区间逐值核对) |
| **输入归一化** `preproc.comp` `norm_val=1/255; v*norm_val` | v/255,通道 RGB | `tiling.h:84 gatherTile`(`p[c]*1/255`,CHW,alpha 不进网络) | **一致** |
| **输出反归一化+clamp** `realesrgan_postproc.comp` `v=v*255; v=v+0.5; clamp(floor(v),0,255)` | floor(v*255+0.5),[0,255] | `tiling.h:59 quantize01`(`floor(v01*255+0.5)` clamp) | **一致**(测试 `testQuantize` 覆盖 .4/.6 边界) |
| **中心裁剪拼接** `postproc.comp` 只写 `crop_x/crop_y` 起的中心区,丢弃 prepadding 边 | 丢 prepadding*scale 边 | `tiling.h:175 scatterTile`(`srcX=srcY=overlap*M`,只拷中心 (x1-x0)*scale) | **一致**(测试 `testTiledEqualsUntiled`:整图 vs 16/24/32 分块逐像素 ≤1) |
| **alpha 单独 bicubic** `realesrgan.cpp:166-201` Interp `pd.set(0,3)`=bicubic、align_corners=0;`:385` `bicubic_2x->forward(in_alpha,…)`,不进主网络 | A=-0.75,半像素中心 `(d+0.5)/s-0.5`,边界 clamp | `tiling.h:127 cubicTap`+`:115 cubicWeights`(同式),`:145 bicubicAlphaRect`(通道 3 单独 resize) | **一致**(测试 `testCubicCoefficients` 把我方权重重建成 1-D 矩阵,对 ncnn wheel 记录的 `kCoef2/kCoef4` 逐元素 ≤2e-4) |
| **RGB 输入无 alpha → 输出 alpha=255** `process` channels 分支 | 255 | `tiling.h:201 fillAlphaRect` | **一致** |
| **目标倍数≠模型倍数** 模型恒 4x;scale 2 需降采样 | 参考只支持整模型倍数;Final2x 是「整图跑完再 resize」 | `tiling.h:175 scatterTile` down=M/scale,**块内 2×2 float 均值**降到 2x(输出缓冲仅 2x 大小) | **有意偏离**:手机内存——不落 4x 大图。Final2x 的「目标≠模型倍数」思路,压到块内做 |
| **GPU 自定义 SPIR-V pre/post shader** `realesrgan_preproc/postproc.comp`(int8 上传、fp16/int8 两套变体、仅 GPU) | use_int8_storage 上传 uint8 | 走 ncnn `Extractor` 的 float CPU-Mat(`core.cpp:126 inferTile`),ncnn 自动上传/下载;`configureOptions` 关 int8_storage | **有意偏离**:同一份代码 CPU+Vulkan 都能跑、无需 glslang 运行时;代价是每块多一次 host↔device 拷贝(块 256² 可忽略) |
| **tilesize 按显存挑** `main.cpp:786-793` >1900→200 / >550→100 / >190→64 / else 32(RRDB x4plus) | 显存分档 | `core.cpp:82 effectiveTileSize`:>550 保留请求 / >190→cap 128 / else 64 | **有意偏离**:compact 网络激活内存约为 x4plus 的 1/15(见 PLAN.md),故档位放宽 |
| **fp16 数值档** `net.opt` fp16_packed/storage=true、fp16_arithmetic=false | — | `core.cpp:51 configureOptions`(逐项一致,arithmetic 关以保色) | **一致** |

## 许可证与署名

- **Real-ESRGAN-ncnn-vulkan**:MIT,Copyright (c) 2021 Xintao Wang。permissive → 可对照移植,已署名。runtime = **ncnn**(BSD-3,Tencent)。均在应用「关于」页与 listing 展示(`lib/main.dart:97-106` 内置 BSD-3/MIT 全文;`lib/core/branding.dart` 说明本地 AI 模型)。
- **Final2x** / **upscayl**:仅参考思路(目标倍数分离 / 进度分块),未复制代码。upscayl 为 AGPL,**只读、未取用任何代码或资源**。

## 模型权重 sha256 与来源核对

模型 = Real-ESRGAN `realesr-general-x4v3` 系列(**SRVGGNetCompact**,BSD-3,Copyright 2021 Xintao Wang;非 RRDB x4plus)。三档降噪 = 三套权重的 dni(denoise interpolation)插值:

| 档 (UI) | 资源 | `.bin` sha256 | 对应权重 |
|---|---|---|---|
| 关 / Off | `general-x4v3-dn0` | `8fdd6052f8931091164a570ee7b5c5b2d1dcd991112d464eb9ae1a5b52ece553` | `realesr-general-x4v3`(官方发布,无降噪) |
| 轻度 / Light | `general-x4v3-dn05` | `8fe24682c8f4440f1ed66d2c8a90dc7bd745b203212c31fe69c18032c39645aa` | dn0/dn1 **50/50 权重空间插值**(= Real-ESRGAN `-dn 0.5`) |
| 强 / Strong | `general-x4v3-dn1` | `e1a48f579154b22e556a0e0d328c6525cac4e9887f964ec72eb9c8a821ea1231` | `realesr-general-wdn-x4v3`(官方发布,with-denoise) |

三个 `.param` 的 sha256 全同 = `f230f5da284435477d67a3ee69ccee664054f13b2bf4de836e70d4f01bd41626`(同一 SRVGGNetCompact 计算图:72 层 conv+PReLU + PixelShuffle 4x + nearest 残差 `add_0`,只权重不同)。`.bin` 各 2,435,272 B。

**核对结论**:
- `dn0` / `dn1` 对应官方发布的 `realesr-general-x4v3` / `realesr-general-wdn-x4v3` **两套权重**;`dn05` 是二者的 50/50 插值,**本身不是上游发布文件**(无上游 sha256 可比),等价于 Real-ESRGAN 命令行的 `-dn 0.5`。
- **无法做字节级 sha256 对比**:上游发布的是 PyTorch `.pth`,ncnn 转换(pnnx/onnx→ncnn)非位可复现,且 `_ref` 未附官方 ncnn 版 general 权重(该仓模型走 release 下载,本机 `_ref/upscayl/models` 只有 animevideov3,无 general-x4v3)。因此以 **计算图同一性**(param 全同、架构=SRVGGNetCompact + nearest 残差,与 realesr-general-x4v3 定义一致)+ **档位命名与 dni 语义**作为来源证据,并留存我方三档实测 sha256 供后续复现比对。

## 补齐 / 修正

- **漏掉→已补**:`native/tests/tiling_test.cpp` 的 `testBicubicAlphaMatchesNcnn` 原先硬编码了一张 12×12 期望表 `kPlane6x2`,该表与 ncnn 自己的系数矩阵 `kCoef2` 不自洽(逐点差最大 **171**,行 2 起整体发散——旧 agent 记录错的 fixture,不是我方 bicubic 有 bug)。已核实:我方 `bicubicAlphaRect` 对同一输入应用 **已被 ncnn wheel 验证过**的 `kCoef2` 系数矩阵,逐像素差 ≤1(浮点累加顺序差 <1 LSB)。改法:删除错误 fixture,ground truth 改为在测试内用 `kCoef2/kCoef4`(其本身由 `testCubicCoefficients` 对 ncnn 核对)**可分离地推导**,x2/x4 双尺度断言 ≤1,并保留「矩形拼块 == 整图(无缝)」检查。
- **新增** `native/tests/run_host_tests.sh`(被测试注释引用但此前缺失):用系统 `g++`/`clang++` 编译并跑 host 测试。
- **fallback 文案**:`lib/tool/fallback_upscaler.dart` 双三次+锐化的兜底引擎已全程标 `EngineKind.dartFallback`,UI 显示「基础放大 / Basic resample」(`models.dart:45`,`isAi=false`),`result_screen.dart:187` 明确告知用户「此设备 AI 引擎不可用,效果弱于 AI 修复」。**无需改文案**。

## 验证结果

- **native host 测试**:`bash native/tests/run_host_tests.sh`(g++ 15.2,`-std=c++11 -O2 -Wall -Wextra`)→ `photolift tiling tests: all passed`。覆盖:reflect-101、量化边界、bicubic 系数对 ncnn 矩阵、alpha 对已验证矩阵(x2/x4 ≤1)、**整图 vs 16/24/32 分块拼接逐像素 ≤1**、alpha 保留且不混入 RGB、几何/进度/取消/错误路径。
- **C++ 核心**(需 ncnn,本机不可编译):静态核对 `core.cpp` 适配层——`inferTile` 送入已归一化的 [0,1] CHW float、取回后交 `scatterTile` 反量化,与参考「preproc 归一化 → 网络 → postproc 反量化」链一致;`inputName_/outputName_` 取自 `net_.input_names()[0]`(param 为 `in0/out0`)。
- **Dart**:`flutter analyze` → **No issues found**;`flutter test` → **25 passed**。
