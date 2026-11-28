# AUDIT：Cozy Days 代碼、玩法、關卡、數值、淨室審計（第 14 步）

- 審計版本：`codex/cozy-days-web` @ `ba26dc1`
- 審計者：Claude（非作者審計）
- 日期：2026-11-28
- 證據目錄：`qa/evidence/`；工具：`qa/tools/`
- 狀態：**已修**＝Claude 已改代碼並附回歸測試，見 `CHANGELOG-claude.md`；**交 Codex**＝見 `CODEX-REQUESTS.md`；**待決定**＝需要用戶或策劃決定

## 一、總表

| ID | 嚴重度 | 發現 | 證據 | 狀態 |
|---|---|---|---|---|
| AUD-01 | P1 | 手機時鐘往回撥後，體力恢復倒數被推到最多 24 小時之後，體力凍住 | `kernel-cases.json` TC-CHEAT-01/02（修前 refillIn 37800 秒、88200 秒） | **已修** `3884773` |
| AUD-02 | **P0** | 存檔損壞時開機直接顯示「保存失敗」，沒有開始按鈕，玩家永遠進不了遊戲 | `m-corrupt-save-boot.jpg`、`browser-check-2.json` corruptBoot | **已修** `c204268`，驗證圖 `fix-corrupt-save-recovered.jpg` |
| AUD-03 | P1 | 首次啟動固定顯示簡體中文，不跟系統語言（目標市場是美國和阿拉伯地區） | `browser-check.json` TC-I18N-SYS；`m-home-first-launch.jpg` | **已修** `c204268`，驗證圖 `fix-first-launch-en.jpg` |
| AUD-04 | **P0** | 第 21–160 關不用道具基本過不了。第 1–20 關經 `balanceStage` 重排（暫存欄峰值 0），第 21 關起沿用舊排布。免費玩家只有各一次的贈送道具，會永久卡在第 21 關 | 貪心機器人 160 關只過 21 關（1–20 + 51）：`kernel-cases.json` TC-LVL-03；beam search 第 21、22、30、60、100、160 關全部失敗：`solver-no-tools.json`；連開第 3 個需求箱 + 7 格暫存欄（等於付費空間包）第 21、30、60 關仍失敗：`solver-expanded.json`；Claude 在真實構建版親自玩第 21 關，收 10 次後暫存欄滿而輸，36 個需求只完成 2 個：`m-stage-021-start.jpg`、`m-stage-021-end.jpg` | 交 Codex CR-01；**待決定**（關卡重排方案） |
| AUD-05 | P1 | 設定頁寫「勝利返還」體力，但代碼只在首通或星級提升時返還；重玩已三星的關卡贏了不返還 | `kernel-cases.json` TC-ECO-03；`src/progress.js` completeRound；`examples/strings.js` entry | **已修** `9416991`（用戶決定改代碼：每次勝利都返還） |
| AUD-06 | P1 | 正式玩家的設定頁和頁尾露出「關卡測試（獨立沙盒）」，可以直接選全部 160 關、無限使用道具 | `m-settings-zh.jpg`、`m-settings-zhTW.jpg` | 交 Codex CR-03（上架版移除或隱藏） |
| AUD-07 | P1 | 沒有分享功能（結算頁只有下一關、重來、回首頁） | `browser-check.json` TC-FUN-02；`m-result-001.jpg` | 交 Codex CR-04 |
| AUD-08 | P1 | 沒有引導評論，設定裡也沒有「給我們評分」 | `browser-check.json` TC-FUN-06 | 交 Codex CR-05 |
| AUD-09 | P1 | 只有 3 種語言（簡中、繁中、英文）；casual 標準第一批要 7 種（en/ar/ja/ko/de/fr/es） | `examples/strings.js` 每個鍵只有 3 個值 | 交 Codex CR-06 |
| AUD-10 | P1 | 沒有去廣告商品；廣告和內購都沒接，道具的唯一來源是購買憑據 | `kernel-cases.json` TC-MON-05；`src/shop.js` | 交 Codex CR-07，見 `MONETIZATION.md` |
| AUD-11 | P1 | 設定缺「震動開關」和「減少閃光」（casual 手感規則要求） | `browser-check.json` TC-SET-TOGGLES | 交 Codex CR-08 |
| AUD-12 | P1 | 英文版道具按鈕文字被截斷（「Fill reques t」「Retur 3」「Eras an object」），底部導覽「Achievemen ts」斷字 | `m-stage-001-start.jpg`、`m-result-001.jpg` | 交 Codex CR-09（涉及按鈕排版和字級，屬視覺，按規矩交 Codex） |
| AUD-13 | P1 | 橫屏 844×390：首頁標題和按鈕重疊，設定按鈕和「排行」被切掉，關卡物品小到認不出來 | `l-home.jpg`、`l-stage-001.jpg` | 交 Codex（ART-FIX AF-05）；或決定手機版鎖直屏 |
| AUD-14 | P2 | 失敗彈窗顯示的是道具操作說明，沒有說明為什麼輸、怎麼避免；也沒有「用道具救一局」的入口 | `m-result-001.jpg`（第一次運行的失敗畫面）、`m-stage-021-end.jpg` | 交 Codex CR-10 |
| AUD-15 | P2 | `SortingSession.dispatch(null)` 拋 TypeError；未知命令拋例外。上層有 try/catch，不影響玩家 | TC-RULE-05 | 不修，記錄 |
| AUD-16 | P2 | `advance` 接受極大值（1e12 秒），規則層沒有上限 | TC-RULE-06 | 不修：呼叫方只傳每幀時間，記錄 |
| AUD-17 | P2 | 局完成後 `arrival` 留著已送走的物品編號；`save()` 會清掉，不影響可玩狀態 | TC-RULE-07（9/30 局，都在 done 狀態） | 不修，記錄 |
| AUD-18 | P2 | `PlayerJournal` 接受 `ratings` 為字串、道具餘額為負數的存檔（使用時有 `> 0` 檢查，不能刷） | TC-SAVE-02 | 交 Codex CR-11（順手補驗證） |
| AUD-19 | P2 | 前 4 關一局不到 1 分鐘（22–53 秒，估算），低於 casual 標準的 1–5 分鐘；作為教學關可接受 | TC-LVL-07 | 記錄，策劃確認 |
| AUD-20 | P2 | 第 1–20 關暫存欄峰值都是 0：每一步都有可直接送的物品，沒有任何取捨；第 21 關又突然變成不可解。難度曲線從「零決策」直接跳到「不可能」 | `kernel-cases.json` levels[].trayPeak | 和 AUD-04 一起處理 |
| AUD-21 | 資訊 | 生圖沒有用 gameartstyle.loopyhop.com 的提示詞（工具寫的是 built-in image_gen），和用戶流程不同 | `presentation/american-v1/prompts/*.txt` | 交 Codex 說明，見 `INTAKE.md` |

