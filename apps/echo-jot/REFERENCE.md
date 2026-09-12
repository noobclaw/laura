# echo-jot · 参考保真审计(REFERENCE.md)

**参考仓**:[ggml-org/whisper.cpp](https://github.com/ggml-org/whisper.cpp)(**MIT**),本机镜像 `D:\toolapp\_ref\whisper.cpp`(whisper.cpp v1.9.x 系)。
**署名**:whisper.cpp 为 MIT 许可(permissive),本 app 的引擎层按其算法**对照移植**(energy VAD、参数默认、特殊 token 处理),并在「关于/原理」页与商店 listing 署名开源组件(whisper.cpp MIT、FFmpeg LGPL v3)。移植代码为独立 Dart 实现,常量与算术与原作逐位对齐。
**运行时**:whisper.cpp 经 `whisper_ggml` 2.6.0 插件(MIT)调用;插件把 `TranscribeRequest` 转 `whisper_full_params`。凡插件未暴露的参数,一律落到 whisper.cpp 的 `whisper_full_default_params(WHISPER_SAMPLING_GREEDY)`(`src/whisper.cpp:6040+`)。

## 汇总表

| | 数 |
|---|---|
| 核对项(函数 / 参数 / 算法) | **24** |
| 一致 | 13 |
| 有意偏离(产品理由) | 6 |
| 漏掉 → 已补(本轮) | 5 |
| **剩余(未处理)** | **0** |

剩余 = 0,满足 G8c 提审门槛。

---

## A. `whisper_full_params`(逐参数)

原作默认取自 `src/whisper.cpp:6040-6135`(`whisper_full_default_params`,GREEDY 分支 `best_of=5`)。我方设值在 `lib/tool/whisper_engine.dart` 的 `_transcribeFile`(`TranscribeRequest`,行 331-352)。

| 参数 | 原作默认 | 我方 | 判定 | 我方 文件:行 |
|---|---|---|---|---|
| `language` | `"en"`(可 `"auto"` 触发自动检测,`whisper.cpp:6938`) | 由 tag 映射,**永不发 `auto`** | **有意偏离** | `whisper_language.dart:49` |
| `translate` | `false` | `false`(插件 `isTranslate` 默认 false,未设) | 一致 | 默认 |
| `no_context` | `true` | `false`(显式) | **有意偏离** | `whisper_engine.dart:345` |
| `no_timestamps` | `false` | `false`(`isNoTimestamps:false`) | 一致 | `whisper_engine.dart:335` |
| `single_segment` | `false` | `false`(插件不暴露) | 一致 | 默认 |
| `print_special` | `false` | `false`(插件 `isSpecialTokens` 默认 false) | 一致 | 默认 |
| `token_timestamps` | `false` | `false`(不暴露) | 一致 | 默认 |
| `max_len` | `0` | `0`(不暴露) | 一致 | 默认 |
| `split_on_word` | `false` | `false`(`splitOnWord` 默认 false) | 一致 | 默认 |
| `suppress_blank` | `true` | `true`(不暴露) | 一致 | 默认 |
| `suppress_nst`(非语音 token) | `false` | **`true`** | **有意偏离** | `whisper_engine.dart:350` |
| `temperature` | `0.0` | `0.0`(不暴露) | 一致 | 默认 |
| `temperature_inc`(回退) | `0.2`(`no_fallback` 关) | `0.2`(插件 `noFallback` 默认 false → 回退开) | 一致 | 默认 |
| `entropy_thold` | `2.4` | `2.4`(不暴露) | 一致 | 默认 |
| `logprob_thold` | `-1.0` | `-1.0`(不暴露) | 一致 | 默认 |
| `no_speech_thold` | `0.6` | `0.6`(不暴露) | 一致 | 默认 |
| `greedy.best_of` | `5` | `5`(不暴露) | 一致 | 默认 |
| `n_threads` | `std::thread::hardware_concurrency()/2`(cli) | `clamp(1,4,cores)` | **有意偏离** | `whisper_engine.dart:333` |
| `initial_prompt` | `nullptr` | 脚本前缀 + 上一段末尾文本 | **有意偏离**(见 §C) | `whisper_engine.dart:258` |

**偏离理由**
- **`language` 永不 `auto`**:whisper.cpp 本身接受 `"auto"`(`src/whisper.cpp:6938` 走自动检测),但**插件的原生桥**在把参数交给 whisper.cpp **之前**先 `whisper_lang_id(language)==-1` 就判错返回 `"error: unknown language"`(`whisper_ggml-2.6.0/macos/Classes/whisper_ggml.cpp:200-205`、`ios/.../whisper_flutter_plus.cpp:249-252`),而 `"auto"` 不在 `whisper_lang_id` 表里(`src/whisper.cpp:4089-4097` 返回 -1)。故 `whisperRequestLanguage` 把映射到 `auto` 的 tag 解析成 app UI 语言(再兜底 `en`)。**插件强制的偏离**;插件日后放行 `auto` 即可撤。
- **`suppress_nst=true`**:听写场景每段录音尾部都是停说后的静音——正是 whisper 产 `[BLANK_AUDIO]`/`(music)`/`♪` 的温床。代价是听写文本里的真方括号被抑制;可接受。
- **`no_context=false`**:单次插件调用内的多个 30s 解码窗互相条件化(= OpenAI `condition_on_previous_text=True`,= stream `--keep-context`),接住被 chunk 切开的句子。显式设值,防插件默认变更翻转。
- **`n_threads` clamp(1,4)**:手机核多但内存/发热受限,>4 线程在中端机只抖动不提速。
- **`initial_prompt`**:见 §C。

---

## B. Energy VAD 与分段(切点落静音)

### B1. `high_pass_filter`(`examples/common.cpp:597-608`)→ 我方 `highPassFilter`(`audio_chunks.dart:402`)
- `rc=1/(2π·cutoff)`,`dt=1/sr`,`alpha=dt/(rc+dt)`,`y[i]=alpha·(y[i-1]+x[i]-x[i-1])`,`y[0]=x[0]`,**原地**。判定:**一致(漏掉→已补)**。
- **原作细节被忠实保留**:原作原地覆写后 `data[i-1]` 已是上一步输出 `y`,故 `y+x[i]-data[i-1]` 退化为 `alpha·x[i]`——是**恒定增益**,非真高通。我方 Dart 逐位复现(增益在 `vad_simple` 的能量**比值**里约掉,决策不受影响)。对照测试:`whisper_logic_test.dart:381-408`(`data[1]≈alpha`、正弦逐样 `alpha·x[i]`)。

### B2. `vad_simple`(`examples/common.cpp:610-648`)→ 我方 `vadSimple`(`audio_chunks.dart:424`)
- `n_samples_last=sr·last_ms/1000`;`>=n_samples`→false;`freq_thold>0` 先高通;`energy_all=mean|x|`、`energy_last=mean|x| over tail`;`energy_last > vad_thold·energy_all`→false 否则 true。判定:**一致(漏掉→已补)**。
- 默认 `vad_thold=0.6`、`freq_thold=100Hz`、buffer 2000ms、last 1000ms(`audio_chunks.dart:385-399`),与 stream/command 一致。全静音 buffer→true、全语音→false 的边角与原作一致。我方不原地改输入(callers 不依赖),对照测试 `whisper_logic_test.dart:415-475`。

### B3. 分段与切点
| 项 | 原作(examples/stream) | 我方 | 判定 |
|---|---|---|---|
| 分段方式 | 滑窗 `step_ms/length_ms/keep_ms`(实时流) | 离线 60s 段 + 5s 重叠(`defaultChunkSeconds=60`/`defaultOverlapSeconds=5`,`audio_chunks.dart:174-175`) | **有意偏离**:离线整条录音,非实时流;60s 保证每次调用一个 whisper.cpp `mel`,内存不炸 |
| 切点落静音 | VAD 模式靠 `vad_simple` 判「说完了就转写」 | `findSilentCut`/`snapChunksToSilence`:在名义切点 ±3s 内每 100ms 用 `vadSimple` 找最近停顿,把 seam(重叠中线)移到停顿中部(`audio_chunks.dart:477/526`) | **漏掉→已补** |
| 段间上下文 | `--keep-context`:上一段解码 token 作下一段 `prompt_tokens` | `contextPromptFor` 取上段末(不含重叠区)文本喂 `initial_prompt`(§C) | **漏掉→已补** |

对照测试:`findSilentCut`(`:510-566`,落最近停顿/两停顿取近/无停顿返 null/尊重窗口)、`snapChunksToSilence`(`:568-622`,seam 落停顿且保 5s 重叠、无停顿不动)。

---

## C. 段间上下文(stream `--keep-context` 的对应)
- 原作:`examples/stream/stream.cpp:34/69/338-339/415-416`——`no_context` 默认 true,`--keep-context` 置 false 后把**上一窗解码的 token** 作 `prompt_tokens` 传下一窗。
- 我方:插件只暴露 `initial_prompt`(文本),whisper.cpp 会把它 tokenise 进**同一个** `prompt_tokens` 槽,故传文本等价。`contextPromptFor`(`audio_chunks.dart:588`)只取**结束早于下段起点**的段(重叠区文本会被下段再听到,放进 prompt 反诱使跳词),取尾部并按 CJK 100 / Latin 400 字符封顶(远低于 whisper `n_text_ctx/2=224` token 预算)。`buildInitialPrompt`(`:622`)把脚本前缀(中文定简繁)与上下文拼接。判定:**漏掉→已补**。
- 对照测试:`contextPromptFor`(`:624-689`)、`buildInitialPrompt`(`:691-700`)。

---

## D. 特殊 token 过滤
- 原作 token 文本形(`src/whisper.cpp:1653-1675`):`[_TT_x]` `[_EOT_]` `[_SOT_]` `[_SOLM_]` `[_PREV_]` `[_NOSP_]` `[_NOT_]` `[_BEG_]` `[_LANG_x]` `[_extra_token_x]`,以及裸词表 `<|...|>` 写法。`print_special=false`(默认)本不外泄它们。
- 我方 `stripSpecialTokens`(`audio_chunks.dart:359`,正则 `\[_[A-Za-z0-9_]*\]|<\|[^|>]*\|>`)在合并/清洗/上下文各环节兜底剥离;`isNonSpeechArtifact`(`:340`)与 `_cleanSegments`(`:342`)串上它。**belt-and-braces**:即便插件改默认或请求 `is_special_tokens`,`[_TT_450]` 也进不了笔记。普通 `[note]`/`(aside)`/`[BLANK_AUDIO]` 不误伤(后者由非语音判定另行处理)。判定:**漏掉→已补**。对照测试:`whisper_logic_test.dart:337-367`。
- 非语音注解 `[BLANK_AUDIO]`/`(music)`/`♪`/`*laughs*` 的丢弃:`isNonSpeechArtifact` + `suppress_nst` 双保险,判定 **一致**(语义对齐原作 suppress_nst 意图)。

---

## E. 音频前处理与模型
| 项 | 原作 | 我方 | 判定 |
|---|---|---|---|
| 采样 | 16kHz 单声道 f32 [-1,1] | 直接录 16kHz/mono/PCM16 WAV(`whisper_recorder.dart:23/40/42`);`pcm16ToFloat` 按 `/32768`(`audio_chunks.dart:457`) | **一致** |
| 归一化 | `s/32768`(WAV 读取) | 同(`whisper_logic_test.dart:477-491` 逐值:0/32767→32767/32768/-1.0/0.5) | **一致** |
| 模型 | 用户自选 | `ggml-base-q5_1.bin`(**多语种** base,q5_1,59,707,625 B,sha256 `422f1ae4…01a8898`) | **一致** |
| 完整性 | 无 | 构建期 `prepare_assets.sh` sha256 校验;运行期 asset→app-support 按长度校验 marker(`whisper_engine.dart:105-145`) | **一致**(资产不可变,无需运行时 sha256) |

多语种(非 `.en`)模型与任意 `language` 码配套;`.en` 模型只允许 `en`——故选多语种正确。

---

## 结论
上一轮半成品(`audio_chunks.dart` / `dictation_controller.dart` / `whisper_engine.dart` / `whisper_language.dart` / `test/whisper_logic_test.dart`)对照原作**逐位核实无误**:VAD 忠实复现原作原地滤波「退化为恒定增益」的行为、能量比值判定、`whisper_lang_id` 拒 `auto` 的插件事实、参数默认全部对齐。5 项原缺功能(VAD 切点、段间上下文、特殊 token 剥离、`auto` 兜底、参数默认显式化)已补齐并加对照测试。`flutter analyze` 0 issue、`flutter test` 全绿(91 项)。剩余 0,可提审。
