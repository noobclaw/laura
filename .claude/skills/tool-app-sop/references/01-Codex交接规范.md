# 01 Codex 交接规范

## 1. 交给 Codex 的任务模板（复制后填空）

```
目标：为 noobclaw 做 <品类> 工具 App 找对标竞品并做初步产品整理。
1. 从 <榜单/区域/日期> 选 1 个竞品：付费榜或畅销榜前 100、评论数 ≥1,000、仍在更新（近 6 个月有版本）。写明为什么选它。
2. 获取它的 Android 包（APK/XAPK，来源写清楚）或开源仓库；反编译（jadx）出 resources 与 sources。
3. 交接包放到 Desktop/<竞品>-产品分析/，结构见下。
4. 写初步报告（中文 md）：信息架构、每个页面的功能、设置项全集、付费点与价格、广告位、弹窗时机、权限、第三方服务、远程配置、你觉得的弱点。
5. 不要删减资源文件；不要只给摘要。
```

## 2. 交接包必须包含

| 项 | 必须 | 说明 |
|---|---|---|
| 初步报告 md | ✅ | 文件名用英文或拼音，避免中文文件名乱码（Total 那次报告文件名乱码了） |
| `AndroidManifest.xml` | ✅ | 权限、组件、深链、Service |
| `res/values/strings.xml`（及其他语言 `values-xx/`） | ✅ | 文案是功能清单最全的来源 |
| `res/xml/*`（设置页 preference、file paths） | ✅ | 设置项全集 |
| `sources/<主包名>/` | ✅ | 控制器、模型、服务 |
| `assets/`（远程配置样例、网页、JSON） | ✅ | 默认配置常在这里 |
| 商店链接（iOS + Android，主要区域） | ✅ | Claude 自己再补评论 |
| 截图（每个页面 1 张） | 建议 | 没有就 Claude 从商店截图补 |

**路径深度**：桥接只能取到约 8 层深的文件。让 Codex 把关键深层目录（如 `view/widget/`）**另外平铺复制一份**到 `flat/`，否则读不到。

## 3. 接收清点（第 1 步闸）

1. `device_list_dir` 递归列交接包，统计文件数。
2. 先读：报告 → Manifest → strings.xml → 设置 xml → assets 配置 → 控制器/服务（按名字里含 Controller/Manager/Service/Config/Purchase/Billing/Ads/Rate/Review/Share/Referral 的优先）。
3. 写清点表到 TEARDOWN 的「材料」行：读了哪些、多少个、**哪些读不到及原因**。
4. 报告里的每个说法都要在源码/资源/商店页里找到证据；找不到的标「仅报告所述，未证实」。
5. 报告有而资源里没有的功能（或反过来）列入差异，第 2 步逐条核。
