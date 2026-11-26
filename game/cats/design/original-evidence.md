# 原版機制、操作、畫面：有出處的證據表

整理日：2026-11-25。只用公開資料（媒體報導、攻略站、開發者貼文、玩家討論、擁有者提供的截圖與筆記）。
沒有下載、反編譯或讀取任何外掛與修改器。

可信度：
- **A** 開發者本人的說法，或多家遊戲媒體轉述同一則官方更新
- **B** 兩個以上攻略站一致，或擁有者親自玩到／截圖
- **C** 只有一個來源，或來源之間有矛盾
- **？** 查不到

這份文件的規則是：**A、B 級照做；C 級照做但標記；？ 級由我們自己定，並寫明是自己定的。**

---

## 1. 回合流程與預設值

| 項目 | 內容 | 級 | 出處 |
|---|---|---|---|
| 階段 | 大廳 → 躲藏（獵人等待）→ 搜索 → 對答案 | B | game.watch.impress.co.jp/docs/kikaku/2118862.html；擁有者截圖 |
| 預設模式 | 増え鬼（感染） | B | volx.jp/meccha-chameleon-server/ |
| 預設獵人人數 | 1 | B | 同上 |
| 獵人等待時間（躲藏時間） | 預設 60 秒，房主可調 | B | 同上；擁有者貼的資料寫 30–60 秒、常見約 55 秒，量級一致 |
| 搜索時間 | 預設 300 秒 | B | volx |
| 對答案時間 | 預設 30 秒 | B | volx；擁有者截圖顯示 30 |
| 強制挑釁間隔 | 預設 0（關） | B | volx；擁有者截圖 |
| 向獵人顯示遺漏排行榜 | 預設開 | B | volx；擁有者截圖 |
| 設定入口 | 大廳裡走到開關前按 E | B | volx；players.com.ua 的彈數教學 |
| 人數 | 最多 24；穩定約 2–10（一說 1–13） | B | rapidgamer.net/chameleon-friendroom/；volx |
| 時間可設極大值 | 截圖出現 999999 | B | 擁有者截圖 |
| 獵人怎麼選 | 大廳地上「請站在這裡」＋「獵人抽選」倒數 | B | 擁有者截圖 |
| 提前結束 | Y（もうええよ）投票 | C | freespirited.website/meccha-chameleon-beginner-guide/ |

## 2. 躲的一方：操作

| 操作 | 按鍵 | 級 | 出處 |
|---|---|---|---|
| 移動 | W A S D | A | game8.jp/meccha-chameleon/821876 等 |
| 跑 | Shift＋移動 | B | Game8、freespirited、volx、擁有者；games.gg 說沒有跑步鍵（矛盾，採多數與擁有者） |
| 鏡頭 | 直接動滑鼠 | B | freespirited |
| 鎖定朝向移動 | 按住右鍵＋W A S D | B | freespirited；擁有者筆記「右鍵固定人物視角」 |
| 原地轉身 | 按住左鍵＋A/D | C | freespirited |
| 跳 | 空白鍵 | A | Game8 |
| 貼牆 | 朝牆或物體跳就貼住；空白鍵上、Ctrl 下、Shift 解除 | B | Game8；擁有者截圖底部提示 |
| 可貼在空中的牆面與物體，不必著地 | — | B | w.atwiki.jp/aniwotawiki/pages/61701.html |
| 蹲 | Ctrl | B | Game8 |
| 姿勢 | 按住 R 開圓盤；滑鼠移到姿勢上變藍，放開 R 即套用；左右鍵翻到第二頁 | B | allthings.how/?p=87876；volx |
| 姿勢朝向微調 | 選定後繼續拖曳 | C | Game8 |
| 解除姿勢 | 圓盤最下面的 × | B | volx；擁有者截圖 |
| 擺姿勢後移動會不會解除 | 查不到。沒有來源說會解除 | ？ | — |
| 分身 | Q 放、X 全清 | A | Game8、allthings |
| 挑釁（口哨） | 1 | B | Game8、擁有者 |
| 名牌 | 2 | B | 擁有者截圖 |
| 穿透描繪 | 3 | B | 擁有者截圖；用途見第 5 節 |
| 自由鏡頭 | 5；自由鏡頭中按 4 變自由移動 | B | volx、shi77-i.com |
| 躲著時就能用自由鏡頭看獵人 | — | B | game.watch、shi77 |
| 繪畫模式 | F | A | 多站 |
| 按讚 | G，對答案時用，每人每局一次 | C | freespirited、clip.dor.gg |
| 聊天／麥克風／語音 | T／V／B；麥克風預設靜音 | B | Game8 |

