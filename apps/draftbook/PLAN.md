# Draftbook — 产品规划文档

> 立项 2026-09-13。本项是**纪律 AY（2026-09-13 用户拍板）落地的第一个候选**：垂直细分 + 巨头注意不到 + 抱怨最多 + 还没人做或做得不够好，且**服务端解禁后第一个用上 `256btc.com` 的 app**。
> 发现路径：Reddit `r/Scrivener` / `r/writers` 的反复抱怨 → App Store 付费榜差评密度实查 → 主词付费面验证。

---

## 差异化楔子

> **「你的稿子存在我们自己的服务器上，不经过 Dropbox；换台设备接着写，Android 上也有；一次买断，所有设备都能用。」**

三句话对应在位者被骂得最狠的三件事，逐条有实查原话撑着（见下）。

### 证据①：商店侧 —— 龙头 `Scrivener` 的差评密度是跟踪期最高的

**实查（2026-09-13）**：`Scrivener` / Literature & Latte / **$23.99 / ★4.18 / 2,604 条 / ver 2023-09-29（停更 2 年）/ 上架 2016-07-20**，今日仍在**美区付费榜 #92**。
**评论 RSS 读到 99 条，其中 ≤3★ 66 条（67%）** —— 本项目跟踪期见过的最高差评密度（第二名是 09-12 的 `AstroShader` 17/49 = 35%）。

**骂点高度集中在三处，逐字引用（纪律 AB② 只引实查读数）：**

**(a) 同步靠 Dropbox，反复丢稿 —— 最大的一块**
- 「Better than nothing but clumsy and **Dropbox leads to data loss**」
- 「**Too many issues with the Sync**. Disappointed by the Sync'ing with the Desktop version. I spent too much time trying to fix it. It worked for a while… until it did not anymore!」
- 「**Poor Storage Solution**. I can't stand drop box especially for IOS and **in 2026 we shouldn't be forced into using a paid storage service**.」
- 「Rarely Updated … **Sync begins to suck and cause issues** no matter how certain you are at making sure Dropbox is updated first.」
- 「Needs table support … **iCloud support would be nice too**.」

**(b) 移动端被当弃子，长期不更新**
- 「**Rarely Updated**. Update: here we are years later and **there is still no updates**. So as the OS improves this become more and more buggy.」
- 「**wish they would update the app.** it's so outdated appearance wise and there are constantly bugs.」
- 「**Formatting Bug on iOS App** … for **MONTHS** I've been unable to format anything. I can't highlight, re-align, change the font, nothing.」
- 「**Issue**. None of the tools above the keyboard open nor work」
- 「**Mac Version Rocks - iOS, not so much.** Menus are missing/inadequate and it's not intuitive.」

**(c) 付了钱还觉得被坑**
- 「**I shouldn't have to buy it twice**」
- 「**Felt deceived**. It was not clearly stated that the iPad version was severely empty of the touted Scrivener features like templates. **If I'd known that I would not have wasted $23.**」
- 「**Trash.** The MacOS app is great. **This is a mess.** Don't waste your money on this junk.」

### 证据②：Reddit 侧 —— `r/Scrivener` 同一批抱怨反复出现（纪律 AY③ 要求 ≥3 条独立原话，实得 7 条）

- 「**Rant... Frustrated by Scrivener's constant sync issues**」
- 「**I am terrified of Scrivener and Dropbox.**」
- 「**Writer's horror Dropbox**」
- 「**Does it have to be Dropbox?**」
- 「**Restoring from a month old backup - devastating to lose a month of writing.**」
- 「**No iOS update for 2 years?**」
- 「**Scrivener Android -- yet another desperate petition**」/「**Scrivener Android App**」

### 证据③：🔴 最硬的一条 —— **Scrivener 根本没有 Android 版，而圈里在请愿**

`r/Scrivener` 里「Android 请愿」是个反复出现的帖子类型（标题里自带 "**yet another desperate petition**" —— 说明之前已经请愿过很多次）。
**→ 安卓侧的长文写作组织工具是一块空地，龙头十年不进去。** 这是我们能拿到的最干净的一段路。

### 证据④：付费面 —— 7 支，价格带是本项目见过最高的之一

主词 `long form writing organize chapters` 命中 44 / **付费 7 支**：

