# PicWorks 图片万能箱 — 产品规划 (M1)

> 立项 2026-09-05(用户当日批准)。目录 `apps/picbox`,applicationId `com.noobclaw.picbox`,iOS bundle `com.noobclaw.picbox`,内购 `com.noobclaw.picbox.pro_unlock`。
> 参考实现 `T8RIN/ImageToolbox`(Kotlin,Apache-2.0,14.5k★,仅 Android),浅克隆在 `_ref/ImageToolbox`(git-ignored)。

## 命名决定(2026-09-05 实搜 App Store)

原拟名 **PicBox / 图片工具箱** 两个都撞名,弃用:
- `PicBox`:美区已有 `PicBox - Smart Photo Frame`、`PicBox: Private Photo Sharing`、`AI Photo Generator: Picbox`、`PicBox - Send, Make!` 四支。
- `图片工具箱`:中区**同名在位** `图片工具箱 - 多功能图像处理神器`(商汤 Beijing Shangtang Technology),另有 `PicToolbox - 图片工具箱`。
- 备选 `PixKit`(PinFong Limited 已用)、`图片百宝箱`(刘仕清已用)、`图片工坊`(`图片工坊-AI图片&视频创作工具` 已用)也撞。

**定名:英文 `PicWorks`(美区/中区均无同名),中文 `图片万能箱`(中区无同名)。** 文件夹与包名保持 `picbox`(用户指定,包名不对外显示)。

## 一句话定位
给 iPhone / Android 用户的**一站式离线图片工具箱**:压缩、缩放、格式转换、裁剪旋转、去元数据、加水印,六个工具全部支持批量,全程本地处理、不申请网络权限,一次买断。

## 差异化楔子
**用户为什么选我而不是竞品**:iOS 上没有一个「一站式 + 离线 + 买断」的图片工具箱——在位者要么是单功能订阅制(压缩一个 app、去 EXIF 一个 app、水印一个 app,各收一份订阅),要么是联网上传处理的网页壳。PicWorks 把六件常用小工具装进一个买断 app,**批量、离线、中文优先**,图片不出手机。
楔子三要素:① 六合一(不用装六个 app)② 真离线(无 INTERNET 权限,可验证)③ 买断不订阅($4.99,对标单功能订阅 app 年费的 1/3 以下)。

## 参考实现分析(ImageToolbox,Apache-2.0)

> 只读其代码写成本节规格,再按规格用 Dart 从零实现;**未复制任何代码与资源**。`Branding.aboutText` 含 Apache 署名。

### 功能清单(原项目 60+ 工具,按模块)
- 核心图像:SingleEdit、ResizeAndConvert、**WeightResize(按体积压缩)**、LimitResize(限最大边)、**FormatConversion**、**Crop**、**DeleteExif**、EditExif、**Watermarking**、Filter、Curves、Draw、MarkupLayers、EraseBackground、CompressionLab
- 拼接/切分:ImageStitching、ImageSplitting、ImageCutter、ImageStacking、MultiFrameFusion、CollageMaker、Photomosaic、Compare
- 动图/特殊格式:Gif/Apng/Webp/Jxl Tools、SvgMaker、AsciiArt
- PDF 工具 30 余项、颜色/渐变/噪声/分形生成、加解密、校验和、Base64、压缩包、批量重命名、重复图查找、OCR、扫码、文档扫描 等
- 加粗的是本 app 取用的能力。

