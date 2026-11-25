#!/usr/bin/env python3
"""Targeted checks of the brush (headless Chrome, software GL). usage: paintcheck.py OUTDIR [breed]
Draws a fast diagonal stroke in a few big mouse jumps and measures: continuity of the band (gaps along the path),
dab cost, event cost, event->frame latency, sub-uploads; then takes close-ups (wet, settled), the fill wipe, the part fill,
the unpainted highlight and the white-left number."""
import sys, time, json, pathlib
from playwright.sync_api import sync_playwright
from PIL import Image
ARGS = ["--no-sandbox", "--disable-gpu-sandbox", "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist", "--allow-file-access-from-files"]
out = pathlib.Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)
breed = sys.argv[2] if len(sys.argv) > 2 else "mochi"
extra = sys.argv[3] if len(sys.argv) > 3 else ""
root = pathlib.Path(__file__).resolve().parent.parent / "index.html"
W, H = 1280, 720
res = {}
def raf(pg, n=2): pg.evaluate("new Promise(r=>{var n=%d;(function f(){if(n--<=0)r();else requestAnimationFrame(f)})()})" % n)
with sync_playwright() as p:
    b = p.chromium.launch(executable_path="/usr/bin/google-chrome", headless=True, args=ARGS)
    pg = b.new_page(viewport={"width": W, "height": H}); logs = []
    pg.on("console", lambda m: logs.append(m.type + ": " + m.text) if m.type == "error" else None); pg.on("pageerror", lambda e: logs.append("pageerror: " + str(e)))
    pg.goto(root.as_uri() + "?shot=paintblank&nolock=1&breed=" + breed + extra)
    pg.wait_for_function("window.__ready===true || window.__error", timeout=180000)
    raf(pg, 3)
    # where the body is on screen
    box = pg.evaluate("""(function(){var G=SG.game,c=G.me.c,cam=SG.camera,x0=1e9,y0=1e9,x1=-1e9,y1=-1e9,n=0;
      for(var y=100;y<700;y+=8)for(var x=200;x<1000;x+=8){var r=new THREE.Raycaster();r.setFromCamera(new THREE.Vector2(x/G.vw*2-1,-(y/G.vh)*2+1),cam);r.far=60;if(c.raycast(r)){n++;if(x<x0)x0=x;if(x>x1)x1=x;if(y<y0)y0=y;if(y>y1)y1=y;}}
      return {x0:x0,y0:y0,x1:x1,y1:y1,n:n,size:G.paint.size,painted:G.me.c.paintedRatio()};})()""")
    res["box"] = box
    pg.screenshot(path=str(out / "p1_before.png"))
    pg.evaluate("SG.game.setColor([47,75,124]); SG.game.fx.stats.dabs=0; SG.game.fx.stats.dabMs=0; SG.game.fx.stats.dabMax=0; SG.game.fx.stats.sub=0; SG.game.fx.stats.full=0; SG.game.strokeStats.evMax=0; SG.game.strokeStats.latMax=0; SG.game.strokeStats.dabsMaxEv=0;")
    ax, ay, bx, by = box["x0"] - 30, box["y0"] - 20, box["x1"] + 30, box["y1"] + 20
    # fast diagonal: 5 jumps, one per frame, starting beside the body
    pg.mouse.move(ax, ay); pg.mouse.down()
    N = 5
    for i in range(1, N + 1):
        pg.mouse.move(ax + (bx - ax) * i / N, ay + (by - ay) * i / N, steps=1); raf(pg, 1)
        if i == 3: pg.screenshot(path=str(out / "p2_stroke_mid.png"))
    raf(pg, 1)
    pg.screenshot(path=str(out / "p3_stroke_wet.png"))
    st = pg.evaluate("JSON.stringify({fx:SG.game.fx.stats, st:SG.game.strokeStats, ft:SG.game.ft})"); res["diag"] = json.loads(st)
    pg.mouse.up()
    # continuity: along the mouse path, every pixel that is on the body must be painted (blue), not white
    img = Image.open(out / "p3_stroke_wet.png").convert("RGB"); on = pg.evaluate("""(function(a){var G=SG.game,c=G.me.c,cam=SG.camera,o=[];for(var i=0;i<=200;i++){var x=a[0]+(a[2]-a[0])*i/200,y=a[1]+(a[3]-a[1])*i/200,r=new THREE.Raycaster();r.setFromCamera(new THREE.Vector2(x/G.vw*2-1,-(y/G.vh)*2+1),cam);r.far=60;o.push(c.raycast(r)?1:0);}return o;})""", [ax, ay, bx, by])
    gaps = 0; body = 0; run = 0; worst = 0
    for i, o in enumerate(on):
        if not o: continue
        x = ax + (bx - ax) * i / 200; y = ay + (by - ay) * i / 200; r, g, bl = img.getpixel((int(x), int(y))); body += 1
        white = r > 170 and g > 170 and bl > 150 and abs(r - bl) < 60
        if white: gaps += 1; run += 1; worst = max(worst, run)
        else: run = 0
    res["continuity"] = {"samplesOnBody": body, "unpainted": gaps, "longestGapSamples": worst}
    # wet close-up now, settled close-up after 2.5 s of game time
    cx, cy = (box["x0"] + box["x1"]) // 2, (box["y0"] + box["y1"]) // 2
    clip = {"x": max(0, box["x0"] - 60), "y": max(0, box["y0"] - 60), "width": box["x1"] - box["x0"] + 120, "height": box["y1"] - box["y0"] + 120}
    # a second, slower curved stroke in another colour so wet and dry can be compared in one picture
    pg.evaluate("SG.game.setColor([200,60,40])")
    pg.mouse.move(box["x0"] + 20, cy + 30); pg.mouse.down()
    import math
    for i in range(1, 13):
        t = i / 12; pg.mouse.move(box["x0"] + 20 + (box["x1"] - box["x0"] - 40) * t, cy + 30 - math.sin(t * math.pi) * (box["y1"] - box["y0"]) * 0.3, steps=1); raf(pg, 1)
    pg.screenshot(path=str(out / "p4_closeup_wet.png"), clip=clip)
    pg.mouse.up(); pg.mouse.move(cx, cy - 10); raf(pg, 2)
    pg.screenshot(path=str(out / "p4b_cursor_ring.png"), clip=clip)
    pg.mouse.move(30, 700); pg.evaluate("SG.game.step(3)"); raf(pg, 2)
    pg.screenshot(path=str(out / "p5_closeup_settled.png"), clip=clip)
    res["whiteAfterStrokes"] = pg.evaluate("(function(){var G=SG.game;return G.fx.whiteLeft(G.me.c,null,true)})()")
    # highlight of unpainted areas (hold H)
    pg.keyboard.down("h"); pg.evaluate("SG.game.step(0.4)"); raf(pg, 2); pg.screenshot(path=str(out / "p6_highlight.png"), clip=clip); pg.keyboard.up("h"); pg.evaluate("SG.game.step(0.4)")
    # double-click fills one part
    pg.evaluate("SG.game.setColor([70,150,90])"); u0 = pg.evaluate("SG.game.paint.undo.length")
    pg.mouse.dblclick(cx, cy); pg.evaluate("SG.game.step(0.12)"); raf(pg, 2); pg.screenshot(path=str(out / "p7_partfill_mid.png"), clip=clip)
    pg.evaluate("SG.game.step(0.6)"); raf(pg, 2); pg.screenshot(path=str(out / "p7b_partfill_done.png"), clip=clip)
    res["partFill"] = {"undoBefore": u0, "undoAfter": pg.evaluate("SG.game.paint.undo.length")}
    # whole-body fill wipe
    pg.evaluate("SG.game.setColor([214,170,60]); SG.game.fillAll(); SG.game.step(0.2)"); raf(pg, 2); pg.screenshot(path=str(out / "p8_fill_mid.png"), clip=clip)
    pg.evaluate("SG.game.step(0.5)"); raf(pg, 2); pg.screenshot(path=str(out / "p8b_fill_done.png"), clip=clip)
    res["whiteAfterFill"] = pg.evaluate("(function(){var G=SG.game;return G.fx.whiteLeft(G.me.c,null,true)})()")
    res["undo"] = pg.evaluate("(function(){var G=SG.game,n=0;while(G.undo())n++;return {undone:n,painted:G.me.c.paintedRatio(),white:G.fx.whiteLeft(G.me.c,null,true)}})()")
    # dab cost at three sizes, 200 dabs each over the body
    res["dabCost"] = pg.evaluate("""(function(){var G=SG.game,c=G.me.c,ctr=c.center(new THREE.Vector3()),o={};[0.03,0.07,0.2].forEach(function(R){var S=G.fx.stats;S.dabs=0;S.dabMs=0;S.dabMax=0;S.texels=0;for(var i=0;i<200;i++){var a=i*0.7;G.fx.dab(c,new THREE.Vector3(ctr.x+Math.cos(a)*0.12,ctr.y+Math.sin(a*1.3)*0.1,ctr.z+Math.sin(a)*0.12),R,[9,9,9],0.5,0,0.85,1);}o['r'+R]={avgMs:+(S.dabMs/S.dabs).toFixed(4),maxMs:+S.dabMax.toFixed(3),texelsPerDab:Math.round(S.texels/S.dabs)};});var t=performance.now();G.fx.flush(c);o.flushMs=+(performance.now()-t).toFixed(2);return o;})()""")
    # eyedropper magnifier: hold Space beside the body
    pg.mouse.move(box["x0"] - 80, box["y1"] - 10); pg.keyboard.down(" "); pg.evaluate("SG.game.step(0.1)"); raf(pg, 3); pg.screenshot(path=str(out / "p9_loupe.png")); res["loupe"] = pg.evaluate("(function(){var l=document.querySelector('.loupe');return {shown:!l.classList.contains('hide'),hex:l.lastChild.textContent}})()"); pg.keyboard.up(" ")
    res["sounds"] = [x for x in pg.evaluate("SG.audio.selfTest()") if x["name"] in ("squelch", "pick", "fill", "brushMove", "brush")]
    res["errors"] = logs[:8]
    b.close()
print(json.dumps(res, indent=1))
