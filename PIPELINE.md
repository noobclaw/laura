# 二期:选题 → 成品 App 流水线

从日报选题到可上架 APK/AAB 的标准流程。原则:**壳不动、只换芯**——所有 app 共用一个壳工程,每个新 app 只替换 `lib/tool/` 里的工具模块和品牌资源。

## ⭐ 工厂标准作业流程 SOP(2026-07-26 定版,每轮工厂逐条执行、缺一不可)

> 背景:干净闹钟真机验收失败(不响)暴露「analyze+test 过 ≠ 能用」;本 SOP 把质量关卡全部机器化/成文化。**顺序执行,每关不过不得进下一关。**

**G0 防撞车**:`git log --oneline --since="2.5 days ago" -- apps/`,近 2.5 天有新 app 提交则本轮跳过。

**G1 取题**:取 BACKLOG「⚪排队」指数最高项,**执行当日决策门备注**(跳取/退取规则)。硬性否决:①系统自带 app 可基本替代且无付费榜实证差异化;②缺口 <5/15 或付费验证 <15/25(只进观察池);③依赖服务端。

**G2 立项评审(写码前,写进 PLAN.md)**:
- **差异化楔子一句话**:「用户为什么选我而不是竞品X」——写不出来 = 退回换题。
- **招牌功能架构评审**:核心可靠性机制选型定死(闹钟=`setAlarmClock`/前台服务,非通知调度;桌面小组件=provider 端实时计算,非 Flutter 端烤死数值;相机=生命周期 resume 必须重建;后台任务=WorkManager/前台服务)。
- **权限流程评审**:每个危险权限(通知/相机/定位/麦克风)必须:显式请求 → 拒绝有可见提示 → 永久拒绝给「去系统设置」出口。**禁止静默失败。**
- **定价**(见「变现与定价标准」),写进 PLAN.md。

**G3 开发**:`node scripts/new_app.mjs` 克隆壳 → 实现 `lib/tool/`。强制:
- **视觉设计(2026-07-27 起铁律):UI 必须美,不只是能用。** 见下「视觉设计标准」。核心操作要有 hero 感,间距/层级/字阶/圆角/配色成体系,空状态有温度而非一行冷字,深浅色都好看,数据展示(图表/评分/表盘)干净不廉价。写码时就按标准做,别指望事后补;丑的实现到 G6b 会被打回重做。
- **多语言(2026-07-26 起铁律)**:所有用户可见字符串一律 `tr(zh:, en:)`(壳 `core/l10n.dart`,ja 可选),跟随系统语言、英文兜底;`MaterialApp` 带 `GlobalMaterialLocalizations.delegates`+`supportedLocales`;安卓桌面名走 `@string/app_name`(`values/`+`values-zh/` 分别填英文名/中文名,取自 store/listing.md);Branding 的 aboutText/privacyPolicy 双语。日志/JSON key/文件名不翻。
- **专属图标(2026-08-30 起铁律,用户拍板)**:每个新 app 必须有**贴近产品自身**的专属图标——产品功能符号 + 该 app seed 色渐变,1024px 源图写入 Android mipmap 5 档(48/72/96/144/192)+ iOS AppIcon.appiconset 全尺寸(iOS 侧去 alpha),顺手出 512px(Play 商店图标)与 1024×500(feature graphic)存 `store/`。**禁止用壳默认 Flutter 图标出包**(由来:08-30 装机验收发现 7 个已做 app 图标 md5 全同,G3「生成图标」从未真正执行过;同图标还加重 Apple 4.3 重复判定)。范本:2026-08-30 会话的 `icons.mjs`(SVG→sharp)。
- 零联网默认:`tools:node="remove"` 剥 INTERNET;确需网络单独立项说明。
- 免费层必须真可用(核心功能+数量上限),Pro 解锁「无限+进阶」;禁广告 SDK。

**G4 本地验收**:`flutter analyze` 零 issue + `flutter test` 全过(PUB_CACHE=D:\dev\pub-cache;严禁本机 flutter build)。

**G5 独立审计**:请独立审计 agent 通读全部代码,按「**装到真机上什么会坏**」出报告(权限流/生命周期/持久化/边界值/Pro 门);修完复审才过关。

**G6 出包+机器冒烟**:push → `gh workflow run build-app.yml -f app=apps/<name>` → **smoke-test job 必须绿**(模拟器装包→启动→30s 验活→扫 FATAL EXCEPTION→截屏);冒烟逻辑在 `scripts/ci_smoke.sh`(emulator-runner 逐行 sh -c,workflow 里只准一行调用)。**下载 smoke 截屏亲眼确认 UI 真渲染**,不许只看绿勾。