### 处理管线(原版)与本 app 的对应
| 项 | 原版做法 | PicWorks 做法 |
|---|---|---|
| 总顺序 | rotate → scale → flip → 拦截器(水印等)→ 垫底色 → 编码 | Dart 路径:bakeOrientation → rotate → flip → crop → resize → watermark → 垫白(JPEG)→ 编码 |
| EXIF 方向 | Coil 解码时**隐式烘焙进像素**;保存时**从不写回 Orientation**(MetadataTag 枚举 150+ tag 唯独没有 Orientation) | 解码后 `bakeOrientation`;写出时 Orientation 置空;原生路径 `autoCorrectionAngle` + 插件把 Orientation 归一为 1。**去元数据(无损)例外**:保留一个只含 Orientation 的 32 字节 APP1,否则手机竖拍照会横着显示 |
| 按体积压缩 | 质量从 100 起**线性 −1** 到 15(最坏 86 次编码),仍超标则宽高各 ×0.93 无上限循环;安全余量 `2048 × max(1, size/5MB)`,目标下限 1024 B | **二分**质量 20..95(≤7 次),仍超标按 `sqrt(target/size)×0.9` 估算缩放,最多 3 轮、最小 0.15;**沿用**安全余量与 1 KB 下限;容差 10% 内提前停 |
| 缩放 | Explicit / Flexible(锚点 Width/Height/Max/Min)/ CenterCrop / Fit;取整 `toInt()` 截断;默认 Bilinear | 像素(单边跟比例、双边框内适配、不保比拉伸)/ 百分比 / 最长边;**四舍五入**;默认不放大;缩小用 average、放大用 cubic。原生路径 `minWidth/minHeight` 框内适配 |
| 格式转换 | 32 种输出格式;JPEG 等不含 alpha 的格式**垫底色,默认不透明黑** | 输出 JPEG/PNG/WebP;JPEG **垫白**(更符合 logo 转换预期);HEIC 只读,导入时转成 JPEG 工作副本 |
| 元数据 | 删除工具不重编码像素(字节流原样复制,只清 tag);预设 All/Privacy/LocationOnly/KeepDateAndCopyright | 字节级无损剥离:JPEG 去 APP1/APP2(非 ICC)/APP3-15/COM 并截掉 EOI 之后的尾巴(motion photo),保留 JFIF/ICC/Adobe;PNG 去 tEXt/zTXt/iTXt/eXIf/tIME;WebP 去 EXIF/XMP 并清 VP8X 标志。M1 只做「全部移除」 |
| 水印 | Text/Image/Stamp;归一化坐标 + 九宫格(Stamp);默认 alpha 0.5、rotation 45、**平铺默认开**;文字 size 为相对比例 | 文字水印;九宫格锚点 / 平铺(角度 −90..90);大小=短边百分比、边距=短边百分比、不透明度、5 色、投影;预览与导出共用同一套放置算法 |
| 裁剪/旋转 | 26 个比例预设;裁剪页连续 −45..45° 微调;90° 步进;只有水平翻转 | 13 个比例预设(Free/原图/1:1/4:3/3:4/16:9/9:16/3:2/2:3/4:5/5:4/2:1/21:9);90° 步进;水平 + 垂直翻转;每张独立编辑,可「应用到全部」 |
| 批处理 | 严格串行;编码全局单线程;逐文件失败不中断;前台服务通知进度 | 串行;像素运算在 `Isolate.run`,原生编解码走 flutter_image_compress;逐文件失败记入结果行不中断;底部进度面板可「完成当前这张后停止」 |
| 命名/位置 | `Prefix_Orig(W)x(H)Date_Rand[Seq]…` 默认存 `Documents/ImageToolbox/` | `<原名>_<工具后缀>.<ext>`(重名加 `_2`);结果先在临时目录,用户点「保存到相册」/「分享」才离开 |

### 里程碑
- **M1(本轮)**:六工具 + 批量 + Pro 门 + 前后对比 + 中英双语 + 双平台配置 + 图标/文案。
- **M2**:按标签删元数据(GPS-only / 保留日期与版权)、编辑 EXIF、图片水印(logo)、时间戳水印、限最大边(LimitResize)、输出保留到「文件」。
- **M3**:长图拼接/切分、拼贴、GIF/APNG 工具、色彩曲线与滤镜、HEIC/AVIF 写出(需原生)。

