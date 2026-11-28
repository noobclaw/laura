# Spindle — PLAN（tool-app-sop 统一模板）

> 状态：🟢在做（M1）　路线：原生 SwiftUI（iOS 17+，只 iPhone 竖屏）　Bundle：`com.noobclaw.spindle`
> 链接：[TEARDOWN-nas-music.md](TEARDOWN-nas-music.md) · [TEST-CASES.md](TEST-CASES.md) · [ACCEPTANCE.md](ACCEPTANCE.md)
> 立项：用户 2026-11-28 点名开工（「直接开工吧，不用验证了」）→ 按 `08` 规则不退回挑刺关，第 13 节补评分并写明风险。

## 1. 一句话定位
家里有 NAS（Synology、QNAP、任何 WebDAV / SMB 共享）的人，用 Spindle 把 NAS 里的音乐当成一张张唱片来听：稳、快、好看、能离线。
英文副标题草案：*NAS & WebDAV Music Player*（商店名不用 Synology 商标，描述里写「works with Synology, QNAP…」）。

## 2. 差异化楔子
DS audio 能连但难用（★2.71），DS Music 免费但只有 3 种语言，Evermusic / CloudBeats 收费但停播、更新即坏、客服不回。**Spindle：播放不断、封面永不丢、曲库直读 NAS 文件（Audio Station 停了也能用）、10 种语言、一次买断不订阅。**

## 3. 目标用户
| 人群 | 场景 | 证据 |
|---|---|---|
| Synology / QNAP 家用 NAS 用户 | 把多年收藏的 MP3/FLAC 放 NAS，手机上听 | DS audio 差评跨多年多区（TEARDOWN W1–W6） |
| WebDAV / 自建服务器玩家 | Nextcloud、rclone、Synology WebDAV Server | Evermusic、CloudBeats 付费用户（$9.99 / 终身 $29.99） |
| 本地音乐收藏者（iCloud / 手机文件夹） | 不想用流媒体，只听自己的文件 | 文件 App 只能单首播放、无曲库 |

