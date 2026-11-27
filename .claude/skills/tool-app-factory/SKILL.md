---
name: tool-app-factory
description: noobclaw 工具类 App 的完整制作规范（选题→挑刺关→立项→设计→开发→审计→出包→TestFlight→ASO→上架→复盘）。凡是在 laura 仓库里新做一个工具 App、给已有 App 改版、审计、打包、提审、写商店文案时都用它；Flutter 壳与原生 SwiftUI 两条技术路线都覆盖。
---

# Tool App Factory — noobclaw 工具 App 制作规范

这是我们自己做了 15 个工具 App（remcard / autosnore / echo-jot / orbit / daycount / fieldstamp / goldenscout / photolift / picbox / tunekit / astropile / ohmbench / draftbook / clean-alarm / groovelens）之后沉淀下来的规矩。**每条规矩背后都有一次真实事故**，事故记录在 `references/07-教训.md`。

仓库原文是最终依据：`CLAUDE.md`（选题标准）、`PIPELINE.md`（工厂 SOP）、`kb/`（知识库）。本 skill 是它们的**可执行版本**：按关卡给出检查清单和模板。两边冲突时以仓库原文为准，并回来修本 skill。

## 什么时候用哪一份

| 你要做的事 | 先读 |
|---|---|
| 判断一个点子能不能做 / 进 BACKLOG | `references/01-选题与挑刺关.md` |
| 开工做一个 App（任何技术栈） | 本页「关卡总表」+ `references/02-工厂SOP.md` |
| 定视觉、写界面、评审好不好看 | `references/03-UIUX.md` + `templates/design-brief.md` |
| 原生 iOS（SwiftUI）路线 | `references/04-iOS原生SwiftUI.md` |
| Flutter 壳路线 | `PIPELINE.md` 的 G3 细则（壳 `shell/`、`new_app.mjs`） |
| 内购、定价、付费墙 | `references/05-变现与内购.md` |
| 多语言（10 种，必做） | `references/08-多语言.md` |
| 出包、TestFlight、ASO、提审 | `references/06-ASO与上架.md` |
| 审计（G5 / G8a） | `templates/audit-checklist.md` |
| 写 PLAN.md | `templates/PLAN.md` |

配套的通用 Apple 开发 skill（rshankras/claude-code-apple-skills，MIT，装在同级目录）按需调用：`ios`（HIG 审查）、`swiftui`、`swift`（并发）、`testing`、`performance`、`design`（含 game feel）、`monetization`、`app-store`、`release-review`、`legal`（隐私政策）、`security`（隐私清单）。**它们管「怎么写好 Swift」，本 skill 管「我们怎么做产品、过哪些关」。** 两者冲突时以本 skill 为准。

## 关卡总表（顺序执行，前一关不过不进下一关）

| 关 | 名称 | 过关标准（一句话） | 产物 |
|---|---|---|---|
| 挑刺 | 立项前挑刺关 | 双硬门（缺口 ≥5/15 且付费 ≥15/25）+ 分发 >0 + 热度/竞争 ≥3 + 最危险假设已实验 + 评分 ≤14 天 | BACKLOG 条目 |
| G0 | 防撞车 | 近 2.5 天 `apps/` 无其他新 App 提交（里程碑项除外） | — |
| G1/G1b | 取题与复核 | 取 BACKLOG 排队最高项；评分缺项/过期/硬门不过 → 退回日报 | — |
| G2 | 立项评审 | 差异化楔子一句话、招牌功能架构、权限流程、定价、**设计简报**都写进 PLAN.md | `PLAN.md` |
| G3 | 开发 | 先落 design token 与字体，再写页面；铁律见下 | 代码 |
| G4 | 本地验收 | 编译零错误 + 单元测试全过 + **10 语言覆盖率 100%**（原生路线在 CI 上跑） | 测试报告 |
| G5 | 独立审计 | 按「装到真机什么会坏」审一遍，修完复审 | 审计记录 |
| G6 | 出包 + 冒烟 | CI 绿 + 模拟器启动截屏**亲眼看过**（en / zh-Hant / ja / de 四种语言） | 截屏 |
| G6b | 美观复查 | UIUX 打分 ≥75 且无否决项 | 评分表 |
| G7 | 记账 | 过冒烟只准写「🧪待验收」 | BACKLOG |
| G8a | 提审前审计 | 8 个面（购买/iOS/Android/语言/错误/数据/崩溃/文案一致）无 P0/P1。**任何出包前都要过** | 审计报告 |
| G8c | 参考保真 | 有 GitHub 参考的写 REFERENCE.md，「漏掉」=0 | REFERENCE.md |
| G8b | ASO | 主词实测、三件套、截图首图即广告 | `store/aso.md` |
| G8 | 上架 | 真机验收过 + 真内购 + 每周 1–2 个 | — |

