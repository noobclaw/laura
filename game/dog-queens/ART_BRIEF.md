# 招牌柴犬插畫需求（給 AI 繪圖用）

2026-11-24。用於 Lantern Garden 大更新（狗狗主題）。用戶用 AI 繪圖生成，生成後放到電腦桌面的一個資料夾，告訴我資料夾名，我負責去背、裁切、壓縮、接入遊戲。

## 1. 角色設定（每張圖都要一致）

- **名字（暫定）**：Mochi
- **品種**：柴犬幼犬，圓滾滾的身材，頭大身小（大約 1:1.2）
- **毛色**：暖橘色背部，奶油白的臉頰、胸口、肚子和四隻腳掌（柴犬經典「裏白」）
- **辨識配件**：脖子上一條**薄荷綠格紋小領巾**（所有圖都要有，這是和其他狗區分的標誌）
- **眼睛**：大而圓的深棕色眼睛，有高光；眉毛位置有兩個淡色小圓點（柴犬「麻呂眉」）
- **尾巴**：捲成一圈翹在背上
- **風格**：高品質 3D 渲染，柔和的毛髮質感，像動畫電影角色；柔光、乾淨、可愛
- **不要**：黑白配色、貓、樂器（小號、喇叭）、小魚、文字、浮水印

## 2. 技術要求

- 背景：**純白色、無陰影、無地面**（我來去背）。場景插畫（第 6 節）除外。
- 解析度：Midjourney 用預設最高；最終輸出至少 1024 像素寬。
- 檔案：PNG 或高品質 JPG，按下面的編號命名，例如 `B3_celebrate.png`。
- 每個姿勢可以多出幾張，挑最好的一張；拿不準就都給我，我來挑。
- **授權**：請確認你用的繪圖工具允許商用（Midjourney 付費方案允許；即夢等其他工具請看它的條款）。

## 3. 保持角色一致的做法（Midjourney）

1. 先生成 **A1 角色設定圖**，挑出最滿意的一張。
2. 之後每張提示詞的結尾加上 `--cref <A1 的圖片網址> --cw 100`，讓同一隻狗出現在所有圖裡。
3. 如果某個姿勢的臉跑掉了，把 `--cw` 降到 60 再試。

其他工具（即夢、GPT 圖像）：每次都把 A1 圖片作為參考圖上傳，再貼提示詞。

## 4. A 組：角色設定（先做這張）

**A1 角色設定圖**
```
character turnaround sheet of a chubby shiba inu puppy mascot, warm orange back fur, cream white cheeks chest belly and paws, big round dark brown eyes with sparkle highlights, two small pale dots above the eyes, curled tail over the back, small mint green gingham bandana around the neck, front view, three-quarter view, side view, back view, standing, high quality 3D render, soft fluffy fur, Pixar style, soft studio lighting, pure white background, no shadow, no text --ar 16:9 --style raw
```

## 5. B 組：全身姿勢（遊戲中的情緒反饋）

每張都用：`--ar 1:1`，加上 `--cref <A1> --cw 100`。共同結尾：
`, high quality 3D render, soft fluffy fur, Pixar style, soft lighting, full body, centered, pure white background, no shadow, no text`

