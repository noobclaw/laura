#!/usr/bin/env python3
"""One picture per area from a fixed corner camera (for before/after comparisons), plus draw calls there.
usage: areashots.py OUTDIR TAG [path/to/index.html]"""
import sys, json, pathlib
from playwright.sync_api import sync_playwright
ARGS = ["--no-sandbox", "--disable-gpu-sandbox", "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist", "--allow-file-access-from-files"]
out = pathlib.Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True); tag = sys.argv[2]
root = pathlib.Path(sys.argv[3]) if len(sys.argv) > 3 else pathlib.Path(__file__).resolve().parent.parent / "index.html"
AREAS = {"living": [-4.5, 4.5, -3.5, 2.55], "kitchen": [-2.5, 2.5, -6.1, -3.5], "genkan": [-6.7, -4.5, -3.5, 2.9], "washitsu": [2.6, 7.0, -7.5, -3.5], "study": [4.62, 8, -3.5, -0.55], "bath": [4.62, 8, -0.55, 2.3], "store": [-6.7, -2.56, -6.5, -3.62], "westalley": [-8.6, -6.82, -3.5, 2.3], "northalley": [-2.5, 8.6, -8.6, -6.3], "eastalley": [8.0, 8.6, -8.6, 2.3], "garden": [-8, 8, 4.0, 8.7]}
with sync_playwright() as p:
    b = p.chromium.launch(executable_path="/usr/bin/google-chrome", headless=True, args=ARGS)
    pg = b.new_page(viewport={"width": 960, "height": 540}); logs = []
    pg.on("pageerror", lambda e: logs.append("pageerror: " + str(e)))
    pg.goto(root.as_uri() + "?shot=room&nolock=1"); pg.wait_for_function("window.__ready===true || window.__error", timeout=240000)
    res = {"err": pg.evaluate("window.__error||null")}
    for n, a in AREAS.items():
        x0, x1, z0, z1 = a; ix = min(0.5, (x1 - x0) * 0.2); iz = min(0.5, (z1 - z0) * 0.2)
        pg.evaluate("(function(v){var w=SG.WS,G=SG.game;G.cam.free={p:new THREE.Vector3(v[0]*w,v[1]*w,v[2]*w),t:new THREE.Vector3(v[3]*w,v[4]*w,v[5]*w),fov:72};})", [x0 + ix, 0.95, z1 - iz, x1 - ix, 0.15, z0 + iz])
        pg.evaluate("new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(()=>requestAnimationFrame(r))))")
        pg.screenshot(path=str(out / ("%s_%s.png" % (n, tag)))); res[n] = pg.evaluate("SG.post.sceneCalls")
    res["errors"] = logs[:5]; print(json.dumps(res)); b.close()