**G6b 视觉美观二次 check(2026-07-27 加,铁律)**:渲染 ≠ 美。出包后**必须做第二次「好不好看」评审**——**下载 smoke 截屏**(至少覆盖首页/核心操作屏)对照下「视觉设计标准」rubric **逐条打分**,并**通读各页 UI 源码**评审冒烟没截到的屏(报告/详情/图表等)。**建议请独立设计评审 agent** 出「美不美 + 具体改哪」报告(独立视角,像 G5 代码审计一样)。**丑/廉价/不一致/拥挤/空洞就打回 G3 改,改完重出包重看 G6b,直到 UI 过关**。评审要点见下。**未过 G6b 不得进 G7 记「已做」。**

**G7 记账与用语纪律**:BACKLOG 状态流转 ⚪→✅已做;**过冒烟只准写「待真机验收」,用户真机核心功能验过才准写「待上架」**;真机验收失败标 ⛔ 附根因,重做前不上架。PLAN.md 附「真机验收清单」(权限弹窗/核心功能/传感器/边界各 1 行,给用户照着点)。

**G8 上架(节奏独立)**:每周 1-2 个防商店反垃圾;上架前必须:真机验收通过 + **本地 Pro 占位换成真内购**(见下)+ release keystore 签名。

## 视觉设计标准(2026-07-27 定版,G3 照做 / G6b 照查)

**原则:每个 App 都要看起来像「用心做的独立精品」,不是「能跑的 demo」。** UI 不美的直接打回,和功能不成立同罪。评审 rubric(G6b 逐条,任一不及格即打回):

1. **层级与留白**:一眼看出主次;核心操作是全屏最抢眼的元素(hero),不是和列表挤在一起。间距成体系(8/12/16/20/24 的节奏),不拥挤、不空洞、不左右顶边。
2. **配色**:用 Material 3 seed + tonal surface 成体系,别一堆硬编码原色乱撞;强调色克制、语义化(危险=红、成功=绿)。**深色与浅色都要好看**(壳已给 darkTheme,自测两套)。
3. **字阶**:标题/正文/说明分明用 `textTheme` 层级,数字类(时长/评分/统计)可用等宽或加粗突出;不全是一个字号。
4. **形状与质感**:圆角/卡片/分隔一致;适度用 elevation 或 tonal 容器分区;关键数字可上表盘/进度环/图表,别只堆纯文字。
5. **空状态有温度**:首次打开不是一行冷字——给图标 + 一句引导 + (可选)示意,让人知道下一步干嘛。
6. **hero/首屏**:App 的招牌操作(录音/拍照/开始)要有设计感——大按钮/渐变/图标背景/一句 tagline,第一眼就「想点」。
7. **数据可视化**:图表/曲线/评分表盘要干净专业(轴/网格克制、配色和主题一致、有单位与标签),不廉价、不糊。
8. **一致性**:各页共用同一套间距/圆角/卡片语言,不是每屏一个风格。

> 现实约束:CI 冒烟只截「启动屏」,故**首页/核心屏的美观是硬指标**(必被截到);冒烟截不到的屏(报告/详情/趋势)按源码评审 + 必要时本地 `flutter run` 驱动截图补看。**别用「冒烟只截首页」当借口放过其它屏。**

> **起点已抬高(2026-07-27)**:壳 `shell/lib/core/app_theme.dart` 现提供 `buildAppTheme(brightness)`(扁平填充卡/圆角 20/数字等宽+加粗字阶),new_app 出来的 app 默认就用它——**主题这层不再是零分起点**。但主题只解决「不丑」,rubric 的 hero/空状态/数据可视化/art direction 仍要**每个 app 自己 bespoke**(见 apps/autosnore 的 app_theme+渐变 hero+自绘表盘为范例)。历史 6 个 app 已于 2026-07-27 逐个 retrofit 到此标准(clean-alarm 搁置除外)。

## 变现与定价标准(2026-07-26 定版)