## 4. 功能对照表
| 竞品编号 | 竞品功能 | 我们 | 做法 |
|---|---|---|---|
| T-N01 | 连 Audio Station | ↑（M2） | M1 走 WebDAV 与「文件」App 的 SMB 位置直读文件；M2 再加 Audio Station 账号（作为可选来源，不依赖它，W10） |
| T-N02 | HTTPS / 自定义端口 | ＝ | WebDAV 地址可写 `https://host:port/path`；自签证书需用户在系统信任后使用（不绕过 TLS） |
| T-N03 | 2FA / 一次性密码 | ↑（M2） | 随 Audio Station 来源一起做；WebDAV 用 NAS 的应用专用密码 |
| T-N04 | 多 NAS 账号 | ＝ | 来源列表；免费 1 个、Pro 无限 |
| T-N05 | DLNA 浏览 | ✕ | 平台不适用 + 与主线偏离；SMB/WebDAV 已覆盖同一批文件 |
| T-N06 | SMB / WebDAV / 云盘 | ↑ | M1：WebDAV + 「文件」App 里的任何位置（含系统 SMB、iCloud、本机）；M2：Google Drive / Dropbox / OneDrive |
| T-L01 | 专辑 / 艺人 / 流派 | ＝ | 专辑、艺人、歌曲三视图；流派 M2 |
| T-L02 | 文件夹浏览 | ＝ | 来源详情里按文件夹浏览 |
| T-L03 | 全部歌曲 + 搜索 | ↑ | 一个搜索框同时搜歌名/艺人/专辑，边打边出，≤150 ms（本地索引） |
| T-L04 | 最近添加 | ＝ | 首屏「最近添加」唱片行 |
| T-L05 | 评分 | ✕（v1） | 改为「收藏」（心形），评分 M3 再评估 |
| T-L06 | 封面 | ↑ | 封面一次取到就存进 Application Support（不是 Caches），换网络、重启都在（W2）；无封面时按专辑名生成唱片标签 |
| T-L07 | CUE 分轨 | ✕（v1） | 工作量大，放 M3 |
| T-L08 | 多格式 | ↑ | iOS 原生：MP3/AAC/M4A/ALAC/AIFF/WAV/FLAC/Opus(CAF)；不支持的格式在曲库里标「此格式无法播放」而不是静默失败 |
| T-L09 | 大曲库扫描 | ↑ | 先按路径秒出曲库（艺人/专辑/曲名从文件夹结构推断），再后台慢慢补标签与封面；扫描进度可见、可中断续扫；重复专辑按「专辑名+艺人」合并 |
| T-L10 | 在线修标签 | ✕ | 需第三方标签服务授权 |
| T-P01 | 播放队列 + 拖动排序 | ＝ | 队列页拖动、左滑删除 |
| T-P02 | 随机 / 循环 | ＝ | 随机（不重复直到一轮）、列表循环、单曲循环 |
| T-P03 | 无缝播放 | ＝ | AVQueuePlayer 预载下一首 |
| T-P04 | 后台、锁屏 | ↑ | 播放器守护：中断（来电/通知/Siri）后按系统 `shouldResume` 自动恢复，音量不变；卡住 >8 s 自动重连同一位置；拔耳机暂停（W1） |
| T-P05 | 歌词 | ↑（M2） | 只显示文件内嵌歌词（不联网） |
| T-P06 | 睡眠定时 | ＝ | Pro；15/30/45/60 分钟/本曲结束，淡出 |
| T-P07 | 摇一摇切歌 | ✕ | 误触多，用锁屏/耳机键即可 |
| T-P08 | 转码 | ✕ | 需 NAS 端服务 |
| T-P09 | CarPlay | ↑（M2） | 需向 Apple 申请 CarPlay 音频权限，M2 |
| T-P10 | AirPlay | ＝ | 系统路由按钮 |
| T-P11 | 均衡器 | ✕ | 仅 Android 有；iOS 用系统 |
| T-Y01 | 歌单 | ＝ | 免费 2 个、Pro 无限 |
| T-Y02 | 智能歌单 | ↑（M3） | |
| T-Y03 | 导入 M3U | ↑（M2） | 失败时逐行列出找不到的歌 |
| T-O01 | 离线下载 | ↑ | 整张专辑/歌单一键下载，队列连续下完（W5）；免费 20 首、Pro 无限 |
| T-O02 | 下载状态 | ＝ | 来源详情里显示已下载数与占用空间，可一键清除 |
| T-X01 | 网络电台 | ✕ | 偏离主线 |
| T-X02 | 分享链接 | ↑ | 分享「正在听」唱片卡（不暴露 NAS 地址） |
| T-X03 | 远程播放器 | ✕ | 偏离主线 |
| T-X04 | Alexa | ✕ | 平台不适用 |
| T-M01–M03 | 免费 / 订阅 / 付费下载 | ↑ | 免费可用 + Pro 一次买断，无邮箱、无订阅（W9） |
| T-M04 | 语言 3 种 | ↑ | 10 种（W11） |

统计：＝ 14、↑ 17、✕ 11。

## 5. 创新
| 编号 | 创新 | 解决什么 | 里程碑 |
|---|---|---|---|
| S-I01 | **秒出曲库**：先按文件夹结构建库，再后台补标签/封面 | W3 大曲库慢 | M1 |
| S-I02 | **播放守护**：中断后自动恢复、卡住自动重连同一位置、显示「重连中」 | W1 停播 | M1 |
| S-I03 | **封面永存**：封面进 Application Support 并按专辑去重 | W2 | M1 |
| S-I04 | **唱片墙首屏**：首屏就是你的唱片架，最近添加 + 一张张旋转的唱片，没有登录墙 | W4 界面老旧 | M1 |
| S-I05 | **示范唱片架**：没 NAS 也能先听 8 首合成示范曲，30 秒内知道 App 好不好用（也给审核员用） | 冷启动 | M1 |
| S-I06 | **不依赖 Audio Station**：直读文件，NAS 套件停更也照常 | W10 | M1 |
| S-I07 | **正在听唱片卡**：分享 1080×1350 卡，封面 + 曲名 + 进度环，不含任何地址 | 拉新 | M1 |

## 6. 核心循环、功能与页面
核心循环：加一个来源 → 曲库秒出 → 点一张唱片 → 播放不断 → 想带走就离线。

