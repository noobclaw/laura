# 二期:选题 → 成品 App 流水线

从日报选题到可上架 APK/AAB 的标准流程。原则:**壳不动、只换芯**——所有 app 共用一个壳工程,每个新 app 只替换 `lib/tool/` 里的工具模块和品牌资源。

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
6. **出包(CI)**:`gh workflow run build-app.yml -R noobclaw/laura --ref main -f app=apps/<name>`(先 push!CI 从 main 拉代码)→ `gh run watch` → APK/AAB 在 run 的 artifacts(`<slug>-apk`/`<slug>-aab`)。壳验证过:shell 5m49s 出包成功。仓库是 public,Actions 免费。
   - **⚠️ 插件多的 app 要调大 Gradle 内存**:壳默认 `android/gradle.properties` 是为 8GB 本机压小的(Xmx1024m / MaxMetaspaceSize=384m),CI 上跑轻量 app 够用,但**装了多个原生插件(相机/定位/PDF/图像等)的 app,R8 阶段会 `OutOfMemoryError: Metaspace` 挂掉**。CI 跑在 16GB runner 上,给该 app 的 `android/gradle.properties` 提到 `Xmx4096m / MaxMetaspaceSize=1024m` 即可(见 apps/fieldstamp)。母版不动,只改该 app 自己的。
7. **签名**:当前 CI 出的是 debug 签名(能装能测)。上 Play 前要配 release keystore:keystore 存 GitHub Secrets(base64)+workflow 里解码写 `key.properties`,**别把 keystore 提交进这个 public 仓库**。signing 步骤已做容错:secret 缺失**或非法 base64** 时自动回退 debug 签名,不再中断整个 build(2026-07-15 修:曾因 `ANDROID_KEYSTORE_BASE64` 非法 base64 令 `bash -e` 直接失败)。

## 三期(未做):上架

- Google Play:fastlane supply 或 Play Console API 上传 AAB + 商店素材;新 app 首次上架需人工在 Console 建应用+过数据安全表单。
- App Store:需 macOS 构建(GitHub Actions macos runner,须用户授权),fastlane deliver。
- 节奏:每周 1-2 个,勿触发商店反垃圾(Apple 4.3 / Google 重复内容)。
