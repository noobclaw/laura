# UI/UX 规矩(界面 · 功能 · 体验)

> 2026-09-25 定。起因是用户说"现在的界面太重复太丑"。本文替代 PIPELINE.md「视觉设计标准」里 1–8 条那种"要美观"式的形容词;原第 9–13 条(Logo、动效、英语区、不许一样、色相表)继续有效,并在本文变成可检查的条款。
> 适用范围:`D:\toolapp\apps\*` 所有新 app,以及老 app 下一次改版。约束:Flutter、只发 iPhone(`TARGETED_DEVICE_FAMILY=1`)、零联网、所有字符串 `tr(zh:, en:)`。
> 规则来源:见第六节(ui-ux-pro-max、impeccable、taste-skill、emil、Flutter-Skills、anthropics frontend-design、ehmo iOS、dickwu HIG、M3 skill)。文中带 **[否决]** 的条款,不达标就打回,不参与打分。

---

## 一、诊断:为什么又重复又丑

根据 14 个 app 的 `lib/` 源码,加上 `D:\noob\app\out\*`(09-05 装机截图)和 ohmbench 09-23 商店图得出。

### 根因 1:所有 app 共用同一副骨架,只是换了颜色
- **壳首页原样保留**:`shell/lib/main.dart:104-124` 的 `_HomeScaffold` = Material `AppBar(title: 应用名)` + 右上角 `Icons.settings_outlined` + `SafeArea(tool.buildHome)`。14 个 app 的 `lib/main.dart` 全部沿用这个结构,例如 astropile:62/67、autosnore:67/71、daycount:58/62、orbit:58/62、photolift:69/73、remcard:64/68、tunekit:62/69。所以每个 app 的第一屏顶部都一样:居中标题加一个齿轮(截图 倒数日/记得/鼾声记录 的 1.png 完全同构)。
- **首屏配方一样**:`AppBar` → 渐变圆角 hero 卡 → 卡片右上角放一个放大、半透明的 Material 图标当装饰 → 一列 tonal 卡片行(左边圆形数字,右边 `chevron_right`)→ 右下角 `FloatingActionButton.extended`。
  - 渐变 hero + 角落大图标:remcard `remcard_tool.dart:494/508-512`(`Icons.style_rounded`)、goldenscout `light_view.dart:184/194-203`(`wb_sunny_rounded` + `brightness_2`)、draftbook `ui/home_screen.dart:452-453`、daycount `hero_card.dart:129`、photolift `home_screen.dart:233`
  - extended FAB:daycount `daycount_tool.dart:305`、fieldstamp `fieldstamp_tool.dart:291`、remcard `deck_detail.dart:100`、clean-alarm `alarm_tool.dart:189`
  - 全仓统计:`ListTile(` 143 处(14 个 app 都有),`Card(` 155 处,`FilledButton` 133 处
- **空状态是同一个组件抄了 8 遍**:结构都是"浅色圆底里放一个图标 + titleMedium/Large 标题 + 一句灰字 + FilledButton"。位置:autosnore `ui_common.dart:47`(76px 圆,alpha .14)、echo-jot `ui_common.dart:40`(96px 渐变圆)、orbit `ui_common.dart:79`(104px 径向渐变圆)、remcard `remcard_tool.dart:633`(72px 图标)、daycount `daycount_tool.dart:315`、draftbook `ui/widgets.dart:132`、photolift `home_screen.dart:447`、fieldstamp `gallery_screen.dart:548`。截图 倒数日/1.png 显示:整屏空白,只有一个日历图标加两行字,主操作 FAB 在另一个角落。

