"use strict";
// Main-screen sample for the supermarket game. Everything is built in code: no image or model files.
// This is a look sample, not the game: customers walk a fixed loop and the numbers are placeholders.
const T = THREE, gl = document.getElementById("gl");
const R = new T.WebGLRenderer({ canvas: gl, antialias: true });
R.setPixelRatio(Math.min(devicePixelRatio, 2)); R.shadowMap.enabled = true; R.shadowMap.type = T.PCFSoftShadowMap;
R.toneMapping = T.ACESFilmicToneMapping; R.toneMappingExposure = 1.18; R.outputColorSpace = T.SRGBColorSpace;
const scene = new T.Scene(), cam = new T.PerspectiveCamera(34, 1, .1, 300);
let seed = 11; const rnd = (a = 0, b = 1) => { seed = (seed * 1664525 + 1013904223) >>> 0; return a + (b - a) * seed / 4294967296 };
const pick = a => a[Math.floor(rnd(0, a.length))];

// ---------- textures drawn on canvases ----------
function tex(size, draw, rep) { const c = document.createElement("canvas"); c.width = c.height = size; draw(c.getContext("2d"), size); const t = new T.CanvasTexture(c); t.colorSpace = T.SRGBColorSpace; t.anisotropy = 8; if (rep) { t.wrapS = t.wrapT = T.RepeatWrapping; t.repeat.set(rep[0], rep[1]) } return t }
function speckle(c, s, n, a, b, alpha) { for (let i = 0; i < n; i++) { const v = Math.floor(rnd(a, b)); c.fillStyle = `rgba(${v},${v},${v},${alpha})`; c.fillRect(rnd(0, s), rnd(0, s), rnd(1, 3), rnd(1, 3)) } }
const tileTex = tex(512, (c, s) => { const n = 4, w = s / n; for (let y = 0; y < n; y++)for (let x = 0; x < n; x++) { const v = 228 + rnd(-10, 10); c.fillStyle = `rgb(${v},${v - 6},${v - 16})`; c.fillRect(x * w, y * w, w, w); const g = c.createLinearGradient(x * w, y * w, x * w + w, y * w + w); g.addColorStop(0, "rgba(255,255,255,.22)"); g.addColorStop(.5, "rgba(255,255,255,0)"); g.addColorStop(1, "rgba(120,90,60,.12)"); c.fillStyle = g; c.fillRect(x * w, y * w, w, w) } speckle(c, s, 2600, 150, 250, .12); c.strokeStyle = "rgba(120,104,88,.75)"; c.lineWidth = 3; for (let i = 0; i <= n; i++) { c.beginPath(); c.moveTo(i * w, 0); c.lineTo(i * w, s); c.moveTo(0, i * w); c.lineTo(s, i * w); c.stroke() } }, [7, 5]);
const wallTex = tex(512, (c, s) => { c.fillStyle = "#e9dcc4"; c.fillRect(0, 0, s, s); const h = s / 6; for (let r = 0; r < 6; r++) { const off = r % 2 ? s / 6 : 0; for (let x = -1; x < 4; x++) { const v = rnd(-12, 12); c.fillStyle = `rgb(${226 + v},${212 + v},${188 + v})`; c.fillRect(x * s / 3 + off + 2, r * h + 2, s / 3 - 4, h - 4) } } speckle(c, s, 3000, 120, 240, .1); c.fillStyle = "rgba(90,70,50,.25)"; for (let r = 0; r <= 6; r++)c.fillRect(0, r * h - 1, s, 2) }, [6, 1]);
const asphaltTex = tex(512, (c, s) => { c.fillStyle = "#565b72"; c.fillRect(0, 0, s, s); speckle(c, s, 9000, 60, 170, .35); c.strokeStyle = "rgba(20,20,28,.5)"; c.lineWidth = 1.5; for (let i = 0; i < 9; i++) { c.beginPath(); let x = rnd(0, s), y = rnd(0, s); c.moveTo(x, y); for (let k = 0; k < 6; k++) { x += rnd(-30, 30); y += rnd(-30, 30); c.lineTo(x, y) } c.stroke() } for (let i = 0; i < 5; i++) { const g = c.createRadialGradient(rnd(0, s), rnd(0, s), 2, rnd(0, s), rnd(0, s), 60); g.addColorStop(0, "rgba(10,10,20,.35)"); g.addColorStop(1, "rgba(10,10,20,0)"); c.fillStyle = g; c.fillRect(0, 0, s, s) } }, [5, 3]);
const paveTex = tex(256, (c, s) => { c.fillStyle = "#b9a892"; c.fillRect(0, 0, s, s); const w = s / 4; for (let y = 0; y < 4; y++)for (let x = 0; x < 4; x++) { const v = rnd(-14, 14); c.fillStyle = `rgb(${196 + v},${180 + v},${158 + v})`; c.fillRect(x * w + 2 + (y % 2 ? w / 2 : 0) - (y % 2 && x === 3 ? s : 0), y * w + 2, w - 4, w - 4) } speckle(c, s, 900, 90, 220, .15) }, [14, 2]);
const woodTex = tex(256, (c, s) => { c.fillStyle = "#a9713f"; c.fillRect(0, 0, s, s); for (let i = 0; i < 60; i++) { c.strokeStyle = `rgba(${rnd(60, 110)},${rnd(35, 60)},${rnd(15, 30)},.35)`; c.lineWidth = rnd(1, 3); c.beginPath(); const y = rnd(0, s); c.moveTo(0, y); c.bezierCurveTo(s / 3, y + rnd(-8, 8), s * 2 / 3, y + rnd(-8, 8), s, y); c.stroke() } });
const grassTex = tex(256, (c, s) => { c.fillStyle = "#3f8f4e"; c.fillRect(0, 0, s, s); for (let i = 0; i < 2600; i++) { c.strokeStyle = `hsla(${rnd(95, 140)},${rnd(40, 60)}%,${rnd(24, 46)}%,.6)`; c.beginPath(); const x = rnd(0, s), y = rnd(0, s); c.moveTo(x, y); c.lineTo(x + rnd(-2, 2), y - rnd(3, 8)); c.stroke() } }, [6, 1]);
function signTex(text, icon, bg, fg) { return tex(512, (c, s) => { c.clearRect(0, 0, s, s); const g = c.createLinearGradient(0, 150, 0, 360); g.addColorStop(0, bg[0]); g.addColorStop(1, bg[1]); c.fillStyle = g; rr(c, 14, 150, s - 28, 212, 46); c.fill(); c.lineWidth = 10; c.strokeStyle = "rgba(255,255,255,.85)"; c.stroke(); c.font = "130px serif"; c.textAlign = "center"; c.textBaseline = "middle"; c.fillText(icon, 104, 262); c.font = "800 78px ui-rounded,system-ui,sans-serif"; c.fillStyle = fg; c.fillText(text, 318, 262, 290) }) }
function rr(c, x, y, w, h, r) { c.beginPath(); c.moveTo(x + r, y); c.arcTo(x + w, y, x + w, y + h, r); c.arcTo(x + w, y + h, x, y + h, r); c.arcTo(x, y + h, x, y, r); c.arcTo(x, y, x + w, y, r); c.closePath() }
const glowTex = tex(128, (c, s) => { const g = c.createRadialGradient(s / 2, s / 2, 0, s / 2, s / 2, s / 2); g.addColorStop(0, "rgba(255,255,255,1)"); g.addColorStop(.25, "rgba(255,255,255,.55)"); g.addColorStop(1, "rgba(255,255,255,0)"); c.fillStyle = g; c.fillRect(0, 0, s, s) });

