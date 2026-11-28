# 竞品拆解：Total（App Ideas S.r.l.）

> 拆解日期 2026-11-28。按 `.claude/skills/tool-app-sop/` 第 2 步「逐项拆解」完成。
> 材料：① Codex 初步报告 `Desktop/Total-产品分析/Total-产品功能与设计分析.md`；② Android 版 `total_1.0.175`（包名 `it.appideas.totaldownloader`）反编译资源与核心代码（`sources/it/ideasolutions/` 共 500 个文件，已读 45 个核心控制器、模型和服务，以及 `strings.xml` 579 条 App 自有文案和 `AndroidManifest.xml`）；③ iOS 版「Total files pro」商店页与用户评论（Apple 公开页面）。
> 用途边界：反编译只用来**盘点功能与行为**。不复制任何代码、资源、图标、文案原句。`strings.xml` 里有对方的云服务 OAuth 客户端密钥和广告 ID，**严禁使用**。

## 0. 一句话结论

Total 是「浏览器下载 + 多云盘文件管理 + 混合播放列表」三合一。它的付费点是「去广告 + 导出 + 视频转音频」。真正的护城河是**多云账号统一管理**和**本地/云端混合播放**。最大的弱点是：广告重、设计老、App 级别没有密码锁、不能把文件传回电脑、更新后丢过用户数据、技术支持不回复。

## 1. 市场数据（2026-11-27 榜单快照）

| 版本 | 平台 | 价格 | 评分 | 评论数 | 榜单 |
|---|---|---|---|---|---|
| Total files pro | iOS | €5.99 / £4.99 / HK$38 | 4.69（德区）/ 4.6（英区） | 7,360（德区）/ 417（英区） | 德区工具付费榜 #69 |
| Total files | iOS | 免费 + 内购 + 广告 | — | — | — |
| Total | Android | 免费 + 广告 + 内购 `premium_unlock`（买断） | — | — | — |

2012 年上架，已经 14 年；2026-11-24 仍在更新（3.14.7）。iOS 版 10 种语言里只有 6 种（英、法、德、意、葡、西）。

## 2. 信息架构

Android 版用侧边抽屉切换 6 个区块（`BaseMasterSectionMenuViewController`，会记住上次停留的区块）：

| 区块 | 子页面 |
|---|---|
| Browser（默认首页） | 多标签（每个标签存缩略图）、地址/搜索栏（带补全建议）、书签（文件夹）、历史（按日/月/年分组）、最近检测到的视频 |
| Archive | 本地文件（App 内）、设备文件、云账号列表 → 云端目录、图片画廊（沉浸式查看） |
| Transfer files | 下载列表、上传列表 |
| Playlists | 播放列表目录 → 曲目详情 → 播放器（可拖成迷你窗） |
| Advanced search | 本地搜索、云端搜索 |
| Settings | 网络、浏览数据、购买、邀请、反馈、重置 |
| （隐藏）Remove adv | 看广告 / 做问卷 / 邀请好友 / 购买 换去广告 |

## 3. 功能逐项清单（不漏项）

编号规则：`T-区块-序号`。「证据」列：S=商店描述，R=资源文案，C=代码，iOS=iOS 商店页。

### 3.1 浏览器（T-B）

