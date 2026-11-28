# Spindle — 测试用例（由 PLAN.md 逐条推导，tool-app-sop 第 6 步）

> 字段：ID · 来源 · 前置 · 步骤 · 预期 · 优先级 · 里程碑 · 方式（U 单测 / A XCUITest / M 人工模拟器 / D 真机）。
> U/A 类写成测试函数，函数名带用例号（例 `test_TC_LIB_01_…`），CI 每次跑并生成 `qa/TC-RESULT-<build>.md`；未测 = 不通过。

## 0. 环境与夹具
| 项 | 值 |
|---|---|
| 设备 | CI：iPhone 16 模拟器（最新 iOS）；小屏：iPhone SE（M 类）；真机 1 台（D 类） |
| 语言 | en 源 + zh-Hant / ja / de 截屏；其余 6 种跑覆盖率闸门 |
| 夹具 | `SpindleTests/Fixtures/`：`propfind_root.xml`、`propfind_album.xml`（含中文、空格、% 编码、子目录、非音频文件）、`propfind_401.txt`；示范来源 8 首合成 WAV（运行时生成） |
| 启动参数 | `-UITourReset`（清空数据，重新生成示范库）、`-UITourPro`（Pro 状态）、`-UITourLanguage <code>` |
| StoreKit | `Spindle.storekit` 本地配置 |

## 1. 首屏唱片架（6、6.1、S-I04、S-I05）
| ID | 来源 | 前置 | 步骤 | 预期 | 优先级 | M | 方式 |
|---|---|---|---|---|---|---|---|
| TC-HOME-01 | 6.1-3 / V6 | 全新安装 | 冷启动 | 0 次点击看到唱片轴 hero、「Demo shelf」唱片与 8 首示范曲所在专辑 | P0 | M1 | A |
| TC-HOME-02 | 6 / 铁律 10、7 | 同上 | 看首屏右上 | 有「Share」与「Settings」两个按钮，可点 | P0 | M1 | A |
| TC-HOME-03 | 7-1 / 6.1-3 | 同上 | 点示范专辑 → 点第 1 首 | 迷你播放器出现并显示该曲名；播放状态为播放中 | P0 | M1 | A |
| TC-HOME-04 | 8 PathInference | — | 单测：唱片轴各来源厚度比例 | 厚度 = 曲目数 / 总数，最少 4 pt | P2 | M1 | U |
| TC-HOME-05 | 6.1-10 | 删除示范来源且无其他来源 | 打开首屏 | 空状态有「Add WebDAV」「Choose a folder」两个按钮 | P1 | M1 | A |
| TC-HOME-06 | S-I05 | — | 单测：示范来源生成 | 生成 8 个 WAV、每个可被 AVAudioFile 打开、时长 18–22 s | P1 | M1 | U |

## 2. 来源（T-N02、T-N04、T-N06、8）
| ID | 来源 | 前置 | 步骤 | 预期 | 优先级 | M | 方式 |
|---|---|---|---|---|---|---|---|
| TC-SRC-01 | 8 WebDAV | 夹具 `propfind_root.xml` | 解析 | 得到子文件夹与音频文件；非音频（.jpg/.txt）不计入歌曲；中文与 % 编码路径正确解码 | P0 | M1 | U |
| TC-SRC-02 | 8 WebDAV | 夹具 `propfind_album.xml` | 解析 | 文件大小、修改时间正确；集合自身（href 与请求同）被排除 | P1 | M1 | U |
| TC-SRC-03 | T-N02 | — | 单测：地址规范化 | `nas.local:5006/music` → `http://nas.local:5006/music/`；`https://` 保留；空格去除；非法地址报「This address doesn’t look right」 | P1 | M1 | U |
| TC-SRC-04 | 7-2 | 真实 Synology WebDAV Server | 添加 → 测试连接 → 保存 | 显示找到的文件夹数；保存后曲库出现歌曲 | P0 | M1 | D |
| TC-SRC-05 | 7-2 / F6 | 错误密码 | 测试连接 | 提示「The server rejected the user name or password.」，不保存 | P1 | M1 | U（401 映射）+ D |
| TC-SRC-06 | 7-3 | 「文件」App 已连 SMB | 选择文件夹 → 选 SMB 上的音乐文件夹 | 扫描完成，曲库出现歌曲 | P0 | M1 | D |
| TC-SRC-07 | 8 FolderSource | 临时目录放 3 个 mp3 名称文件 + 1 个 txt | 单测：枚举 | 只收 3 个音频；子目录递归 | P1 | M1 | U |
| TC-SRC-08 | 10 免费额度 | 免费，已有 1 个来源 | 点 ＋ | 弹付费页，标题「Add as many servers as you like」 | P0 | M1 | A |
| TC-SRC-09 | 10 | 免费，删除唯一来源后 | 再加来源 | 不弹付费页（额度回来） | P1 | M1 | U |
| TC-SRC-10 | 14 隐私 | 保存 WebDAV 来源 | 单测：存储 | 密码只在 Keychain；library.json 与 UserDefaults 里搜不到密码 | P0 | M1 | U |
| TC-SRC-11 | T-N04 | Pro | 加 2 个来源 | 两个来源各自列出，歌曲不串 | P1 | M1 | U |
| TC-SRC-12 | 9 | 拒绝本地网络 | 连局域网地址 | 提示去设置打开本地网络 | P1 | M1 | D |

