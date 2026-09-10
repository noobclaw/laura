# AstroPile — 商店文案 / Store listing

> 规则:这里的每一条卖点在 v1(M1)里都必须真的存在并可达(PIPELINE G8a ⑧)。
> M2/M3 才有的功能(kappa-sigma、星轨最大值叠加、暗场平场、app 内连拍、RAW)**一个字都不写**。
> 两个平台的文案里都不出现另一个平台的名字。

---

## 中文(简体)

**标题(30 字内)**
星野叠加 - 夜空多帧对齐堆栈

**副标题 / 简短描述(80 字内)**
把连拍的夜空照片对齐叠成一张,逐帧告诉你对上了没有、为什么没对上。

**关键词(App Store,100 字符内,逗号分隔)**
天文摄影,叠加,堆栈,星空,银河,降噪,长曝光,夜景,星野,对齐,连拍,离线

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
1. 选 2 张以上同一场景的连拍照片
2. 挑一张作参考帧(默认第一张)
3. 开始叠加,过程随时可以停止
4. 拖动黑点 / 亮度 / 饱和度三个滑杆,预览实时变化
5. 保存到相册或分享,导出的是全分辨率

**它怎么对齐**
不是靠找角点 —— 星点彼此长得一模一样,角点法在星空上不成立。AstroPile 用的是「星阵匹配」:把每颗星和邻居组成的三角形形状拿去比对,再用 RANSAC 剔掉错配,最后解出平移、旋转和缩放。这正是天文界处理无 WCS 星图的通行做法。

**贴心之处**
• 导入时读 EXIF,**曝光设置和多数帧不一样的照片会被标出来**
• 画幅不一致的照片直接标红,不会悄悄毁掉整叠
• 内存按横条流式处理,几十张全分辨率也不会撑爆
• 临时文件跑完就删,下次启动再兜底清一次

**免费版**
一次最多叠 6 张,平均叠加,全分辨率导出,**逐帧对齐报告完整可用**。没有广告,没有水印,没有账号。

**AstroPile Pro(一次性买断,不是订阅)**
• 一次最多叠 32 张
• **中值叠加**:自动去掉只出现在少数帧里的东西 —— 飞机、卫星拖线、热噪点
• 记住你的叠加方式与工作分辨率

**隐私**
本应用不申请网络权限,不含统计与广告 SDK。照片只在本机读取与处理,成片只有在你主动保存或分享时才离开应用。

**开源致谢**
星阵配准的思路参考了 astroalign(MIT 许可,© 2016 Martin Beroiz)公开的设计。本应用是独立的 Dart 实现,未复制其代码。

---

## English (US)

**Title (30 chars)**
AstroPile: Stack the Night Sky

> 刻意避开 `Stacker` 词根(`Star Stacker` / `AstroShader` / `SharpStacker` / `Astro Stacker` 四支已占,PLAN §商店定位)。动词 `Stack` 保留,因为它就是这件事的名字。

**Subtitle / short description (80 chars)**
Align and stack a night-sky burst — and see why any frame did not line up.

**Keywords (App Store, ≤100 chars, comma separated)**
astrophotography,stacking,star,milky way,noise reduction,long exposure,night sky,align,burst

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
1. Pick two or more shots of the same scene
2. Choose the reference frame (the first one by default)
3. Start stacking — you can stop at any point
4. Drag black point, brightness and saturation; the preview updates live
5. Save to Photos or Share — the export is full resolution

**How it aligns**
Not by corner detection: stars look identical to each other, so feature matching does not work on a star field. AstroPile matches asterisms — the shape of the triangle each star forms with its neighbours — then uses RANSAC to throw out the false pairs and solves for shift, rotation and scale. This is the standard approach for registering star fields with no WCS information.

**Details that matter**
• Reads EXIF on import and **flags frames shot with different exposure settings** than the rest
• Frames with a different pixel size are marked in red instead of quietly ruining the stack
• Combines in horizontal bands, so even a few dozen full-resolution frames will not exhaust memory
• Scratch files are deleted when the run ends, and swept again on the next launch

**Free**
Up to 6 frames per stack, mean stacking, full-resolution export, and **the full per-frame alignment report**. No ads, no watermark, no account.

**AstroPile Pro (a one-time purchase, not a subscription)**
• Up to 32 frames per stack
• **Median stacking** — aircraft, satellite trails and hot pixels drop out on their own
• Remembers your stacking mode and working resolution

**Privacy**
The app requests no network permission and contains no analytics or advertising SDK. Photos are read and processed on this device only; the finished picture leaves the app only when you save or share it.

**Credits**
The asterism-matching approach follows the published design of astroalign (MIT, © 2016 Martin Beroiz). This app is an independent Dart implementation and copies none of its code.

---

## 商品与价格

| 项 | 值 |
|---|---|
| 内购商品 ID | `com.noobclaw.astropile.pro_unlock` |
| 类型 | 非消耗型(一次性买断) |
| 美区价 | $3.99 |
| 中区价 | ¥28 |
| 内购显示名 | AstroPile Pro |
| 内购描述 | 一次最多叠 32 张、中值叠加(去飞机与卫星拖线)、记住叠加设置。一次性买断,无订阅。 |

## 分类与素材

- 主分类:Photo & Video(摄影与录像);副分类:Utilities(工具)
- 图标:`store/icon-1024.png`(1024,iOS 无 alpha)、`store/play-icon-512.png`
- Feature graphic:`store/feature-1024x500.png`
- 截图:待真机验收时补(首页 / 帧列表 / 进度 / 结果 / 逐帧报告,5 张 1284×2778)
- 隐私:不收集任何数据
- 年龄分级:4+
