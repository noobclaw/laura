#!/usr/bin/env python3
"""Stuck check (headless Chrome): a player-sized dog is driven through the whole patrol tour (every room and doorway) and
along every wall / furniture edge of the walking grid; reports every stall longer than a second (no un-stick help), then
the same with the bot dog's own AI for a while. Also: what the walking grid loses with a lower step-up height.
usage: walkcheck.py [OUT.json] [maxEdgeGoals]"""
import sys, json, pathlib
from playwright.sync_api import sync_playwright
ARGS = ["--no-sandbox", "--disable-gpu-sandbox", "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist", "--allow-file-access-from-files"]
root = pathlib.Path(__file__).resolve().parent.parent / "index.html"; mx = int(sys.argv[2]) if len(sys.argv) > 2 else 0
with sync_playwright() as p:
    b = p.chromium.launch(executable_path="/usr/bin/google-chrome", headless=True, args=ARGS)
    pg = b.new_page(viewport={"width": 640, "height": 360}); logs = []
    pg.on("pageerror", lambda e: logs.append("pageerror: " + str(e)))
    pg.goto(root.as_uri() + "?shot=room&nolock=1&q=low"); pg.wait_for_function("window.__ready===true || window.__error", timeout=180000)
    r = {}
    r["nav"] = pg.evaluate("(function(){var G=SG.game;G.settings.mode='basic';G.start('dog','shiba');G.skip();G.step(0.1);return [0.12,0.24].map(function(s){return G.navStats(s)});})()")
    print("nav", json.dumps(r["nav"]), flush=True)
    r["me"] = pg.evaluate("(function(){var m=SG.game.me;return {rad:+m.rad.toFixed(3),halfLen:+m.halfLen.toFixed(3),h:+m.h.toFixed(3),step:m.step}})()")
    r["route"] = pg.evaluate("SG.game.walkTest('route',{noNudge:true})"); print("route", json.dumps(r["route"]), flush=True)
    r["edges"] = pg.evaluate("SG.game.walkTest('edges',{noNudge:true,max:%d})" % mx); print("edges", json.dumps(r["edges"])[:3000], flush=True)
    # the bot dog on its own AI: 4 minutes of patrol, count how long it stands still while it wants to move
    r["bot"] = pg.evaluate("""(function(){var G=SG.game;G.settings.mode='basic';G.settings.seek=99999;G.start('cat','mochi');G.skip();G.step(0.1);var d=G.ents.filter(function(e){return e.team==='dog'&&e.bot})[0],still=0,worst=0,where=null,dist=0,wps={},px=d.x,pz=d.z;
      for(var i=0;i<10*240;i++){G.step(0.1);var mv=Math.hypot(d.x-px,d.z-pz);dist+=mv;px=d.x;pz=d.z;wps[d.ai.wp%G.botRoute.length]=1;if(d.ai.mode==='patrol'&&!(d.ai.wait>0)&&mv<0.012){still+=0.1;if(still>worst){worst=still;where=[+(d.x/SG.WS).toFixed(2),+(d.z/SG.WS).toFixed(2)];}}else still=0;if(G.state.phase!=='seek')break;}
      return {dist:+dist.toFixed(0),worstStandstillSec:+worst.toFixed(2),where:where,goalsVisited:Object.keys(wps).length,of:G.botRoute.length,tourGoals:SG.room.route.length,phase:G.state.phase};})()""")
    print("bot", json.dumps(r["bot"]), flush=True); r["errors"] = logs[:5]
    ok = not r["route"]["stalls"] and not r["edges"]["stalls"] and r["bot"]["worstStandstillSec"] <= 1.0
    print("PASS" if ok else "FAIL", logs[:3])
    if len(sys.argv) > 1: json.dump(r, open(sys.argv[1], "w"), indent=1)
    b.close()
