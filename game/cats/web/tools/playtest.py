#!/usr/bin/env python3
"""Scripted playthrough with real mouse / keyboard events in headless Chrome (software WebGL).
The simulation is advanced with SG.game.step() so results do not depend on how slowly SwiftShader renders.
Writes screenshots to /tmp/webshots/test and prints one line per check. Exit code 1 if any check fails."""
import sys, json, time, pathlib, math
from playwright.sync_api import sync_playwright
ARGS = ["--no-sandbox", "--disable-gpu-sandbox", "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist", "--autoplay-policy=no-user-gesture-required"]
ROOT = pathlib.Path(__file__).resolve().parent.parent / "index.html"
OUT = pathlib.Path("/tmp/webshots/test"); OUT.mkdir(parents=True, exist_ok=True)
W, H = 1280, 720
results = []
def check(name, ok, detail=""):
    results.append((name, bool(ok), detail)); print(("PASS " if ok else "FAIL ") + name + ((" — " + str(detail)) if detail != "" else "")); sys.stdout.flush()

def boot(pg, query="q=low&nolock=1"):
    pg.goto(ROOT.as_uri() + "?" + query); pg.wait_for_function("window.__ready===true||window.__error", timeout=180000)
    err = pg.evaluate("window.__error||null"); assert not err, err
    pg.evaluate("""() => { const G=SG.game; G.paused=true; window.__ev=[]; SG.bus.on('*',(t,d)=>{ if(t!=='frame') __ev.push(Object.assign({t:t},d||{})); }); }""")
def info(pg): return pg.evaluate("SG.game.info()")
def step(pg, s): pg.evaluate("s=>SG.game.step(s)", s)
def events(pg, t=None): ev = pg.evaluate("__ev"); return [e for e in ev if t is None or e["t"] == t]
def catxy(pg): return pg.evaluate("""() => { const G=SG.game; SG.camera.updateMatrixWorld(true); const p=G.me.c.center().project(SG.camera); return [(p.x*.5+.5)*G.vw, (-p.y*.5+.5)*G.vh]; }""")
def proj(pg, x, y, z): return pg.evaluate("""(a) => { const G=SG.game; const p=new THREE.Vector3(a[0],a[1],a[2]).project(SG.camera); return [(p.x*.5+.5)*G.vw, (-p.y*.5+.5)*G.vh]; }""", [x, y, z])
def shot(pg, name): step(pg, 0.02); pg.screenshot(path=str(OUT / (name + ".png")))
def texhash(pg): return pg.evaluate("""() => { const a=SG.game.me.c.alb; let h=0; for(let i=0;i<a.length;i+=7) h=(h*31+a[i])|0; return h; }""")
def drag(pg, tr_sel, frac):
    b = pg.locator(tr_sel).bounding_box(); x = b["x"] + b["width"] * frac; y = b["y"] + b["height"] / 2
    pg.mouse.move(x, y); pg.mouse.down(); pg.mouse.move(x + 1, y); pg.mouse.up()

