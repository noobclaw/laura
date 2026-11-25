#!/usr/bin/env python3
"""Quick sanity of the flat bodies in the game (headless Chrome): cat walks, jumps, sticks to a wall, poses with amount, clone copies
pose + paint; dog walks, rears up (C), fires at a posed cat 3 m ahead and it vanishes; reveal shows it again. usage: bodycheck.py OUTDIR"""
import sys, json, pathlib
from playwright.sync_api import sync_playwright
ARGS = ["--no-sandbox", "--disable-gpu-sandbox", "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist", "--allow-file-access-from-files"]
out = pathlib.Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)
root = pathlib.Path(__file__).resolve().parent.parent / "index.html"; res = {}; fails = []
def check(name, ok, info=None):
    res[name] = [bool(ok), info]; print(("ok   " if ok else "FAIL ") + name, "" if info is None else json.dumps(info)[:300], flush=True)
    if not ok: fails.append(name)
with sync_playwright() as p:
    b = p.chromium.launch(executable_path="/usr/bin/google-chrome", headless=True, args=ARGS)
    pg = b.new_page(viewport={"width": 1280, "height": 720}); logs = []
    pg.on("pageerror", lambda e: logs.append("pageerror: " + str(e))); pg.on("console", lambda m: logs.append(m.text) if m.type == "error" else None)
    pg.goto(root.as_uri() + "?shot=room&nolock=1"); pg.wait_for_function("window.__ready===true || window.__error", timeout=180000)
    def shot(name): pg.evaluate("new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)))"); pg.screenshot(path=str(out / name))
    # ---- cat
    r = pg.evaluate("""(function(){var G=SG.game;G.start('cat','mochi');G.cam.yaw=Math.PI;var m=G.me,x0=m.x,z0=m.z;G.keys.w=true;G.step(1.5);G.keys.w=false;var d=Math.hypot(m.x-x0,m.z-z0),sp=m.speed;G.step(0.5);
      return {moved:+d.toFixed(2),speed:+sp.toFixed(2),rad:+m.rad.toFixed(3),halfLen:+m.halfLen.toFixed(3),h:+m.h.toFixed(3),size:m.c.measure().size.map(function(v){return +v.toFixed(3)}),y:+m.y.toFixed(3)};})()""")
    check("cat walks (W for 1.5 s)", r["moved"] > 2.0, r); shot("b1_cat_walk.png")
    r = pg.evaluate("""(function(){var G=SG.game,m=G.me,y0=m.y,top=0;window.dispatchEvent(new KeyboardEvent('keydown',{key:' '}));for(var i=0;i<60;i++){G.step(1/60);top=Math.max(top,m.y-y0);}window.dispatchEvent(new KeyboardEvent('keyup',{key:' '}));return {jump:+top.toFixed(2),landed:!m.air};})()""")
    check("cat jumps and lands", r["jump"] > 0.3 and r["landed"], r)
    r = pg.evaluate("""(function(){var G=SG.game,m=G.me,o=[];SG.POSE_LIST.forEach(function(p){G.setPose(p[0]);G.step(0.6);var s=m.c.measure().size;o.push(p[0]+':'+m.c.pose+':'+s.map(function(v){return v.toFixed(2)}).join('x'));});G.setPose('pancake');G.step(0.6);var a0=m.c.measure().size[1];G.setPoseAmount(1);G.step(0.6);var a1=m.c.measure().size[1];G.setPoseAmount(0);G.step(0.6);var a2=m.c.measure().size[1];return {poses:o,thick:[+a0.toFixed(3),+a1.toFixed(3),+a2.toFixed(3)]};})()""")
    check("all 17 pose names resolve and change the body; pose amount changes the pancake thickness", len(r["poses"]) == 17 and all(q.split(":")[0] == q.split(":")[1] for q in r["poses"]) and r["thick"][1] < r["thick"][2] - 0.02, r)
    # wheel: hold R, scroll, release
    pg.evaluate("SG.game.setPose('stand'); SG.game.step(0.3)"); pg.keyboard.down("r"); pg.mouse.move(640, 360); pg.mouse.move(520, 260, steps=4); shot("b2_wheel.png")
    hov = pg.evaluate("(function(){var h=document.querySelector('.pw2 .seg.hov');return h?{pose:h.dataset.pose,bg:getComputedStyle(h).backgroundColor}:null})()")
    pg.mouse.wheel(0, -100); pg.mouse.wheel(0, -100); pg.keyboard.up("r"); pg.evaluate("SG.game.step(0.5)")
    r = pg.evaluate("({pose:SG.game.me.c.pose, amt:SG.game.me.c.poseAmount, def:(SG.POSE_INFO[SG.game.me.c.pose]||{}).amount})")
    check("pose wheel: hover is blue, wheel scroll raises the amount, releasing R applies", hov and "47, 125, 225" in hov["bg"] and r["pose"] == hov["pose"] and r["amt"] > r["def"] + 0.15, [hov, r])
    # paint + clone
    r = pg.evaluate("""(function(){var G=SG.game,m=G.me;G.setPose('loaf');G.step(0.5);var c=m.c.center(new THREE.Vector3());c.y+=0.08;G.fx.attach(m.c);m.c.beginStroke();var n=G.fx.dab(m.c,c,0.07,[200,40,40],0.5,0,0.85,1);var st=m.c.endStroke();G.fx.flush(m.c);var pr=m.c.paintedRatio();G.setPoseAmount(0.9);G.step(0.4);G.decoySlots.forEach(function(s){s.cd=0});var ok=G.decoy();var d=G.decoys[0];var same=d&&d.c.pose===m.c.pose&&Math.abs(d.c.poseAmount-m.c.poseAmount)<1e-6&&d.c.paintedRatio()===pr&&d.c.earMode===m.c.earMode;if(st)m.c.undoStroke(st);return {texels:n,painted:+pr.toFixed(3),clone:!!ok,same:!!same,afterUndo:m.c.paintedRatio()};})()""")
    check("brush paints the new atlas, undo restores, a clone copies pose + amount + ears + paint", r["texels"] > 500 and r["painted"] > 0.005 and r["clone"] and r["same"] and r["afterUndo"] == 0, r); shot("b3_cat_clone.png")
    # wall cling (same spot as the playtest)
    r = pg.evaluate("""(function(){var G=SG.game,m=G.me;G.recallDecoys();G.setPose('stand');G.placeU('you',5.0,0,-1.9,-Math.PI/2);G.cam.yaw=Math.PI/2;G.cam.pitch=0.2;G.step(0.3);G.keys.w=true;G.step(0.15);window.dispatchEvent(new KeyboardEvent('keydown',{key:' '}));G.step(0.3);G.keys.w=false;G.keys[' ']=false;var n=m.cling&&m.cling.n;G.setPose('pancake');G.step(0.6);var up=new THREE.Vector3(0,1,0).applyQuaternion(m.c.root.quaternion);return {n:n,bodyUp:up.toArray().map(function(v){return +v.toFixed(2)}),thickAlongNormal:+m.c.measure().size[1].toFixed(3)};})()""")
    check("jump into a wall sticks; the mat lies flat on the wall (its up axis = the wall normal)", r["n"] == [1, 0, 0] and r["bodyUp"][0] > 0.99 and r["thickAlongNormal"] < 0.12, r); pg.evaluate("SG.game.cam.yaw=Math.PI/2+0.9;SG.game.cam.pitch=0.25;SG.game.step(0.5)"); shot("b4_cat_wall.png")
    # ---- dog
    r = pg.evaluate("""(function(){var G=SG.game;G.settings.mode='infection';G.start('dog','shiba');G.skip();G.step(0.2);var m=G.me,x0=m.x,z0=m.z;G.keys.w=true;G.step(1.5);G.keys.w=false;var d=Math.hypot(m.x-x0,m.z-z0);var e0=SG.camera.position.y-m.y;G.keys.c=true;G.step(0.8);var e1=SG.camera.position.y-m.y;G.keys.c=false;G.step(0.8);
      return {phase:G.state.phase,moved:+d.toFixed(2),eyeLow:+e0.toFixed(3),eyeRear:+e1.toFixed(3),rad:+m.rad.toFixed(3),halfLen:+m.halfLen.toFixed(3),h:+m.h.toFixed(3),vm:!!(G.vm&&G.vm.visible)};})()""")
    check("dog walks; eye is low; holding C rears up", r["moved"] > 2.0 and 0.12 < r["eyeLow"] < 0.3 and r["eyeRear"] > r["eyeLow"] + 0.15, r); shot("b5_dog_fp.png")
    r = pg.evaluate("""(function(){var G=SG.game,m=G.me,c=G.ent('cat0');G.place('you',-1.6*SG.WS,0,1.5*SG.WS,1.9);G.step(0.1);var rc=new THREE.Raycaster(),best=0;for(var yw=0;yw<6.28;yw+=0.2){rc.set(new THREE.Vector3(m.x,m.y+0.2,m.z),new THREE.Vector3(Math.sin(yw),-0.03,Math.cos(yw)));rc.far=30;var hh=rc.intersectObjects([SG.room.batched,SG.room.dyn],true)[0],dd=hh?hh.distance:30;if(dd>best&&dd<7){best=dd;m.yaw=yw;}}G.step(0.05);var fx=Math.sin(m.yaw),fz=Math.cos(m.yaw);c.cling=null;c.walk=null;G.place('cat0',m.x+fx*3,SG.room.groundAt(m.x+fx*3,m.z+fz*3,0.5,0),m.z+fz*3,0.7);c.c.setPose('pancake',0.75);c.c.settle();G.step(0.2);
      var ctr=c.c.center(new THREE.Vector3()),eye=SG.camera.position.clone();m.pitch=Math.asin((ctr.y-eye.y)/ctr.distanceTo(eye));G.step(0.1);window.__ev=[];SG.bus.on('found',function(d){window.__ev.push(d)});return {catAt:[+c.x.toFixed(2),+c.y.toFixed(2),+c.z.toFixed(2)],size:c.c.measure().size.map(function(v){return +v.toFixed(3)}),pitch:+m.pitch.toFixed(3)};})()""")
    shot("b6_dog_aim_pancake_3m.png")
    r2 = pg.evaluate("""(function(){var G=SG.game,m=G.me,c=G.ent('cat0');var d=new THREE.Vector3();SG.camera.getWorldDirection(d);var ok=G.fire(m,SG.camera.position.clone(),d);G.step(0.25);var mid={vis:c.c.root.visible,vanish:c.vanish>0};G.step(0.6);return {fired:ok,out:!!G.state.players.cat0.out,found:window.__ev.length,mid:mid,goneAfter:!c.c.root.visible,hunter:!!G.ent('cat0#h'),hunterAt:G.ent('cat0#h')?[+G.ent('cat0#h').x.toFixed(1),+G.ent('cat0#h').z.toFixed(1)]:null,spawn:G.dogSpawn.map(function(v){return +v.toFixed(1)})};})()""")
    check("a shot hits a pancake cat 3 m ahead; it vanishes within 0.85 s; in infection it comes back as a hunter at the entry point", r2["fired"] and r2["out"] and r2["found"] == 1 and r2["goneAfter"] and r2["hunter"] and abs(r2["hunterAt"][0] - r2["spawn"][0]) < 3 and abs(r2["hunterAt"][1] - r2["spawn"][1]) < 3, [r, r2]); shot("b7_after_shot.png")
    r = pg.evaluate("""(function(){var G=SG.game;G.dispatch?0:0;for(var i=0;i<400&&G.state.phase==='seek';i++){G.state.left=0.01;G.step(0.05);}G.step(0.5);var c=G.ent('cat0');return {phase:G.state.phase,catBack:c.c.root.visible,pose:c.c.pose,hull:!!(c.hull&&c.hull.visible),tags:document.querySelectorAll('.tag').length};})()""")
    check("answer check: the found cat is shown again in its pose, with outline and tags", r["phase"] == "reveal" and r["catBack"] and r["pose"] == "pancake" and r["hull"] and r["tags"] > 3, r); shot("b8_reveal.png")
    # ---- a found hider disappears: basic and double
    HELP = """window.__lane=function(m,c){var G=SG.game,rc=new THREE.Raycaster(),best=0,yaw=0;for(var yw=0;yw<6.28;yw+=0.2){rc.set(new THREE.Vector3(m.x,m.y+0.2,m.z),new THREE.Vector3(Math.sin(yw),-0.03,Math.cos(yw)));rc.far=30;var hh=rc.intersectObjects([SG.room.batched,SG.room.dyn],true)[0],dd=hh?hh.distance:30;if(dd>best&&dd<7){best=dd;yaw=yw;}}var fx=Math.sin(yaw),fz=Math.cos(yaw);c.cling=null;c.walk=null;G.place(c.id,m.x+fx*2.6,SG.room.groundAt(m.x+fx*2.6,m.z+fz*2.6,0.5,0),m.z+fz*2.6,0.7);return yaw;};
      window.__shoot=function(d,t){var G=SG.game,o=new THREE.Vector3(d.x,d.y+0.2,d.z),c=t.c.center(new THREE.Vector3());G.state.players[d.pid||d.id].lastShot=-9;return G.fire(d,o,c.sub(o).normalize());}; 1"""
    pg.evaluate(HELP)
    r = pg.evaluate("""(function(){var G=SG.game;G.settings.mode='basic';G.start('dog','shiba');G.skip();G.step(0.2);var m=G.me,c=G.ent('cat0');if(!m||!c)return {dbg:[!!m,!!c,G.mode,G.state&&G.state.phase,G.ents.map(function(e){return e.id}).join(',')]};G.place('you',-1.6*SG.WS,0,1.5*SG.WS,0);__lane(m,c);c.c.setPose('loaf');c.c.settle();G.step(0.2);var n0=G.ents.length;var ok=__shoot(m,c);G.step(0.8);
      return {fired:ok,out:!!G.state.players.cat0.out,gone:!c.c.root.visible,noHunter:G.ents.length===n0,banner:(document.querySelector('.banner')||{}).textContent||''};})()""")
    check("basic: the shot hider vanishes, nobody respawns, the hunter is told who was found", "dbg" not in r and r["fired"] and r["out"] and r["gone"] and r["noHunter"] and "找到" in r["banner"], r)
    r = pg.evaluate("""(function(){var G=SG.game;G.settings.mode='basic';G.start('cat','mochi');var m=G.me;G.setPose('loaf');G.step(0.4);G.decoy();m.x+=1.2;G.step(0.1);G.skip();G.step(0.3);var d=G.ents.filter(function(e){return e.team==='dog'})[0],cl=G.decoys[0];G.place(d.id,cl.x+1.5,cl.y,cl.z+1.5,0);G.step(0.05);var ok=__shoot(d,cl);G.step(0.9);
      var mid={out:!!m.out,spectator:!!G.fly,bodyGone:!m.c.root.visible,cloneGone:!cl.c.root.visible};for(var i=0;i<400&&G.state.phase==='seek';i++){G.state.left=0.01;G.step(0.05);}G.step(0.4);return {fired:ok,mid:mid,phase:G.state.phase,bodyBack:m.c.root.visible,cloneBack:cl.c.root.visible,pose:m.c.pose,links:G.marks.length};})()""")
    check("basic, you are the hider: a hit on your clone takes you out, body and clone vanish, you spectate; the answer check shows both again with a link line", r["fired"] and all(r["mid"].values()) and r["phase"] == "reveal" and r["bodyBack"] and r["cloneBack"] and r["pose"] == "loaf" and r["links"] >= 1, r)
    r = pg.evaluate("""(function(){var G=SG.game;G.settings.mode='double';G.start('cat','mochi');var m=G.me,body=G.ent('you');G.setPose('loaf');G.step(0.4);G.decoy();var cl=G.decoys[0];body.x+=1.2;G.step(0.1);G.skip();G.step(0.3);var x0=G.decoys.length;G.recallDecoys();var xBlocked=G.decoys.length===x0;
      var h=G.ents.filter(function(e){return e.team==='dog'&&e.pid!=='you'})[0];G.place(h.id,cl.x+1.5,cl.y,cl.z+1.5,0);G.step(0.05);var ok=__shoot(h,cl);G.step(0.9);
      return {phase:G.state.phase,xBlocked:xBlocked,fired:ok,foundBy:G.state.players[h.pid].found.slice(),hitCloneStays:cl.c.root.visible,otherBodyGone:!body.c.root.visible};})()""")
    check("double: X is blocked once you are a hunter; finding one of a player's bodies leaves that one and removes the others", r["xBlocked"] and r["fired"] and "you" in r["foundBy"] and r["hitCloneStays"] and r["otherBodyGone"], r)
    pg.evaluate("SG.game.settings.mode='infection'")
    res["errors"] = logs[:8]; check("no page errors", not logs, logs[:4])
    b.close()
print(json.dumps({"fails": fails}))
