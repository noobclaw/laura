# 倒数日 (DayCount) — PLAN

## 一句话定位
把生日、纪念日、考试、旅行等重要日子做成倒计时/累计天数，并放到主屏小组件一眼可见 —— 全程本地、不联网。

## 目标用户
学生（考试/开学倒数）、情侣与家庭（生日/纪念日）、职场（deadline/发薪日）、旅行党（出发倒数）。中区为主战场（付费品类「时间规划局/时间块」长青验证），英文市场为次。

## 竞品与缺口
同类多为设计平庸的免费+banner 广告，或重订阅。缺口最弱（拼设计而非填质量洼地），差异点押在：① 干净的 Material 3 视觉；② **好用的桌面小组件是主体验**（本品类核心卖点）；③ 一次买断、零广告、零联网的隐私姿态。

## 功能清单（v1 只做核心）
- 事件列表：每条含 标题 / 目标日期 / emoji 图标 / 主题色 / 备注。
- 自动判定 **倒数（未来）/ 累计（已过）/ 就是今天🎉**，无需手选模式。
- **每年重复**：生日、纪念日自动跳到下一次（含闰年 2/29 → 平年 2/28 兜底）。
- **置顶**：置顶项排最前，并作为小组件展示对象。
- 排序：置顶 → 最近的未来 → 最近发生的过去。
- 新增 / 编辑 / 删除；日期选择器；emoji 与颜色选择器。
- **Android 桌面小组件**（`home_widget`）：展示最靠前的一条（置顶或最近），点击回 App。
- 免费上限 5 条；解锁 Pro 去除上限 + 全部主题色。
- 设置：解锁 Pro、手动刷新小组件、隐私政策、关于。

## 页面结构
- 主页 `daycount_tool.dart`：列表 + 空状态 + 悬浮「添加日子」。卡片 = 图标块 / 标题 / 目标日期·星期·每年 / 天数徽章。
- 编辑页 `event_edit.dart`：标题、日期、每年重复、置顶、emoji、颜色（后 6 色 Pro 门）、备注。返回 `EventDraft`。
- 详情页 `event_detail.dart`：大色块天数、日期/重复/距今/备注，顶部置顶·编辑·删除。
- 设置项由 `ToolModule.buildSettingsItems` 注入（Pro / 刷新小组件）。

## 技术要点
- 纯 Dart 日期数学（`models.dart`），全部 UTC 计算避免 DST 漂移；有 18 项单元测试。
- 持久化：`path_provider` 单 JSON 文件（`daycount.json`），仿 remcard 的 `ChangeNotifier` store。
- 小组件桥：`home_widget` 把「featured」事件写入共享偏好 `HomeWidgetPreferences`，原生 `CountdownWidgetProvider`（Kotlin，纯 RemoteViews，不依赖插件 Kotlin 类）读取渲染。所有 `HomeWidget.*` 调用 try/catch，桌面/测试环境降级为 no-op。
- **零网络**：AndroidManifest 用 `tools:node="remove"` 剥离 INTERNET，卖点可验证。
- CI 内存：`android/gradle.properties` 提到 Xmx4096m/Metaspace1024m（母版不动，仅本 app）。

## 定价
免费 + 一次性内购买断（默认口径）。建议中区 **¥8 / 海外 $1.99** 解锁 Pro（无限日子 + 全部主题色）。参考 BACKLOG 中区 ¥6-12 买断带。内购 SDK 尚未接入，当前为本地解锁占位。

## 商店定位
- 分类：效率 / 工具。
- 关键词（中）：倒数日、纪念日、倒计时、生日提醒、小组件、日子、恋爱天数、考试倒计时。
- 关键词（英）：countdown、days until、anniversary、widget、event countdown、date counter。

## 待办（非 v1）
- 本地通知（当天/前 N 天提醒，flutter_local_notifications；native 面较大，v2）。
- iOS WidgetKit 小组件（当前小组件仅 Android）。
- 真实内购（in_app_purchase）接入替换本地解锁占位。
- 装机验收：小组件添加与刷新、`home_widget` 共享偏好键名、emoji 在小组件 RemoteViews 的显示、颜色对比。
