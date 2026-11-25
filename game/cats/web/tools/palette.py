#!/usr/bin/env python3
"""Palette strip per area: top-down unlit albedo of each area, binned into 24 hues x 2 lightness bands (plus neutrals).
A bin counts when it covers at least 0.3 % of the area. Writes /tmp/webshots/r2/palette-<tag>.png and prints the counts."""
import pathlib, sys, json, base64
from playwright.sync_api import sync_playwright
ARGS = ["--no-sandbox", "--disable-gpu-sandbox", "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"]
root = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else pathlib.Path(__file__).resolve().parent.parent / "index.html"; tag = sys.argv[1] if len(sys.argv) > 1 else "after"
AREAS = {"客廳": [-4.5, 4.5, -3.5, 2.55], "廚房": [-2.5, 2.5, -6.1, -3.5], "玄關": [-6.7, -4.5, -3.5, 2.9], "和室": [2.6, 7.0, -7.5, -3.5], "庭院": [-8, 8, 4.0, 8.7], "書房": [4.62, 8, -3.5, -0.55], "浴室": [4.62, 8, -0.55, 2.3], "倉庫": [-6.7, -2.56, -6.5, -3.62], "西巷": [-8.6, -6.82, -3.5, 2.3], "北巷": [-2.5, 8.6, -8.6, -6.3], "東巷": [8.0, 8.6, -8.6, 2.3]}
JS = """(AREAS) => { const S=SG.WS||1, out={}, cv=document.createElement('canvas'), names=Object.keys(AREAS); cv.width=620; cv.height=names.length*34+8; const g=cv.getContext('2d'); g.fillStyle='#fff'; g.fillRect(0,0,cv.width,cv.height); g.font='15px sans-serif';
 names.forEach((n, k) => { const a=AREAS[n], x0=a[0]*S, x1=a[1]*S, z0=a[2]*S, z1=a[3]*S, W=160, H=Math.max(8, Math.round(W*(z1-z0)/(x1-x0)));
  const cam=new THREE.OrthographicCamera(-(x1-x0)/2,(x1-x0)/2,(z1-z0)/2,-(z1-z0)/2,0.01,60); cam.position.set((x0+x1)/2, 2.2*S, (z0+z1)/2); cam.up.set(0,0,-1); cam.lookAt((x0+x1)/2,0,(z0+z1)/2); cam.updateMatrixWorld(true);
  const px=SG.post.renderAlbedo(SG.scene, cam, W, H), bins={}; let tot=0;
  for (let i=0;i<W*H*4;i+=4){ const r=px[i]/255, gg=px[i+1]/255, b=px[i+2]/255, mx=Math.max(r,gg,b), mn=Math.min(r,gg,b), d=mx-mn, l=(mx+mn)/2; let key; if (d<0.1) key='n'+Math.round(l*3); else { let h = mx===r ? ((gg-b)/d)%6 : mx===gg ? (b-r)/d+2 : (r-gg)/d+4; h=(h*60+360)%360; key=Math.floor(h/15)+'_'+(l<0.45?0:1); } const e=bins[key]||(bins[key]=[0,0,0,0]); e[0]++; e[1]+=px[i]; e[2]+=px[i+1]; e[3]+=px[i+2]; tot++; }
  const keep=Object.keys(bins).filter(k=>bins[k][0]/tot>=0.003).sort((p,q)=>bins[q][0]-bins[p][0]); const hues=keep.filter(k=>k[0]!=='n').length; out[n]={hues, neutrals:keep.length-hues};
  g.fillStyle='#000'; g.fillText(n+'  '+hues+' 色相', 6, k*34+26); keep.forEach((kk, j) => { const e=bins[kk]; g.fillStyle='rgb('+Math.round(e[1]/e[0])+','+Math.round(e[2]/e[0])+','+Math.round(e[3]/e[0])+')'; g.fillRect(120+j*15, k*34+8, 14, 24); }); });
 return {out, url:cv.toDataURL()}; }"""
with sync_playwright() as p:
    b = p.chromium.launch(executable_path="/usr/bin/google-chrome", headless=True, args=ARGS)
    pg = b.new_page(viewport={"width": 640, "height": 360}); pg.goto(root.as_uri() + "?q=low&nolock=1&shot=room"); pg.wait_for_function("window.__ready===true||window.__error", timeout=240000); pg.evaluate("SG.game.paused=true")
    r = pg.evaluate(JS, AREAS); b.close()
pathlib.Path("/tmp/webshots/r2").mkdir(parents=True, exist_ok=True); open("/tmp/webshots/r2/palette-%s.png" % tag, "wb").write(base64.b64decode(r["url"].split(",")[1])); print(tag, json.dumps(r["out"], ensure_ascii=False))