| 编号 | 功能 | 细节 | 证据 |
|---|---|---|---|
| T-B01 | 多标签 | 新建标签、标签切换器（缩略图抽屉 `TabSwitcherDrawable`）、关闭；重启后恢复所有标签和选中标签 | C `TabRecycler`、`state_tabs`、`state_tabs_selected_idx` |
| T-B02 | 地址栏 | 输入网址或搜索词；补全建议（`OmniboxSuggestion`）；默认首页 google.com，可由远程配置改 `welcomeSite` | R `search_or_type_url`、C `ConfigAppData` |
| T-B03 | 导航 | 后退、前进、刷新、停止加载、在外部浏览器打开、请求桌面版网站（换 UA） | R `accessibility_*`、`menu_request_desktop_site` |
| T-B04 | 书签 | 加书签（标题、网址必填）、编辑、删除；书签文件夹 | R `add_bookmark`、`bookmark_missing_url`、`bookmarks_folder_empty` |
| T-B05 | 历史 | 按年/月/日分组浏览、删除单条、清空全部 | C `HistoryGroupsListViewController`（historyyear/month/day） |
| T-B06 | 长按菜单 | 复制链接地址、复制链接文字、复制邮箱、复制图片、复制图片网址、打开图片、在新标签打开（链接/图片）、保存链接、保存图片、保存视频、删除书签 | R `contextmenu_*` |
| T-B07 | 视频嗅探 | 页面播放视频时检测链接，提示「发现视频，要下载吗？」；HLS（m3u8）、blob；可选清晰度/码率；「最近检测到的视频」列表 | R `VIDEO_LINK_FOUND`、`choose_quality_video`、`last_multimedia_detected`；C `HlsMediaPlaylistStorageData` |
| T-B08 | 下载选项 | 「下载并打开」「后台下载」「只下载音频」「下载视频」 | R `download_and_open`、`download_asynk`、`download_audio` |
| T-B09 | 站点管控（远程） | 远程配置下发：屏蔽站点规则与弹窗文案、按国家启用的自定义 JS 注入、跳过检测的域名、媒体检测脚本 URL、桌面/手机 UA | C `ConfigAppData`、`JavascriptCustomInject`（allowedCountries、blocked） |
| T-B10 | YouTube 禁用 | 明确屏蔽 YouTube 下载（「Youtube is disabled」） | R `YT_DISABLED`；iOS 差评「YouTube 下载不了」 |
| T-B11 | 浏览数据 | 设置里清除历史、清除 Cookie（二次确认） | R `confirm_delete_*` |
| T-B12 | 文件名识别 | 读取 `Content-Disposition` / `Content-Location` 决定文件名 | C `browser/l.java` |

### 3.2 文件库 Archive（T-A）

| 编号 | 功能 | 细节 | 证据 |
|---|---|---|---|
| T-A01 | 三类来源 | App 内文件、设备文件（含 SD 卡）、云账号 | R `archive_app/device/cloud`、`sdcard` |
| T-A02 | 列表/网格 | 切换显示方式 | R `visible_mode` |
| T-A03 | 排序 | 按文件名、最后修改时间 | R `order_by_title/last_modified` |
| T-A04 | 文件夹内搜索 | 当前目录过滤 | R `search_hint` |
| T-A05 | 新建文件夹 | 名称输入 | R `create_new_folder` |
| T-A06 | 单项操作 | 复制、移动、重命名、删除、复制副本（Duplicate）、隐藏、分享、用其他 App 打开、上传到云、下载、加入播放列表、在文件夹中显示、显示上级文件夹 | R `*_item_menu`、`hide_item_menu`、`open_with_item_menu` |
| T-A07 | 多选批量 | 多选后批量复制/移动/删除/上传/下载/分享/加入播放列表，显示「已选 N 项」 | R `*_items`、`selected_items`；C `select-multiple-*` |
| T-A08 | 目标文件夹选择器 | 复制/移动/下载/上传时选目标（本地或某个云账号的某个目录） | C `ArchiveSelect*FolderViewController` |
| T-A09 | 图片画廊 | 目录内图片左右滑、沉浸模式、删除、分享 | C `GalleryImagesViewController` |
| T-A10 | 导出（付费） | 把 App 内文件导出到外部文件夹 | R `export_file`、`export_feature_description_premium` |
| T-A11 | 视频转音频（付费或看广告） | 提取 M4A 音轨，可后台继续 | R `convert_item_menu`、`content_convert_video_premium` |
| T-A12 | 空间显示 | 本机与每个云账号的已用/可用空间 | R `space_used_long`、`space_available_long` |
| T-A13 | 文件夹不能分享 | 选中文件夹时分享禁用并提示 | R `cant_send_folder` |
| T-A14 | 数据迁移 | Android 11 分区存储迁移：迁移中不可退出，可跳过（不可逆警告） | C `MigrationDataStorageActivity` |
| T-A15 | 虚拟文件夹（iOS） | 把不同来源（云/本地）的文件归到同一个虚拟文件夹 | iOS |
| T-A16 | 隐藏文件夹 PIN（iOS） | 用 PIN 隐藏、锁住文件夹 | iOS |
| T-A17 | 压缩/解压（iOS） | zip | iOS |
| T-A18 | PDF 阅读/批注（iOS） | 批注、形状识别 | iOS |
| T-A19 | Files App 集成（iOS） | 通过 File Provider 让所有云在系统「文件」里读写 | iOS |
| T-A20 | Spotlight（iOS） | 本地内容建 Spotlight 索引 | iOS |
| T-A21 | QuickLook、缩略图（iOS） | 选中文件后左右滑看下一个；更多格式缩略图；可在图片上画 | iOS |
| T-A22 | iPad 多窗口拖放（iOS） | 两个窗口之间、与其他 App 之间拖文件 | iOS |
| T-A23 | iTunes 文件共享（iOS） | 通过电脑 Finder/iTunes 取文件（曾被拿掉又加回，用户为此给过 2 星） | iOS 评论 |

