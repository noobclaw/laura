# GitHub 可移植项目短名单(2026-09-05,首次)

> 用户 09-05:「调研半天都没有好项目出来,不如从 github 上看看」。本文是新采集器 `collectors/github_search.mjs` 第一次快照(344 个仓库、45 个能力问题)的人工筛选结果。评估口径见 CLAUDE.md 第 2 步五问:纯本地 / 许可证 / 手机端缺口 / 移植量 / 维护度。付费证据取自当日 `appstore.json` 美区、中区付费榜。

## 结论:先做这 3 个(按建议顺序)

### 1. 调音器 + 节拍器 + 和弦/音阶练习(音乐练习工具箱)
- **付费证据**:`TonalEnergy Tuner & Metronome` 今日**美区付费 #4**(长期常客,$3.99),这是今天付费榜前 10 里唯一的纯本地工具;中区有大量吉他/钢琴练习付费 app。
- **GitHub 参考**:`patzly/tack-android`(节拍器,480★,**无许可证 → 只借交互,全部重写**)、`ZaneH/piano-trainer`(MIT,音阶/和弦练习 + MIDI)、`tonaljs/tonal`(音乐理论库,无许可证 → 重写和弦/音阶推导,这部分是纯数学)、音高检测用 YIN/McLeod 算法(论文公开,自己实现,不用 aubio 的 GPL 代码)。
- **纯本地**:麦克风 → 音高;节拍器 → 音频调度;理论 → 表。零联网。
- **缺口/楔子**:TonalEnergy ★4.8 很强,但它是英文、界面老、功能堆叠;楔子写「中文 + 一次买断 + 练习记录(每天练了什么、准不准)」。CN 侧同类多为订阅。
- **移植量**:中(音高检测算法 + 低延迟音频调度要真机调;Flutter 侧用 `flutter_soloud`/原生 AVAudioEngine)。
- **风险**:节拍器精度在 Flutter 层不可靠,必须原生调度(PIPELINE G2「招牌功能架构评审」)。

### 2. 图片工具箱(Image Toolbox 移植到 iOS + Android)
- **GitHub 参考**:`T8RIN/ImageToolbox`(Kotlin,**Apache-2.0,14.5k★,持续维护**):缩放/裁剪/格式转换/压缩/去 EXIF/拼图/水印/滤镜/批处理,全部本地。
- **缺口**:它只有 Android 且免费开源;**iOS 没有同等级的一站式离线图片工具箱**,现有的多是订阅制单功能 app。
- **付费证据**:今日榜单直接证据弱(美区付费 #43 `PhotoPills` 是摄影规划,不同类);要用「iOS 图片压缩/转换/去元数据」主词补搜(交明日日报)。
- **许可证**:Apache → 可以直接读它的处理流程与边界处理,用 Dart/原生重写 UI;图像内核用 `image` 包(MIT)+ 平台原生编解码。
- **移植量**:中偏大,按 M1(缩放/压缩/转换/去 EXIF/批处理)→ M2(裁剪/水印/拼图)→ M3(滤镜)分里程碑。
- **注意**:BACKLOG #15 曾否决「EXIF/照片元数据工具」——那是单功能;工具箱不以 EXIF 为主卖点。

### 3. 离线 AI 老照片修复 / 放大(打订阅制的 Remini 类)
- **GitHub 参考**:`xinntao/Real-ESRGAN`(**BSD-3**,36.7k★,模型权重同许可)+ `Tencent/ncnn`(BSD,手机端推理,官方有 `realesrgan-ncnn-vulkan`);`EutropicAI/Final2x`(BSD,桌面端产品化范本);`upscayl/upscayl`(**GPL,只看 UX**)。**GFPGAN / CodeFormer 是 S-Lab 非商业许可,不能用**,人脸修复要另找(或先不做人脸)。
- **付费证据**:该品类的头部(Remini 等)是订阅制年入数亿美元级;用户抱怨集中在「订阅贵、要上传照片」——「离线 + 一次买断 + 照片不出手机」是现成楔子。
- **纯本地**:ncnn Vulkan/Metal 在 iPhone 12+/中端安卓可跑 2x/4x,单张数秒到几十秒。
- **移植量**:大(FFI 接 ncnn、模型打包 ~20MB、内存控制),必须拆 M1(2x 放大)/M2(4x + 去噪)/M3(人脸,待找许可证干净的模型)。
- **风险**:低端机 OOM;审核对「AI 修图」无额外要求。

## 建议直接升级现有 app 的 2 个(不占新 app 名额)

### 4. 回声笔记 → whisper.cpp 离线转写
- `ggml-org/whisper.cpp`(**MIT**,53k★)官方支持 iOS/Android,有 Flutter 绑定可参考。
- **解决的正是用户 09-04 的两条投诉**:不再依赖 Siri/系统听写开关,语言由模型决定(base/small 多语言模型 ~75–250MB,首次下载或随包)。
- 代价:包体 + 首次加载几秒;M1 先做「录完再转写」,M2 再做流式。

### 5. 记得 → FSRS 调度算法
- `open-spaced-repetition/fsrs4anki` / `free-spaced-repetition-scheduler`(**MIT**)。比 SM-2 更准,Anki 已默认。
- 商店文案可写「FSRS 算法,比传统 SM-2 少复习 20–30%」——这是记得目前缺的差异化楔子(BACKLOG 09-05 记它「零上架阻塞」但楔子弱)。
- 移植量小(纯算法,几百行 Dart + 权重表)。

## 看过但不建议(写明原因,避免重复评估)
- **PDF 工具箱**(`pdfcpu` Apache):品类付费真(美区 #98 TurboScan、中区 #3 扫描全能王),但 BACKLOG #16 已按「主词无付费入口」否决;且 iOS PDFKit 原生覆盖合并/拆分,楔子难写。若日后重开,参考 pdfcpu 的流程。
- **KeePass 客户端**:iOS `KeePassium`、Android `KeePassDX` 已是 GPL 开源精品,零缺口。
- **离线翻译 / 离线 OCR 单功能**:系统自带(Apple 翻译、Live Text、Google 翻译离线)覆盖 → 纪律 AG「付费理由被系统侵蚀」。
- **Loop Habit Tracker(GPL)**:iOS 习惯类红海且订阅制,楔子只剩「更便宜」。
- **本地文件转换器**(`VERT` GPL 参考):内核靠 ffmpeg(LGPL,可动态链接),可做,但手机端「转换」需求分散、付费弱;放观察池。
- **科学计算本**(`numbat` / `kalker` MIT):对标 Soulver;今日美区付费有 `10bii`(#58)、中区 `车工计算器`(#87)证明**垂直计算器**能收费,通用计算本反而难;记观察池,等具体垂直方向。

## 采集器今天的两处修正
- Search API 不接受 `topic:A OR topic:B`(422)→ 已拆成独立问题;`in:readme` 把所有 awesome 列表都捞进来 → 已去掉并加噪声过滤。
- 结果里仍会混入大项目(ncnn/moviepy 一类是「内核」不是「产品」)——这类要当**内核候选**记,不当选题。
