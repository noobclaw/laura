# 竞品拆解：NAS / 云端音乐播放器（DS audio、DS Music、Evermusic、CloudBeats）

> 拆解日期 2026-11-28。tool-app-sop 第 0–2 步。用户 11-28 点名开工（「直接开工吧，不用验证了」），立项评分照写，风险见 PLAN 第 13 节。
> 材料：Synology 官方 Audio Station / DS audio 规格页（S）、App Store 商店页与评分（S）、GitHub Actions `keywords.yml` 拉取的美英德日 12 词头部与 Evermusic Pro / CloudBeats 近 43 条 1–3★ 评论（R）、DS audio 公开差评摘要（R）。本次**无 Codex 交接包**（无源码/反编译），只拆可观察的功能与行为；所有「C 代码」证据项为空。
> 净室声明：只记录功能与行为参数；不复制任何代码、图标、文案原句与资源；不使用对方任何密钥或服务器。

## 0. 一句话结论

Synology 官方 DS audio 能力全但难用（★2.71/美区 213 条），免费的 DS Music 功能已较全但只有简繁英 3 种语言；宽口径对手 Evermusic / CloudBeats 付费真实，但差评集中在**停播、大曲库慢、更新即坏、客服不回、收费反感**。我们的楔子：**最稳、最好看、一次买断、10 种语言的 NAS 音乐播放器**，曲库直读 NAS 文件（不依赖 Audio Station 是否停更）。

## 1. 市场数据（2026-11-28，iTunes Search API）

| App | 价格 | 评分 / 评价数（美区） | 备注 |
|---|---|---|---|
| DS audio（Synology） | 免费 | ★2.71 / 213（德 327、英 93） | 官方；Audio Station 末版 7.2.0（2024-08） |
| DS Music – SynologyMusicPlayer | 免费 | ★4.26 / 43 | 第三方；CarPlay、离线、歌词、2FA；仅简中/繁中/英 |
| Evermusic / Evermusic Pro | 免费+订阅/终身 $29.99；Pro 付费 | 19,352（免费版） | 多云 + NAS；差评集中在更新与客服 |
| CloudBeats | $9.99 | 3,436 | 2025-04 后未更新；无 iCloud |
| 11 月新进同类（NAS Music Player、Cartridge、Synofi、TuneSync、Mina…） | 多为免费/$2.99 | 0–43 条 | 搜索头部未被占稳 |

巨头快检：`cloud music player` / `nas music player` / `synology music` 美区前 10 无 Apple/Google 等，无 ≥10 万评价免费真同类（Musicana 96,136 但 2022 后停更，且偏「免费流媒体」）。英德区混入 SoundCloud（词义碰撞，非真同类）。

## 2. 信息架构（DS audio，按官方规格与帮助页）

| 区块 | 子页面 |
|---|---|
| 登录 | QuickConnect ID / 域名 / 局域网 IP:端口、HTTPS、2FA、一次性密码 |
| 首页 | 置顶的歌单/文件夹/专辑/艺人、推荐流派 |
| 曲库 | 专辑 / 艺人 / 作曲 / 流派 / 文件夹 / 歌曲 / 最近添加 / 评分 |
| 歌单 | 个人 / 群组 / 智能歌单、随机 100 首 |
| 播放器 | 播放队列（拖动排序）、歌词、睡眠定时、摇一摇切歌、评分 |
| 已下载 | 离线歌曲、下载状态 |
| 其他 | 网络电台、DLNA/AirPlay/Chromecast 输出、远程播放器、分享链接 |
| 设置 | 播放质量（转码）、缓存、账号 |

## 3. 功能逐项清单

证据：S = 官方规格/商店页，R = 用户评论。

### 3.1 连接（T-N）
| 编号 | 功能 | 细节 | 证据 |
|---|---|---|---|
| T-N01 | 连接 Synology Audio Station | QuickConnect / 域名 / IP:端口 | S |
| T-N02 | HTTPS 与自定义端口 | | S |
| T-N03 | 2FA / 一次性密码 | | S |
| T-N04 | 多 NAS 账号 | | S（DS Music 多登录方式） |
| T-N05 | 浏览 DLNA 媒体服务器 | | S |
| T-N06 | 其他协议（宽口径：SMB、WebDAV、FTP、Google Drive、Dropbox、OneDrive…） | Evermusic / CloudBeats | S |

