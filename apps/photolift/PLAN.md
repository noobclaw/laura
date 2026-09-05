# PhotoLift / 离线老照片修复 — 产品规划 (v1, 2026-09-05)

## 一句话定位
把模糊的老照片(翻拍、扫描件、早期手机照)**在手机本地**用 AI 放大 2x/4x 并降噪,照片从不上传;一次买断 $6.99,没有订阅。

## 差异化楔子(G2)
**用户为什么选我而不是 Remini / 各家「老照片修复」:** 这一品类的头部全是「上传到云端 + 周订阅」(Remini 约 $4.99–9.99/周,中区 27 支同名 app 全部免费下载 + 订阅/次数付费),差评集中在**价格**和**把家人照片传到别人服务器**。PhotoLift 占的是空着的另一头:**模型内置、零联网权限(商店可验证)、一次买断**。楔子三要素:① 离线 / 零上传 ② 一次买断 ③ 干净(无账号、无广告、无水印订阅套路)。

### 命名决定
- 英文名 **PhotoLift**。App Store 精确搜索命中 `Photolift - Face & Body Editor`(Mimoza,`com.mimoza.photolift`,美体类)。Apple 的重名检查是整串比较,裸 `PhotoLift` 大概率可通过,但为避免撞名/混淆,**ASC 名称建议用 `PhotoLift: Offline AI Upscaler`(30 字符)**,副标题写清品类;显示名(CFBundleDisplayName / launcher)仍是 `PhotoLift`。
- 中文名:中区搜「老照片修复」命中 **27 支**,标题里含「老照片修复」的至少 15 支(`老照片修复-瞬间清晰`、`AI 老照片修复 4K 高清`、`老照片修复: ReliveAI`…),裸名完全没有辨识度,也过不了 Apple 的重名检查。**决定:中文显示名用「离线老照片修复」**(7 字,launcher 不截断;「离线」正是楔子),ASC 中文名建议 `离线老照片修复 PhotoLift`。命中列表中没有任何一支带「离线」前缀。
- 这些 app 在中国大陆不上架(与前七个 app 一致),中文本地化服务港台新马和海外华人。

## 参考实现分析(D:\toolapp\_ref,已 git-ignore)
| 仓库 | 许可证 | 看了什么 | 带走了什么 / 明确没带 |
|---|---|---|---|
| `xinntao/Real-ESRGAN-ncnn-vulkan` | BSD-3 | `src/realesrgan.cpp`:tilesize + `prepadding=10` 的分块流程;`use_fp16_packed/storage=true, fp16_arithmetic=false` 的数值配置;alpha 通道单独 bicubic;自带 GLSL pre/post-proc shader 在 GPU 上裁块/拼块 | **分块 + 复制边(replicate padding)+ 只保留中心区**的思路和 fp16 配置照搬到 `native/photolift_core.cpp`。**没用**它的自定义 SPIR-V shader(需要 glslang 运行时编译、两套 fp16/int8 变体、只在 GPU 路径可用):我们走 ncnn `Extractor` 的 CPU-Mat 输入/输出,ncnn 自动上传/下载,同一份代码在 CPU 和 Vulkan 上都能跑,代价是每块多一次 host↔device 拷贝(块 256² 时可忽略)。 |
| `EutropicAI/Final2x` | BSD-3 | `core/Final2x_core/SRqueue.py` / `SRclass.py`(队列 + 目标倍数与模型倍数分离,输出再 resize)、`src/renderer`(拖放队列、进度、设置持久化) | **「目标倍数 ≠ 模型倍数」**:它先跑模型倍数再整图 resize;我们在每块内做 4x→2x 的 2×2 box 下采样,输出缓冲只有 2x 大小,手机内存友好。进度按块上报、设置持久化两点照做。 |
| `upscayl/upscayl` | **GPL-3** | 只看 `renderer/components/main-content/`:`slider-view.tsx`(前后对比拖杆)、`lens-view.tsx`(放大镜)、`progress-bar.tsx`(百分比 + 取消)、`onboarding-dialog.tsx` | **只取 UX 结论、零代码**:前后对比用可拖分界线 + 左右角标签;结果页给「对比 / 放大细看」两种看法;进度带百分比和取消。`lib/tool/compare_slider.dart` 是独立实现。 |

