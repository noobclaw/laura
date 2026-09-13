# AstroPile — 商店文案 / Store listing

> 规则:这里的每一条卖点在**当前版本**里都必须真的存在并可达(PIPELINE G8a ⑧)。
> 本文对应 **v1.1.0(M1 + M2)**:M2 的四件事(κ-σ 剪切、星轨最大值叠加、暗场/平场校准、app 内连拍)**已实现,故已写入**。
> **M3 才有的功能(RAW/DNG、批次管理、失败帧可视化诊断报告)一个字都不写。**
> 两个平台的文案里都不出现另一个平台的名字。
> 三件套(标题/副标题/关键词)以 `store/aso.md` 的实打结论为准 —— 2026-09-13 已把 en-US 标题从 `AstroPile: Stack the Night Sky` 换成 aso.md 定的 `AstroPile: Astro Image Stacker`(理由见 aso.md §选词理由 2:`Stacker` 词根的在位者评价量只有个位数到 103 条,**它们弱,正是该抢的词**;而 `night sky` 的头部是 49 万条的 `Night Sky`,白占 9 个字符)。

---

## 中文(简体)

**标题(30 字内)**
AstroPile 星空叠加 - 天文摄影堆栈

**副标题 / 简短描述(80 字内)**
夜空连拍对齐叠加,逐帧告诉你原因;星轨、暗场平场校准都在,全程离线。

**关键词(App Store,100 字符内,逗号分隔)**
星野,银河,星空相机,长曝光,降噪,星轨,深空,对齐,连拍,离线,星空照片,夜景,AstroShader

**长描述**

用手机拍星空,单张总是噪点满屏。把同一场景连拍的十几张叠在一起,噪点会被平均掉,暗处的细节留下来 —— 这就是天文摄影里的「叠加」。

AstroPile 把这件事装进你的手机,而且**全程离线**:没有网络权限,照片一张都不上传。

**它和别的叠加工具最大的不同,是它会说话。**
大多数叠加工具只给你一个结果:糊了就是糊了,你不知道是哪一张拖了后腿。AstroPile 给每一帧一份成绩单:

• 检出了多少颗星
• 有多少颗和参考帧对上了
• 对齐残差是多少像素
• 0–100 的质量分

对不上的帧会写明原因 —— 星点太少 / 画面过亮 / 找不到相符的星阵 / 误差过大 / 画幅不一致 —— 并给出一句能照做的建议。你可以把它勾掉,重新叠一次。

**怎么用**
1. 选 2 张以上同一场景的连拍照片 —— 或者直接在 app 里连拍一组
2. 挑一张作参考帧(默认第一张)
3. 开始叠加,过程随时可以停止
4. 拖动黑点 / 亮度 / 饱和度三个滑杆,预览实时变化
5. 保存到相册或分享,导出的是全分辨率

**app 内连拍**
不用切到相机再切回来。按下之后**对焦与曝光会锁住**,整组照片用同一套参数拍完 —— 叠加最怕的就是相机拍到一半自己重新测光。张数 4 / 8 / 16 / 32,以你的叠加上限为准(免费版 6 张)。拍下的原片默认存进相册,可关。(注:它不能设置长曝光,快门由系统决定。)

**星轨模式**
把固定机位的连拍取每个像素最亮的一次,**并且不做星点对齐** —— 地景不动,星星拉成弧线。张数越多,弧越长。

**它怎么对齐**
不是靠找角点 —— 星点彼此长得一模一样,角点法在星空上不成立。AstroPile 用的是「星阵匹配」:把每颗星和邻居组成的三角形形状拿去比对,再用 RANSAC 剔掉错配,最后解出平移、旋转和缩放。这正是天文界处理无 WCS 星图的通行做法。

**贴心之处**
• 导入时读 EXIF,**曝光设置和多数帧不一样的照片会被标出来**
• 画幅不一致的照片直接标红,不会悄悄毁掉整叠
• 内存按横条流式处理,几十张全分辨率也不会撑爆
• 叠加过程的临时文件跑完就删,下次启动再兜底清一次(连拍的原片如果你开着「存进相册」则会保留在相册里)

**免费版**
一次最多叠 6 张,平均叠加,**星轨模式**,app 内连拍,全分辨率导出,**逐帧对齐报告完整可用**。没有广告,没有水印,没有账号。