| 功能 | 免费 | Pro |
|---|---|---|
| 来源（WebDAV / 文件位置） | 1 个（示范唱片架不算） | 无限 |
| 曲库、搜索、队列、随机循环、后台播放、AirPlay | ✅ | ✅ |
| 歌单 | 2 个 | 无限 |
| 离线下载 | 20 首 | 无限 |
| 睡眠定时 | — | ✅ |
| 分享卡 | ✅ | ✅ |

页面：
- **唱片架（首屏）**：顶部 Spindle 字标 + 分享 + 齿轮；hero「唱片轴」（每个来源一张唱片叠在轴上，厚度 = 曲目数）；「最近添加」唱片行；专辑网格；底部迷你播放器。
- **搜索**：搜索框 + 歌曲/专辑/艺人分组结果。
- **歌单**：歌单列表、详情。
- **来源**（从唱片架进入）：来源列表、添加来源（WebDAV 表单 / 选择文件夹）、来源详情（扫描进度、文件夹浏览、离线占用）。
- **专辑 / 艺人详情**、**正在播放**（大唱片随播放旋转、进度环、队列）、**设置**（语言第一行）、**付费页**、**分享卡**。

### 6.1 设计简报
1. 场景：通勤/在家，单手；3 秒内点开一张专辑开始播。
2. 首屏：唱片架本身（唱片轴 hero + 最近添加 + 专辑网格），主操作（播放/迷你播放器）在拇指区。
3. 首胜：冷启动 0 设置即见示范唱片架，点任一唱片 1 次即播放。
4. 原型：**仪器面板 Instrument**（Hi-Fi 功放面板）；已用该原型：tunekit；不同点：字体 Anton（窄体海报字）vs tunekit 系统等宽；形状 2/10/999 圆角 + 唱片圆形 vs tunekit 方表盘。
5. 色彩：Restrained；色相 56°（黄铜信号黄，色相表空档 50–65°）。
   浅色：bg #F1EFE8 surface #FFFFFF ink #1B1C1E sub #6B6A64 accent #8A8122 signal #C2502F
   深色：bg #121315 surface #1C1E21 ink #ECEAE3 sub #9A9890 accent #D9CF4A signal #E86A4A
6. 字体：展示 Anton-Regular（OFL，170 KB，只用于字标、专辑大标题、大数字）；数字等宽系统字；正文系统字；CJK 环境下 Anton 只用于拉丁字标，标题回退系统粗体。
7. 形状：圆角 2 / 10 / 999；分隔用 1 px 发丝线；基准间距 8 pt；行高 1.25。
8. 图形语言：**唱片轴（Spindle Stack）**——一根黄铜轴上叠着各来源的唱片，厚度 = 该来源曲目数，正在播放的那张亮信号色并缓慢转动。
9. Signature 场景：正在播放页大唱片按真实播放进度转动，唱臂位置 = 进度；减少动态效果时唱片静止、只显示进度环。
10. 空状态：没有来源时，唱片轴上只有「示范」一张，下方两个按钮「添加 WebDAV」「选择文件夹」。
11. 触感：播放/暂停 light；加入歌单 success；扫描完成 success。
12. 首屏线框：
```
 SPINDLE                      ⇪  ⚙
 ┌───────────────────────────────┐
 │  ══╪══  唱片轴（来源叠片）     │  3 sources · 2,418 songs
 └───────────────────────────────┘
 Recently added  ◉ ◉ ◉ ◉ →
 Albums
 ◉ Kind of Blue   ◉ Blue Train
 ◉ ...            ◉ ...
 ▌▶  So What — Miles Davis   ⏸
 [唱片架] [搜索] [歌单]
```
13. 自检：换成「云盘音乐播放器」会不会做成一样的列表？不会——唱片轴 + 唱片网格 + 旋转唱片是本 App 独有的图形语言。
14. 用户拍板偏离：无。

## 7. 关键流程
1. 首启：0 引导页，直接进唱片架（示范唱片架已在）→ 点示范专辑 → 播放。
2. 加 WebDAV：唱片架 ⚙旁「来源」→ ＋ → WebDAV → 填地址/用户名/密码 → 「测试连接」显示找到的文件夹数 → 保存 → 曲库秒出（路径推断）→ 后台补标签/封面，进度可见。
3. 加文件夹：＋ → 选择文件夹 → 系统文件选择器选一个文件夹（可选「文件」App 里的 SMB 服务器）→ 扫描 → 曲库出现。
4. 播放：专辑页 → 点歌 → 迷你播放器出现 → 锁屏可控 → 来电后自动恢复。
5. 离线：专辑页「下载」→ 进度 → 飞行模式仍可播放已下载歌曲。
6. 歌单：歌曲长按 → 加入歌单 → 新建歌单。
7. 分享：首屏分享或正在播放页分享 → 唱片卡预览 → 系统分享面板。
8. 好评：见第 11 节。