## 技术选型(写码前定死)
### 模型:Real-ESRGAN `realesr-general-x4v3`(+ `wdn` 降噪变体),BSD-3
- **为什么不是 `realesrgan-x4plus`**:x4plus 是 RRDB 23 块、16.7M 参数、33 MB;compact 的 general-x4v3 是 SRVGGNetCompact(32 层 conv+PReLU、64 通道)、1.2M 参数,pnnx 报 **9.93 GFLOPs / 64² 输入块**,约为 x4plus 的 1/15。手机 CPU(4 大核 fp16 packed)按 20–40 GFLOPS 有效算力估:一张 1200×1600 老照片 4x ≈ 470 块(64²)≈ 4.7 TFLOP ≈ **2–4 分钟 CPU / 20–40 秒 GPU**;x4plus 在 CPU 上要半小时,不成立。
- **为什么不用 GFPGAN / CodeFormer 做人脸**:S-Lab 非商业许可,商业 app 不能用,M1 明确不做人脸修复(商店文案里也不承诺)。
- **降噪 = 权重空间插值**:Real-ESRGAN 的 `-dn` 参数就是把 `general-x4v3` 和 `general-wdn-x4v3` 的权重按比例混合。我们离线做好三档:`dn0`(关)/`dn05`(轻,50/50)/`dn1`(强 = wdn),各 2.4 MB fp16,共 7.3 MB 随包。
- **转换**:官方只发 `.pth`(v0.2.5.0 release),没有 ncnn 版。`scripts/convert_model.py` 用 PyTorch CPU + pnnx 把 `SRVGGNetCompact` trace 后导出 ncnn param/bin(输入 `in0`、输出 `out0`,bin 存 fp16)。**已验证**:用 ncnn python wheel 按 app 完全相同的分块/复制边/中心裁剪流程跑 300×220 测试图,与 PyTorch fp32 整图推理比 **PSNR 39.3 dB,平均误差 0.48/255**,块与块之间无缝;只有图像最外一圈像素有差异(torch 的 conv 零填充 vs 我们的复制边,后者反而不会出现暗边)。
- **动漫模型(x4plus-anime / animevideov3)不进 M1**:老照片是真人,后续可作「插画模式」加进来(官方 release 直接有 ncnn 文件)。

### 运行时:ncnn(Tencent,BSD-3)预编译包
- **Android**:`ncnn-20260526-android-vulkan.zip`(静态 libncnn + glslang,含 `lib/cmake/ncnn` 配置)。`android/app/build.gradle.kts` 的 `fetchNcnn` 任务在 configure 后、CMake 前从 GitHub Release 下载到 `android/app/build/ncnn/`(不进仓库),CMake 用 `find_package(ncnn)` 按 `ANDROID_ABI` 选目录。**首选 Vulkan,GPU 初始化失败或 `get_gpu_count()==0` 自动 CPU**;设置页有「GPU 加速」开关兜底驱动问题。ABI:arm64-v8a / armeabi-v7a / x86_64(x86_64 保证 CI 模拟器冒烟跑的是真原生库)。`minSdk=29`(ImageDecoder 缩放解码、MediaStore 免权限写入、Vulkan 普及)。
- **iOS**:`ncnn-20260526-ios.zip`(**CPU 版**,`ncnn.framework` + `openmp.framework` 静态库)。`scripts/fetch_ncnn_ios.sh` 下载到 `ios/Frameworks/`(git-ignore),Runner target 的第一个 build phase「Fetch ncnn」自动调它,所以**一次干净 checkout 的 `xcodebuild archive` 不依赖 workflow 改动**。**为什么不上 Vulkan**:ncnn 的 iOS Vulkan 版靠 MoltenVK 在运行时动态加载,MoltenVK 不在 ncnn 的包里,要从 Vulkan SDK 另取并随 app 打包(+ 约 10 MB),还要 Metal 链接和真机调试;没有本机 Xcode 的情况下风险太高。iOS 上 compact 模型 CPU 路径(A 系列 4–6 大核 + fp16)已在可接受范围,GPU 排 M2(见下)。ObjC++ 包装 `ios/Runner/PhotoLiftEngine.mm` 包住共享的 `native/photolift_core.cpp`,Swift 只碰 ObjC 接口。**没有 Podfile**(SPM 铁律),ncnn 以静态 framework 直接挂在 Runner。
- **共享核心** `native/photolift_core.{h,cpp}`(C++11、无异常/RTTI,因为 ncnn 预编译库把 `-fno-exceptions -fno-rtti` 传给使用者):RGBA/RGB 输入 → 分块(`tile 256`(GPU)/`192`(CPU),`overlap 12` 复制边)→ `Extractor` → 每块中心写回;`scale==2` 时每块 4x 输出做 2×2 box 下采样再写,输出缓冲只有 2x 大小。取消 = `std::atomic<bool>`,每块开始前检查;进度每块回调。**已用 NDK 28 clang 对三个 ABI 做过 `-Wall -Wextra` 编译检查(零警告)**,链接留给 CI。
- **内存上限**:输出 ≤ 24 MP 且长边 ≤ 8192;超出的输入先按比例缩小(Android `ImageDecoder.setTargetSize`、iOS ImageIO 缩略图,都自动应用 EXIF 方向),UI 事先告诉用户「原图较大将先缩到 W×H」。4x 一张 1500×1000 = 6000×4000 ≈ 96 MB RGBA + 编码时一份拷贝,现代机型可承受;`largeHeap=true`。
- **Dart 兜底引擎**(`lib/tool/fallback_upscaler.dart`,文件头大写标注 FALLBACK):`image` 包 cubic 重采样 + 轻 unsharp,降噪 = 高斯预模糊。**只在** `capabilities` 探测不到原生库时启用;结果全链路标 `EngineKind.dartFallback`,结果页显示「基础放大(AI 引擎不可用)」横幅,历史缩略图打点。CI 证明原生路径可用后无需改动——它本来就不是默认路径。