| 支 | 实查（2026-09-13） |
|---|---|
| **`Scrivener`** | **$23.99 / ★4.18 / 2,604 条 / ver 2023-09-29（停更 2 年）** ← 龙头 |
| `iA Writer` | $19.99 / ★4.56 / 1,532 条 / ver 2026-08-10（在维护）—— **极简 markdown 单文档编辑器，不做章节化组织，非同一用途** |
| `Story Planner for Writers` | $8.99 / ★4.74 / 1,177 条 / ver 2026-07-16（在维护）—— **只做人物/情节卡片规划，不写正文** |
| `yWriter: Novel Writing` | **$14.99 / ★3.08 / 25 条** / ver 2024-02-25 |
| `Lists for Writers` | $2.99 / ★4.72 / 491 条 / ver 2020-10-30（停更 5 年） |
| `iDeas for Writing` | $2.99 / ★4.69 / 70 条 / ver 2026-09-09 |
| `IEW Writing Toolbox` | $1.99 / ★0.00 / 0 条（纪律 R 伪实体） |

主词 `novel writing app outline` 命中 46 / 付费 4 支（与上表重叠）。

### 证据⑤：通过纪律 AY②「不和巨头竞争」的一票否决检查

两组主词的**免费侧头部全部是小支，没有任何 ≥10 万评价的免费 app，也没有任何巨头**：

| 免费侧头名 | 评价数 |
|---|---|
| `Werdsmith: Writing App` ★4.67 | 7,993 |
| `Book Creator: Author AI` ★4.53 | 3,652 |
| `MyStory.today: Write a Book` ★4.48 | 2,534 |
| `Paper: Writing App, Notes` ★4.65 | 1,708 |
| `Fortelling` ★4.49 | 1,013 |
| `Essayist: Academic Writing App` ★4.47 | 407 |

**⚖️ 为什么 Pages / Word / Google Docs 不算在内**：它们是**通用文档编辑器**，不做「章节 / 场景 / 语料板 / 大纲 / 编译输出」这套长文组织。纪律 AY② 要看的是**同一用途**的头部，不是同主词的任何头部（这一条与 09-13 §六 4 判 `CARFAX` 时用的是同一口径）。

---

## 1. 定位与人群

**一句话**：手机 / 平板上的长篇写作组织工具 —— 把一本书拆成章节和场景来写，稿子自动同步，换设备接着写。

**人群**（垂直，纪律 AY③）：
- 写小说 / 非虚构长稿 / 剧本的人，**主力设备是手机或平板**（`r/writers`「Do you write your stories on your phone?」是个常年热帖）
- **被 Dropbox 同步坑过的 Scrivener 用户**
- **安卓上的写作者** —— 他们目前没有任何对应物

**明确不做**（避免变成通用笔记 app，撞纪律 AG）：
- 不做通用笔记 / 待办 / 日记（Notion / Obsidian / 系统备忘录的地盘）
- 不做 AI 代写（`Book Creator: Author AI` 那一类，免费侧已很厚，且不是这批用户要的）
- 不做桌面版（v1 范围内）

---

## 2. 功能清单

### M1（v1.0，必须有，否则不成立）
1. **项目 = 一本书**：多项目并存，每个项目独立。
2. **三级结构**：项目 → 章（Chapter）→ 场景（Scene）。场景是最小写作单元，可拖拽排序、跨章移动。
3. **编辑器**：纯文本 + 轻量格式（粗体 / 斜体 / 标题 / 引用）。**必须解决 Scrivener 被骂的那个：键盘上方工具条永远可用、可自定义。**
4. **大纲视图**：把所有场景的标题 + 摘要一屏铺开，可拖拽重排（这是 Scrivener 的 Corkboard，也是它最不可替代的一件事）。
5. **字数统计与目标**：全书 / 本章 / 本场景；每日目标 + 连续天数。
6. **自动保存 + 本地版本历史**：每个场景保留最近 N 个快照，可回滚。**这一条直接对着「lost a month of writing」。**
7. **导出**：Markdown / TXT / DOCX（分章合并，含章节标题）。
8. **全本地可用** —— 不登录也能完整写作，同步是可选增强（见 §4b 离线降级）。