**AstroPile Pro(一次性买断,不是订阅)**
• 一次最多叠 32 张
• **中值叠加**:自动去掉只出现在少数帧里的东西 —— 飞机、卫星拖线、热噪点
• **κ-σ 剪切叠加**:按每个像素自己的均值与标准差剔除异常值再平均,既去掉飞机卫星,又比中值多留住降噪(八张以上效果最好)
• **暗场 / 平场校准**:暗场扣掉传感器的热噪与坏点,平场抹平暗角和镜头上的灰尘印
• 记住你的叠加方式与工作分辨率

**权限**
相机:只用于 app 内连拍,不录音。相册:选择要叠的照片、以及你主动保存成片时。**没有网络权限。**

**隐私**
本应用不申请网络权限,不含统计与广告 SDK。照片只在本机读取与处理,成片只有在你主动保存或分享时才离开应用。

**更新内容 — 1.1.0**
新增星轨模式:固定机位的连拍不做星点对齐直接合成,地景不动、星星拉成弧线。Pro 新增 κ-σ 剪切叠加与暗场/平场校准,把传感器自己的噪点和暗角一起处理掉。还有 app 内连拍——按下之后对焦与曝光锁住,整组用同一套参数拍完。

**开源致谢**
星阵配准参考了 astroalign(MIT,© 2016 Martin Beroiz),叠加合成参考了 OpenSkyStacker(MIT,© 2017 Benjamin Schubert),星点清晰度评估参考了 astra_lite(MIT,© 2023 Denis Artyomov),κ-σ 剪切与暗场/平场校准参考了 DeepSkyStacker(BSD-3,© 2006-2019 LucCoiffier、© 2018-2025 David C. Partridge 等)公开的设计。本应用是独立的 Dart 实现,未复制其代码。

---

## English (US)

**Title (30 chars)**
AstroPile: Astro Image Stacker

> 2026-09-12 的主词实打(`store/aso.md`)推翻了 M1 时「避开 `Stacker` 词根」的判断:`astro stacker` 的头部评价量只有 **240**、`image stacker` 只有 26,335,而原标题里的 `night sky` 头部是 **494,824**。这个标题一次覆盖 `astro stacker`(主攻)+ `image stacker`(次攻),且与在架 app **无逐字同名**(ASO 铁律里唯一的硬规则)。

**Subtitle / short description (28 chars — App Store subtitle)**
Astro Stacker & Frame Report

> 09-13 改:原定 `Long Exposure & Frame Report` **卖了一个 app 自己在界面上否认的能力** —— 连拍页明写「不能设置长曝光,快门由系统决定」。副标题是 Apple 按功能声明读的元数据(2.3.1),这正是 09-04 记下的「付费页卖不存在的功能」那一类。`long exposure` 是合法的**关键词**,不是合法的**副标题**,已移进关键词字段。

**Short description (80 chars — Play)**
Align and stack a night-sky burst — and see why any frame did not line up.

**Keywords (App Store, ≤100 chars, comma separated)**
astrophotography,night,sky,milky,way,long,exposure,align,noise,median,trails,deep,astroshader

> 93/100 字符。`star` 与 `image`/`stacker` 已在标题里,苹果自动合并,重复是浪费额度。

**Long description**

One phone photo of the night sky is mostly noise. Stack a dozen shots of the same scene and the noise averages away while the faint detail stays — that is what astrophotographers call stacking.

AstroPile does it on your phone, entirely offline: no network permission, and no photo is ever uploaded.

**What makes it different is that it tells you what happened.**
Most stackers hand you one picture. If it came out smeared, you have no idea which frame ruined it. AstroPile gives every frame a report card:

• how many stars were detected
• how many matched the reference frame
• the alignment residual, in pixels
• a 0–100 quality score

Frames that could not be aligned say why — too few stars, too bright, no matching star pattern, residual too large, different pixel size — plus one line on what to change. Untick it and stack again.

**How it works**
1. Pick two or more shots of the same scene — or shoot a burst inside the app
2. Choose the reference frame (the first one by default)
3. Start stacking — you can stop at any point
4. Drag black point, brightness and saturation; the preview updates live
5. Save to Photos or Share — the export is full resolution

