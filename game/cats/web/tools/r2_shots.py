#!/usr/bin/env python3
"""Evidence screenshots for round 2/3 into /tmp/webshots/r2 (headless Chrome, software WebGL)."""
import pathlib, base64
from playwright.sync_api import sync_playwright
ARGS = ["--no-sandbox", "--disable-gpu-sandbox", "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"]
ROOT = pathlib.Path(__file__).resolve().parent.parent / "index.html"; OUT = pathlib.Path("/tmp/webshots/r2"); OUT.mkdir(parents=True, exist_ok=True)
ROOMS = {"room-living": [1.5, 1.7, 2.2, -1.5, 0.6, -1.5, 70], "room-kitchen": [1.9, 1.6, -3.9, -0.8, 0.7, -5.6, 72], "room-genkan": [-4.9, 1.6, 2.4, -6.0, 0.9, -1.5, 72], "room-loft": [-3.0, 3.9, -4.0, -5.6, 3.0, -5.6, 75], "room-tatami": [3.0, 1.7, -7.0, 5.6, 0.6, -4.4, 75],
         "room-garden": [0.5, 1.8, 3.4, 0.5, -0.2, 7.5, 75], "room-study": [4.9, 1.9, -0.9, 7.6, 0.9, -3.0, 78], "room-bath": [4.9, 1.9, -0.2, 7.6, 0.4, 2.0, 78], "room-storehouse": [-6.9, 1.5, -7.2, -3.6, 0.8, -4.4, 75], "room-alley-west": [-7.7, 1.4, 2.0, -7.7, 0.6, -3.5, 70], "room-alley-north": [8.2, 1.5, -8.2, 2.0, 0.5, -8.1, 70]}
TOP = """() => { const b=SG.room.bounds, W=1000, cx=(b.x0+b.x1)/2, cz=(b.z0+b.z1)/2, hw=(b.x1-b.x0)/2+0.6, hd=(b.z1-b.z0)/2+0.6, H=Math.round(W*hd/hw);
 const cam=new THREE.OrthographicCamera(-hw,hw,hd,-hd,0.01,60); cam.position.set(cx,2.2*SG.WS,cz); cam.up.set(0,0,-1); cam.lookAt(cx,0,cz); cam.updateMatrixWorld(true);
 const px=SG.post.renderAlbedo(SG.scene, cam, W, H); const cv=document.createElement('canvas'); cv.width=W; cv.height=H+40; const x=cv.getContext('2d'); const id=x.createImageData(W,H);
 for(let j=0;j<H;j++) for(let i=0;i<W;i++){ const s=((H-1-j)*W+i)*4, d=(j*W+i)*4; id.data[d]=px[s]; id.data[d+1]=px[s+1]; id.data[d+2]=px[s+2]; id.data[d+3]=255; } x.fillStyle='#fff'; x.fillRect(0,0,W,H+40); x.putImageData(id,0,0);
 x.font='14px sans-serif'; x.fillStyle='#000'; x.strokeStyle='rgba(0,0,0,.3)'; for (let m=Math.ceil((cx-hw)/2)*2; m<cx+hw; m+=2){ const X=(m-(cx-hw))/(2*hw)*W; x.beginPath(); x.moveTo(X,0); x.lineTo(X,H); x.stroke(); x.fillText(m+' m',X+2,13); } for (let m=Math.ceil((cz-hd)/2)*2; m<cz+hd; m+=2){ const Y=(m-(cz-hd))/(2*hd)*H; x.beginPath(); x.moveTo(0,Y); x.lineTo(W,Y); x.stroke(); x.fillText(m+' m',2,Y-2); }
 x.fillText('貓屋敷 top-down (ceilings cut at 3.3 m). Grid 2 m. Property '+(b.x1-b.x0).toFixed(1)+' x '+(b.z1-b.z0).toFixed(1)+' m, ceilings '+(SG.room.K.H*SG.WS).toFixed(1)+' m, living room 13.5 x 9.1 m, x1.0 cat about 0.3 m at the shoulder.', 8, H+25); return cv.toDataURL(); }"""
