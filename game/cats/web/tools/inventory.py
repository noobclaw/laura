#!/usr/bin/env python3
"""Dump the object inventory of the room (counted by the builder code, not by eye) as a Markdown table."""
import pathlib, sys
from playwright.sync_api import sync_playwright
ARGS = ["--no-sandbox", "--disable-gpu-sandbox", "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"]
root = pathlib.Path(__file__).resolve().parent.parent / "index.html"
with sync_playwright() as p:
    b = p.chromium.launch(executable_path="/usr/bin/google-chrome", headless=True, args=ARGS)
    pg = b.new_page(viewport={"width": 640, "height": 360}); pg.goto(root.as_uri() + "?q=low&shot=room"); pg.wait_for_function("window.__ready===true", timeout=180000)
    inv = pg.evaluate("SG.room.inventory"); st = pg.evaluate("SG.room.stats"); b.close()
rows = sorted(inv.items(), key=lambda kv: (-kv[1], kv[0]))
out = ["## 客廳物件清單（由 web/tools/inventory.py 從建造程式輸出）", "", "種類 %d、總數 %d、其中可撞倒的小物 %d 件、會動的系統 %d 組。" % (st["types"], st["items"], st["knockables"], st["moving"]), "", "| 物件 | 數量 | 物件 | 數量 | 物件 | 數量 |", "|---|---|---|---|---|---|"]
for i in range(0, len(rows), 3):
    r = rows[i:i + 3] + [("", "")] * (3 - len(rows[i:i + 3])); out.append("| " + " | ".join("%s | %s" % (k, v) for k, v in r) + " |")
print("\n".join(out))