## 3. 曲库（T-L01–L09、S-I01、S-I03）
| ID | 来源 | 前置 | 步骤 | 预期 | 优先级 | M | 方式 |
|---|---|---|---|---|---|---|---|
| TC-LIB-01 | S-I01 | — | 单测：路径推断 `Miles Davis/Kind of Blue/01 So What.flac` | 艺人 Miles Davis、专辑 Kind of Blue、音轨 1、标题 So What | P0 | M1 | U |
| TC-LIB-02 | S-I01 | — | 单测：`Kind of Blue/02 - Freddie Freeloader.mp3`、`03. Blue in Green.m4a`、`song.mp3` 在根目录 | 去掉序号与分隔；缺失层级用「Unknown Artist / Unknown Album」 | P1 | M1 | U |
| TC-LIB-03 | T-L09 | — | 单测：同名专辑、同艺人来自两个文件夹 | 合并为一张专辑；不同艺人同名专辑不合并 | P1 | M1 | U |
| TC-LIB-04 | T-L01 | 示范库 | 专辑排序 | 专辑按标题排序；专辑内按音轨号 | P1 | M1 | U |
| TC-LIB-05 | T-L03 | 示范库 | 单测：搜索「tide」 | 命中歌名、艺人、专辑任一字段；不区分大小写与变音符号 | P1 | M1 | U |
| TC-LIB-06 | T-L03 | 示范库 | UI：搜索页输入 | 结果按歌曲/专辑/艺人分组出现 | P1 | M1 | A |
| TC-LIB-07 | T-L04 | — | 单测：最近添加 | 按加入时间倒序，最多 12 张专辑 | P2 | M1 | U |
| TC-LIB-08 | 8 存储 | — | 单测：保存→重新加载 | 内容一致；写入为原子写；文件带 schemaVersion | P0 | M1 | U |
| TC-LIB-09 | 8 存储 / DATA | 损坏的 library.json | 加载 | 不崩溃；用备份恢复，没有备份则空库并提示 | P0 | M1 | U |
| TC-LIB-10 | S-I03 | — | 单测：封面存储 | 封面写入 Application Support/Artwork，按专辑键去重；重复写同一张不增加文件 | P1 | M1 | U |
| TC-LIB-11 | T-L08 | 曲库含 .wma | 单测：可播放判定 | .wma 标为不可播放；mp3/m4a/flac/wav/aiff/alac(m4a)/caf 可播放 | P1 | M1 | U |
| TC-LIB-12 | 8 Enricher | 示范库 | 单测：读取内嵌元数据 | 有元数据时覆盖推断值；无则保留推断 | P1 | M1 | U |
| TC-LIB-13 | 6 | 示范库 | UI：专辑页 | 显示专辑标题、艺人、曲目列表、「Play」「Shuffle」「Download」 | P1 | M1 | A |
| TC-LIB-14 | 6 | 示范库 | UI：艺人页 | 显示该艺人的专辑 | P2 | M1 | A |