### 3.3 云账号（T-C）

| 编号 | 功能 | 细节 | 证据 |
|---|---|---|---|
| T-C01 | 支持的服务 | Android：Google Drive、OneDrive、Dropbox；iOS 另有 iCloud Files、WebDAV | C `cloudmanagercore/model/*`；iOS |
| T-C02 | 多账号 | 同一服务可加多个账号，数量不限（引导页卖点「INFINITE cloud accounts」） | R `tutorial_third_*` |
| T-C03 | 加/重配/删账号 | OAuth 授权；授权失效提示「Configuration lost」→「Reconfigure」；移除账号 | R `reconfigure_cloud_account`、`menu_remove_account_cloud` |
| T-C04 | 云端操作 | 列目录、建文件夹、复制、移动、重命名、删除、生成分享链接、临时下载链接、上传（Dropbox/OneDrive 分片上传会话） | C 各服务 Request*Model、UploadSession* |
| T-C05 | 不支持的操作提示 | 「该云不支持此操作」 | R `error_unsupported_operation` |
| T-C06 | 共享文件夹（iOS） | 管理和他人共享的文件夹 | iOS |
| T-C07 | 授权中转 | Dropbox/OneDrive 的 OAuth 回调走开发者自己的服务器域名 | R `redirecturl*` |

### 3.4 搜索（T-S）

| 编号 | 功能 | 细节 | 证据 |
|---|---|---|---|
| T-S01 | 本地搜索 | 按文件名；结果可打开、加入播放列表、在文件夹中显示 | C `ArchiveLocalSearchAdvancedViewController` |
| T-S02 | 云端搜索 | 选择账号后搜索；可从结果直接下载（后台/下载并打开）、加入播放列表、显示上级文件夹；「显示全部 >」 | C `CloudArchivesSearchAdvancedViewController` |
| T-S03 | 无账号空态 | 提示先添加云账号，可直接点加号 | R `no_cloud_account_configured_content` |

### 3.5 传输（T-T）

