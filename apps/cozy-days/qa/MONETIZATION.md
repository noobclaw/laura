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

## 三、商品表與定價核對（用戶 2026-11-28 已同意，要求「蘋果定價要合理」）

競品美區價格（查證日 2026-11-28，apppricinglab.com 對應 App Store 美區）：

| 類別 | Goods Triple Match（Guru） | Goods Store: 3D Sorting | Goods Sort – Triple Master 3D |
|---|---|---|---|
| 去廣告 | Remove Ads $4.99 | NoAds $7.99 | 沒有 |
| 新手包 | Beginner Pack $1.99 | Beginner Bundle $1.99 | — |
| 小額 | XS Coin Pack $1.99、Piggy Bank $1.99 | Daily Bundle $0.99 | Large PacK $0.99、Large Pack2 $0.39 |
| 中檔 | Small Pack $5.99、S Coin Pack $4.99 | Endless Bundle $2.99、New Milestone $3.99 | Master Pack $2.99、Bag3 $2.99、Small Pack $6.99 |
| 高檔 | Master Pack $12.99、GOODS PASS $9.99 | Master Bundle $9.99、Lucky Bag $9.99、Mega Bundle $21.99 | Festival $9.99、Gold 5500 $9.99、Basic Bundle $12.99 |

我們的商品：

| 商品 ID | 類型 | 內容 | 美區價格 | 和競品比 | 結論 |
|---|---|---|---|---|---|
| `cozy.noads` | 非消耗型 | 去插頁廣告 | $4.99 | 和 Guru 同價，低於 Goods Store 的 $7.99 | 合理 |
| `cozy.toolbox.welcome` | 消耗型 | 新手工具包（裝箱 2、移回 2、尋物 3、擦除 1） | $1.99 | 兩家新手包都是 $1.99 | 合理；建議每個玩家限購 1 次（同類新手包的通行做法），見 CR-14 |
| `cozy.toolbox.helpers` | 消耗型 | 小幫手工具包（5/5/5/3） | $4.99 | 中檔 $2.99–$6.99 之間 | 合理 |
| `cozy.space.bundle` | 消耗型 | 空間包（需求箱 3、暫存欄 3） | $2.99 | 同 Endless Bundle、Bag3 | 合理 |
| `cozy.energy.refill` | 消耗型 | 體力 5 | $0.99 | 同 Daily Bundle、Large PacK | 合理 |

- 總結：5 個價格都落在同類區間內，取的是區間中間或偏低（新遊戲沒有口碑，不宜定高）。
- 缺口：同類都有 $9.99 以上的大包，給願意多花的玩家。建議上線後看數據再加，不在首版。
- 其他地區：用 App Store Connect 的自動等價（以美區為基準），沙烏地、阿聯酋等地由 Apple 換算成當地價格點。
- **前提**：道具要先變成「省時間、救一局」（CR-01 完成），否則「不買就過不了」，價格再合理也會被差評。

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
| Steam | **用戶 2026-11-28 決定：買斷制**。Steam 版關掉體力和內購、不需要伺服器（CR-13）。售價待定，上架前對照 Steam 上同類休閒遊戲再定。以下是當時的比較，留作記錄：Steam 可以做內購：走 Steamworks 的 Microtransaction API，玩家用 Steam 錢包付款。**但必須有自己的購買伺服器**：遊戲把購買請求送到我們的伺服器，伺服器用 publisher key 呼叫 `ISteamMicroTxn/InitTxn` 發起交易，玩家在 Steam 疊加介面授權後，伺服器再呼叫 `FinalizeTxn` 完成，然後才發道具。伺服器可以用 CLAUDE.md 允許的 256btc.com。也可以選買斷制（例如 $4.99–$9.99，關掉體力和內購），不需要伺服器。兩種方案待用戶選定 | 桌面殼（Electron 或 Tauri）+ Steamworks SDK；選內購時另加伺服器端 |
| 網頁版 | 只做展示，保留標明「測試」的模擬 | — |

## 六、App Store Connect 建立結果（Claude，2026-11-28）

| 項目 | 結果 |
|---|---|
| App ID（開發者後台） | `com.laura.cozydays`，In-App Purchase 能力已開。另有一個先建好、後因用戶改包名規則而不用的 `com.noobclaw.cozydays`，沒有綁任何 App，先留著（刪除不可逆） |
| App 記錄 | 名稱 **Cozy Days: Sort & Tidy Up**（「Cozy Days」已被他人佔用；按 GEO 加玩法詞），Apple ID 6840346021，SKU `cozydays-ios`，主要語言 English (U.S.)，狀態 1.0 Prepare for Submission |
| 內購 | 5 個，全部「Prepare for Submission」：`cozy.noads` 非消耗型 $4.99（Remove Ads）、`cozy.toolbox.welcome` 消耗型 $1.99（Welcome Toolbox）、`cozy.toolbox.helpers` 消耗型 $4.99（Helpful Bundle）、`cozy.space.bundle` 消耗型 $2.99（More Room Bundle）、`cozy.energy.refill` 消耗型 $0.99（Energy Refill） |
| 每個內購的設定 | 美國基準價，其他 173 個地區用 Apple 自動換算；可售地區 174/175，**排除中國大陸**（遊戲在中國大陸需要版號）；英文、簡中、繁中三語名稱和描述，名稱與遊戲字串表一致 |
| 還沒做 | 每個內購的審核截圖和審核備註（要等 iOS 安裝包）；App 本身的價格（免費）與可售地區；年齡分級；隱私標籤；送審（等 CR-01 關卡重排、廣告接入、原生殼完成，並先問用戶） |
| 注意 | `cozy.noads` 對應的廣告還沒做，送審前必須先有廣告，否則這個商品會被拒 |