## 3. 繪畫模式

| 項目 | 內容 | 級 | 出處 |
|---|---|---|---|
| 塗 | 按住左鍵 | A | Game8 |
| 3D 吸管 | 長按空白鍵 | A | 開發者貼文 x.com/lemorion1224/status/2070071252698689963 |
| **3D 吸管吸到什麼** | **「正確的顏色」加上光澤等質感**；左上調色盤那個普通吸管吸出來會「完全不一樣」 | **A** | 同上（開發者原話大意） |
| 吸管也取材質與花紋 | 「直接取得背景的貼圖與色調」 | C | Game8 |
| 金屬度數值吸不到 | 玩家在開發者貼文下反映 | C | 同上貼文的回覆 |
| 筆刷大小 | 右鍵＋滑鼠左右 | B | meccha-chameleon.app/sousa、volx |
| 陰影開關 | V | B | 同上 |
| 轉鏡頭 | 滾輪鍵拖曳，或 Alt＋左鍵拖曳 | B | 同上 |
| 縮放 | 滾輪，或 Alt＋右鍵左右拖 | B | 同上 |
| 面板內容 | 色輪、兩條直條、新舊色預覽、sRGB Preview、RGB（0–1）、HSV、Hex 8 位、歷史下拉、金屬感、粗糙度 | B | 擁有者截圖 |
| 特殊顏料 | 有夜光顏料 | C | Game8 |
| 用姿勢／表情會退出繪畫模式 | — | C | Game8 |
| 塗的東西即時同步給所有人 | 開發者最花力氣的功能 | A | news.denfaminicogamer.jp/interview/260630w |

**對我們最重要的一條**：吸管要取的是材質本身的底色和質感，不是螢幕上那個已經被光照和調色處理過的顏色。
有人用 C++ 重做這個遊戲時遇到同一個問題，解法是把不受光的材質資料另外存一份，吸色時從那裡取
（daily.dev/posts/i-made-meccha-chameleon-in-c--rcmhndroc；原始碼 github.com/meemknight/cppChameleon，授權未查，只參考做法）。
貓和牆用同一套光照，底色和質感相同，貼上去自然就一樣。這直接對應擁有者說的「塗了也藏不住」。

同一個重做專案的另外兩個做法：
- 塗色定位：給角色套一張每個像素顏色都不同的編號貼圖，讀滑鼠底下的顏色就知道要塗貼圖的哪一點。
- 物理用現成的角色控制器處理任意地形和爬牆。

## 4. 獵人

| 項目 | 內容 | 級 | 出處 |
|---|---|---|---|
| 武器 | 霰彈槍／漆彈槍，左鍵開槍 | A | 多家媒體 |
| 射擊間隔 | 1.5 秒（1.9.0 加到 2.0，2.3.0 改回 1.5） | A | denfaminicogamer.jp/news/260630b；gamebrief.net |
| 子彈 | 2.3.0 以前無限；之後是房主可開關的「彈數限制」，1–99 發，建議 5 | A | 同上；players.com.ua；shi77 |
| 限彈規則 | 打空 −1、打中 +1、打逃跑中的人不扣、全員歸零躲方勝 | A | 多家媒體 |
| 視野角 | 105（2.6.0 由 100 調高） | C | clip.dor.gg/ja/blog/meccha-chameleon-game-modes-how-to-play |
| 人稱 | 右鍵切第一／第三人稱 | B | Game8、freespirited |
| 跳、蹲 | 空白鍵、Ctrl | B | Game8 |
| 能不能爬牆 | 能。「雙方都能沿牆和天花板移動」 | B | ja.wikipedia.org めっちゃカメレオン；freespirited；mobalytics 獵人攻略 |
| 躲藏階段獵人在哪 | 在等待區，看不到躲的人 | B | games.gg 獵人攻略；實況影片觀察 |
| 找人靠形狀 | 側面看厚度、凹凸、視差；色是其次 | B | game8.jp/meccha-chameleon/821878；mobalytics |

## 5. 鏡頭穿透

測試時玩家躲起來後鏡頭會被擋住，所以正式版加了「鏡頭穿透」和「自由鏡頭」。
級 A，出處：電ファミ開發者訪談。這就是按鍵 3 和 5 的由來。