### M2（v1.1，同步与多设备）
9. **自建同步**（`256btc.com`）：账号 → 项目云端存一份 → 多设备增量同步 + 冲突处理（按场景粒度，冲突时保留双版本让用户选，绝不静默覆盖）。
10. **回收站 + 云端版本历史**（30 天）。
11. **Android 版**（Flutter 同一套代码，M2 一起发 —— 这是证据③那块空地）。

### M3（v1.2，长文专业功能）
12. **语料板 / 研究资料**：项目内附图片、网页剪藏、人物设定卡。
13. **编译输出**：按自定义模板把选中的场景编译成一份稿件（分隔符、场景间距、章节编号规则）。
14. **写作统计**：按日 / 按项目的字数曲线。

---

## 3. 页面结构与交互

```
[项目列表]  ── 新建 / 打开 / 删除，显示每本书的字数与进度
     │
     ├─ [大纲视图]   章节树 + 场景卡片（拖拽重排、跨章移动、批量选中）
     │        │
     │        └─ [编辑器]  全屏写作；键盘上方常驻工具条；左滑回大纲、右滑下一场景
     │
     ├─ [统计]       字数目标 / 每日进度 / 连续天数
     └─ [项目设置]   导出、版本历史、同步开关
```

**交互三条铁律**（全部对着 Scrivener 的差评写）：
1. 键盘上方工具条**任何时候都能点开**（对应「None of the tools above the keyboard open nor work」）。
2. **写作中永不弹窗**；同步、保存、冲突全部在后台，出错只在顶部显示一条可忽略的条。
3. 从「打开 app」到「光标在上次停笔处」**不超过 2 次点击**。

---

## 4. 技术方案

- Flutter（iOS + Android，同一套代码 —— 这正是安卓那块空地的成本优势）。
- 本地存储：SQLite（`drift` 或 `sqflite`），场景正文按行存，便于增量同步与版本快照。
- 编辑器：先用 Flutter 原生 `TextField` + 自绘工具条（**不引入重型富文本引擎**，Scrivener 的格式化 bug 正是重编辑器的代价）。轻量格式用 Markdown 语法存储，编辑时行内渲染。
- 导出 DOCX：纯 Dart 拼 OOXML（docx 就是个 zip + XML，不需要第三方服务）。

### 4b. 服务端（纪律 AY① 强制项）

| 项 | 内容 |
|---|---|
| **服务端做什么** | 只做三件事：① 账号（邮箱 + 密码，无第三方登录）；② 项目/场景的增量同步（存的是加密后的文本 blob，服务端不解析内容）；③ 云端版本历史（30 天滚动）。**不做 AI、不做渲染、不做任何需要算力的事。** |
| **部署在哪** | `256btc.com`（宝塔独立站，webroot `/www/wwwroot/256btc.com`，经 upgeo 仓 git 传输再 cp 部署 —— 见记忆 `reference_laura_support_url`）。新增一个 `/api/draftbook/*` 路由，与现有 support 静态页共存。 |
| **月成本** | 存量估算：一本 10 万字的书 ≈ 200KB 纯文本，压缩后 ~60KB；即使 1,000 个付费用户 × 5 本书 = **~300MB**。**现有机器零增量成本**，带宽可忽略。数据库用 SQLite 或现有 PG 均可。 |
| **挂了怎么办（离线降级）** | 🔴 **这是硬要求**：app 是 **local-first**，所有写作、大纲、导出、版本历史**全部在本地完成，不依赖服务端**。服务端只负责把本地库同步到别的设备。**服务端挂掉时 app 功能完全不变**，只是顶部出现一条「暂时无法同步」，恢复后自动补传。**不登录的用户可以永久免费使用全部单机功能。** |
| **隐私声明** | App Store 数据收集声明须填：邮箱（账号）、用户内容（书稿，端到端加密后上传）。**不收集任何分析/广告标识符。** |

**⚖️ 为什么值得引入服务端**：同步是在位者被骂得最狠的一件事，而它**只能**靠服务端解决 —— iCloud 方案在 Android 上不存在，Dropbox 方案正是被骂的那个。这是纪律 AY① 说的「服务端解开的那一道门槛」的教科书案例。

---

## 5. 定价与商店