## 8. 招牌功能架构
- **来源协议** `MusicSource`：`list()` 递归列出音频文件（路径、大小、修改时间）、`playableURL(for:)`、`download(_:to:)`。实现：`WebDAVSource`（PROPFIND Depth:1 逐层，XML 解析，Basic 认证凭据存 Keychain 并登记到 `URLCredentialStorage` 让 AVPlayer 认证）、`FolderSource`（security-scoped bookmark + FileManager 枚举）、`DemoSource`（首次启动用代码合成 8 首 WAV 写入 Application Support）。
- **曲库** `LibraryStore`：JSON 原子写入 `Application Support/library.json`（带 schemaVersion，升级前备份）；`PathInference` 从 `Artist/Album/NN Title.ext` 推断；`MetadataEnricher` 后台并发 2 读 AVAsset commonMetadata（标题/艺人/专辑/音轨号/封面），结果覆盖推断值。
- **播放器** `PlayerEngine`：AVQueuePlayer；`AVAudioSession` playback；`MPNowPlayingInfoCenter` + `MPRemoteCommandCenter`；中断/路由变化处理；`timeControlStatus` 卡住 8 s 自动重建 item 并 seek 回原位置。
- **离线** `OfflineStore`：URLSession 下载到 `Application Support/Offline/`，串行队列连续下载；播放时优先本地文件。
- 可替换接口：来源协议，M2 加 Audio Station / 云盘只需新实现。

## 9. 权限
| 权限 | 何时请求 | 用途说明（英文源） | 拒绝后 |
|---|---|---|---|
| 本地网络 `NSLocalNetworkUsageDescription` | 第一次连接局域网地址的 WebDAV 时（系统自动弹） | Spindle connects to the music server on your home network that you add as a source. | 显示「无法访问局域网，去设置打开 Spindle 的本地网络」+ 去设置 |
| 相册写入 `NSPhotoLibraryAddUsageDescription` | 分享卡点「存到相册」时 | Spindle saves the share card you create to your photo library. | 提示去设置；系统分享面板仍可用 |
| 后台音频 `UIBackgroundModes: audio` | — | — | — |

## 10. 变现
- 免费 + **Spindle Pro 一次买断 $9.99**（`com.noobclaw.spindle.pro_unlock`，非消耗型，家人共享）。
- 依据：CloudBeats $9.99、MusicStreamer €9.99、play:Sub $4.99、Evermusic 终身 $29.99；DS audio / DS Music 免费，所以免费层必须真能用（1 个来源完整可用）。
- 免费额度：来源 1 个（示范不算；删除来源后额度回来）；歌单 2 个；离线 20 首（按「已下载完成的歌曲数」计，失败不计，删除离线文件后额度回来）。
- 付费墙按铁律 4，入口：加第 2 个来源、建第 3 个歌单、第 21 首离线、睡眠定时、设置里的 Pro 卡片。

## 11. 好评引导
- 时机：本次安装 ≥3 天，且（完整播完第 10 首歌 或 首次扫描完成 ≥100 首），距上次 ≥30 天；出错后、付费页上、首启 5 分钟内不弹。
- 两步：自家卡片「喜欢 Spindle 吗？」→ 喜欢 → 系统 `requestReview`；还不够好 → mailto `support@256btc.com`，正文带 App 版本与 iOS 版本，不带任何地址/账号。
- 设置常驻「给 Spindle 评分」。
- 对比竞品：DS audio / Evermusic 无此类前置卡；我们不奖励、不画星星。

## 12. 分享
- 首屏右上分享 → 「我的唱片架」卡：唱片轴图形 + 来源数 + 专辑数 + 歌曲数（不含来源名、地址）。
- 正在播放页分享 → 「正在听」卡：封面唱片 + 曲名 + 艺人 + 进度环。
- 1080×1350，App 名与图标在卡底；系统分享面板 + 存到相册。

