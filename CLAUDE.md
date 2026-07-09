# toolapp — 工具型 App 热点情报 + 日报流水线

每天自动采集 GitHub / App Store / Google Play / Hacker News 的工具类热点，产出一份分析报告 + 一个 app 原型设计。最终目标：从报告中选题 → AI 开发无服务端工具 app → 自动上架（二期/三期，见下）。

## 目录结构

```
collectors/          # 采集脚本(Node 24+, ESM)
  run_all.mjs        # 入口:跑全部采集器,写 data/YYYY-MM-DD/*.json
  github_trending.mjs   # GitHub trending 页抓取(daily+weekly)
  appstore_rss.mjs      # Apple 官方 RSS(us/cn × top-free/top-paid,含工具类标记 isToolLike)
  google_play.mjs       # google-play-scraper(us × tools/productivity/photography TOP_FREE)
  hn_showhn.mjs         # HN Algolia API,近7天 Show HN ≥50分
data/YYYY-MM-DD/     # 当日原始数据(json,gitignore 不入库)
reports/YYYY-MM-DD.md  # 当日报告(最终交付物,推 GitHub)
shell/               # Flutter 壳工程模板(见 PIPELINE.md)
apps/<name>/         # 每个生成的 app 一个独立文件夹(推 GitHub)
scripts/new_app.mjs  # 克隆壳→新 app
```

远程仓库:`https://github.com/noobclaw/laura`(main)。报告与 apps/ 每次产出后都要 push。

## 每日定时任务的作业流程

1. `node collectors/run_all.mjs`(需网络,沙箱拦截时用 dangerouslyDisableSandbox)。看 stdout:允许个别源失败(记入 summary.json),全失败才算任务失败。
2. 读当日 `data/YYYY-MM-DD/` 下各 json(大文件别整读,用 node -e 浓缩打印再分析)。
3. 与**前几天的报告**(reports/ 下最近 2-3 份)对比,识别「新上榜/持续升温/掉榜」。
4. 写 `reports/YYYY-MM-DD.md`,格式见下。
5. **推 GitHub**:本仓库远程是 `https://github.com/noobclaw/laura`(main 分支)。`git add reports/ apps/ && git commit && git push origin main`(commit message 全英文;push 前先 `git fetch` 确认 fast-forward;PowerShell 里 push 的红字 NativeCommandError 是假错误,以 `git log origin/main` 为准)。
6. 报告写完后,在回复里给用户一段 5 行以内的中文摘要(今日最值得做的 1 个选题 + 理由)。

## 报告格式(reports/YYYY-MM-DD.md)

```
# 工具 App 情报日报 — YYYY-MM-DD
## 一、今日信号(各源要点 + 与昨日对比)
## 二、趋势主题(跨源交叉出现的 2-4 个主题)
## 三、候选 App 清单(3-5 个,每个含:一句话定位/核心功能/目标用户/竞品与其弱点/变现/无服务端可行性/开发量估计)
## 四、今日原型(从候选中选 1 个展开:页面结构、核心交互流程、技术要点、商店定位[分类/关键词/定价])
## 五、观察池(还不够成熟但值得跟踪的信号)
```

## App 落地节奏(用户 2026-07-07 拍板)

- **每日选题进队列**:每天日报产出后,更新 `BACKLOG.md`(候选队列):合并当日新候选与既有队列,基于**全部历史数据**(目标过去 1~4 个月;不足用现有全部)按「值得做」**重新排序**。排序依据:①信号持续性(出现天数/多源交叉,权重最高) ②付费意愿验证(付费榜有同类) ③开发量(小优先) ④质量缺口(竞品评分低)。
- **每 3 天落地 1 个**(定时任务 `app-factory-3d`):**不自己选题,直接取 BACKLOG.md 排名最前的「待做」项**开发,开发全自动,完成后通知用户装机验收。
- **严禁重复**:BACKLOG 里已做项标 `✅已做`、否决项标 `❌否决`(附一句原因),永不删行;新候选与已做/否决项相同或高度相似的不入队。

### BACKLOG.md 格式

```
# App 候选队列(每日重排,3天任务从队首取)
| # | 选题 | 状态 | 信号(出现天数/来源) | 一句话定位 | 变现 | 开发量 |
```
状态:`待做` / `✅已做(apps/<name>)` / `❌否决(原因)`。排序只排「待做」,已做/否决沉底存档。
- 每个 app 文件夹里必须有 `PLAN.md`(定位/功能清单/页面/定价)和 `store/`(商店文案)。
- 变现默认「免费+一次性内购买断」;走量品类可用「免费+去广告内购」;定价写进 PLAN.md。
- 上架节奏与开发节奏分离:开发 3 天一个,**上架仍每周 1-2 个**(商店反垃圾),做好的 app 排队等发布。

## 选题硬性标准

- **必须无服务端**:纯本地逻辑(计算/文件处理/相机/传感器/本地模型),不依赖自建后端。可用系统能力与设备端模型。
- 工具型:解决一个具体小问题,单手可描述清楚。
- 有付费/内购空间(参考 top-paid 榜验证付费意愿)。
- 避开垃圾赛道:清理加速类、壁纸类、山寨 VPN。
- 加分:多平台同时出现信号;现有头部竞品评分 < 4.0(质量缺口)。

## 采集器备注(踩过的坑)

- HN Algolia 的 numericFilters 不再支持 `points`,只能按 `created_at_i` 过滤、分数本地过滤。
- App Store CN 区 RSS 返回中文分类名(工具/效率/摄影与录像),TOOL_GENRES 已含。
- appstore.json 用 PowerShell 5.1 的 ConvertFrom-Json 会假报错,验证 JSON 一律用 `node -e "require(...)"`。
- GitHub trending 是抓 HTML,解析 0 条 = 页面结构变了,要修 `parseTrendingHtml`。
- google-play-scraper 是非官方库,偶发被限流;单类目失败不致命(errors 字段记录)。

## 后续阶段(未做)

- 二期:Flutter 壳工程 + 「选题 → AI 生成完整 app + 商店素材」流水线 + CI 构建。
- 三期:fastlane 自动提交上架(先 Google Play 后 App Store)。用户已有开发者账号。
- 节奏约束:商店反垃圾政策(Apple 4.3 / Google 重复内容),上架节奏每周 1-2 个,不可每日上架。