## 十三条铁律（违反任何一条 = 打回）

1. **先打分后开工。** 没过挑刺关的题不写一行代码（TuneBench 先做后评，被 4.3(a) 拒）。
2. **CI 绿 ≠ 能用 ≠ TestFlight 有包。** 必须亲眼看截屏；上传后去 ASC 的 Build Uploads 看是否 Failed（ITMS-90683）。
3. **出包前必审计。** 包括 TestFlight 包。没审过的包传上去就是让用户替你测崩溃。
4. **每个付费门先弹付费页。** 付费页列出 Pro 内容 + 商店真实价格 + 解锁 + 恢复购买；禁止任何入口直接拉起付款，价格禁止写死。
5. **不许长得一样。** 每个 App 自己的色相（查色相表，±20° 不撞）、自己的字体、自己的 hero 形态、至少一处承载真实数据的自绘图形、专属图标。
6. **首屏就是工具本身。** 不是「标题栏 + 齿轮 + 卡片列表」；冷启动 ≤2 次点击看到第一个结果。
7. **必须完整支持 10 种语言，翻译没做完不出包（含 TestFlight）。** en（源语言、ASC 主语言 English (U.S.)）、zh-Hant、zh-Hans、ja、ko、de、fr、es、pt-BR、it。范围：App 内全部文字 + 权限说明 + 显示名 + 商店文案。App 名和标题用英文，不用中文。**设置页必须有 App 内语言切换，立即生效，不跳 iOS 设置；语言行放在设置页最上方（Pro 卡片下第一行），设置入口用齿轮图标，且首屏就能一点打开（用户 2026-11-27：「语言切换在设置里更方便」）。**流程与闸门见 `references/08-多语言.md`。
8. **权限：用到时才要，说清用途，拒绝有出口。** `NS*UsageDescription` 写明用途；拒绝后给「去设置」；禁止静默失败。
9. **只发 iPhone、竖屏**（`TARGETED_DEVICE_FAMILY=1`），除非 PLAN 明确写了 iPad 设计。
10. **必须有分享功能（用户 2026-11-27 拍板）。** 每个 App 至少一个「把成果分享出去」的入口：生成一张好看的分享图（1080×1350，带 App 名与成果，敏感数据默认隐藏，可开关）走系统分享面板；首屏有明显的分享按钮（`square.and.arrow.up`），不能只藏在「⋯」菜单里。分享图免费，它也是拉新渠道。用到保存相册时 Info.plist 必须有 `NSPhotoLibraryAddUsageDescription`（10 语言）。
12. **审核录屏自己录，不找用户（用户 2026-11-27 拍板）。** CI 在模拟器上自动录一段完整英文操作视频，首次送审就作为审核附件上传，做法见 `references/07-教训.md` 11-27 条。只有 Apple 明确要求实机录屏时才请用户录。
13. **必须引导好评（用户 2026-11-27 拍板）。** 每个 App 内置评分引导：
   - 时机：用户刚完成一件「有成就感」的事（存好第一个作品、完成一次核心流程、连续使用第 N 天）之后，且距上次弹窗 ≥30 天；出错、付费墙、首次启动 5 分钟内一律不弹。
   - 两步：先弹自家小卡片「喜欢 <App> 吗？」→「喜欢」才调系统评分窗（SwiftUI `@Environment(\.requestReview)` / `SKStoreReviewController`，iOS 每年最多显示 3 次），「还不够好」转到意见反馈（mailto 支持邮箱），不让差评先上商店。
   - 设置页常驻「给我们评分」一行（跳 `itms-apps://itunes.apple.com/app/id<APPID>?action=write-review`）。
   - 🔴 红线：不能以任何奖励换评分/评论（Guideline 3.2.2(x)、5.6.1），不能自己画假的星星评分窗，不能要求评论才解锁功能；系统评分窗无法回传评了几星，也不能「默认五星」。Google Play 禁止「先问满意再决定是否引导评分」的筛选做法，Android 版只用系统 In-App Review API，不加前置卡片。
11. **状态如实。** 过冒烟只写「待验收」；上没上架以 iTunes lookup 为准；做不到的说做不到。

## 用户拍板优先

用户对某个 App 明确选定的方向（例如 Groovelens 选了「霓虹节奏舞台」的游戏感），**优先于** UIUX 禁用清单里的同类条款。做法：在 PLAN.md「设计简报」里写一行「用户拍板偏离：<条款号> → <用户选择>，日期」，评审时这些条款不扣分；其余条款照常执行。

## 回报格式

每过一关，用一句话回报：过了什么、证据在哪（截屏/测试数/审计报告路径）、下一关是什么。卡住时说清卡在哪、需要用户做什么（例如在 ASC 建 App 记录、建内购商品），不要绕过去假装完成。
