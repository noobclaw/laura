# ADR-0001：用網頁技術（three.js）製作，Electron 包成客戶端

## Status
Accepted（2026-11-24，擁有者指示停用 Unity）

## Context
先前用 Unity 做，製作端看不到自己的輸出：每次改動要等雲端打包十多分鐘，畫面品質長期不達標。同期公開的 Fable 5.2 高品質作品幾乎都是 three.js、全程式生成，並靠「開頁面→截圖→自檢→修改」的快速迴圈做出來。本工作環境有無頭 Chrome，可以做同樣的迴圈。

## Decision
- 渲染：three.js（WebGL2），版本固定並放在 `web/vendor`，不走 CDN。
- 美術與音效：全程式生成。
- 發行：Electron 外殼打包 Windows／macOS，上 Steam。
- 開發期直接用瀏覽器開 `web/index.html`。

## Alternatives Considered
1. 繼續 Unity：畫面上限更高，但看不到輸出的問題沒解。否決。
2. Godot：同樣需要編輯器與匯出流程，迴圈不比 Unity 快多少。否決。
3. WebGPU：效果更好，但相容性較差，Electron 內的支援情況未驗證。先不用。
4. Tauri 取代 Electron：包更小，但各平台用系統自帶的瀏覽器核心，WebGL 表現不一致。先不用。

## Consequences
- 好處：迭代快；同一份程式也能放網頁給人試玩；安裝包小。
- 壞處：效能上限低於原生引擎；防作弊較弱（客戶端程式可讀）——派對遊戲、好友房，可接受；Steam 整合要靠第三方橋接。
- 未驗證：Electron 版實機幀率；Steam 橋接函式庫的選擇與授權。

## Validation Criteria
- 垂直切片在擁有者的 Windows 電腦上以 1080p 跑到 60 fps。
- Electron 包能在 Windows 與 macOS 啟動並進入遊戲。
