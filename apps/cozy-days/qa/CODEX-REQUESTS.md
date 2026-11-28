# CODEX-REQUESTS：請 Codex 修改的清單（代碼、玩法、功能）

- 對應版本：`codex/cozy-days-web` @ `ba26dc1`；Claude 修改在 `claude/cozy-days-qa`（先合併，見 `CHANGELOG-claude.md`）
- 美術和動效的修改要求另見 `ART-FIX-20261128-1.md`
- 每一項都附證據。修完請在總表把狀態改成「已修待複驗」，附提交號和證據，Claude 會按「驗收方法」複驗
- 先做 P0，再做 P1，再做 P2

## 總表

| ID | 嚴重度 | 項目 | 狀態 |
|---|---|---|---|
| CR-00 | P0 | 補齊策劃文件（`INTAKE.md` 第二節的 8 項） | 待修 |
| CR-01 | P0 | 第 21–160 關重排，讓不用道具也能過關 | 待修（先回答方案） |
| CR-02 | P1 | 體力「勝利返還」：文案和代碼二選一對齊 | 待用戶決定 |
| CR-03 | P1 | 上架版移除「關卡測試（獨立沙盒）」入口 | 待修 |
| CR-04 | P1 | 分享功能 | 待修 |
| CR-05 | P1 | 引導評論 | 待修 |
| CR-06 | P1 | 第一批 7 種語言 | 待修 |
| CR-07 | P1 | 變現：去廣告商品、獎勵廣告點位、道具的免費來源 | 待修 |
| CR-08 | P1 | 設定加「震動」「減少閃光」 | 待修 |
| CR-09 | P1 | 英文道具按鈕和導覽文字截斷 | 待修 |
| CR-10 | P2 | 失敗彈窗說明原因並提供「救一局」 | 待修 |
| CR-11 | P2 | `PlayerJournal` 補欄位型別驗證 | 待修 |
| CR-12 | P2 | 重跑 `pnpm run build` | 待修 |

## CR-00 補齊策劃文件

- 證據：`INTAKE.md` 第一節清點表。
- 要求：照 `INTAKE.md` 第二節，在 `apps/cozy-days/design/` 補 `GDD.md`、`NUMBERS.md`、`LEVELS.md`、`ORIGINAL-MAP.md`、`INNOVATION.md`、`ART-SPEC.md`、`SELF-REVIEW.md`，並說明生圖為什麼沒有用 gameartstyle.loopyhop.com 的提示詞。
- 驗收方法：Claude 逐份讀，並按 `GDD.md` 重寫 `TEST-CASES-claude.md`。

## CR-01 第 21–160 關不用道具過不了（P0）

- 證據：
  - `qa/evidence/kernel-cases.json` TC-LVL-03：貪心機器人 160 關只過 21 關（1–20 + 51）。
  - `qa/evidence/solver-no-tools.json`：beam search 第 21、22、30、60、100、160 關全部失敗。
  - `qa/evidence/solver-expanded.json`：加開第 3 個需求箱和 7 格暫存欄，第 21、30、60 關仍失敗。
  - `qa/evidence/m-stage-021-start.jpg`、`m-stage-021-end.jpg`：Claude 在真實構建版親自玩第 21 關，收 10 次後暫存欄滿，36 個需求只完成 2 個。
- 原因：`src/campaign.js` 的 `openingCounts` 只有 20 個數字，`balanceStage` 對第 21 關以後回傳原始排布（不做「兩類一波、當前需求在上」的重排）；README 也寫了「後續關卡暫沿用現有配置」。
- 要求：
  1. 第 21–160 關每一關都要有「不用道具可解」的排布，並用求解器證明（可直接用 `qa/tools/solver.mjs`）。
  2. 難度要逐步上升，不能像現在從「零決策」（第 1–20 關暫存欄峰值都是 0）直接跳到「不可能」。建議做法：從第 6 關起讓部分需要的物品壓在一兩層下面，暫存欄峰值隨關卡從 1 逐步升到 3–4；緩衝關降低。
  3. 道具只能「省時間」或「救一局」，不能是「不用就過不了」（casual 經濟模型規則）。
- 驗收方法：`node qa/tools/kernel-cases.mjs` 的 TC-LVL-03 要 160/160；貪心和隨機的勝率差 ≥ 20 個百分點（TC-LVL-04）；每關暫存欄峰值寫進 `LEVELS.md`。
- 先回答：打算全部重排，還是先上 20 關、其餘鎖住？這要用戶拍板。

## CR-02 體力「勝利返還」不一致（P1，待用戶決定）

- 證據：`qa/evidence/kernel-cases.json` TC-ECO-03（重玩已三星關卡：勝前 4、勝後 4、返還 0）；文案 `examples/strings.js` `entry`：「新开一局用 1 体力，胜利返还」；代碼 `src/progress.js` completeRound 只在 `improved` 時返還。
- 二選一：
  - A：改代碼，每次勝利都返還 1 點（重玩已通過的關卡等於免費）。
  - B：改文案為「首次通關或星級提升時返還」（三語）。
