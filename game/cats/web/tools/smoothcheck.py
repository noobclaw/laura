#!/usr/bin/env python3
"""Smoothness measurement (headless Chrome, simulated frames): the cat is walked with the keyboard only (no mouse) along the
patrol tour - through rooms, doorways, past walls and round furniture - while the camera position is recorded every frame.
Reported per run: the largest camera movement in one frame that the body's own movement does not explain (limit 5 cm per 1/60 s;
longer frames are scaled to that length), the
largest change of camera velocity between two frames (limit 3 m/s per frame = a jolt you would see), and the same for an uneven
frame rhythm (16.7 / 22 / 8 / 33 ms mixed). Also: in paint mode with no input the camera must not move at all, and the dog's
first-person camera must follow the body without jolts. usage: smoothcheck.py [OUT.json]"""
import sys, json, pathlib
from playwright.sync_api import sync_playwright
ARGS = ["--no-sandbox", "--disable-gpu-sandbox", "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist", "--allow-file-access-from-files"]
root = pathlib.Path(__file__).resolve().parent.parent / "index.html"
JS = r"""(opt) => { const G=SG.game, cam=SG.camera, W=SG.WS; G.settings.mode='basic'; G.settings.prep=99999; G.settings.seek=99999; G.start(opt.side, opt.side==='cat'?'mochi':'shiba'); if (opt.side==='dog') G.skip(); if (opt.third) G.third=true; const m=G.me; G.step(0.3); G.noRender=true;
  const dts = opt.uneven ? [1/60, 0.022, 0.008, 0.033, 1/60, 1/60, 0.012] : [1/60]; let fi=0;
  const route=SG.room.route, tr=[]; let worstExcess=0, worstJolt=0, wE=null, wJ=null, dist=0, pc=cam.position.clone(), pb=m.c.root.position.clone(), pv=null, t=0, frames=0, run=!!opt.run;
  const one=(dt)=>{ G.step(dt, 1/dt); const c=cam.position.clone(), b=m.c.root.position.clone(); const dc=c.clone().sub(pc), db=b.clone().sub(pb), ex=dc.clone().sub(db).length()/(dt*60), v=dc.clone().multiplyScalar(1/dt);
    if (frames>20) { if (ex>worstExcess) { worstExcess=ex; wE={t:+t.toFixed(2), at:[+(m.x/W).toFixed(2), +(m.z/W).toFixed(2)], dt:+dt.toFixed(4)}; } if (pv) { const j=v.clone().sub(pv).length(); if (j>worstJolt) { worstJolt=j; wJ={t:+t.toFixed(2), at:[+(m.x/W).toFixed(2), +(m.z/W).toFixed(2)], dt:+dt.toFixed(4)}; } } }
    dist+=db.length(); pc=c; pb=b; pv=v; t+=dt; frames++; };
  try {
  if (opt.mode==='paint') { G.setPaintMode(true); for (let i=0;i<60;i++) G.step(1/60); const c0=cam.position.clone(); let mx=0; for (let i=0;i<240;i++){ G.step(1/60); mx=Math.max(mx, cam.position.distanceTo(c0)); } G.noRender=false; return {mode:'paint idle 4 s', maxCameraDriftM:+mx.toFixed(5)}; }
  for (let g=0; g<route.length && t<opt.seconds; g++) { const path=G.navPath(m.x, m.z, route[g][0], route[g][1], m.y); if (!path) continue; let pi=0, guard=0;
    while (pi<path.length && guard++<1500 && t<opt.seconds) { const tx=path[pi][0], tz=path[pi][1], d=Math.hypot(tx-m.x, tz-m.z); if (d<0.3) { pi++; continue; }
      // keyboard only: the key combination whose direction is closest to where the path goes
      const want=Math.atan2(tx-m.x, tz-m.z), yaw=opt.side==='cat'?G.cam.yaw:m.yaw; let best=null, bd=9;
      for (const [f,s] of [[1,0],[1,1],[0,1],[-1,1],[-1,0],[-1,-1],[0,-1],[1,-1]]) { const mx2 = opt.side==='cat' ? -Math.sin(yaw)*f+Math.cos(yaw)*s : Math.sin(yaw)*f-Math.cos(yaw)*s, mz2 = opt.side==='cat' ? -Math.cos(yaw)*f-Math.sin(yaw)*s : Math.cos(yaw)*f+Math.sin(yaw)*s; let da=Math.abs(Math.atan2(Math.sin(Math.atan2(mx2,mz2)-want), Math.cos(Math.atan2(mx2,mz2)-want))); if (da<bd) { bd=da; best=[f,s]; } }
      G.keys.w=best[0]>0; G.keys.s=best[0]<0; G.keys.d=best[1]>0; G.keys.a=best[1]<0; G.keys.Shift=run; one(dts[fi++%dts.length]); } }
  G.keys.w=G.keys.s=G.keys.a=G.keys.d=G.keys.Shift=false; for (let i=0;i<40;i++) one(1/60);
  } finally { G.noRender=false; }
  return {mode:opt.side+(opt.third?' third person':'')+(run?' run':' walk')+(opt.uneven?' uneven frames':' 60 fps'), seconds:+t.toFixed(1), frames, distM:+dist.toFixed(1), worstUnexplainedCamMoveCm:+(worstExcess*100).toFixed(2), whereExcess:wE, worstVelocityChangeMps:+worstJolt.toFixed(2), whereJolt:wJ}; }"""
out = []
with sync_playwright() as p:
    b = p.chromium.launch(executable_path="/usr/bin/google-chrome", headless=True, args=ARGS)
    pg = b.new_page(viewport={"width": 480, "height": 270}); logs = []
    pg.on("pageerror", lambda e: logs.append("pageerror: " + str(e)))
    pg.goto(root.as_uri() + "?shot=room&nolock=1&q=low"); pg.wait_for_function("window.__ready===true || window.__error", timeout=180000)
    for opt in [{"side": "cat", "seconds": 120}, {"side": "cat", "seconds": 90, "uneven": True}, {"side": "cat", "seconds": 60, "run": True}, {"side": "dog", "seconds": 90}, {"side": "dog", "seconds": 60, "uneven": True}, {"side": "dog", "seconds": 60, "third": True}, {"side": "cat", "mode": "paint"}]:
        r = pg.evaluate(JS, opt); out.append(r); print(json.dumps(r), flush=True)
    b.close()
ok = all(r.get("worstUnexplainedCamMoveCm", 0) <= 5 and r.get("worstVelocityChangeMps", 0) <= 3 and r.get("maxCameraDriftM", 0) <= 0.0005 for r in out)
print("PASS" if ok else "FAIL", logs[:3])
if len(sys.argv) > 1: json.dump(out, open(sys.argv[1], "w"), indent=1)
