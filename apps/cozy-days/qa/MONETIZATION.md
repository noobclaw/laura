# MONETIZATION：內購、廣告、定價、Steam（第 18 步）

- 日期：2026-11-28；查證來源附在每條後面
- 結論：**不通過，未到可上架狀態**。網頁版沒有接任何支付或廣告；商品表不完整；道具的唯一來源是購買，而第 21 關以後不用道具過不了（AUDIT AUD-04），等於「不買就過不了」。

## 一、現況核對

| 項目 | 狀態 | 證據 |
|---|---|---|
| 網頁版不模擬購買成功 | 通過 | `m-shop.jpg`（「購買暫未開放」，按鈕禁用） |
| 價格取商店回傳，不寫死 | 通過 | `src/shop.js` `productPresentation`；TC-MON-04 |
| 恢復購買入口 | 缺 | 設定和商店都沒有 |
| 去廣告一次性內購 | 缺 | `src/shop.js` 只有 4 個商品 |
| 獎勵廣告點位 | 缺 | `toolDecision` 會回傳 `'ad'`，但沒有對應的廣告流程 |
| 插頁廣告規則 | 不適用 | 沒有插頁廣告 |
| 隨機獎勵公開機率 | 不適用 | 沒有隨機寶箱 |
| 不花錢也能通關 | **不通過** | AUD-04 |
| 道具的免費來源 | 缺 | 只有第 3 關起各送 1 次 |
| iOS StoreKit／Android Play Billing | 未做 | 沒有原生殼 |
| Steam | 未做 | 沒有桌面殼 |

## 二、品類頭部的內購價格（美區，查證日 2026-11-28）

| 遊戲 | 內購範圍 | 有沒有去廣告 | 來源 |
|---|---|---|---|
| Goods Triple Match: Sorting 3D（Guru） | $1.99–$12.99；Remove Ads $4.99；Beginner Pack $1.99；GOODS PASS $9.99 | 有，$4.99 | apppricinglab.com/iap/apple/6499306806 |
| Goods Store: 3D Sorting Games | 10 個商品，$0.99–$21.99 | — | apppricinglab.com/app/apple/6503113766 |
| Goods Sort – Triple Master 3D | 10 個商品，最低 $0.39；評分 4.9、11.8 萬則評價 | — | apppricinglab.com/app/apple/1658958534 |
| Match Factory!（Peak） | 金幣包、Beginner／Pro／Master／Mega／Ultra Bundle；主打無廣告 | 不做廣告 | apps.apple.com/us/app/match-factory/id6449094229 |

## 三、商品表（用戶 2026-11-28 已同意價格）

| 商品 ID | 內容 | 建議美區價格 | 依據 |
|---|---|---|---|
| `cozy.noads` | 去插頁廣告（一次性、非消耗型） | $4.99 | 和 Guru 的 Remove Ads 同價 |
| `cozy.toolbox.welcome` | 新手工具包（裝箱 2、移回 2、尋物 3、擦除 1） | $1.99 | 同類的 Beginner Pack $1.99 |
| `cozy.toolbox.helpers` | 小幫手工具包（5/5/5/3） | $4.99 | 同類中檔 |
| `cozy.space.bundle` | 空間包（需求箱 3、暫存欄 3） | $2.99 | 判斷，需要測試 |
| `cozy.energy.refill` | 體力 5 | $0.99 | 判斷，需要測試 |

**前提**：先完成 CR-01（關卡不用道具也能過），道具才是「省時間、救一局」，而不是「不買就過不了」。

## 四、要補的變現功能（CR-07）

1. 恢復購買（設定和商店都要有）。
2. 獎勵廣告：道具餘額 0 時「看廣告得 1 次」、體力 0 時「看廣告 +1」；每天上限。
3. 道具的免費來源：每日登入、成就、每日競速名次、相冊集齊一頁。
4. 插頁廣告（如果要做）：第 10 關以後、只在結算後、不打斷一局；買了去廣告就不出現。
5. 每個付費入口先出付費頁：列出內容、商店本地價、購買、恢復購買。

## 五、平台

| 平台 | 方案 | 待確認 |
|---|---|---|
| iOS | 用 WebView 殼打包（例如 Capacitor），內購走 StoreKit 插件；只發 iPhone 直屏 | 殼和插件的選型與版本，接之前先查官方文件 |
| Android | 同一個殼，走 Google Play Billing | 同上 |
| Steam | **Steam 可以做內購**：走 Steamworks 的 Microtransaction API，玩家用 Steam 錢包付款。**但必須有自己的購買伺服器**：遊戲把購買請求送到我們的伺服器，伺服器用 publisher key 呼叫 `ISteamMicroTxn/InitTxn` 發起交易，玩家在 Steam 疊加介面授權後，伺服器再呼叫 `FinalizeTxn` 完成，然後才發道具。伺服器可以用 CLAUDE.md 允許的 256btc.com。也可以選買斷制（例如 $4.99–$9.99，關掉體力和內購），不需要伺服器。兩種方案待用戶選定 | 桌面殼（Electron 或 Tauri）+ Steamworks SDK；選內購時另加伺服器端 |
| 網頁版 | 只做展示，保留標明「測試」的模擬 | — |

## 六、App Store Connect 與 Play Console 由 Claude 建立

用戶 2026-11-28 定：App 記錄、內購商品、價格、本地化文字、審核截圖由 Claude 在後台建立和填寫。用戶只做登入與驗證碼、協議、銀行稅務。開始建立之前，Claude 會在對話裡列出 bundle id、App 名稱、SKU、商品 ID、類型和價格，讓用戶確認一次。**目前還沒到建立的階段**：要先過 CR-01、CR-07，並做出原生殼。