### 平台通道契约(Dart 不分平台)
- `photolift/upscale`:`capabilities`→`{native}`;`upscale{jobId,inputPath,outputPath,scale,model,useGpu,tag,tagText,maxOutPixels,maxOutLongEdge}`→`{outputPath,outWidth,outHeight,inWidth,inHeight,downscaled,engine,elapsedMs}`;`cancel`。错误码 `busy|engine_unavailable|engine_load_failed|decode_failed|too_large|inference_failed|write_failed|cancelled`。进度 EventChannel `photolift/upscale/progress`:`{jobId,done,total,stage}`。
- `photolift/media`:`pick`→`{path,width,height}|null`(Android 13+ 系统 Photo Picker / 老版本 OPEN_DOCUMENT;iOS PHPicker,**都不需要相册读权限**,文件拷进 cache);`saveToGallery{path,displayName}`(Android MediaStore `Pictures/PhotoLift`,免权限;iOS add-only 授权,拒绝 → `permission_denied` → UI 给「去设置」);`openSettings`。
- 免费角标由原生侧在编码前画进像素(Kotlin Canvas / CoreGraphics),Dart 兜底用 `image` 包画。

### 权限流程评审(G2)
- Android:**零权限声明**(manifest 还主动 `tools:node="remove"` 掉 INTERNET / 三个存储权限)。Photo Picker 与 MediaStore 插入都不弹框。
- iOS:只有 `NSPhotoLibraryAddUsageDescription`(en + zh-Hans 都写明「只在点保存时写入、不读相册、不上传」)。拒绝 → 结果页 SnackBar「没有写入相册的权限」+「去设置」按钮(`UIApplication.openSettingsURLString`)。PHPicker 是进程外的,不需要 `NSPhotoLibraryUsageDescription`,也就不会触发 ITMS-90683。

## 功能清单(M1)
- 选照片(系统选择器)→ 预览 + 尺寸角标 → 2x/4x(4x 带锁,点了弹 Pro)→ 降噪 关/轻/强(默认轻,可在设置改默认)→ 输出尺寸 + 预计用时(按引擎的秒/MP 学习值)→ 开始。
- 处理页:渐变进度环 + 百分比 + 剩余时间 + 阶段文案(读取 / AI 放大 n/N 块 / 保存)+ 取消;系统返回键 = 取消。
- 结果页:前后对比拖杆(原图与结果同一 `BoxFit.contain` 几何,像素对齐)/ 放大细看(InteractiveViewer 全分辨率);信息卡(倍数·降噪 / 尺寸 / 引擎·用时);保存到相册 / 分享(share_plus)/ 删除。
- 首页:hero 卡(渐变 + 三枚卖点 pill + 大按钮)、今日额度卡(三格进度 + 升级 Pro)、最近修复九宫格(点开结果页)、空状态。
- 设置:Pro 行(商店价 `ProPriceText`)、恢复购买、GPU 加速(仅 Android 显示)、默认降噪、清空修复记录(显示张数 / 占用 MB)、语言 / 隐私 / 关于(壳)。
- 历史:JSON(`lifted/` 目录 + `photolift.json`,壳 `JsonFileStore` 原子写);原图副本 + 结果 JPEG(q94)都在 app 私有目录。