### 根因 2:能拉开差异的手段只有一个(色相),字体、形状、图形语言没有一个做了定制
- **字体为零**:14 个 app 没有一个打包字体。`pubspec.yaml` 里的 `fonts:` 全部是 Flutter 模板注释(如 astropile:108),`fontFamily` 只在 ohmbench 的 painter 里写死了 `'Roboto'`。字体是最能区分产品气质的手段,我们完全没用。
- **配色是同一种做法**:每个 `lib/tool/app_theme.dart` 都是 `ColorScheme.fromSeed(seedColor)`,再把 `surfaceContainer*` 覆写成带色相的近黑色(daycount:23-26、echo-jot:108-111、photolift:27-30、draftbook:27、picbox:22-24、tunekit:56-59、autosnore:37-40、orbit:32-38)。结果是"同一套深色 UI,只是色温不同"。另外 autosnore(`main.dart:52`)、ohmbench(`main.dart:77`)强制 `ThemeMode.dark`;autosnore、orbit、astropile、echo-jot 都是夜间调,**4 个 app 属于"深蓝紫夜空加一点发光强调色"这一个原型**(taste-skill 和 impeccable 都把它列为 AI 聚类外观)。
- **没有形状语言**:圆角数值是 20(38 处)/16(31)/12(28)/14(22)/999(15)/24(14)/28(12)混着用,既没有档位,也看不出哪个值属于哪个 app。
- **图标全是 Material**:`Icons.` 共 577 处,覆盖 14 个 app。线宽和端点风格全仓统一,放在 iOS 上更显"安卓味",app 之间也没有区别。
- **动效一个曲线用到底**:`Curves.easeOutCubic` 71 处,时长从 120 到 900ms 不等,没有档位。

### 根因 3:规矩本身是在教人套模板,而且查不出问题
- PIPELINE rubric 第 6 条写着"大按钮/渐变/图标背景/一句 tagline",第 5 条写着"图标 + 一句引导"。**这两条本身就是上面那个模板的配方**,照着做,做出来一定都一样。
- rubric 大多是不可检查的形容词("有温度""不廉价""干净"),G6b 打分只能凭感觉。第 12 条"并排看分不出是哪个 app"没有规定怎么并排、谁来判。
- G2 没有"设计简报"这一步,art direction 是在 G3 写代码时临时拍脑袋定的,默认就落回壳的样子。
- CI 冒烟只截启动屏,空状态、深浅色、大字号等状态一张都没截。
- 可访问性和手感几乎没做:`textScaler` 只有 1 个 app 用了,`HapticFeedback` 只有 3 个 app,`Switch.adaptive` 为 0。壳 `app_theme.dart:23-26` 在 iOS 上把页面转场换成了 `FadeForwardsPageTransitionsBuilder`,**这会让 iOS 边缘右滑返回失效**(右滑返回由 Cupertino 转场提供;需真机确认)。

### 正面参照
ohmbench(09-23 商店图 `store/screenshots/appstore/zh/1.png`)是目前唯一一眼能认出来的 app。原因是**首屏就是工具本身**(电路画布加示波器),而不是"标题栏 + 卡片列表"。它的图形语言(点阵网格、发光导线、元件符号)都是这个产品独有的。下文规矩的核心就是把这一点变成硬性要求。

---

## 二、界面规矩(视觉)

### 2.1 每个 app 在 G2 定好 art direction(决策表)

先从下面 8 个原型里**选 1 个**。已有 app 用过的原型,**新 app 最多重复 1 次,而且字体、形状两项必须不同**。

| 原型 | 适合 | 色彩策略(impeccable 四选一) | 形状 | 密度 | 图形语言 | 已占用 |
|---|---|---|---|---|---|---|
| 仪器面板 Instrument | 测量/调音/传感器 | Restrained:中性灰底 + 1 个信号色 | 小圆角 4–8,刻度线,硬分隔 | 高 | 刻度、指针、LED 数码字 | tunekit |
| 蓝图工作台 Blueprint | 编辑器/电路/规划 | Committed:深底 + 线稿色 | 0–4 圆角,网格 | 高 | 点阵网格、线稿、标注线 | ohmbench |
| 夜间观测 Nocturne | 天文/睡眠 | Drenched:整屏深色 | 大圆 / 胶囊 | 低 | 星点、弧线、发光 | orbit、astropile、autosnore、echo-jot(**已饱和,禁止新增**) |
| 纸本手账 Paper | 记录/写作/计数 | Restrained:纸色底 + 墨色 | 12 圆角 + 纸张阴影 | 中 | 格线、印章、手写数字 | draftbook、daycount |
| 暗房胶片 Darkroom | 照片/相机 | Committed:中性黑 + 安全灯红/橙 | 0 圆角 + 胶片齿孔 | 中 | 取景框、直方图、齿孔 | fieldstamp、photolift |
| 粗野工具 Utility Brutal | 批处理/转换/文件工具 | Full:高饱和纯色块 | 0 圆角,2px 粗描边 | 高 | 粗边框、大号等宽标签 | 空 |
| 柔和实体 Soft Tactile | 习惯/记忆/轻娱乐 | Full:明亮浅底 | 20+ 圆角,按下下沉 | 低 | 立体按键、贴纸 | remcard(部分) |
| 编辑排版 Editorial | 阅读/词典/知识卡 | Restrained:白底 + 大字号对比 | 0–4 圆角,细线 | 中 | 大号衬线数字、栏线 | 空 |