// ---------- helpers ----------
const M = (color, o = {}) => new T.MeshStandardMaterial(Object.assign({ color, roughness: .7, metalness: 0 }, o));
const box = (w, h, d, mat, x = 0, y = 0, z = 0, p = scene) => { const m = new T.Mesh(new T.BoxGeometry(w, h, d), mat); m.position.set(x, y, z); m.castShadow = m.receiveShadow = true; p.add(m); return m };
const cyl = (r1, r2, h, mat, x = 0, y = 0, z = 0, p = scene, seg = 16) => { const m = new T.Mesh(new T.CylinderGeometry(r1, r2, h, seg), mat); m.position.set(x, y, z); m.castShadow = m.receiveShadow = true; p.add(m); return m };
const ball = (r, mat, x = 0, y = 0, z = 0, p = scene) => { const m = new T.Mesh(new T.SphereGeometry(r, 14, 10), mat); m.position.set(x, y, z); m.castShadow = true; p.add(m); return m };
function glow(color, size, x, y, z, p = scene, op = .9) { const s = new T.Sprite(new T.SpriteMaterial({ map: glowTex, color, transparent: true, opacity: op, blending: T.AdditiveBlending, depthWrite: false })); s.scale.set(size, size, 1); s.position.set(x, y, z); p.add(s); return s }
const flick = [], spin = [], mist = [];

// ---------- sky ----------
scene.background = tex(512, (c, s) => { const g = c.createLinearGradient(0, 0, 0, s); g.addColorStop(0, "#120c33"); g.addColorStop(.45, "#3a1f63"); g.addColorStop(.72, "#b0486a"); g.addColorStop(.9, "#ff9a5c"); g.addColorStop(1, "#ffd08a"); c.fillStyle = g; c.fillRect(0, 0, s, s); for (let i = 0; i < 160; i++) { c.fillStyle = `rgba(255,255,255,${rnd(.2, .9)})`; const y = rnd(0, s * .5); c.fillRect(rnd(0, s), y, rnd(.6, 1.8), rnd(.6, 1.8)) } });
scene.fog = new T.Fog(0x4a2a5e, 110, 230);

// ---------- lights ----------
scene.add(new T.HemisphereLight(0xc4b6ff, 0x4a3a30, 1.25));
const sun = new T.DirectionalLight(0xffc48a, 2.1); sun.position.set(-16, 22, 14); sun.castShadow = true; sun.shadow.mapSize.set(2048, 2048);
Object.assign(sun.shadow.camera, { left: -24, right: 24, top: 26, bottom: -26, near: 1, far: 80 }); sun.shadow.bias = -.0004; sun.shadow.normalBias = .03; scene.add(sun);
const fill = new T.DirectionalLight(0x7f8cff, .55); fill.position.set(14, 10, -10); scene.add(fill);

// ---------- ground: lot, pavement, street ----------
const W = 18, D = 12;                                   // store footprint, centred on x; z from -D to 0
const lot = new T.Mesh(new T.PlaneGeometry(60, 34), M(0xffffff, { map: asphaltTex, roughness: .92 })); lot.rotation.x = -Math.PI / 2; lot.position.set(0, 0, 9); lot.receiveShadow = true; scene.add(lot);
const far = new T.Mesh(new T.PlaneGeometry(120, 60), M(0x3a3358, { roughness: 1 })); far.rotation.x = -Math.PI / 2; far.position.set(0, -.02, -30); scene.add(far);
const pave = new T.Mesh(new T.PlaneGeometry(W + 6, 2.2), M(0xffffff, { map: paveTex, roughness: .85 })); pave.rotation.x = -Math.PI / 2; pave.position.set(0, .03, 1.2); pave.receiveShadow = true; scene.add(pave);
const lineM = new T.MeshBasicMaterial({ color: 0xf2f2e8 });
for (let i = -5; i <= 5; i++) { const l = new T.Mesh(new T.PlaneGeometry(.1, 3.4), lineM); l.rotation.x = -Math.PI / 2; l.position.set(i * 2.3, .012, 5.2); scene.add(l) }
for (let i = -6; i <= 6; i++) { const l = new T.Mesh(new T.PlaneGeometry(1.4, .14), new T.MeshBasicMaterial({ color: 0xffd35a })); l.rotation.x = -Math.PI / 2; l.position.set(i * 3.2, .012, 10.4); scene.add(l) }
for (let i = 0; i < 6; i++) { const z = new T.Mesh(new T.PlaneGeometry(.5, 2), lineM); z.rotation.x = -Math.PI / 2; z.position.set(-1.6 + i * .64, .013, 2.9); scene.add(z) }
for (const sx of [-1, 1]) { const g = new T.Mesh(new T.PlaneGeometry(2.4, 13), M(0xffffff, { map: grassTex, roughness: 1 })); g.rotation.x = -Math.PI / 2; g.rotation.z = Math.PI / 2; g.position.set(sx * 14.6, .05, 7.6); g.scale.set(1, .5, 1); g.receiveShadow = true; scene.add(g) }