> 🔴 **2026-09-16 更正**：下面这一行 Pro 权益是**三个里程碑加起来**的样子，不是 v1.0 卖的东西。
> **v1.0 实际只卖两项：不限项目数 + Word(.docx) 导出**（见 §6b）。往 App Store Connect 的内购描述里填文案时**照 §6b 填，不要照这一行填** ——
> 卖一个包里没有的同步功能是 3.1.1 直接拒审，也正是本 app 要回应的那条「felt deceived」差评。

- **模型**：免费 + 一次性买断解锁 Pro。**（⚖️ 服务端解禁后订阅制也开了口子，但本项仍选买断 —— 理由见下）**
- **免费**：1 个项目、无限字数、导出 TXT/Markdown、全部单机功能。
- **Pro 买断 $9.99 / ¥68**（~~v1.0~~ 全部里程碑合计）：无限项目、自建同步 + 多设备、云端版本历史、DOCX 导出、语料板。
- **⚖️ 为什么不做订阅**：① 这批用户刚被 $23.99 买断 + 还要自备 Dropbox 付费存储坑过，「不再被收第二次钱」本身就是楔子的一部分；② 服务端成本近似为零，没有收订阅的成本理由；③ 定价 $9.99 是龙头 $23.99 的 **42%**，同时高于该邻域的小工具带（$2.99）—— 卡在「明显比 Scrivener 便宜，又不像个玩具」的位置。
- **⚠️ 待复核**：若 M2 上线后同步的运维负担超预期，再评估是否给「云端版本历史」单独加一档订阅。**v1 不做。**

### 商店标题 / ASO（按记忆 `feedback_laura_aso_every_app` 的三层）

- **名称（30 字符内）**：`Draftbook: Novel Writing` —— **实查逐字/前缀同名 0 支** ✅
- **副标题（30 字符内）**：`Chapters, outline & sync`
- **关键词**：`scrivener,manuscript,chapter,outline,novel,writing,author,draft,sync,offline,corkboard,scene`
- **中文显示名**：`Draftbook 写长篇` —— ⚠️ **不含任何与中区在位者逐字同名的词**（09-13 `倒数日` 撞名 270 万条免费龙头的教训）。
- **🔴 en-US 本地化必须在第一次提交前填全**（铁律 `feedback_store_listing_must_have_enus`；本项与 tunekit/picbox/photolift 一样，是能从第一天就做对的）。

---

## 6. 里程碑（纪律「大型项目须拆里程碑，否则不得进工厂」）

