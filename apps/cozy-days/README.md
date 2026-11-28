# Sorting Engine

独立的整理消除游戏内核，使用 JavaScript ES Modules，规则内核无需第三方依赖。正常试玩的表现层使用 Three.js / React Three Fiber，配合 Rapier、ThreeQuarks、postprocessing、Anime.js 与 drei，版本见锁文件。

## 运行

要求 Node.js 20 或以上。此版本用 Node.js 24.22.3 验证。

```sh
pnpm install --frozen-lockfile --ignore-scripts
pnpm test
pnpm run build
node examples/play.mjs 160
```

浏览器验收预览：

```sh
python3 -m http.server 18767 --bind 127.0.0.1
```

打开 `http://127.0.0.1:18767/`，默认进入正常闯关，按进度解锁 160 关。新版前 20 关采用渐进物品量和双类别分层，前三关为 18/28/36 件，穿插缓冲与挑战关；后续关卡暂沿用现有配置。入场或重开用 1 体力，胜利返还本次入场的 1 点，续玩不重复扣除；体力默认 5，每 30 分钟恢复 1 点。前 20 关的三星门槛为 max(60 秒, 物品数 × 3.5 秒)，二星为 max(100 秒, 物品数 × 5.5 秒)，后续仍为每件物品 3/5 秒。新旧局分别保存版本，已经开始的一局使用其原有配置和体力规则。当前新局为 neighborhood-3，另外修正第 33–39 关同名类别重复身份的问题；不改物品坐标、总量与每条需求数量。已开始的 classic / neighborhood-1 / neighborhood-2 局继续按旧配置恢复，重开后使用新版。

新版在第 3/4/5/7 关依次开放寻物、移回、装箱、擦除，各一种赠送体验。旧版已开始的一局保持当时的解锁规则。赠送寻物提示只能激活 1 件，后续普通额度为 3 件。正常模式按余额扣除；余额不足时说明尚未接广告/付费，不模拟购买成功。第 5 关开放相册收集，支持 48 张照片与 8 页；23 项成就随行为累计；第 12 关开放每日竞速和周联赛，支持实际结算与体力领奖。排行榜使用 10,000 名本地模拟对手，页面明确标示。

独立沙盒在 `http://127.0.0.1:18767/lab.html`，仍可直接选择全部 160 关、无限使用测试道具。沙盒与正常模式使用不同存档键，不累加正式进度、相册、成就或活动奖励。已有沙盒单局存档保持可用。

当前 american-v1 已替换所有运行时图片：425 张新物品绘图、8 个房间、主页、导航/工具图标与 48 张组合相册。部分同类变化共用新图，并非将旧变化逐张重画。关卡仍为 2.5D 图片平面，主页装箱使用真实 3D 刚体；飞入、光点、到达光环、纸带、接触阴影、材质音效与减少动效已接入。放大和纵向排布使用统一展示坐标，原关卡记录与存档身份保持。完整证据和限制见 [验收记录](presentation/american-v1/ACCEPTANCE.md)。没有接入支付、广告、联网账户或平台构建。补给站展示分阶段工具包，商店未连接时购买按钮禁用，不扣款、不发放虚构购买。

## 结构

- `src/session.js`：单局状态、点击与遮挡、目标接续、暂存、提示、道具、复活、存档验证。
- `src/spatial.js`：多边形与透明像素轮廓、命中、距离、面积和联合遮挡。
- `src/progress.js`：体力、关卡进度、星级、奖励凭据去重、道具余额与恢复。
- `src/playthrough.js`：将单局、账户、相册、成就和活动合并为原子保存的正常闯关流程。
- `src/festivals.js`：每日竞速、每周联赛、晋降级、里程碑与领奖。
- `src/opponents.js`：10,000 名模拟对手、每日得分分布与时间表。
- `src/collections.js`：48 张相册照片的收集进度与成就。
- `src/calendar.js`：时区、每日边界、周一边界及夏令时。
- `data/`：完整关卡、碰撞轮廓与数值配置。
- `presentation/american-v1/`：本轮新作、运行时资源与验收记录。
- `art/`：研究留档，不作为当前正常试玩的运行时图片来源，也不包含在干净交付包。
- `test/`：无需对照工程即可执行的测试。
- `examples/play.js` / `game.css`：正常闯关、结果与五个外围页面；`lab.js` / `lab.css`：独立测试界面。

## 接口