## 定价(变现与定价标准)
- **免费**:每天 3 张、2x、结果右下角小标签「PhotoLift」。真可用:一张老照片 2x 就已经明显清晰。
- **Pro $6.99 一次买断**(`com.noobclaw.photolift.pro_unlock`,非消耗型):不限张数、4x、无标签。锚定:Remini 周订阅 $4.99–9.99(一年 $250+),「一次 $6.99 永久」是压倒性对比;同时高于标准工具档,因为 AI 模型是真功能。中区价 ¥ 参考 48 档(不上大陆,仅作港台定价参考)。
- 每个免费门都走 `lib/tool/pro.dart` 的 `showProSheet(context, reason:)`:4x 段、额度用完、结果页标签提示、设置页 Pro 行。`grep buyPro(` 只在 pro.dart / core/purchase.dart。

## CI(build-app.yml / build-ios.yml 均未改)
### Android — 无需改 workflow
1. `flutter pub get / analyze / test` 照旧。
2. `flutter build apk` 触发 `fetchNcnn`(约 33 MB 下载,已挂到 `preBuild` 和所有 `configureCMake*/buildCMake*` 任务)→ AGP 自动装 NDK 28.2 + CMake 3.22.1(license 步骤已接受)→ 三个 ABI 各编一份 `libphotolift.so`(静态链 ncnn+glslang,预计每 ABI 6–10 MB,fat APK +25 MB,AAB 按 ABI 拆)。
3. 「Verify shipped permissions」不受影响:manifest 剥 INTERNET,ncnn 不声明任何权限。
4. smoke-test 用 x86_64 模拟器,APK 含 x86_64 原生库;app 启动时**不碰** Vulkan(引擎在第一次点「开始修复」时才创建),所以 swiftshader 不影响冒烟。
5. `gradle.properties` 已抬到 fieldstamp 同档(Xmx4096m / Metaspace 1024m)。

### iOS — 无需改 workflow;可选的最小改动
- 现状:Runner target 第一个 build phase「Fetch ncnn」= `bash "$SRCROOT/../scripts/fetch_ncnn_ios.sh"`(`ENABLE_USER_SCRIPT_SANDBOXING = NO` 已是壳默认),`xcodebuild archive` 自己会下载 `ios/Frameworks/{ncnn,openmp}.framework`。`flutter build ios --config-only` 不跑 phase,不受影响。
- **建议(可选)在 `build-ios.yml` 的「Flutter configure」之前加一步,日志更清楚、失败更早**:
  ```yaml
  - name: Fetch native frameworks (apps that ship one)
    run: |
      if [ -f scripts/fetch_ncnn_ios.sh ]; then bash scripts/fetch_ncnn_ios.sh; fi
  ```
  (`working-directory` 已是 `${{ inputs.app }}`。)不加也能编;加了以后 Xcode 里的 phase 会因版本标记文件直接跳过。
- 其它 iOS 铁律核对:无 Podfile ✅;`TARGETED_DEVICE_FAMILY = 1` ✅(壳);竖屏锁定 ✅;`CFBundleDisplayName` 英文 + `zh-Hans.lproj/InfoPlist.strings` 中文 ✅(用 Write 工具 UTF-8 写入,不经 Windows shell);plist 只有一条 usage key ✅;Kotlin 通道有 Swift 对应物 ✅;`share_plus` 传 `sharePositionOrigin` ✅;无 UIBackgroundModes ✅。