// ---------- store shell (cut-away: floor, back wall, side walls, low front wall with door) ----------
const floor = new T.Mesh(new T.PlaneGeometry(W, D), M(0xffffff, { map: tileTex, roughness: .28, metalness: .08 })); floor.rotation.x = -Math.PI / 2; floor.position.set(0, .08, -D / 2); floor.receiveShadow = true; scene.add(floor);
box(W + .6, .16, D + .6, M(0x8d7b68), 0, 0, -D / 2);
const wallM = M(0xffffff, { map: wallTex, roughness: .85 }), trimM = M(0x6b4a3a, { roughness: .5 }), darkM = M(0x2c2540, { roughness: .6 });
box(W + .6, 4.2, .4, wallM, 0, 2.1, -D - .1); box(W + 1, .3, .7, trimM, 0, 4.3, -D - .1);
for (const sx of [-1, 1]) { box(.4, 2.6, D, wallM, sx * (W / 2 + .1), 1.3, -D / 2); box(.6, .22, D + .4, trimM, sx * (W / 2 + .1), 2.7, -D / 2) }
for (const sx of [-1, 1]) { box(W / 2 - 1.6, 1.0, .3, wallM, sx * (W / 4 + .8), .5, 0); box(W / 2 - 1.6, .14, .44, trimM, sx * (W / 4 + .8), 1.05, 0); const gl2 = box(W / 2 - 1.8, 1.3, .06, new T.MeshPhysicalMaterial({ color: 0xbfe6ff, transparent: true, opacity: .22, roughness: .05, metalness: 0 }), sx * (W / 4 + .8), 1.75, 0); gl2.castShadow = false }
box(.3, 3, .3, trimM, -1.6, 1.5, 0); box(.3, 3, .3, trimM, 1.6, 1.5, 0); box(3.6, .16, 1.1, M(0xd4472f, { roughness: .5 }), 0, 3.05, .45); box(3.4, .05, .9, M(0xfff2d8, { emissive: 0xffd9a0, emissiveIntensity: 1.2 }), 0, 2.95, .45);
glow(0xffc27a, 7, 0, 2.2, .9, scene, .55);
// neon name on the back wall
const neon = new T.Mesh(new T.PlaneGeometry(9, 2.2), new T.MeshBasicMaterial({ map: tex(1024, (c, s) => { c.clearRect(0, 0, s, s); c.font = "900 190px ui-rounded,system-ui,sans-serif"; c.textAlign = "center"; c.textBaseline = "middle"; c.shadowColor = "#ff4fa0"; c.shadowBlur = 60; c.fillStyle = "#fff"; for (let i = 0; i < 3; i++)c.fillText("SOUQ  MART", s / 2, s / 2); c.shadowBlur = 0; c.lineWidth = 6; c.strokeStyle = "#ff7ac0"; c.strokeText("SOUQ  MART", s / 2, s / 2) }), transparent: true })); neon.position.set(0, 5.3, -D - .05); neon.scale.y = 4.2; scene.add(neon); flick.push(neon.material);
glow(0xff4fa0, 16, 0, 5.2, -D + .4, scene, .5);
// ceiling lamps: a truss with hanging lights and pools of light on the floor
for (const z of [-3.2, -8.6]) { box(W, .1, .1, darkM, 0, 4.0, z).castShadow = false; for (let x = -7; x <= 7; x += 3.5) { cyl(.02, .02, .7, darkM, x, 3.65, z).castShadow = false; const l = cyl(.3, .16, .2, M(0xfff0c8, { emissive: 0xffd890, emissiveIntensity: 2.2 }), x, 3.25, z); l.castShadow = false; glow(0xffd28a, 2.6, x, 3.2, z, scene, .7); const pool = new T.Mesh(new T.CircleGeometry(1.9, 24), new T.MeshBasicMaterial({ map: glowTex, color: 0xffd9a0, transparent: true, opacity: .28, blending: T.AdditiveBlending, depthWrite: false })); pool.rotation.x = -Math.PI / 2; pool.position.set(x, .1, z); scene.add(pool) } }
const warm = new T.PointLight(0xffb060, 60, 26, 1.6); warm.position.set(0, 3.4, -5.5); scene.add(warm);

// ---------- departments ----------
function bay(x, z, w, d, mat, label, icon, colors) {
  const g = new T.Group(); g.position.set(x, .09, z); scene.add(g);
  const rug = new T.Mesh(new T.PlaneGeometry(w, d), M(mat, { roughness: .9 })); rug.rotation.x = -Math.PI / 2; rug.position.y = .005; rug.receiveShadow = true; g.add(rug);
  const edge = new T.Mesh(new T.RingGeometry(.0001, .0001, 4), M(0xffffff)); g.add(edge);
  const sign = new T.Mesh(new T.PlaneGeometry(2.5, 2.5), new T.MeshBasicMaterial({ map: signTex(label, icon, colors, "#fff"), transparent: true })); sign.position.set(0, 2.55, -d / 2 + .2); g.add(sign);
  for (const sx of [-.9, .9]) cyl(.015, .015, 1.2, darkM, sx, 3.4, -d / 2 + .2, g).castShadow = false;
  glow(new T.Color(colors[0]), 3.4, 0, 2.5, -d / 2 + .5, g, .35); return g
}
const crateM = M(0xffffff, { map: woodTex, roughness: .8 }), steelM = M(0xcfd6e2, { roughness: .25, metalness: .8 }), glassM = new T.MeshPhysicalMaterial({ color: 0xcfefff, transparent: true, opacity: .28, roughness: .04 });
function pile(g, x, y, z, nx, nz, r, cols, jit = .5) { for (let i = 0; i < nx; i++)for (let k = 0; k < nz; k++)for (let l = 0; l < 2; l++) { if (l && rnd() < .35) continue; ball(r * rnd(.85, 1.1), M(pick(cols), { roughness: .45 }), x + (i - (nx - 1) / 2) * r * 1.9 + rnd(-r, r) * jit * .3, y + r + l * r * 1.5, z + (k - (nz - 1) / 2) * r * 1.9, g) } }
// 1. produce: tiered crates
{ const g = bay(-6.2, -9.6, 4.6, 3.6, 0x4f9d58, "Fresh", "🍊", ["#3fbf6a", "#1f8a4c"]);
  for (let t = 0; t < 3; t++)for (let i = 0; i < 4; i++) { const cx = -1.65 + i * 1.1, cz = -1.1 + t * .75, cy = .55 - t * .18; box(1, .34, .66, crateM, cx, cy, cz, g).rotation.x = -.22; pile(g, cx, cy + .1, cz, 4, 2, .13, [[0xff5a3c, 0xe8402a], [0xffa531, 0xff8c1a], [0x7fd14b, 0x4faa2e], [0xffe14a, 0xf2c21e], [0x9b3fd1, 0x7a2bb0], [0xff7fa8, 0xe85a86]][(i + t * 2) % 6]) }
  box(4.4, .5, 2.6, M(0x6b4a2e, { map: woodTex }), 0, .2, -.4, g); for (const sx of [-1.9, 1.9]) { cyl(.5, .42, .7, crateM, sx, .35, 1.2, g, 12); ball(.42, M(0x2f8a3a, { roughness: .5 }), sx, .95, 1.2, g).scale.set(1, .8, 1) } }
