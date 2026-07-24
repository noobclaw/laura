# 干净闹钟 Clean Alarm — PLAN

> 一句话定位:一个**零广告、零联网、零权限滥用**的极简闹钟。你只需要一个能准时响、不弹广告、不偷数据的闹钟。

## 为什么做它

来自 BACKLOG #8(指数 58)。Play Productivity 榜的闹钟洼地(MeloTick 3.09 分)证明:这个刚需品类的现有对手不是「贵」而是「烂」——满屏广告、要一堆权限、界面花哨。缺口叙事 = 「干净」:一次买断去掉一切多余,永远离线。开发量最小(纯确定性时间数学 + 系统本地通知调度),正好走通整条上架流程,适合当自动流水线的确定性工程取项。

按 BACKLOG 开工日决策门:`#7 AutoSnore 美区未站回 Top40 内(#41)` → 退取 `#8 干净闹钟` 作练手首发。

## 变现

- **免费**:核心闹钟功能全开(添加/编辑/重复/贪睡/震动),免费上限 **5 个闹钟**。
- **Pro 一次性买断 ¥6 / $0.99**:解锁**无限闹钟** + **主题强调色**。
- 不做广告(与「干净/离线零权限」卖点直接冲突,且流水线母版零 INTERNET)。BACKLOG 原写「免费+去广告 ¥6」,本实现改为「免费+Pro 买断」以守住零联网卖点——记于此。
- v1 内购为**本地解锁标志占位**(与 remcard/daycount/goldenscout 一致),接商店结算在上架前统一做。

## 功能清单(v1 只做核心)

- 闹钟列表:大字号时间、标签、重复日摘要、启用开关、下次响铃倒计时(「X 小时 Y 分钟后响铃」)。
- 新建/编辑闹钟:滚轮时间选择、标签、**按星期重复**(每天/工作日/周末/自选)、贪睡时长(关/5/10/15 分钟)、响铃声开关、震动开关。
- 删除(左滑 / 详情删除)。
- 精确调度:`flutter_local_notifications` 的 `zonedSchedule` + `exactAllowWhileIdle`,**全屏意图**(锁屏唤醒)、闹钟音频通道(`AudioAttributesUsage.alarm`)、自带闹钟音色(res/raw 内置 WAV,非依赖系统静音铃声)、震动。
- 重复闹钟:每个选中的星期各排一条 `dayOfWeekAndTime` 匹配的通知;开机后由插件的 `ScheduledNotificationBootReceiver` 自动重排。
- 贪睡 / 关闭:通知动作按钮(锁屏可点),贪睡经后台 isolate handler 重排 +N 分钟一次性通知。

## 页面结构

- **主页**(`AlarmListView`):闹钟卡片列表 + 右下 FAB「新建闹钟」;空态引导。
- **编辑页**(`AlarmEditPage`):时间选择 + 标签 + 重复星期 chips + 贪睡/声音/震动开关 + 保存/删除。
- **设置**(壳 `SettingsPage` + 本工具 `buildSettingsItems`):解锁 Pro、主题强调色(Pro)、通知权限引导、隐私政策、关于。

## 技术要点

- 纯 Dart 时间数学 `nextTrigger(alarm, now)`:一次性=今天/明天最近一次;重复=未来 7 天内最近的选中星期,均以**本地墙钟时间**计算,有单元测试覆盖(边界:今天时间已过→明天、跨周回绕、全周、工作日/周末)。
- 存储:`path_provider` 单 JSON 文件 `clean_alarm.json`(闹钟列表 + pro + 强调色 + notifId 自增),失败降级空库不崩。
- 通知调度全部 `try/catch` 包裹,测试环境(无插件平台端)静默 no-op,保证 `flutter test` 绿。
- **零网络**:`AndroidManifest` 以 `tools:node="remove"` 剥离 INTERNET;声明 `POST_NOTIFICATIONS / SCHEDULE_EXACT_ALARM / USE_EXACT_ALARM / USE_FULL_SCREEN_INTENT / VIBRATE / RECEIVE_BOOT_COMPLETED`。
- `MainActivity` 加 `showWhenLocked` / `turnScreenOn`,全屏意图能在锁屏点亮屏幕。
- CI Gradle 内存提到 `Xmx4096m / MaxMetaspaceSize=1024m`(通知/时区插件带原生代码,防 R8 Metaspace OOM,同 fieldstamp)。

## 商店定位

- 分类:工具 / 效率(Tools / Productivity)。
- 关键词:闹钟、简约闹钟、离线闹钟、无广告闹钟、贪睡、alarm clock、simple alarm、offline、no ads、minimal。
- 定价:免费下载 + 应用内 Pro 买断 ¥6 / $0.99。

## 已知限制(v1,待真机验证)

- **未真机验证**(本机 8GB 不能出包):精确闹钟权限弹窗、全屏意图锁屏点亮、贪睡后台重排、自带音色音量、各 OEM 省电策略下的准时性需装机确认。
- 响铃为「高优先级全屏通知 + 一次性音色(约 5 秒)」,非持续循环长响;循环长响 / 渐强音量留 v1.1(需前台服务或 `alarm` 包 + 音频资源)。
- 一次性闹钟响过后 UI 开关仍显示「开」(无进程回调翻转);重复闹钟不受影响。
- iOS 原生侧(通知权限/后台)未配置,当前只出 Android 包。
