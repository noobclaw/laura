# 04 原生 iOS（SwiftUI）路线

2026-11 Groovelens 起，高质量 App 可以走原生 SwiftUI（不套 Flutter 壳）。本页是这条路线踩出来的做法。范例工程：`apps/groovelens/`。

## 工程骨架
- **XcodeGen**：仓库只提交 `project.yml`，不提交 `.xcodeproj`；CI 里 `brew install xcodegen && xcodegen generate`。
- 目标：iOS 17+、`TARGETED_DEVICE_FAMILY=1`、竖屏、`SWIFT_VERSION 5.0`（Swift 6 严格并发会让第一版卡在大量告警上，稳定后再升）。
- `GENERATE_INFOPLIST_FILE NO` + 手写 `Info.plist`：
  - `CFBundleDisplayName` 英文；`CFBundleVersion = $(CURRENT_PROJECT_VERSION)`（CI 传入递增 build 号）。
  - 每个 `NS*UsageDescription` 写清用途（「用来听你敲鼓并打分」，不是「需要麦克风」）。
  - `ITSAppUsesNonExemptEncryption = false`；`UILaunchScreen` 用 asset 里的颜色；`UIAppFonts` 列出字体文件。
  - 不加用不到的 `UIBackgroundModes`。
- 目录：`App/`（入口、根视图）、`Model/`（SwiftData 模型、文件布局）、`Analysis/` 或 `Core/`（纯算法，不 import SwiftUI，方便测）、`Audio/`、`Game/`、`Store/`、`Design/`（Theme、Components）、`Features/<页面>/`、`Export/`、`Resources/`（Fonts、xcstrings）、`Assets.xcassets`。
- 测试 target：`<App>Tests`，`TEST_HOST` 指向 App，用 `@testable import`。

## 状态与数据
- `@Observable` 做模型；不需要触发界面刷新的内部状态加 `@ObservationIgnored`。
- 全局服务（Store、Profile、任务中心）用 `.environment(obj)` 注入，视图里 `@Environment(Type.self)`。
- SwiftData 只放元数据；大文件（音频、分析结果 JSON）放 `Application Support/<Kind>/<uuid>/`，模型存相对位置。
- 持久化的偏好放 `UserDefaults` 的 JSON 块，**构造函数接收 `UserDefaults` 参数**，测试用独立 suite。
- 随机但「当天稳定」的东西（每日任务）用自己的种子 RNG + 日期 FNV 哈希；`String.hashValue` 每次启动都不同，不能当种子。

## 后台任务与并发（审计常见 P0）
- 长任务用 `Task.detached`，进度回主线程更新。**每次回主线程先检查模型是否已被删除**（`isDeleted` / `modelContext == nil`），否则用户中途删除会崩。
- 内层循环里 `try Task.checkCancellation()`，否则取消要等整段算完。
- `beginBackgroundTask` 必须带过期回调：取消任务并 `endBackgroundTask`，否则会被系统杀掉。
- 音频线程不要读 `@Observable` 属性：在 didSet 里同步一份普通变量给音频线程用。
- 从相册导入的临时文件用完即删。

## 音频（AVAudioEngine）
- 多轨同步：所有 player 在同一个 `AVAudioTime(hostTime:)` 上 `play(at:)`。
- 变速不变调：`AVAudioUnitTimePitch` 放在 submix 之后。
- 「用户听到的时间」= 渲染时间 − `outputLatency × rate`。
- 麦克风 onset 换算到歌曲时间：以 player 的 `lastRenderTime`（同时有 host 和 sample 时间）为锚点，按 host 时间差 × rate 外推；再减输入延迟、输出延迟和用户校准偏移。不要直接把只含 host time 的 `AVAudioTime` 丢给 `playerTime(forNodeTime:)`。
- 来电、拔耳机会让引擎暂停：上层每帧检查「本该在播但引擎停了」→ 切到暂停菜单，不要让画面冻住。
- 提供「延迟校准」：节拍器 + 用户跟拍，取中位数偏移。

## 渲染与动效
- 高频画面（游戏轨道、波形）用 `Canvas` + `CADisplayLink`（120Hz，通过 NSObject 代理转发 selector），不要用一堆 SwiftUI 视图。
- 轻量循环动画用 `TimelineView(.animation(minimumInterval:paused:))`，`paused` 接「减少动态效果」。
- 多点触控（鼓垫、键盘类）用 `UIViewRepresentable` 自己处理 `touchesBegan`，不用 `Button`（手势识别有延迟、不能同时按）。
- 数字滚动：`contentTransition(.numericText())` 或自定义 `Animatable` 文本。
- 屏幕常亮只在演奏/录制页开，离开时关。

## 字体
- OFL 字体用 fontTools 实例化成需要的静态字重（可变字体在 iOS 上按名字取字重不可靠），PostScript 名写进代码。
- 许可证 `OFL-*.txt` 一起打包，设置页「字体与许可」可读。
- CJK 语言（ja/ko/zh）下展示字体退回系统圆体（`.rounded` 设计 + heavy），数字仍用 HUD 字体。

## 本地化
- `Localizable.xcstrings`（String Catalog），源语言 en；代码里一律 `String(localized:)` 或 `Text("...")` 字面量。
- 显示名本地化用 `InfoPlist.xcstrings`。
- 目标语言（2026-11 起）：en、zh-Hant、zh-Hans、ja、ko、de、fr、es、pt-BR、it。翻译写进 xcstrings，不靠运行时。

## 内购（StoreKit 2）
见 `05-变现与内购.md`。要点：`Product.products(for:)`、`Transaction.updates` 常驻监听、`currentEntitlements` 刷新、`AppStore.sync()` 恢复、价格只用 `displayPrice`、`.storekit` 文件挂在 scheme 上做本地测试。

## CI（GitHub Actions macos-15）
- 本机没有 Xcode：一切编译、测试、截图都在 CI 上跑。
- `gh` token 不可用时，CI 把日志和截图 **force-push 到结果分支**（例如 `<app>-ci`），本地 `git fetch origin +refs/heads/<app>-ci:refs/remotes/origin/<app>-ci` 读回。注意 `git fetch origin <分支>` 不一定更新远程跟踪分支，要写完整 refspec。
- 构建 job：选最新 Xcode → xcodegen → `xcodebuild test`（模拟器，`CODE_SIGNING_ALLOWED=NO`）→ 装包启动 → `simctl io screenshot` → `log show` 抓运行日志 → 推结果分支 → 最后一步按测试结果判失败。
- TestFlight job：`needs: build`，由提交信息含 `[testflight]` 或手动触发。导入 p12 到临时 keychain → `xcodebuild archive` 带 `-allowProvisioningUpdates` + ASC API key 云签名 → `-exportArchive`（method `app-store-connect`）→ `xcrun altool --upload-app`，**grep 输出里的 ERROR 判失败**（altool 出错也可能退出 0）。build 号用 `100 + run_number` 递增。
- 已有 Secrets：`ASC_API_KEY_P8`、`ASC_API_KEY_ID`、`ASC_API_ISSUER_ID`、`APPLE_TEAM_ID`、`IOS_DEV_CERT_P12`、`IOS_CERT_PASSWORD`。

## 上传前必须人工做的（API 做不了）
1. App Store Connect 里**先建 App 记录**（bundle id 由云签名自动注册），主语言 English (U.S.)，否则上传报找不到 App。
2. 内购商品在 ASC 建好（ID `<bundleId>.pro_unlock`，非消耗型），否则 TestFlight 里拉不到价格。
3. 内部测试员接受一次邀请，测试组勾「自动分发」。