## 6. 遺漏排行（Missed Spot Ranking，日文「見落としポイント」）

| 項目 | 內容 | 級 | 出處 |
|---|---|---|---|
| 觸發 | 在獵人視線內沒被認出來，就一直加分 | A | game.watch；gamerant.com/meccha-chameleon-missed-spot-ranking-points/ |
| 依據 | 距離和持續時間（1.2.0 加入） | B | allthings.how/meccha-chameleon-missed-spot-ranking-how-to-earn-more-points/ |
| 公式 | 官方沒公開 | ？ | 同上 |
| 正對時每次 45 分 | 擁有者親見 | B | 擁有者筆記 |
| 躲的人看到的是即時的；右下角跳數字 | — | B | 擁有者筆記；Steam 討論 |
| 獵人看到的排行 | 預設每 30 秒更新一次；間隔房主可調（有人設成 1 秒） | B | steamcommunity.com/app/4704690/discussions/0/562534659773420858/；gamerant；allthings |
| 可以對獵人隱藏 | 房主選項 | B | 同上；擁有者截圖 |
| 分身也算分 | — | B | allthings；Game8 |
| 獎勵 | 沒有實質獎勵 | C | allthings |

## 7. 分身

| 項目 | 內容 | 級 | 出處 |
|---|---|---|---|
| 數量 | 本體＋2 | A | 2.0.0 更新；allthings |
| 冷卻 | 每個 30 秒；畫面底部兩個綠色菱形，左是第一個、右是第二個 | B | allthings.how/meccha-chameleon-clones-how-to-duplicate-and-clear-your-hides/ |
| 被打中 | 本體一起出局 | A | 多站 |
| 自由鏡頭中不能按 X | 要先退出 | B | allthings |
| 不受重力 | 跳起來放，分身會浮在空中 | C | mecchachameleon.help |
| 可以走進自己的分身 | 不會出現重疊的紅色警告 | C | 同上 |
| 嵌進物體會有紅色警告 | — | C | 同上；先前資料另說位置會暴露 |
| 雙重模式 | 找到某人任何一個身體，他其餘分身立刻消失；變獵人後不能再清分身 | C | 擁有者貼的資料；neonlightsmedia |

## 8. 姿勢

- 發售時約 8 個；6 月 23 日加了一批（一說 10 個、一說 11 個），放在圓盤第二頁。級 B，allthings.how/?p=87876。
- 第二批的名字：蜷身（背對鏡頭把手腳藏起來）、後仰、斜身、單臂靠、深蹲、盤腿、單腳、T 字、劈腿、前彎。
- 擁有者截圖的第一頁：跪坐、仰躺、彎腰、舉臂、叉腰、雙手過頭、蜷縮、趴平。
- 開發者在預告片裡特地放了一個蜷起來扮成肉的畫面，目的是讓人想分享。級 A，電ファミ訪談。

## 9. 身體類型與尺寸

- 1.6.0：躲藏方尺寸可由選項更改。級 A，famitsu.com/article/202606/79055。
- 2.2.0：方塊體型加 1.4 倍、1.7 倍；修了 1.4 倍以上卡樓梯的問題。級 B，gamerch.com/mecha-chameleon/991166。
- 4.0.0：迷你（0.5 倍），房主允許才能用。級 A，denfaminicogamer.jp/news/2608203d。
- 10 月：章魚、肌肉、多邊形三種新體型。級 A，4gamer。
- 進場前選；截圖是兩種體型各 1.0／1.4／1.7。級 B，擁有者截圖。
- 實際身高：查不到。躲的一方被形容為「小個子」（ja.wikipedia）。從截圖估 1.0 倍約 1 公尺，這是我們的估計。

## 10. 模式

| 模式 | 規則 | 級 |
|---|---|---|
| 基本 | 隊伍固定，被打中出局可觀戰 | A |
| 感染 | 被打中變獵人，撐到最後的贏 | A |
| 雙重 | 全員先躲再全員找 | A；勝負條件兩說（最先找完／找到最多） C |
| 逆算小雞賽跑（2.4.0） | 先公開外觀再找，計分制；找到一人 500 分（原 1000） | B |
| 隊伍戰（10 月） | 兩隊輪流，個人分加總 | A；細節 ？ |

## 11. 濾鏡（只影響獵人）

