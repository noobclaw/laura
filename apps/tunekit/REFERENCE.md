# TuneBench — 参考保真审计(PIPELINE G8c)

审计日期 2026-09-12。原仓均在 `D:\toolapp\_ref\`。本文按 G8c 规则:核心函数级清单 → 逐条「一致 / 有意偏离(产品理由)/ 漏掉→已补」→ 对照测试。

## 汇总

| 参考 | 许可 / 处理方式 | 函数/表项 | 一致 | 有意偏离 | 漏掉→已补 | 剩余 |
|---|---|---|---|---|---|---|
| `patzly/tack-android`(节拍器) | **README 标 GPL-3.0、源码树无 LICENSE 文件、每个文件头写 GPL** → 按 copyleft/无许可对待:**只读、只写规格、按规格重写,未复制任何一行代码,未使用其任何音频/图形资源** | 14 | 6 | 6 | 2 | 0 |
| `ZaneH/piano-trainer`(练习逻辑) | MIT(`LICENSE.md`)→ 可对照移植 + 署名(关于页 / listing 已署) | 9 | 4 | 5 | 0 | 0 |
| `tonaljs/tonal`(乐理权威) | MIT(`packages/*/LICENSE`;PLAN.md 旧记录「无许可证」已纠正)→ 字典自写,tonal 音程串抄进测试作期望值,署名 | 48 表项 + 6 函数 | 48 + 3 | 3 | 1(dim7 音级标签)| 0 |
| YIN(de Cheveigné & Kawahara 2002;pitchfinder / aubio 实现规格) | 论文 / 规格 | 8 | 6 | 2 | 0(原缺项已在 09-05 实现,本次补对照测试)| 0 |

对照测试:`test/theory_tonal_test.dart`(48 条逐条断言音程集合 == tonal、符号 ∈ tonal 别名、音级数字 == tonal 音程数)、`test/pitch_test.dart`(抛物线插值 / 首谷抗次谐波 / 阈值区间 / 缓冲长度)、`test/metronome_math_test.dart`(tap tempo 按 Tack 规则 7 例)。`flutter analyze` 0 issue,`flutter test` 143 passed。

---

## 一、tack-android(节拍器)

原仓入口:`core/.../metronome/MetronomeEngine.kt`(排程)→ `audio/AudioEngine.kt`(Oboe 桥)→ `core/src/main/cpp/oboe_audio_engine.cpp`(渲染回调)。tap tempo 只在 `legacy-app/.../TempoDialogUtil.kt`(新 Compose 版尚未移植)。

| # | 原仓函数 / 规格 | 输入 → 输出 / 关键常量 / 边界 | 结论 | 我方实现 |
|---|---|---|---|---|
| T1 | `startTicks.tickRunnable`:`nextScheduleTime += interval; postAtTime(nextScheduleTime)` —— **绝对时间累加**,不用相对 postDelayed;`getInterval() = 60000 / tempo`(**Long 毫秒,整数截断**) | tempo 1..600 | **有意偏离(更严)**:同样是累加绝对位置,但我方以**输出采样**为时间轴,`nextTick`(double)`+= sr·60/bpm/sub`,排程在渲染回调内,不经 Handler;不截断到毫秒(137 bpm 时 Tack 每拍少 0.96 ms,我方零累积误差)。理由:音频时钟比 uptime 更稳,且 Dart/Flutter 侧没有 Handler | `AudioBridge.kt:395-412`(`renderLoop`)、`AudioBridge.swift:353-369`(`Sequencer.render`)、`metronome_math.dart:94-100`(`tickTimeSeconds`/`tickSample` 镜像 + 测试「tick 10 000 无漂移」)|
| T2 | 拍型派生:`beatIndex = tickIndex / subdivisionsCount`;`isBeat = tickIndex % subs == 0`;`isFirstBeat = isBeat && beatIndex % beatsCount == 0`;类型 = `config.beats[beat]` / `config.subdivisions[sub]` | tickIndex Long | **一致**(等价):`kindAt` = `inBar % sub != 0 → sub`,否则 `accents.contains(beat) ? accent : beat`;6/8 重音 {0,3} | `AudioBridge.kt:372-383`、`.swift:363-365`、`metronome_math.dart:78-89`(`tickKindAt`/`beatAt`,测试 4/4 八分 + 6/8)|
| T3 | tempo / 拍号运行中改变:`applyConfig` 只换 `config`,下一次 runnable 用新 `getInterval()`,`nextScheduleTime` 与 `tickIndex` 延续 → **相位保留、下一拍生效** | — | **一致**:`metroUpdate` 只改 volatile 参数,`renderLoop` 每拍读 `bpm/subPerBeat/accents`,`nextTick`/`tickIndex` 不重置 | `AudioBridge.kt:266-272,409`、`.swift:318-325,355`、`metronome_controller.dart:47-60` |
| T4 | 重新开始:`start()` 置 `tickIndex = 0`(从第 1 拍起);路由变化不重开 | — | **一致**:Kotlin 每次 `start` 新线程局部变量归零;Swift `restart()` 归零,`reset(sampleRate:)` 保留 `tickIndex`(路由重建不丢小节位置)| `AudioBridge.kt:395-397`、`.swift:328-343` |
| T5 | 视觉/触觉延迟:`performTick` 把 `_tickEvent` `postAtTime(scheduledTime + appSettings.latency)`,预动画提前 `BEAT_ANIM_OFFSET = 25 ms`;latency 由**用户校准对话框**设定(默认 0) | latency Long ms | **有意偏离**:不做校准 UI;每个 tick 事件携带 `dueMs` = 渲染点距扬声器的时间(Android: `p − playbackHeadPosition`;iOS: 块内偏移 + `outputLatency + ioBufferDuration`),Dart 侧按 `dueMs` 延迟点灯(上限 400 ms)。理由:自动量比让用户手调更省事;代价是 Android 不含 HAL 之后的固定硬件延迟(约 10–40 ms),见「剩余风险」| `AudioBridge.kt:405-407`、`.swift:218-222,367`、`metronome_controller.dart:110-125` |
| T6 | 音频焦点:`AUDIOFOCUS_LOSS → stop()`;`LOSS_TRANSIENT / CAN_DUCK → ducking 0.25`;`GAIN → 1.0`;`ignoreFocus` 开关 | — | **漏掉→已补(部分)**:原来 LOSS 与 LOSS_TRANSIENT 都停,`CAN_DUCK` 完全忽略(通知音期间仍全音量)。本次补 `CAN_DUCK → duck 0.25f`、`GAIN → 1f`,渲染时 `s * duck`。**保留偏离**:`LOSS_TRANSIENT`(来电)仍停止并通知 UI,不像 Tack 那样压低继续 —— 理由:来电中继续打拍是打扰,listing 已承诺「来电时自动停止」 | `AudioBridge.kt:258-259,299,368-378,431` |
| T7 | 流生命周期:`warmUp()` 预开流、`scheduleDelayedStop` 停止后**保留流 60 s**(`STREAM_DELAY_SECONDS`)避免下次首拍延迟;Oboe LowLatency/Exclusive,失败退 Shared | — | **有意偏离**:每次 start 新建 AudioTrack(float + LOW_LATENCY → default → 16-bit 三级退化),stop 即释放。理由:节拍器停了就该彻底放开输出(省电、不占独占流);首拍延迟只是 `play()` 的几十毫秒,用户按下播放键感知不到 | `AudioBridge.kt:274-321`、`.swift:187-231` |
| T8 | 混音:10 路 voice + 偷 voice;**限幅器** `ceiling 0.95`、瞬时 attack、`release 0.0005/样本` | float | **有意偏离**:voice 列表按需增长(最坏 300 bpm × 16 分 = 20 tick/s,click 40 ms → 同时最多 1–2 路),硬 clamp ±1。理由:合成 click 峰值 ≤ 1.0 + 0.8 且从不重叠,限幅器没有触发机会 | `AudioBridge.kt:411-421`、`.swift:371-381` |
| T9 | tick 音色:WAV 资源(wood / mechanical / beatbox …),strong = 2× 抽取升八度、sub = 2× 重复降八度(`adjustPitch`) | FloatArray | **有意偏离**:不带任何音频资源(Tack 的资源也是 GPL),`y(t)=g·sin(2πft)·e^(−t/τ)`,accent 1760 Hz/τ 8 ms/g 1.0、beat 1320/6 ms/0.8、sub 990/6 ms/0.45。三档同样是「强拍更高更响、细分更弱」 | `metronome_math.dart:161-178`、`AudioBridge.kt:384-389`、`.swift:346-351` |
| T10 | tap tempo(legacy `TempoDialogUtil`):`MAX_TAPS = 20` 个间隔取**均值**;`shouldTapReset`:新间隔的 tempo ≥ 均值 tempo × 1.5 或 ≤ × 0.5(`TEMPO_FACTOR 0.5`),或间隔 > 均值 × 3(`INTERVAL_FACTOR`)→ 清空后**把该间隔留作新序列首样本**;`60000 / avg` clamp 到 TEMPO_MIN..MAX | ms Long | **漏掉→已补**:原实现是「最近 6 个取中位数 + 固定 2 s 超时重置」,窗口/统计量/重置规则三项都与规格不一致。已按规格重写(窗 20、均值、±50 % tempo 与 3× 间隔相对重置、异常间隔保留为首样本)。clamp 用我方 30..300 | `metronome_math.dart:116-178`(`TapTempo`),测试 `metronome_math_test.dart` 「tap tempo」组 7 例 |
| T11 | elapsed 计时:`elapsedTime = uptime − elapsedStartTime + elapsedPrevious`,1 s Handler 刷新,stop 不清零(`resetTimerOnStop` 可选) | Long ms | **有意偏离**:不显示本次 elapsed;`Timer.periodic(1 s)` 把播放秒数记入练习账本(按天/按工具聚合)。理由:产品卖点是「练了多久」的跨天记录,不是单次秒表 | `metronome_controller.dart:76-81`、`store.dart addSeconds` |
| T12 | swing:`swing3/5/7` = 细分类型模式 `[BEAT_SUB, MUTED, NORMAL]` / `[…, MUTED, MUTED, NORMAL, MUTED]` / 7 个,本质是「细分中静音若干」 | 模式表 | **有意偏离**:细分只有 4 种固定(♩ ♫ ♪³ ♬),无逐细分静音编辑器。理由:练习向 app 的 UI 只有 4 个 chip;要做 swing 需要 `subMask` 参数 + 编辑 UI,列入 BACKLOG 而非本次补 | `metronome_math.dart:15-27` |
| T13 | count-in / 定时器(bars/seconds/minutes)/ 渐进 tempo / 小节静音训练 / 复节奏 / 歌单分段 | — | **有意偏离**:产品范围外(TuneBench 是「调音+打拍+练和弦」三合一,不是专业节拍器)| — |
| T14 | 线程:tick 用独立 `HandlerThread`;audio 在 Oboe 回调线程 | — | **一致**:专用 `tunekit-metro` 线程 `THREAD_PRIORITY_URGENT_AUDIO`,`WRITE_BLOCKING` 让 AudioTrack 回压定节奏;iOS 在 `AVAudioSourceNode` 渲染块 | `AudioBridge.kt:392`、`.swift:215` |

**版权处理声明**:tack-android 仅按上表的规格重写;未复制其任何代码行、常量表以外的实现、WAV 资源或界面资源。「关于」页与 listing 不署名(copyleft 参考不署名,以免暗示派生关系)。

## 二、piano-trainer(练习逻辑,MIT)

原仓入口:`src/core/services/{scaleService,chordService,noteService}.ts`、`hooks/useNoteProgression.ts`、`components/Quiz/Questions/Questions.ts`。

| # | 原仓函数 | 规格 | 结论 | 我方 |
|---|---|---|---|---|
| P1 | `SCALE_STEPS.Major = w w h w w w h`;natural minor `[0,2,3,5,7,8,10]`;melodic minor `[0,2,3,5,7,9,11]` | 半音 | **一致**(与 tonal 亦一致)| `theory.dart:145-148` |
| P2 | `getTriadChord / getSeventhChord`:在音阶内隔三度取音(index+2, +4, +6),跨八度 +12 | 音阶键 → MIDI[] | **有意偏离**:和弦用半音公式表(28 种),不从音阶派生。理由:派生法只能得到自然音和弦,给不出 sus / 7b9 / maj7#11;半音表已按 tonal 逐条校验 | `theory.dart:112-141` |
| P3 | `useNoteProgression`:目标音顺序上行,弹对 `advanceNote`;到顶回到起点;ping-pong 下行;shuffle 换随机调 | 状态机 | **一致(核心)**:音阶「弹奏检查」严格顺序上行,末尾加高八度主音完成;逐音打勾。ping-pong / shuffle / hard mode(只亮上一个音)未做 —— 有意偏离,练习页一次一个目标 | `practice_page.dart:466-486, 499-513` |
| P4 | 和弦练习:目标 = 该级三和弦全部音同时高亮,任意顺序弹全即进 | — | **一致**:非音阶模式下任意顺序,每个目标音一次;指法模式按弦匹配最近八度(±12)| `practice_page.dart:514-530` |
| P5 | `normalizeNoteName`:一律折到升号(Db→C#…),`getRandomKey` 剔除 E#/B#/Fb | 字符串 | **有意偏离**:根音 {Db, Eb, F, Ab, Bb} 用降号拼写,其余升号(吉他谱惯例);不产生 E#/B#/Fb | `theory.dart:28-30, 184-199` |
| P6 | `CIRCLE_OF_FIFTHS` 顺序作根音选择 | 12 项 | **有意偏离**:根音按半音顺序 12 个 chip。理由:调音/练习用户按字母找根音更快 | `practice_page.dart` 根音选择 |
| P7 | Quiz:`QUIZ_QUESTIONS` 只有两类(某调的五度是什么 / 认调),随机抽;判分对错 | — | **有意偏离**:我方两类题为「看音认名 / 看名认音」四选一,干扰项 = 同根其它类型且音集不同,连对加分(10 + min(10, 2·(streak−1)));10 题一轮。理由:围绕字典条目出题才能把字典变成练习 | `practice_page.dart:786-866` |
| P8 | 判分:MIDI 输入的音 == 目标(忽略八度,`ignoreOctave`)| — | **一致**:按 pitch class 比对(指法模式再按 ±12 找最近弦)| `practice_page.dart:506-527` |
| P9 | `isAdjacentFifth`(原仓 `frontIdx >= length−1` 有 off-by-one,最后一项永不算相邻)| — | 不适用(未用五度圈题型);记录原仓 bug 以免日后照抄 | — |

## 三、tonal(乐理权威,MIT)

原仓:`packages/chord-type/data.ts`(和弦:`"1P 3M 5P"` 音程串 + 全名 + 别名)、`packages/scale-type/data.ts`、`packages/pitch-interval/index.ts`(`SIZES=[0,2,4,5,7,9,11]`、`TYPES="PMMPPMM"`、`qToAlt`:P/M=0、m=−1、A×n=+n、d×n = perfectable −n / majorable −(n+1);半音 = SIZES[step]+alt+12·oct)、`packages/note/index.ts`(`simplify`/`enharmonic`)、`packages/chord/index.ts`(`tokenize`)。

| # | 项 | 结论 | 说明 / 我方 |
|---|---|---|---|
| N1 | **28 个和弦音程集合** | **48/48 一致**(28 和弦 + 20 音阶)| 逐条见 `test/theory_tonal_test.dart`;把 tonal 的音程串抄为期望值,用 Dart 重写 tonal 的音程→半音算法解析,断言 `semitones == tonalSet(...)`。值得记的两处:`11` 和弦 tonal 定义**不含三度**(`1P 5P 7m 9M 11P`),我方同;`aug7` = `1P 3M 5A 7m`(tonal 别名 `7#5 +7 aug7`),我方同 |
| N2 | **20 个音阶音程集合** | **一致** | 含 `blues` = tonal「minor blues」、`dimWH` = tonal「diminished」、`dimHW` = 「half-whole diminished」、`dblHarm` = 「double harmonic major」 |
| N3 | 和弦符号 ∈ tonal 别名 | **一致**(28/28)| 测试逐条断言;大三和弦我方后缀为空(`C`),tonal 无空别名而是 `tokenize("C")` 落到 major,测试以 `M` 代查 |
| N4 | 全名:tonal 把 `1P 3M 5A 7M`(maj7#5)叫「augmented seventh」,`1P 3M 5A 7m` 无全名 | **有意偏离**:我方 `aug7` = `1P 3M 5A 7m` 名「Augmented 7th / 增七和弦」,按 Wikipedia 与吉他谱惯例(C+7 = C E G# Bb);音程集合与 tonal 别名 `aug7` 一致 | `theory.dart:127` |
| N5 | 音级标签(`chord.degrees` / 音程数字):dim7 的第 4 音是 `7d`(bb7) | **漏掉→已补**:原 `degreeLabel(9)` 上下文无关,给 dim7 标成 `6`。加 `IntervalPattern.degrees` 覆盖 + `degreeLabels` getter,dim7 = `['1','b3','b5','bb7']`,详情页改用 `degreeLabels`;测试断言 28 个和弦每个音的音级数字 == tonal 音程数字 | `theory.dart:63-64, 86-98, 125`、`practice_page.dart:265` |
| N6 | 同音异名 `Note.enharmonic / simplify`:按字母距离正确拼写(F#dim7 = F# A C **Eb**;`simplify` 用原音升降号方向)| **有意偏离**:12 个 pitch class 固定拼写(升号表 / 降号表),`kFlatRoots={Db,Eb,F,Ab,Bb}` 决定用哪张表;F#dim7 显示 `D#`。理由:指板/键盘图按 pitch class 画,吉他谱也这么写;严格拼写会出现 Cb/E#/双降号,对学习者反而陌生 | `theory.dart:13-30, 184-199` |
| N7 | `chord.tokenize`(解析「Am7」「C#m7b5」等字符串)| **有意偏离**:不解析用户输入的和弦名,和弦一律从 `RootedPattern(root, pattern)` 构造,`label` 只做拼接 | `theory.dart:189-191` |
| N8 | 音程→半音算法(`pitch-interval.parse`)| **一致**(在测试里重写并用 13 个音程自检)| `theory_tonal_test.dart:13-40` |

署名:关于页(`branding.dart aboutText`)与 `store/listing.md` 中英各加「和弦与音阶字典按 tonal.js(MIT)逐条校验;练习模式参考了 piano-trainer(MIT)」;测试文件头注明 tonal 版权与 MIT。

## 四、YIN(论文 + pitchfinder / aubio 规格)

| # | 规格 | 结论 | 我方 |
|---|---|---|---|
| Y1 | 步骤 1–2 差分函数 `d(τ)=Σ_{j<W}(x[j]−x[j+τ])²`,直接计算 O(W·τmax)(pitchfinder 同;aubio 有 FFT 版)| **一致** | `yin.dart:96-106` |
| Y2 | 步骤 3 CMND:`d'(0)=1`,`d'(τ)=d(τ)·τ/Σ_{1..τ}d` | **一致** | `yin.dart:96,104-105` |
| Y3 | 步骤 4 绝对阈值:取**第一个**低于阈值的 τ,再沿谷下滑到局部最小(pitchfinder: `while yin[τ+1] < yin[τ] τ++`);阈值 论文 0.1、pitchfinder 0.10、aubio(yinfft)默认 0.15 | **一致**(阈值 0.12,在 0.1–0.15 内;拨弦起振略不谐时防八度跳)| `yin.dart:111-120`;测试「absolute threshold picks the first dip」「threshold is in the YIN range」 |
| Y4 | 无谷低于阈值时:pitchfinder 返回 null;aubio 退回全局最小 | **有意偏离(折中)**:退回全局最小但要求 `cmnd ≤ 0.35`,否则 null。理由:音衰减尾段 CMND 抬高但仍是同一周期,tuner 需要多保持几帧 | `yin.dart:121-130` |
| Y5 | 步骤 5 抛物线插值:顶点 `x = (s0−s2)/(2(s0−2s1+s2))`,|shift|<1 | **一致**(等价写法)| `yin.dart:132-144`;测试「parabolic interpolation resolves non-integer periods」(1000 Hz τ=44.1,误差 < 1 音分,整数 τ 会差 3.9 音分)|
| Y6 | 概率 / 置信度 = `1 − d'(τ)`(pitchfinder `probability`)| **一致** | `yin.dart:150` |
| Y7 | 缓冲:W ≥ 2 个最低可测周期(E2 82 Hz → 535 样本 → W ≥ 1070);τmax = sr/minHz | **一致**:W = 2048,τmax = 1470(30 Hz),`requiredSamples = W + τmax = 3518`;测试断言 | `yin.dart:35-46, 68` |
| Y8 | 步骤 6 最佳局部估计(在 ±Tmax/2 邻域重搜更低谷)| **有意偏离**:用 RMS 门限 + tracker 的三点中值 / 8 帧保持 / 3 帧稳定替代。理由:单音调音器不需要逐帧最优,滞回对拨弦更友好 | `pitch_tracker.dart:97-139` |

## 五、剩余风险(非 G8c 阻塞项,记入 BACKLOG)

- Android `dueMs` 不含 AudioTrack 之后的硬件输出延迟(`AudioTrack.getTimestamp` 可估),灯光可能比声音早 10–40 ms;Tack 用用户校准解决。
- Swing(T12)与 count-in(T13)若要做,需 `subMask`/`countInBars` 参数穿过 `metroStart/metroUpdate` 契约。
- Kotlin 侧 ducking 改动只做了静态审读,本机未跑 Android 构建;下次出包由 CI 编译验证。
