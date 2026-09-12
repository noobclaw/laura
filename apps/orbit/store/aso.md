# Orbit ASO(2026-09-12)

> 数据:iTunes Search API `country=us`(中文词 `country=cn`)、`entity=software&limit=50`,每词间隔 1.2s,实打于 2026-09-12。
> 「头部评价量」= **前 10 名里免费 app 的最高 userRatingCount**(50 名里随便一支巨头不代表词被占);档位判据:<5,000 主攻 / 5,000–50,000 次攻 / >50,000 放弃(只进关键词字段)。
> 「付费在位者」= 50 名内 price>0 的数量。「前3名」格式 `名称 ($价) [评价数]`。
> 美区 13 词中 12 词为放弃档。

## 主词表

### en-US(country=us)

| 词 | 命中 | 付费在位者 | 头部评价量 | 前3名 | 档位 |
|---|---|---|---|---|---|
| satellite tracker | 48 | 2 | 494,757 | Satellite Tracker by Star Walk [69917] ; Satellite Tracker / Radar [22] ; Sky Guide [373068] | 放弃 |
| iss tracker | 44 | 1 | 69,924 | Spot the Station [9834] ; ISS Tracker - ISSWatch [0] ; ISS Live Now [6570] | 放弃 |
| space station | 44 | 3 | 69,924 | Spot the Station [9834] ; Space Station Tracker [4] ; ISS Live Now [6570] | 放弃 |
| iss | 45 | 4 | 69,924 | ISS Live Now [6570] ; Spot the Station [9834] ; ISS Detector [569] | 放弃 |
| satellite | 48 | 2 | 373,191 | Satellite Tracker by Star Walk [69924] ; satellite - Mobil telefonieren [195] ; Google Earth [47209] | 放弃 |
| iss spotter | 38 | 1 | 69,924 | ISS Spotter App [0] ; Spot the Station [9834] ; Space Station Tracker [4] | 放弃 |
| see satellites | 48 | 6 | 69,924 | Find Starlink Satellites [83] ; Spot the Station [9834] ; Staslink: Satellites Tracker [19587] | 放弃 |
| starlink tracker | 48 | 3 | 114,893 | Satellite Tracker by Star Walk [69924] ; Starlink [114893] ; Find Starlink Satellites [83] | 放弃 |
| gosatwatch | 48 | 3 | 1,855,433 | GoSatWatch Satellite Tracking ($9.99) [60] ; Satellite Tracker by Star Walk [69924] ; Apple TV [1855433] | 放弃 |
| heavens above | 24 | 1 | 494,824 | Sky Live: Heavens Above Viewer [14752] ; Satellite Tracker by Star Walk [69924] ; Stellarium Mobile - Star Map [36796] | 放弃 |
| satellite pass | 49 | 3 | 15,935 | Starlink Satellite Passes [170] ; Satellite Tracker Pro [67] ; Satellite Tracker 3D [61] | 次攻 |
| spot the station | 34 | 0 | 69,924 | Spot the Station [9834] ; NASA [63704] ; ISS Tracker - ISSWatch [0] | 放弃 |
| tiangong | 35 | 2 | 69,924 | Space Station Passes [2] ; Satellite Tracker by Star Walk [69924] ; 睿住天工 [0] | 放弃 |

### zh-Hans(country=cn)