**决策表 5 项,每项必填,不许写"默认"**:
1. **色彩**:用 4–6 个带名字的 hex 手写 `ColorScheme`,浅色、深色各一套(Flutter-Skills 规则)。`fromSeed` 只能用来出草稿,落地前逐个角色手工核对。色相继续查 PIPELINE 第 13 条的色相表,±20° 内不许撞。**强调色在一屏里的面积 ≤10%**,主操作以外的地方不用强调色。
2. **字体配对**(零联网:**字体文件必须放进 `assets/fonts/` 并在 pubspec 注册;禁止使用 `google_fonts` 包的运行时下载**):
   - 中文:正文一律用系统字体(iOS 苹方),不打包,否则包体会增加 10–20MB。展示字(标题、大数字)可以打包一个**子集化**的 OFL 中文字体,只包含实际用到的字,目标 ≤300KB,例如霞鹜文楷(手账)、思源宋体(编辑排版)。
   - 拉丁 / 数字:**必须**打包 1 个展示字体,OFL 许可,只打包需要的字重,每个 ≤150KB。数字统一开 `FontFeature.tabularFigures()`。
   - **禁用**作为默认字体(被 impeccable、taste-skill 列为 AI 高频):Inter、Fraunces、Playfair、Space Grotesk、DM Sans、Outfit、Plus Jakarta、IBM Plex、Instrument Serif。
   - 候选(按原型选,各 app 不许重复):仪器用 JetBrains Mono / Chivo Mono;蓝图用 Martian Mono;纸本用霞鹜文楷 + Figtree;暗房用 Barlow Condensed;粗野用 Archivo Black + Space Mono;柔和用 Nunito;编辑用 Newsreader + 思源宋体子集。
   - 在 `fontFamilyFallback` 里写全中英回退链。
3. **形状语言**:全 app **只允许 3 个圆角值**(例如 0 / 8 / 全胶囊,或 12 / 20 / 28),写成 token 放进 `lib/tool/app_theme.dart`,其他地方不许出现 `BorderRadius.circular(字面量)`。分隔方式从"描边 / 色块 / 阴影"中选一种为主。
4. **密度**:给定基准间距(4 或 8 的倍数)和行高(仪器、蓝图 44pt;其他 52–64pt)。
5. **图形语言**:写一句话说明这个 app 独有的一种自绘元素(刻度、网格、齿孔、印章……),这个元素必须出现在首屏,并且**承载真实数据**(不能是纯装饰)。

