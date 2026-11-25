#!/usr/bin/env python3
"""Paused close-ups of the wet-paint look (headless Chrome). usage: paintwet.py OUTDIR [query]
Strokes are sent as synchronous mouse events and the game is paused at once, so the picture shows the paint as it is
the moment it is laid down, then half settled (0.75 s), then settled (3 s); then a fill wipe caught half way."""
import sys, json, pathlib
from playwright.sync_api import sync_playwright
ARGS = ["--no-sandbox", "--disable-gpu-sandbox", "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist", "--allow-file-access-from-files"]
out = pathlib.Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True); extra = sys.argv[2] if len(sys.argv) > 2 else ""
root = pathlib.Path(__file__).resolve().parent.parent / "index.html"
JS = """(function(){var G=SG.game,c=G.me.c,cam=SG.camera,cv=document.getElementById('gl'),x0=1e9,y0=1e9,x1=-1e9,y1=-1e9;
 for(var y=80;y<700;y+=8)for(var x=150;x<1100;x+=8){var r=new THREE.Raycaster();r.setFromCamera(new THREE.Vector2(x/G.vw*2-1,-(y/G.vh)*2+1),cam);r.far=60;if(c.raycast(r)){if(x<x0)x0=x;if(x>x1)x1=x;if(y<y0)y0=y;if(y>y1)y1=y;}}
 function ev(t,x,y){var e=new MouseEvent(t,{clientX:x,clientY:y,button:0,buttons:t==='mouseup'?0:1,bubbles:true,detail:1});(t==='mousedown'?cv:window).dispatchEvent(e);}
 window.__stroke=function(pts,rgb,size){G.setColor(rgb);if(size)G.paint.size=size;ev('mousedown',pts[0][0],pts[0][1]);for(var i=1;i<pts.length;i++)ev('mousemove',pts[i][0],pts[i][1]);ev('mouseup',pts[pts.length-1][0],pts[pts.length-1][1]);};
 return {x0:x0,y0:y0,x1:x1,y1:y1};})()"""
with sync_playwright() as p:
    b = p.chromium.launch(executable_path="/usr/bin/google-chrome", headless=True, args=ARGS)
    pg = b.new_page(viewport={"width": 1280, "height": 720}); logs = []
    pg.on("pageerror", lambda e: logs.append("pageerror: " + str(e))); pg.on("console", lambda m: logs.append(m.text) if m.type == "error" else None)
    pg.goto(root.as_uri() + "?shot=paintblank&nolock=1&dist=1.6" + extra)
    pg.wait_for_function("window.__ready===true || window.__error", timeout=180000)
    box = pg.evaluate(JS); w = box["x1"] - box["x0"]; h = box["y1"] - box["y0"]; cx = (box["x0"] + box["x1"]) / 2; cy = (box["y0"] + box["y1"]) / 2
    clip = {"x": max(0, box["x0"] - 50), "y": max(0, box["y0"] - 50), "width": min(1280 - max(0, box["x0"] - 50), w + 100), "height": min(720 - max(0, box["y0"] - 50), h + 100)}
    def snap(name): pg.evaluate("new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)))"); pg.screenshot(path=str(out / name), clip=clip)
    import math
    wave = [[box["x0"] + 10 + (w - 20) * i / 24, cy - 10 + math.sin(i / 24 * math.pi * 2) * h * 0.22] for i in range(25)]
    pg.evaluate("SG.game.paused=true"); snap("w0_before.png")
    pg.evaluate("(function(p){__stroke(p,[47,75,124]); SG.game.paused=false; SG.game.step(0.03); SG.game.paused=true;})", wave); snap("w1_wet.png")
    pg.evaluate("SG.game.paused=false; SG.game.step(0.75); SG.game.paused=true"); snap("w2_half.png")
    pg.evaluate("SG.game.paused=false; SG.game.step(3); SG.game.paused=true"); snap("w3_settled.png")
    # second stroke over the first: fresh red next to dry blue
    line = [[box["x0"] + 20 + (w - 40) * i / 10, cy + h * 0.18 - (h * 0.36) * i / 10] for i in range(11)]
    pg.evaluate("(function(p){SG.game.paused=false; __stroke(p,[200,60,40]); SG.game.step(0.05); SG.game.paused=true;})", line); snap("w4_wet_over_dry.png")
    res = {"drops": pg.evaluate("SG.game.fx.drops.count"), "wetLive": pg.evaluate("SG.game.me.c._fx.live")}
    pg.evaluate("SG.game.paused=false; SG.game.step(3); SG.game.setColor([214,170,60]); SG.game.fillAll(); SG.game.step(0.22); SG.game.paused=true"); snap("w5_fill_wipe_mid.png")
    res["fillMid"] = pg.evaluate("SG.game.me.c._fx.fillJob ? +SG.game.me.c._fx.fillJob.p.toFixed(2) : null")
    pg.evaluate("SG.game.paused=false; SG.game.step(0.5); SG.game.paused=true"); snap("w6_fill_done.png")
    res["errors"] = logs[:6]; print(json.dumps(res)); b.close()