## 招牌功能架构评审(G2)
- **编解码分两路**:① 原生路径 `flutter_image_compress`(iOS ImageIO / Android BitmapFactory)负责压缩、缩放(缩小)、转格式——快 10 倍、读 HEIC、写有损 WebP、可保留 EXIF;② Dart 路径 `package:image` 在 `Isolate.run` 里负责裁剪/旋转/翻转/水印/透明垫白/放大拉伸——一次解码一次编码。实测本机 JIT 12 MP JPEG 解码 ≈2 s、编码 ≈2 s,手机 AOT 同量级,可接受;按体积压缩的多次试编码**必须**走原生。
- **HEIC 最终形态**:只读。iOS 上 `image_picker`(PHPicker)已把 HEIC 转成 JPEG 交给我们;Android 上 HEIC 原样返回,导入时用原生转成 JPEG 工作副本(API 28+,更低版本明确提示跳过)。**不写 HEIC**。
- **WebP**:`package:image` 只有无损 VP8L 编码;有损 WebP 走原生(iOS 经 SDWebImageWebPCoder,较慢),原生失败时退回无损 WebP,仍是合法文件。iOS 上 WebP 无法写入 EXIF(插件限制,UI 有提示)。
- **文字水印的 CJK**:`package:image` 自带字体无中文,文字精灵在 UI isolate 用 `TextPainter` 渲染(系统字体,支持中文/emoji)成 RGBA,再传给 isolate 合成;不透明度在精灵 alpha 上乘。
- **去元数据不重编码**:字节级剥离(见上表),含 EOI 之后的尾巴;只保留 Orientation。单测覆盖 JPEG/PNG/WebP、ICC 保留、COM 删除、尾巴截断、像素逐点一致。
- **内存**:12 MP RGBA 在 Dart 里 ≈48 MB,一次只处理一张;缩略图 `cacheWidth` 解码;裁剪/水印预览 `cacheWidth: 1200`。

## 权限流程评审(G2)
| 权限 | 触发 | 拒绝反馈 | 永久拒绝出口 |
|---|---|---|---|
| 相册读取 | 不需要:iOS PHPicker / Android Photo Picker 都免权限;`NSPhotoLibraryUsageDescription` 按 image_picker 要求仍写入 | — | — |
| 相机 | 用户点「拍摄」 | `camera_access_denied` → 具体提示 + 「去设置」 | `openAppSettings()` |
| 相册写入 | 用户点「保存到相册」;`Gal.hasAccess/requestAccess`(iOS 只要 Add-only) | 提示「没有相册写入权限…可改用分享」+「去设置」 | `openAppSettings()`;分享作为替代路径 |
| Android 存储 | 仅 API ≤29 声明 `WRITE_EXTERNAL_STORAGE(maxSdk 29)` + `requestLegacyExternalStorage`(gal 要求);30+ 走 MediaStore 免权限 | 同上 | 同上 |
| 网络 | `INTERNET tools:node=remove` | — | — |
另剥离:READ_EXTERNAL_STORAGE / READ_MEDIA_IMAGES / CAMERA / RECORD_AUDIO(图片选择器不需要;声明 CAMERA 反而会让 Intent 拍照要求运行时权限)。

## iOS 平行检查
- `Info.plist`:`NSPhotoLibraryUsageDescription`、`NSPhotoLibraryAddUsageDescription`、`NSCameraUsageDescription` 三条,英文默认 + `zh-Hans.lproj/InfoPlist.strings` 中文(UTF-8 无 BOM,`file` 已验),`CFBundleLocalizations` en/zh-Hans,`project.pbxproj` 已登记 InfoPlist.strings(与 fieldstamp 同结构)。
- **未写 `NSMicrophoneUsageDescription`**:app 不录音、不拍视频,没有真实用途可写。image_picker README 说仅录像才需要;**风险**:若 ASC 上传后在 TestFlight → Build Uploads 报 ITMS-90683(Microphone),须回来补一条或换 picker(见「真机/上传验证清单」)。
- 竖屏锁:`UISupportedInterfaceOrientations` 仅 Portrait + Android `screenOrientation=portrait` + `SystemChrome`。
- `TARGETED_DEVICE_FAMILY = 1`(iPhone-only,继承 shell)。无 `UIBackgroundModes`。不提交 Podfile(flutter_image_compress / gal / image_picker 都有 SPM;若 CI 生成 Podfile 走 CocoaPods 亦可)。
- 无 platform channel 自写代码,无 Kotlin/Swift 差异。
- 平台差异写进代码:iOS WebP 不带 EXIF(UI 提示);iOS HEIC 由 picker 转 JPEG;Android HEIC 需 API 28+。

