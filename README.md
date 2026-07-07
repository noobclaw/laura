# laura — 工具 App 自动化工厂

每天自动采集热点 → 产出情报日报 → 从选题生成无服务端工具 App → 构建上架。

## 目录

| 路径 | 内容 |
|---|---|
| `reports/YYYY-MM-DD.md` | 每日情报报告(趋势/候选选题/当日原型) |
| `apps/<name>/` | 每个生成的 App 一个独立文件夹(完整 Flutter 工程 + `store/` 商店素材) |
| `shell/` | Flutter 壳工程模板 —— 所有 App 的母体,只换 `lib/tool/` 芯 |
| `collectors/` | 热点采集器(GitHub Trending / App Store / Google Play / Show HN) |
| `scripts/new_app.mjs` | 从壳克隆出新 App(改包名/显示名) |
| `CLAUDE.md` | 每日定时任务的作业说明书 |
| `PIPELINE.md` | 选题 → 成品 App 的流水线文档 |

## 运行

```bash
npm install
node collectors/run_all.mjs          # 采集当日数据到 data/
node scripts/new_app.mjs <name> <applicationId> "<显示名>"   # 生成新 app
```

日报由 Claude Code 定时任务每天 09:00 自动生成并推送本仓库。
