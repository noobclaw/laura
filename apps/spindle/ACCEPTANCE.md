# Spindle — 质量验收（tool-app-sop 第 7–8 步）

**验收 = 按 TEST-CASES.md 把用例真的跑一遍，看 `qa/TC-RESULT-<build>.md` 说话。** UX 标准 = tool-app-factory `03-UIUX.md`（G6b ≥75 且无 V1–V9 否决）。

## 1. M1 出口（全过才记「🧪待验收」）
| # | 闸 | 判定 | 证据 |
|---|---|---|---|
| A1 | 编译 | CI 零错误 | `spindle-ci` 分支 summary.txt |
| A2 | 单测 | U 类 100% 通过 | TC-RESULT |
| A3 | UI 自动化 | A 类 100% 通过；连点巡游 0 崩溃 | TC-RESULT + ui-shots |
| A4 | 用例执行 | TC-RESULT 中 M1 用例 0 条「未测」（M/D 类可标「待人工」，但必须列出），P0/P1 自动用例全过 | TC-RESULT |
| A5 | 多语言 | 覆盖率闸门通过；en/zh-Hant/ja/de 截屏亲眼看过 | l10n.txt + 截屏 |
| A6 | 审计 | 独立子代理按「装到真机什么会坏」审一遍，P0/P1 修完复审 | 审计记录 |
| A7 | 美观 | G6b ≥75 且无否决 | UIUX 评分 |
| A8 | 人工用例 | M 类 P0/P1 跑完存截屏；P2 挂起 ≤3 条写原因 | 本文件第 5 节 |

## 2. 发布出口（全过才记「📦可发布」）
R1 D 类 P0 全过（TC-PLY-03/04、TC-SRC-04/06、TC-OFF-03、TC-IAP-08）· R2 G8a 八面无 P0/P1 · R3 审核说明写明示范唱片架 · R4 ASC 建 App 与 `com.noobclaw.spindle.pro_unlock`、价格先设、首个 IAP 网页「Add for Review」· R5 App Privacy「不收集」、PrivacyInfo 齐 · R6 CI 自录英文审核视频 · R7 内购/分享/好评 P0 全过 · R8 上架以 iTunes lookup 为准。

## 3. 缺陷分级
P0 崩溃、丢曲库、付费不生效、密码泄露、审核红线 → 阻断；P1 核心流程错、语言明显错、UX 否决 → 阻断该里程碑；P2 可带入 M2 并记录。

## 4. 需要用户做的事
1. ASC 建 App 记录（`com.noobclaw.spindle`，名称 Spindle）与非消耗型内购 `com.noobclaw.spindle.pro_unlock`（$9.99）。
2. 真机验收第 PLAN 17 节的 7 项（需要真实 NAS）。

## 5. 验收记录
| 日期 | 里程碑 | Build | 用例（通过/失败/未测/待人工） | A/R 结果 | 结果表 | 挂起 | 结论 |
|---|---|---|---|---|---|---|---|