**Burst capture, built in**
No switching to the camera app and back. Focus and exposure **lock** when the burst starts, so every frame is shot on one setting — a camera that re-meters halfway through is the thing stacking hates most. Shoot 4, 8, 16 or 32 frames, up to your stack limit (6 on the free tier). The frames are kept in Photos by default; you can turn that off. (It cannot set a long exposure: the shutter is the system's choice.)

**Star trails**
Takes the brightest value each pixel ever had across a burst from a fixed position, and **skips star alignment** — so the ground stays put and the stars draw arcs. The more frames, the longer the arc.

**How it aligns**
Not by corner detection: stars look identical to each other, so feature matching does not work on a star field. AstroPile matches asterisms — the shape of the triangle each star forms with its neighbours — then uses RANSAC to throw out the false pairs and solves for shift, rotation and scale. This is the standard approach for registering star fields with no WCS information.

**Details that matter**
• Reads EXIF on import and **flags frames shot with different exposure settings** than the rest
• Frames with a different pixel size are marked in red instead of quietly ruining the stack
• Combines in horizontal bands, so even a few dozen full-resolution frames will not exhaust memory
• Scratch files from a stack are deleted when the run ends and swept again on the next launch (frames you shot in burst mode stay in Photos if you left that switch on)

**Free**
Up to 6 frames per stack, mean stacking, **star trail mode**, in-app burst capture, full-resolution export, and **the full per-frame alignment report**. No ads, no watermark, no account.

**AstroPile Pro (a one-time purchase, not a subscription)**
• Up to 32 frames per stack
• **Median stacking** — aircraft, satellite trails and hot pixels drop out on their own
• **Kappa-sigma stacking** — rejects outliers by each pixel's own mean and standard deviation, so aircraft and satellites go while more of mean's noise reduction stays (best from about eight frames up)
• **Dark and flat calibration** — darks subtract the sensor's thermal noise and hot pixels, flats even out vignetting and dust shadows
• Remembers your stacking mode and working resolution

**Permissions**
Camera: for in-app burst capture only, with no audio recording. Photos: to choose the frames to stack, and to save the finished picture when you ask. **No network permission.**

**Privacy**
The app requests no network permission and contains no analytics or advertising SDK. Photos are read and processed on this device only; the finished picture leaves the app only when you save or share it.

**Credits**
Star-field registration follows astroalign (MIT, © 2016 Martin Beroiz), frame stacking follows OpenSkyStacker (MIT, © 2017 Benjamin Schubert), the star-sharpness check follows the published design of astra_lite (MIT, © 2023 Denis Artyomov), and kappa-sigma clipping with dark/flat calibration follows DeepSkyStacker (BSD-3, © 2006-2019 LucCoiffier and © 2018-2025 David C. Partridge and others). This app is an independent Dart implementation and copies none of their code.

**What's New — 1.1.0**
Star trails: stack a fixed-position burst without star alignment and let every star draw its arc. Kappa-sigma stacking and dark/flat calibration (Pro) for cleaner results from a noisy sensor. And a built-in burst mode that locks focus and exposure so every frame is shot the same way.

---

## 商品与价格

| 项 | 值 |
|---|---|
| 内购商品 ID | `com.noobclaw.astropile.pro_unlock` |
| 类型 | 非消耗型(一次性买断) |
| 美区价 | $3.99 |
| 中区价 | ¥28 |
| 内购显示名 | AstroPile Pro |
| 内购描述 | 一次最多叠 32 张、中值与 κ-σ 剪切叠加(去飞机与卫星拖线)、暗场/平场校准、记住叠加设置。一次性买断,无订阅。 |
| IAP description (en) | Up to 32 frames per stack, median and kappa-sigma stacking (aircraft and satellite trails drop out), dark/flat calibration, and saved settings. A one-time purchase, not a subscription. |

## 分类与素材

- 主分类:Photo & Video(摄影与录像);副分类:Utilities(工具)
- 图标:`store/icon-1024.png`(1024,iOS 无 alpha)、`store/play-icon-512.png`
- Feature graphic:`store/feature-1024x500.png`
- 截图:**🔴 未做**(全项目 12 个 app 一张都没有,是当前最大的上架阻塞)。计划 5 张 1284×2778:首页 / 帧列表(含叠加方式四选一) / 进度 + 逐帧结果流 / 结果页 / 逐帧报告。文案中英各一套,第 1 张必须是「大字标题 + 楔子 + 界面」(G8b-4)
- 隐私:不收集任何数据
- 年龄分级:4+