## 定价(变现标准)
- 免费:六个工具全功能,**每次最多 3 张**;无水印预设;无 WebP 导出;设置不记忆。去元数据对 JPEG/PNG/WebP 无损,HEIC 先转 JPEG(Android 原生 q95;iOS 由 picker 转)。
- Pro **$4.99**(一次买断,商品 `com.noobclaw.picbox.pro_unlock`,ASC Tier 5):不限张数、WebP 导出、水印预设、压缩/缩放/转换/裁剪/水印记住上次设置。
- 锚定:iOS 单功能竞品多为订阅($2.99–4.99/月或 $9.99–19.99/年),买断 $4.99 ≈ 其年费 1/3 以下。中区若上架取 ¥28。
- 所有付费门(批量上限 / WebP 芯片 / 存预设 / 设置页 Pro 行)统一 `showProSheet(context, reason:)`;`buyPro(` 只在 `pro.dart` 与 `core/purchase.dart`。

## 页面结构
- 首页:渐变 hero(离线·免费 / PRO 徽章、六工具一句话、已处理张数)+ 2 列工具网格(每工具独立色相图标)+ 隐私脚注。
- 工具页(共用 `ToolScaffold`):工具头 → 空状态选图卡(相册多选 / 拍摄)或缩略图条(第 4 张起加锁遮罩)→ 可选预览(裁剪编辑器 / 水印实时预览)→ 选项卡片 → 底部 hero 按钮「开始处理 N 张」→ 进度底板(可停止)→ 结果页。
- 结果页:渐变汇总卡(完成数、总体积前后、−N%)+ 每张一行(缩略图、体积/尺寸/格式前后、失败原因红字)→ 点行进入**滑动对比**(拖分割线 / 并排);底部「保存到相册 (N)」+「分享」。
- 设置:Pro 行(商店价 `ProPriceText`)、恢复购买、清理临时文件、语言、隐私政策、关于(含 Apache 署名)。

## 真机验收清单(照着点)
1. 首次「从相册选择」:iOS 直接弹系统选择器(无权限框);多选 5 张 → 第 4、5 张缩略图有锁 → 点开始 → 弹 Pro 页(不是直接拉起支付)。
2. 「拍摄」:首次弹相机权限框(中文说明);拒绝 → 底部提示 + 「去设置」按钮能跳到本 app 设置页。
3. 压缩 → 指定 500 KB → 3 张 12 MP 照片:结果行体积 ≤ 500 KB,尺寸行显示是否缩小,点行滑动对比清晰。
4. **竖拍 HEIC(iPhone)**:压缩 / 裁剪 / 去元数据 三个工具输出都是**正立**的,结果页尺寸显示为竖(如 3024×4032)。
5. 去元数据:带定位的照片 → 卡片红字显示「位置 纬度, 经度」+ 顶部红条「N 张图片带有拍摄地点」→ 处理后再导入结果图 → 显示「没有发现元数据」;相册里的结果图仍正立。
6. 水印:输入中文 + emoji,九宫格右下 / 平铺 −30°,预览与导出位置一致;透明 PNG 加水印输出 PNG 仍透明,转 JPEG 则垫白。
7. 「保存到相册」:iOS 首次弹「添加照片」权限框(中文说明);拒绝 → 提示 + 「去设置」;允许 → 相册出现 N 张;再点按钮显示「已保存」。
8. 「分享」:分享面板弹出且文件可存到「文件」。
9. 进度中点「完成当前这张后停止」:结果页显示「已停止 · 完成 N 张」。
10. 深色模式:首页 / 工具页 / 结果页 / 对比页 都看一遍。
11. 语言切换 English:所有文案跟着换(含结果行「Skipped/…」)。
12. 设置 → 恢复购买(无购买记录时 5 秒内出现「没有找到可恢复的购买」)。

## 真机/上传验证清单(iOS 专项)
- ASC → TestFlight → Build Uploads 若报 **ITMS-90683**:看缺哪条 purpose string;Microphone 则补一条如实说明(「本 app 不使用麦克风;此说明因图片选择组件引用系统相机接口而必须存在」)并重新出包。
- WebP 导出在 iPhone 上耗时(SDWebImageWebPCoder 慢),12 MP 约数秒,属已知。
- Android 8(API 26/27)导入 HEIC 会被跳过并提示「HEIC 需要 Android 9 以上」。

## 状态
- 2026-09-05:M1 代码完成,`flutter analyze` 0 issue,`flutter test` 42/42;图标/商店文案/appstore.md 齐;**未 commit、未打包、未真机**。→ 🧪待验收(需 push + CI 出包 + 真机)。