## 13. 立项评分（补，评分日期 2026-11-28）
| 科 | 分 | 依据 |
|---|---|---|
| 信号持续性 /40 | 24 | DS audio 差评跨多年多区；11 月 ≥6 支新同类 = 别人也看到需求；Trends 热度近 0 |
| 付费验证 /25 | 16 | CloudBeats $9.99/3,436、play:Sub $4.99/435、Evermusic 终身 $29.99；Synology 专属付费品未证实 |
| 开发可行性 /20 | 13 | WebDAV/文件直读 + 原生播放器可行；Audio Station API 社区文档（M2） |
| 竞品缺口 /15 | 9 | 官方 ★2.71；免费 DS Music ★4.26/43 为主要对手 |
| 分发 /10 | 10 | 真同类 <5,000 + 工具联想 + r/synology、Synology 论坛、NAS 教程站 |
| 热度/竞争 /10 | 6 | 工具意图 3 + 头部 <5,000 得 3；vsAnchor 0–2 不加分 |
总指数 62。最危险假设：「Synology 用户在两个免费 App 之外愿意买断 $9.99」——**用户拍板跳过实验**，上线后以首月转化复盘；次险 Audio Station 停更已由 S-I06 规避。

## 14. 技术方案
| 模块 | 技术 | 许可证 |
|---|---|---|
| UI | SwiftUI（iOS 17），Observation | Apple |
| 播放 | AVFoundation、MediaPlayer | Apple |
| WebDAV | URLSession + 自写 PROPFIND 解析（XMLParser） | 自写 |
| 文件位置 | UIDocumentPicker + security-scoped bookmark | Apple |
| 存储 | JSON 原子写 + Keychain | Apple |
| 内购 | StoreKit 2 | Apple |
| 字体 | Anton-Regular | OFL 1.1 |
无第三方代码依赖。

## 15. 术语表（10 语言核心术语）
Source / 來源 / 来源 / ソース / 소스 / Quelle / Source / Fuente / Fonte / Sorgente；Album / 專輯 / 专辑 / アルバム / 앨범 / Album / Album / Álbum / Álbum / Album；Artist / 演出者 / 艺人 / アーティスト / 아티스트 / Künstler / Artiste / Artista / Artista / Artista；Playlist / 播放清單 / 歌单 / プレイリスト / 재생목록 / Playlist / Playlist / Lista / Playlist / Playlist；Offline / 離線 / 离线 / オフライン / 오프라인 / Offline / Hors ligne / Sin conexión / Offline / Offline。

## 16. 里程碑
- **M1（本轮）**：WebDAV + 文件位置 + 示范来源；秒出曲库 + 后台补标签封面；专辑/艺人/歌曲/搜索；播放器（队列、随机循环、后台、锁屏、中断恢复、卡住重连、AirPlay）；离线下载；歌单；睡眠定时；Pro 付费墙；分享卡 ×2；好评引导；设置（语言第一行）；10 语言。验收 = TEST-CASES 标 M1 的用例全部有结果、P0/P1 全过。
- **M2**：Synology Audio Station 账号来源（QuickConnect/2FA）、CarPlay、内嵌歌词、M3U 导入、Google Drive / Dropbox / OneDrive、流派视图。
- **M3**：智能歌单、CUE 分轨、小组件、评分。

## 17. 真机验收清单（D 类用例）
1. TC-PLY-03 锁屏控制；2. TC-PLY-04 来电后自动恢复；3. TC-PLY-05 拔耳机暂停；4. TC-SRC-04 连真实 Synology WebDAV；5. TC-SRC-06 「文件」App SMB 位置；6. TC-OFF-03 飞行模式播放离线歌曲；7. TC-IAP-08 沙盒购买。

## 18. 隐私与审核
- 不收集任何数据；App Privacy 填「不收集」。WebDAV 密码只在 Keychain；连接只在手机与用户 NAS 之间。
- 审核说明：App 无需账号；首次启动即有「示范唱片架」（App 自己合成的音频，无版权内容）可测试全部播放功能；WebDAV 可用任意测试服务器；Pro 内购随版本提交。
- 年龄分级 4+。商店名与关键词不用「Synology」商标，描述中以兼容说明出现。

## 19. 参考实现分析
无开源代码参考；功能按官方规格页与商店页拆解（TEARDOWN），未接触任何竞品代码与资源。