- 恐怖：畫面變暗。像素：顆粒變粗、畫質變糙。是給熟手加難度的。級 B，gamewith.jp/gamedb/17059/articles/59202。
- 另有單色。級 B，擁有者截圖。
- 各有幾級：查不到，截圖是左右箭頭切換。

## 12. 地圖與畫面

- 原本只打算出一張大宅，後來加到四張。級 A，電ファミ訪談。
- 大宅：廚房、洗衣房、書庫、倉庫等很多房間，偏大、東西多。室內鄉村：比較小，獵人略佔優勢。大阪：小地圖。級 B，atwiki、redfreshet。
- 太大獵人找不完，太小變碰運氣；表面種類越多偽裝花樣越多。級 C，games.gg。
- 2.3.0 起部分地圖有隨機擺放的物件。級 A，Game*Spark。
- 畫面建議：動態模糊 0、幀率不設上限。級 B，meccha-chameleon.app、shi77。
- 美術方針：開發者沒談過。場景寫實、角色純白光滑無臉，是從截圖和影片看到的。
- 設計原則：不要複雜操作、不要複雜系統；用畫面溝通、少用文字。級 A，電ファミ訪談。

## 13. 製作

- 兩人、約兩個月（含沿用前作約四到五個月）、UE5、沒有廣告費和伺服器費。級 A，gamewith.jp/gamedb/17059/articles/59486 等。
- 做法：先用最低限度的系統和畫面做完整個遊戲，滿意才公開。級 B。
- 測試：隨機找人自由玩兩小時，允許錄影外流，這幫了宣傳。級 A。
- 有背景音樂，開發者自己做的。級 A。

## 14. 擁有者貼來的資料裡，查證後要注意的地方

| 說法 | 查證結果 |
|---|---|
| 準備時間 30–60 秒、約 55 秒 | 與 volx 的預設 60 秒相符。採 60，可調 |
| 沒有跑步鍵 | 與多數日文攻略和擁有者自己的經驗矛盾。採「Shift 跑」 |
| 排行每 30 秒才對獵人更新 | 查證屬實，而且間隔房主可調 |
| 分身 30 秒冷卻、自由鏡頭不能清 | 查證屬實 |
| C++ 重做的三個技術做法 | 查到來源，見第 3 節 |
| 吸管用空白鍵 | 屬實；是長按 |
| 搜索者子彈有限 | 只在開啟彈數限制時成立，預設情況查不到 |

## 15. 還是查不到的

擺姿勢時能否移動；遺漏分數的公式；各濾鏡的級數；實際公尺數；彈數限制預設開或關；穿透描繪除了鏡頭穿透外是否還影響筆刷。

## Video study 2026-11-26: Husky小隊 (661), youtube.com/watch?v=dfg6eg4YU84 (owner-supplied, 11:52)

Frames at about 1, 4, 8, 12, 20, 60, 110, 140, 160, 200, 240, 290, 340, 450, 505, 560, 600, 640 and 690 s were looked at (paused stills). Grade A for what is visible, but only for these maps.

- **Maps are enclosed interiors.** Seen: a cave set with a boat, a nursery (pink walls, crib), an indoor farm hall (painted barn mural, cows, hay), a beige maze of corridors and pillars, a garage with barrels, a living room with arched doorways, a laundromat, and a hall with blue diamond wallpaper and checker tiles. Every shot has walls and a ceiling, and no outdoor area is visible.
- **Ceilings are low and rooms are small.** Ceilings are about 1.4–1.6 × the figure's height. Rooms are a few body-lengths across, joined by doorways and corridors.
- **The floors are clean.** Furniture stands along the walls, with only a few props in the middle. Our floor is covered in mats, toys and books; the owner points to this as a difference.
- **Scale: the figures are person-sized next to real furniture** (crib, coat stands, sofa, chairs). Props are life-size.
- **Bodies are glossy, smooth vinyl** with strong highlights. Painted colours stay glossy (pink and yellow bodies at 4 s). Players draw faces on with black strokes.
- **Hiding:** posing as objects (lighthouse, vases/statues, a cow cut-out, wrapped round a door frame).
- **The hunter's gun** is a long gun covered in paint splatter, seen in first person. In free camera a hunter's shot shows as a rainbow streak that leaves colourful splats on the wall.
- **Painting UI:** a large colour wheel top-left, brightness/alpha bars, RGB/HSV sliders, a tool column below it.