// 2. bakery: shelves, baskets, oven
{ const g = bay(-1.1, -9.6, 4.2, 3.6, 0xc98a4a, "Bakery", "🥐", ["#ffb24a", "#e07a1a"]);
  for (let s = 0; s < 3; s++) { box(3.6, .08, .7, crateM, 0, .5 + s * .62, -1.25, g); for (let i = 0; i < 7; i++) { const b = ball(.2, M(pick([0xd9a05a, 0xc88a3c, 0xe6b877, 0xb87430]), { roughness: .75 }), -1.5 + i * .5, .66 + s * .62, -1.25 + rnd(-.1, .1), g); b.scale.set(1.5, .62, .8); b.rotation.y = rnd(-.5, .5) } }
  for (const sx of [-1.75, 1.75]) box(.1, 2, .7, crateM, sx, 1, -1.25, g);
  const ov = box(1.5, 1.3, .9, steelM, 1.1, .65, .7, g); box(1.1, .6, .04, M(0x301408, { emissive: 0xff6a1a, emissiveIntensity: 2.4 }), 1.1, .68, 1.17, g).castShadow = false; glow(0xff7a2a, 2.4, 1.1 - 1.1 + 1.1, .7, 1.4, g, .7); mist.push({ g, x: 1.1, y: 1.4, z: .7, c: 0xfff0d0, up: 1 });
  box(1.6, .8, .8, crateM, -1, .4, .7, g); for (let i = 0; i < 5; i++)cyl(.07, .07, .9, M(0xe8c07a, { roughness: .8 }), -1.5 + i * .22, 1.05, .7, g, 8).rotation.z = .25 }
// 3. seafood: ice bed and cold mist
{ const g = bay(3.9, -9.6, 4.4, 3.6, 0x3c8fb8, "Seafood", "🐟", ["#35b6e6", "#1a78b8"]);
  box(3.8, .7, 1.6, steelM, 0, .35, -.9, g); const ice = box(3.6, .16, 1.4, M(0xeaf7ff, { roughness: .2, emissive: 0x9fdcff, emissiveIntensity: .25 }), 0, .78, -.9, g); ice.rotation.x = -.12;
  for (let i = 0; i < 60; i++)ball(rnd(.06, .11), M(0xf4fbff, { roughness: .15 }), rnd(-1.7, 1.7), .86, -.9 + rnd(-.6, .6), g);
  for (let i = 0; i < 12; i++) { const f = ball(.16, M(pick([0x8fa6b8, 0xc7d3dc, 0xff8f7a, 0x5f7f96]), { roughness: .3, metalness: .4 }), -1.5 + (i % 6) * .6, .95, -1.2 + Math.floor(i / 6) * .6, g); f.scale.set(1.9, .5, .7); f.rotation.y = rnd(-.4, .4) }
  box(3.8, .5, .05, glassM, 0, 1.1, -.2, g).castShadow = false; mist.push({ g, x: 0, y: 1, z: -.9, c: 0xcfeeff, up: 0 }); glow(0x7fd8ff, 4, 0, 1, -.9, g, .3);
  cyl(.55, .5, .75, M(0x2a6fa0), 1.5, .38, 1, g); cyl(.5, .5, .05, M(0x6fd0ff, { emissive: 0x2a9fe0, emissiveIntensity: .6, roughness: .1 }), 1.5, .76, 1, g) }
// 4. dates and spices: sacks with coloured mounds (the department the original game does not have)
{ const g = bay(-6.2, -4.6, 4.6, 3.4, 0x9a4a2a, "Spices", "🌶️", ["#ff7a3a", "#c93a1a"]);
  const cols = [0xe0421f, 0xf2b01e, 0x7a4a1e, 0xc9601a, 0x5f8a2e, 0xf7d98a, 0x8a1f1f, 0xd98a2a];
  for (let i = 0; i < 8; i++) { const x = -1.6 + (i % 4) * 1.07, z = -.75 + Math.floor(i / 4) * 1.05; const sack = cyl(.44, .36, .5, M(0xcdb38a, { roughness: 1 }), x, .25, z, g, 12); const m = new T.Mesh(new T.ConeGeometry(.4, .46, 14), M(cols[i], { roughness: .95 })); m.position.set(x, .7, z); m.castShadow = true; g.add(m); const sc = box(.04, .34, .1, steelM, x + .2, .9, z, g); sc.rotation.z = -.5 }
  box(1.4, .12, .5, crateM, 0, 1.25, -1.45, g); for (let i = 0; i < 5; i++) { cyl(.12, .12, .3, new T.MeshPhysicalMaterial({ color: pick(cols), roughness: .1, transparent: true, opacity: .85 }), -.5 + i * .25, 1.46, -1.45, g, 10) }
  const tray = cyl(.7, .7, .06, M(0xd8b24a, { roughness: .3, metalness: .7 }), 1.7, .75, 1.1, g, 20); cyl(.08, .3, .7, M(0x6b4a2e), 1.7, .36, 1.1, g, 8); for (let i = 0; i < 26; i++) { const d = ball(.085, M(pick([0x4a2412, 0x6b3418, 0x3a1a0c]), { roughness: .35 }), 1.7 + rnd(-.5, .5), .84 + rnd(0, .12), 1.1 + rnd(-.5, .5), g); d.scale.set(1.5, .8, .8) } }
