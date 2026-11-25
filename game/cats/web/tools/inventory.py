#!/usr/bin/env python3
"""Dump the object inventory of the property, by kind and by area (counted by the builder code, not by eye), as Markdown."""
import pathlib
from playwright.sync_api import sync_playwright
ARGS = ["--no-sandbox", "--disable-gpu-sandbox", "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"]
root = pathlib.Path(__file__).resolve().parent.parent / "index.html"
with sync_playwright() as p:
    b = p.chromium.launch(executable_path="/usr/bin/google-chrome", headless=True, args=ARGS)
    pg = b.new_page(viewport={"width": 640, "height": 360}); pg.goto(root.as_uri() + "?q=low&shot=room"); pg.wait_for_function("window.__ready===true", timeout=180000)
    by = pg.evaluate("SG.room.inventoryByRoom"); st = pg.evaluate("SG.room.stats"); inv = pg.evaluate("SG.room.inventory"); b.close()
out = ["## 物件清單：依區域、依種類（由 web/tools/inventory.py 從建造程式輸出）", "", "全場地：種類 %d、總數 %d、可撞倒的小物 %d 件、會動的系統 %d 組。書 %d 本，佔 %.1f%%。" % (st["types"], st["items"], st["knockables"], st["moving"], inv.get("書", 0), 100.0 * inv.get("書", 0) / st["items"]), ""]
for room, items in by.items():
    rows = sorted(items.items(), key=lambda kv: (-kv[1], kv[0]))
    out += ["### %s（%d 種、%d 件）" % (room, len(rows), sum(items.values())), "", "、".join("%s×%d" % (k, v) if v > 1 else k for k, v in rows), ""]
print("\n".join(out))