## 二、代碼審計（完工清單第 4 道）

| 項目 | 結論 | 依據 |
|---|---|---|
| 主迴圈錯誤保護 | 部分 | `task()` 包了 try/finally；初始化失敗時原本整頁死掉（AUD-02，已修）。單幀渲染錯誤的保護沒有單獨驗證 |
| 規則與畫面分離 | 通過 | `src/` 規則層可在 Node 單獨跑；Claude 的 160 關機器人直接用內核 |
| 存檔：版本、遷移、原子寫、壞檔 | 部分 → 已修 | 有 schema 和 edition；寫盤失敗不發布（TC-SAVE-03 通過）；壞檔原本鎖死（AUD-02 已修）；欄位型別驗證不全（AUD-18） |
| 計時器與監聽同生同死 | 通過（抽查） | 連續進出 10 局後 DOM 節點和 canvas 數沒有持續上漲（`browser-check.json` TC-PERF-03 前半段；後半段因頁面切換超時，記為部分） |
| 非同步競態 | 通過 | 飛入動畫期間的按鍵會被忽略（`uiBusy`），不會重複收取；Claude 的自動化腳本必須等每一步完成才能繼續，正好證明了這點 |
| 時間作弊 | 已修 | AUD-01 |
| 刷資源 | 通過 | 重複購買憑據被拒（TC-CHEAT-03）；同一關重玩不重複發體力（反而和文案不一致，AUD-05） |
| 依賴鎖定與授權 | 通過 | `pnpm-lock.yaml`、`THIRD_PARTY_NOTICES.txt`、`build/licenses.json` |
| 主控台 | 通過 | 正式流程沒有應用錯誤；只有依賴的棄用警告（THREE.Clock、Rapier 初始化參數）和 SwiftShader 的 GPU 效能提示 |

## 三、玩法、關卡、數值（完工清單第 3、7 道）