| 编号 | 功能 | 细节 | 证据 |
|---|---|---|---|
| T-T01 | 下载/上传两个列表 | 分开显示，空态文案 | R `no_downloads/uploads_advise_title` |
| T-T02 | 单任务操作 | 暂停、继续、重试、强制开始、删除（含文件）、移除（只删任务）、打开所在文件夹 | R `menu_*_transfer` |
| T-T03 | 全部操作 | 全部暂停、全部继续、删除全部任务、清除已完成 | R `stop_tasks`、`resume_tasks`、`delete_tasks`、`remove_complete_tasks` |
| T-T04 | 并发与排队 | 默认同时 1 个任务（可改）；其余排队 | C `DEFAULT_MAX_CONCURRENT_TRANSFER_TASK = 1` |
| T-T05 | 网络策略 | 默认禁止移动网络传输（设置开关）；按流量计费网络判断；网络变化时自动重排、恢复 | C `canTransferWithCurrentNetwork`、`dispatchRescheduleOnNetworkChange` |
| T-T06 | 空间预留 | 开始前计算预留空间，不足时报「空间不足」 | C `calculateReservedSpace`、`InsufficientSpaceException` |
| T-T07 | 断点续传 | 支持 Range 请求；资源变化/不支持 Range 时报错 | C `isAllowRange`、`UnsupportedRangeException`、`ResourceChangedException` |
| T-T08 | 速度显示 | 活动任务的实时速度 | C `updateSpeedActiveTasks` |
| T-T09 | 前台服务 + 通知 | 传输状态、进度、完成通知；通知权限请求（附说明） | C `ServiceForeGroundHolderTransferOperation`；R `check_notification_permission_content` |
| T-T10 | 跨来源传输 | 云 → 本机、本机 → 云；（云 → 云未见证据） | S、C |

### 3.6 播放列表与播放器（T-P）

| 编号 | 功能 | 细节 | 证据 |
|---|---|---|---|
| T-P01 | 播放列表管理 | 新建、重命名、删除、复制整份（Duplicate）、排序 | C `PlaylistsCatalogViewController` |
| T-P02 | 曲目管理 | 添加（来自 App 内、设备媒体库、任意云账号目录）、移除、复制/移动到别的列表、重命名、多选 | C `Pick*Controller`、`PlayListCatalogDetailsTrackController` |
| T-P03 | 混合来源 | 同一列表混合本地与云端音视频，云端边下边播 | S、C `PlaylistTrackMetadataCloudObject` |
| T-P04 | 播放器 | 播放/暂停、上一首/下一首、进度拖动、时间显示；播放出错自动跳下一首 | C `PlayListTracksViewControllerDismissable`、R `error_play_file` |
| T-P05 | 迷你播放器 | 可拖动缩成小窗、向左/向右滑关闭、上滑放大 | C `DraggableView`（CLOSE LEFT/RIGHT、onMinimized/onMaximized） |
| T-P06 | 后台播放 | 前台服务 + MediaSession；耳机拔出自动暂停（noisy）；处理音频焦点；Android Auto 浏览（onLoadChildren） | C `BackgroundAudioService` |
| T-P07 | 投屏 | Chromecast（部分格式不支持提示） | R `playng_on_chromecast`、`file_not_playable_on_chromecast` |
| T-P08 | 画中画（iOS） | 视频 PiP | iOS 评论 |
| T-P09 | 随机/循环（iOS） | 整份列表随机、循环 | iOS 评论 |

### 3.7 设置（T-SET）

允许移动网络传输 · 清除历史 · 清除 Cookie · 购买高级版（显示商店价格）· 恢复购买 · 去广告截止日期 · 已接受邀请数 · 版本号与用户 ID · 隐私政策 · 发邮件反馈（自动带版本号）· 支持请求 · 重置数据库（删光所有文件，二次确认）· 个性化广告开关（GDPR）· 问卷换去广告。

### 3.8 变现（T-M）

| 编号 | 机制 | 细节 |
|---|---|---|
| T-M01 | 广告 | 横幅、插页、原生、激励视频、开屏；插页最短间隔由远程配置控制；接了十几家广告聚合 SDK |
| T-M02 | 买断 `premium_unlock` | 去广告 + 导出到外部 + 视频转音频；价格显示商店价 |
| T-M03 | 限时去广告 | 「你想去广告多久？」一个月 / 永久 |
| T-M04 | 看广告解锁单次 | 单个文件的视频转音频 |
| T-M05 | 问卷换去广告 | 接 Pollfish 问卷 |
| T-M06 | 邀请换去广告 | 5 个好友通过邀请链接安装 → 6 个月无广告；每邀成功 1 人得 1 积分；进度指示器；定期提醒（间隔远程配置）；退出时挽留「你会失去免费去广告的机会」 |
| T-M07 | iOS 买断 + Family Sharing | Pro 版买断，可家人共享 |

