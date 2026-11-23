# 單機休閒遊戲完整製作方案

2026-11-22 · 線上版（可評論）：https://claude.ai/artifact/Um1vYBk1TfJzKeDcHPgdrk

## 結論摘要

做單機、離線可玩的輕量解謎遊戲，免費下載，靠道具內購和廣告賺錢，主攻美區和沙烏地、阿聯酋。先只做 1 款驗證數據，跑通後再擴到 12 款。

| 項目 | 決定 |
| --- | --- |
| 品類 | 輕量解謎：邏輯放置、方塊消除、麻將接龍、顏色分類等 |
| 市場 | 美區，加沙烏地和阿聯酋；不做華語區 |
| 收費 | 免費下載；道具內購、去廣告、皮膚；獎勵廣告 |
| 引擎 | Cocos 或 Unity，二選一，取決於團隊現有技能（見技術方案） |
| 美術 | 3D 用 Blender，2D 用 Affinity，都免費且沒有收入上限 |
| 素材 | 只用 CC0 和 CC-BY 素材當底稿，正式版全部改造；音樂外包原創 |
| 語言 | 首發 7 種：英、阿、日、韓、德、法、西 |
| 第 1 款 | 邏輯放置解謎（Queens 類規則，原創主題） |

本文最後一節是對這份方案的審計。審計發現 3 個重大缺口：沒有獲客方案、收入應以廣告為主而不是內購、12 款同時鋪開風險太高。請先讀那一節再做決定。

## 定位與市場

美區和沙烏地的免費榜前段是同一批輕量解謎遊戲，所以一款遊戲可以同時打兩個市場。

