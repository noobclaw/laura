#!/usr/bin/env python3
"""Camouflage measurement on the flat body (headless Chrome): a posed cat filled with the eyedropped base colour + roughness +
metallic of the surface it lies on, seen by a hunter from 3 m: mean abs difference (0..255, lit render before grading) between
the picture with the cat and the picture without it, over the pixels the cat covers. Walls (3 lighting spots), floors and
ceilings (the plainest patches found automatically). Must stay <= 4. usage: camocheck.py [OUT.json] [pose]"""
import sys, json, pathlib
from playwright.sync_api import sync_playwright
ARGS = ["--no-sandbox", "--disable-gpu-sandbox", "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist", "--allow-file-access-from-files"]
root = pathlib.Path(__file__).resolve().parent.parent / "index.html"
pose = sys.argv[2] if len(sys.argv) > 2 else "pancake"
JS = r"""(pose) => { const G=SG.game, W=SG.WS, post=SG.post, out=[]; G.settings.mode='basic'; SG.RULES.solo.botCatsWhenCat=1; G.start('cat','mochi'); const m=G.me, room=SG.room;
 const cam=new THREE.PerspectiveCamera(40,1,0.05,60), N=96, V3=(x,y,z)=>new THREE.Vector3(x,y,z);
 const shot=(mode)=>post.renderAlbedo(SG.scene, cam, N, N, new Uint8Array(N*N*4), mode).slice();
 const patch=(p, n)=>{ cam.fov=40; cam.updateProjectionMatrix(); cam.position.copy(p).add(V3(n[0],n[1],n[2]).multiplyScalar(0.9)); cam.up.set(0, Math.abs(n[1])>0.5?0:1, Math.abs(n[1])>0.5?1:0); cam.lookAt(p); cam.updateMatrixWorld(true); m.c.root.visible=false; const a=post.renderAlbedo(SG.scene, cam, 12, 12, new Uint8Array(576)); m.c.root.visible=true; let s=[0,0,0], q=[0,0,0]; for(let i=0;i<576;i+=4) for(let k=0;k<3;k++){ s[k]+=a[i+k]; q[k]+=a[i+k]*a[i+k]; } const mean=s.map(v=>v/144), sd=Math.sqrt(q.reduce((t,v,k)=>t+v/144-mean[k]*mean[k],0)/3);
   const ray=new THREE.Raycaster(cam.position.clone(), p.clone().sub(cam.position).normalize()); const h=ray.intersectObjects([room.batched, room.dyn], true)[0]; return {rgb:mean.map(Math.round), sd:+sd.toFixed(2), rough:h&&h.object.material.roughness!=null?h.object.material.roughness:0.9, metal:h&&h.object.material.metalness||0}; };
 const measure=(name, kind, n, pk)=>{ const e=m; e.c.frozen=false; e.c.setPose(pose); for(let k=0;k<30;k++) G.step(0.05); const ctr=e.c.center(); e.c.fill(pk.rgb, pk.rough, pk.metal);
   const res={spot:name, kind, normal:n.join(','), picked:pk, views:[]}; const nn=V3(n[0],n[1],n[2]), t=Math.abs(n[1])>0.5?V3(1,0,0):V3(n[2],0,-n[0]);
   const eyes = Math.abs(n[1])>0.5 ? [[3,0.2],[3,0.62],[1.5,0.2]].map(([d,h],i)=>{ const a=i*2.1; return {tag:d+'m eye '+h, p:V3(ctr.x+Math.cos(a)*d, n[1]>0?room.groundAt(ctr.x,ctr.z,ctr.y+0.1,0)+h:h, ctr.z+Math.sin(a)*d)}; }) : [0,0.6,-0.6].map(ang=>{ const p=ctr.clone().add(nn.clone().multiplyScalar(3*Math.cos(ang))).add(t.clone().multiplyScalar(3*Math.sin(ang))); p.y=0.2; return {tag:Math.round(ang*57.3)+' deg', p}; });
   for (const ev of eyes) { cam.position.copy(ev.p); cam.up.set(0,1,0); cam.lookAt(ctr); cam.fov=14; cam.updateProjectionMatrix(); cam.updateMatrixWorld(true);
     e.c.root.visible=true; const withCat=shot('lit'); e.c.root.visible=false; const noCat=shot('lit'); e.c.root.visible=true;
     const save=e.c.alb.slice(); e.c.fill([255,0,255],1,0); const mag=shot(undefined); e.c.alb.set(save); e.c.texA.needsUpdate=true; e.c.fill(pk.rgb, pk.rough, pk.metal);
     let cnt=0, sum=0, mx=0; for (let i=0;i<N*N*4;i+=4){ if (mag[i]>200&&mag[i+1]<90&&mag[i+2]>200){ const d=(Math.abs(withCat[i]-noCat[i])+Math.abs(withCat[i+1]-noCat[i+1])+Math.abs(withCat[i+2]-noCat[i+2]))/3; sum+=d; cnt++; if(d>mx)mx=d; } }
     res.views.push({view:ev.tag, catPixels:cnt, meanAbsDiff8bit:cnt?+(sum/cnt).toFixed(1):null, maxDiff:Math.round(mx)}); }
   out.push(res); };
 // walls: the three lighting spots of the playtest
 for (const s of [{n:'study west wall (indoor lamp)', p:[4.78,1.65,-1.05], dir:[0,-1]}, {n:'kitchen outer wall, north alley (outdoor shade)', p:[-0.3,1.4,-6.4], dir:[2,1]}, {n:'bath partition wall (lamp, window side)', p:[7.4,1.5,-0.35], dir:[2,-1]}]) {
   const e=m; e.cling=null; e.c.setPose('stand'); e.x=s.p[0]*W; e.y=s.p[1]*W; e.z=s.p[2]*W; G.tryAttach(e,0,0,[s.dir]); if (!e.cling) { out.push({spot:s.n, kind:'wall', err:'could not attach'}); continue; }
   G.step(0.1); const n=e.cling.n, c0=e.c.center(); measure(s.n, 'wall', n, patch(c0.clone().add(V3(0,0.5,0)), n)); }
 // floors and ceilings: the plainest patches on a grid
 const b=room.bounds, fl=[], ce=[];
 for (let x=b.x0+0.9; x<b.x1-0.9; x+=0.75) for (let z=b.z0+0.9; z<b.z1-0.9; z+=0.75) { const g=room.groundAt(x,z,0.3,0); if (g>0.3||g<-0.01||room.blocked(x,z,g,0.45,0.05,0.4)) continue; m.cling=null; m.x=x; m.z=z; m.y=g; G.place('you',x,g,z,0); const pk=patch(V3(x,g+0.005,z),[0,1,0]); if (pk.sd<2.2) fl.push({x,z,g,pk});
   m.y=g+1.2; m.cling=null; if (G.tryAttach(m,0,0,[[1,1]])||(()=>{ for(let yy=g+1.5; yy<g+5; yy+=0.25){ m.y=yy; if(G.tryAttach(m,0,0,[[1,1]])) return true; } return false; })()) { const cy=m.y; const pk2=patch(V3(x,cy-0.005,z),[0,-1,0]); if (pk2.sd<2.2) ce.push({x,z,y:cy,pk:pk2}); m.cling=null; } }
 fl.sort((a,b2)=>a.pk.sd-b2.pk.sd); ce.sort((a,b2)=>a.pk.sd-b2.pk.sd);
 const pick3=(L)=>{ const o=[]; for(const c of L){ if(o.every(q=>Math.hypot(q.x-c.x,q.z-c.z)>3)) o.push(c); if(o.length>=3) break; } return o; };
 for (const c of pick3(fl)) { m.cling=null; G.place('you',c.x,c.g,c.z,0.4); G.step(0.1); measure('floor '+(c.x/W).toFixed(1)+','+(c.z/W).toFixed(1), 'floor', [0,1,0], c.pk); }
 for (const c of pick3(ce)) { m.cling=null; m.c.setPose('stand'); m.x=c.x; m.z=c.z; m.y=c.y-0.3; G.tryAttach(m,0,0,[[1,1]]); if(!m.cling){ out.push({spot:'ceiling', kind:'ceiling', err:'could not attach'}); continue; } G.step(0.1); measure('ceiling '+(c.x/W).toFixed(1)+','+(c.z/W).toFixed(1)+' y '+c.y.toFixed(2), 'ceiling', [0,-1,0], c.pk); }
 return {out, floorsFound:fl.length, ceilingsFound:ce.length}; }"""
