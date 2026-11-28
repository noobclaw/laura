# INTAKE：Cozy Days 接手清點（第 13 步）

- 日期：2026-11-28
- 驗收版本：`codex/cozy-days-web` @ `ba26dc1`
- Claude 分支：`claude/cozy-days-qa`
- 依據：`codex-handoff-test`（倉庫版 `.claude/skills/claude-codex-test/`）、`casual-game-production`
- 品類判定：單機休閒整理消除類，按 `casual-game-production` 的標準驗收。

## 一、交接包清點

| 交接項 | 必須 | 狀態 | 實際找到的 |
|---|---|---|---|
| 新版策劃書（世界觀、核心循環、系統清單、每個系統的規則） | ✅ | **缺件** | 沒有獨立策劃書。規則散在 `README.md`（約 8 KB）和 `PLAN.md`（約 2 KB）；沒有世界觀、故事和角色 |
| 數值表 | ✅ | **缺件** | 沒有。數值只在代碼裡：`src/policies.js`、`src/campaign.js`、`src/shop.js`、`src/festivals.js` |
| 關卡表（每關教什麼、考什麼、組合什麼、目標時長與勝率） | ✅ | **缺件** | 沒有。只有 `data/stage-001…160.json` 和 `campaign.js` 前 20 關的件數表 |
| 原版對照表 | ✅ | **缺件** | 沒有。交接文件沒寫原版是哪款遊戲 |
| 創新清單 | ✅ | **缺件** | 沒有 |
| 美術規格九節 + 維度/引擎/光照/材質決定 | ✅ | **部分** | `presentation/american-v1/PRODUCTION.md` 只有方向一段話；`ACCEPTANCE.md` 有 2.5D 圖片平面 + 主頁 3D 剛體的說明。九節中的形狀語言、色板、角色、介面、素材標準、參考方向都沒寫 |
| 素材登記表 | ✅ | **部分** | `presentation/american-v1/manifest.json` 登記了 425 個物品和 8 個房間，有生成工具、雜湊和提示詞路徑；授權欄寫「release review pending」。UI 圖示、主頁圖、相冊組合圖要逐一核對（見 ART-REVIEW） |
| Codex 的交付前自評四項 | ✅ | **缺件** | 沒有手感矩陣、好玩標準打分和並排圖；只有部分截圖（`verification/`） |
| 可運行版本與啟動方式 | ✅ | 有 | `index.html` + `build/`；`START.md` 寫了用 `python3 -m http.server` 啟動 |
| Codex 自己的測試與驗收記錄 | ✅ | 有 | `test/*.test.js`（5 個檔案）、`verification/`、`presentation/american-v1/ACCEPTANCE.md` |
| 原版拆解材料 | 建議 | 沒有 | 無法做原版代碼和素材的比對 |

**流程偏差（記錄，不阻塞）**：用戶的流程規定生圖用 gameartstyle.loopyhop.com 的提示詞配 img2.5。`prompts/*.txt` 和 `PRODUCTION.md` 都沒有引用這個網站，工具寫的是「built-in image_gen」。需要 Codex 說明是不是故意的。

## 二、交 Codex 的補件要求

請在 `codex/cozy-days-web` 補齊以下文件，放在 `apps/cozy-days/design/`：

1. `GDD.md`：世界觀與故事背景、核心循環（30 秒／一局／一天）、系統清單，以及每個系統的規則（逐條寫，標明「沿用原版」或「我們的創新」）。
2. `NUMBERS.md`：體力（上限、恢復、入場、返還）、星級門檻、道具（解鎖關、贈送、價格）、商店商品、每日競速、週聯賽、相冊、成就的全部數值及設計理由。
3. `LEVELS.md`：160 關每關的件數、類別數、教什麼、考什麼、組合什麼、節奏（學習／緩衝／挑戰）、目標時長和目標勝率。
4. `ORIGINAL-MAP.md`：原版是哪款遊戲，原版規則 → 已做／改了／故意不同（附理由）。
5. `INNOVATION.md`：每條創新解決原版的哪個問題，怎麼驗證。
6. `ART-SPEC.md`：美術規格九節。
7. `SELF-REVIEW.md`：交付前自評四項（手感矩陣、好玩標準八條打分、並排截圖、≥10 秒動態）。
8. 說明生圖為什麼沒有用 gameartstyle.loopyhop.com 的提示詞。

**策劃書補齊之前**：Claude 暫時把 `README.md` 和 `PLAN.md` 當作規格寫用例，每條用例都標了出處。只能從代碼看到、文件裡沒寫的設計，對應的用例標「未評估：缺策劃」，或寫成「與 README 不一致，待策劃確認」。

## 三、基線

| 項目 | 命令 | 結果 |
|---|---|---|
| 單元測試 | `node --test`（Node v22.23.5） | 56 項通過，0 項失敗，耗時約 4.7 秒 |
| 構建 | 未重跑 | 這個環境不能安裝依賴（沒有網路）。直接驗證倉庫裡已附的 `build/` 產物 |
| 運行 | `python3 -m http.server` + 無頭 Chrome（Playwright 1.63） | 見 TC-RESULT |