// 5. coffee and tea
{ const g = bay(-1.1, -4.6, 4.2, 3.4, 0x6a4a3a, "Coffee", "☕", ["#b07a4a", "#6b3f22"]);
  box(3.4, 1, .9, M(0x4a2c1c, { map: woodTex }), 0, .5, -.9, g); box(3.6, .08, 1.1, M(0xf2e6d2, { roughness: .3 }), 0, 1.04, -.9, g);
  const mach = box(.9, .8, .6, steelM, -.9, 1.48, -.95, g); box(.5, .06, .06, M(0xff4a2a, { emissive: 0xff4a2a, emissiveIntensity: 2 }), -.9, 1.7, -.64, g); mist.push({ g, x: -.9, y: 1.95, z: -.9, c: 0xffffff, up: 1 });
  for (let i = 0; i < 4; i++) { const p = cyl(.16, .12, .34, M(0xd8b24a, { roughness: .25, metalness: .85 }), .2 + i * .42, 1.25, -.9, g, 12); const sp = cyl(.03, .02, .3, M(0xd8b24a, { metalness: .85, roughness: .25 }), .2 + i * .42 + .16, 1.34, -.9, g, 6); sp.rotation.z = -.9 }
  for (let s = 0; s < 2; s++) { box(3.4, .06, .4, crateM, 0, 1.9 + s * .5, -1.5, g); for (let i = 0; i < 9; i++)box(.26, .34, .2, M(pick([0x8a1f1f, 0x1f5a3a, 0x1f3a7a, 0xc98a1a, 0x3a1f5a]), { roughness: .6 }), -1.5 + i * .37, 2.1 + s * .5, -1.5, g) }
  for (const sx of [-1.2, 1.2]) { cyl(.34, .34, .05, crateM, sx, .72, .9, g, 16); cyl(.04, .04, .7, darkM, sx, .36, .9, g, 8); cyl(.07, .06, .1, M(0xffffff), sx + .1, .8, .9, g, 10) } }
// 6. fragrance
{ const g = bay(3.9, -4.6, 4.4, 3.4, 0x5a3a8a, "Oud", "💎", ["#b06aff", "#6a2ad0"]);
  for (let s = 0; s < 3; s++) { box(3.6, .05, .6, glassM, 0, .6 + s * .55, -1.3, g).castShadow = false; for (let i = 0; i < 8; i++) { const c = pick([0xffd35a, 0xff7ac0, 0x9fe8ff, 0xc9a0ff, 0xffa24a]); const b = cyl(.09, .11, .26, new T.MeshPhysicalMaterial({ color: c, roughness: .05, transparent: true, opacity: .8, emissive: c, emissiveIntensity: .35 }), -1.55 + i * .44, .76 + s * .55, -1.3, g, 8); cyl(.04, .04, .08, M(0xd8b24a, { metalness: .9, roughness: .2 }), -1.55 + i * .44, .93 + s * .55, -1.3, g, 6) } }
  for (const sx of [-1.8, 1.8]) box(.08, 1.9, .6, M(0xd8b24a, { metalness: .9, roughness: .25 }), sx, .95, -1.3, g);
  const ped = cyl(.5, .6, .9, M(0x2a1f4a, { roughness: .3 }), 0, .45, .6, g, 20); const jar = ball(.34, new T.MeshPhysicalMaterial({ color: 0xffc56a, roughness: .05, transparent: true, opacity: .75, emissive: 0xff9a2a, emissiveIntensity: .6 }), 0, 1.25, .6, g); spin.push(jar); glow(0xc98aff, 4.5, 0, 1.3, .6, g, .5);
  for (let i = 0; i < 10; i++) { const s = glow(pick([0xffd35a, 0xc9a0ff, 0xff9ad8]), .22, rnd(-1.8, 1.8), rnd(.8, 2.4), rnd(-1.3, 1), g, .9); mist.push({ spark: s, ph: rnd(0, 6) }) } }

// ---------- checkout row ----------
for (let i = 0; i < 3; i++) { const g = new T.Group(); g.position.set(-4.6 + i * 2.9, .09, -1.5); scene.add(g);
  box(1.9, .8, .7, M(0x2f6fd6, { roughness: .4 }), 0, .4, 0, g); box(2, .06, .8, M(0xe9eef6, { roughness: .3 }), 0, .83, 0, g);
  const belt = box(1.1, .03, .5, M(0x1c1c22, { roughness: .9 }), -.3, .87, 0, g); belt.castShadow = false;
  box(.5, .4, .06, M(0x10203a, { emissive: 0x3fd0ff, emissiveIntensity: 1.6 }), .62, 1.2, -.15, g).rotation.y = -.5; cyl(.03, .03, .34, darkM, .62, .98, -.15, g, 6);
  box(.14, .1, .14, M(0x111111, { emissive: 0xff2a2a, emissiveIntensity: 2.2 }), .28, .9, .1, g); glow(0xff3a3a, .5, .28, .95, .1, g, .8);
  for (let k = 0; k < 3; k++)box(.2, .2, .2, M(pick([0xff8a3a, 0x7fd14b, 0xffe14a, 0xff5a8a])), -.7 + k * .3, .98, rnd(-.1, .1), g);
  box(.5, .46, .36, M(0xc9a36a, { roughness: 1 }), 1.25, .6, 0, g); }
for (let i = 0; i < 4; i++) { cyl(.05, .05, .9, steelM, -6 + i * 2.9, .54, -.6, scene, 8); if (i < 3) { const r = box(2.9, .04, .04, M(0xd4472f), -4.55 + i * 2.9, .92, -.6); r.castShadow = false } }