with sync_playwright() as p:
    b = p.chromium.launch(executable_path="/usr/bin/google-chrome", headless=True, args=ARGS)
    pg = b.new_page(viewport={"width": 1280, "height": 720}); pg.goto(ROOT.as_uri() + "?nolock=1&shot=room"); pg.wait_for_function("window.__ready===true||window.__error", timeout=240000); pg.evaluate("SG.game.paused=true")
    def snap(n): pg.evaluate("SG.game.step(0.05)"); pg.screenshot(path=str(OUT / (n + ".png"))); print(n)
    open(OUT / "map-topdown.png", "wb").write(base64.b64decode(pg.evaluate(TOP).split(",")[1])); print("map-topdown")
    import sys
    for n, c in ({} if "staged" in sys.argv else ROOMS).items():
        pg.evaluate("(c) => { const w=SG.WS; SG.game.cam.free={p:new THREE.Vector3(c[0]*w,c[1]*w,c[2]*w), t:new THREE.Vector3(c[3]*w,c[4]*w,c[5]*w), fov:c[6]}; SG.game.step(0.3); }", c); snap(n)
    # proportions: a x1.0 cat, a dog, a doorway and a table in one frame
    pg.evaluate("""() => { const G=SG.game, w=SG.WS; G.settings.mode='basic'; SG.RULES.solo.botCatsWhenCat=3; G.settings.dogs=1; G.start('cat','mochi'); G.placeU('you', -3.3, 0, 1.3, 1.2); G.placeU('dog0', -3.9, 0, 0.75, 1.2); G.ents.forEach(e=>e.c.root.visible = e.id==='you'||e.id==='dog0'); G.cam.free={p:new THREE.Vector3(-1.2*w,0.75*w,1.9*w), t:new THREE.Vector3(-4.5*w,0.75*w,1.2*w), fov:62}; G.step(0.6); G.ents.forEach(e=>e.c.root.visible = e.id==='you'||e.id==='dog0'); }"""); snap("proportions-cat-dog-doorway")
    # three cats stuck in odd places in the study: high on a wall, on the ceiling, on a beam
    pg.evaluate("""() => { const G=SG.game, w=SG.WS; const put=(id,x,y,z,dir,f,pose)=>{ const e=G.ent(id); e.cling=null; e.x=x*w; e.y=y*w; e.z=z*w; G.tryAttach(e,0,0,[dir]); if (e.cling && f) e.cling.f=f; e.c.frozen=false; e.c.setPose(pose); e.c.root.visible=true; };
      put('you', 6.9, 1.5, -0.75, [2,1], [1,0,0], 'stretch'); put('cat0', 6.4, 2.3, -2.0, [1,1], null, 'loaf'); put('cat1', 5.6, 2.46, -1.25, [2,-1], [1,0,0], 'sphinx'); G.ent('cat0').c.fill([232,120,42],0.8,0); G.ent('cat1').c.fill([74,134,184],0.8,0); window.__stuck=['you','cat0','cat1'].map(id=>G.ent(id).cling?G.ent(id).cling.n.join(','):null);
      G.ents.forEach(e=>e.c.root.visible = ['you','cat0','cat1'].includes(e.id)); G.cam.free={p:new THREE.Vector3(7.3*w,0.5*w,-3.0*w), t:new THREE.Vector3(5.8*w,2.0*w,-1.2*w), fov:70}; G.step(1.0); G.ents.forEach(e=>e.c.root.visible = ['you','cat0','cat1'].includes(e.id)); G.step(0.05); }"""); snap("three-cats-stuck-wall-ceiling-beam"); print(pg.evaluate("window.__stuck"))
    pg.evaluate("() => { SG.game.toTitle(); SG.game.step(0.5); }"); snap("title")
    for s in (() if "staged" in sys.argv else ("cats", "dogs", "poses", "pose3")):
        pg.goto(ROOT.as_uri() + "?nolock=1&shot=" + s); pg.wait_for_function("window.__ready===true||window.__error", timeout=240000); pg.evaluate("SG.game.paused=true; SG.game.step(0.3)"); pg.screenshot(path=str(OUT / ("lineup-" + s + ".png"))); print(s)
    b.close()