### 3.9 增长与留存（T-G）

| 编号 | 机制 | 细节 |
|---|---|---|
| T-G01 | 引导页 | 5 页（浏览器、混合播放列表、无限云账号、同时传输、总结），可跳过 |
| T-G02 | 评分引导 | 触发：打开 ≥6 次且安装 ≥3 天，或安装 ≥7 天；之后每 7 天再弹，直到评过或点「不再提醒」。先在 App 内打星：≥4 星 → 跳商店评分 + 分享到 Facebook；<4 星 → 「告诉我们哪里不好」+ 发邮件 |
| T-G03 | 分享 App | 分享文案 + 邀请链接 |
| T-G04 | 推送 | Firebase 推送；强制更新（低于 `minVersionAppEnabled` 必须更新） |
| T-G05 | 设备注册与统计 | 启动时向自家统计服务注册设备；Firebase Analytics、Crashlytics |

### 3.10 权限与合规

网络、通知、前台服务（媒体播放）、唤醒锁、Wi-Fi 状态、粗略定位（广告 SDK）、广告 ID、计费、安装来源。GDPR 同意弹窗。iOS 年龄分级 17+（不受限网页访问）。

## 4. 弱点（我们的机会）

| 编号 | 弱点 | 证据 |
|---|---|---|
| W1 | 广告极重：十几家广告 SDK、插页、开屏，连 Pro 用户都在评论里抱怨体验 | C、评论 |
| W2 | App 本身没有密码 / Face ID 锁，「别人能看到我有隐藏文件」 | iOS 评论（英区） |
| W3 | 不能方便地把文件传回电脑（iTunes 共享曾被拿掉） | iOS 评论（意区） |
| W4 | 大改版后流程变长、功能找不到、多任务下载失效；旧版升级后丢失全部歌曲 | iOS 评论（爱尔兰区、希腊区、意区） |
| W5 | 技术支持不回复 | iOS 评论（英区） |
| W6 | 播放器不显示专辑封面 | iOS 评论（爱尔兰区） |
| W7 | GIF 支持不全 | iOS 评论 |
| W8 | 书签按钮位置不顺手（在顶部） | iOS 评论（意区） |
| W9 | 默认同时只传 1 个任务；不支持云到云直传 | C |
| W10 | 视觉陈旧（2012 年的产品，抽屉导航，Material 旧组件） | C、截图 |
| W11 | 只有 6 种语言；中文、日文、韩文都没有 | iOS 商店页 |
| W12 | 授权回调走自家服务器，服务器挂了就加不了账号 | R `redirecturl*` |
| W13 | 视频嗅探受 YouTube 等平台限制，承诺做不到 → 差评 | 评论 |
| W14 | 没有「接收其他 App 分享过来的文件」入口（Android 清单无分享接收） | Manifest |

## 5. 对我们不能照抄的部分（审核与合规）

- **视频嗅探下载（T-B07、T-B10）**：Apple 审核 5.2.3 禁止帮助用户从第三方媒体平台下载受版权保护的内容。我们**不做视频嗅探、不做 HLS 抓流**，只做用户主动点击的普通文件下载链接。
- **广告体系（T-M01、T-M04、T-M05）**：不做。
- **邀请换去广告（T-M06）**：需要服务端去重、防刷，且我们没有广告可去，不做。
- **App 内先打星再分流到商店（T-G02 的星级筛选）**：iOS 不能自己画星级评分窗；按 tool-app-factory 铁律 13，改用「喜欢吗？」两步法。
- **自家服务器做 OAuth 回调（T-C07）**：改用原生 PKCE + App 自己的 URL scheme，不依赖服务端。