### 2.2 结构硬规则
- **[否决] 首屏禁止出现"默认 `AppBar(title: 应用名)` + 右上齿轮 + `ListView` / `ListTile` 卡片列表"的组合。** 首屏必须是工具本身:画布、表盘、取景器、输入区、今日卡片等。壳的 `_HomeScaffold` 必须替换掉,设置入口改放到 app 自己的位置(底部工具条、长按标题、头像等)。
- **[否决] 首屏不许出现"渐变圆角卡 + 角落放大半透明 Material 图标"做的 hero**(根因 1 列出的那个样子)。
- 首屏主操作放在屏幕**下半部分拇指区**(ehmo 规则 1.3),不能放在顶部卡片里。
- 自定义图标:核心的 3–6 个图标用 `CustomPainter` 或 SVG 转路径自绘,线宽、端点和 app 的形状语言一致。Material Icons 只用于设置页等次要位置。**首屏 `Icons.` 不超过 4 处**。
- 同一 app 的所有圆角、颜色、时长、曲线只能从 `app_theme.dart` 的 token 里取。检查方法:`grep -n "Color(0x\|circular([0-9]\|milliseconds:" lib/tool/**/*.dart`,命中处只能在 theme 或 token 文件里(Flutter-Skills 的 `check_raw_values` 思路)。
- iPhone 专属:`Switch` 一律用 `Switch.adaptive`,日期和时间选择器用 Cupertino 版本。禁用 Material 水波纹(`splashFactory: NoSplash.splashFactory`),改为按压缩放(见第四节)。iOS 转场必须保留边缘右滑返回。

### 2.3 禁用清单(AI 味 / 模板味,命中 1 条扣分,命中 3 条否决)
1. 默认 AppBar 居中标题 + 齿轮
2. 渐变 hero 卡 + 角落放大图标
3. "浅色圆底 + 图标 + 标题 + 灰字 + FilledButton" 空状态
4. 深蓝紫底 + 霓虹发光强调色(Nocturne 原型以外)
5. 满屏同款圆角卡片 + 淡阴影 + 渐变
6. 所有区块都用"淡入上滑"入场
7. "大数字 + 小灰标签" 统计卡堆成一排
8. 全大写小标签、标题上方的 eyebrow 小字
9. 标题里只把一个词换色或改斜体
10. 文案里用 emoji 当图标
11. 渐变文字、霓虹 `BoxShadow` 外发光
12. 纯 `#000000` 底,或用 `#111` 冒充黑
13. `01 / 02 / 03` 编号(内容本身不是步骤时)
14. "轻松 / 无缝 / 一键 / 赋能 / Elevate / Seamless" 这类空泛文案
15. 破折号"——"堆砌、全篇"·"分隔

---

## 三、功能与交互规矩