| 編號 | 用途 | 提示詞前半段 |
| --- | --- | --- |
| B1 | 首頁待機 | `the same shiba inu puppy mascot sitting happily, tail wagging, gentle smile, looking at the viewer` |
| B2 | 新手教學 | `the same shiba inu puppy mascot waving one front paw hello, cheerful open mouth smile` |
| B3 | 過關慶祝 | `the same shiba inu puppy mascot jumping in the air with joy, all four paws spread, tongue out, eyes closed happily, a few colorful confetti pieces` |
| B4 | 大過關 / 完美 | `the same shiba inu puppy mascot proudly holding up a shiny golden bone trophy with both front paws, standing on hind legs, sparkles` |
| B5 | 放錯 | `the same shiba inu puppy mascot looking embarrassed, covering its eyes with one paw, small sweat drop, ears down` |
| B6 | 提示 | `the same shiba inu puppy mascot thinking, head tilted, one paw raised to its chin, curious eyes looking up` |
| B7 | 今日已完成 | `the same shiba inu puppy mascot sleeping curled up in a ball, peaceful face, tail wrapped around, small z letters not needed` |
| B8 | 生命用完 | `the same shiba inu puppy mascot sitting sadly, ears flat, big watery puppy eyes, cute pout` |
| B9 | 每日打卡 | `the same shiba inu puppy mascot happily carrying a small wrapped gift box in its mouth` |

## 6. C 組：棋盤上的棋子（最重要，每局都看到）

放在格子裡的狗頭，畫面很小，要**一眼看得清**。每張 `--ar 1:1`，加 `--cref`。共同結尾：
`, head only, front view, centered, simple clean shapes, bold readable silhouette, high quality 3D render, soft lighting, pure white background, no shadow, no text`

| 編號 | 用途 | 提示詞前半段 |
| --- | --- | --- |
| C1 | 放下的狗（預設） | `cute face of the same shiba inu puppy mascot with mint green bandana visible, happy smile, eyes open` |
| C2 | 過關時一起開心 | `cute face of the same shiba inu puppy mascot, eyes closed in a happy smile, tongue slightly out` |
| C3 | 衝突（兩隻相鄰） | `cute face of the same shiba inu puppy mascot, surprised wide eyes, small open mouth` |

## 7. D 組：道具和圖示

`--ar 1:1`，共同結尾：`, game item icon, high quality 3D render, glossy, soft lighting, centered, pure white background, no shadow, no text`

| 編號 | 用途 | 提示詞前半段 |
| --- | --- | --- |
| D1 | 生命 / 貨幣 | `a cute chunky dog bone, cream white color, slightly glossy` |
| D2 | 提示道具 | `a small round dog treat cookie shaped like a paw print, golden brown` |
| D3 | 自動放置道具 | `a small red dog ball with a white star on it` |
| D4 | 打卡獎勵 | `a small gift box with a paw print on the lid, mint green ribbon` |

## 8. E 組：App 圖示

**E1**（`--ar 1:1`，加 `--cref`）
```
app icon, the face of the same shiba inu puppy mascot peeking over the edge of a colorful grid of rounded pastel squares (pink, mint, sky blue, butter yellow), happy smile, mint green bandana, high quality 3D render, soft lighting, light sky blue background, centered, no text
```

## 9. F 組：相簿插畫（收集用，每張拆成 16 塊拼圖）

`--ar 3:4`，加 `--cref <A1> --cw 80`。共同結尾：
`, cozy storybook scene, high quality 3D render, soft warm lighting, rich detail, no text`

| 編號 | 場景 |
| --- | --- |
| F1 | `the same shiba inu puppy mascot napping in a sunny flower garden full of tulips` |
| F2 | `the same shiba inu puppy mascot playing in autumn leaves in a park, leaves flying` |
| F3 | `the same shiba inu puppy mascot building a small snowman, snowy backyard, red scarf added` |
| F4 | `the same shiba inu puppy mascot at the beach digging in the sand, waves, seashells` |
| F5 | `the same shiba inu puppy mascot having a picnic on a checkered blanket with sandwiches` |
| F6 | `the same shiba inu puppy mascot in a bubble bath, foam on its head, rubber duck` |

## 10. 優先順序

第一批先給我 **A1、C1、C2、C3、B1、B3**，就能做出可玩的新版本；其餘的可以之後陸續補。

## 11. 我會做的部分（不需要你出圖）

棋盤、格子顏色、規則圖示卡、按鈕、彈窗、骨頭生命條、打卡條、結算頁版面、動效、音效、去背和壓縮。