## 原生集成状态(交接用)
| 项 | Android | iOS |
|---|---|---|
| ncnn 获取 | Gradle `fetchNcnn`(Release zip → build/ncnn) | `scripts/fetch_ncnn_ios.sh`(Xcode phase 自动调) |
| 引擎 | Vulkan 优先,CPU 兜底(`ncnn-gpu` / `ncnn-cpu`) | CPU(`ncnn-cpu`);Vulkan/MoltenVK 排 M2 |
| 图片解码 | `ImageDecoder` 目标尺寸解码,EXIF 已转正 | ImageIO 缩略图 + `kCGImageSourceCreateThumbnailWithTransform` |
| 编码 | `Bitmap.compress(JPEG 94)` tmp+rename | `CGImageDestination`(JPEG 0.94)tmp+move |
| 选图 | `ACTION_PICK_IMAGES`(33+)/ `OPEN_DOCUMENT` | `PHPickerViewController` |
| 存相册 | MediaStore `Pictures/PhotoLift`(IS_PENDING) | `PHPhotoLibrary`(add-only) |
| 已本地验证 | C++ 三 ABI 编译零警告;模型转换 PSNR 39.3 dB;Dart analyze 0 / test 18 全过 | Swift/ObjC++ **未编译**(无 Xcode);pbxproj 由 `scripts/patch_ios_project.cjs` 文本改写,需 CI 验证 |
| Dart 兜底 | `fallback_upscaler.dart`,同接口、明确标注 | 同左 |

## 已知风险 / 需要真机
1. **Vulkan 驱动差异**:Adreno 5xx / 旧 Mali 上 fp16 storage 可能出错或花屏 → 设置页「GPU 加速」关掉走 CPU;M2 可按 GPU 型号自动黑名单。
2. **速度**:估算表在 `eta.dart`(GPU 1.6 s/MP、CPU 12 s/MP 起步,EMA 学习)。真机第一跑之前的估计可能偏差一倍,跑一次后收敛。
3. **iOS 编译**:pbxproj 手改(新增 4 个源文件、2 个 framework、strings variant group、1 个 phase、3 个 config 的 search paths + `gnu++17`),没有 Xcode 只能靠 CI 验证;`ncnn.framework/Headers` 是符号链接,macOS unzip 会保留。若 CI 报 `net.h not found`,看 fetch 脚本末尾打印的 Headers 目录结构,调整 `HEADER_SEARCH_PATHS`。
4. **ncnn iOS 包架构**:官方 `ios` 包只有 arm64 真机(模拟器是另一个 zip),CI `generic/platform=iOS` 归档正好;本地模拟器跑不了,不影响。
5. **HEIC**:Android 端 ImageDecoder 可解 HEIC(API 28+);iOS ImageIO 可解。输出统一 JPEG。
6. **R8**:JNI 静态方法与 `Progress.onProgress` 有 keep 规则(`proguard-rules.pro`);若冒烟里点「开始」崩在 `GetMethodID`,先查 mapping。

## 真机验收清单(G7)
- [ ] 首次打开:首页 hero / 额度卡 / 空状态正常,深色模式切换正常。
- [ ] 选照片:系统选择器弹出(**不**出现任何权限弹窗),取消返回首页无异常。
- [ ] 2x 轻降噪跑一张约 1200×1600 翻拍照:进度环走动、块数递增、剩余时间下降;结果页对比拖杆左右像素对齐;右下角有小标签。
- [ ] 处理中点「取消」/ 按返回:≤ 1 块时间内回到设置页,无残留文件(设置 → 清空记录里张数不变)。
- [ ] 一张 12 MP 手机照 2x:提示「先缩到 W×H」,不 OOM。
- [ ] 保存到相册:iOS 第一次弹「添加照片」授权;拒绝后 SnackBar 带「去设置」;允许后相册出现 `PhotoLift_…_2x.jpg`。Android 无弹窗,相册 `Pictures/PhotoLift` 出现文件。
- [ ] 分享面板可用(iPhone)。
- [ ] 免费额度:第 4 张弹 Pro 页;4x 段点击弹 Pro 页;沙盒购买后 4x 可用、无标签、额度卡变 Pro;卸载重装「恢复购买」找回。
- [ ] Android 设置关掉「GPU 加速」再跑一张,结果页引擎显示「AI · CPU」;开着显示「AI · GPU」。
- [ ] 中英文切换后所有页面文案随之变化;关于 / 隐私政策无「相机 / Android」等错话。

## M2 候选
- iOS GPU:ncnn `ios-vulkan` 包 + 随 app 打包 MoltenVK.xcframework(Apache-2.0)+ `Metal.framework`。
- 批量处理(队列 + 后台前台服务 / iOS `beginBackgroundTask`)。
- 插画模式(`realesr-animevideov3` / `x4plus-anime`,官方 ncnn 文件直接可用)。
- 人脸修复:需要商业友好的模型(GFPGAN/CodeFormer 不行);先看 `RestoreFormer`/`GPEN` 许可证。
- 自适应图标(Android adaptive icon)、结果保留 EXIF 拍摄日期、HEIC 输出。