```js
import { SortingSession, readStage } from './src/index.js';
const { stage, forms } = await readStage(1);
let round = new SortingSession(stage, forms, {
  bays: 3,
  trayMode: 'flexible',
  promptPolicy: 'classic',
  prompts: true,
});
round.dispatch({ kind: 'collect', tokenId: 0 });
round.dispatch({ kind: 'advance', seconds: 1 / 60 });
const current = round.inspect();
const events = round.takeSignals();
const checkpoint = round.save();
round = SortingSession.resume(stage, forms, checkpoint);
```

`inspect()` 返回副本，不能通过修改它改变内核。每次输入后读取事件更新界面；动画时长不决定规则处理时机。时间由调用方传入，存档包含关卡绑定和守恒验证。

常用命令：`pointer`、`collect`、`advance`、`expandBay`、`expandTray`、`sweepBay`、`erase`、`reverse`、`returnTray`、`prompt`、`scanGrant`、`scanActivate`、`scanFocus`。`locate()` 查询普通点击目标，`locateErase()` 查询擦除目标，`latestTrayTokens()` 查询最近暂存顺序。

暂存规则有 `flexible`、`explanatory`、`strict`、`expanded` 四种；目标槽有 3 与 4 两种容量；提示有 `classic`、`reachable` 两种。分类合并可用 `grouping: { pairs: [[source, target]] }` 注入。

账户通过 `PlayerJournal` 管理。构造时注入 `clock` 和原子持久化函数 `persist`，写操作返回 Promise。失败的写入不发布账户新状态；道具应用未完成时保留恢复记录。`FestivalBook` 可注入时钟、时区、持久化与按凭据去重的奖励回调。

支付、广告与账户服务的适配器应在确认授权后调用 `grantReceipt()`；内核负责凭据去重与道具余额。此包不包含平台 SDK、商店验证、线上账户或服务端。当前存档使用独立格式，旧格式迁移属于外部适配边界。

正常试玩支持简体中文、繁体中文与英文切换，文案集中在 `examples/strings.js`；其他语种尚未补齐。内核事件不含显示文案。独立沙盒使用英文。

正常存档使用 `sorting-playthrough-v1`。每次输入在内存草稿中处理，将账户、棋盘、成就、相册和活动一起持久化成功后才发布；写盘失败时不提交该次操作。单局每 5 秒及离开页面时额外保存，切换到首页、弹窗暂停或标签页隐藏时不计游戏时间。刷新后点“继续整理”恢复现有一局。其他标签页更新同一存档时会拒绝覆盖并提示刷新。本地存档不是跨设备云存档。

## 表现层与可读性

所有尺寸采用上下紧凑布局：上方需求箱（类别名、多图示例、点击查看全组），下方暂存栏和道具；没有左右侧栏。关卡和暂停并入上方需求箱一行，体力、星星、商店及设置收入暂停菜单。390×844 视口实测棋盘 368×674，约占屏幕面积 75%，没有横向溢出。房间背景保持原始世界坐标与尺寸；视口超出背景底边时只延伸底部地板纹理，不移动或缩放房间及物品。镜头根据整局初始物品范围取景，不随拿走物品反复跳动。右上角放大镜切换 1.6 倍查看，放大时可拖动，拖动不会选中物品。棋盘按 2 倍像素渲染，不对关卡图片叠加泛光；装饰场景保留轻微后处理。设置支持音效开关、减少动效及三种语言。后台暂停表现和计时。

- `src/campaign.js`：前期曲线、版本与渐进解锁；基础关卡数据不被覆盖。
- `src/view.js`：物品取景、缩放、拖动及点击坐标转换。
- `src/shop.js`：工具包与商店展示状态，不包含真实支付网关。
- `web/scenes.jsx`：R3F 场景、纹理、刚体、粒子和后处理。
- `examples/feedback.js`：飞入、按钮、星级、礼花和合成音效。
- `presentation/`：首页背景与图标图集；`third-party/` 与 `THIRD_PARTY_NOTICES.txt` 保留依赖许可证。

构建产物已随工程提供；仅试玩不必安装 Node 依赖。重新构建使用锁定依赖，`pnpm run build` 会更新入口及第三方许可说明。此版本的 esbuild 使用已安装的官方可选平台二进制，不需要启用依赖安装脚本。

需求箱图片代表类别，不代表只收这一种外形；例如电脑配件包括键盘、鼠标和耳机。直接命中一个物品时，触控辅助不再改选另一个附近物品。语言切换保持设置弹窗打开；减少动效时装饰物在箱内静态摆放。图形中断显示重新载入入口并冻结棋盘输入与计时。
