# Architecture：貓躲狗找

## 分層

```
core/     純規則，不依賴 three.js，不碰 DOM。 apply(state, action) -> { state, events }
sim/      角色移動、碰撞、拋射物、可撞物。固定 60 Hz 步進。
net/      房主權威。客戶端送輸入與筆劃，房主回狀態與事件。
render/   three.js：場景建構、參數化貓狗、著色器、後處理。只讀狀態、播放事件。
paint/    每隻貓一張塗色貼圖；筆劃 -> 貼圖。
audio/    WebAudio 合成；訂閱事件。
ui/       HTML/CSS HUD 與選單；訂閱事件。
data/     rules.json、地圖定義、物件清單。數值不寫死在程式裡。
tools/    截圖腳本、腳本化試玩、離線音訊檢查。
```

規則：`core` 可以用 Node 直接跑測試；`render`、`audio`、`ui` 不直接改遊戲狀態，只發出輸入、只聽事件。

## 目錄

```
game/cats/
  web/            可直接用瀏覽器開的遊戲（index.html + src/ + vendor/）
  desktop/        Electron 外殼（之後）
  design/ docs/ production/   文件
```

## 決策記錄

- ADR-0001：網頁技術＋Electron 外殼
- ADR-0002：房主權威連線
- ADR-0003：塗色用物件空間筆刷＋筆劃同步

## 驗證方式

- `core`：Node 單元測試，CI 上跑。
- 畫面：無頭 Chrome 截圖（本機是軟體渲染，效能數字不可信，只看畫面對不對）。
- 玩法：腳本化試玩（移動→擺姿勢→塗→被打→揭曉），每次提交前跑。
- 聲音：OfflineAudioContext 算峰值、削波、靜音段；註明「未經人耳試聽」。
- 效能、多人連線、Electron 與 Steam：必須在擁有者的實機上驗，沒驗之前一律標「未驗證」。

## 已知的未驗證項

1. Electron 包裝後在 Windows／macOS 的實際幀率。
2. Steam 好友邀請與連線穿透（用哪個函式庫還沒選，見 ADR-0002）。
3. 14 人同場的流量與幀率。