- **模式**:默认「免费+Pro 一次性买断」;B 端搜索转化型(如 FieldStamp)可用纯付费下载(零代码,Console 定价);**禁广告**(与隐私/干净卖点冲突)。
- **定价阶梯**:练手/填充 $0.99-1.99;标准工具 $2.99-4.99;B 端刚需 $5.99-9.99。锚定法:**对标头部竞品价的 1/3~1/2 切入**(AnkiMobile $29.99→Remcard $4.99;PhotoPills $10.99→GoldenScout $3.99)。中区价取 ¥ 整数(6/12/18/28)。上架 3 个月按转化复盘调价。
- **支付接入(Play)**:数字商品**必须走 Google Play Billing**(商店政策强制,不得接支付宝/微信/Stripe);Flutter 用官方 `in_app_purchase` 插件,产品为 non-consumable;**商品 ID(2026-08-31 修订):App Store 的商品 ID 是全账号唯一的(Play 才是按 app 隔离),故每个 app 必须用 `<applicationId>.pro_unlock`**(new_app.mjs 自动替换;历史例外:remcard 占用了裸 `pro_unlock`,两店保持不变)。Play 侧建商品时用与代码一致的 ID;设置页必须有「恢复购买」(restorePurchases)。**App 无需 INTERNET 权限**(结算经 Play Store 进程完成),零联网卖点保留;BILLING 权限由插件自动并入。抽成 15%(年 ≤$100 万 small business 档)。**✅ 2026-08-22:7 个在架 app(remcard/autosnore/echo-jot/orbit/daycount/fieldstamp/goldenscout)已全部接真内购,本地占位后门清零**(clean-alarm ⛔搁置未接)。**新 app 出厂即须接,不再留占位**——壳 `core/purchase.dart` 提供 `PurchaseService`(买/恢复/pending/错误降级)+ `PurchaseNotices`(把结果弹成 snackbar,不放就等于错误全部静默)+ `RestorePurchasesTile` + `ProPriceText`。**价格一律用 `ProPriceText`/`PurchaseService.price` 取商店下发的本地化价,禁止在 UI 里硬编码**(Play 按用户所在区计价,写死「¥18」给一个实际被扣 €4.99 的人看 = 客诉)。仍须经 Play Console 内部测试轨 + license tester 真机走通「购买→解锁→卸载重装→恢复购买」才准上生产轨。
- **大陆安卓商店**(华为/小米/OPPO/vivo):各家自有结算 SDK+软著+备案,是独立后续项目,**首发只做 Google Play**(海外+中文区用户靠 zh 本地化覆盖)。
- **iOS**:同 `in_app_purchase` 走 StoreKit,Apple 小企业档 15%;iOS 工程未配置,归三期。

## 上架自动化路线(三期,未做)

1. **一次性人工前置**:release keystore 生成→base64 进 GitHub Secrets(workflow 已支持自动切真签名);每个 app 首次在 Play Console 人工建应用+数据安全表单+内容分级(Google 政策要求,无法绕);Play Developer API 开 service account,JSON 进 Secrets。
2. **CI 自动上传**:build-app.yml 加 `publish` 可选 job——fastlane supply(或 gradle-play-publisher)把 AAB+双语商店文案(`store/listing.md` 转 `fastlane/metadata/android/{en-US,zh-CN}/` 结构)推 **internal 测试轨**;**晋级 production 保留人工点击**(最后闸门)。
3. **App Store**:macos runner + fastlane deliver + App Store Connect API key;需 Apple 开发者账号($99/年)+ iOS 工程补配;排在 Play 通道跑顺之后。
4. 节奏纪律不变:每周 1-2 个。

## 本机工具链(D:\dev)

| 组件 | 位置 | 备注 |
|---|---|---|
| Flutter stable | `D:\dev\flutter` | `D:\dev\flutter\bin` 需在 PATH |
| JDK 17 (Temurin) | `D:\dev\jdk17` | JAVA_HOME 指向此 |
| Android SDK | `D:\dev\android-sdk` | ANDROID_HOME;cmdline-tools/platform-tools/build-tools |
| Gradle 缓存 | `D:\dev\gradle-cache` | GRADLE_USER_HOME(C盘只剩6GB,必须重定向) |
| Pub 缓存 | `D:\dev\pub-cache` | PUB_CACHE |

以上环境变量已写入机器级(Machine scope),新开终端即生效。

## 壳工程(shell/)

`D:\toolapp\shell` 是模板 Flutter 工程,固化:

- **工具模块契约** `lib/tool/tool_module.dart`:每个 app 实现 `ToolModule`(name/icon/homeWidget/settingsItems)。壳的 main.dart 只认这个接口。
- **通用件** `lib/core/`:主题(Material 3,种子色可配)、设置页(评分引导/隐私政策/关于/语言)、本地存储封装(shared_preferences)、多语言脚手架(zh/en/ja)。
- **零网络权限**:AndroidManifest 默认不声明 INTERNET —— 无服务端工具的隐私卖点,如某 app 确需网络再单独加。
- **品牌占位**:app 名/applicationId/图标/主色 全部集中在 `branding.dart` + android 配置,由 new_app 脚本一次替换。

