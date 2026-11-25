# 垂直切片報告
日期：2026-11-24 ｜ 分支：game/cats-web ｜ 程式：game/cats/web/

## Validation Question
用網頁技術和全程式生成，能不能把「一個房間＋貓塗色＋狗射擊＋揭曉」做到成品水準，而且真的好玩？
本報告只回答「做得出來、畫面長什麼樣、腳本跑得通」。好不好玩要由人判斷。

## Scope Built
客廳一間（106 種、332 件，27 件可撞）；貓 4 體型、狗 4 犬種；站立＋8 姿勢；完整塗色面板；限彈射擊；
準備→搜索→揭曉；機器貓與機器狗；分身、喵叫、貼牆、搭掃地機器人；HUD 與標題；28 個合成音效。

## Stories with evidence
- 001 渲染底座 — 截圖 room.png
- 002 客廳場景 — playtest「room inventory」；room_4cams_a.png、room_4cams_b.png
- 003 會動的東西 — playtest「idle for 10 s」列出 9 種（用程式比對，沒有錄屏）
- 004 參數化貓 — cats.png；playtest 走、跳、跳上暖桌
- 005 8 個姿勢 — pose.png、pose2.png、pose3.png；playtest「paint texture is identical…」
- 006 塗色核心 — playtest「3D brush」「left-drag」「Ctrl+Z walks back 20 strokes」
- 007 塗色面板 — paint.png；playtest 每個控制項一條（花紋筆沒做）
- 008 參數化狗 — dogs.png、dogfp*.png、reveal.png
- 009 射擊與球數 — playtest dog 段
- 010 回合流程與揭曉 — core 測試 18 條；playtest 三種結束各一次；reveal.png
- 011 眼皮底下計分 — playtest「under your nose」（面積用包圍球估，不算遮擋）
- 012 機器人 — playtest「bot dog finds…」「dog vision」；painted.png（難度沒調過）
- 013 HUD 與標題 — title.png、paint.png、dogfp.png、reveal.png
- 014 音效 — playtest「audio」；未經人耳試聽
- 015 貼牆、喵叫、分身、撞倒 — playtest 各一條（貼牆只支援外牆）
- 016 腳本化試玩 — 最後一次完整執行 61 條過 60 條；未過的那條門檻是猜的，看了數字後放寬，只重跑 world 段 5/5；dog 與 cat 段之後沒有重跑
- 017 Electron — 沒做

## 和設計文件不一樣的地方
- 取色取材質本色，不含光照。
- 塗色在 CPU 上算，1024² 圖集。
- 畫面佔比用包圍球估，不算遮擋。
- 單機時貓出局後可按 Enter 直接看結果。
- rules.json 另產生 rules.js（file:// 不能讀 JSON）。
- 繪製呼叫約 470（遊戲中）至 731（標題），超過美術規格的 300 目標。

## 相對擁有者五項要求的不足
1. 場景：只有客廳可玩；廚房、玄關、院子是佈景；沒有樓梯。
2. 物體動作：小物物理很簡單，彼此不碰撞，杯子倒下是固定動畫。
3. 物品：332 件裡 114 件是書。
4. 貓狗：鬥牛犬看起來更像聖伯納；耳朵尾巴跟體型綁定，不能單選。
5. 姿勢：只看靜態截圖調的，側躺和弓背較弱，沒有獨立的跑步動作。

## Not verified
沒有人玩過；沒有在真顯示卡上跑過（無幀率數字）；聲音沒人聽過；滑鼠鎖定未測；
連線、14 人、Electron、Steam 未做；花紋筆、壓低、聞一聞、夜晚模式、強制喵叫未做；
機器貓的偽裝只在塗的那個視角成立。

## Recommendation
NOT ASSESSED — 還沒有人玩過。