| # | 规矩 | 怎么查 |
|---|---|---|
| F1 **[否决]** | **首次打开 3 秒内能做成第一件事**:不需要注册,不先弹引导页(引导页如果要做,≤3 页且可跳过),不先要权限。工具默认带一个示例或预填值,打开就能看到结果(如调音器直接听、计数器直接 +1、编辑器带示例文档)。 | 冷启动计时,录屏数点击次数:从打开到第一个有效结果 ≤2 次点击 |
| F2 | **权限在用到时才申请**:先用 app 自己的说明卡讲清原因,再弹系统框。拒绝后该功能位显示"去设置开启"按钮(`openAppSettings`),不许出现空白或卡死。 | 真机依次试:拒绝、永久拒绝 |
| F3 | **空状态 = 能直接动手的示范**:展示一个真实的样例或占位数据,主按钮就放在空状态里、位于拇指区。禁止第二节禁用清单第 3 条那种写法。每个 app 空状态的视觉必须用本 app 的图形语言。 | 截图"首次打开"状态 |
| F4 | **撤销代替确认**:删除、清空、覆盖一律立即执行,然后弹 SnackBar 提供"撤销",保留 ≥5 秒。只有不可逆操作(清全部数据、覆盖导出)才弹确认框,确认按钮文字写后果,比如"删除 12 条记录",不写"确定"。 | grep `AlertDialog`,逐个判断是否不可逆 |
| F5 | **反馈在同一帧给出**:按下立即出现视觉变化,耗时 >300ms 的操作要有进度。加载超过 1 秒用骨架屏或进度条,不用整屏转圈。`CircularProgressIndicator` 只允许出现在按钮内部。 | 审代码 + 慢机录屏 |
| F6 | **错误要说原因和出路**:"存储空间不足,已保留原文件" 可以,"出错了" 不行。禁止静默 `catch`(G8a ⑤)。错误提示不道歉,也不用感叹号。 | grep `catch (_)` / `catch (e) {}` |
| F7 | **触控尺寸**:所有可点区域 ≥44×44pt,相邻可点区域间距 ≥8pt。列表行高 ≥44pt。 | `flutter test` 里用 `meetsGuideline(iOSTapTargetGuideline)` |
| F8 | **单手可达**:主操作和高频操作放在屏幕下 60% 区域。顶部只放标题和低频入口。不用汉堡菜单。一级导航如果需要,用底部 tab bar(2–5 个),tab 只负责切换页面、不执行动作。 | 截图上画拇指热区 |
| F9 | **手势**:每个手势都要有按钮做替代入口。滑动删除用 `Dismissible` 配合撤销。可拖动面板要支持甩动关闭(速度超过阈值即关闭,不必拖过一半)。不许劫持 iOS 边缘右滑返回。 | 真机 |
| F10 | **动态字体**:禁止 `textScaler: TextScaler.noScaling` 和把缩放上限夹在 1.3 以下。文字不许用 `FittedBox` 或省略号去硬塞进固定框。在 1.0 / 1.5 / 2.0 三档下布局不许溢出(大数字 hero 允许单独夹到 1.5)。 | `flutter test` 用 `MediaQuery(textScaler: TextScaler.linear(2))` 渲染首页,不得出现 overflow |
| F11 | **可访问性**:图标按钮必须有 `tooltip` 或 `Semantics(label:)`,纯装饰图用 `ExcludeSemantics`。状态不能只靠颜色表达,要同时有形状或文字。对比度:正文 ≥4.5:1,大字和控件边框 ≥3:1,**浅色、深色两套分别测**。尊重系统"粗体文本"设置(`MediaQuery.boldTextOf`)。 | `meetsGuideline(textContrastGuideline)` + `labeledTapTargetGuideline` |
| F12 | **减少动态效果**:读取 `MediaQuery.disableAnimationsOf(context)`,为 true 时位移、缩放、弹簧、循环动画一律 `Duration.zero`,只保留 ≤150ms 的淡入淡出。signature 场景要降级成静态画面。 | 在测试里打开 `disableAnimations` 再截图 |
| F13 | **深浅色**:两套都要手工调过。深色底用带色相的深灰(不用纯黑),正文不用纯白(约 90% 白)。Nocturne 原型可以只做深色,其他原型必须跟随系统设置。 | 两套截图并排看 |
| F14 | **触感反馈**:统一封装成一个 `Haptics` 类。选择类操作用 `selectionClick`,提交用 `lightImpact` / `mediumImpact`,出错最多用 `lightImpact`(**禁止 heavyImpact**)。一个事件只震一次。设置页提供总开关。 | grep `HapticFeedback.` 只能出现在 Haptics 封装里 |
| F15 | **键盘和输入**:数字输入用对应的 `keyboardType`,键盘不能遮住当前输入框。点击空白处收起键盘。回车键执行"下一项 / 完成"。 | 真机 |
| F16 | **文案**:按钮用动词加对象("导出 PDF"),同一个动作全程用同一个词。中英文长度差异要预留空间,英文按比中文长 1.6 倍估算。 | 切换英文后截图检查 |

---

## 四、动效规矩(主要来自 emil 和 impeccable,换成 Flutter 写法)

**时长档位**(写成 token,不许出现其他值):

| token | 时长 | 用在哪 |
|---|---|---|
| `press` | 100–160ms | 按压反馈、开关、选中 |
| `small` | 150–250ms | tooltip、下拉、chip、SnackBar |
| `medium` | 250–350ms | 页面内状态切换、`AnimatedSwitcher`、列表增删 |
| `sheet` | 350–450ms | 底部面板、页面转场 |
| `hero` | 500–800ms | 仅用于首次入场和关键数字滚动到位,每屏最多 1 处 |

- **退出比进入快**,约为进入时长的 0.6–0.75 倍。列表逐项错开 30–60ms,最多错开 6 项,后面的直接出现。