- 驗收方法：TC-ECO-03 按選定方案改預期後通過。

## CR-03 移除玩家可見的沙盒入口（P1）

- 證據：`qa/evidence/m-settings-zh.jpg`、`m-settings-zhTW.jpg`（設定頁「關卡測試（獨立沙盒）」按鈕）；`index.html` 頁尾 `#lab-link`。
- 要求：上架構建不顯示這兩個入口（例如只在 `?lab=1` 或開發構建出現）；`lab.html` 不打包進商店版。
- 驗收方法：正式入口的設定頁和頁尾沒有沙盒入口；直接打開 `lab.html` 在商店構建中不存在。

## CR-04 分享（P1）

- 證據：`qa/evidence/browser-check.json` TC-FUN-02（結算頁按鈕只有下一關、重來、回首頁）；`metrics.sharesCaptured` 為空。
- 要求（skill 4.5 節）：結算頁和成就時刻有明顯的分享按鈕，叫起系統分享（Web Share API；不支援時下載圖片）；分享 1080×1350 成果卡（遊戲名、關卡、星級、用時、一個好笑的統計、商店連結，不含個人資料）；首頁或設定有「分享遊戲」。成果卡的視覺屬於美術，由 Codex 設計。
- 驗收方法：Claude 攔截 `navigator.share` 檢查傳入內容；把成果卡存到 `qa/evidence/` 打開看。

## CR-05 引導評論（P1）

- 證據：`qa/evidence/browser-check.json` TC-FUN-06（設定只有語言、音效、減少動效、沙盒）。
- 要求（skill 4.5 節）：成就時刻觸發（首次三星、過第 N 關、集齊一頁相冊）；不在失敗後、不在首次開啟、不打斷一局；同一玩家間隔至少 30 天；兩步法（先問喜不喜歡，喜歡才叫系統評分，不喜歡引到意見回饋）；設定常駐「給我們評分」；不用獎勵換評分、不畫星星。網頁版先做好觸發邏輯，接平台時接 `requestReview` 和 Play In-App Review。
- 驗收方法：Claude 用固定時鐘和存檔驗觸發條件；檢查設定項。

## CR-06 第一批 7 種語言（P1）

- 證據：`examples/strings.js` 每個鍵只有 [簡中, 繁中, 英文]。
- 要求：補 ar、ja、ko、de、fr、es（英文已有），阿拉伯語要由右至左、和數字混排正確；設定的語言選單用各語言自己的名字；每種語言截圖檢查溢出。
- 驗收方法：Claude 逐語言截全部畫面檢查。

## CR-07 變現（P1）

- 證據：`src/shop.js` 只有 4 個商品，沒有去廣告；`kernel-cases.json` TC-MON-05；`src/progress.js` 道具的唯一來源是 `grantReceipt`（購買）和一次性贈送。
- 要求：見 `MONETIZATION.md`。至少：去廣告一次性內購；獎勵廣告點位（看廣告換一次道具或體力）；道具的免費來源（每日、成就、活動）；恢復購買入口。
- 驗收方法：`MONETIZATION.md` 的核對表。

## CR-08 設定加震動與減少閃光（P1）

- 證據：`browser-check.json` TC-SET-TOGGLES。
- 要求：casual 手感規則要求音效、震動、減少閃光、減少動態四個開關；減少動態已有且有效（`motion-reduced-pick-and-win.jpg`）。
- 驗收方法：四個開關都在，且真的生效。

## CR-09 英文文字截斷（P1）

- 證據：`qa/evidence/m-stage-001-start.jpg`（道具按鈕「Fill reques t」「Retur 3」「Find a object」「Eras an object」）；`m-result-001.jpg`（導覽「Achievemen ts」）。
- 要求：所有語言的按鈕文字完整顯示、不在單字中間斷行；可以縮短英文文案（例如 Fill / Return / Find / Erase）或調整按鈕排版。
- 驗收方法：三語（之後七語）× 390×844 截圖沒有截斷。

## CR-10 失敗彈窗（P2）

- 證據：`m-stage-021-end.jpg`、第一輪 `m-result-001.jpg`（失敗時顯示的是道具操作說明）。
- 要求：說明為什麼輸（暫存欄滿）和下次怎麼避免；有餘額時提供「用移回／擴充暫存欄救一局」。
- 驗收方法：截圖檢查。

## CR-11 存檔欄位驗證（P2）

- 證據：`kernel-cases.json` TC-SAVE-02（ratings 為字串、道具餘額為負數都被接受）。
- 要求：`PlayerJournal` 構造時驗證 ratings、durations、credits、gifts 的型別和範圍；不合法時交給開機修復流程（C-03 已會備份並重開）。
- 驗收方法：TC-SAVE-02 全部 rejected。

## CR-12 重新構建

- 要求：合併 `claude/cozy-days-qa` 後跑 `pnpm install --frozen-lockfile --ignore-scripts && pnpm run build`，讓 `build/` 從源碼重新產生（包含 C-02，並取代 C-05 的手改）。
- 驗收方法：Claude 重跑 `verify-fixes.mjs` 和 `kernel-cases.mjs`。
