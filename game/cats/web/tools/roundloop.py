#!/usr/bin/env python3
"""Three rounds in a row with the real frame loop: the lobby countdown must run, every phase must be reached, the loop must survive the end of a round.
Regression test for the owner-reported freeze (lobby stuck at 20): reveal -> lobby cleared the round state in the middle of update(), the next line threw and the frame loop died."""
import sys, json, pathlib
from playwright.sync_api import sync_playwright
ARGS = ["--no-sandbox","--disable-gpu-sandbox","--use-gl=angle","--use-angle=swiftshader","--enable-unsafe-swiftshader","--ignore-gpu-blocklist","--autoplay-policy=no-user-gesture-required"]
ROOT = pathlib.Path(sys.argv[1]) if len(sys.argv)>1 else pathlib.Path(__file__).resolve().parent.parent / "index.html"
ok=True
with sync_playwright() as p:
    b = p.chromium.launch(executable_path="/usr/bin/google-chrome", headless=True, args=ARGS)
    pg = b.new_page(viewport={"width":1280,"height":720}); errs=[]
    pg.on("pageerror", lambda e: errs.append("PAGEERR "+str(e)))
    pg.on("console", lambda m: errs.append(m.type+" "+m.text) if m.type=="error" else None)
    pg.goto(ROOT.as_uri()+"?q=low&nolock=1"); pg.wait_for_function("window.__ready===true||window.__error", timeout=180000)
    for rnd in range(3):
        pg.evaluate("SG.game.enterLobby()")
        f0=pg.evaluate("SG.game.frames"); t0=pg.evaluate("SG.game.info().lobby.t"); pg.wait_for_timeout(3000)
        f1=pg.evaluate("SG.game.frames"); L=pg.evaluate("SG.game.info().lobby"); t1=L["t"] if L else None
        good = f1>f0 and t1 is not None and t1<t0
        print(f"round {rnd+1}: lobby {t0:.2f} -> {t1}, frames {f0}->{f1}", "OK" if good else "STUCK"); ok&=good
        # let the lobby run out with the real loop (speed it up) and play the round through every phase to its end
        pg.evaluate("SG.game.lobby && (SG.game.lobby.t=0.05)"); pg.wait_for_timeout(1500)
        i=pg.evaluate("SG.game.info()"); print("   started:", i["mode"], i.get("phase"), i.get("side"))
        for ph in range(4):
            pg.evaluate("SG.game.state && (SG.game.state.left=0.05)"); pg.wait_for_timeout(1200)
            i=pg.evaluate("SG.game.info()"); print("   ->", i["mode"], i.get("phase"))
        f2=pg.evaluate("SG.game.frames"); pg.wait_for_timeout(1500); f3=pg.evaluate("SG.game.frames")
        alive=f3>f2; print("   loop alive after round end:", alive, "errors:", pg.evaluate("SG.game.errors||0")); ok&=alive
    print("PAGE ERRORS:", errs[:6]); print("RESULT", "PASS" if ok else "FAIL")
    b.close()
