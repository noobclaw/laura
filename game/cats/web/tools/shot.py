#!/usr/bin/env python3
"""Capture a state of the game with headless Chrome (software WebGL).
usage: shot.py OUT.png "shot=room&cam=..." [W H] [--eval "js"] [--wait SEC]"""
import sys, time, pathlib
from playwright.sync_api import sync_playwright
ARGS = ["--no-sandbox", "--disable-gpu-sandbox", "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist", "--allow-file-access-from-files"]
def main():
    a = sys.argv[1:]; ev = None; wait = 0.0
    if "--eval" in a: i = a.index("--eval"); ev = a[i + 1]; del a[i:i + 2]
    if "--wait" in a: i = a.index("--wait"); wait = float(a[i + 1]); del a[i:i + 2]
    out, query = a[0], a[1] if len(a) > 1 else ""
    w, h = (int(a[2]), int(a[3])) if len(a) > 3 else (1600, 900)
    root = pathlib.Path(__file__).resolve().parent.parent / "index.html"
    with sync_playwright() as p:
        b = p.chromium.launch(executable_path="/usr/bin/google-chrome", headless=True, args=ARGS)
        pg = b.new_page(viewport={"width": w, "height": h})
        logs = []
        pg.on("console", lambda m: logs.append(m.type + ": " + m.text) if m.type in ("error", "warning") else None)
        pg.on("pageerror", lambda e: logs.append("pageerror: " + str(e)))
        pg.goto(root.as_uri() + ("?" + query if query else ""))
        try: pg.wait_for_function("window.__ready===true || window.__error", timeout=120000)
        except Exception as e: logs.append("timeout waiting for ready")
        err = pg.evaluate("window.__error||null")
        if err: logs.append("BOOT ERROR: " + err)
        if ev: print("eval:", pg.evaluate(ev))
        pg.evaluate("new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(()=>requestAnimationFrame(r))))")
        if wait: time.sleep(wait)
        pg.screenshot(path=out)
        for l in logs[:12]: print(l[:400])
        b.close()
main()