**曲线**(三条就够,写成 token):
- 进出场:`Cubic(0.23, 1, 0.32, 1)`(强 ease-out)
- 屏内移动:`Cubic(0.77, 0, 0.175, 1)`
- iOS 式面板:`Cubic(0.32, 0.72, 0, 1)`
- **界面动效禁止纯 ease-in**(起步慢,会显得卡顿)。禁止随手用 `easeOutBack` / `bounceOut`。
- 弹簧:默认阻尼比 1.0、response ≈0.35s,即 `SpringDescription.withDampingRatio(mass: 1, stiffness: 320, ratio: 1.0)`。只有甩、抛这类带惯性的手势才用 ratio 0.8。

**按压手感**:
- 可点击的卡片和主按钮按下时 `scale 0.97`(允许 0.95–0.98),`press` 时长,在**按下的瞬间**触发,不要等抬手。
- 松手后回弹用同样的曲线。
- 入场从 `scale 0.95 + opacity 0` 开始,**禁止从 `scale 0` 开始**。

**什么时候不用动效**:
- 每天用几十上百次的操作(计数 +1、切换 tab、键盘输入)不加动效,或只做 ≤100ms 的颜色变化。
- 纯为了好看的入场动画不做,尤其是"每个区块都淡入上滑"(禁用清单第 6 条)。
- 动效只用来回应用户操作,或用来表达状态变化。
- 所有动画点一下就能直接跳到结束状态。转场期间不锁住输入;动画中途被打断时,从当前位置继续,不要从头重播。
- 循环动画在页面不可见、app 切到后台、开启"减少动态效果"时必须停止(用 `TickerMode` 或监听生命周期)。

**signature 场景**(PIPELINE 第 10 条保留,但要加约束):
- 必须**由真实数据驱动**(音量、角度、进度、时间),不能是纯装饰。
- 每屏最多 1 个。
- 性能要求:在低端机上跑 60fps 且不掉帧,用 `RepaintBoundary` 隔离重绘区域。
- 必须能按 F12 降级成静态画面。

---

## 五、流程关卡

### 5.1 放在工厂的哪一步
| 关 | 新增动作 |
|---|---|
| G2 立项 | 填写下面的《设计简报》,写进 `PLAN.md` 的「设计简报」一节。简报没通过"并排判定"(5.4)不许进 G3 |
| G3 开发 | 第一个 commit 先落 `app_theme.dart` 的 token(颜色 / 字体 / 圆角 / 时长 / 曲线)和 `assets/fonts/`,之后再写页面。替换壳的 `_HomeScaffold` |
| G4 本地验收 | `screens_test/`(参照 ohmbench)用 `flutter test` 渲染 8 张图:首页首次打开、首页有数据、核心操作屏、空状态、错误态、深色、`textScaler 2.0`、英文。同时跑 F7 / F10 / F11 的 guideline 测试 |
| G6b 评审 | 用 5.3 的打分表,由**独立设计评审 agent** 打分。输入是 G4 渲染的 8 张图、首页源码、5.4 的并排拼图 |
| G8a | 第 ④ 面(语言)增加 F16 检查;第 ⑦ 面(崩溃项)增加 F10 大字号溢出检查 |

### 5.2 设计简报模板(G2 填空,每格必填)
```
## 设计简报 — <app 英文名>/<中文名>
1. 一句话:用户在什么场景下、用单手还是双手、要在几秒内完成什么? ______
2. 首屏是什么(工具本身,不许写"卡片列表"):______;主操作在哪里(拇指区坐标描述):______
3. 3 秒首胜(F1):冷启动后,零设置、≤2 次点击看到什么结果? ______(预填或示例数据是什么)
4. 原型(2.1 表选一):______;与它共用原型的已有 app:______;我与那个 app 在【字体】【形状】上的不同:______
5. 色彩:策略(Restrained / Committed / Full / Drenched)______;色相 ___°(已查色相表,不撞)
   浅色:bg #____ surface #____ ink #____ accent #____ signal #____
   深色:bg #____ surface #____ ink #____ accent #____ signal #____
6. 字体:展示字 ______(OFL,文件名,字重,KB)/ 中文展示子集 ______(或"不用")/ 正文 = 系统字体
7. 形状:3 个圆角值 __/__/__;分隔方式(描边/色块/阴影)______;基准间距 __pt;行高 __pt
8. 图形语言:独有的自绘元素 ______,它显示哪项真实数据:______
9. signature 场景:______,由什么数据驱动:______,开启"减少动态效果"后变成什么样:______
10. 空状态:展示什么样例或示范,按钮在哪里:______
11. 触感映射:哪 3 个事件震动,各用什么强度:______
12. 首屏线框(ASCII,≤15 行)
13. 自检:"换一个类似需求的 app,我会不会做成一样的?" 如果会,改哪一项:______
```

