#!/usr/bin/env python3
"""Scripted playthrough with real mouse / keyboard events in headless Chrome (software WebGL).
The simulation is advanced with SG.game.step() so results do not depend on how slowly SwiftShader renders.
Sections: world cat dog modes. Screenshots go to /tmp/webshots/r2/test. Exit code 1 if any check fails."""
import sys, json, time, pathlib, math
from playwright.sync_api import sync_playwright
ARGS = ["--no-sandbox", "--disable-gpu-sandbox", "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist", "--autoplay-policy=no-user-gesture-required"]
ROOT = pathlib.Path(__file__).resolve().parent.parent / "index.html"
OUT = pathlib.Path("/tmp/webshots/r2/test"); OUT.mkdir(parents=True, exist_ok=True)
W, H = 1280, 720
results = []
def check(name, ok, detail=""):
    results.append((name, bool(ok), detail)); print(("PASS " if ok else "FAIL ") + name + ((" — " + str(detail)[:300]) if detail != "" else "")); sys.stdout.flush()
def boot(pg, query="q=low&nolock=1", setup=None):
    pg.goto(ROOT.as_uri() + "?" + query); pg.wait_for_function("window.__ready===true||window.__error", timeout=180000)
    err = pg.evaluate("window.__error||null"); assert not err, err
    pg.evaluate("""() => { const G=SG.game; G.paused=true; window.__ev=[]; SG.bus.on('*',(t,d)=>{ if(t!=='frame') __ev.push(Object.assign({t:t},d||{})); }); }""")
    # classic small round for the rule checks; numbers are data
    pg.evaluate(setup or "() => { const G=SG.game; G.settings.mode='basic'; G.settings.dogs=1; G.settings.seek=90; SG.RULES.solo.botCatsWhenCat=3; SG.RULES.solo.botCatsWhenDog=4; SG.RULES.solo.botDogsWhenDog=0; }")
def info(pg): return pg.evaluate("SG.game.info()")
def step(pg, s): pg.evaluate("s=>SG.game.step(s)", s)
def events(pg, t=None): ev = pg.evaluate("__ev"); return [e for e in ev if t is None or e["t"] == t]
def catxy(pg): return pg.evaluate("""() => { const G=SG.game; SG.camera.updateMatrixWorld(true); const p=G.me.c.center().project(SG.camera); return [(p.x*.5+.5)*G.vw, (-p.y*.5+.5)*G.vh]; }""")
def proj(pg, x, y, z): return pg.evaluate("""(a) => { const G=SG.game; const p=new THREE.Vector3(a[0],a[1],a[2]).project(SG.camera); return [(p.x*.5+.5)*G.vw, (-p.y*.5+.5)*G.vh]; }""", [x, y, z])
def shot(pg, name): step(pg, 0.02); pg.screenshot(path=str(OUT / (name + ".png")))
def texhash(pg, eid="you"): return pg.evaluate("""id => { const e=SG.game.ent(id), a=e.c.alb; let h=0; for(let i=0;i<a.length;i+=7) h=(h*31+a[i])|0; return h; }""", eid)
def drag(pg, tr_sel, frac):
    b = pg.locator(tr_sel).bounding_box(); x = b["x"] + b["width"] * frac; y = b["y"] + b["height"] / 2
    pg.mouse.move(x, y); pg.mouse.down(); pg.mouse.move(x + 1, y); pg.mouse.up()
def floor_point(pg):
    return pg.evaluate("""() => { const G=SG.game, r=new THREE.Raycaster(); for (let y=560; y>200; y-=40) for (let x=330; x<920; x+=40) { if (document.elementFromPoint(x,y).id!=='gl') continue; r.setFromCamera(new THREE.Vector2(x/G.vw*2-1, -(y/G.vh)*2+1), SG.camera); const h=r.intersectObjects([SG.room.batched, SG.room.dyn], true)[0]; if (h && h.point.y<0.005 && h.object.material.name==='twoodHoney' && !G.me.c.raycast(r)) return [x,y]; } return [640,560]; }""")

