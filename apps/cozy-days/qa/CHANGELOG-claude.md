# CHANGELOG（Claude 的每一項改動）

分支：`claude/cozy-days-qa`（從 `codex/cozy-days-web` @ `ba26dc1` 切出）。Codex 請先合併這個分支再動手，避免衝突。

| # | 提交 | 改了什麼 | 為什麼 | 證據 | 回歸測試 |
|---|---|---|---|---|---|
| C-01 | `99bd0ab` | 新增 `.claude/skills/claude-codex-test/SKILL.md` | 用戶要求的 Claude 接手驗收 skill | — | — |
| C-02 | `3884773` | `src/progress.js` `#projectPower`：恢復起點晚於現在時，夾到現在並寫回記錄 | AUD-01：時鐘回撥後體力凍住最多 24 小時 | 修前：`qa/evidence/kernel-cases.json` 首輪 TC-CHEAT-01 refillIn 37800 秒、TC-CHEAT-02 refillIn 88200 秒；修後兩項都是 1800 秒 | `test/claude-qa.test.js`（2 項，修前失敗、修後通過）；全部測試 58/58 通過 |
| C-03 | `c204268` | `examples/play.js` 開機：存檔解析或驗證失敗時，把原存檔另存到 `sorting-playthrough-v1-damaged-<時間>`，從新存檔開始並彈出提示；`examples/strings.js` 新增 `saveRecovered`（三語） | AUD-02：壞檔讓玩家永遠進不了遊戲 | 修前：`qa/evidence/m-corrupt-save-boot.jpg`；修後：`qa/evidence/fix-corrupt-save-recovered.jpg`；`qa/tools/verify-fixes.mjs` 輸出 play=true、備份鍵存在、可進入關卡 | 瀏覽器腳本 `qa/tools/verify-fixes.mjs` |
| C-04 | `c204268` | `examples/play.js`：首次啟動按 `navigator.languages` 選 zh-TW／zh-CN／en，不支援的語言用英文（原本固定 zh-CN） | AUD-03 | 修前：`qa/evidence/m-home-first-launch.jpg`（en-US 瀏覽器顯示中文）；修後：`qa/evidence/fix-first-launch-en.jpg`；`verify-fixes.mjs` 輸出 en-US→en、zh-TW→zh-TW、zh-CN→zh-CN、ar-SA→en | 同上 |
| C-05 | `c204268` | `build/game-SWW4RGOU.js`：手動套上 C-03、C-04 的同等邏輯 | 這個環境不能安裝依賴，無法跑 `pnpm run build`；手改是為了能在瀏覽器實測 | 同 C-03、C-04 | **Codex 請重跑 `pnpm run build`**，會從源碼重新產生並覆蓋這個手改版本 |
| C-07 | `9416991` | `src/progress.js` completeRound：bonus 類入場（正常闖關）每次勝利都返還入場體力，不再只限首通或星級提升；`build/` 手改同一處 | AUD-05、用戶決定（每次贏都返還） | 修前：`kernel-cases.json` TC-ECO-03（重玩三星關卡勝利不返還） | `test/claude-qa.test.js` AUD-05 兩項（修前失敗 1 項）；全部測試 60/60 |
| C-06 | `2cba9f8` | 新增 `qa/` 全部文件、`qa/tools/` 驗收腳本、`qa/evidence/` 證據 | 驗收記錄 | — | — |

**注意**：C-02 只改了 `src/progress.js`，網頁版要等 Codex 重新構建後才會生效。目前的 `build/` 手改了 C-03、C-04、C-07。

## 怎麼重現

```sh
cd apps/cozy-days
node --test                                            # 58 項
node qa/tools/kernel-cases.mjs --seeds 3 --random 5 > /tmp/k.json   # 約 10 分鐘
node qa/tools/solver.mjs 21 30 60 --beam 6 --branch 10
python3 -m http.server 18771 --bind 127.0.0.1 &
node qa/tools/browser-check.mjs     # 需要 Playwright 和 Chrome
node qa/tools/browser-check-2.mjs
node qa/tools/verify-fixes.mjs
node qa/tools/record-motion.mjs [--reduced]
```
