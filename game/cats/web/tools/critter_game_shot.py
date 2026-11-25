#!/usr/bin/env python3
"""Like shot.py, for scenes that keep animating (title): waits for ready, then screenshots with a long timeout.
usage: critter_game_shot.py OUT.png "query" [W H]"""
import sys, pathlib
from playwright.sync_api import sync_playwright
ARGS = ["--no-sandbox", "--disable-gpu-sandbox", "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist", "--allow-file-access-from-files"]
a = sys.argv[1:]; out, query = a[0], a[1] if len(a) > 1 else ""; w, h = (int(a[2]), int(a[3])) if len(a) > 3 else (1280, 720)
root = pathlib.Path(__file__).resolve().parent.parent / "index.html"
with sync_playwright() as p:
    b = p.chromium.launch(executable_path="/usr/bin/google-chrome", headless=True, args=ARGS)
    pg = b.new_page(viewport={"width": w, "height": h}); logs = []
    pg.on("console", lambda m: logs.append(m.type + ": " + m.text) if m.type == "error" else None)
    pg.on("pageerror", lambda e: logs.append("pageerror: " + str(e)))
    pg.goto(root.as_uri() + ("?" + query if query else ""))
    pg.wait_for_function("window.__ready===true || window.__error", timeout=180000)
    print("boot error:", pg.evaluate("window.__error||null"))
    pg.screenshot(path=out, timeout=240000, animations="disabled")
    for l in logs[:10]: print(l[:300])
    b.close()