// ---------- people (segmented, animated in code) ----------
const skins = [0xf2c9a0, 0xd9a273, 0xb07a4f, 0x8a5a3a, 0xf7d9b8], cloth = [0xffffff, 0x1f2a4a, 0xe84a5f, 0x3fa7d6, 0x2f8a5a, 0xf2b01e, 0x7a4ad0, 0x222222, 0xf7e9d0];
const people = [];
function person(kind) {
  const g = new T.Group(), skin = pick(skins), top = pick(cloth), robe = kind === 1 || kind === 2;
  const body = cyl(.2, robe ? .3 : .22, robe ? .95 : .55, M(kind === 1 ? 0xffffff : kind === 2 ? pick([0x1c1c22, 0x3a1f4a, 0x1f3a4a]) : top, { roughness: .8 }), 0, robe ? .62 : .82, 0, g, 12);
  const head = ball(.19, M(skin, { roughness: .6 }), 0, 1.3, 0, g);
  if (kind === 1) { const c = ball(.215, M(pick([0xffffff, 0xd9382e]), { roughness: .9 }), 0, 1.34, -.02, g); c.scale.set(1, .8, 1.05); const band = cyl(.2, .2, .05, M(0x111111), 0, 1.44, 0, g, 12); const cloth2 = box(.36, .34, .06, M(0xffffff, { roughness: .9 }), 0, 1.16, -.17, g) }
  else if (kind === 2) { const c = ball(.225, M(body.material.color.getHex(), { roughness: .9 }), 0, 1.31, -.03, g); c.scale.set(1.02, 1.05, 1.02); const face = ball(.16, M(skin), 0, 1.3, .08, g) }
  else { const hair = ball(.2, M(pick([0x2a1a10, 0x111111, 0x6b4a2e, 0xc9a36a]), { roughness: .9 }), 0, 1.36, -.03, g); hair.scale.set(1, .75, 1) }
  const legs = [], arms = [];
  if (!robe) for (const sx of [-.1, .1]) { const l = cyl(.08, .07, .5, M(pick([0x1f2a4a, 0x3a3a44, 0x5a4a3a])), sx, .3, 0, g, 8); legs.push(l) }
  for (const sx of [-.27, .27]) { const a = cyl(.06, .055, .46, M(robe ? body.material.color.getHex() : top), sx, .86, 0, g, 8); arms.push(a) }
  for (const sx of [-.07, .07]) ball(.025, M(0x111111), sx, 1.32, .175, g);
  let cart = null; if (rnd() < .55) { cart = new T.Group(); box(.5, .3, .7, M(0xd8dde8, { roughness: .3, metalness: .7, transparent: true, opacity: .75 }), 0, .55, .7, cart); for (const sx of [-.2, .2]) for (const sz of [.45, .95]) cyl(.06, .06, .05, darkM, sx, .08, sz, cart, 8).rotation.z = Math.PI / 2; box(.5, .04, .04, M(0xff5a3c), 0, .78, .32, cart); for (let i = 0; i < 4; i++)box(.14, .14, .14, M(pick([0xff8a3a, 0x7fd14b, 0xffe14a, 0xff5a8a, 0x3fa7d6])), rnd(-.14, .14), .66 + rnd(0, .1), .7 + rnd(-.2, .2), cart); g.add(cart) }
  scene.add(g); return { g, legs, arms, ph: rnd(0, 6), sp: rnd(.8, 1.25), cart }
}
// a looping path through the store: door -> produce -> bakery -> seafood -> oud -> coffee -> spices -> till -> out
const PATH = [[0, 3.4], [0, -.4], [-6, -2.2], [-6, -7.2], [-1.2, -7.4], [3.8, -7.4], [6.6, -6.4], [6.4, -2.6], [1.2, -2.8], [-3.4, -2.8], [-3.2, -1], [-1.9, .4], [-1.6, 3.2], [-9, 5.2], [-9, 8], [6, 8], [6, 4.4]];
const segL = PATH.map((p, i) => { const q = PATH[(i + 1) % PATH.length]; return Math.hypot(q[0] - p[0], q[1] - p[1]) }), total = segL.reduce((a, b) => a + b, 0);
for (let i = 0; i < 22; i++) { const p = person(pick([0, 0, 0, 1, 2, 0])); p.d = i / 22 * total + rnd(-.6, .6); p.off = rnd(-.35, .35); people.push(p) }
// staff standing at their posts
for (const [x, z, c, ry] of [[-6.2, -10.9, 0x2f8a3a, 0], [-1.1, -10.6, 0xffffff, 0], [3.9, -11, 0x1a78b8, 0], [-6.2, -6, 0xc93a1a, 0], [-1.1, -5.9, 0x4a2c1c, 0], [3.9, -6.1, 0x6a2ad0, 0], [-4.6, -2.1, 0x2f6fd6, 0], [-1.7, -2.1, 0x2f6fd6, 0], [1.2, -2.1, 0x2f6fd6, 0]]) { const s = person(0); s.g.position.set(x, .09, z); s.staff = true; s.g.rotation.y = ry; s.g.children[0].material = M(c, { roughness: .7 }); if (s.cart) { s.g.remove(s.cart); s.cart = null } box(.34, .3, .04, M(0xffffff), 0, .86, .21, s.g); const hat = cyl(.17, .19, .12, M(c), 0, 1.5, 0, s.g, 12); people.push(s) }

// ---------- cars, palms, lamps ----------
function car(x, z, color, ry, special) { const g = new T.Group(); g.position.set(x, 0, z); g.rotation.y = ry; scene.add(g); const pm = M(color, { roughness: .25, metalness: .6 });
  box(1.5, .46, 3, pm, 0, .5, 0, g); const cab = box(1.34, .44, 1.6, pm, 0, .92, -.15, g); box(1.36, .34, 1.3, M(0x9fd8ff, { roughness: .05, metalness: .5, emissive: 0x24405a, emissiveIntensity: .5 }), 0, .94, -.15, g).castShadow = false;
  for (const sx of [-.76, .76]) for (const sz of [-.95, .95]) { const w = cyl(.3, .3, .2, M(0x15151a, { roughness: .9 }), sx, .3, sz, g, 14); w.rotation.z = Math.PI / 2; cyl(.16, .16, .22, steelM, sx, .3, sz, g, 10).rotation.z = Math.PI / 2 }
  for (const sx of [-.5, .5]) { box(.3, .14, .05, M(0xfff6d0, { emissive: 0xfff0b0, emissiveIntensity: 3 }), sx, .56, 1.5, g).castShadow = false; glow(0xfff0b0, 1.3, sx, .56, 1.7, g, .8); box(.3, .12, .05, M(0x7a0a0a, { emissive: 0xff2a2a, emissiveIntensity: 2.5 }), sx, .58, -1.5, g).castShadow = false; glow(0xff3a3a, .9, sx, .58, -1.62, g, .6) }
  if (special) { glow(0xffd35a, 6, 0, 1, 0, g, .5); const st = glow(0xffffff, 1.2, 0, 1.6, 0, g, 1); mist.push({ spark: st, ph: 0 }) } return g }
