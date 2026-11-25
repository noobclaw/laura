#!/usr/bin/env python3
"""Look at the animals in the small studio page (tools/critter_preview.html), without booting the game.

  critter_shots.py js OUT.png "PV.spawn('mochi'); PV.look([1.6,0.6,1.8],[0,0.25,0],30); PV.full();" [W H] [--old]
  critter_shots.py all [OUTDIR]        every evidence sheet (default /tmp/webshots/body)
  critter_shots.py NAME [OUTDIR]       one sheet: lineup poses1 poses2 pancake stripes density frozen gait oldnew compare icons sizes

Headless Chrome with software WebGL; one screenshot takes 2-3 s."""
import sys, json, pathlib, time
from playwright.sync_api import sync_playwright

ARGS = ["--no-sandbox", "--disable-gpu-sandbox", "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist", "--allow-file-access-from-files"]
HERE = pathlib.Path(__file__).resolve().parent
PAGE = HERE / "critter_preview.html"


class Studio:
    def __init__(self, p, w=1600, h=900, old=False):
        self.b = p.chromium.launch(executable_path="/usr/bin/google-chrome", headless=True, args=ARGS)
        self.pg = self.b.new_page(viewport={"width": w, "height": h})
        self.logs = []
        self.pg.on("console", lambda m: self.logs.append(m.type + ": " + m.text) if m.type in ("error", "warning") else None)
        self.pg.on("pageerror", lambda e: self.logs.append("pageerror: " + str(e)))
        self.pg.goto(PAGE.as_uri() + ("?old=1" if old else ""))
        self.pg.wait_for_function("window.__ready===true || window.__error", timeout=60000)
        err = self.pg.evaluate("window.__error||null")
        if err:
            raise SystemExit("preview failed: " + err + "\n" + "\n".join(self.logs))

    def js(self, code):
        r = self.pg.evaluate("(()=>{" + code + "})()")
        for l in self.logs[:8]:
            print("  [page]", l[:300])
        self.logs.clear()
        return r

    def shot(self, out, clip=None):
        self.pg.evaluate("new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)))")
        self.pg.screenshot(path=str(out), clip=clip)

    def close(self):
        self.b.close()


def main():
    a = sys.argv[1:]
    if not a:
        print(__doc__); return
    old = "--old" in a
    if old: a.remove("--old")
    with sync_playwright() as p:
        if a[0] == "js":
            w, h = (int(a[3]), int(a[4])) if len(a) > 4 else (1600, 900)
            st = Studio(p, w, h, old)
            t = time.time(); r = st.js(a[2]); st.shot(a[1])
            if r is not None: print(json.dumps(r, ensure_ascii=False))
            print("ok %.1fs" % (time.time() - t)); st.close(); return
        import critter_sheets
        out = pathlib.Path(a[1] if len(a) > 1 else "/tmp/webshots/body"); out.mkdir(parents=True, exist_ok=True)
        critter_sheets.run(p, Studio, a[0], out)


if __name__ == "__main__":
    main()