| 词 | 命中 | 付费在位者 | 头部评价量 | 前3名 | 档位 |
|---|---|---|---|---|---|
| 卫星过境 | 9 | 3 | 2 | 天宫空间站过境 [0] ; 卫星追踪 3D [2] ; SatCue: 卫星追踪器 [0] | 主攻 |
| 国际空间站 | 38 | 11 | 182,004 | Star Walk的卫星跟踪应用 [18737] ; NASA [7504] ; Star Walk 2 Plus: 观星的应用 AR [182004] | 放弃 |
| 看卫星 | 42 | 2 | 44,853 | 超清卫星地图 - 北斗导航看世界&精准定位 [547] ; 钓鱼佬-路亚台钓卫星地图找标点与钓友晒鱼获查天气潮汐水位 [1163] ; 百斗卫星实时导航 [33] | 次攻 |
| 天宫 | 45 | 0 | 15,404,914 | 天工 [8215] ; 千问 - 阿里AI助手 [299182] ; 闹闹天宫 [519] | 放弃 |
| 卫星追踪 | 43 | 1 | 57,292 | 卫星追踪 3D [2] ; Orbit：卫星追踪与 ISS [0] ; SatCue: 卫星追踪器 [0] | 放弃 |
| 空间站 | 42 | 1 | 18,737 | Star Walk的卫星跟踪应用 [18737] ; 天宫空间站 [8] ; 天文通 - 星图、观星指数、极光天象、星空指南 [896] | 次攻 |

## 三件套(en-US)

Title(29/30): Orbit: Satellite Pass Tracker
Subtitle(27/30): ISS & Space Station Spotter
Keywords(98/100): starlink,tiangong,hubble,flyover,offline,sky,night,stargazing,heavens,above,gosatwatch,sgp4,alerts

## 三件套(zh-Hans)

Title(20/30): Orbit 卫星过境预报 - 国际空间站
Subtitle(15/30): 几点抬头、朝哪看,离线卫星追踪
Keywords(50/100): 空间站,看卫星,天宫,ISS,哈勃,星链,观星,天文,过境,轨道,SGP4,StarWalk,天文通

## 复测基线

| 主词(4个) | 2026-09-12 排位 | 备注 |
|---|---|---|
| satellite tracker | 未进前 175 | 当前名 `Orbit: Satellite Pass Alerts`(id 6806894318);放弃(头部 494,757) |
| satellite pass | #31 / 166 | 当前名 `Orbit: Satellite Pass Alerts`(id 6806894318);次攻(头部 15,935) |
| iss tracker | 未进前 166 | 当前名 `Orbit: Satellite Pass Alerts`(id 6806894318);放弃(头部 69,924) |
| space station | 未进前 136 | 当前名 `Orbit: Satellite Pass Alerts`(id 6806894318);放弃(头部 69,924) |

> 排位实打方式:同一 API `limit=200`,按 trackId 找位次;「未进前 N」的 N = 该词实际返回条数。改元数据后 7–10 天再测(索引延迟)。

## 选词理由(≤8 行)

1. 唯一非放弃词是 `satellite pass`(头部 1.6 万、3 支付费)——而我们**当前名 `Orbit: Satellite Pass Alerts` 已在该词排 #31**,是全部 8 次排位实打里唯一进榜的,证明标题词在起作用。新标题保留 `Satellite Pass`,把 `Alerts` 换成 `Tracker`(`satellite tracker` 4.8 万命中,`alerts` 退到关键词)。
2. `iss tracker`/`space station`/`iss` 头部 6.99 万(Star Walk 卫星追踪)刚过 5 万线,按判据放弃,但直接同类 Spot the Station 只有 9,834 条——这三个词是**放弃档里最值得赌的**,所以副标题 `ISS & Space Station Spotter` 三个词全占。
3. `satellite`(Google Earth)、`starlink tracker`(Starlink 官方 11.5 万)、`gosatwatch`(前 10 有 Apple TV)、`heavens above`(Stellarium)放弃,只进关键词。
4. 楔子 `offline` 从副标题挤出去了(ISS/空间站更值钱),放关键词第 5 位。
5. 中区:`卫星过境` 9 个命中、头部 2 条 = 真空位(主攻);中区当前名 `Orbit：卫星追踪与 ISS`(中区独立 id 6772174570)在 `卫星追踪` 已排 #2、`卫星过境` #6(0 评价也能进,因为词空)。新中文标题首词改 `卫星过境预报`,`国际空间站` 放标题末段(18 万头部但 11 支付费,付费面厚)。