with sync_playwright() as p:
    b = p.chromium.launch(executable_path="/usr/bin/google-chrome", headless=True, args=ARGS)
    pg = b.new_page(viewport={"width": 960, "height": 540}); logs = []
    pg.on("pageerror", lambda e: logs.append("pageerror: " + str(e)))
    pg.goto(root.as_uri() + "?shot=room&nolock=1"); pg.wait_for_function("window.__ready===true || window.__error", timeout=180000)
    r = pg.evaluate(JS, pose); b.close()
worst = {}
for q in r["out"]:
    vs = [v["meanAbsDiff8bit"] for v in q.get("views", []) if v["catPixels"] > 150]
    print(q.get("kind"), "|", q["spot"], "|", q.get("picked", {}).get("rgb"), "sd", q.get("picked", {}).get("sd"), "|", [(v["view"], v["catPixels"], v["meanAbsDiff8bit"], v["maxDiff"]) for v in q.get("views", [])], q.get("err", ""))
    if vs: worst[q["kind"]] = max(worst.get(q["kind"], 0), max(vs))
print("worst per kind:", worst, "floors", r["floorsFound"], "ceilings", r["ceilingsFound"], "errors", logs[:3])
print("PASS" if worst and all(v <= 4.0 for v in worst.values()) and len(worst) == 3 else "FAIL")
if len(sys.argv) > 1: json.dump({"worst": worst, "results": r["out"]}, open(sys.argv[1], "w"), indent=1)