## 4. 播放（T-P01–P06、T-P10、S-I02）
| ID | 来源 | 前置 | 步骤 | 预期 | 优先级 | M | 方式 |
|---|---|---|---|---|---|---|---|
| TC-PLY-01 | T-P01 | — | 单测：队列 | 从第 3 首开始播放：队列为 3…n；下一首/上一首正确；播放超过 3 s 时「上一首」回到本曲开头 | P0 | M1 | U |
| TC-PLY-02 | T-P02 | — | 单测：随机 | 随机一轮内不重复，且当前曲排第一 | P1 | M1 | U |
| TC-PLY-03 | T-P04 | 播放中 | 锁屏、控制中心 | 显示标题/艺人/封面/进度；播放暂停上下首有效 | P0 | M1 | D |
| TC-PLY-04 | S-I02 | 播放中 | 来电后挂断 / Siri 打断 | 中断结束且系统允许恢复时自动继续；音量不变 | P0 | M1 | U（中断处理逻辑）+ D |
| TC-PLY-05 | T-P04 | 戴耳机播放 | 拔耳机 | 暂停 | P1 | M1 | U（路由变化逻辑）+ D |
| TC-PLY-06 | S-I02 | — | 单测：卡住检测 | 等待状态持续 >8 s 触发重连，重连后 seek 回原位置；1 首最多重连 3 次后跳下一首并提示 | P1 | M1 | U |
| TC-PLY-07 | T-L08 | 队列第 2 首不可播放 | 顺序播放 | 跳过并提示「Skipped a song this iPhone can’t play」 | P1 | M1 | U |
| TC-PLY-08 | T-P01 | 正在播放页 | 打开队列，拖动、左滑删除 | 顺序与删除生效 | P2 | M1 | M |
| TC-PLY-09 | T-P06 | Pro | 睡眠定时 15 分钟 | 到时淡出暂停；「本曲结束」在曲末暂停 | P2 | M1 | U |
| TC-PLY-10 | T-P06 / 10 | 免费 | 点睡眠定时 | 弹付费页 | P1 | M1 | A |
| TC-PLY-11 | T-P10 | 有 AirPlay 设备 | 点路由按钮 | 系统路由选择器出现 | P2 | M1 | D |
| TC-PLY-12 | 6.1-9 | 播放中 | UI：正在播放页 | 唱片随播放转动；进度环随时间增长；暂停时停转 | P1 | M1 | A（截屏）+ M |
| TC-PLY-13 | 6.1-9 / F12 | 开「减少动态效果」 | 正在播放页 | 唱片静止，只显示进度环 | P2 | M1 | M |
| TC-PLY-14 | T-P02 | — | 单测：循环模式 | 列表循环在末尾回到第 1 首；单曲循环重复当前曲 | P1 | M1 | U |

## 5. 离线（T-O01、T-O02）
| ID | 来源 | 前置 | 步骤 | 预期 | 优先级 | M | 方式 |
|---|---|---|---|---|---|---|---|
| TC-OFF-01 | T-O01 | 示范库 | 专辑「Download」 | 下载队列串行连续完成；每首显示已下载标记 | P1 | M1 | U（队列逻辑）+ A |
| TC-OFF-02 | 8 | 已下载 | 单测：播放地址 | 优先本地文件 | P0 | M1 | U |
| TC-OFF-03 | T-O01 | 已下载专辑 | 飞行模式播放 | 正常播放 | P0 | M1 | D |
| TC-OFF-04 | 10 | 免费，已下载 20 首 | 下载第 21 首 | 弹付费页；已下载的 20 首不受影响 | P0 | M1 | U+A |
| TC-OFF-05 | 10 | — | 单测：下载失败 | 失败不计入 20 首额度 | P1 | M1 | U |
| TC-OFF-06 | T-O02 | 已下载 | 来源详情 → 清除离线 | 显示释放空间；额度回来 | P1 | M1 | U |

