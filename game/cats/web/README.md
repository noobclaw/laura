# 貓躲狗找 — 網頁版垂直切片

日式老家裡的塗裝捉迷藏：貓把自己塗成周圍的樣子躲起來，狗拿網球發射器把貓找出來。
這個資料夾是可以直接開的遊戲，不需要安裝、不需要網路、沒有建置步驟。

## 怎麼開

用 Chrome 或 Edge 直接雙擊 `index.html`（`file://` 就能跑）。
全部美術（模型、貼圖、著色器）和音效都是程式在啟動時生成的，資料夾裡沒有任何圖片、模型或音檔。

## 操作

| 貓（躲） | |
|---|---|
| W A S D | 移動（以鏡頭方向為準） |
| 空白 | 跳；可以跳上暖桌、沙發、階梯櫃、貓爬架。朝牆跳會貼在牆上：W／S 上下、Shift 放開 |
| 按住 R | 姿勢輪（放開選定）；左下角的姿勢鈕也可以點 |
| F | 開關塗色。左鍵在身上塗、Alt+點 取場景顏色、滾輪或 `[` `]` 調筆刷、Ctrl+Z 復原 |
| 1 / Q / X | 喵叫／放分身／收回分身 |
| 右鍵拖曳、滾輪 | 轉視角、遠近（塗色中用 Shift+滾輪） |
| Enter | 準備好了（跳過準備階段） |

| 狗（找） | |
|---|---|
| W A S D | 移動 |
| 滑鼠、方向鍵 | 看四周（點一下畫面會鎖定滑鼠） |
| 左鍵、空白 | 發射網球：打空 −1、打中 +1、每 1.5 秒一發，球用完貓隊就贏 |
| V、右鍵 | 第一／第三人稱 |

## 資料夾

```
index.html
data/rules.json      所有數值（時間、速度、球數、筆刷範圍…）。改完跑 node tools/build-rules.js 產生 rules.js
src/core/rules.js    純規則：apply(state, action, rules) -> { state, events }，不碰畫面，可用 node 直接跑
src/render/          tex.js 程式貼圖、geo.js 幾何、post.js 渲染與後處理、critter.js 參數化貓狗與塗色、room.js 客廳
src/ui/ui.js         標題、HUD、塗色面板、姿勢輪、揭曉（HTML/CSS）
src/audio/audio.js   WebAudio 合成音效
src/game.js          把上面接起來：輸入、鏡頭、機器人、回合
tests/core.test.js   規則單元測試：node tests/core.test.js
tools/               shot.py 截圖、playtest.py 腳本化試玩（真的滑鼠鍵盤事件）
vendor/ fonts/       第三方檔案，見 ASSETS.md
```

## 驗證

```
node tests/core.test.js                 # 規則
python3 tools/playtest.py               # 腳本化試玩（需要 Chrome 與 playwright 的 Python 套件）
python3 tools/shot.py out.png "shot=title"   # 截圖；shot 可用 title room cats dogs poses paint painted dogfp reveal
```

本機截圖用的是軟體渲染（SwiftShader），所以這裡沒有任何幀率數字；效能要在實機上量。
音效只做過離線檢查（有聲音、不削波），沒有人實際聽過。

## 和設計文件不一樣的地方

- **取色取的是材質本色，不含光照**（painting.md 寫的是含光照）。原因：塗上去的漆會再被同一盞燈照一次，取含光照的顏色會被照兩次而變暗，反而融不進去。
- **塗色在 CPU 上做**（ADR-0003 寫的是在顯示卡上跑片段著色器）。同樣是物件空間的球形筆刷加位置圖，只是用 JS 逐紋素算；貼圖是 1024² 的圖集（文件寫 512²）。
- 花紋筆、壓低（Ctrl）、聞一聞、夜晚模式、強制喵叫、Electron 外殼與連線都還沒做。
- `rules.json` 另外產生一份 `rules.js`，因為 Chrome 在 `file://` 下不能 fetch 本機的 JSON。