| 證據 | 內容 | 來源 |
| --- | --- | --- |
| 美區免費榜 | 前段是 Meowdoku、Block Out、Magic Sort、Block Blast 等解謎 | [Appfigures](https://app.appfigures.com/top-apps/ios-app-store/united-states/iphone/games) |
| 沙烏地免費榜 | 前段同樣是 Block Out、Magic Sort、Bus Fever、Block Blast | [LaunchShots](https://launchshots.app/showcase/sa/games) |
| 解謎類收入 | 2025 年從 77 億增至 88 億美元（只算內購） | [AppMagic 報告摘要](https://gamedevreports.substack.com/p/appmagic-mobile-games-monetization) |
| 中東市場 | 沙烏地、阿聯酋、埃及 2025 年合計 21.5 億美元；沙烏地佔 59.1%，阿聯酋 33.7% | [Game Growth Advisor](https://gamegrowthadvisor.com/blog/2026-05-28-mena-gaming-market-entry-guide-2026/) |
| 人均消費 | 阿聯酋 84.60 美元，沙烏地 54.89 美元，埃及 3.39 美元 | [PocketGamer.biz](https://www.pocketgamer.biz/mena-3-games-market-set-to-reach-28bn-by-2029/) |
| 小團隊可行 | Geometry Dash 一人開發；Plague Inc. 是一人加 3 個接案者；Toastie 兩人 | [Wikipedia](https://en.wikipedia.org/wiki/Geometry_Dash)、[Game Developer](https://gamedeveloper.com/business/how-i-plague-inc-i-topped-the-mobile-market) |

要注意的反面證據：

- 免費榜頭部是大公司。Meowdoku 的開發商據報有 200–300 人的研發團隊（單一來源）。
- 2025 年新上架超過 140 萬款 App，只有約 10% 得到關注（[AppMagic](https://investgame.net/news/pdf/2026-02-06-upload_reports_en_mobilemarkelandscape2026/)）。
- 沙烏地暢銷榜上的本地遊戲（Ludo、巴洛特紙牌）都是連網社交遊戲，不是單機。

## 產品線

順序按「榜單證據強、參考程式碼好、開發快」排列。每款的核心玩法、美術、音樂都不同。參考專案只讀演算法思路，程式碼全部自己重寫。

| 順序 | 遊戲 | 榜單證據 | 重寫時參考 |
| --- | --- | --- | --- |
| 1 | 邏輯放置（Queens 類） | Meowdoku 美區免費榜第 1 | [queens-generator](https://github.com/gitars/queens-generator) |
| 2 | 方塊消除 | Block Blast 美區、沙烏地均在榜 | [BlockBlast](https://github.com/sidhant947/BlockBlast) |
| 3 | 麻將接龍 | Vita Mahjong、Mahjong Blast 在榜 | [mah](https://github.com/ffalt/mah) |
| 4 | 顏色分類 | Magic Sort、Block Out 在榜 | [最佳解求解器](https://github.com/hkociemba/WaterBallSortPuzzleOptimalSolver) |
| 5 | 數獨 | 沙烏地桌遊榜有 Sudoku.com | [LibreSudoku](https://github.com/kaajjo/LibreSudoku) |
| 6 | 數織 | 經典謎題，這次沒查榜單 | [Nonogram](https://github.com/HandsomeOne/Nonogram) |
| 7 | 數字合成（2048 類） | 沙烏地桌遊榜有 Puff Up | [SwiftUI-2048](https://github.com/unixzii/SwiftUI-2048) |
| 8 | 離線雙人對戰合集 | 沙烏地街機榜有多款 | [c4](https://github.com/kenrick95/c4) |
| 9 | 螺絲解謎 | 這次沒查榜單 | [ScrewJam](https://github.com/sidhant947/ScrewJam) 的難度曲線 |
| 10 | 挖礦放置升級 | PicoCraft 休閒付費榜第 13 | 無 |
| 11 | 迷你卡牌組合 | Balatro 付費榜前 10 | [card-framework](https://github.com/chun92/card-framework) |
| 12 | 阿拉伯語文字解謎 | Last letter 下載 170 萬 | 無可用的開源專案，需要母語者 |

第 9–12 款的證據較弱，等前幾款有數據後再決定做不做。

讀完參考程式碼後的共同結論：每款都要先做兩樣東西，再做關卡。一是保證有解的生成器，二是按人的解題方式評難度的評分器。

## 收費設計

所有遊戲共用同一套收費底層，每款的主力道具不同。下表價格是設計建議，不是數據結論。

| 項目 | 定價（美元） | 類型 |
| --- | --- | --- |
| 首購禮包 | 0.99–1.99 | 一次性 |
| 去廣告 | 3.99–4.99 | 一次性 |
| 金幣包 | 1.99 / 4.99 / 9.99 / 19.99 | 消耗型 |
| 限時禮包 | 4.99–9.99，卡關或連續失敗時出現 | 消耗型 |
| 皮膚和主題包 | 1.99–4.99 | 一次性 |
| 獎勵廣告 | 免費，看一次換一個道具或接關 | 廣告 |

各類遊戲的主力道具：

- **邏輯、方塊、分類：** 接關、撤銷、提示一步、多一個空位。
- **麻將、2048、數獨：** 提示、洗牌、撤銷，另加牌面和背景皮膚。
- **雙人對戰合集：** 不賣消耗道具，改賣「解鎖其他小遊戲」。
- **文字解謎：** 揭示字母、刪掉錯誤字母、跳過。

設計依據：

1. 道具、接關、體力是休閒遊戲內購的三大基本組件（[GameRefinery](https://www.gamerefinery.com/casual-game-iap-monetization-trends)）。
2. 先送道具再賣：體驗過道具的玩家更可能購買；難關和簡單關要交替（[Unity 的 Match Triple 3D 分析](https://unity.com/blog/breaking-down-match-triple-3d)）。
3. 年收入 100 萬美元以下可申請 15% 抽成（[Apple 小型企業計畫](https://developer.apple.com/app-store/small-business-program/)）。

底線：不賣隨機抽獎；關卡不買道具也要能過。

## 技術方案

引擎在 Cocos 和 Unity 之間選，決定因素是團隊已經會哪一個。虛幻不用：它的安裝包太大，簡單 2D 遊戲也要約 60MB（[Unreal 論壇](https://forums.unrealengine.com/t/mobile-game-package-size-is-so-huge/33385)）。

> 提交到本倉庫時的補充：本倉庫已有 Flutter 殼工程（`shell/`）和 CI。Flutter 也是可行選項（參考專案 BlockBlast、ScrewJam 都是 Flutter），而且可以直接重用現有的內購、多語言和打包流程。引擎最終選哪個，見文末「待你決定的事」。

| 項目 | Cocos（COCOS 4） | Unity |
| --- | --- | --- |
| 擅長 | 輕量 2D 手機遊戲 | 2D、3D、跨平台 |
| 費用 | MIT 開源，免費（[官方公告](https://technode.global/prnasia/cocos-4-is-here-fully-open-source/)） | 收入或融資超過 20 萬美元要升級 Pro，每席每年 2,310 美元（[Unity](https://unity.com/runtime-fee)） |
| 語言 | TypeScript | C# |
| 安裝包 | 較小 | 較大 |
| 廣告變現 | 自己接第三方 SDK | 自家 LevelPlay 聚合平台 |
| 阿拉伯語由右至左 | 沒找到可靠資料，需要先測試 | UI Toolkit 已完整支援（[Unity 公告](https://discussions.unity.com/t/announcing-full-rtl-language-support/1544214)）；TextMeshPro 要裝 [RTLTMPro](https://github.com/pnarimani/rtltmpro) |
| 招人 | 人才較少 | 人才多 |

選擇規則：

1. 團隊已經會 Unity 和 C#，就用 Unity。
2. 團隊會 TypeScript 或前端，就用 Cocos，但第一週先做阿拉伯語介面測試。測試不通過就改用 Unity。

程式架構：

| 層 | 內容 |
| --- | --- |
| 共用底層 | 內購、金幣、廣告、存檔、設定、多語言、每日一題、數據統計 |
| 每款獨立 | 核心玩法、生成器和求解器、難度評分、介面、美術、音樂 |

所有介面文字放在外部語言檔，程式裡不寫死文字。

## 美術、素材庫與音樂

所有玩家看得到、聽得到的內容都要原創或經過改造。12 款的畫風各不相同。

製作工具：

| 用途 | 工具 | 價格 | 選它的理由 |
| --- | --- | --- | --- |
| 3D 建模和渲染 | Blender | 免費 | 沒有收入上限；Maya Indie 和 Houdini Indie 的收入上限都是 10 萬美元 |
| 2D 繪圖和介面 | Affinity | 免費，可商用（[TechRadar](https://www.techradar.com/pro/affinity-by-canva-2026-review)） | 向量、點陣、排版三合一 |
| 2D 骨骼動畫 | Spine Essential | 69 美元買斷（[官網](https://esotericsoftware.com/spine-purchase)） | 需要角色動畫時才買 |
| 體素風格 | MagicaVoxel | 免費 | 只在選方塊畫風時用 |

可用的開放素材庫：

| 素材庫 | 類型 | 授權 | 用途 |
| --- | --- | --- | --- |
| [Kenney](https://kenney.nl/support) | 2D、介面、3D、音效 | CC0 | 原型、介面起稿、音效 |
| [Quaternius](https://quaternius.com) | 低多邊形 3D 模型 | CC0 | 在 Blender 裡改造後渲染 |
| [Poly Haven](https://www.polyhaven.com/license) | 環境光、材質、模型 | CC0 | 渲染用的光照和材質 |
| [ambientCG](https://docs.ambientcg.com/license) | 材質 | CC0 | 做皮膚變化 |
| [game-icons.net](https://game-icons.net/about.html) | 圖示 | CC BY 3.0，要署名 | 圖示底稿 |
| [Freesound](https://www.freesound.org/help/faq) | 音效 | 每個不同 | 只用 CC0 和 CC BY |
| [Google Noto](https://fonts.google.com/noto/use) | 字型 | SIL OFL | 所有語言的字型 |

使用規則：

1. 只用 CC0 和 CC-BY。CC-BY-NC、CC-BY-SA、GPL 一律不用。
2. 每個外部素材都登記：名稱、作者、網址、授權、用在哪一款。
3. CC0 素材只當底稿，正式版要改造型、材質、配色。
4. 背景音樂每款外包原創，合約寫明買斷全部版權。
5. 參考程式碼裡的圖片、音效、關卡數據一律不帶走。

## 語言

語言按收入排序，不按人口排序，因為我們的收入來自成熟市場。2025 年手機遊戲收入前五是美國、中國、日本、韓國、德國（[AppMagic 報告摘要](https://gamedevreports.substack.com/p/appmagic-mobile-market-landscape)）。中文按要求不做。

| 批次 | 語言 | 主要市場 |
| --- | --- | --- |
| 第一批（首發） | 英文、阿拉伯語、日文、韓文、德文、法文、西班牙文 | 美英加澳、沙烏地和阿聯酋、日本、韓國、德國、法國、西班牙和拉美 |
| 第二批（首款跑通後） | 巴西葡萄牙文、義大利文、土耳其文、印尼文 | 巴西、義大利、土耳其、印尼 |
| 第三批（看數據） | 波蘭文、荷蘭文、泰文、越南文 | — |

從第一天就要做好的技術準備：

1. 阿拉伯語版整個介面左右鏡像，數字和英文夾在阿拉伯文中間時方向要正確。
2. 德文比英文長很多，按鈕和標題要預留空間或自動縮放。
3. 字型用 Noto 系列，授權文字檔要和字型檔一起打包。
4. 價格用商店自動換算的當地貨幣顯示。

解謎遊戲的文字量很少，所以多做幾種語言的成本不高。這是我的判斷，沒有報價數據。

## 合規

有 4 條規定會直接影響上架，必須從設計階段就遵守。我不是律師，授權問題有疑慮時請找律師確認。

| 規定 | 內容 | 我們的做法 |
| --- | --- | --- |
| App Store 4.3 垃圾應用 | 相同程式碼或素材、同一模板換皮的多款 App 會被拒（[Apple 開發者論壇](https://developer.apple.com/forums/thread/775805)） | 每款核心玩法、美術、音樂、商店頁面都不同 |
| App Store 3.1.1 抽獎 | 付費抽隨機道具要先公開機率（[PC Gamer](https://www.pcgamer.com/apple-now-requires-app-store-games-to-disclose-loot-box-odds/)） | 不做隨機抽獎 |
| GPL 程式碼 | GPL 和 App Store 條款被認為不相容，VLC 曾因此下架（[Engadget](https://www.engadget.com/2011-01-09-the-gpl-the-app-store-and-you.html)） | 只學思路，程式碼全部重寫 |
| 素材授權 | CC-BY-NC 不能商用；CC-BY-SA 和 GPL 要求衍生作品同授權 | 只用 CC0 和 CC-BY，逐項登記 |

參考專案的授權：queens-generator、mah、c4、card-framework 是 MIT；BlockBlast、ScrewJam、LibreSudoku 是 GPL-3.0。GPL 的三個專案要特別小心，見審計一節。

## 製作流程與團隊分工

每款遊戲按 7 步製作，先驗證好不好玩，再投入美術和音樂。這裡不給工期，因為我不知道團隊人數和經驗。

1. **玩法原型：** 用 Kenney 的素材和灰色方塊，驗證核心玩法。
2. **生成器、求解器、難度評分：** 保證每題有解、難度可控。
3. **關卡曲線和金幣經濟表。**
4. **美術：** 定畫風，用 Blender 或 Affinity 製作，介面另外設計。
5. **音樂和音效：** 音樂外包，音效用 CC0 素材二次加工。
6. **接內購和廣告，做在地化。**
7. **測試上線**（上線方式見審計一節的修正）。

最小團隊配置（我的建議）：

| 角色 | 人數 | 負責 |
| --- | --- | --- |
| 程式 | 1–2 | 引擎開發、演算法重寫、內購和廣告接入 |
| 美術 | 1 | 建模渲染、介面設計 |
| 企劃 | 1，可兼任 | 關卡曲線、經濟表、在地化、上架 |
| 音樂 | 外包 | 每款一套配樂和音效，買斷版權 |
| 翻譯 | 外包 | 阿拉伯語、日文、韓文等，要母語者校對 |

## 第 1 款規格概要：邏輯放置解謎

規則是經典謎題 Star Battle 的 1 星版：N×N 格子分成 N 個顏色區域，每行、每列、每區各放 1 個標記，標記之間不能相鄰（斜角也不行）。主題、名稱、美術全部原創。

| 項目 | 設計 |
| --- | --- |
| 操作 | 點一下打叉，點兩下放標記，滑動連續打叉 |
| 一局長度 | 1–3 分鐘；格子從 5×5 逐步升到 8×8 |
| 出題 | 程式自動生成，每題唯一解。我寫的原型出題器在 8×8 平均約 0.2 秒一題；9×9 太慢，需要改進演算法 |
| 難度 | 只接受「不用猜就能解」的題目，按推理步數評難度（做法參考 queens-generator） |
| 回訪動力 | 每日一題、計時和最佳紀錄、三星評分、連續天數 |
| 防挫折 | 違規即時標紅、撤銷、提示 |
| 主力道具 | 推理提示：告訴玩家下一步的理由，不直接給答案 |
| 畫風 | 扁平 2D，用 Affinity 製作 |

尚未完成的部分：金幣經濟表、關卡曲線、美術風格說明、音效清單。這四項要等引擎和團隊確定後再寫。

可玩的玩法原型在 `game/lantern/prototype/`，說明見 `game/lantern/PLAN.md`。

## 成功遊戲的要素（審計標準）

成功的休閒遊戲靠三根支柱：好玩的機制、成功的經濟模型、精美的美術。調研裡還反覆出現第四項：獲客。下面每項都寫成可以量化檢查的標準。

### 支柱一：好玩的機制

好不好玩用留存率衡量，不靠感覺。

| 指標 | 中位數 | 前 10% | Block Blast | 來源 |
| --- | --- | --- | --- | --- |
| 次日留存 | 約 22% | 約 40% | 51% | [GameAnalytics 2026 摘要](https://investgame.net/wp-content/uploads/2026/01/2026-01-20-Mobile_retention_benchmarks_2026.pdf)、[Gamigion](https://www.gamigion.com/?p=24040) |
| 7 日留存 | 約 4% | 約 12% | 32% | 同上 |
| 30 日留存 | 約 0.7% | 約 4% | 21% | 同上 |

- **現實的「好」標準是 35% / 15% / 5%。** 美區 iOS 解謎類的次日留存平均是 34%（[AppsFlyer 2026 Q3](https://www.appsflyer.com/?p=549948)）。
- **前 5–15 分鐘決定去留。** 玩家在這段時間沒感受到樂趣就會流失，教學要設計成「展示樂趣」。
- **簡單。** Block Blast 的設計原則是「少即是多」（[Gamesforum](https://www.globalgamesforum.com/news/how-casual-games-build-global-audiences-the-block-blast-approach)）。
- **專注和持續迭代。** Block Blast 做了超過 10,000 次 A/B 測試，而且只專注這一款，不擴充產品線（[PocketGamer.biz](https://www.pocketgamer.biz/block-blast-reaches-70m-daily-active-users-and-300m-monthly-active-users-worldwide)、[mobilegamer.biz](https://mobilegamer.biz/block-blast-maker-hungry-studio-a-b-tested-its-way-to-the-top-of-the-charts/)）。

### 支柱二：成功的經濟模型

經濟模型成立的標準只有一條：每個用戶帶來的收入要高於獲得他的成本。

- **用戶終身收入要高於安裝成本。** 比值低於 1.5 倍就是問題（[The Social Outline](https://thesocialoutline.com/blog/cpi-benchmarks-mobile-gaming)）。
- **頭部解謎遊戲主要靠廣告賺錢，不是內購。** Block Blast 的收入來自廣告，估計每天約 58.4 萬美元；它從一開局就有橫幅、插頁和獎勵廣告（[Udonis](https://www.blog.udonis.co/statistics/block-blast)、[MAF](https://maf.ad/en/blog/block-blast/)）。
- **廣告和內購要平衡，不互相損害。** 這是發行商 Supersonic 評估原型的標準之一（[Unity](https://unity.com/blog/mobile-gaming-shift-hyper-hybrid-casual)）。
- **廣告的位置和頻率要靠測試調出來，** 目標是在不傷留存的前提下讓每個用戶的收入最大。

### 支柱三：精美的美術

這一項我找到的量化證據最少，以下兩點有來源，其餘要靠實測。

- **美術平淡會拖累銷量。** 獨立遊戲 Redactem 的開發者把銷量不如預期歸因於「沒做行銷加上畫面平淡」（[IndieDB](https://www.IndieDB.com/features/redactem-an-indie-game-postmortem)）。
- **美術直接決定廣告素材的表現。** 廣告影片超過 5 秒還沒進入吸引人的玩法畫面，就留不住人（[Supersonic](https://supersonic.com/?p=80702)）。可檢查的標準是：用實機畫面做的廣告，點擊率和安裝成本有沒有優於同類。

### 第四項：獲客（調研補充）

三根支柱都做到，沒有人下載也沒用。

- **美區 iOS 解謎遊戲每次安裝的廣告成本是 9.48 美元，** 安卓是 4.81 美元（[AppsFlyer 2026 Q3](https://www.appsflyer.com/?p=549948)）。
- **原型階段就要測吸引力，數據不好就砍掉。** 這是休閒遊戲發行商的標準做法（[AppLovin](https://www.applovin.com/?p=24887)）。
- **先在便宜的市場試營運，不要一開始就上美國、日本、韓國。** 菲律賓的安裝成本只要 0.30–1 美元（[Game Growth Advisor](https://gamegrowthadvisor.com/blog/2025-12-16-mobile-soft-launch-complete-guide/)）。試營運的中位時長是 40 天（[PocketGamer.biz](https://www.pocketgamer.biz/feature/61904/sponsored-article-deltadna-retention/)）。
- **沒有行銷預算，下載量會趨近於零。** 獨立遊戲 Discover O 被 App Store 推薦一週後下載量驟降，幾個月後幾乎歸零（[Game Developer](https://gamedeveloper.com/business/post-mortem-discover-o---design-with-data)）。
- **混合休閒遊戲從概念到上線通常要 12–18 個月。** 這是 Supersonic 的說法（[Unity](https://unity.com/en/blog/mobile-gaming-shift-hyper-hybrid-casual)）。

### 同類遊戲前人的經驗

下表是 8 個做解謎遊戲成功的團隊或個人，以及他們自己或分析者總結的關鍵做法。

| 遊戲 | 關鍵做法 | 來源 |
| --- | --- | --- |
| Block Blast | 玩法極簡單；超過 10,000 次 A/B 測試；只專注一款；收入靠廣告 | [mobilegamer.biz](https://mobilegamer.biz/block-blast-maker-hungry-studio-a-b-tested-its-way-to-the-top-of-the-charts/) |
| Royal Match | 不靠創新，靠把核心玩法打磨到 100%；關卡設計成玩家常常只差 1–2 步失敗；不放廣告，只靠內購；廣告素材展示真實玩法 | [FoxData](https://foxdata.com/en/blogs/games-redefined-match3-with-flawless-execution-and-smart-ua/)、[Deconstructor of Fun](https://www.deconstructoroffun.com/blog/2021/3/21/royal-match-the-new-king-from-turkey) |
| Color Block Jam | 一開始就給有意義的挑戰，不慢慢加難度；畫面乾淨、介面優雅、有觸感回饋 | [Mobidictum](https://mobidictum.com/gybe-games-rollic-success-story-color-block-jam/)、[Gamigion](https://www.gamigion.com/?p=19452) |
| Vita Mahjong | 明確鎖定年長玩家：大牌面、操作簡單、可離線玩 | [App Store](https://apps.apple.com/us/app/-/id6468921495) |
| Sudoku.com（Easybrain） | 做經典謎題；做過無數次產品測試；在地化 18 種語言；每題唯一解，有提示 | [Easybrain](https://easybrain.com/news/sudoku-mobile-app-hits-the-web) |
| Wordle | 每天只有一題，只佔 3 分鐘；分享結果時不洩露答案 | [NPR](https://www.npr.org/2022/01/12/1071840091)、[Game Developer](https://gamedeveloper.com/gdc2022/josh-wardle-reflects-on-the-the-unconventional-road-to-wordle-s-success) |
| LinkedIn Queens | 每天一題，約 5 分鐘；連續天數、排行榜；題目由真人設計 | [Fortune](https://fortune.com/2024/05/02/linkedin-adds-games-like-wordle-microsoft/)、[Entrepreneur](https://www.entrepreneur.com/business-news/heres-how-hes-shaping-linkedins-puzzle-game) |
| Burny Games（Colorwood 系列） | 數據不好的專案盡早砍掉 | [PocketGamer.biz](https://www.pocketgamer.biz/what-burny-games-learned-about-building-puzzle-games-over-four-years-and-65-million-downloads/) |

這些經驗和「好玩、經濟模型、美術」三點有兩處不同，值得注意：

- **「好玩」在這個品類裡主要來自打磨，不是來自新機制。** Royal Match 和 Sudoku.com 都是拿現成玩法做到極致。
- **「精美」的意思是乾淨、清晰、手感好，不是華麗。** Color Block Jam 和 Vita Mahjong 的美術都是為「看得清、按得準」服務。

### 綜合後的 8 條審計標準

| # | 標準 | 對應 |
| --- | --- | --- |
| 1 | 核心玩法簡單，並打磨到位 | 好玩的機制 |
| 2 | 留存達標：次日 35%、7 日 15%、30 日 5% | 好玩的機制 |
| 3 | 有每日習慣機制：每日一題、連續天數 | 好玩的機制 |
| 4 | 有明確的目標玩家 | 前人經驗 |
| 5 | 經濟模型成立：用戶終身收入至少是安裝成本的 1.5 倍，收入來源和品類相符 | 成功的經濟模型 |
| 6 | 美術乾淨清晰、有手感回饋，能做出有效的廣告素材 | 精美的美術 |
| 7 | 有獲客方案和試營運計畫 | 調研補充 |
| 8 | 專注、用數據迭代、數據不好就早砍 | 前人經驗 |

## 方案審計

用 8 條標準審計，這份方案通過 1 條、部分通過 4 條、不通過 3 條。不通過的 3 條都會直接決定賺不賺錢，必須先修正。

| # | 標準 | 結果 | 審計發現 | 修正 |
| --- | --- | --- | --- | --- |
| 1 | 玩法簡單並打磨到位 | 部分通過 | 玩法選的都是已驗證的簡單規則，生成器和難度評分也有考慮。但方案沒有為「打磨」留時間，反而強調快速做 12 款 | 第 1 款上線後先迭代，不急著做第 2 款 |
| 2 | 留存達標 | 不通過 | 原方案只說「看留存」，沒有定目標數字，也沒有不達標時怎麼辦 | 目標定為次日 35%、7 日 15%、30 日 5%。次日留存低於中位數 22% 就重做或砍掉 |
| 3 | 每日習慣機制 | 通過 | 第 1 款已有每日一題、連續天數、最佳紀錄 | 可加上不洩露答案的結果分享 |
| 4 | 明確的目標玩家 | 不通過 | 方案只寫了國家，沒寫是什麼人。Vita Mahjong 鎖定年長者、Queens 鎖定上班族，我們沒有對應的定位 | 每款寫明目標玩家的年齡、場景、設備，美術和難度跟著調 |
| 5 | 經濟模型成立 | 不通過 | ① 方案以道具內購為主、只放獎勵廣告，但 Block Blast 這類遊戲的收入來自廣告。② 沒有任何收入預估。③ 美區 iOS 每次安裝成本 9.48 美元，方案沒有證明每個用戶能賺回這個數 | 改為廣告和內購並重：加入插頁廣告，用測試調頻率。上線前先算清單個用戶的預期收入 |
| 6 | 美術乾淨清晰有手感 | 部分通過 | 工具和素材授權都規劃了，但沒有任何一款的美術風格定稿，也沒提震動、動效、音效這些手感回饋 | 第 1 款先出美術風格稿和手感清單，再拍 3–5 支實機廣告素材測點擊率 |
| 7 | 獲客和試營運 | 部分通過 | 方案有商店頁面和多語言，但沒有廣告投放預算，而且直接首發美區。業界建議先避開美、日、韓 | 先在安裝成本低的英語市場試營運約 40 天，數據達標再上美區和中東。沒有投放預算就要找發行商 |
| 8 | 專注、數據迭代、早砍 | 部分通過 | 方案寫了「先做 1 款驗證」，但總目標仍是 12 款。Block Blast 的團隊明確表示不擴充產品線 | 把目標從「12 款」改成「做出 1 款留存達標的遊戲」；其餘當備選 |

### 方案本身的其他問題

- **我前後說法有矛盾。** 早先我判斷「小團隊不要碰免費解謎紅海」，後來按你選的收費方式，又把這個紅海列為第一方向。風險沒有消失：頭部對手是數百人的公司。
- **「開發快」沒有根據。** 業界說法是混合休閒遊戲從概念到上線要 12–18 個月。我沒有你們團隊的任何資訊，無法估工期。
- **引擎建議反覆過。** 我先建議 Flutter，再改 Cocos，最後說「看團隊」。如果收入改成以廣告為主，Unity 的自家廣告平台會更有優勢。Cocos 的阿拉伯語支援我沒驗證。
- **只研究了 iOS。** 所有榜單都是 App Store 的，Google Play 完全沒查。安卓的安裝成本大約是 iOS 的一半。
- **中東的假設沒驗證。** 沙烏地人均消費高，但那是全部遊戲類型的數字。單機解謎在當地的收入我沒有數據。
- **法律風險沒有完全排除。** 讀了 GPL 程式碼再重寫，如果結構太接近原作，仍可能被視為衍生作品。穩妥的做法是：讀程式碼的人只寫文字規格，由另一個人照規格實作。這點請找律師確認。
- **共用底層可能觸發 4.3 審核。** 蘋果會比對二進位檔。每款玩法不同可以降低風險，但我無法保證能過。
- **漏掉的合規項目：** 廣告 SDK 的追蹤授權彈窗、隱私政策、年齡分級、歐洲和中東的當地法規，方案都沒涵蓋。
- **數據品質有限。** 榜單是單日快照；收入數字是第三方模型估算；部分數字只來自搜尋摘要，我沒有打開原始報告逐頁核對。

### 審計後的修正版路線

1. 只做 1 款：邏輯放置解謎，先寫明目標玩家。
2. 做原型，拍廣告素材，用小預算測吸引力。
3. 在安裝成本低的市場試營運，看留存和單個用戶收入。
4. 留存達標：打磨、加廣告和內購、擴語言、上美區和中東。不達標：改或砍，換產品線裡的下一款。
5. 第 1 款賺錢之後，再考慮第 2 款。

## 待你決定的事

這 5 個問題沒有答案，方案就無法往下細化。

- [ ] 團隊有幾個人？會 Unity、Cocos 還是都沒用過？（本倉庫現有的是 Flutter 殼工程）
- [ ] 有沒有廣告投放預算？沒有的話，願不願意找發行商分成？
- [ ] 你說「已經有好幾款」，是哪幾款？有沒有現成的留存數據？
- [ ] 接不接受把目標從「12 款」改成「先做成 1 款」？
- [ ] 接不接受在遊戲裡放插頁廣告？

所有來源都以連結形式標在對應的數字旁邊。
