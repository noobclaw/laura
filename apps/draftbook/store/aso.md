# Draftbook — ASO

> 按记忆 `feedback_laura_aso_every_app` 的三层：元数据 / 转化 / 评价。每项都要有 iTunes API 实打的读数，不许凭感觉。

## 0. 命名撞名实查（2026-09-13，立项当天）

| 候选名 | 逐字 / 前缀同名 | 判定 |
|---|---|---|
| **Draftbook** | **0 支** | ✅ **采用** |
| Scribehouse | 0 支 | 备选 |
| Manuscript | 2（`Manuscript Lite` ★0.00/0、`Manuscript Study Bible` ★5.00/2） | ❌ 有逐字同名 |
| Draftsmith | 1（`Draftsmith: AI Writer` ★4.33/6） | ❌ |
| Chapterly | 4（含 `Chapterly - chapter manager`） | ❌ |
| Novelist | 4（含 `Novelist - Write novels` ★4.40/210） | ❌ |
| Longform | 1（`Longform Reader` ★3.20/5） | ❌ |
| Chapters | 2，其中 `Chapters: Interactive Stories` **★4.40 / 115,452 条** | ❌❌ 巨物 |
| Quill | **14 支** | ❌ 重灾区 |

**→ `Draftbook` 是唯一逐字/前缀同名为 0 的候选。** 按 ASO 铁律「只有逐字同名才是硬规则，前缀共享主词是目的」，本名同时满足两条：不撞名，且标题里带 `Novel Writing` 这个主词。

## 1. 元数据层

**名称**：`Draftbook: Novel Writing`（24 字符）
**副标题**：`Chapters, outline & drafts`（26 字符）
**关键词**（98 字符）：`scrivener,manuscript,corkboard,scene,writer,author,book,wordcount,longform,storyboard,offline,plot`

> ⚠️ **2026-09-16(M1 落地当轮)修订**：副标题原为 `Chapters, outline & sync`，而 **v1.0 没有同步**（M2 才有）——
> 卖不存在的功能是 App Store 3.1.1 的直接拒审项，也正是本 app 要回应的那条「felt deceived」差评。
> 同理，关键词里的 `sync` 一并撤下，等 M2 真的发出去再加回。
> 另：`novel` / `writing` 已在标题，`chapters` / `outline` / `drafts` 已在副标题，苹果自动合并，关键词字段不再重复。

主词选择依据（2026-09-13 iTunes API 实打）：

| 主词 | 命中 | 付费支数 | 用途 |
|---|---|---|---|
| `long form writing organize chapters` | 44 | **7** | 主战场，付费面最厚 |
| `novel writing app outline` | 46 | 4 | 第二主词 |

⚠️ **`scrivener` 放在关键词字段是允许的，但正文与截图文案里一律不提竞品名**（审核 + 商标风险，见 `store/listing.md` 抬头）。

## 2. 转化层

- **首图必须是大纲拖拽**，不是编辑器 —— 大纲是这个品类唯一不可替代的能力，编辑器人人都有。
- 截图 1/2/6 的文案要落在三个楔子上：重排整本书、工具条随时在、没有账号不联网。
- **图标（2026-09-16 已出）**：墨蓝渐变底 + 米白稿纸 + 一支斜压在稿纸上的笔（笔尖在最后一行，留下一个墨点）。生成器是committed 的 `scripts/icons.mjs`（纯 Node，无依赖，逐尺寸矢量渲染），色相 198° —— 与现有 11 个 app 的色相带各差 ≥20°（铁律 `feedback_app_icon_product_specific` + `feedback_laura_visual_disciplines_0911` 的「不许长得一样」）。

## 3. 评价层

- **实现（v1.0）**：壳的 `ReviewPrompt.noteCoreAction()`，在**第 3 次「改动了正文的写作会话」结束时**调一次原生 `requestReview()`，90 天内最多一次（PIPELINE G8b-7）。调用点只有一处：`EditorScreen._closeSession()`。
- **不得在丢稿/恢复版本之后弹** —— 恢复版本走的是 `HistoryScreen`，不经过 `_closeSession()` 的计数路径。

## 4. 上线后要实打的可发现性基线（绑上架当天 + 之后每日）

| 主词 | 目标 |
|---|---|
| `novel writing app outline` | 上线 14 天内进前 20 |
| `long form writing organize chapters` | 上线 14 天内进前 10 |
| `manuscript chapters` | 记基线 |
| `Draftbook`（全名） | 上线即 #1（**n 很小，不构成读数**，只作索引生效的信号） |

> ⚠️ 按 `Orbit` 的实测，索引生效有数日延迟，且**前几天的位次波动是噪声**（09-13 实测 `satellite pass alerts` #24→#27→#28→#23，三日"单调下行"当天就反转了）。**任何单日位次变化不作数，须连续 3 日同向才定性。**