## 生成一个新 app 的步骤

1. **选题**:从 reports/ 选一条候选,确定 app 英文名(kebab-case)和 applicationId(`com.<你的域>.<name>`)。
2. **克隆壳**:`node scripts/new_app.mjs <name> <applicationId> "<显示名>"` → 产出 `apps/<name>/`(复制 shell、改包名/显示名/目录)。
3. **写芯**:AI 在 `apps/<name>/lib/tool/` 下实现工具逻辑(遵守 ToolModule 契约,纯本地)。
4. **品牌**:生成图标(1024px 主图标 → `dart run flutter_launcher_icons`)、主题色、商店文案(标题30字/简述80字/长描述4000字,中英双语)存 `apps/<name>/store/`。
5. **验收(本地)**:`flutter analyze` 零 error → `flutter test`。**⚠️ 本机(8GB RAM,多会话共存)出不了 release 包**——Gradle JVM 已连崩 4 次(系统提交内存耗尽,压到 Xmx1024m+SerialGC 仍崩),**出包一律走 CI**。
   - **⚠️ analyze+test 过 ≠ 装机能用**(2026-07-24 教训:5 个 app 审计出 3 个真机 bug、1 个核心功能不成立)。写码前必须过两道**纸面评审**:① **招牌功能架构评审**——凡涉及「可靠性」的核心机制(闹钟必须准时响=setAlarmClock/前台服务而非通知调度、小组件必须自刷新=provider 端实时算而非 Flutter 端烤死数值、相机必须能 resume),先确认所选方案在 Doze/国产 ROM/生命周期下真的成立再动手;② **运行时权限流程评审**——每个用到的危险权限(通知/相机/定位)要有显式请求+被拒时的可见反馈+去系统设置的出口,禁止静默失败。完成后**必须请独立审计 agent 通读代码**按「真机会不会坏」出报告,修完才算过。
6. **出包(CI)**:`gh workflow run build-app.yml -R noobclaw/laura --ref main -f app=apps/<name>`(先 push!CI 从 main 拉代码)→ `gh run watch` → APK/AAB 在 run 的 artifacts(`<slug>-apk`/`<slug>-aab`)。壳验证过:shell 5m49s 出包成功。仓库是 public,Actions 免费。
   - **机器验收关卡(smoke-test job,2026-07-24 加)**:出包后 CI 自动起 Android 34 模拟器,装 APK → 启动 → 30s 后进程必须还活着 → logcat 无 FATAL EXCEPTION → 截屏传 artifact(`<slug>-smoke`)。**smoke 挂 = 本轮不算完成**,修到绿为止;绿了也只证明「能装能启动」,传感器/闹钟/小组件等仍需真机。**用语纪律:过了 smoke 只能标「待真机验收」,真机核心功能验过才准写「待上架」。**
   - **⚠️ 插件多的 app 要调大 Gradle 内存**:壳默认 `android/gradle.properties` 是为 8GB 本机压小的(Xmx1024m / MaxMetaspaceSize=384m),CI 上跑轻量 app 够用,但**装了多个原生插件(相机/定位/PDF/图像等)的 app,R8 阶段会 `OutOfMemoryError: Metaspace` 挂掉**。CI 跑在 16GB runner 上,给该 app 的 `android/gradle.properties` 提到 `Xmx4096m / MaxMetaspaceSize=1024m` 即可(见 apps/fieldstamp)。母版不动,只改该 app 自己的。
7. **签名**:当前 CI 出的是 debug 签名(能装能测)。上 Play 前要配 release keystore:keystore 存 GitHub Secrets(base64)+workflow 里解码写 `key.properties`,**别把 keystore 提交进这个 public 仓库**。signing 步骤已做容错:secret 缺失**或非法 base64** 时自动回退 debug 签名,不再中断整个 build(2026-07-15 修:曾因 `ANDROID_KEYSTORE_BASE64` 非法 base64 令 `bash -e` 直接失败)。

## 三期(未做):上架

- Google Play:fastlane supply 或 Play Console API 上传 AAB + 商店素材;新 app 首次上架需人工在 Console 建应用+过数据安全表单。
- App Store:需 macOS 构建(GitHub Actions macos runner,须用户授权),fastlane deliver。
- 节奏:每周 1-2 个,勿触发商店反垃圾(Apple 4.3 / Google 重复内容)。