| 里程碑 | 交付 | 工厂轮次 |
|---|---|---|
| **M1** | 项目/章/场景三级结构 + 编辑器 + 大纲拖拽 + 字数目标与统计 + 本地版本历史 + TXT/MD/**DOCX** 导出。**纯本地，不含账号与服务端。** | ✅ **2026-09-16 交付** |
| **M2** | `256btc.com` 同步后端 + 账号 + 增量同步与冲突处理 + 云端版本历史 + **Android 版上架**。 | 第 2 轮 |
| **M3** | 语料板 / 研究资料 + 编译输出模板 + 写作统计曲线（按周/按项目）。 | 第 3 轮 |

**M1 独立可上架** —— 即使 M2/M3 不做，M1 也是一个完整的单机长文写作 app。

### 6b. M1 实际交付（2026-09-16 工厂轮，与原计划的三处出入）

| # | 差异 | 为什么 |
|---|---|---|
| 1 | **DOCX 导出由 M3 提前到 M1**，并成为 Pro 的第二项权益 | §2 功能清单第 7 条本来就把 DOCX 写在 M1（与 §6 里程碑表冲突，本轮按 §2 执行）。更硬的理由：M1 只有「不限项目数」一条 Pro 权益，撑不起 $9.99；而 DOCX 是纯 Dart 拼 OOXML（zip + XML，`archive` 包），不需要服务端也不需要原生库。实现见 `lib/tool/export/docx.dart`，有对照测试解出 zip 校验部件与转义。 |
| 2 | **「左滑回大纲、右滑下一场景」改为工具条上的上/下一场景按钮** | 全屏手势会和文本选择、光标拖动打架 —— 那正是在位者被骂「工具条点不开」的同一类病。按钮在常驻工具条右侧，收起键盘时出现。 |
| 3 | **场景增加 `状态`（待写 / 草稿 / 已完成）** | 原计划没有。大纲一屏几十个场景时，没有状态点就只能靠字数猜进度；成本是一个枚举，收益是大纲真的可扫。写入正文会自动把「待写」变「草稿」。 |

**免费 / Pro 分界（v1.0 实际）**：免费 = 1 本书 + 不限字数/章/场景 + 大纲拖拽 + 每日目标与统计 + 版本历史 + TXT/Markdown 导出；**Pro（一次买断 $9.99）= 不限项目数 + Word(.docx) 导出**。同步 / 云端历史 / 资料板**不在 v1.0 的售卖文案里**（G8a ⑧：卖点必须真的存在），`store/listing.md` 已按此重写，原文案挪到该文件末尾等 M2。

**G8b-7「第 3 次核心操作」= 一次改动了正文的写作会话结束**（离开编辑器或切到别的场景时结算）。调用点只有 `EditorScreen._closeSession()` 一处；从版本历史恢复不计入（恢复后会重置本次会话基线）。

**视觉（G3）**：色相 **198°**（色相分配表里 190–210° 的空档，与 remcard 174° / orbit 223° 各差 ≥20°）。art direction 是「纸与墨」：浅色是骨白纸面 `#F6F4EE`、深色是墨蓝 `#0E1519`，编辑器永远坐在 `surfaceContainerLowest` 那张「纸」上。**signature 场景**是首页 hero 的自绘墨迹：一支笔尖沿手写曲线把一道墨线写出来，**写到哪儿就是今天离目标还差多少**（`lib/tool/ui/ink_mark.dart`，`AnimationController` + `CustomPainter`，尊重「减少动态效果」）。图标由 committed 的 `scripts/icons.mjs` 逐尺寸矢量渲染（此前这个生成器只存在于会话 scratchpad 里，每轮重写）。

---

## 7. 指数拆解（2026-09-13 立项）

| 科目 | 分 | 依据 |
|---|---|---|
| 信号持续性 | **26/40** | 商店侧：龙头连续在美区付费榜（今日 #92），**停更 2 年仍在榜**＝需求持续；Reddit 侧：`r/Scrivener` 的同步抱怨与安卓请愿是**常年重复的帖子类型**，非单点。**扣分项**：本项目自己只跟踪了 1 天，跨源交叉 2（商店 + Reddit），无 GitHub 侧参考实现 |
| 付费验证 | **22/25 ✅** | 主词付费 **7 支**，$1.99~$23.99；龙头 $23.99 且**在榜**；去噪后真实体（≥50 条）5 支。价格带是本项目见过最高的之一 |
| 开发可行性 | **13/20** | Flutter 单套代码覆盖双端；无端侧模型、无标定、无版权内容。**扣分项**：编辑器 + 拖拽大纲 + 同步冲突是**真正的工程量**，不是单手可描述的小工具 —— 按 08-30 放宽条款③ 已拆 M1/M2/M3 |
| 竞品缺口 | **11/15 ✅** | 有效离散 **2 支**：`Scrivener`（★4.18 / 2,604 条 / **停更 2 年**）、`yWriter`（★3.08 / 25 条 —— 纪律 R 伪实体，不计）。纪律 AM 三问：① Scrivener **是龙头不是陪跑者**；② 主词下**不存在同一用途**的在维护付费替代（`iA Writer` 是单文档编辑器、`Story Planner` 只做规划、都不做章节化组织）→ **缺口成立**。加分：**安卓侧 0 支对应物** |
| **合计** | **72** | **双硬门：付费 22 ≥ 15 ✅、缺口 11 ≥ 5 ✅ → 入队** |

**→ 队列位置：指数 72，排在 `daycount/Daybird`(75) 之后、`tunekit`(67) 之前 = 总览 #3。**
**⚖️ 但它是当前唯一的 `⚪排队` 项**（#1/#2 均为 🧪待验收/✅已上架），所以**下一轮工厂按「取队首的待做项」规则，取的就是它的 M1**。

---

## 8. 已知风险 / 未决（立项时写清楚，别到 G2 才发现）

1. **🔴 最大风险：编辑器**。Scrivener 的格式化 bug 说明富文本在移动端不好做。**处置**：v1 坚决用「Markdown 存储 + 轻量行内渲染」，**不引入富文本引擎**；如果用户要求 WYSIWYG，放到 M3 再评估。
2. **🔴 第二风险：同步冲突**。两台设备离线改同一个场景，必须**保留双版本让用户选，绝不静默覆盖** —— 这批用户刚被丢稿坑过，一次静默覆盖就是致命差评。
3. **⚠️ Scrivener 会不会突然更新？** 它停更 2 年但公司还在（桌面版在维护）。**可证伪条款（绑 2026-12-13）**：若 `Scrivener` iOS 版在此之前发布新版且 ★ 回升至 ≥4.4，缺口分须从 11 下修重估。**每周实查一次版本日期。**
4. **⚠️ 安卓那块空地有没有别人占了？** 本次只查了 App Store。**M2 立项前必须补一次 Google Play 实查**（Scrivener 安卓替代品：JotterPad / Novelist / Writer Plus 等），否则安卓这条楔子是没验过的。**这一条是 M2 的前置，不做完不准进 M2。**
5. **⚠️ 服务端是本项目第一次做后端 app**。运维、备份、数据丢失责任全是新的。**M1 完全不碰服务端**，正是为了让 M1 能独立上架，把服务端风险隔离在 M2。
6. **DOCX 导出**用纯 Dart 拼 OOXML，格式兼容性需真机验证（Word / Pages / Google Docs 三家都要打开看）。

---

## 8a. G5 / G8a 审计轮（2026-09-16，两个独立只读 agent）

**修掉的 P0（会丢稿 / 会被拒 / 用户走进死路）**

| # | 问题 | 处置 |
|---|---|---|
| 1 | **读取失败被当成「空稿子」** —— `read()` 对「首次启动」「文件损坏」「IO 异常」一律返回 null，`load()` 照样把 `loaded=true`，下一次按键就用空文档覆盖真稿子 | `JsonFileStore.readFailed` 只在**原文件仍在**的失败上置位；`canPersist` 为 false 时**一个字也不写**，首页出红条说明原因（`store.dart` / `json_file_store.dart`） |
| 2 | **自动保存把整本书连同每个场景的 20 份历史快照重新编码一遍** —— 8 万字的书约 9MB JSON，在 UI 线程上每隔几秒来一次 | 版本历史搬到**独立文件** `draftbook_history.json`（只在存版本时写）；主文档写入**合并**（一串编辑只落一次盘）+ 600ms 去抖；`Scene.words` / `Scene.summary` 加缓存 |
| 3 | **导出的 .docx 违反 OOXML 子元素顺序**（`pageBreakBefore` 在 `pStyle` 前、`outlineLvl` 没排最后）—— Word 会弹「内容有问题，是否修复」，而这正好发生在**每一本书的第二章开始** | 全部按 `pStyle → pageBreakBefore → spacing → ind → jc → outlineLvl` 重排，并加了一条**断言顺序的测试** |
| 4 | **一气呵成写完的场景没有任何还原点** —— 全选 + 敲一个字，唯一那份快照存的是「破坏后的样子」 | 一次会话**第一次改动时先存一版**（此刻正文还是会话开始时的样子），外加「一次删掉一半以上」时的 pre-cut 快照 |
| 5 | **iOS 图标带 alpha 通道** —— 15 张全是 RGBA，上传会被 ITMS-90717 打回（仓里另外 12 个 app 都是 RGB） | `scripts/icons.mjs` 加 `opaque` 模式（色彩类型 2），iOS 图标与商店图重出 |
| 6 | 关键词里的 `nanowrimo` 是注册机构商标 | 删掉换 `longform`；`scrivener` **保留**（PIPELINE G8b 明写「关键词 = 长尾 + 竞品名」，与已上架的 autosnore/goldenscout 同口径，理由与退路写在 `store/listing.md` 抬头） |

**修掉的 P1**：`dispose()` 里通知 store → 在「树被锁住」的时机 `setState`（debug 必抛，且是 app 最常走的一条路：写完按返回）→ 通知改为出帧后的微任务，**并补了一条会复现原 bug 的测试**；保存失败完全静默 → 首页红条；中文/日文输入法**组字期间整篇文档掉样式**（每个拼音音节都重排一次）→ 只有正在组字的那一行让位，其余行保持格式；场景拖不出屏幕（内层列表没有滚动范围）→ 菜单补「上移/下移」；导出没有进度指示 → 加转圈。

**没做、按现状记账（不是遗漏）**
- **导出仍在 UI 线程上拼装**：改 `compute` 需要把 `tr()`/`AppLanguage` 拿进后台 isolate（要读 `PlatformDispatcher.locale`），风险大于收益；现在用「转圈 + 禁用整行」兜住感知。**一本 50 万字的书导出时会卡顿，真机验收要试。**
- **多行选中时行首标记只加在第一行**（`MarkdownEdits.linePrefix`）。
- **Play Billing 在 INTERNET 被 `tools:node="remove"` 剥掉后是否照常** —— 结算走 Play Store 进程，**理论上不受影响，但必须在内部测试轨的真机上验一次**（这是隐私卖点与唯一收入路径唯一的交叉点）。

## 8c. 出包与 G6b(2026-09-16)

| 关卡 | 结果 |
|---|---|
| G4 本地验收 | `flutter analyze` **0 issue**；`flutter test` **54 项全过**（其中 6 项是本轮审计的回归测试：读取失败不得覆盖原文档 / 大段删除要留底 / 恢复不计入今日 / 损坏文档不吊销 Pro / 版本历史不进主文档 / **写完按返回不抛异常**） |
| G6 出包 + 冒烟 | run **35058520635** 绿（build-android + smoke-test），G6b 修完后重出包 run **35059979723** 同样两个 job 全绿 |
| G6b 视觉二次 check | 下载冒烟截屏亲眼看了。**打回一次**：① app 内的自绘标记里笔尖朝右上，和启动图标里「笔尖压在最后一行」相反，单看像光标不像笔；② 英文空状态里写死的 `\n` 让三行长短不齐。两条都改掉后重出包复看，通过（见上表第二个 run） |
| 冒烟截不到的屏 | 大纲 / 编辑器 / 版本历史 / 导出 / 统计按源码评审 + widget 测试覆盖（测试会真的打开大纲和编辑器并断言工具条在位） |

**APK 下载**：Actions run `35289549762`（09-18 第二轮审计修完后的包；上一轮的 35059979723 已作废） → artifacts `apps-draftbook-apk`（另有 `apps-draftbook-aab`、`apps-draftbook-smoke`）。**debug 签名，装机验收用；上架前要换 release keystore。**

## 8a2. 第二轮审计（2026-09-18，用户要求「审计你的代码」；对上一轮的修法本身做对抗性复审）

**上一轮的修法里藏了一个 P0**：「一次会话第一次改动先存一版」是用 `_dirty` 判的，而 `_dirty` 每次 700ms 自动保存后就归零 —— 结果是**每停顿一次就存一版**，正常打字几分钟就把 20 个槽位灌满、把真正的旧版本全挤掉，而且每次停顿都重写整个历史文件（把上一轮为了省下的那笔开销又从编辑器那头加回来了）。已改成会话级标记 `_sessionSnapshotted`，并补了一条「三次停顿只留一版」的 widget 测试。

**同轮修掉的 P1**：① 历史文件读不出来时没有写保护，任何一次存版本都会用空历史覆盖真历史 → 与主文档同一类保护（`_historyFile.readFailed` 门）；② 主文档读失败时页面走的是空状态分支，**红条根本渲染不出来** → 空状态上方也挂红条；③ 「写完按返回」那条回归测试是空转的（测试树里没有任何监听 store 的 widget，锁树期间通知没人接，原 bug 触发不了）→ 加了 `ListenableBuilder` 并断言它真的被通知过；④ JSON 合法但形状不对（比如更高版本写的文档降级回来）走的是 catch 分支，`projects` 已清空但 `readFailed` 没置位 → 现在同样算读失败、不落盘。

**P2**：光标移动也会触发 controller 通知 → 加 `_lastText` 门只认真正的文本变化；旧开发版文档里的内联历史 / Pro 标记迁移到新文件；store 层加 `AppLifecycleListener`（大纲页的重排、改名、删章之前只有编辑器那一个钩子）；编辑器落盘时直接 `store.saveNow()` 不再叠第二层去抖（落盘延迟由 1.3s 回到 0.7s）；「保存失败」红条在下一次成功写入后自动撤下；widget 测试改指向临时目录（之前是靠 FakeAsync 恰好不派发 IO 才没写进真实 Documents）。

**审计确认干净的**：微任务通知的时机；Pro 的读写路径；组字行的 span 与原文逐字等长（含跨行组字、表情）；pre-cut 快照不会堆积；Scene 的缓存 setter 没有旁路；上移/下移的索引语义（对照了 SDK 源码）；从 dispose 发起的评分请求不会落在锁树期间。

## 8b. 真机验收清单（G7，用户照着点）

| # | 动作 | 应该看到 |
|---|---|---|
| 1 | 首次打开 | 空状态：自绘的「纸 + 笔」标记、一句引导、一个「新建项目」按钮；**不是**一行冷字 |
| 2 | 新建一本书，写两句话，退出编辑器再进来 | 字数变了；首页 hero 的墨线往前走了；退回首页再进去，光标回到这一场景（两次点击） |
| 3 | 在编辑器里点 **B / I / #** | 选中的字被 `**` / `*` 包住并当场变粗/变斜；`#` 加在行首且整行变大。**键盘弹出时工具条仍在键盘上方** |
| 4 | 中文输入法打一段字（拼音候选窗） | 候选期间不跳字、不丢字（输入法组字期间高亮会让位给系统下划线） |
| 5 | 大纲：拖章的把手、拖场景的把手 | 两级都能拖；顺序退出重进后仍在 |
| 6 | 场景菜单 → 移动到其它章 | 场景带着正文和版本历史过去，目标章自动展开 |
| 7 | 改一段话 → 退出 → 进「版本历史」 | 有一条新版本；点「恢复」后正文回到旧版，**再进历史能看到刚才那版也被存下来了** |
| 8 | 导出 → Markdown / 纯文本 | 系统分享面板打开；发到备忘录/文件里，章节标题和正文都在 |
| 9 | 导出 → Word（未买 Pro） | 弹 Pro 解锁页（列权益 + 商店真实价格 + 恢复购买），**不直接拉起付款** |
| 10 | 新建第二本书（未买 Pro） | 同样弹 Pro 解锁页，并说明「免费版 1 本」 |
| 11 | 设置 → 语言切中文 / English | 全部界面文字跟着切，包括空状态、Pro 页、导出面板 |
| 12 | 深色模式 | 编辑器是墨蓝纸面、正文不刺眼；hero 墨线在深色下仍看得清 |
| 13 | 写到一半直接切后台 / 锁屏，再回来 | 一个字都没丢（切后台即落盘） |
| 14 | 飞行模式全程 | 一切照常 —— 这个 app 根本没有联网权限 |
| 15 | 删除一本书 | 二次确认里写清楚会连版本历史一起删，并提示先导出 |
| 16 | **内部测试轨真机**：设置页点「解锁 Pro」 | 弹出的是**商店真实价格**（不是 $9.99 兜底字样），能走完付款、解锁、卸载重装后「恢复购买」拿回 —— **这一条验的是「剥掉 INTERNET 权限后 Play Billing 仍然通」**，模拟器验不了 |
| 17 | 写满一章（几万字）后导出 Word | 能导出、Word / Pages / Google Docs 三家都**直接打开、不弹「修复」**，章与章之间分页 |

## 9. 立项依据链（可追溯）

```
纪律 AY(2026-09-13 用户拍板：垂直 + 不碰巨头 + 抱怨最多 + 没人做好；服务端解禁)
  └─ Reddit r/Scrivener / r/writers 反复抱怨(同步丢稿 ×5、安卓请愿 ×2、两年不更新 ×1)
       └─ App Store 实查：Scrivener $23.99 / ★4.18 / 2,604 条 / 停更 2 年 / 付费榜 #92 在榜
            └─ 评论 RSS：99 条读到，66 条 ≤3★(67%，跟踪期最高)
                 └─ 主词付费面 7 支 / $1.99~$23.99；免费侧无 ≥10 万支、无巨头 → 过 AY② 一票否决
                      └─ 指数 72，双硬门双过 → 入队
```