const carCols = [0xe84a5f, 0x3fa7d6, 0xf2f2f2, 0x2a2a34, 0xf2b01e, 0x2f8a5a, 0x8a5ad0];
[-9.2, -6.9, -2.3, 2.3, 4.6, 9.2].forEach((x, i) => car(x, 5.3, carCols[i], Math.PI));
car(-.1, 5.2, 0xd8b24a, Math.PI, true);
const moving = [car(-20, 9.2, 0x3fa7d6, Math.PI / 2), car(16, 11.6, 0xe84a5f, -Math.PI / 2)];
// delivery truck
{ const g = new T.Group(); g.position.set(11.6, 0, 1.3); g.rotation.y = -Math.PI / 2; scene.add(g); box(1.8, 1.9, 3.6, M(0xfff4e0, { roughness: .5 }), 0, 1.35, -.5, g); box(1.7, 1.2, 1.2, M(0xff7a3a, { roughness: .3, metalness: .3 }), 0, .95, 1.95, g); box(1.72, .5, .05, M(0x9fd8ff, { roughness: .05, emissive: 0x24405a, emissiveIntensity: .5 }), 0, 1.2, 2.56, g); for (const sx of [-.9, .9]) for (const sz of [-1.5, 1.7]) cyl(.4, .4, .26, M(0x15151a), sx, .4, sz, g, 14).rotation.z = Math.PI / 2;
  const lg = new T.Mesh(new T.PlaneGeometry(3, 1.3), new T.MeshBasicMaterial({ map: tex(512, (c, s) => { c.fillStyle = "#fff4e0"; c.fillRect(0, 0, s, s); c.font = "900 120px ui-rounded,system-ui"; c.textAlign = "center"; c.fillStyle = "#ff5a2a"; c.fillText("SOUQ", s / 2, 240); c.font = "700 64px ui-rounded,system-ui"; c.fillStyle = "#3a2a5a"; c.fillText("fresh daily", s / 2, 330) }) })); lg.position.set(.91, 1.4, -.5); lg.rotation.y = Math.PI / 2; g.add(lg) }
function palm(x, z, h) { const g = new T.Group(); g.position.set(x, 0, z); scene.add(g); for (let i = 0; i < 7; i++) { const s = cyl(.17 - i * .012, .2 - i * .012, h / 7 + .04, M(i % 2 ? 0x8a6a48 : 0x7a5a3a, { roughness: 1 }), Math.sin(i * .5) * .12, h / 14 + i * h / 7, 0, g, 8) }
  const lm = M(0x3f9a4a, { roughness: .7, side: T.DoubleSide }); for (let i = 0; i < 9; i++) { const l = new T.Mesh(new T.PlaneGeometry(.5, 2.2, 1, 5), lm); const pos = l.geometry.attributes.position; for (let v = 0; v < pos.count; v++) { const y = pos.getY(v) + 1.1; pos.setZ(v, -y * y * .28); pos.setX(v, pos.getX(v) * (1 - y / 2.6)) } l.geometry.computeVertexNormals(); l.position.set(Math.sin(6 * .5) * .12, h, 0); l.rotation.set(-1.15, i / 9 * Math.PI * 2, 0, "YXZ"); l.geometry.translate(0, 1.1, 0); l.castShadow = true; g.add(l) } spin.push({ sway: g, ph: rnd(0, 6) }) }
[[-14.6, 3.2, 4.4], [-14.6, 8, 5], [-14.6, 12, 4.2], [14.6, 4, 4.8], [14.6, 9, 4.2], [14.6, 12.6, 5.2], [-11.2, 1.3, 3.4], [-11.4, -3, 3.8]].forEach(p => palm(...p));
for (const x of [-11.5, -5.8, 5.8, 11.5]) { cyl(.07, .1, 4.6, darkM, x, 2.3, 7.4, scene, 8); const arm = box(.9, .07, .07, darkM, x, 4.55, 7.05); const hd = box(.5, .1, .3, M(0xfff2c8, { emissive: 0xffe2a0, emissiveIntensity: 3 }), x, 4.48, 6.7); hd.castShadow = false; glow(0xffd98a, 3.2, x, 4.4, 6.7, scene, .8);
  const cone = new T.Mesh(new T.ConeGeometry(2.3, 4.4, 24, 1, true), new T.MeshBasicMaterial({ color: 0xffd98a, transparent: true, opacity: .07, blending: T.AdditiveBlending, depthWrite: false, side: T.DoubleSide })); cone.position.set(x, 2.25, 6.7); scene.add(cone);
  const pool = new T.Mesh(new T.CircleGeometry(2.4, 24), new T.MeshBasicMaterial({ map: glowTex, color: 0xffd08a, transparent: true, opacity: .3, blending: T.AdditiveBlending, depthWrite: false })); pool.rotation.x = -Math.PI / 2; pool.position.set(x, .02, 6.7); scene.add(pool) }