def cat_run(pg):
    boot(pg); pg.evaluate("() => { SG.game.settings.paintAids = true; }")
    shot(pg, "01-title")
    pg.click("button[data-act=start-cat]"); i = info(pg)
    check("title: 當貓咪 starts a round in prep", i["mode"] == "play" and i["phase"] == "prep" and i["side"] == "cat", i["phase"])
    check("solo prep timer comes from rules.json (solo.prepSec)", abs(i["left"] - pg.evaluate("SG_RULES.solo.prepSec")) < 0.5, i["left"])
    check("while hiding, the other cats are invisible to you (original rule)", pg.evaluate("SG.game.ents.filter(e=>e!==SG.game.me).every(e=>!e.c.root.visible)"))
    x0, z0 = i["me"]["x"], i["me"]["z"]
    pg.keyboard.down("d"); step(pg, 1.0); pg.keyboard.up("d"); i = info(pg); d = math.hypot(i["me"]["x"] - x0, i["me"]["z"] - z0)
    check("WASD walks the cat (rules.cat.walkSpeed 1.6 m/s)", 1.3 < d < 1.8, round(d, 2))
    x0, z0 = i["me"]["x"], i["me"]["z"]; pg.keyboard.down("Shift"); pg.keyboard.down("a"); step(pg, 1.0); pg.keyboard.up("a"); pg.keyboard.up("Shift"); i = info(pg); d = math.hypot(i["me"]["x"] - x0, i["me"]["z"] - z0)
    check("Shift runs (2.5 m/s)", 2.1 < d < 2.7, round(d, 2)); check("guide advances after moving", i["guide"] >= 1, i["guide"])
    x1 = i["me"]["x"]; pg.keyboard.down("c"); pg.keyboard.down("a"); step(pg, 1.0); pg.keyboard.up("a"); i = info(pg); pg.keyboard.up("c"); step(pg, 0.3)
    check("hold C (or Ctrl): crouched sneak at ~0.8 m/s in the crouch pose", 0.6 < abs(i["me"]["x"] - x1) < 0.95 and i["me"]["pose"] == "crouch", (round(abs(i["me"]["x"] - x1), 2), i["me"]["pose"]))
    pg.keyboard.press("Space"); step(pg, 0.25); y1 = info(pg)["me"]["y"]; step(pg, 1.0); y2 = info(pg)["me"]["y"]
    check("Space jumps and the cat lands again", y1 > 0.5 and y2 < 0.05, (round(y1, 2), round(y2, 2)))
    b0 = len(events(pg, "bump")); pg.evaluate("""() => { const G=SG.game, R=SG.room, k=R.knock.find(k=>k.y<0.2&&Math.abs(k.x)<3&&Math.abs(k.z)<2.5&&!R.raw.blocked(k.x-0.5,k.z,0,0.15,0.1,0.3)); G.place('you', (k.x-0.5)*R.WS, 0, k.z*R.WS, Math.PI/2); G.cam.yaw=-Math.PI/2; }"""); pg.keyboard.down("Shift"); pg.keyboard.down("w"); step(pg, 1.2); pg.keyboard.up("w"); pg.keyboard.up("Shift"); step(pg, 0.8)
    check("running into a small prop knocks it (bump events)", len(events(pg, "bump")) > b0, len(events(pg, "bump")) - b0)
    # stairs to the loft
    r = pg.evaluate("""() => { const G=SG.game, W=SG.WS; G.placeU('you', -6.22, 0, -0.35, Math.PI); G.cam.yaw = 0; G.keys.w = true; G.step(5.6); G.keys.w = false; G.step(0.3); return [G.me.x/W, G.me.y/W, G.me.z/W]; }""")
    check("the cat walks up the staircase into the loft (plan height 2.7 = 4.05 m)", abs(r[1] - 2.7) < 0.05 and r[2] < -3.5, [round(v, 2) for v in r]); shot(pg, "02-loft")
    # ---- climb and stick (the owner's favourite): floor -> wall -> ceiling -> beam, hold still, pose + paint + clone up there, release
    P = "(() => { const m=SG.game.me, W=SG.WS; return {p:[m.x/W, m.y/W, m.z/W].map(v=>+v.toFixed(3)), n:m.cling ? m.cling.n.join(',') : null}; })()"
    pg.evaluate("() => { const G=SG.game; G.placeU('you', 6.3, 0, -0.74, 0); G.cam.yaw = 0; G.cam.pitch = 0.2; G.setPose('stand'); }"); step(pg, 0.3)
    pg.keyboard.down("Space"); step(pg, 0.1); a0 = pg.evaluate(P); step(pg, 1.0); a1 = pg.evaluate(P)
    check("Space next to a wall sticks to it and climbs at rules.cat.clingSpeed (1.3 m/s)", a0["n"] == "0,0,-1" and 1.1 < (a1["p"][1] - a0["p"][1]) * 1.5 < 1.5, (a0, a1))
    step(pg, 3.0); pg.keyboard.up("Space"); a2 = pg.evaluate(P); check("wall -> ceiling without falling off", a2["n"] == "0,-1,0" and abs(a2["p"][1] - 2.6) < 0.01, a2); shot(pg, "05a-on-ceiling")
    pg.keyboard.down("w")
    for _ in range(40):
        step(pg, 0.05); a3 = pg.evaluate(P)
        if a3["n"] == "0,0,1": break
    pg.keyboard.up("w"); check("ceiling -> side of a beam (WASD moves along the surface)", a3["n"] == "0,0,1" and abs(a3["p"][2] + 1.33) < 0.02, a3)
    pg.keyboard.down("Control")
    for _ in range(40):
        step(pg, 0.05); a4 = pg.evaluate(P)
        if a4["n"] == "0,-1,0": break
    pg.keyboard.up("Control"); check("Ctrl goes down and round the edge onto the underside of the beam", a4["n"] == "0,-1,0" and abs(a4["p"][1] - 2.44) < 0.01, a4)
    step(pg, 10.0); a5 = pg.evaluate(P); check("stuck means stuck: 10 s without input, position delta exactly 0", a5 == a4, a5)
    hb = texhash(pg); r = pg.evaluate("""() => { const G=SG.game, m=G.me; G.setPose('loaf'); G.step(0.5); const c=m.c.center(); m.c.beginStroke(); m.c.paint(c.clone().add(new THREE.Vector3(0,-0.1,0)), 0.08, [200,69,46], 0.8, 0, 0.8); m.c.endStroke(); G.meow(); const ok=G.decoy(); const d=G.decoys[0]; return {pose:m.c.pose, cling:!!m.cling, decoy:ok, sameQ: d ? d.c.root.quaternion.angleTo(m.c.root.quaternion) < 1e-6 : false, upsideDown: new THREE.Vector3(0,1,0).applyQuaternion(m.c.root.quaternion).y < -0.99}; }""")
    check("on the underside of a beam: pose, paint, meow and a clone all work; the clone hangs there too; the body is upside-down", r["pose"] == "loaf" and r["cling"] and r["decoy"] and r["sameQ"] and r["upsideDown"] and texhash(pg) != hb, r); shot(pg, "05b-posed-under-beam"); hb2 = texhash(pg)
    l0 = len(events(pg, "land")); pg.keyboard.press("Shift"); sq = 0
    for _ in range(12): step(pg, 0.1); sq = max(sq, pg.evaluate("SG.game.me.c.squash||0"))
    a6 = pg.evaluate(P); check("Shift lets go: the cat drops, lands with a squash, and the paint is still there", a6["n"] is None and a6["p"][1] < 0.05 and sq > 0.3 and len(events(pg, "land")) > l0 and texhash(pg) == hb2, (a6, round(sq, 2)))
    pg.keyboard.press("x"); r = pg.evaluate("""() => { const G=SG.game, W=SG.WS, out=[]; G.placeU('you', 2.0, 0, -6.9, 0); G.cam.yaw=Math.PI; G.setPose('stand'); G.step(0.2); const P=()=>({p:[G.me.x/W,G.me.y/W,G.me.z/W].map(v=>+v.toFixed(2)), n:G.me.cling?G.me.cling.n.join(','):null});
      G.tryAttach(G.me, 0, 1); out.push(P()); G.keys.d=true; for (let i=0;i<80 && G.me.cling && G.me.cling.n[0]===0;i++) G.step(0.05); G.keys.d=false; out.push(P()); G.keys[' ']=true; for (let i=0;i<80 && G.me.cling;i++) G.step(0.05); G.keys[' ']=false; G.step(0.3); out.push(P()); return out; }""")
    check("furniture too: stick to the side of the outdoor unit, go round its outside corner, then climb over the top edge and stand on it", r[0]["n"] == "0,0,-1" and r[1]["n"] in ("1,0,0", "-1,0,0") and r[2]["n"] is None and abs(r[2]["p"][1] - 0.65) < 0.02, r)
    # pose
    pg.evaluate("() => { SG.game.placeU('you', 1.9, 0.012, 0.6, 2.3); SG.game.cam.yaw = 2.5; SG.game.cam.pitch = 0.22; SG.game.cam.dist = 2.3; }"); step(pg, 0.5)
    pg.keyboard.down("r"); step(pg, 0.05); vis = pg.locator(".pw2").evaluate("e=>!e.classList.contains('hide')"); nseg = pg.locator(".pw2 .seg").count(); shot(pg, "02b-pose-wheel"); pg.hover(".pw2 .seg[data-pose=curl]"); pg.keyboard.up("r"); step(pg, 0.6); i = info(pg)
    check("hold R opens the radial pose wheel (8 poses + cancel), releasing R picks the segment under the mouse", vis and nseg == 9 and i["me"]["pose"] == "curl" and pg.locator(".pw2.hide").count() == 1, (nseg, i["me"]["pose"]))
    pg.keyboard.down("r"); step(pg, 0.05); pg.click(".pw2 .more"); pg.click(".pw2 .seg[data-pose=loaf]"); pg.keyboard.up("r"); step(pg, 0.5); p2 = info(pg)["me"]["pose"]
    pg.keyboard.down("r"); step(pg, 0.05); pg.click(".pw2 .seg.cancel"); pg.keyboard.up("r"); step(pg, 0.4)
    check("second page holds the other poses; the cancel segment returns to standing", p2 == "loaf" and info(pg)["me"]["pose"] == "stand", p2)
    pg.evaluate("SG.game.setPose('loaf')"); step(pg, 0.6)
    pg.mouse.click(600, 300, button="right"); l1 = info(pg)["viewLock"]; pg.mouse.click(600, 300, button="right"); check("right click toggles the view lock while posed", l1 and not info(pg)["viewLock"])
    pg.keyboard.press("2"); t1 = info(pg)["tags"]; pg.keyboard.press("2"); pg.keyboard.press("3"); s1 = info(pg)["seeThrough"]; pg.keyboard.press("3"); pg.keyboard.press("g")
    check("2 name tags, 3 see-through, G like", t1 and s1 and len(events(pg, "like")) == 1)
    pg.evaluate("SG.game.setPose('sit')"); step(pg, 0.8)
    kc = pg.locator(".keycol .kc").all_inner_texts(); cb = pg.locator(".cbar .slots .dia").count()
    check("HUD as in the original: right-edge key column (T, 1, R, F, right mouse, 2, 3, V, B) and bottom-centre Q + 2 clone slots + X", len(kc) == 9 and cb == 2 and pg.locator(".cbar .key.x").count() == 1, kc)
    # paint
    pg.keyboard.press("f"); step(pg, 0.6); i = info(pg)
    check("F opens paint mode and the panel", i["paintOn"] and pg.locator(".pp").evaluate("e=>!e.classList.contains('off')")); shot(pg, "03-paint-panel")
    pg.click(".swatches i[data-rgb='200,69,46']"); c = pg.evaluate("SG.game.paint.rgb"); check("swatch click sets the colour", c == [200, 69, 46], c)
    drag(pg, ".sl:has(span:text-is('G')) .tr", 0.9); c = pg.evaluate("SG.game.paint.rgb"); check("RGB slider changes the colour", c[1] > 215, c)
    pg.click(".tabs b[data-m=hsv]"); drag(pg, ".sl:has(span:text-is('H')) .tr", 0.6); c2 = pg.evaluate("SG.game.paint.rgb"); check("HSV tab + hue slider changes the colour", c2 != c, c2); pg.click(".tabs b[data-m=rgb]")
    wb = pg.locator(".wheel").bounding_box(); pg.mouse.move(wb["x"] + 110, wb["y"] + 40); pg.mouse.down(); pg.mouse.move(wb["x"] + 112, wb["y"] + 42); pg.mouse.up(); c3 = pg.evaluate("SG.game.paint.rgb"); check("colour wheel picks hue/saturation", c3 != c2, c3)
    vb = pg.locator(".vbar").bounding_box(); pg.mouse.move(vb["x"] + 10, vb["y"] + vb["height"] * 0.7); pg.mouse.down(); pg.mouse.move(vb["x"] + 10, vb["y"] + vb["height"] * 0.72); pg.mouse.up(); c4 = pg.evaluate("SG.game.paint.rgb"); check("value bar darkens the colour", max(c4) < max(c3), c4)
    pg.fill(".prev input", "#2F4B7C"); c5 = pg.evaluate("SG.game.paint.rgb"); check("hex field sets the colour", c5 == [47, 75, 124], c5)
    drag(pg, ".sl[data-s=metal] .tr", 0.8); drag(pg, ".sl[data-s=rough] .tr", 0.25); drag(pg, ".sl[data-s=size] .tr", 0.37); p = pg.evaluate("SG.game.paint")
    check("metallic / roughness / brush-size sliders", p["metal"] > 0.7 and p["rough"] < 0.35 and 0.07 < p["size"] < 0.09, (round(p["metal"], 2), round(p["rough"], 2), round(p["size"], 3)))
    pg.click(".tools button[data-tool=hard]"); h1 = pg.evaluate("SG.game.paint.hard"); pg.click(".tools button[data-tool=hard]"); check("hard/soft edge toggle", h1 is False and pg.evaluate("SG.game.paint.hard") is True)
    drag(pg, ".sl[data-s=metal] .tr", 0.0); drag(pg, ".sl[data-s=rough] .tr", 0.8)
    h0 = texhash(pg); r0 = info(pg)["me"]["painted"]; x, y = catxy(pg)
    pg.mouse.move(x - 30, y + 10); pg.mouse.down()
    for k in range(8): pg.mouse.move(x - 30 + k * 8, y + 10 + (k % 2) * 6)
    pg.mouse.up(); i = info(pg)
    check("left-drag on the body paints (texture changes, 1 undo step)", texhash(pg) != h0 and i["me"]["painted"] > r0 and i["undo"] == 1, round(i["me"]["painted"], 3))
    sz0 = pg.evaluate("SG.game.paint.size"); pg.mouse.move(500, 200); pg.mouse.down(button="right"); pg.mouse.move(560, 200); pg.mouse.up(button="right"); check("right-drag changes the brush size (original binding)", pg.evaluate("SG.game.paint.size") > sz0 + 0.02, round(pg.evaluate("SG.game.paint.size"), 3))
    drag(pg, ".sl[data-s=size] .tr", 0.37)
    g = pg.evaluate("""() => { const G=SG.game, c=G.me.c; const before=c.alb.slice(); const ctr=c.center(); const ray=new THREE.Raycaster(SG.camera.position.clone(), ctr.clone().sub(SG.camera.position).normalize()); const hit=c.raycast(ray); const R=0.05;
      const t0=performance.now(); for (let k=0;k<50;k++) c.paint(hit.point, R, [10,200,90], 0.8, 0, 0.8); const ms=(performance.now()-t0)/50; let changed=0, far=0, maxd=0;
      const A=c.A; c.parts.forEach(p=>{ const e=p.mesh.matrixWorld.elements; for(let j=0;j<p.th;j++) for(let i=0;i<p.tw;i++){ const o=((p.ry+j)*A+p.rx+i)*4; const k=(j*p.tw+i)*3; const x=p.tp[k],y=p.tp[k+1],z=p.tp[k+2]; const wx=e[0]*x+e[4]*y+e[8]*z+e[12], wy=e[1]*x+e[5]*y+e[9]*z+e[13], wz=e[2]*x+e[6]*y+e[10]*z+e[14]; const d=Math.hypot(wx-hit.point.x,wy-hit.point.y,wz-hit.point.z); const ch=before[o]!==c.alb[o]||before[o+1]!==c.alb[o+1]||before[o+2]!==c.alb[o+2]; if(ch){changed++; if(d>maxd) maxd=d;} else if(d>R*1.01) far++; } });
      c.alb.set(before); c.texA.needsUpdate=true; return {changed, maxd:+maxd.toFixed(4), far, R, msPerDab:+ms.toFixed(3)}; }""")
    check("3D brush: only texels inside the brush sphere change; the rest (incl. far side) untouched", g["changed"] > 50 and g["maxd"] <= g["R"] * 1.04 and g["far"] > 10000, g)
    check("CPU cost of one brush dab at 1024² is under 4 ms (texture upload not included)", g["msPerDab"] < 4, g["msPerDab"]); results.append(("STROKE_MS", True, g["msPerDab"]))
    # pattern brush (our own aid, enabled for this run)
    pg.click(".tools button[data-tool=pattern]"); pat = pg.evaluate("SG.game.paint.pattern"); x, y = catxy(pg)
    cols = pg.evaluate("""(a) => { const G=SG.game, c=G.me.c, before=c.alb.slice(); G.paint.rgb=[200,69,46]; G.paint.rgb2=[245,241,232]; G.paint.size=0.07; return 0; }""", [x, y])
    pg.mouse.move(x - 40, y - 5); pg.mouse.down()
    for k in range(10): pg.mouse.move(x - 40 + k * 8, y - 5)
    pg.mouse.up()
    cols = pg.evaluate("""() => { const c=SG.game.me.c, A=c.A; let red=0, cream=0; c.parts.forEach(p=>{ for(let j=0;j<p.th;j+=2) for(let i=0;i<p.tw;i+=2){ const o=((p.ry+j)*A+p.rx+i)*4; if (Math.abs(c.alb[o]-200)<8&&Math.abs(c.alb[o+1]-69)<8) red++; if (Math.abs(c.alb[o]-245)<5&&Math.abs(c.alb[o+1]-241)<5&&Math.abs(c.alb[o+2]-232)<5) cream++; } }); return [red, cream]; }""")
    check("pattern brush (stripes) lays down two alternating colours along the stroke", pat == "stripe" and cols[0] > 60 and cols[1] > 60, (pat, cols)); shot(pg, "04-pattern-brush")
    for _ in range(4): pg.click(".tools button[data-tool=pattern]")
    check("pattern button cycles back to plain", pg.evaluate("SG.game.paint.pattern") == "")
    hp = texhash(pg); ok = True
    for pose in [p[0] for p in pg.evaluate("SG.POSE_LIST")][1:] + ["sit"]:
        pg.evaluate("p=>SG.game.setPose(p)", pose); step(pg, 0.4); ok = ok and texhash(pg) == hp
    check("paint texture is identical after cycling all 13 poses", ok)
    pg.evaluate("() => SG.game.setPaintMode(true)"); step(pg, 0.3)
    # eyedropper: hold Space + click = lit on-screen colour; with Shift = unlit surface colour
    bx = by = None
    for yaw in (-1.7, -2.6, -1.4, -2.9):
        pg.evaluate("y => { SG.game.cam.yaw = y; SG.game.cam.pitch = 0.3; }", yaw); step(pg, 0.6); bx, by = proj(pg, 2.9 * 1.5, 0.40 * 1.5, 1.25 * 1.5)
        top = pg.evaluate("(a) => { const G=SG.game, r=new THREE.Raycaster(); r.setFromCamera(new THREE.Vector2(a[0]/G.vw*2-1, -(a[1]/G.vh)*2+1), SG.camera); if (G.me.c.raycast(r)) return null; const h=r.intersectObjects([SG.room.batched, SG.room.dyn], true)[0]; return h ? [h.point.x, h.point.y, h.point.z] : null; }", [bx, by])
        if 300 < bx < 930 and 140 < by < 520 and top and math.hypot(top[0] - 2.9 * 1.5, top[2] - 1.25 * 1.5) < 0.6 and top[1] > 0.2: break
    pg.keyboard.down("Space"); pg.keyboard.down("Shift"); pg.mouse.click(bx, by); pg.keyboard.up("Shift"); cu = pg.evaluate("SG.game.paint.rgb"); pg.mouse.click(bx, by); pg.keyboard.up("Space"); cl = pg.evaluate("SG.game.paint.rgb")
    check("Space+Shift+click picks the unlit surface colour of the beanbag (mustard ~217,169,58)", abs(cu[0] - 217) < 30 and abs(cu[1] - 169) < 30 and abs(cu[2] - 58) < 40, cu)
    scr = pg.evaluate("""(a) => { const k=SG.post.width/SG.game.vw; return SG.post.pick(SG.scene, SG.camera, a[0]*k, a[1]*k, SG.post.width, SG.post.height, 'lit'); }""", [bx, by])
    check("Space+click picks the lit colour as rendered before grading (differs from the unlit colour, equals a re-read of that pixel)", cl != cu and max(abs(cl[k] - scr[k]) for k in range(3)) <= 3 and cl[0] > cl[2], (cl, scr))
    check("picked colour lands in the recent swatches", pg.locator(".swatches i[data-rgb='%d,%d,%d']" % tuple(cl)).count() >= 1)
    kx, ky = floor_point(pg); pg.click(".tools button[data-tool=pick]"); pg.mouse.click(kx, ky); c2 = pg.evaluate("SG.game.paint.rgb")
    check("eyedropper tool button picks the wooden floor and returns to the brush", c2[0] > c2[1] > c2[2] and c2[0] > 90 and pg.evaluate("SG.game.paint.tool") == "brush", c2)
    pg.evaluate("() => { SG.game.cam.yaw = 2.5; SG.game.cam.pitch = 0.22; }"); step(pg, 0.6)
    pg.evaluate("() => SG.ui.refreshSug()"); sg = pg.evaluate("SG.game.suggest()"); pg.locator(".sug div").nth(0).click(); c3 = pg.evaluate("SG.game.paint.rgb")
    check("environment suggestions (our aid): 4 colours, clicking one selects it", len(sg) == 4 and c3 == sg[0], sg)
    hf = texhash(pg); pg.click(".tools button[data-tool=fill]"); i = info(pg); check("fill paints the whole body", i["me"]["painted"] > 0.95 and texhash(pg) != hf, round(i["me"]["painted"], 3))
    pg.click(".tools button[data-tool=undo]"); check("undo restores the texture before the fill", texhash(pg) == hf)
    pg.evaluate("() => { while (SG.game.undo()) {} }"); base = texhash(pg); x, y = catxy(pg); hashes = [base]
    for k in range(22):
        pg.evaluate("k => { SG.game.paint.rgb = [k*11, 255-k*9, 60+k*5]; SG.game.paint.size = 0.03; }", k)
        pg.mouse.move(x - 40 + (k % 6) * 14, y - 20 + (k // 6) * 14); pg.mouse.down(); pg.mouse.move(x - 38 + (k % 6) * 14, y - 18 + (k // 6) * 14); pg.mouse.up(); hashes.append(texhash(pg))
    n = info(pg)["undo"]; ok = n >= 20
    for k in range(20):
        pg.keyboard.press("Control+z"); ok = ok and texhash(pg) == hashes[len(hashes) - 2 - k]
    check("Ctrl+Z walks back 20 strokes one by one", ok, n)
    # see-through painting (key 3): default off = things in the way block the brush; on = paint through them, front and back in one pass
    pg.evaluate("() => { const G=SG.game; G.placeU('you', 1.9, 0.012, 0.6, 2.3); G.setPose('sit'); G.cam.yaw = 2.5; G.cam.pitch = 0.22; G.cam.dist = 2.3; G.setSeeThrough(false); G.paint.rgb=[30,160,90]; G.paint.size=0.05; }"); step(pg, 0.6)
    r = pg.evaluate("""() => { const G=SG.game, m=G.me, c=m.c, out={}; const ctr=c.center(); const cam=SG.camera.position.clone(); const mid=ctr.clone().lerp(cam, 0.45);
      const wall=new THREE.Mesh(new THREE.BoxGeometry(1.2,1.2,0.04), new THREE.MeshBasicMaterial({color:0x8a6a48})); wall.position.copy(mid); wall.lookAt(cam); SG.room.dyn.add(wall); wall.updateMatrixWorld(true); out.wall=true; window.__wall=wall;
      const p=ctr.clone().project(SG.camera); out.xy=[(p.x*.5+.5)*G.vw, (-p.y*.5+.5)*G.vh]; return out; }""")
    x, y = r["xy"]; h0 = texhash(pg); pg.mouse.move(x - 12, y); pg.mouse.down(); pg.mouse.move(x + 12, y + 3); pg.mouse.up(); blocked_same = texhash(pg) == h0
    pg.keyboard.press("3"); shot(pg, "05c-see-through-paint"); pg.mouse.move(x - 12, y); pg.mouse.down(); pg.mouse.move(x + 12, y + 3); pg.mouse.up(); through = texhash(pg) != h0
    far = pg.evaluate("""() => { const G=SG.game, c=G.me.c, A=c.A, ctr=c.center(), cam=SG.camera.position, v=ctr.clone().sub(cam).normalize(); let front=0, back=0; c.parts.forEach(p=>{ const e=p.mesh.matrixWorld.elements; for(let j=0;j<p.th;j+=2) for(let i=0;i<p.tw;i+=2){ const o=((p.ry+j)*A+p.rx+i)*4; if (Math.abs(c.alb[o]-30)>10||Math.abs(c.alb[o+1]-160)>10||Math.abs(c.alb[o+2]-90)>10) continue; const k=(j*p.tw+i)*3, x=p.tp[k],y=p.tp[k+1],z=p.tp[k+2]; const wx=e[0]*x+e[4]*y+e[8]*z+e[12], wy=e[1]*x+e[5]*y+e[9]*z+e[13], wz=e[2]*x+e[6]*y+e[10]*z+e[14]; const d=(wx-ctr.x)*v.x+(wy-ctr.y)*v.y+(wz-ctr.z)*v.z; if (d<-0.02) front++; else if (d>0.02) back++; } }); SG.room.dyn.remove(__wall); return [front, back]; }""")
    check("see-through painting: with a board between camera and cat the normal brush does nothing; key 3 on -> the same stroke paints, and texels on the far side of the body change in the same pass", blocked_same and through and far[0] > 20 and far[1] > 20 and info(pg)["seeThrough"], (blocked_same, through, far))
    pg.keyboard.press("3"); pg.keyboard.press("v"); fl = pg.evaluate("SG.game.paint.flat"); pg.keyboard.press("v"); check("V toggles shading in paint mode", fl is True and not pg.evaluate("SG.game.paint.flat"))
    pg.keyboard.press("f")
    r = pg.evaluate("""() => { const G=SG.game; G.place('you', SG.room.vac.x, 0.5, SG.room.vac.z, 0); G.step(1.0); const a=[G.me.x,G.me.z,G.me.y]; G.step(4.0); return {a, b:[G.me.x,G.me.z,G.me.y], vac:[SG.room.vac.x, SG.room.vac.z]}; }""")
    moved = math.hypot(r["b"][0] - r["a"][0], r["b"][1] - r["a"][1]); off = math.hypot(r["b"][0] - r["vac"][0], r["b"][1] - r["vac"][1])
    check("cat rides the robot vacuum (carried along, stays on top)", moved > 0.8 and off < 0.15 and abs(r["b"][2] - 0.135) < 0.03, (round(moved, 2), round(off, 3), round(r["b"][2], 3)))
    # cat flap: cats fit, dogs do not
    fl = pg.evaluate("""() => { const G=SG.game, R=SG.room; return [!!R.blocked(-5.6*R.WS, 2.95*R.WS, 0, G.me.rad, 0.24, 0.3), !!R.blocked(-5.6*R.WS, 2.95*R.WS, 0, 0.22, 0.24, 0.62)]; }""")
    check("cat flap in the front door: a cat fits through, a dog does not", fl == [False, True], fl)
    pg.keyboard.press("1"); check("1 = meow event", len(events(pg, "meow")) == 1)
    pg.evaluate("() => { SG.game.placeU('you', 2.9, 0.42, 1.25, -2.0); SG.game.setPose('loaf'); }"); step(pg, 0.8)
    pg.keyboard.press("q"); pg.keyboard.press("q"); i = info(pg); check("Q drops a decoy; second one is refused during the 30 s cooldown", i["decoys"] == 1 and len(events(pg, "denied")) == 1, i["decoys"])
    pg.keyboard.press("x"); check("X recalls decoys", info(pg)["decoys"] == 0)
    still = pg.evaluate("""() => { const G=SG.game, c=G.ent('cat0').c; const snap=()=>c.meshes.map(m=>Array.from(m.matrixWorld.elements).join()).join('|'); const a=snap(); G.step(1.0); return a===snap() && c.pose!=='stand'; }""")
    check("a posed cat that is not yours is perfectly still for 60 frames", still)
    emb = pg.evaluate("""() => { const G=SG.game, p=SG.room.platforms.find(p=>!p.wall&&p.x1-p.x0>0.9&&p.z1-p.z0>0.9&&p.y1-p.y0>0.6&&p.y0<0.05); const x=(p.x0+p.x1)/2, z=(p.z0+p.z1)/2; G.place('you', x, 0.1, z, 0); G.me.vy=0; G.step(0.02); const d=G.embedDepth(G.me); G.embedT=0; for (let k=0;k<200;k++){ G.me.x=x; G.me.z=z; G.me.y=0.1; G.me.vy=0; G.step(0.02); } return {depth:+d.toFixed(2), exposed:G.me.exposed}; }""")
    check("buried too deep inside furniture: warning, then exposed after 3 s", emb["depth"] > 0.1 and emb["exposed"] and len(events(pg, "embed")) >= 2, emb)
    # seek: an unpainted white cat in the open gets stared at and found
    pg.evaluate("() => { const G=SG.game; G.me.c.fill([255,255,255],0.8,0); G.placeU('you', -2.6, 0, 1.4, 0); G.setPose('sit'); }"); step(pg, 0.5)
    pg.click("button[data-act=vote]"); i = info(pg); check("vote-to-skip button (alone with bots: instant) -> seek", i["phase"] == "seek", i["phase"])
    check("when the search starts everyone becomes visible", pg.evaluate("SG.game.ents.every(e=>e.c.root.visible)")); shot(pg, "06-seek-start")
    t = 0; shot_done = False
    ov = False
    while t < 85 and not info(pg)["me"]["out"]:
        step(pg, 0.5); t += 0.5
        if not shot_done and events(pg, "say"): shot(pg, "07-dog-staring-bubble"); shot_done = True
        if not ov and pg.locator(".ovl:not(.hide)").count(): shot(pg, "07b-overlook-counter"); ov = True
    i = info(pg); hit = [e for e in events(pg, "hit") if e.get("cat") == "you"]; dg = [e["v"] for e in events(pg, "danger")]
    check("bot dog finds an unpainted cat sitting in the open and shoots it", i["me"]["out"] and len(hit) == 1, "after %.1f s" % t)
    sc = [e for e in events(pg, "score") if e.get("cat") == "you"]
    check("THE mechanic on the hider's side: while the dog had you on screen the counter popped up at the bottom right (with tick sounds) and the score climbed", ov and len(sc) >= 2 and len(events(pg, "ovltick")) == len(sc) and max(e["add"] for e in sc) >= 20, (len(sc), [e["add"] for e in sc][:8]))
    check("FUN-1 danger meter rose before the catch (heartbeat/vignette input), FUN-3 the dog spoke (stare/aim bubbles)", dg and max(dg) > 0.6 and len(events(pg, "say")) >= 1, (round(max(dg), 2) if dg else None, [e["text"] for e in events(pg, "say")][:4]))
    check("caught in basic mode -> free spectator camera; 4 follows a player, 5 returns to free", i["me"]["fly"]); shot(pg, "08-caught")
    pg.keyboard.press("4"); f1 = pg.evaluate("!!SG.game.follow"); pg.keyboard.press("5"); check("spectator keys 4 / 5", f1 and not pg.evaluate("!!SG.game.follow"))
    while info(pg)["phase"] == "seek" and t < 130: step(pg, 2.0); t += 2
    i = info(pg); check("seek ends -> reveal with a winner", i["phase"] == "reveal" and i["winner"] in ("cats", "dogs"), (i["winner"], i["reason"]))
    step(pg, 1.5); shot(pg, "09-reveal-cat-side")
    check("reveal shows a tag for every animal and the result panel", pg.locator(".tags .tag").count() == pg.evaluate("SG.game.ents.filter(e=>e.c.root.visible).length") and pg.locator(".result").is_visible(), pg.locator(".tags .tag").count())
    glow = pg.evaluate("""() => SG.game.ents.filter(e=>e.team==='cat').map(e=>({out:SG.game.state.players[e.id].out, r:e.c.glow.value.r, b:e.c.glow.value.b}))""")
    check("reveal glow: found = blue, not found = red, matching the rules state", all((g["b"] > g["r"]) == g["out"] for g in glow), glow)

def dog_goto_view(pg, cid):
    """test scaffolding: stand the dog somewhere with a clear line to the cat (a player would walk there)"""
    return pg.evaluate("""id => { const G=SG.game, m=G.me, c=G.ent(id).c.center(), eh=m.eyeH, ray=new THREE.Raycaster();
      for (let r=1.0; r<7; r+=0.3) for (let a=0; a<6.28; a+=0.3) { const x=c.x+Math.cos(a)*r, z=c.z+Math.sin(a)*r; const gy=SG.room.groundAt(x,z,c.y+0.3,0); if (Math.abs(gy-c.y)>4.6 || SG.room.blocked(x,z,gy,0.25,0.24,0.62)) continue;
        const o=new THREE.Vector3(x,gy+eh,z), d=c.clone().sub(o), L=d.length(); d.normalize(); ray.set(o,d); ray.far=L; const h=ray.intersectObjects([SG.room.batched, SG.room.dyn], true)[0];
        if (!h || h.distance > L-0.12) { G.place('you', x, gy, z, 0); return true; } } return false; }""", cid)
def dog_clear_spot(pg):
    pg.evaluate("""() => { const G=SG.game; for (const p of [[0.5,1.6],[1.2,-1.3],[-2.6,0.2],[2.2,-1.9],[-1.6,1.9],[3.0,0.9],[0.9,0.6],[0,3.3]]) { const W=SG.WS; if (SG.room.blocked(p[0]*W,p[1]*W,0,0.25,0.24,0.62)) continue; if (G.ents.every(e=>e.team!=='cat'||Math.hypot(e.x-p[0]*W,e.z-p[1]*W)>2.2)) { G.placeU('you',p[0],0,p[1],Math.PI); break; } } G.me.yaw=Math.PI; G.me.pitch=1.2; }""")
def dog_aim(pg, cid):
    pg.evaluate("""id => { const G=SG.game, m=G.me, c=G.ent(id).c.center(); const dx=c.x-m.x, dy=c.y-(m.y+m.eyeH), dz=c.z-m.z; m.yaw=Math.atan2(dx,dz); m.pitch=Math.atan2(dy,Math.hypot(dx,dz)); }""", cid)

def dog_run(pg):
    boot(pg); pg.click(".card.dog .cy[data-k=breed] .nx"); pg.click(".card.dog .cy[data-k=collar] .nx")
    check("title cyclers choose breed and collar (preview turntable updates)", pg.evaluate("[SG.game.pick.dog.breed, SG.game.pick.dog.collar]") == ["corgi", "red"], pg.evaluate("SG.game.pick.dog"))
    pg.click("button[data-act=start-dog]"); i = info(pg)
    check("當狗狗 starts as a dog waiting in the genkan", i["side"] == "dog" and i["phase"] == "prep" and pg.locator(".wait").is_visible())
    pg.keyboard.press("Enter"); i = info(pg); check("Enter (vote) goes in -> seek, 5 ammo", i["phase"] == "seek" and i["players"]["you"]["ammo"] == 5)
    x0 = i["me"]["x"]; pg.keyboard.down("w"); step(pg, 1.0); pg.keyboard.up("w"); d = info(pg)["me"]["x"] - x0; check("dog walks at rules.dog.speed (1.8 m/s)", 1.5 < d < 2.0, round(d, 2))
    pg.keyboard.press("Space"); step(pg, 0.2); yj = info(pg)["me"]["y"]; step(pg, 0.8)
    e0 = pg.evaluate("SG.game.me.eyeH"); pg.keyboard.down("Control"); step(pg, 0.5); e1 = pg.evaluate("SG.game.me.eyeH"); pg.keyboard.up("Control"); step(pg, 0.5)
    pg.mouse.click(640, 360, button="right"); th = info(pg)["third"]; step(pg, 0.3); shot(pg, "10-dog-third-person"); pg.mouse.click(640, 360, button="right")
    check("seeker controls as in the original: Space jumps, Ctrl crouches (eye lower), right click toggles third person", yj > 0.2 and e1 < e0 * 0.7 and th and not info(pg)["third"], (round(yj, 2), round(e0, 2), round(e1, 2)))
    check("all dogs share one eye height by default (breeds are cosmetic)", abs(e0 - pg.evaluate("SG_RULES.dog.eyeHeightDefault")) < 1e-6, e0)
    dog_clear_spot(pg); step(pg, 0.1)
    pg.mouse.click(640, 360); b1 = info(pg)["players"]["you"]["ammo"]; shot(pg, "11-blaster-fire"); pg.mouse.click(640, 360); step(pg, 0.5); pg.mouse.click(640, 360); i = info(pg); b2 = i["players"]["you"]["ammo"]
    check("miss: 5 -> 4; clicks inside 1.5 s do nothing", b1 == 4 and b2 == 4, (b1, b2))
    check("the shot is a spread of paint pellets that leave splats on the surface", i["splats"] >= 5 and len(events(pg, "blast")) == 1, i["splats"]); step(pg, 1.2)
    pg.evaluate("() => { SG.game.placeU('cat0', -2.4, 0, 0.3, 1.0); }"); step(pg, 0.2); hc = texhash(pg, "cat0"); dog_goto_view(pg, "cat0"); step(pg, 0.2); dog_aim(pg, "cat0"); shot(pg, "12-dog-aim"); pg.mouse.click(640, 360); step(pg, 0.6); i = info(pg)
    check("hit a still cat: +1 ammo, cat is out, and the cat keeps a paint mark", i["players"]["you"]["ammo"] == 5 and i["players"]["cat0"]["out"] and texhash(pg, "cat0") != hc, i["players"]["you"]["ammo"]); shot(pg, "13-dog-hit")
    step(pg, 1.5)
    s = pg.evaluate("""() => { const G=SG.game, out={}; const sc=id=>G.state.players[id].score; const run=(cx,cz,yaw)=>{ G.placeU('cat1', cx, 0, cz, 0); G.placeU('you', 1.2, 0, 1.4, Math.PI); G.me.yaw=yaw; G.me.pitch=-0.11; G.ovT=9; G.step(0.2); const s0=sc('cat1'); G.ovT=0; G.step(0.4); return sc('cat1')-s0; };
      out.centre=run(1.2,-1.4,Math.PI); out.edge=run(1.2,-1.4,Math.PI+0.74); out.behind=run(1.2,3.0,Math.PI); out.wall=run(1.2,-4.6,Math.PI); out.far=run(1.2,-3.3,Math.PI); out.tick=SG_RULES.overlooked.tickEverySec; return out; }""")
    check("THE mechanic, hunter side: a hider dead centre and close scores exactly 45 per tick (2 ticks/s, our guess); at the screen edge little; behind the hunter 0; behind a wall 0; farther away less", s["centre"] == 45 and 0 < s["edge"] <= 15 and s["behind"] == 0 and s["wall"] == 0 and 0 < s["far"] < 45 and s["tick"] == 0.5, s)
    step(pg, 0.3); check("the ranking panel on the left lists the hiders by score (shown to hunters because the host setting is on)", pg.locator(".rank:not(.hide) div").count() >= 3, pg.locator(".rank div").count()); shot(pg, "13b-rank-panel")
    b0 = info(pg)["players"]["you"]["ammo"]
    pg.evaluate("() => { const G=SG.game; const c=G.ent('cat1'); c.speed=2.0; const o=new THREE.Vector3(G.me.x,0.5,G.me.z); const d=c.c.center().sub(o).normalize(); d.y+=0.12; d.normalize(); G.fire(G.me,o,d); c.speed=0; }")
    i = info(pg); check("missing a running cat costs no ammo", i["players"]["you"]["ammo"] == b0 and events(pg, "miss")[-1].get("free") is True, i["players"]["you"]["ammo"]); step(pg, 1.6)
    dog_clear_spot(pg); n = 0
    while info(pg)["phase"] == "seek" and n < 12: pg.mouse.click(640, 360); step(pg, 1.6); n += 1
    i = info(pg); check("end: ammo runs out -> reveal, cats win (no-ammo)", i["phase"] == "reveal" and i["winner"] == "cats" and i["reason"] == "no-ammo", (i["winner"], i["reason"], n))
    step(pg, 2.0); shot(pg, "14-reveal-dog-side"); check("paint splats stay for the reveal", info(pg)["splats"] >= 25, info(pg)["splats"])
    pg.click(".result .btn:text('再來一局')"); pg.keyboard.press("Enter"); i = info(pg); check("再來一局 starts a fresh round", i["phase"] == "seek" and i["players"]["you"]["ammo"] == 5 and i["splats"] == 0)
    pg.evaluate("() => { [[0.5,1.6],[1.2,-1.3],[-2.6,0.2],[2.2,-1.9]].forEach((p,i)=>SG.game.placeU('cat'+i, p[0], 0, p[1], i)); }"); step(pg, 0.2) # test scaffolding: cats in the open (a cat inside a box cannot be seen from a dog's eye height at all)
    for cid in ["cat0", "cat1", "cat2", "cat3"]:
        ok = dog_goto_view(pg, cid); step(pg, 0.2); dog_aim(pg, cid); step(pg, 0.02); pg.mouse.click(640, 360); step(pg, 1.6)
    i = info(pg); check("end: every cat found -> reveal, dogs win (all-found)", i["phase"] == "reveal" and i["winner"] == "dogs" and i["reason"] == "all-found", (i["winner"], i["reason"], [p["out"] for k, p in i["players"].items() if k != "you"]))
    step(pg, 1.0); shot(pg, "15-reveal-dogs-win")
    pg.keyboard.press("Enter"); check("Enter in reveal returns to the title", info(pg)["mode"] == "title")
    pg.evaluate("() => { SG.game.settings.seek = 6; }"); pg.click("button[data-act=start-dog]"); pg.keyboard.press("Enter"); step(pg, 6.5); i = info(pg)
    check("end: time up with cats left -> reveal, cats win (time)", i["phase"] == "reveal" and i["winner"] == "cats" and i["reason"] == "time", (i["winner"], i["reason"]))
    pg.evaluate("() => { SG.game.toTitle(); SG.game.settings.seek = 90; }"); pg.click("button[data-act=start-cat]")
    r = pg.evaluate("""() => { const G=SG.game; G.placeU('you', 2.9, 0.42, 1.25, -2.0); G.setPose('loaf'); G.step(0.5); G.decoy(); G.placeU('you', -3.0, 0, -2.0, 0); G.skip(); G.step(0.1); const d=G.ent('dog0'), dc=G.decoys[0]; const o=new THREE.Vector3(0.5*SG.WS,0.9,1.0*SG.WS); const ok=G.fire(d,o,dc.c.center().sub(o).normalize()); return {ok, out:G.state.players.you.out, vis:dc.c.root.visible}; }""")
    check("a shot that hits a decoy takes the real cat out", r["ok"] and r["out"] and not r["vis"], r)

LOSJS = """() => { window.LOS = function (e) { const c=e.c.center(), ray=new THREE.Raycaster(); for (let r=0.6; r<4; r+=0.3) for (let a=0; a<6.28; a+=0.4) for (const dy of [0.3, 0.8, -0.2]) { const o=new THREE.Vector3(c.x+Math.cos(a)*r, c.y+dy, c.z+Math.sin(a)*r); if (SG.game.solidAt(o.x,o.y,o.z)) continue; const d=c.clone().sub(o), L=d.length(); ray.set(o, d.normalize()); ray.far=L; const h=ray.intersectObjects([SG.room.batched, SG.room.dyn], true)[0]; if (!h || h.distance > L-0.1) return o; } return c.clone().add(new THREE.Vector3(0.7,0.5,0.5)); }; }"""
def modes_run(pg):
    boot(pg, setup="() => { const G=SG.game; G.settings.seek=60; }"); pg.evaluate(LOSJS)
    d = pg.evaluate("[SG.game.settings.mode, SG_RULES.solo.botCatsWhenCat, SG_RULES.solo.botDogsWhenCat, SG.game.settings.prep, SG.game.settings.seek]")
    check("solo defaults: infection, 9 bot cats + 2 bot dogs, prep 75 s", d[0] == "infection" and d[1] == 9 and d[2] == 2 and d[3] == 75, d)
    lm = pg.evaluate("[window.__loadMs, SG.bootT.build, SG.bootT.first]"); results.append(("LOAD_MS", True, lm)); check("loading bar is shown and removed; time from script start to first frame is recorded", pg.locator("#boot").count() == 0 and lm[0] > 0, lm)
    mm = pg.locator(".mm .btn").all_inner_texts(); check("main menu: create room / find room / settings / quit + maps, language buttons", mm[:4] == ["建立房間", "尋找房間", "設定", "結束遊戲"] and pg.locator(".langs .lg").count() == 3, mm); shot(pg, "19-main-menu")
    pg.click("button[data-act=mm-options]"); pg.click(".op button[data-tab=general]"); pg.click(".op .cyc[data-k=lang] .nx"); pg.click(".op .cyc[data-k=lang] .nx"); drag(pg, ".op .sl[data-s=fov] .tr", 0.97); pg.click(".op .cyc[data-k=invertY] .nx"); shot(pg, "19b-options"); tabs = pg.locator(".op .side .btn").count(); o = pg.evaluate("SG.game.opts"); pg.click("button[data-act=op-back]"); en = pg.locator(".mm .btn").first.inner_text()
    check("options menu: 6 sections; language -> English changes the menu; FOV slider and invert-Y are stored", tabs == 7 and o["lang"] == "en" and o["fov"] >= 95 and o["invertY"] and en == "Create room", (tabs, o["lang"], o["fov"], en))
    pg.evaluate("() => { SG.game.opts.lang='zh'; SG.game.opts.fov=62; SG.game.opts.invertY=false; }"); pg.click("button[data-act=mm-find]"); nn = pg.locator(".ov2 .box").inner_text(); pg.click(".ov2 .box .btn"); check("find room: says honestly that online play is not built", "還沒做完" in nn, nn[:40])
    pg.click("button[data-act=mm-create]"); shot(pg, "20-host-settings")
    pg.fill("input[data-f=seek]", "999999"); pg.keyboard.press("Tab"); pg.fill("input[data-f=meowEvery]", "5"); pg.keyboard.press("Tab"); pg.click(".hs .custom summary"); pg.click(".hs .cyc[data-k=night] .nx"); pg.fill("input[data-f=ammo]", "1"); pg.keyboard.press("Tab"); pg.click(".hs .cyc[data-k=fMono] .nx"); pg.click(".hs .cyc[data-k=board] .nx"); pg.click(".hs .cyc[data-k=board] .nx")
    st = pg.evaluate("SG.game.settings"); check("room settings, three columns: mode, the three times (999999 allowed = practically endless), forced taunt interval, ranking-to-hunters, filters, map list; our own rules sit in a separate 自訂規則 block", pg.locator(".hs .col").count() == 3 and st["seek"] == 999999 and st["night"] and st["ammo"] == 1 and st["forcedMeow"] and st["meowEvery"] == 5 and st["fMono"] and st["board"] and pg.locator(".maplist button").count() >= 4, {k: st[k] for k in ("seek", "night", "ammo", "forcedMeow", "meowEvery", "fMono", "board")})
    pg.click("button[data-act=hs-start]"); step(pg, 0.5); lb = info(pg)["lobby"]; shot(pg, "20b-lobby")
    check("start -> lobby: map card, player counter 12 / 12, hunter-lottery countdown, mat on the floor", lb and lb["n"] == 12 and 18 < lb["t"] <= 20 and pg.locator(".mapcard img").count() == 1 and pg.locator(".lobbyhud .cnt b").inner_text() == "12 / 12" and "獵人抽選" in pg.locator(".lot").inner_text(), lb)
    pg.click("button[data-act=body]"); pg.click(".bp button[data-body='dango:1.7']"); step(pg, 0.3); shot(pg, "20c-body-picker"); sz = info(pg)["me"]["size"]; pg.keyboard.press("b")
    check("body picker in the lobby: 6 builds x 3 sizes (x1.0 / x1.4 / x1.7); choosing one respawns you with it", pg.locator(".bp .grid button").count() == 18 and sz == 1.7 and pg.evaluate("SG.game.pick.cat.breed") == "dango", sz)
    on = pg.evaluate("() => { const G=SG.game; G.place('you', G.lobby.x, 0, G.lobby.z, 0); G.step(0.3); const a=G.lobby.on; G.place('you', G.lobby.x - 3, 0, G.lobby.z, 0); G.step(0.3); return [a, G.lobby.on]; }")
    check("standing on the mat enters the hunter lottery, stepping off leaves it", on == [True, False], on)
    pg.keyboard.press("Enter"); step(pg, 0.2); i = info(pg); n = pg.evaluate("[SG.game.ents.filter(e=>e.team==='cat').length, SG.game.ents.filter(e=>e.team==='dog').length]")
    check("lottery over (not on the mat) -> infection round starts with you + 9 bot cats hiding and 2 bot dogs waiting; your size is kept", i["gameMode"] == "infection" and i["phase"] == "prep" and i["side"] == "cat" and n == [10, 2] and i["me"]["size"] == 1.7, (n, i["phase"]))
    pg.evaluate("() => { SG.game.pick.cat.size = 1; }")
    pg.keyboard.press("Enter"); step(pg, 0.1); fm = pg.evaluate("SG.post.final.uMono.value"); step(pg, 5.9); shot(pg, "21-night-mode"); i = info(pg); nt = pg.evaluate("[SG.room.night, SG.game.torch.intensity, SG.room.sunLight.intensity]")
    check("night mode: lights off, the leading dog carries a torch", nt[0] and nt[1] > 10 and nt[2] < 1, nt)
    check("forced taunt (meow): the cats meow on the interval (5 s) during the search", len([e for e in events(pg, "meow") if e.get("forced")]) >= 8, len(events(pg, "meow")))
    r = pg.evaluate("""() => { const G=SG.game; G.settings.night=false; SG.room.setNight(false); const d=G.ent('dog0'); const c=G.me.c.center(); const o=LOS(G.me); G.state.players.dog0.lastShot=-99; const ok=G.fire(d,o,c.clone().sub(o).normalize()); G.step(0.5); return {ok, me:G.me.id, team:G.me.team, ammo:G.state.players.you.ammo, hunters:SGCore.hunters(G.state).length}; }""")
    check("infection: when you are found you become a dog with fresh ammo (first-person, blaster)", r["ok"] and r["me"] == "you#h" and r["team"] == "dog" and r["ammo"] == 1 and r["hunters"] == 3 and pg.locator(".ammo").is_visible(), r); shot(pg, "22-infection-became-dog")
    step(pg, 0.3); fm2 = pg.evaluate("SG.post.final.uMono.value"); shot(pg, "22b-monochrome-filter-as-hunter")
    check("host filter (monochrome) applies to the hunter's screen only: off while you were a cat, on once you are a dog", fm == 0 and fm2 == 1, (fm, fm2))
    pg.evaluate("() => { const G=SG.game; G.toTitle(); G.settings.ammo=5; G.settings.forcedMeow=false; G.settings.fMono=false; G.settings.seek=120; }")
    pg.click(".modes b[data-mode=double]"); pg.click("button[data-act=start-cat]"); i = info(pg)
    check("double mode: everyone starts as a hiding cat, no dogs", i["gameMode"] == "double" and pg.evaluate("SG.game.ents.every(e=>e.team==='cat')"))
    pg.evaluate("() => { SG.game.placeU('you', 2.9, 0.42, 1.25, -2.0); SG.game.setPose('loaf'); SG.game.me.c.fill([217,169,58],0.9,0); }"); step(pg, 0.5); pg.keyboard.press("Enter"); step(pg, 0.5); i = info(pg)
    r = pg.evaluate("""() => { const G=SG.game, out={me:G.me.id, hunters:G.ents.filter(e=>e.team==='dog').length, body:G.ent('you').c.root.visible && G.ent('you').c.pose}; const b=G.ent('you').c.center(); let o=LOS(G.ent('you')); out.own=G.fire(G.me,o,b.clone().sub(o).normalize()); out.ammoAfterOwn=G.state.players.you.ammo; G.state.players.you.lastShot=-99; const c=G.ent('p0').c.center(); o=LOS(G.ent('p0')); G.fire(G.me,o,c.clone().sub(o).normalize()); out.found=G.state.players.you.found; return out; }""")
    check("double: at the search everyone gets a hunter body, your painted body stays; shooting your own body is a miss, finding another counts", r["me"] == "you#h" and r["hunters"] == 4 and r["body"] == "loaf" and r["ammoAfterOwn"] == 4 and r["found"] == ["p0"], r); shot(pg, "23-double-hunt")
    r = pg.evaluate("""() => { const G=SG.game; G.placeU('p1', 0.5, 0, 1.6, 0); G.placeU('p2', -2.6, 0, 0.2, 0); G.step(0.1); ['p1','p2'].forEach(id=>{ G.state.players.you.lastShot=-99; const c=G.ent(id).c.center(); const o=LOS(G.ent(id)); G.fire(G.me,o,c.clone().sub(o).normalize()); }); G.step(1.0); return [G.state.phase, G.state.winner, G.state.reason]; }""")
    check("double: first to find all the others wins", r == ["reveal", "you", "double-all"], r); step(pg, 1.0); shot(pg, "24-double-result")

def world_run(pg):
    boot(pg, "q=low&shot=room")
    st = pg.evaluate("SG.room.stats"); inv = pg.evaluate("SG.room.inventory"); books = inv.get("書", 0)
    check("house inventory: >= 200 kinds, books at most 15% of items", st["types"] >= 200 and books / st["items"] <= 0.15, {"types": st["types"], "items": st["items"], "books": books, "bookShare": round(books / st["items"], 3)})
    rooms = pg.evaluate("Object.keys(SG.room.inventoryByRoom).map(k=>[k, Object.keys(SG.room.inventoryByRoom[k]).length])"); check("inventory is recorded per area (10+ areas)", len(rooms) >= 10, rooms)
    sz = pg.evaluate("(() => { const b=SG.room.bounds, P=SG.room.platforms; return {w:+(b.x1-b.x0).toFixed(1), d:+(b.z1-b.z0).toFixed(1), ceiling:+(SG.room.K.H*SG.WS).toFixed(2), scale:SG.WS, route:+SG.room.route.reduce((a,p,i,r)=>a+Math.hypot(p[0]-r[(i+1)%r.length][0], p[1]-r[(i+1)%r.length][1]),0).toFixed(0)}; })()")
    check("scale: property about 26 x 26 m, ceilings 3.9 m, bot patrol tour > 200 m", sz["w"] > 25 and sz["d"] > 25 and sz["ceiling"] >= 3.8 and sz["route"] > 200, sz); results.append(("SIZE", True, sz))
    mv = pg.evaluate("""() => { const G=SG.game; const snap=()=>{ const m={}; SG.room.dyn.children.forEach(g=>{ if(!g.name) return; let s=''; g.traverse(o=>{ o.updateWorldMatrix(true,false); s+=Array.from(o.matrixWorld.elements).map(v=>v.toFixed(4)).join(); }); m[g.name]=(m[g.name]||'')+s; }); return m; }; G.step(0.1); const a=snap(); G.step(10); const b=snap(); return Object.keys(a).filter(k=>a[k]!==b[k]); }""")
    check("idle for 10 s: at least 10 kinds of things move by themselves", len(mv) >= 10, mv)
    ph = pg.evaluate("""() => { const G=SG.game, R=SG.room.raw, K=SG.room.knock, out={}; R.resetProps=SG.room.resetProps; const cup=K.find(k=>k.type==='茶杯'), roly=K.find(k=>k.type==='不倒翁'), blocks=K.filter(k=>k.type==='積木'&&k.y>2.6).sort((a,b)=>a.y-b.y);
      out.stackY0=blocks.map(b=>+b.y.toFixed(3)); const base=blocks[0]; R.kick(base.x, base.y+0.03, base.z, 1, 0, 3.0); for (let i=0;i<180;i++) R.stepProps(1/60, [], null); out.stackY1=blocks.map(b=>+b.y.toFixed(3));
      R.stepProps(1/60, [{x:cup.x-0.05, y:cup.y, z:cup.z, r:0.06, speed:3.5}], null); for (let i=0;i<120;i++) R.stepProps(1/60, [], null); out.cupLying=cup.lying; out.cupMoved=+Math.hypot(cup.x-cup.home[0], cup.z-cup.home[2]).toFixed(2);
      R.stepProps(1/60, [{x:roly.x-0.1, y:roly.y, z:roly.z, r:0.1, speed:2.5}], null); let mx=0; for (let i=0;i<40;i++){ R.stepProps(1/60, [], null); mx=Math.max(mx, Math.abs(roly.th)); } for (let i=0;i<400;i++) R.stepProps(1/60, [], null); out.rolyMax=+mx.toFixed(2); out.rolyEnd=+Math.abs(roly.th).toFixed(3); out.rolyLying=roly.lying;
      const a=K.find(k=>k.type==='毛線球'), b=K.filter(k=>k.type==='毛線球')[1]; b.x=a.x+0.4; b.z=a.z; b.vx=0; a.vx=2.0; a.vz=0; a.sleep=false; b.sleep=false; for (let i=0;i<60;i++) R.stepProps(1/60, [], null); out.pushed=+b.vx.toFixed(2)+ +(b.x-(a.home[0]+0.4)).toFixed(2);
      R.resetProps(); out.reset=blocks.map(b=>+b.y.toFixed(3)); return out; }""")
    check("prop physics: a stack falls when its base is knocked out, a cup tips over from an impulse, the roly-poly wobbles and rights itself, one ball pushes another, reset restores", ph["stackY1"][-1] < ph["stackY0"][-1] - 0.05 and ph["cupLying"] and ph["rolyMax"] > 0.15 and ph["rolyEnd"] < 0.05 and not ph["rolyLying"] and ph["pushed"] > 0.05 and ph["reset"] == ph["stackY0"], ph)
    tr = pg.evaluate("""() => { const R=SG.room.raw, T=SG.room.triggers, out={}; const sl=T.find(t=>t.kind==='slide'), dr=T.find(t=>t.kind==='drawer'), rk=T.find(t=>t.kind==='rock'&&t.axis==='x'), fl=T.find(t=>t.kind==='flap');
      for (let i=0;i<60;i++) R.stepTriggers(1/60, [{x:3.55,y:0,z:-3.0,speed:1}]); out.open=+sl.open.toFixed(2); for (let i=0;i<120;i++) R.stepTriggers(1/60, []); out.closed=+sl.open.toFixed(2);
      for (let i=0;i<60;i++) R.stepTriggers(1/60, [{x:dr.x,y:0,z:dr.z+0.2,speed:1}]); out.drawer=dr.out; for (let i=0;i<20;i++) R.stepTriggers(1/60, [{x:rk.x,y:0,z:rk.z,speed:2}]); out.rock=+Math.abs(rk.a).toFixed(3); for (let i=0;i<10;i++) R.stepTriggers(1/60, [{x:fl.x,y:0,z:fl.z+0.1,speed:1}]); out.flap=+Math.abs(fl.a).toFixed(3); return out; }""")
    check("things that react to you: sliding fusuma opens and closes, the ajar drawer can be pushed shut, rocking chair rocks, cat flap swings", tr["open"] > 0.9 and tr["closed"] < 0.1 and tr["drawer"] == 0 and tr["rock"] > 0.01 and tr["flap"] > 0.01, tr)
    cm = pg.evaluate("""() => { const G=SG.game; G.settings.mode='basic'; SG.RULES.solo.botCatsWhenCat=1; G.settings.dogs=1; G.start('cat','soba'); const out={white:[], camo:[]};
      for (const s of [[2.9,0.42,1.25,-2.0,'loaf'], [-2.4,0,-1.2,0.6,'sit'], [0.6,0,2.4,2.2,'curl']]) { G.me.c.fill([255,255,255],0.8,0); G.placeU('you', s[0], s[1], s[2], s[3]); G.setPose(s[4]); G.step(1.0); const c=G.me.c.center(); const eyes=[0.5,2.6,4.7].map(a=>new THREE.Vector3(c.x+Math.cos(a)*2.4, 0.62, c.z+Math.sin(a)*2.4));
        eyes.forEach(e=>out.white.push(+G.mismatch(G.me, e).m.toFixed(3))); G.camoAllSides(G.me, 1); eyes.forEach(e=>out.camo.push(+G.mismatch(G.me, e).m.toFixed(3))); }
      const mean=a=>+(a.reduce((x,y)=>x+y,0)/a.length).toFixed(3); out.better=out.camo.filter((v,i)=>v<out.white[i]).length; out.meanWhite=mean(out.white); out.meanCamo=mean(out.camo); return out; }""")
    check("bot camouflage sampled from 9 seeker directions: at 3 hiding spots x 3 viewpoints it is on average closer to the background than an unpainted white body (per-view count reported)", cm["meanCamo"] < cm["meanWhite"] * 0.8 and cm["better"] >= 6, cm)
    dc = pg.evaluate("""() => { const G=SG.game; G.toTitle(); G.settings.mode='infection'; SG.RULES.solo.botCatsWhenCat=9; G.settings.dogs=0; G.start('cat'); G.skip(); const out=[]; for (const yaw of [0, 1.6, 3.1, 4.7]) { G.cam.yaw=yaw; G.step(0.5); out.push(G.info().draw); } const t0=performance.now(); for (let i=0;i<5;i++) { SG.post.render(SG.scene, SG.camera, 0); SG.post.renderer.getContext().finish(); } return {draw:out, ents:G.ents.length, msFrameSoftwareGL:+((performance.now()-t0)/5).toFixed(0), size:[SG.post.width, SG.post.height]}; }""")
    check("draw calls in play (12 animals, whole house, 4 camera directions) stay under 300", max(dc["draw"]) < 300, dc); results.append(("DRAW", True, dc))
    au = pg.evaluate("SG.audio.selfTest()"); bad = [a for a in au if a["silent"] or a["clipped"] > 0]
    check("audio: %d synthesised sounds rendered offline, none silent, none clipped (not heard by a human)" % len(au), len(bad) == 0 and len(au) >= 30, bad if bad else "peak %.2f..%.2f" % (min(a["peak"] for a in au), max(a["peak"] for a in au)))
    (OUT / "audio.json").write_text(json.dumps(au, indent=1, ensure_ascii=False))

def main():
    which = sys.argv[1:] or ["world", "dog", "modes", "cat"]
    with sync_playwright() as p:
        b = p.chromium.launch(executable_path="/usr/bin/google-chrome", headless=True, args=ARGS)
        for w in which:
            pg = b.new_page(viewport={"width": W, "height": H}); errs = []
            pg.on("pageerror", lambda e: errs.append(str(e)))
            print("== " + w + " =="); t0 = time.time()
            try: {"cat": cat_run, "dog": dog_run, "world": world_run, "modes": modes_run}[w](pg)
            except Exception as e: check(w + " run completed without exception", False, repr(e)[:500])
            check(w + ": no uncaught page errors", len(errs) == 0, errs[:3]); print("(%.0f s)" % (time.time() - t0)); pg.close()
        b.close()
    bad = [r for r in results if not r[1]]
    print("\n%d checks, %d failed" % (len([r for r in results if r[0] not in ("DRAW", "STROKE_MS", "SIZE", "LOAD_MS")]), len(bad)))
    (OUT / "results.json").write_text(json.dumps(results, indent=1, ensure_ascii=False))
    sys.exit(1 if bad else 0)
main()