- **機器人**：`qa/tools/kernel-cases.mjs`，和正式遊戲同一條資料管線（`balanceStage` → `applyAmericanArt` → `SortingSession`）。貪心機器人 3 個種子、隨機機器人 5 個種子，每關都跑。
- **求解器**：`qa/tools/solver.mjs`，在「暫存哪一件」上做 beam search（寬 6–15、分支 10–15）。
- **可解性**：第 1–20 關無道具可解；第 21–160 關中只有第 51 關被機器人解出。這只證明「找不到解」，不是嚴格證明「無解」；但真人實玩（Claude 親自玩第 21 關）的結果一致。
- **選擇有沒有意義**：貪心平均勝率 12.7%，隨機 0%；第 1–20 關貪心 100%，因為根本不需要選擇（AUD-20）。
- **獎勵間隔**：已解的關卡中，完成兩個需求箱之間最長約 13 秒（中位數），符合每 15–30 秒一次的標準（TC-FUN-01）。
- **30 天經濟模擬**（不付費、不看廣告）：用機器人勝率模擬，**第 1 天就打完第 1–20 關，之後卡在第 21 關**。原模型假設每關至少 15% 勝率，和求解器結果矛盾，已作廢，結論改判**不通過**（卡死）。
- **體力**：上限 5、每 30 分鐘 +1、入場 −1、首通 +1（TC-ECO-01/02/05 通過）。
- **原版對照、創新是否更好**：未評估（缺原版對照表和創新清單）。

### 好玩標準八條（casual 原文）

| # | 標準 | 結論 | 依據 |
|---|---|---|---|
| 1 | 獎勵密集 | 通過（第 1–20 關） | 完成需求箱的間隔中位數約 13 秒 |
| 2 | 每局有高潮 | 部分 | 過關有星星彈出和彩帶（`motion-normal-pick-and-win.jpg`）；局中完成一箱沒有「大」級反饋 |
| 3 | 輸了不白玩 | 不通過 | 失敗只能花 1 點體力重來，沒有帶走任何東西 |
| 4 | 一個招牌動作或聲音 | 部分 | 主頁可以點擊裝箱 3D 玩具；聲音未經人耳 |
| 5 | 角色有梗 | 不通過 | 沒有角色和台詞 |
| 6 | 可分享 | 不通過 | AUD-07 |
| 7 | 每天回來的理由 | 部分 | 每日競速和週聯賽在第 12 關解鎖；沒有連續天數獎勵 |
| 8 | 廣告拍什麼遊戲就有什麼 | 未評估 | 沒有廣告素材 |

### 八條驗收標準（casual 原文）

| # | 標準 | 結論 |
|---|---|---|
| 1 | 核心玩法簡單且打磨過 | 部分：第 1–20 關順，第 21 關起不可玩 |
| 2 | 留存目標與測量方法 | 不通過：沒寫 |
| 3 | 每天回來的理由 | 部分 |
| 4 | 目標玩家寫清楚 | 不通過：缺策劃書 |
| 5 | 經濟模型算得過來 | 不通過：30 天卡死 |
| 6 | 美術乾淨統一、操作有手感 | 部分：見 `ART-REVIEW-20261128.md` |
| 7 | 買量和試投放計畫 | 不通過：沒寫 |
| 8 | 專注一款、持續迭代 | 通過 |

## 四、淨室查重

- **原版代碼比對**：無法進行，Codex 沒有提供原版拆解材料，也沒寫原版是哪款遊戲。
- **素材**：`manifest.json` 登記了 425 個物品和 8 個房間，全部標「built-in image_gen」，有生成雜湊和提示詞；運行時引用舊路徑的數量沒有重查（Codex 驗收記錄寫是 0，Claude 未獨立重跑，標「僅記錄所述，未證實」）。
- **商標外觀風險**：見 ART-FIX AF-03。
- **授權**：AI 生成素材標「release review pending」，上架前要結論。

## 五、Codex 自測盲點（Claude 有、Codex 沒有）

1. Codex 寫「160 關 × 兩版共 320 次輔助推進通過」，沒指出第 21 關起不用道具幾乎過不了 → AUD-04。
2. 沒有測壞檔開機 → AUD-02。
3. 沒有測時鐘回撥 → AUD-01。
4. 沒有測首次啟動語言 → AUD-03。
5. 沒有對照介面文案和實際數值 → AUD-05。
6. 沒有測橫屏 → AUD-13。
