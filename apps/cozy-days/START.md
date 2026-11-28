# 本地试玩

在本目录运行 `python3 -m http.server 18771 --bind 127.0.0.1`，然后打开 http://127.0.0.1:18771/ 。静态构建已经包含，不需要安装依赖即可预览。

源代码位于 src、examples、web；需要重建时使用 Node.js 20+，执行 `pnpm install --frozen-lockfile --ignore-scripts` 和 `pnpm run build`。新作源图和生成记录在 presentation/american-v1；自动检查及截图在 verification。本包不含研究工程的旧图片。

关卡仍为 2.5D；主页装箱为真实 3D 刚体。内购、广告和平台打包未接入，验收范围见 ACCEPTANCE.md。