### 5.3 G6b 评审打分表(满分 100,≥75 分且无否决项才算通过)

**否决项(任一命中直接打回,不打分)**:
- V1 首屏是 默认 AppBar + 齿轮 + 列表 / 卡片列表(2.2)
- V2 首屏出现 渐变圆角卡 + 角落放大图标
- V3 禁用清单(2.3)命中 ≥3 条
- V4 没有打包展示字体,或 pubspec 引入了 `google_fonts`
- V5 并排判定(5.4)不通过
- V6 F1 不通过(需要 >2 次点击,或先弹权限、先要注册)
- V7 `textScaler 2.0` 下首页溢出(出现黄黑条)
- V8 任何一套主题(浅或深)正文对比度 <4.5:1
- V9 没有 signature 场景,或 signature 是纯装饰

**计分项**:
| 项 | 分 | 满分标准(可检查) |
|---|---|---|
| 首屏工具化 | 15 | 首屏即工具;主操作在下 60% 区域;首屏 `Icons.` ≤4 处 |
| art direction 落地 | 15 | 简报第 4–8 项在代码里都能找到对应 token;原始值 grep 命中只出现在 theme 文件里 |
| 字阶 | 10 | 一屏里 ≤4 个字号层级;大数字用展示字体 + 等宽数字;中英切换后不掉版 |
| 色彩 | 10 | 强调色面积 ≤10%;语义色(错误、成功)与品牌色分开;深浅色都手工调过 |
| 形状与一致性 | 10 | 只用 3 个圆角值;分隔方式统一;各页间距来自同一套基准 |
| 空状态 / 错误态 / 加载 | 10 | F3、F5、F6 各自达标,每项 3–4 分 |
| 交互手感 | 10 | 按压缩放 + 触感封装(F14)+ 撤销(F4) |
| 动效纪律 | 10 | 只用 token 里的时长和曲线;高频操作无动效;F12 降级正确 |
| 可访问性 | 5 | F7、F11 的 guideline 测试全部通过 |
| 图标与 Logo | 5 | 核心图标自绘;1024 图标缩到 60px 仍能认出 |

评审 agent 的输出格式固定为三列:"问题 / 依据(本文条款号)/ 具体改法(文件:行)"。只写"不够精致"这类形容词的评审作废。