## 6. 歌单（T-Y01）
| ID | 来源 | 前置 | 步骤 | 预期 | 优先级 | M | 方式 |
|---|---|---|---|---|---|---|---|
| TC-PL-01 | T-Y01 | — | 新建歌单并加入 3 首 | 歌单出现 3 首，顺序保持 | P1 | M1 | U+A |
| TC-PL-02 | 10 | 免费，已有 2 个歌单 | 新建第 3 个 | 弹付费页 | P0 | M1 | U+A |
| TC-PL-03 | T-Y01 | — | 删除歌单内某曲 / 删除歌单 | 生效；不删曲库里的歌 | P1 | M1 | U |
| TC-PL-04 | 8 | 来源被删 | 歌单里的该来源歌曲 | 从歌单移除，不崩溃 | P1 | M1 | U |

## 7. 内购（10、铁律 4）
| ID | 来源 | 前置 | 步骤 | 预期 | 优先级 | M | 方式 |
|---|---|---|---|---|---|---|---|
| TC-IAP-01 | 铁律 4 | 免费 | 从 5 个入口打开（第 2 来源、第 3 歌单、第 21 首离线、睡眠定时、设置 Pro 卡） | 都先弹同一付费页：标题随原因变、列出 Pro 每一项、价格来自 StoreKit（取不到不显示数字）、「Unlock」「Restore Purchases」 | P0 | M1 | U（原因→标题）+ A |
| TC-IAP-02 | 10 | 本地 StoreKit | 购买 | 付费页关闭，限制全部解除，设置显示「Spindle Pro is unlocked」 | P0 | M1 | M |
| TC-IAP-03 | 10 | — | 恢复购买（无购买记录） | 提示「No previous Pro purchase was found for this Apple ID.」 | P1 | M1 | M |
| TC-IAP-04 | 10 | — | 代码审查 grep `.purchase(` | 只出现在 ProStore | P0 | M1 | U（静态检查脚本） |
| TC-IAP-05 | 10 | — | 单测：免费额度规则 | 来源 1、歌单 2、离线 20；Pro 无限 | P0 | M1 | U |
| TC-IAP-06 | 10 | 断网 | 打开付费页 | 显示「The App Store isn’t reachable right now…」与重试，不显示假价格 | P1 | M1 | M |
| TC-IAP-07 | 10 | 退款 | 回 App | Pro 失效；超额来源保留但不能新增 | P1 | M1 | U |
| TC-IAP-08 | 10 | 沙盒账号 | 真机购买 | 成功 | P0 | M1 | D |

## 8. 好评引导（11、铁律 13）
| ID | 来源 | 前置 | 步骤 | 预期 | 优先级 | M | 方式 |
|---|---|---|---|---|---|---|---|
| TC-RVW-01 | 11 | 安装 ≥3 天（注入时钟） | 第 10 首完整播完 | `shouldAsk` 为真 | P0 | M1 | U |
| TC-RVW-02 | 11 | 首次扫描完成 ≥100 首 | — | `shouldAsk` 为真 | P1 | M1 | U |
| TC-RVW-03 | 11 | 安装 <3 天 / 30 天内问过 / 刚出错 / 付费页开着 | 触发条件 | 都不弹 | P0 | M1 | U |
| TC-RVW-04 | 11 | 卡片出现 | 点「Love it」 | 调用系统评分（替身记录 1 次） | P0 | M1 | U |
| TC-RVW-05 | 11 | 卡片出现 | 点「Not yet」 | 生成 mailto，含版本号，不含地址/账号 | P1 | M1 | U |
| TC-RVW-06 | 11 | — | 设置 → 「Rate Spindle」 | 存在 `action=write-review` 链接 | P1 | M1 | A |
| TC-RVW-07 | 11 红线 | — | grep | 无自绘星星、无评论换奖励 | P0 | M1 | U（静态检查脚本） |

## 9. 分享（12、铁律 10）
| ID | 来源 | 前置 | 步骤 | 预期 | 优先级 | M | 方式 |
|---|---|---|---|---|---|---|---|
| TC-SHR-01 | 12 | 示范库 | 首屏分享 | 生成 1080×1350 图，含 Spindle 名、来源数/专辑数/歌曲数 | P0 | M1 | U（渲染尺寸）+ A |
| TC-SHR-02 | 12 | 有 WebDAV 来源 | 单测：卡片文字 | 不含任何来源名、主机名、路径 | P0 | M1 | U |
| TC-SHR-03 | 12 | 播放中 | 正在播放页分享 | 「正在听」卡含曲名与艺人 | P1 | M1 | A |
| TC-SHR-04 | 9 | — | 存到相册被拒 | 提示去设置；分享面板仍可用 | P2 | M1 | M |