### 3.2 曲库（T-L）
| T-L01 | 按专辑/艺人/作曲/流派组织 | | S |
| T-L02 | 文件夹浏览 | | S |
| T-L03 | 全部歌曲 + 搜索 | 评论抱怨 DS audio 无好用搜索 | S/R |
| T-L04 | 最近添加 | | S |
| T-L05 | 评分（含从 iTunes 导入） | | S |
| T-L06 | 封面（文件夹 JPG / 内嵌） | 评论：换网络后封面缓存全清 | S/R |
| T-L07 | CUE 整轨分割 | | S |
| T-L08 | 格式：MP3/M4A/ALAC/AIFF/WAV/FLAC/OGG/APE/WMA/DSD（部分需转码） | | S |
| T-L09 | 大曲库扫描 | 宽口径评论：几千/几万首扫描慢、重复专辑 | R |
| T-L10 | 标签修正（在线搜 ID3） | | S |

### 3.3 播放（T-P）
| T-P01 | 播放队列、拖动排序 | | S |
| T-P02 | 随机 / 循环 / 随机 100 首 | | S |
| T-P03 | 无缝播放（无损原文件） | | S |
| T-P04 | 后台播放、锁屏控制 | 评论：锁屏停播、3–4 首后卡死、通知后音量不恢复 | R |
| T-P05 | 歌词（插件联网搜） | | S |
| T-P06 | 睡眠定时 | | S |
| T-P07 | 摇一摇切歌 | | S |
| T-P08 | 播放质量 / 转码 | | S |
| T-P09 | CarPlay | DS audio、DS Music 都有 | S |
| T-P10 | AirPlay / Chromecast / DLNA 输出 | | S |
| T-P11 | 均衡器（仅 Android） | | S |

### 3.4 歌单（T-Y）
| T-Y01 | 个人 / 群组歌单 | | S |
| T-Y02 | 智能歌单（条件） | | S |
| T-Y03 | 导入 M3U/PLS/WPL | 宽口径评论：M3U 导入失败 | S/R |

### 3.5 离线（T-O）
| T-O01 | 下载歌曲到手机离线播放 | 评论：DS audio 每首播完下载就停 | S/R |
| T-O02 | 下载状态页 | | S |

### 3.6 其他（T-X）
| T-X01 | 网络电台（SHOUTcast） | | S |
| T-X02 | 分享链接（歌曲/歌单） | | S |
| T-X03 | 远程播放器控制 NAS 外接音箱 | | S |
| T-X04 | Alexa 语音 | | S |

### 3.7 变现与增长（T-M）
| T-M01 | DS audio / DS Music 免费 | | S |
| T-M02 | Evermusic 订阅 + 终身 $29.99；Pro 付费版 | 评论：Pro 比免费少功能、买断后仍弹网页要邮箱 | S/R |
| T-M03 | CloudBeats 付费下载 $9.99 | 评论：付了钱 Pro 没解锁 | S/R |
| T-M04 | 语言：DS Music 仅简繁英 | | S |

## 4. 弱点（W）

| # | 弱点 | 证据 |
|---|---|---|
| W1 | 后台/锁屏停播、播几首就卡死、来通知后音量不恢复 | R（DS audio、Evermusic、Readdle 同类） |
| W2 | 换网络/重启后封面缓存全清 | R（DS audio） |
| W3 | 大曲库扫描慢、标签缺失、重复专辑 | R（Evermusic、CloudBeats） |
| W4 | 界面老旧、操作笨、无好用搜索 | R（DS audio） |
| W5 | 离线下载不连续（每首播完就停） | R（DS audio） |
| W6 | 暂停一会儿就被登出 / TLS 1.3 连不上 | R（DS audio） |
| W7 | 更新即坏（iOS 26 耳机键失灵、SMB 坏一个月） | R（Evermusic） |
| W8 | 客服不回 | R（Evermusic、CloudBeats） |
| W9 | 收费反感：订阅、Pro 功能少、买断还要邮箱、付了没解锁 | R |
| W10 | 依赖 Audio Station：它停更就全停（Video Station 已被移除） | S |
| W11 | 语言少（DS Music 3 种） | S |
| W12 | CloudBeats 无 iCloud、一年多不更新 | R |

## 5. 不照抄

- 网络电台、Alexa、DLNA 远程播放器：偏离「播放自己 NAS 里的音乐」主线，且需额外服务，✕。
- 联网歌词插件、在线 ID3 修正：需要第三方歌词/标签服务的授权，✕（只显示文件内嵌歌词）。
- 转码：需 NAS 端服务，✕（iOS 原生支持的格式直放；FLAC 原生支持）。
- 订阅、买断后要邮箱注册：✕。
- 任何账号密码上传到我们的服务器：✕（只存 Keychain，直连 NAS）。
