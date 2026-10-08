# 采集器运行环境

Node 24+；Python 3.11+（需 OpenSSL 1.1.1+，避免 macOS 系统 Python 的 LibreSSL）。首次恢复工作区时安装依赖：

```sh
npm ci --no-audit --no-fund
python3.11 -m venv .venv
.venv/bin/python -m pip install -r collectors/requirements.txt
```

也可用 `uv venv --python 3.11 .venv` 和 `uv pip install --python .venv/bin/python -r collectors/requirements.txt`。Windows 虚拟环境解释器为 `.venv/Scripts/python.exe`。

macOS 自动化的联网命令须通过 `scheduled-tasks/local-paths.json` 指定的系统代理包装器。当前映射示例（在 laura 项目根目录运行）：

```sh
TZ=Asia/Shanghai node /Users/duke/Documents/ChatGPT/noobclaw/scripts/run-with-system-proxy.cjs node collectors/run_all.mjs
TZ=Asia/Shanghai OPENBLAS_NUM_THREADS=1 node /Users/duke/Documents/ChatGPT/noobclaw/scripts/run-with-system-proxy.cjs .venv/bin/python collectors/google_trends.py "embroidery digitizing" "embroidery app" "pes file"
```

`google_trends.py` 在直接使用系统 Python 启动时，也会自动使用已存在的项目 `.venv`。虚拟环境与原始采集数据不提交 Git；Node 依赖由已有 `package-lock.json` 恢复。依赖验证：

```sh
node --input-type=module -e 'await import("google-play-scraper"); console.log("Node dependencies ready")'
.venv/bin/python -c 'import pytrends, requests, pandas; print("Python dependencies ready")'
```