## 10. 设置与多语言（6、铁律 7、15）
| ID | 来源 | 前置 | 步骤 | 预期 | 优先级 | M | 方式 |
|---|---|---|---|---|---|---|---|
| TC-SET-01 | 铁律 7 | — | 首屏齿轮 | 1 次点击进设置；Pro 卡片下第一行是「Language」 | P0 | M1 | A |
| TC-SET-02 | 铁律 7 | — | 选日本語 | 立即全 App 变日语，不跳系统设置；重启后保持 | P0 | M1 | A |
| TC-SET-03 | 6 | — | 设置各行 | Language、Pro、Sources、Rate、Feedback、Privacy、About 均可进入并返回 | P1 | M1 | A |
| TC-L10N-01 | 铁律 7 | — | CI 覆盖率闸门 | 10 语言 × 全部 key 已翻译，占位符一致 | P0 | M1 | U（CI） |
| TC-L10N-02 | 铁律 7 | de / zh-Hant / ja | CI 截屏 | 主要页面无截断、无方框字 | P0 | M1 | A+M |
| TC-L10N-03 | 铁律 7 | — | InfoPlist 字符串 | `NSLocalNetworkUsageDescription`、`NSPhotoLibraryAddUsageDescription`、显示名 10 语言 | P0 | M1 | U（CI） |

## 11. 系统与合规（审计九面）
| ID | 来源 | 步骤 | 预期 | 优先级 | M | 方式 |
|---|---|---|---|---|---|---|
| TC-SYS-01 | 铁律 9 | 检查工程 | `TARGETED_DEVICE_FAMILY=1`、只竖屏、后台模式只有 audio | P0 | M1 | U（脚本） |
| TC-SYS-02 | 18 | 检查 PrivacyInfo.xcprivacy | 存在；声明 UserDefaults 访问原因 | P0 | M1 | U（脚本） |
| TC-SYS-03 | 18 | 代码审查 | 除用户 NAS 与 App Store 外无网络请求；无分析 SDK | P0 | M1 | U（脚本 grep URL 常量） |
| TC-ERR-01 | F6 | 单测：错误映射 | 401/403/404/超时/证书错误/离线各有具体文案与出路 | P1 | M1 | U |
| TC-LIFE-01 | 生命周期 | 扫描中删除来源 | 扫描停止，不崩溃，不残留该来源歌曲 | P1 | M1 | U |
| TC-LIFE-02 | 生命周期 | 空曲库、单曲专辑、超长曲名（300 字） | 不崩溃，长名截断 | P1 | M1 | U+A |
| TC-STORE-01 | 文案一致 | 商店描述每条卖点 | 在 App 内可达 | P1 | M1 | M |

## 12. UX 通用（factory 03-UIUX）
| ID | 步骤 | 预期 | 优先级 | 方式 |
|---|---|---|---|---|
| TC-UX-01 | 动态字体 AX5 走首屏、专辑页、设置 | 不溢出关键文字 | P0 | A（截屏）+ M |
| TC-UX-02 | 深浅色各截首屏、正在播放 | 两套都调过，正文对比度 ≥4.5:1 | P1 | A+M |
| TC-UX-03 | 所有按钮触控区 | ≥44pt | P1 | M |
| TC-UX-04 | 首屏骨架与已有 App 并排 | 原型/字体/形状/图形语言/首屏结构 ≥3 项不同 | P1 | M |
| TC-CRASH-01 | UI 巡游 + 连点（每页快速点 10 次） | 0 崩溃 | P0 | A |

## 覆盖核对
- 对照表 ＝/↑ 行（M1 范围）→ 均有用例；M2/M3 行在对应里程碑补。✕ 行为「平台不适用/偏离主线」，无合规风险，不需证明没做。
- 免费/Pro 表每行 → 超限弹付费页（TC-SRC-08、TC-PL-02、TC-OFF-04、TC-PLY-10）+ Pro 生效（TC-SRC-11、TC-IAP-02、TC-IAP-05）。
- 统计由 `scripts/tc_report.py --stats` 计算，写入 `qa/TC-RESULT-<build>.md` 头部。
