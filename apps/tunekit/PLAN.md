# TuneBench / 调音节拍器 — 调音器 + 节拍器 + 和弦音阶练习

> 2026-09-05 立项(用户当日批准)。目录 `apps/tunekit`,applicationId `com.noobclaw.tunekit`,包名 `tunekit`。
> 显示名:英文 **TuneBench**、中文 **调音节拍器**。原拟名「TuneKit」经 iTunes Search 实查已被 `TuneKit`(Truck and Toolbox LLC,$0.99,Music)占用,故改用 TuneBench(实查无同名);中文「调音节拍器」无精确同名(最近的是「调音器, 节拍器」/「节拍器-调音器&…」,均非同名)。目录与 applicationId 按任务书保留 `tunekit`。
> 内购产品 ID 按 PIPELINE 2026-08-31 修订走 `<applicationId>.pro_unlock` = `com.noobclaw.tunekit.pro_unlock`(new_app.mjs 自动替换;任务书里写的裸 `pro_unlock` 已被 remcard 占用,App Store 全账号唯一,不能复用)。

## 差异化楔子(G2)

**TonalEnergy 是给专业人士的 $6.99 全能表盘,TuneBench 是给练琴的人的:调准、打拍、把和弦弹对,还替你记着今天练了多久。**
美区付费榜 TonalEnergy Tuner & Metronome 长期在位(实查 $6.99,任务书记 #4 $3.99),证明「调音器+节拍器」有人付费;但它英文界面、功能堆叠、没有练习记录。我们的位置:① **中文优先**双语界面;② **一次性 $3.99 买断**(对标价一半);③ **练习记录**(每工具分钟数、音准命中率、连续天数)——这是竞品全部缺失、而练琴的人真正会回头看的东西;④ 「弹奏检查」把和弦字典从「看」变成「练」。硬承诺:零联网权限、麦克风只在测音时打开、不录音。

## 参考实现分析(spec-then-rewrite)

克隆到 `_ref/`(git-ignored),只读设计,**未复制任何非宽松许可的代码**:

| 参考 | 许可 | 学到什么 | 我们怎么做 |
|---|---|---|---|
| `patzly/tack-android`(核心在 `core/.../metronome/MetronomeEngine.kt`、`audio/AudioEngine.kt`) | **GPL-3.0**(文件头明示)→ 只读思路,零复制 | ① 节拍时刻用**绝对时间累加**(`nextScheduleTime += interval`,`postAtTime`)而非相对 `postDelayed`,避免 handler 抖动累积成漂移;② 音频流**预热常驻**(`warmUp`/60 s 延迟关流)避免每拍重开流的首拍延迟;③ 有**延迟校准**(LatencyDialog)承认视觉/触觉与声音不同步;④ 音频焦点丢失即停;⑤ 每 tick 的类型(强/弱/细分)按 `tickIndex % (beats×subdivisions)` 派生。 | 更进一步:把**排程放进音频渲染回调本身**——每个输出采样有绝对下标,`nextTick`(double)按精确采样间隔累加,tick 到点即在流里合成 click。时间源=音频时钟,连 handler 都不经过。Tick 事件携带 `dueMs`(渲染点距扬声器还有多远),Dart 侧按它延迟点灯,不做校准弹窗。 |
| `ZaneH/piano-trainer`(MIT) | MIT | ① 练习模式拆成「音阶 / 三和弦 / 七和弦 / 五度圈」,每题一个目标;② 键盘高亮=目标音,弹对逐个点亮,全对进下一题;③ 和弦由「音阶内隔三度取音」派生而非查表;④ 五度圈顺序作根音选择。 | 采用「目标音逐个点亮」的检查 UX(逐弦 / 逐音 / 顺序音阶)与随机训练的题型思路(看音认名 / 看名认音);和弦不从音阶派生而用半音公式(更通用,覆盖 sus/alt)。未复制代码(它是 React/TS,我们是 Dart)。 |
| `tonaljs/tonal`(`packages/chord-type/data.ts`、`scale-type/data.ts`) | 仓库**无许可证文件**(pub 元数据声称 MIT,但源码树里没有 LICENSE)→ 按无许可对待,零复制 | ① 字典格式=「音程串 + 全名 + 别名」;② 和弦扩展音程>八度(9=14 半音)以保留声部意义;③ 音阶/和弦共用同一套音程→音级换算;④ 覆盖面:三和弦/七和弦/扩展/挂留/五声/调式/异域音阶。 | `music/theory.dart` 自写:每条目=半音偏移数组(公式本身就是乐理常识:大三度 4、纯五度 7…),配 zh+en 名与符号;精选 28 种和弦 + 20 种音阶(练习向,不收 alt 爵士堆叠);`degreeLabel`/`scaleDegreeLabel` 自写。 |
| YIN(de Cheveigné & Kawahara 2002,JASA) | 论文 | 差分函数 → 累积均值归一化(CMND)→ 绝对阈值取**第一个**低于阈值的谷(抗次谐波/低八度误判)→ 抛物线插值到亚采样。 | `pitch/yin.dart` 按论文 1–5 步自写(第 6 步「最佳局部估计」用 RMS 门限 + tracker 滞回替代)。**不用 aubio(GPL)**,无 FFT 依赖。 |

## 招牌功能架构评审(G2)

| 关键机制 | 选型 | 为什么不是另一种 |
|---|---|---|
| **节拍器计时** | **自家平台通道 + 原生音频流内序列器**:Android `AudioTrack`(MODE_STREAM、float PCM、LOW_LATENCY)由专用线程持续写 256 帧块;iOS `AVAudioEngine` + `AVAudioSourceNode` 渲染回调。两端同一套算法:输出帧绝对下标 `pos`,`nextTick += sr·60/bpm/subdiv`(double,不累积舍入),到点把 click 语音压入混音;click 由公式合成 `g·sin(2πft)·e^(−t/τ)`,零采样资源。参数改动原子读取、下一拍生效、相位保持。 | **不用 Dart Timer**(PIPELINE G2 明令;Timer 在后台/低功耗下抖动 10–50 ms)。**不用 flutter_soloud**:它靠 C++ 编译 + FFI,iOS 走 CocoaPods 与本仓「不提交 Podfile/SPM 优先」的约束相抵,且其 API 是「播放采样」而非「按采样排程」,仍需自己实现序列器;自家通道 ~600 行 Kotlin+Swift,完全可控,并顺带承载麦克风与权限。 |
| **后台走拍** | Android:AudioTrack 在 Activity 停止后照常输出(进程存活即走)。iOS:`UIBackgroundModes: audio` + `.playback` 会话 → 锁屏继续。 | Android **未做前台服务**(v1 限制):系统在内存压力下杀进程则节拍停;写进「已知未做」。iOS 的 audio 后台模式有正当理由(节拍器=可听内容),Info.plist 注释与 ASC 审核备注均说明。 |
| **音高检测** | YIN(自写 Dart),44.1 kHz 单声道,窗 W=2048 + τmax=1470(30 Hz)→ 每次分析约 3M 乘加,跑在**独立 isolate**(`PitchWorker`),每 2048 样本分析一次(~21 次/s,≈46 ms 一帧)。tracker:三点中值去尖刺、音分指数平滑、8 帧保持、3 帧稳定判定、RMS 门限区分「静音 / 太小 / 跟踪」。 | 延迟预算:采集块 46 ms + 分析 <10 ms + 60 Hz 绘制 ≈ **60–80 ms**(<100 ms 目标)。不做 FFT/自相关变体是因为 YIN 的「第一个谷」天然抗八度误判,对拨弦乐器实测友好。 |
| **麦克风采集** | Android `AudioRecord`(UNPROCESSED 可用则用之,否则 VOICE_RECOGNITION,绕开 AGC/降噪);iOS `AVAudioEngine.inputNode` tap,会话 `.playAndRecord` + `.measurement` 模式(关闭语音处理链)。2048 float 一块经 EventChannel(Float32List)送 Dart。 | 不用 `record`/`mic_stream` 等插件:它们多为文件录制导向、iOS 端也要 CocoaPods;自家通道已在写。 |
| **权限流程** | 通道方法 `micStatus/micRequest/openSettings`。Android 用 `shouldShowRequestPermissionRationale` + 「已问过」标记区分 denied/permanentlyDenied;iOS 只问一次,denied 直接映射 permanentlyDenied。 | 详见下「权限流程评审」。不用 permission_handler:少一个原生依赖,也免去 ITMS-90683 误编入风险。 |
| **中断处理** | Android 音频焦点 LOSS/LOSS_TRANSIENT → 停节拍 + 事件;iOS 中断通知 → 停麦克风与节拍 + 事件;耳机拔出(输入格式变)→ 停麦克风 + 事件,Dart 提示一键重开。App 切后台 → **立即关麦克风**(隐私),节拍照走。 | 09-04 审计教训:耳机断开麦克风静默死掉。所有中断都变成页面上可见的一句话 + 按钮。 |
| **持久化** | 壳 `JsonFileStore`(原子写、序列化、坏文件旁置)存一份 `tunekit.json`:Pro 标志、A4、乐器、BPM/拍号/细分、练习日志(按日)。秒级计时用 15 s 批量写 + 切后台 flush。 | 每字段防御式读取,类型不对只丢该项不丢日志。 |

## 权限流程评审(G2,禁止静默失败)

| 权限 | 用途 | 请求 | 拒绝 | 永久拒绝 |
|---|---|---|---|---|
| `RECORD_AUDIO` / `NSMicrophoneUsageDescription` | 调音器与弹奏检查测音高 | 调音页首屏 GuidanceCard「允许麦克风」按钮(不自动弹);已授权则切到调音页自动开始 | 页面红卡 + 原因 + 「允许麦克风」重试 | 页面红卡 + 「去系统设置」按钮(`openSettings`),回到前台自动重查状态并开始 |
| `INTERNET` | **不申请**,`tools:node="remove"` 剥离 | — | — | — |
| 音频输出 | 节拍器 | 无需权限;打不开输出时页面横幅报错 | — | — |

麦克风在:离开调音页(切 tab)、弹奏检查页关闭、App 切后台/失活 时**立即关闭**。

## 功能清单(v1 = M1,可上架质量)

**免费层(必须真可用)**
- 半音调音器:大表盘(−50…+50 音分,±5 绿区)、音名+八度、音分、频率、输入电平;A4 430–450 可调;状态:未开始 / 等待声音 / 太小 / 偏低 / 偏高 / 准了。
- 节拍器:30–300 BPM,滑杆 + ±1(长按 ±10)+ 打拍测速 + 常用速度;2/4、3/4、4/4;四分、八分细分;第一拍重音;拍点灯按 `dueMs` 延迟对齐声音。
- 和弦与音阶:5 种类型(大三、小三、属七;大调;小调五声)× 12 根音,音级标注,指板 / 键盘图,吉他与尤克里里自动推导指法,弹奏检查,随机训练。
- 练习记录:今日分钟数、连续天数、最近 7 天柱状图(按工具堆叠)、音准命中率折线、训练正确率。

**Pro(一次性买断 $3.99)**
- 吉他 / 尤克里里 / 小提琴 / 贝斯预设,每根弦一个按钮(自动识别 + 手动固定目标)。
- 6/8 拍号(重音 1、4);三连音、十六分细分。
- 完整字典:28 种和弦 + 20 种音阶/调式。
- 练习记录不限天数,30 天视图。

每个门都走 `lib/tool/pro.dart` `showProSheet(context, reason:)`;`grep buyPro(` 只命中 pro.dart 与 core/purchase.dart。

## 页面结构

1. **调音**(首页 tab)— 渐变 hero:表盘 + 大音名 + 音分 / 状态胶囊 / 频率 + 电平条;权限 / 错误引导卡;乐器 chip(Pro 锁);弦按钮(点选固定,点亮=检测到/准了);A4 步进卡。
2. **节拍** — 渐变 hero:拍点灯 + 96pt BPM + 意大利速度术语 + 滑杆 + 打拍 / 大播放键 / 拍号细分摘要;拍号 chip、细分 chip、常用速度;系统中断横幅。
3. **练习** — 随机训练入口 hero;根音 12 chip;图示乐器 chip;和弦 / 音阶分段;按组分卡列表(PRO 徽标)。→ **详情页**(音级 chip、指板 / 键盘图、指法简写与省略音提示、「弹奏检查」)→ **弹奏检查页**(实时音名 + 音分、逐弦 / 逐音清单、通过卡片)。→ **随机训练页**(10 题、进度、得分、答案反馈、总结)。
4. **记录** — 今日分钟 + 连续天数 hero;7 天 / 30 天切换(30 天 Pro 锁);堆叠柱状图;音准折线;统计瓦片;空状态引导卡。
5. **设置**(壳)— 解锁 Pro(商店价)、恢复购买、语言、隐私、关于。

## 技术要点

- `music/theory.dart`:音名 / 频率 / MIDI 换算,和弦 & 音阶字典,`RootedPattern`(根音 + 类型 → 音名、音级、MIDI)。
- `music/voicing.dart`:指法推导(见文件头算法说明),对 C/G/D/E/A/Am/Em/Dm/G7/C7/E7/A7/D7/B7/Cmaj7/Am7 与教材一致,Ab → 466544、Bbm → x13321 等横按;测试穷举 28 类型 × 12 根音要求三和弦与四音和弦不缺音(五度除外)、根音必响。
- `music/metronome_math.dart`:间隔 / tick 类型 / 采样位置 / 打拍中值估速 / click 公式,与原生序列器同公式,单元测试锁定。
- `pitch/yin.dart` + `pitch_tracker.dart` + `pitch_worker.dart`:见上。
- `audio_bridge.dart` ↔ `AudioBridge.kt` / `AudioBridge.swift`:通道契约写在 Dart 文件头。
- iOS:`AudioBridge.swift` 已登记进 `project.pbxproj`(PBXBuildFile/FileReference/Sources);`InfoPlist.strings`(en、zh-Hans)登记为 PBXVariantGroup,`knownRegions` 加 zh-Hans;`TARGETED_DEVICE_FAMILY = 1`;仅竖屏;`UIBackgroundModes: audio`。
- Android:`screenOrientation="portrait"`,`RECORD_AUDIO`,`INTERNET` 剥离,`microphone required=false`(节拍器无麦也可用)。
- 依赖:壳自带 `in_app_purchase` + `path_provider`;**无其它插件**。

## iOS 差异(G3 平行检查)

| 项 | Android | iOS |
|---|---|---|
| 权限说明 | manifest RECORD_AUDIO | `NSMicrophoneUsageDescription`(Info.plist 英文 + zh-Hans.lproj 中文,说明用途) |
| 永久拒绝 | rationale=false 判定 → 去设置 | `.denied` 即永久 → 去设置 |
| 平台通道 | AudioBridge.kt | AudioBridge.swift(同契约,已入 pbxproj) |
| 显示名 | values / values-zh | CFBundleDisplayName + InfoPlist.strings |
| 后台 | AudioTrack 进程存活即走 | UIBackgroundModes audio |
| 采样率 | 固定 44100 采集 | 跟随输入格式(48 k 常见),Dart 侧用返回值建检测器 |
| 中断 | 音频焦点 | 中断通知 + 路由变化 + 引擎配置变化 → 重建引擎保相位 |
| 横屏 | manifest portrait | UISupportedInterfaceOrientations 仅 Portrait |

## 定价

**免费 + Pro 一次性买断 $3.99**(PIPELINE 标准工具档;对标 TonalEnergy $6.99 的约 1/2)。商店价由 `ProPriceText`/`PurchaseService.price` 下发,UI 只在商店未响应时显示 `$3.99` 兜底,不写 ¥。

## 本地验收(G4)

- `flutter analyze`:**0 issues**。
- `flutter test`:**54 passed**(YIN 合成正弦 / 含泛音低音 / 噪声 / 静音;音名映射与 A4 偏移;tracker 滞回;和弦音阶派生;指法穷举;节拍数学、打拍、click;各页面 widget 测试含 Pro 门与权限引导)。
- 未本机 build(8 GB 机器禁令),出包走 CI。

## G8a 提审前自审(2026-09-05,写码后立即做的一轮;正式提审前须再做一轮)

已查并修:
- ① 购买流:`grep buyPro(` 仅 pro.dart / core/purchase.dart;每个门(乐器预设、6/8、三连音/十六分、锁定字典项、30 天记录、设置页 Pro 行)都开 `showProSheet`;恢复购买在弹层与设置页;Pro 由 `onUnlocked → store.unlockPro()` 持久化;兜底价 USD。
- ② iOS:mic usage 中英双语且说明用途;device family 1;仅竖屏;后台模式仅 audio 且有正当理由;Swift 文件已入 pbxproj。
- ③ Android:权限声明、永久拒绝出口、INTERNET 剥离、portrait。
- ④ 语言:全部 `tr(zh:, en:)`,`supportedLocales` 只 en/zh(壳 ja 已去掉),无 ja 选项。
- ⑤ 错误可见:麦克风打不开 / 被占用 / 被中断 / 音频输出失败 / 读取错误 都有页面文案 + 重试或去设置按钮;无静默 catch(仅 debugPrint 兜底的地方都同时更新 UI 状态)。
- ⑥ 数据安全:零联网;JsonFileStore 原子写;字段逐个防御读取;写前必先读(`loaded` 门)。
- ⑦ 崩溃项:空记录 → 引导卡;drill 双击 → `_chosen != null` 拦截;计时器全部在 stop/dispose 取消;controller 销毁后不再 notify;IndexedStack 下调音页切 tab 关麦克风。
- ⑧ 商店文案 vs 实现:listing.md / appstore.md 每条卖点对应功能均存在(逐条核过:预设 4 种、拍号 4 种、细分 4 种、字典 48 类型、7/30 天、弹奏检查、随机训练、A4 430–450);未提其它平台名。

## 真机验收清单(G7,请照着点)

1. 首次打开 → 调音页显示「允许麦克风」引导卡(不自动弹);点它 → **系统权限弹框**。
2. 允许 → 弹吉他 E2 弦:1 秒内出现音名 E2、指针摆动;拧弦看指针连续变化,进 ±5 音分变绿、胶囊显示「准了」。
3. 拒绝 → 红卡「麦克风没有在听」+ 重试;再拒(Android 二次 / iOS 一次)→ 卡片变「去系统设置」,点它跳到本 app 设置页;打开权限回到 app 自动开始。
4. 唱一个音或吹口哨(纯音)→ 仍能跟踪;安静时显示「弹一根弦…」,轻声时「声音太小」。
5. 切到节拍 tab → 调音的麦克风指示(iOS 橙点 / Android 绿点)应消失。
6. 节拍器 60 / 120 / 240 BPM 各听 30 s 与另一台设备的节拍器对拍,不漂;拍点灯与声音同步(容差 ≤ 一帧)。
7. 播放中改 BPM / 拍号 / 细分 → 下一拍生效不卡顿;6/8 时 1、4 拍重音。
8. 锁屏 → 节拍继续(iOS、Android 各试 2 分钟);来电 / Siri → 停止并显示横幅。
9. 练习 → 点「Cdim」→ Pro 弹层(显示商店价,沙盒可购);恢复购买给出结果文案。
10. 打开「C」→ 指法 x32010 →「弹奏检查」→ 从 6 弦到 1 弦逐根弹 → 逐弦打勾并显示音分;全对 → 通过卡片;记录页「弹奏检查通过」+1。
11. 记录页:调音 1 分钟后回来,今日分钟数与柱状图有值;跨午夜后再看,日期滚动。
12. 深色 / 浅色各看四个 tab 与详情、检查、训练页,无看不清的文字。

## 已知未做(写清楚,别当没看见)

- **Android 前台服务未做**:节拍器在系统杀进程时会停(通常需长时间锁屏 + 内存压力)。需要时加 `FOREGROUND_SERVICE_MEDIA_PLAYBACK` + 通知,属 v1.1。
- **麦克风与节拍同时用**(iOS):切换会话类别会重建节拍引擎(相位保持),但可能有一次 ~50 ms 的间隙;真机验证。
- **视觉与声音的对齐**只靠 `dueMs`(渲染提前量),未加输出延迟校准;Android 蓝牙耳机下灯可能比声音早 100–200 ms。
- **指法为自动推导**:常见开放 / 横按和弦与教材一致,但九和弦以上会省略一个音(详情页会标出省略了哪个);无「多种指法」切换。
- **弹奏检查按音高类匹配**,不判定实际按的是哪根弦(同音异弦 ±12 半音内取最近);扫弦整体不支持,须逐弦。
- 日语等第三语言未做(壳规则:无 `ja:` 字符串就不提供选项)。
- 小提琴 / 贝斯只有调音预设,没有指板图(键盘图代替)。