### 5.4 与已有 app 并排对比的判定办法
1. **拼图**:把新 app 的"首页有数据"截图和全部已有 app 的首页截图拼成一张图(sharp 或 `flutter test` 出图后拼接),**去掉应用名和图标**。
2. **眯眼测试**:整张拼图转灰度,再做 8px 高斯模糊。如果新 app 的明暗块布局(顶部条 / 大块 / 行列)和任何一个已有 app 大致一样(块的位置和数量相同),判不通过。这一步测的是骨架,不看颜色。
3. **盲认测试**:另开一个 agent,只给它每个 app 一句话的定位和打乱顺序的去名截图,让它配对。新 app 被认错或者被标为"无法区分",判不通过。
4. **差异清单**:新 app 与最像的那个已有 app 相比,在【原型 / 字体 / 形状 / 图形语言 / 首屏结构】5 项里**至少有 3 项不同**。
5. 老 app 改版也走同一流程。现在的 14 个 app 首页拼图作为基线,存到 `D:\toolapp\reports\uiux_baseline\`(G4 渲染时顺便生成)。

---

## 六、推荐引入的 skill

| skill | 星 / 许可证 | 结论 | 理由 |
|---|---|---|---|
| **pbakaus/impeccable** | 70.8k / Apache-2.0 | **装**(`~/.claude/skills/impeccable`) | 规则质量最高:`reference/ios.md` 和 `android.md` 明确覆盖 Flutter;`craft-floor.md` 给出了对比度、禁用 eyebrow、禁用渐变字、禁"大数字小标签"等具体规则;`animate.md` 有时长表;`audit.native` 能从 Flutter 源码做审计,G6b 可以直接用。注意:启动器第一次运行会下载二进制,跑不起来时 skill 会退回纯文档模式,照样能用。 |
| **zakariaf/Flutter-Skills** | 21 / MIT | **装子集**:design-system-structure、accessibility-as-code、motion-and-haptics、ui-states-and-feedback、i18n-rtl-l10n | 唯一一个 Flutter 原生、并且和"零联网"对得上的(禁 google_fonts、字体打包、fallback 链、原始值检查脚本、HapticTheme)。星很少,所以只取规则。它默认用 Riverpod 和 Drift,相关部分删掉;它要求"不锁屏幕方向",和 iPhone 竖屏冲突,忽略这一条。 |
| **emilkowalski/skills** | 41.0k / MIT | **装** emil-design-eng、apple-design | 动效数值和"什么时候不用动效"讲得最清楚。代码是 CSS / Framer Motion,已按第四节换成 Flutter 写法。mobile-native、animate-expo 不装。 |
| nextlevelbuilder/ui-ux-pro-max-skill | 130.4k / MIT | 只借数据,可选装 | `data/styles.csv`(风格原型)、`typography.csv`(74 组字体配对)、`stacks/flutter.csv`、`references/pro-rules.md`(44pt、按压 80–150ms、深浅色分别测对比度)适合 G2 选型时查。偏"合规底线",对去模板化帮助不大。需要 Python 3,无第三方依赖。 |
| Leonxlnx/taste-skill | 89.9k / MIT | 只借规则 | §9 的反 AI 味禁用清单已吸收进 2.3。其余内容是 Web / Tailwind / 落地页专用。 |
| anthropics/skills · frontend-design | 178k / Apache-2.0(该 skill 单独许可) | 只借规则 | 5 类 AI 聚类外观、"先写 token 方案再写码"、"大胆只用在一处"已吸收进 2.3 和 5.2 第 13 项。 |
| ehmo/platform-design-skills | 590 / MIT | 只借规则 | `skills/ios/SKILL.md` 规则量化最好(44pt、8pt 栅格、引导 ≤3 页、骨架屏、权限先说明)。G8a 的 iOS 面可以用它当检查清单。 |
| dickwu/apple-design-skill | 798 / **无许可证** | 只读参考,不装、不搬内容 | `references/cross-platform.md` 把 HIG 术语对照成 Flutter 写法,很有用。但没有许可证,且 HIG 原文版权归 Apple。 |
| hamen/material-3-skill | 1.4k / MIT | 只借数值 | 色彩角色配对、圆角档位 4/8/12/16/28、M3 动效时长可作参考。iPhone-only 产品不照搬 M3 的组件外观。 |
| bergside/awesome-design-skills | 2.9k / MIT | 不引入 | 67 套 Web 风格模板,没有移动端内容,最多当看图参考。 |

**落地顺序**:① 把 impeccable、emil(两个)、Flutter-Skills 子集复制到 `~/.claude/skills/`。② 壳 `shell/` 按本文改:删 `_HomeScaffold` 默认 AppBar;iOS 转场恢复右滑返回;加 token 骨架、Haptics 封装、`screens_test` 模板。③ 把 PIPELINE「视觉设计标准」第 1–8 条改为"见 kb/UIUX规矩.md"。④ 用 5.4 对现有 14 个 app 出基线拼图,Nocturne 撞型的 4 个 app 排进改版队列。第 ②③④ 步需要改 shell 和 PIPELINE,由主会话决定何时做。