def cat_run(pg):
    boot(pg)
    pg.evaluate("() => { SG.RULES.round.seekSec = 45; }")  # numbers are data: shorten the seek phase for the test
    shot(pg, "01-title")
    pg.click("button[data-act=start-cat]"); i = info(pg)
    check("title: 當貓咪 starts a round in prep", i["mode"] == "play" and i["phase"] == "prep" and i["side"] == "cat", i["phase"])
    check("prep timer comes from rules.json (120)", abs(i["left"] - 120) < 0.5, i["left"])
    # --- move / jump
    x0, z0 = i["me"]["x"], i["me"]["z"]
    pg.keyboard.down("d"); step(pg, 1.0); pg.keyboard.up("d"); i = info(pg)
    d = math.hypot(i["me"]["x"] - x0, i["me"]["z"] - z0)
    check("WASD moves the cat (~2.2 m/s)", 1.8 < d < 2.4, round(d, 2)); check("guide advances after moving", i["guide"] >= 1, i["guide"])
    pg.keyboard.press("Space"); step(pg, 0.25); y1 = info(pg)["me"]["y"]; step(pg, 1.0); y2 = info(pg)["me"]["y"]
    check("Space jumps and the cat lands again", y1 > 0.5 and y2 < 0.05, (round(y1, 2), round(y2, 2)))
    # jump onto the kotatsu (0.38 m)
    pg.evaluate("() => SG.game.place('you', -0.55, 0, 1.0, Math.PI)"); pg.evaluate("() => { SG.game.cam.yaw = 0; }")
    pg.keyboard.press("Space"); pg.keyboard.down("w"); step(pg, 0.55); pg.keyboard.up("w"); step(pg, 0.8); i = info(pg)
    check("cat can jump onto the kotatsu top", 0.3 < i["me"]["y"] < 0.5, round(i["me"]["y"], 3))
    # bump a knockable (a mikan sits on the kotatsu)
    b0 = len(events(pg, "bump")); pg.keyboard.down("w"); step(pg, 0.5); pg.keyboard.up("w"); step(pg, 1.0)
    check("walking into small props knocks them (bump events)", len(events(pg, "bump")) > b0, len(events(pg, "bump")) - b0)
    # --- pose
    pg.evaluate("() => SG.game.place('you', 1.9, 0.012, 0.6, 2.3)"); pg.evaluate("() => { SG.game.cam.yaw = 2.5; SG.game.cam.pitch = 0.22; SG.game.cam.dist = 2.3; }"); step(pg, 0.5)
    pg.click(".poses button[data-pose=sit]"); step(pg, 0.8); i = info(pg)
    check("pose button sets the pose", i["me"]["pose"] == "sit", i["me"]["pose"])
    pg.keyboard.down("r"); step(pg, 0.05); vis = pg.locator(".pw").evaluate("e=>!e.classList.contains('hide')"); pg.hover(".pw button[data-pose=loaf]"); pg.keyboard.up("r"); step(pg, 0.6); i = info(pg)
    check("hold R opens the pose wheel, release picks the hovered pose", vis and i["me"]["pose"] == "loaf", i["me"]["pose"])
    pg.click(".poses button[data-pose=sit]"); step(pg, 0.8)
    # --- paint
    pg.keyboard.press("f"); step(pg, 0.6); i = info(pg)
    check("F opens paint mode and the panel", i["paintOn"] and pg.locator(".pp").evaluate("e=>!e.classList.contains('off')"))
    shot(pg, "02-paint-panel")
    # every control once
    pg.click(".swatches i[data-rgb='200,69,46']"); c = pg.evaluate("SG.game.paint.rgb"); check("swatch click sets the colour", c == [200, 69, 46], c)
    drag(pg, ".sl:has(span:text-is('G')) .tr", 0.9); c = pg.evaluate("SG.game.paint.rgb"); check("RGB slider changes the colour", c[1] > 215, c)
    pg.click(".tabs b[data-m=hsv]"); drag(pg, ".sl:has(span:text-is('H')) .tr", 0.6); c2 = pg.evaluate("SG.game.paint.rgb"); check("HSV tab + hue slider changes the colour", c2 != c, c2)
    pg.click(".tabs b[data-m=rgb]")
    wb = pg.locator(".wheel").bounding_box(); pg.mouse.move(wb["x"] + 110, wb["y"] + 40); pg.mouse.down(); pg.mouse.move(wb["x"] + 112, wb["y"] + 42); pg.mouse.up(); c3 = pg.evaluate("SG.game.paint.rgb"); check("colour wheel picks hue/saturation", c3 != c2, c3)
    vb = pg.locator(".vbar").bounding_box(); pg.mouse.move(vb["x"] + 10, vb["y"] + vb["height"] * 0.7); pg.mouse.down(); pg.mouse.move(vb["x"] + 10, vb["y"] + vb["height"] * 0.72); pg.mouse.up(); c4 = pg.evaluate("SG.game.paint.rgb"); check("value bar darkens the colour", max(c4) < max(c3), c4)
    pg.fill(".prev input", "#2F4B7C"); c5 = pg.evaluate("SG.game.paint.rgb"); check("hex field sets the colour", c5 == [47, 75, 124], c5)
    drag(pg, ".sl[data-s=metal] .tr", 0.8); drag(pg, ".sl[data-s=rough] .tr", 0.25); drag(pg, ".sl[data-s=size] .tr", 0.37); p = pg.evaluate("SG.game.paint")
    check("metallic / roughness / brush-size sliders", p["metal"] > 0.7 and p["rough"] < 0.35 and 0.07 < p["size"] < 0.09, (round(p["metal"], 2), round(p["rough"], 2), round(p["size"], 3)))
    pg.click(".tools button[data-tool=hard]"); h1 = pg.evaluate("SG.game.paint.hard"); pg.click(".tools button[data-tool=hard]"); check("hard/soft edge toggle", h1 is False and pg.evaluate("SG.game.paint.hard") is True)
    drag(pg, ".sl[data-s=metal] .tr", 0.0); drag(pg, ".sl[data-s=rough] .tr", 0.8)
    # stroke with the real mouse
    h0 = texhash(pg); r0 = info(pg)["me"]["painted"]; x, y = catxy(pg)
    pg.mouse.move(x - 30, y + 10); pg.mouse.down()
    for k in range(8): pg.mouse.move(x - 30 + k * 8, y + 10 + (k % 2) * 6)
    pg.mouse.up(); i = info(pg)
    check("left-drag on the body paints (texture changes, 1 undo step)", texhash(pg) != h0 and i["me"]["painted"] > r0 and i["undo"] == 1, round(i["me"]["painted"], 3))
    shot(pg, "03-stroke")
    # geometry of the 3D brush: all changed texels lie inside the brush sphere; the far side stays untouched
    g = pg.evaluate("""() => { const G=SG.game, c=G.me.c; const before=c.alb.slice(); const ctr=c.center(); const ray=new THREE.Raycaster(SG.camera.position.clone(), ctr.clone().sub(SG.camera.position).normalize()); const hit=c.raycast(ray); const R=0.05;
      c.paint(hit.point, R, [10,200,90], 0.8, 0, 0.8); let changed=0, far=0, maxd=0, back=0, tot=0; c.eachTexel((x,y,z,n,i,j)=>{ tot++; return null; });
      const A=c.A; c.parts.forEach(p=>{ const e=p.mesh.matrixWorld.elements; for(let j=0;j<p.th;j++) for(let i=0;i<p.tw;i++){ const o=((p.ry+j)*A+p.rx+i)*4; const k=(j*p.tw+i)*3; const x=p.tp[k],y=p.tp[k+1],z=p.tp[k+2]; const wx=e[0]*x+e[4]*y+e[8]*z+e[12], wy=e[1]*x+e[5]*y+e[9]*z+e[13], wz=e[2]*x+e[6]*y+e[10]*z+e[14]; const d=Math.hypot(wx-hit.point.x,wy-hit.point.y,wz-hit.point.z); const ch=before[o]!==c.alb[o]||before[o+1]!==c.alb[o+1]||before[o+2]!==c.alb[o+2]; if(ch){changed++; if(d>maxd) maxd=d;} else if(d>R*1.01) far++; } });
      c.alb.set(before); c.texA.needsUpdate=true; return {changed, maxd, far, R}; }""")
    check("3D brush: only texels inside the brush sphere change; the rest (incl. far side) untouched", g["changed"] > 50 and g["maxd"] <= g["R"] * 1.04 and g["far"] > 10000, g)
    # paint survives every pose
    hp = texhash(pg); ok = True
    for pose in ["loaf", "stretch", "side", "curl", "belly", "hind", "arch", "stand", "sit"]:
        pg.evaluate("p=>SG.game.setPose(p)", pose); step(pg, 0.5); ok = ok and texhash(pg) == hp
        if pose in ("curl", "hind"): shot(pg, "04-pose-" + pose)
    check("paint texture is identical after cycling all 8 poses", ok)
    pg.evaluate("() => SG.game.setPaintMode(true)"); step(pg, 0.3)
    # eyedropper (Alt+click) on the mustard beanbag: turn the camera so the beanbag is on screen and clear of the panels
    bx = by = None
    for yaw in (-1.7, -2.6, -1.4, -2.9):
        pg.evaluate("y => { SG.game.cam.yaw = y; SG.game.cam.pitch = 0.3; }", yaw); step(pg, 0.6); bx, by = proj(pg, 2.9, 0.40, 1.25)
        top = pg.evaluate("(a) => { const G=SG.game, r=new THREE.Raycaster(); r.setFromCamera(new THREE.Vector2(a[0]/G.vw*2-1, -(a[1]/G.vh)*2+1), SG.camera); const h=r.intersectObjects([SG.room.batched, SG.room.dyn].concat(G.me.c.meshes), true)[0]; return h ? [h.point.x, h.point.y, h.point.z] : null; }", [bx, by])
        if 300 < bx < 930 and 140 < by < 520 and top and math.hypot(top[0] - 2.9, top[2] - 1.25) < 0.45 and top[1] > 0.15: break
    pg.keyboard.down("Alt"); pg.mouse.click(bx, by); pg.keyboard.up("Alt"); c = pg.evaluate("SG.game.paint.rgb")
    check("Alt+click picks the surface colour of the beanbag (mustard ~217,169,58)", abs(c[0] - 217) < 30 and abs(c[1] - 169) < 30 and abs(c[2] - 58) < 40, c)
    check("picked colour lands in the recent swatches", pg.locator(".swatches i[data-rgb='%d,%d,%d']" % tuple(c)).count() >= 1)
    shot(pg, "03b-eyedropper")
    kx, ky = pg.evaluate("""() => { const G=SG.game, r=new THREE.Raycaster(); for (let y=560; y>200; y-=40) for (let x=330; x<920; x+=40) { if (document.elementFromPoint(x,y).id!=='gl') continue; r.setFromCamera(new THREE.Vector2(x/G.vw*2-1, -(y/G.vh)*2+1), SG.camera); const h=r.intersectObjects([SG.room.batched, SG.room.dyn].concat(G.me.c.meshes), true)[0]; if (h && h.point.y<0.005 && h.object.material.name==='twoodHoney') return [x,y]; } return [640,560]; }""")
    pg.click(".tools button[data-tool=pick]"); pg.mouse.click(kx, ky); c2 = pg.evaluate("SG.game.paint.rgb")
    check("eyedropper tool button picks the wooden floor (honey ~200,155,94) and returns to the brush", abs(c2[0] - 200) < 45 and abs(c2[1] - 155) < 45 and abs(c2[2] - 94) < 45 and pg.evaluate("SG.game.paint.tool") == "brush", c2)
    pg.evaluate("() => { SG.game.cam.yaw = 2.5; SG.game.cam.pitch = 0.22; }"); step(pg, 0.6)
    pg.evaluate("() => SG.ui.refreshSug()"); sg = pg.evaluate("SG.game.suggest()"); pg.locator(".sug div").nth(0).click(); c3 = pg.evaluate("SG.game.paint.rgb")
    check("environment suggestions: 4 colours, clicking one selects it", len(sg) == 4 and c3 == sg[0], sg)
    # fill + undo
    hf = texhash(pg); pg.click(".tools button[data-tool=fill]"); i = info(pg); check("fill paints the whole body", i["me"]["painted"] > 0.95 and texhash(pg) != hf, round(i["me"]["painted"], 3))
    pg.click(".tools button[data-tool=undo]"); check("undo restores the texture before the fill", texhash(pg) == hf)
    # 20+ undo steps
    pg.evaluate("() => { while (SG.game.undo()) {} }"); base = texhash(pg); x, y = catxy(pg); hashes = [base]
    for k in range(22):
        pg.evaluate("k => { SG.game.paint.rgb = [k*11, 255-k*9, 60+k*5]; SG.game.paint.size = 0.03; }", k)
        pg.mouse.move(x - 40 + (k % 6) * 14, y - 20 + (k // 6) * 14); pg.mouse.down(); pg.mouse.move(x - 38 + (k % 6) * 14, y - 18 + (k // 6) * 14); pg.mouse.up(); hashes.append(texhash(pg))
    n = info(pg)["undo"]; ok = n >= 20
    for k in range(20):
        pg.keyboard.press("Control+z"); ok = ok and texhash(pg) == hashes[len(hashes) - 2 - k]
    check("Ctrl+Z walks back 20 strokes one by one", ok, n)
    # --- wall cling
    pg.keyboard.press("f"); pg.evaluate("() => { SG.game.place('you', 3.8, 0, 0.47, Math.PI/2); SG.game.cam.yaw = -Math.PI/2; SG.game.setPose('stand'); }"); step(pg, 0.3)
    pg.keyboard.down("w"); pg.keyboard.press("Space"); step(pg, 0.35); i = info(pg); yc = i["me"]["y"]; cl = i["me"]["cling"]
    shot(pg, "04b-wall-cling"); step(pg, 1.0); y_up = info(pg)["me"]["y"]; pg.keyboard.up("w"); pg.keyboard.press("Shift"); step(pg, 1.2); i = info(pg)
    check("jumping at a wall clings; W climbs ~1 m/s; Shift lets go", cl and 0.8 < y_up - yc < 1.2 and not i["me"]["cling"] and i["me"]["y"] < 0.05, (cl, round(y_up - yc, 2), round(i["me"]["y"], 2)))
    # --- ride the robot vacuum
    r = pg.evaluate("""() => { const G=SG.game; G.place('you', SG.room.vac.x, 0.5, SG.room.vac.z, 0); G.step(1.0); const a=[G.me.x,G.me.z,G.me.y]; G.step(4.0); return {a, b:[G.me.x,G.me.z,G.me.y], vac:[SG.room.vac.x, SG.room.vac.z]}; }""")
    moved = math.hypot(r["b"][0] - r["a"][0], r["b"][1] - r["a"][1]); off = math.hypot(r["b"][0] - r["vac"][0], r["b"][1] - r["vac"][1])
    check("cat rides the robot vacuum (carried along, stays on top)", moved > 0.8 and off < 0.1 and abs(r["b"][2] - 0.09) < 0.02, (round(moved, 2), round(off, 3), round(r["b"][2], 3)))
    # --- meow + decoy
    pg.keyboard.press("1"); check("1 = meow event", len(events(pg, "meow")) == 1)
    pg.evaluate("() => { SG.game.place('you', 2.9, 0.42, 1.25, -2.0); SG.game.setPose('loaf'); }"); step(pg, 0.8)
    pg.keyboard.press("q"); pg.keyboard.press("q"); i = info(pg); check("Q drops a decoy; second one is refused during the 30 s cooldown", i["decoys"] == 1 and len(events(pg, "denied")) == 1, i["decoys"])
    pg.keyboard.press("x"); check("X recalls decoys", info(pg)["decoys"] == 0)
    # posed bots must be perfectly still (GDD hider-cat)
    still = pg.evaluate("""() => { const G=SG.game, c=G.ent('cat0').c; const snap=()=>c.meshes.map(m=>Array.from(m.matrixWorld.elements).join()).join('|'); const a=snap(); G.step(1.0); return a===snap() && c.pose!=='stand'; }""")
    check("a posed cat that is not yours is perfectly still for 60 frames", still)
    # --- seek: an unpainted white cat in the open gets found
    pg.evaluate("() => { const G=SG.game; G.me.c.fill([255,255,255],0.8,0); G.place('you', -1.2, 0, 1.6, 0); G.setPose('sit'); }"); step(pg, 0.5)
    pg.keyboard.press("Enter"); i = info(pg); check("Enter (ready) skips prep -> seek", i["phase"] == "seek", i["phase"])
    shot(pg, "05-seek-start")
    t = 0
    while t < 44 and not info(pg)["me"]["out"]: step(pg, 1.0); t += 1
    i = info(pg); hit = [e for e in events(pg, "hit") if e.get("cat") == "you"]
    check("bot dog finds an unpainted cat sitting in the open and shoots it", i["me"]["out"] and len(hit) == 1, "after %d s, suspicion events %d" % (t, len(events(pg, "suspicion"))))
    shot(pg, "06-caught")
    while info(pg)["phase"] == "seek" and t < 80: step(pg, 2.0); t += 2
    i = info(pg); check("seek ends -> reveal with a winner", i["phase"] == "reveal" and i["winner"] in ("cats", "dogs"), (i["winner"], i["reason"]))
    step(pg, 1.5); shot(pg, "07-reveal-cat-side")
    check("reveal shows a tag for every animal and the result panel", pg.locator(".tag").count() == 5 and pg.locator(".result").is_visible(), pg.locator(".tag").count())
    glow = pg.evaluate("""() => SG.game.ents.filter(e=>e.team==='cat').map(e=>({out:SG.game.state.players[e.id].out, r:e.c.glow.value.r, b:e.c.glow.value.b}))""")
    check("reveal glow: found = blue, not found = red, matching the rules state", all((g["b"] > g["r"]) == g["out"] for g in glow), glow)

def dog_goto_view(pg, cid):
    """test scaffolding: stand the dog somewhere with a clear line to the cat (a player would walk there)"""
    return pg.evaluate("""id => { const G=SG.game, m=G.me, c=G.ent(id).c.center(), eh=SG.RULES.dog.eyeHeight[m.breed], ray=new THREE.Raycaster();
      for (let r=1.2; r<3.6; r+=0.4) for (let a=0; a<6.28; a+=0.35) { const x=c.x+Math.cos(a)*r, z=c.z+Math.sin(a)*r; if (SG.room.blocked(x,z,0,0.25,0.14,0.5)) continue;
        const o=new THREE.Vector3(x,eh,z), d=c.clone().sub(o), L=d.length(); d.normalize(); ray.set(o,d); ray.far=L; const h=ray.intersectObjects([SG.room.batched, SG.room.dyn], true)[0];
        if (!h || h.distance > L-0.15) { G.place('you', x, 0, z, 0); return true; } } return false; }""", cid)

def dog_clear_spot(pg):
    """test scaffolding: stand somewhere at least 1.5 m from every cat and look straight up, so a shot is a guaranteed miss"""
    pg.evaluate("""() => { const G=SG.game; for (const p of [[0.5,1.6],[1.2,-1.3],[-2.6,0.2],[2.2,-1.9],[-1.6,1.9],[3.0,0.9],[0.9,0.6]]) { if (SG.room.blocked(p[0],p[1],0,0.25,0.14,0.5)) continue; if (G.ents.every(e=>e.team!=='cat'||Math.hypot(e.x-p[0],e.z-p[1])>1.5)) { G.place('you',p[0],0,p[1],Math.PI); break; } } G.me.yaw=Math.PI; G.me.pitch=1.2; }""")

def dog_aim(pg, cid):
    pg.evaluate("""id => { const G=SG.game, m=G.me, c=G.ent(id).c.center(); const eh=SG.RULES.dog.eyeHeight[m.breed]; const dx=c.x-m.x, dy=c.y-(m.y+eh), dz=c.z-m.z; m.yaw=Math.atan2(dx,dz); m.pitch=Math.atan2(dy,Math.hypot(dx,dz)); }""", cid)

def dog_run(pg):
    boot(pg); pg.click(".breeds.d b[data-breed=corgi]"); pg.click("button[data-act=start-dog]"); i = info(pg)
    check("當狗狗 starts as a dog waiting in the genkan", i["side"] == "dog" and i["phase"] == "prep" and pg.locator(".wait").is_visible())
    pg.keyboard.press("Enter"); i = info(pg); check("Enter goes in -> seek, 5 balls", i["phase"] == "seek" and i["players"]["you"]["balls"] == 5)
    x0 = i["me"]["x"]; pg.keyboard.down("w"); step(pg, 1.0); pg.keyboard.up("w"); d = info(pg)["me"]["x"] - x0; check("dog walks at ~3 m/s", 2.5 < d < 3.2, round(d, 2))
    pg.keyboard.down("ArrowLeft"); step(pg, 0.3); pg.keyboard.up("ArrowLeft"); shot(pg, "10-dog-first-person")
    # shoot a wall: 5 -> 4, cooldown blocks the second click
    dog_clear_spot(pg); step(pg, 0.1)
    pg.mouse.click(640, 360); b1 = info(pg)["players"]["you"]["balls"]; pg.mouse.click(640, 360); step(pg, 0.5); pg.mouse.click(640, 360); b2 = info(pg)["players"]["you"]["balls"]
    check("miss: 5 -> 4; clicks inside 1.5 s do nothing", b1 == 4 and b2 == 4, (b1, b2)); check("the ball is a real projectile that stays in the room", info(pg)["balls"] == 1)
    step(pg, 1.2)
    # hit a still cat: 4 -> 5
    dog_goto_view(pg, "cat0"); dog_aim(pg, "cat0"); step(pg, 0.1); shot(pg, "11-dog-aim"); pg.mouse.click(640, 360); step(pg, 0.6); i = info(pg)
    check("hit a still cat: +1 ball, cat is out", i["players"]["you"]["balls"] == 5 and i["players"]["cat0"]["out"], i["players"]["you"]["balls"]); shot(pg, "12-dog-hit")
    step(pg, 1.5)
    # 見落とし score: a cat in front for 10 s scores, a cat behind does not
    s = pg.evaluate("""() => { const G=SG.game; const a=G.ent('cat1'), b=G.ent('cat2'); G.place('cat1', 1.2, 0, -1.6, 0); G.place('cat2', 1.2, 0, 2.2, 0); G.place('you', 1.2, 0, 1.4, Math.PI); G.me.yaw=Math.PI; G.me.pitch=0; const s0=[G.state.players.cat1.score, G.state.players.cat2.score]; G.step(10); return [G.state.players.cat1.score-s0[0], G.state.players.cat2.score-s0[1]]; }""")
    check("'under your nose' score: cat 3 m in front for 10 s scores, cat behind scores 0", s[0] > 0 and s[1] == 0, s)
    # miss a fleeing cat: free
    b0 = info(pg)["players"]["you"]["balls"]
    pg.evaluate("() => { const G=SG.game; const c=G.ent('cat1'); c.speed=2.0; const o=new THREE.Vector3(G.me.x,0.5,G.me.z); const d=c.c.center().sub(o).normalize(); d.y+=0.22; d.normalize(); G.fire(G.me,o,d); c.speed=0; }")
    i = info(pg); check("missing a running cat costs no ball", i["players"]["you"]["balls"] == b0 and events(pg, "miss")[-1].get("free") is True, i["players"]["you"]["balls"]); step(pg, 1.6)
    # end condition: all dogs out of balls -> cats win immediately
    dog_clear_spot(pg); n = 0
    while info(pg)["phase"] == "seek" and n < 12: pg.keyboard.press("Space"); step(pg, 1.6); n += 1
    i = info(pg); check("end: balls run out -> reveal, cats win (no-balls)", i["phase"] == "reveal" and i["winner"] == "cats" and i["reason"] == "no-balls", (i["winner"], i["reason"], n))
    step(pg, 2.0); shot(pg, "13-reveal-dog-side"); check("balls stay where they landed for the reveal", info(pg)["balls"] >= 5, info(pg)["balls"])
    pg.click(".result .btn:text('再來一局')"); pg.keyboard.press("Enter"); i = info(pg); check("再來一局 starts a fresh round", i["phase"] == "seek" and i["players"]["you"]["balls"] == 5)
    # end condition: all cats found -> dogs win
    for cid in ["cat0", "cat1", "cat2", "cat3"]:
        dog_goto_view(pg, cid); dog_aim(pg, cid); step(pg, 0.05); pg.mouse.click(640, 360); step(pg, 1.6)
    i = info(pg); check("end: every cat found -> reveal, dogs win (all-found)", i["phase"] == "reveal" and i["winner"] == "dogs" and i["reason"] == "all-found", (i["winner"], i["reason"], [p["out"] for k, p in i["players"].items() if k != "you"]))
    step(pg, 1.0); shot(pg, "14-reveal-dogs-win")
    pg.keyboard.press("Enter"); check("Enter in reveal returns to the title", info(pg)["mode"] == "title")
    # end condition: time runs out -> cats win
    pg.evaluate("() => { SG.RULES.round.seekSec = 6; }"); pg.click("button[data-act=start-dog]"); pg.keyboard.press("Enter"); step(pg, 6.5); i = info(pg)
    check("end: time up with cats left -> reveal, cats win (time)", i["phase"] == "reveal" and i["winner"] == "cats" and i["reason"] == "time", (i["winner"], i["reason"]))
    # decoy rule: hitting a decoy takes the owner out (cat side, bot dog fires at the decoy)
    pg.evaluate("() => SG.game.toTitle()"); pg.click("button[data-act=start-cat]")
    r = pg.evaluate("""() => { const G=SG.game; G.place('you', 2.9, 0.42, 1.25, -2.0); G.setPose('loaf'); G.step(0.5); G.decoy(); G.place('you', -3.0, 0, -2.0, 0); G.skip(); G.step(0.1); const d=G.ent('dog0'), dc=G.decoys[0]; const o=new THREE.Vector3(0.5,0.6,1.0); const ok=G.fire(d,o,dc.c.center().sub(o).normalize()); return {ok, out:G.state.players.you.out, vis:dc.c.root.visible}; }""")
    check("a ball that hits a decoy takes the real cat out", r["ok"] and r["out"] and not r["vis"], r)

def world_run(pg):
    boot(pg, "q=low&shot=room")
    st = pg.evaluate("SG.room.stats"); check("room inventory: >= 60 kinds, >= 250 items (counted by code)", st["types"] >= 60 and st["items"] >= 250, st)
    mv = pg.evaluate("""() => { const G=SG.game; const snap=()=>{ const m={}; SG.room.dyn.children.forEach(g=>{ if(!g.name) return; let s=''; g.traverse(o=>{ o.updateWorldMatrix(true,false); s+=Array.from(o.matrixWorld.elements).map(v=>v.toFixed(4)).join(); }); m[g.name]=(m[g.name]||'')+s; }); m['蒸氣(著色器)']=String(SG.room.steam.uniforms.uAmt.value.toFixed(3)); return m; }; G.step(0.1); const a=snap(); G.step(10); const b=snap(); return Object.keys(a).filter(k=>a[k]!==b[k]); }""")
    check("idle for 10 s: at least 5 kinds of things move", len(mv) >= 5, mv)
    cm = pg.evaluate("""() => { const G=SG.game; G.start('cat','mochi'); G.place('you', 2.9, 0.42, 1.25, -2.0); G.setPose('loaf'); G.step(1.0); const eye=new THREE.Vector3(1.0,0.6,-0.4), eye2=new THREE.Vector3(0.3,0.6,0.9);
      const w=G.mismatch(G.me, eye).m, w2=G.mismatch(G.me, eye2).m; G.autoCamo(G.me, 1, eye); const c=G.mismatch(G.me, eye).m, c2=G.mismatch(G.me, eye2).m; return {white:+w.toFixed(3), camo:+c.toFixed(3), whiteOtherAngle:+w2.toFixed(3), camoOtherAngle:+c2.toFixed(3), floor:SG.RULES.bot.dogMismatchFloor}; }""")
    check("dog vision: from the viewpoint it was painted for, a camouflaged cat drops below the bot's suspicion floor while a white one stays above it", cm["camo"] < cm["white"] * 0.6 and cm["camo"] <= cm["floor"] and cm["white"] > cm["floor"] * 1.5, cm)
    pg.evaluate("() => { SG.game.toTitle(); SG.game.mode='view'; SG.game.ents.slice().forEach(()=>{}); }")
    i = pg.evaluate("SG.game.info()"); print("INFO draw calls %d, triangles %d (software renderer, no fps claim)" % (i["draw"], i["tris"]))
    au = pg.evaluate("SG.audio.selfTest()")
    bad = [a for a in au if a["silent"] or a["clipped"] > 0]
    check("audio: %d synthesised sounds rendered offline, none silent, none clipped (not heard by a human)" % len(au), len(bad) == 0 and len(au) >= 20, bad if bad else "peak %.2f..%.2f" % (min(a["peak"] for a in au), max(a["peak"] for a in au)))
    (OUT / "audio.json").write_text(json.dumps(au, indent=1, ensure_ascii=False))

def main():
    which = sys.argv[1:] or ["cat", "dog", "world"]
    with sync_playwright() as p:
        b = p.chromium.launch(executable_path="/usr/bin/google-chrome", headless=True, args=ARGS)
        for w in which:
            pg = b.new_page(viewport={"width": W, "height": H}); errs = []
            pg.on("pageerror", lambda e: errs.append(str(e)))
            print("== " + w + " =="); t0 = time.time()
            try: {"cat": cat_run, "dog": dog_run, "world": world_run}[w](pg)
            except Exception as e: check(w + " run completed without exception", False, repr(e)[:400])
            check(w + ": no uncaught page errors", len(errs) == 0, errs[:3]); print("(%.0f s)" % (time.time() - t0)); pg.close()
        b.close()
    bad = [r for r in results if not r[1]]
    print("\n%d checks, %d failed" % (len(results), len(bad)))
    (OUT / "results.json").write_text(json.dumps(results, indent=1, ensure_ascii=False))
    sys.exit(1 if bad else 0)
main()
