# 貓（躲的一方）

標記同 round-flow.md。

## Summary

第三人稱。開局全白。移動、跳、貼牆、擺姿勢、塗色、喵叫、放分身。

## 體型【我們定】

四種起手體型，碰撞體積不同，各有利弊。開局前選。

| 體型 | 特徵 | 適合偽裝成 | 弱點 |
|---|---|---|---|
| 圓滾滾 | 球一樣的身體，短尾 | 靠墊、坐墊、鍋、西瓜 | 塞不進窄縫 |
| 修長 | 長身體長尾 | 書脊、門框邊、抱枕卷 | 伸展後輪廓明顯 |
| 長毛 | 輪廓蓬鬆，尾巴像撢子 | 毛毯、地毯、盆栽 | 體積最大 |
| 短腿 | 矮，貼地 | 拖鞋、矮櫃底、玩具 | 跳得低 |

耳朵（立耳／摺耳）、尾巴（長／短／捲）可另選，只影響外觀輪廓。

## 移動

| 操作 | 鍵 | 來源 |
|---|---|---|
| 移動 | WASD | 原作 |
| 跳 | Space | 原作 |
| 壓低 | Ctrl | 原作 |
| 貼牆 | 朝牆跳即貼住；Space 上、Ctrl 下、Shift 放開 | 原作 |
| 奔跑 | 不做獨立衝刺鍵（原作來源互相矛盾，取簡單的） | 我們定 |

數值【我們定】：走 2.2 m/s，跳高 1.1 m（短腿 0.8），貼牆移動 1.0 m/s。貓能跳上桌子、櫃子、貓爬架。

## 姿勢

按住 R 開姿勢輪，選一個；選完可拖曳固定朝向【操作照原作】。原作發售時 8 種【原作】，名單查不到，以下是我們自己的 8 種：

| # | 姿勢 | 輪廓像什麼 |
|---|---|---|
| 1 | 母雞蹲 | 一條吐司、靠墊 |
| 2 | 坐 | 花瓶、招財貓 |
| 3 | 伸懶腰 | 斜坡、書擋 |
| 4 | 側躺 | 長抱枕 |
| 5 | 蜷成一圈 | 甜甜圈、坐墊 |
| 6 | 翻肚 | 攤開的布 |
| 7 | 後腳站立 | 瓶子、檯燈 |
| 8 | 弓背 | 拱橋、提籃 |

換姿勢不掉漆（見 painting.md）。擺好姿勢後按右鍵鎖定視角【原作】。

靜止時的小動作：呼吸、眨眼只在自己畫面播放；**在別人畫面上，擺了姿勢的貓完全靜止**，否則永遠藏不住【我們定】。尾巴甩動、耳朵抖動只在沒擺姿勢時出現。

## 喵叫（原作的口哨）

- 按 1 喵一聲，附近的狗聽得到方向【原作：口哨吸引附近的鬼】。
- 房主可開「強制喵叫」：每隔一段時間所有貓自動叫，間隔可調，最短 5 秒；手動叫會重置倒數【原作】。預設關，開啟時預設 45 秒【原作指南舉例值】。
- 可聽範圍 12 公尺，隔牆衰減一半【我們定】。

## 分身

- Q 放一個分身，複製當下的塗裝和姿勢；X 全部收回【原作】。
- 最多本體＋2 個；每個冷卻 30 秒【原作】。
- **分身被打中，本體也出局**【原作】。所以分身是賭注，不是擋箭牌。

## 撞倒東西【我們定，我們自己的機制】

貓碰到標記為「可撞」的小物會把它推動或撞倒，發出聲音，狗聽得到。被撞倒的東西留在原地，是線索也可以是誘餌。

## Edge Cases

- 貼牆時擺姿勢：允許，姿勢朝向以牆面法線為準。
- 在會動的物件上（掃地機器人、轉盤）擺姿勢：貓跟著動，算靜止（速度相對於腳下物件計算）。
- 分身放在會動的物件上：跟著動。
- 被打中的瞬間正在放分身：分身不生成。

## Acceptance Criteria

- [ ] 四種體型在同一場景並排截圖，輪廓一眼分得出。
- [ ] 8 個姿勢逐一截圖，塗裝在切換後位置不變。
- [ ] 腳本：朝牆跳→貼住→上爬 1 m→放開，狀態正確。
- [ ] 分身被打中時本體出局。
- [ ] 在另一個視角觀察擺好姿勢的貓，連續 60 幀像素差為 0（不含場景動態）。

## Collision rules (2026-11-26, owner bug reports)

- Cardboard boxes, potted plants, garden bushes and tree trunks are solid: a cat cannot walk into them.
- Climbing over the top of a wall is only allowed where there is a ceiling above with room for the body; no climbing into the roof space.
- Last line of defence: every frame, a body that ends up inside a solid, above the ceiling or outside the house goes back to the last place it was fine.
- Verified by `web/tools/containcheck.py` (random walks + a climb on every tall wall face): PASS with the guard on; with the guard off, cats still get above the ceiling, so the guard is what holds this today.

## Owner feedback 2026-11-26 (round 2)

- **Embedding limit:** at most a third of the body may go into a wall or an object. Past that, the body glows red at once with the message 「身體嵌進去超過 1/3，這樣不允許」. Staying in for 3 s exposes it, as before.
  - Measured from the posed body's own vertices: for each solid they touch, how far the body would have to move out along the cheapest axis, as a share of the body's size on that axis. A pillar or shelf cutting through the body counts as about a half.
  - Walking and climbing stop short of the line (0.8 × 1/3), so the player is not pushed into red by the game itself.
- **Climbing stance:** on a wall that is at least as tall as the body, a standing or crouching cat climbs belly to the wall, head up. The body is pulled up, a little flatter and wider, with arms reaching up and feet spread. It no longer stands out of the wall as if the wall were a floor. On thin beams and low ledges the old orientation stays.
- **Bodies:** flatter (depth 0.5 of width), 14 % wider and taller, arms and feet about 1.3–1.45× bigger.
- **Climbable surfaces:** the original lets you stick to walls *and objects* (evidence B: Game8, atwiki — see original-evidence.md), so we keep both.