// carts by the door, bollards, bus stop
for (let i = 0; i < 5; i++) { const c = new T.Group(); box(.5, .3, .7, M(0xd8dde8, { roughness: .3, metalness: .7 }), 0, .5, 0, c); box(.5, .04, .04, M(0xff5a3c), 0, .74, -.36, c); c.position.set(3.3 + i * .16, 0, 1.3 + i * .34); scene.add(c) }
for (const x of [-2.6, 2.6]) { cyl(.11, .11, .7, M(0xf2b01e), x, .35, 2.3, scene, 10); glow(0xffd35a, .7, x, .75, 2.3, scene, .7) }
// skyline silhouettes with lit windows
for (let i = 0; i < 16; i++) { const w = rnd(3, 6), h = rnd(6, 18), x = -44 + i * 5.8 + rnd(-1, 1), z = -24 - rnd(0, 10); const b = box(w, h, 4, M(0x1c1638, { roughness: 1 }), x, h / 2, z); b.castShadow = false; const wt = tex(128, (c, s) => { c.fillStyle = "#1c1638"; c.fillRect(0, 0, s, s); for (let y = 0; y < 14; y++)for (let k = 0; k < 6; k++)if (rnd() < .45) { c.fillStyle = pick(["#ffd98a", "#ffb86a", "#9fd8ff", "#fff2c8"]); c.fillRect(8 + k * 20, 6 + y * 9, 10, 5) } }); const f = new T.Mesh(new T.PlaneGeometry(w, h), new T.MeshBasicMaterial({ map: wt })); f.position.set(x, h / 2, z + 2.01); scene.add(f) }
// drifting particles for mist, steam and sparkles
const puffs = []; for (const m of mist) if (!m.spark) for (let i = 0; i < 7; i++) { const s = glow(m.c, rnd(.5, .9), 0, 0, 0, m.g, 0); puffs.push({ s, m, t: rnd(0, 1), dx: rnd(-.9, .9), dz: rnd(-.4, .4) }) }

// ---------- camera fit for a tall phone screen ----------
function fit() { const w = innerWidth, h = innerHeight; R.setSize(w, h, false); cam.aspect = w / h; const tall = h / w; cam.fov = tall > 1.3 ? 40 : 30;
  const hf = 2 * Math.atan(Math.tan(cam.fov * Math.PI / 360) * cam.aspect), need = tall > 1.3 ? 21.5 : 40, dist = Math.min(120, need / (2 * Math.tan(hf / 2)));
  const pitch = 50 * Math.PI / 180, yaw = -22 * Math.PI / 180, tgt = new T.Vector3(0, .6, tall > 1.3 ? -1.2 : -2.5);
  cam.position.set(tgt.x + Math.sin(yaw) * Math.cos(pitch) * dist, tgt.y + Math.sin(pitch) * dist, tgt.z + Math.cos(yaw) * Math.cos(pitch) * dist); cam.lookAt(tgt);
  if (tall > 1.3) cam.setViewOffset(w, h, 0, h * .135, w, h); else cam.clearViewOffset(); cam.updateProjectionMatrix() }
addEventListener("resize", fit); fit();

// ---------- animation ----------
const coins = document.getElementById("coins"); let lastCoin = 0, money = 48.2;
function at(d) { d = ((d % total) + total) % total; let i = 0; while (d > segL[i]) { d -= segL[i]; i++ } const p = PATH[i], q = PATH[(i + 1) % PATH.length], k = d / segL[i]; return { x: p[0] + (q[0] - p[0]) * k, z: p[1] + (q[1] - p[1]) * k, a: Math.atan2(q[0] - p[0], q[1] - p[1]) } }
const calm = matchMedia("(prefers-reduced-motion: reduce)").matches;
function frame(t) {
  const s = t / 1000;
  for (const p of people) { if (p.staff) { const w = Math.sin(s * 3 + p.ph); p.arms[0].rotation.x = -.5 + w * .35; p.arms[1].rotation.x = -.5 - w * .35; p.g.position.y = .09 + Math.abs(Math.sin(s * 1.5 + p.ph)) * .015; continue }
    p.d += (calm ? 0 : 1) * p.sp * .022; const a = at(p.d), sw = Math.sin(s * 7 * p.sp + p.ph); p.g.position.set(a.x + Math.cos(a.a) * p.off, .09 + Math.abs(sw) * .035, a.z - Math.sin(a.a) * p.off);
    let da = a.a - p.g.rotation.y; while (da > Math.PI) da -= 2 * Math.PI; while (da < -Math.PI) da += 2 * Math.PI; p.g.rotation.y += da * .15; p.g.rotation.z = sw * .03;
    p.legs.forEach((l, i) => { l.rotation.x = (i ? -1 : 1) * sw * .6 }); p.arms.forEach((m, i) => { m.rotation.x = p.cart ? -1.1 : (i ? 1 : -1) * sw * .5 }) }
  moving[0].position.x = ((s * 3.2 + 20) % 46) - 23; moving[1].position.x = 23 - ((s * 2.6 + 8) % 46);
  for (const f of flick) f.opacity = .9 + Math.sin(s * 9) * .05 + (Math.sin(s * 37) > .96 ? -.35 : 0);
  for (const o of spin) { if (o.sway) o.sway.rotation.z = Math.sin(s * .8 + o.ph) * .025; else { o.rotation.y = s * .8; o.position.y = 1.25 + Math.sin(s * 2) * .05 } }
  for (const m of mist) if (m.spark) { const k = .5 + .5 * Math.sin(s * 3 + m.ph); m.spark.material.opacity = .25 + k * .75; m.spark.scale.setScalar((m.spark.userData.b || (m.spark.userData.b = m.spark.scale.x)) * (.7 + k * .6)) }
  for (const p of puffs) { p.t = (p.t + .004) % 1; const k = p.t; p.s.position.set(p.m.x + p.dx * (p.m.up ? k * .5 : 1), p.m.y + (p.m.up ? k * 1.3 : Math.sin(k * 6.28) * .06), p.m.z + p.dz); p.s.material.opacity = Math.sin(k * Math.PI) * (p.m.up ? .32 : .22); p.s.scale.setScalar((p.m.up ? .5 : .9) + k * .8) }
  if (!calm && t - lastCoin > 520) { lastCoin = t; const v = new T.Vector3(-4.6 + Math.floor(rnd(0, 3)) * 2.9, 1.6, -1.5).project(cam), e = document.createElement("div"); e.className = "fly"; const amt = Math.floor(rnd(8, 42)); e.textContent = "+" + amt + "K"; e.style.left = ((v.x + 1) / 2 * innerWidth - 16) + "px"; e.style.top = ((1 - v.y) / 2 * innerHeight) + "px"; coins.appendChild(e); setTimeout(() => e.remove(), 1500); money += amt / 1000; document.getElementById("coin").textContent = money.toFixed(1) + "M" }
  R.render(scene, cam); requestAnimationFrame(frame)
}
requestAnimationFrame(frame);
window.__sample = { people: people.length, tris: () => R.info.render.triangles, calls: () => R.info.render.calls };
