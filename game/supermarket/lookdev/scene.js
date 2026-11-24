// Look development for the supermarket: everything is built from code (vertex-coloured solids, a drawn floor),
// so every edge stays sharp at any screen size. Open index.html; add ?shot=front|aisle|lot for other views.
(() => {
const T = THREE, q = new URLSearchParams(location.search);
const canvas = document.getElementById('c');
const renderer = new T.WebGLRenderer({ canvas, antialias: true, powerPreference: 'high-performance' });
const DPR = Math.min(+q.get('dpr') || window.devicePixelRatio || 1, 3);
renderer.setPixelRatio(DPR); renderer.shadowMap.enabled = true; renderer.shadowMap.type = T.PCFSoftShadowMap;
const scene = new T.Scene(); scene.background = new T.Color('#8fd0f0');

// ---------- solid builder: many small coloured parts merged into one mesh ----------
class Geo {
  constructor() { this.p = []; this.n = []; this.c = []; this.i = []; this.m = new T.Matrix4(); this.col = new T.Color('#fff'); this.shade = 0.16; }
  color(h) { this.col = new T.Color(h); return this; }
  at(x = 0, y = 0, z = 0, ry = 0, rx = 0, rz = 0) { this.m = new T.Matrix4().makeRotationFromEuler(new T.Euler(rx, ry, rz, 'YXZ')).setPosition(x, y, z); return this; }
  _v(x, y, z, nx, ny, nz, k = 1) {
    const v = new T.Vector3(x, y, z).applyMatrix4(this.m), nn = new T.Vector3(nx, ny, nz).transformDirection(this.m);
    this.p.push(v.x, v.y, v.z); this.n.push(nn.x, nn.y, nn.z); this.c.push(this.col.r * k, this.col.g * k, this.col.b * k); return this.p.length / 3 - 1;
  }
  // box centred on x,z with its base at y; lower edge slightly darker so parts sit on each other
  box(w, h, d, x = 0, y = 0, z = 0) {
    const X = w / 2, Z = d / 2, lo = 1 - this.shade, f = [[0, 0, 1], [0, 0, -1], [1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0]];
    for (const [nx, ny, nz] of f) {
      let a;
      if (nz) a = [[-X * nz, 0, Z * nz], [X * nz, 0, Z * nz], [X * nz, h, Z * nz], [-X * nz, h, Z * nz]];
      else if (nx) a = [[X * nx, 0, Z * nx], [X * nx, 0, -Z * nx], [X * nx, h, -Z * nx], [X * nx, h, Z * nx]];
      else a = ny > 0 ? [[-X, h, Z], [X, h, Z], [X, h, -Z], [-X, h, -Z]] : [[-X, 0, -Z], [X, 0, -Z], [X, 0, Z], [-X, 0, Z]];
      const s = this.p.length / 3; for (const v of a) this._v(v[0] + x, v[1] + y, v[2] + z, nx, ny, nz, ny ? (ny > 0 ? 1.04 : lo) : (v[1] === 0 ? lo : 1));
      this.i.push(s, s + 1, s + 2, s, s + 2, s + 3);
    }
    return this;
  }
  // upright cylinder / cone, base at y
  cyl(r0, r1, h, x = 0, y = 0, z = 0, seg = 14, cap = true) {
    const s = this.p.length / 3, lo = 1 - this.shade;
    for (let k = 0; k <= seg; k++) { const a = k / seg * Math.PI * 2, cx = Math.cos(a), sz = Math.sin(a); this._v(x + cx * r0, y, z + sz * r0, cx, (r0 - r1) / h, sz, lo); this._v(x + cx * r1, y + h, z + sz * r1, cx, (r0 - r1) / h, sz, 1); }
    for (let k = 0; k < seg; k++) { const a = s + k * 2; this.i.push(a, a + 1, a + 3, a, a + 3, a + 2); }
    if (cap && r1 > 0) { const c = this._v(x, y + h, z, 0, 1, 0, 1.04); const t = this.p.length / 3; for (let k = 0; k <= seg; k++) { const a = k / seg * Math.PI * 2; this._v(x + Math.cos(a) * r1, y + h, z + Math.sin(a) * r1, 0, 1, 0, 1.04); } for (let k = 0; k < seg; k++) this.i.push(c, t + k + 1, t + k); }
    return this;
  }
  // ellipsoid centred at x,y,z
  ball(rx, ry, rz, x = 0, y = 0, z = 0, seg = 14, rings = 9) {
    const s = this.p.length / 3, lo = 1 - this.shade;
    for (let j = 0; j <= rings; j++) { const v = j / rings * Math.PI, sy = Math.cos(v), sr = Math.sin(v); for (let k = 0; k <= seg; k++) { const a = k / seg * Math.PI * 2, nx = Math.cos(a) * sr, nz = Math.sin(a) * sr; this._v(x + nx * rx, y + sy * ry, z + nz * rz, nx / rx, sy / ry, nz / rz, lo + (1.04 - lo) * (sy * 0.5 + 0.5)); } }
    for (let j = 0; j < rings; j++) for (let k = 0; k < seg; k++) { const a = s + j * (seg + 1) + k, b = a + seg + 1; this.i.push(a, a + 1, b + 1, a, b + 1, b); }
    return this;
  }
  mesh(mat) {
    const g = new T.BufferGeometry(); g.setAttribute('position', new T.Float32BufferAttribute(this.p, 3)); g.setAttribute('normal', new T.Float32BufferAttribute(this.n, 3)); g.setAttribute('color', new T.Float32BufferAttribute(this.c, 3)); g.setIndex(this.i);
    const m = new T.Mesh(g, mat); m.castShadow = true; m.receiveShadow = true; return m;
  }
}
// soft, bright shading: full light wraps round the form and the sky fills the shade, so nothing goes muddy
const solid = new T.MeshLambertMaterial({ vertexColors: true });
solid.onBeforeCompile = s => { s.fragmentShader = s.fragmentShader.replace('#include <dithering_fragment>', 'float rimK = pow(1.0 - clamp(dot(normalize(vNormal), normalize(vViewPosition)), 0.0, 1.0), 3.0); gl_FragColor.rgb += rimK * 0.07 * vec3(0.85, 0.93, 1.0);\n#include <dithering_fragment>'); };
const glow = new T.MeshBasicMaterial({ vertexColors: true });
const glass = new T.MeshLambertMaterial({ color: '#bfe6ff', transparent: true, opacity: 0.32, depthWrite: false });
const rnd = (seed => () => (seed = (seed * 1664525 + 1013904223) >>> 0) / 4294967296)(7);
const pick = a => a[Math.floor(rnd() * a.length)];
let host = scene;
// crisp lettering: drawn as vector text on a small board
function board(text, w, h, bg, fg, x, y, z, icon) {
  const c = document.createElement('canvas'), k = 256; c.width = Math.round(w * k); c.height = Math.round(h * k); const g = c.getContext('2d');
  g.fillStyle = bg; g.fillRect(0, 0, c.width, c.height); g.strokeStyle = 'rgba(255,255,255,.95)'; g.lineWidth = k * 0.035; g.strokeRect(k * 0.05, k * 0.05, c.width - k * 0.1, c.height - k * 0.1);
  g.fillStyle = fg; g.textAlign = 'center'; g.textBaseline = 'middle'; let fs = h * k * 0.6; g.font = `900 ${fs}px 'Arial Black', 'Helvetica Neue', Arial, sans-serif`; const mw = c.width - k * 0.3; const tw = g.measureText(text).width; if (tw > mw) { fs *= mw / tw; g.font = `900 ${fs}px 'Arial Black', 'Helvetica Neue', Arial, sans-serif`; }
  g.shadowColor = 'rgba(0,0,0,.28)'; g.shadowOffsetY = k * 0.02; g.fillText(text, c.width / 2, c.height / 2 + k * 0.01);
  const t = new T.CanvasTexture(c); t.colorSpace = T.SRGBColorSpace; t.anisotropy = 8; const m = new T.Mesh(new T.PlaneGeometry(w, h), new T.MeshBasicMaterial({ map: t })); m.position.set(x, y, z); host.add(m); return m;
}

// ---------- light ----------
scene.add(new T.HemisphereLight('#ffffff', '#c9c2b4', 1.55));
const sun = new T.DirectionalLight('#fff4e0', 2.1); sun.position.set(-9, 22, 12); sun.castShadow = true;
sun.shadow.mapSize.set(4096, 4096); const sc = sun.shadow.camera; sc.left = -22; sc.right = 22; sc.top = 30; sc.bottom = -30; sc.near = 1; sc.far = 80; sun.shadow.bias = -0.0006; sun.shadow.normalBias = 0.03; sun.shadow.radius = 3.5; sun.shadow.intensity = 0.55;
sun.target.position.set(0, 0, -8); scene.add(sun, sun.target);

// ---------- drawn ground: tiles, section mats, lot markings (vector drawing, so the lines are sharp) ----------
const W = 14, STORE_Z0 = 0, STORE_Z1 = -27, LOT_Z = 16, PX = 96;
function ground() {
  const gw = 30, z0 = STORE_Z1 - 4, z1 = LOT_Z, gh = z1 - z0, c = document.createElement('canvas'); c.width = gw * PX; c.height = gh * PX; const g = c.getContext('2d');
  const X = x => (x + gw / 2) * PX, Z = z => (z - z0) * PX, S = v => v * PX;
  const rr = (x, z, w, d, r) => { g.beginPath(); g.roundRect(X(x - w / 2), Z(z - d / 2), S(w), S(d), S(r)); };
  // grass and asphalt
  g.fillStyle = '#7cc45a'; g.fillRect(0, 0, c.width, c.height);
  for (let k = 0; k < 2600; k++) { g.fillStyle = pick(['#86cc62', '#72bb52', '#8fd26a']); g.beginPath(); g.ellipse(rnd() * c.width, rnd() * c.height, S(0.25 + rnd() * 0.5), S(0.12 + rnd() * 0.2), rnd() * 3, 0, 7); g.fill(); }
  g.fillStyle = '#4b5263'; rr(0, (2.6 + LOT_Z) / 2 + 2, 26, LOT_Z - 2.6 + 4, 1.2); g.fill();
  for (let k = 0; k < 900; k++) { g.fillStyle = rnd() < 0.5 ? 'rgba(255,255,255,.035)' : 'rgba(0,0,0,.05)'; g.beginPath(); g.arc(X(-13 + rnd() * 26), Z(2.6 + rnd() * (LOT_Z - 2.6)), S(0.03 + rnd() * 0.1), 0, 7); g.fill(); }
  // road dashes and parking bays
  g.fillStyle = '#ffd24a'; for (let x = -12; x < 12; x += 3) { rr(x + 1, 4.3, 1.5, 0.16, 0.08); g.fill(); }
  g.strokeStyle = '#f4f6fb'; g.lineWidth = S(0.13); g.lineCap = 'round';
  for (let r = 0; r < 2; r++) for (let k = 0; k <= 8; k++) { const x = -12 + k * 3, z = 6.4 + r * 5.6; g.beginPath(); g.moveTo(X(x), Z(z)); g.lineTo(X(x), Z(z + 4.6)); g.stroke(); }
  // pavement
  g.fillStyle = '#d9d4c8'; rr(0, 1.3, 26, 2.6, 0.35); g.fill(); g.strokeStyle = 'rgba(0,0,0,.10)'; g.lineWidth = S(0.03);
  for (let x = -13; x <= 13; x += 1.3) { g.beginPath(); g.moveTo(X(x), Z(0.05)); g.lineTo(X(x), Z(2.55)); g.stroke(); }
  g.fillStyle = '#c7c1b3'; g.fillRect(X(-13), Z(2.45), S(26), S(0.16));
  // shop floor: warm cream tiles with fine joints and a soft sheen
  g.fillStyle = '#f6efdf'; g.fillRect(X(-W / 2), Z(STORE_Z1), S(W), S(STORE_Z0 - STORE_Z1));
  for (let ix = 0; ix < W; ix++) for (let iz = 0; iz < 27; iz++) { if ((ix + iz) % 2) { g.fillStyle = '#efe6d2'; g.fillRect(X(-W / 2 + ix), Z(STORE_Z1 + iz), S(1), S(1)); } }
  g.strokeStyle = 'rgba(120,100,70,.22)'; g.lineWidth = S(0.022);
  for (let x = -W / 2; x <= W / 2; x += 1) { g.beginPath(); g.moveTo(X(x), Z(STORE_Z1)); g.lineTo(X(x), Z(STORE_Z0)); g.stroke(); }
  for (let z = STORE_Z1; z <= STORE_Z0; z += 1) { g.beginPath(); g.moveTo(X(-W / 2), Z(z)); g.lineTo(X(W / 2), Z(z)); g.stroke(); }
  // section mats: a coloured rounded field with a white keyline
  for (const d of DEPTS) {
    g.fillStyle = d.mat; rr(d.x, d.z + 1.2, 6.1, 6.6, 0.5); g.fill();
    g.strokeStyle = d.col; g.lineWidth = S(0.16); rr(d.x, d.z + 1.2, 6.1, 6.6, 0.5); g.stroke();
    g.strokeStyle = 'rgba(255,255,255,.9)'; g.lineWidth = S(0.05); g.setLineDash([S(0.35), S(0.25)]); rr(d.x, d.z + 1.2, 5.6, 6.1, 0.35); g.stroke(); g.setLineDash([]);
  }
  // checkout lane arrows and the entrance mat
  g.fillStyle = '#d43b3b'; rr(0, -0.9, 3.4, 1.3, 0.2); g.fill(); g.strokeStyle = '#fff'; g.lineWidth = S(0.05); rr(0, -0.9, 3.1, 1.0, 0.14); g.stroke();
  g.fillStyle = 'rgba(60,160,90,.85)'; for (let k = 0; k < 5; k++) { const x = -5.4 + k * 2.7 + 0.85; g.beginPath(); g.moveTo(X(x), Z(-2.2)); g.lineTo(X(x - 0.28), Z(-1.75)); g.lineTo(X(x + 0.28), Z(-1.75)); g.fill(); g.fillRect(X(x - 0.09), Z(-1.78), S(0.18), S(0.5)); }
  const t = new T.CanvasTexture(c); t.colorSpace = T.SRGBColorSpace; t.anisotropy = renderer.capabilities.getMaxAnisotropy(); t.generateMipmaps = true; t.minFilter = T.LinearMipmapLinearFilter;
  const m = new T.Mesh(new T.PlaneGeometry(gw, gh), new T.MeshLambertMaterial({ map: t })); m.rotation.x = -Math.PI / 2; m.position.set(0, 0, (z0 + z1) / 2); m.receiveShadow = true; scene.add(m);
}
const DEPTS = [
  { id: 'produce', x: -3.5, z: -9, col: '#39b54a', mat: '#d9f2cf' }, { id: 'bakery', x: 3.5, z: -9, col: '#f29b1d', mat: '#ffe9c4' },
  { id: 'dairy', x: -3.5, z: -17.5, col: '#2f8fe6', mat: '#d3e9ff' }, { id: 'snacks', x: 3.5, z: -17.5, col: '#e8438b', mat: '#ffd9e8' },
];

// ---------- fixtures ----------
const WOOD = '#c98a4b', WOOD2 = '#a96d35', STEEL = '#cfd6de', WHITE = '#fbfbf6', DARK = '#2c3440';
function awning(g, x, z, w, a, b) { // striped canopy on two posts
  g.color(STEEL).box(0.09, 2.5, 0.09, x - w / 2 + 0.1, 0, z + 0.75).box(0.09, 2.5, 0.09, x + w / 2 - 0.1, 0, z + 0.75);
  const n = Math.round(w / 0.45); for (let k = 0; k < n; k++) { const sx = x - w / 2 + (k + 0.5) * (w / n); g.color(k % 2 ? a : b).at(sx, 2.72, z + 0.3, 0, 0.42).box(w / n, 0.07, 1.35).at(sx, 2.36, z + 0.86).box(w / n, 0.2, 0.06).at(); }
  g.at();
}
function sign(g, x, y, z, w, col, name) { // hanging section board
  g.color(DARK).box(0.05, 0.5, 0.05, x - w / 2 + 0.3, y + 0.62, z).box(0.05, 0.5, 0.05, x + w / 2 - 0.3, y + 0.62, z);
  g.color(col).box(w, 0.72, 0.14, x, y - 0.03, z);
  const b = board(name, w - 0.1, 0.62, col, '#ffffff', x, y + 0.33, z - 0.075); b.rotation.y = Math.PI;
}
const dots = cols => (g, x, y, z) => cols.forEach((c, k) => g.color(c).ball(0.15, 0.15, 0.06, x + (k - (cols.length - 1) / 2) * 0.42, y, z));
function produce(g, cx, cz) {
  const fruit = [['#e5352c', '#f0584a'], ['#ff9a1f', '#ffb347'], ['#7ac943', '#9bd95e'], ['#ffd93b', '#ffe873'], ['#8e44ad', '#a65fc2'], ['#f4f0e0', '#e8e0c8']];
  for (let k = 0; k < 3; k++) {
    const x = cx - 1.95 + k * 1.95, z = cz + 3.3;
    // sloped two-tier stand
    g.color(WOOD2).box(1.75, 0.5, 1.2, x, 0, z).color(WOOD).box(1.75, 0.08, 1.24, x, 0.5, z);
    for (let t = 0; t < 2; t++) {
      const y = 0.58 + t * 0.42, zz = z - 0.12 + t * 0.42 - 0.3, f = fruit[(k * 2 + t) % fruit.length];
      g.color(WOOD).box(1.7, 0.24, 0.6, x, y, zz).color(WOOD2).box(1.74, 0.07, 0.05, x, y + 0.22, zz - 0.3).box(0.05, 0.3, 0.6, x - 0.86, y, zz).box(0.05, 0.3, 0.6, x + 0.86, y, zz).box(0.04, 0.26, 0.6, x, y, zz);
      for (let a = 0; a < 2; a++) for (let i = 0; i < 4; i++) for (let j = 0; j < 3; j++) g.color(f[(i + j) % 2]).ball(0.115, 0.11, 0.115, x - 0.63 + a * 0.86 + i * 0.14 + (j % 2) * 0.05 - 0.03, y + 0.3 + (i % 2) * 0.05 + (j === 1 ? 0.06 : 0), zz - 0.17 + j * 0.17, 10, 6);
      g.color('#fff36b').box(0.26, 0.17, 0.03, x - 0.42, y + 0.22, zz - 0.335).box(0.26, 0.17, 0.03, x + 0.42, y + 0.22, zz - 0.335);
    }
  }
  awning(g, cx, cz + 3.1, 5.9, '#39b54a', WHITE);
  // crates of greens and a weighing scale
  for (const [dx, dz] of [[-2.55, 1.2], [2.55, 1.2]]) { g.color(WOOD2).box(0.75, 0.42, 0.55, cx + dx, 0, cz + dz); g.color(WOOD).box(0.79, 0.07, 0.59, cx + dx, 0.36, cz + dz); for (let i = 0; i < 6; i++) g.color(pick(['#5fbf3f', '#8fd65a', '#ff9a1f'])).ball(0.13, 0.11, 0.13, cx + dx - 0.22 + (i % 3) * 0.22, 0.5, cz + dz - 0.1 + Math.floor(i / 3) * 0.2, 9, 6); }
  sign(g, cx, 2.95, cz + 4.3, 3.9, '#39b54a', 'FRESH PRODUCE');
}
function bakery(g, cx, cz) {
  const z = cz + 3.45;
  for (let k = 0; k < 2; k++) { // open bread shelves
    const x = cx - 1.95 + k * 1.95; g.color(WOOD2).box(0.08, 2.1, 0.6, x - 0.85, 0, z).box(0.08, 2.1, 0.6, x + 0.85, 0, z).color('#8a5628').box(1.78, 2.1, 0.06, x, 0, z + 0.3);
    for (let s = 0; s < 4; s++) { const y = 0.3 + s * 0.5; g.color(WOOD).at(x, y, z, 0, 0.16).box(1.66, 0.06, 0.6).at();
      for (let i = 0; i < 5; i++) { const bx = x - 0.62 + i * 0.31; if (s % 2) g.color(pick(['#d99a4e', '#c9833a', '#e6b06a'])).ball(0.13, 0.11, 0.2, bx, y + 0.17, z - 0.02, 10, 6); else g.color(pick(['#e0a85a', '#cf8f3f'])).at(bx, y + 0.08, z - 0.02, 0, 0.16).box(0.2, 0.2, 0.42).color('#f2cf8f').box(0.16, 0.05, 0.36, 0, 0.19, 0).at(); } }
  }
  // glass cake counter
  const x = cx + 1.95; g.color(WHITE).box(1.8, 0.85, 0.75, x, 0, z - 0.05).color('#f29b1d').box(1.84, 0.1, 0.79, x, 0.42, z - 0.05).color(STEEL).box(1.84, 0.05, 0.79, x, 0.85, z - 0.05);
  for (let i = 0; i < 4; i++) { const c = ['#ff7aa8', '#fff3d6', '#7a4a2a', '#ffd93b'][i]; g.color(c).cyl(0.17, 0.17, 0.14, x - 0.6 + i * 0.4, 0.9, z - 0.05, 14).color(WHITE).cyl(0.175, 0.175, 0.03, x - 0.6 + i * 0.4, 1.04, z - 0.05, 14).color('#e5352c').ball(0.04, 0.04, 0.04, x - 0.6 + i * 0.4, 1.1, z - 0.05, 8, 5); }
  const gl = new T.Mesh(new T.BoxGeometry(1.78, 0.5, 0.7), glass); gl.position.set(x, 1.15, z - 0.05); host.add(gl); g.color(STEEL).box(1.84, 0.04, 0.79, x, 1.4, z - 0.05);
  awning(g, cx, cz + 3.1, 5.9, '#f29b1d', WHITE);
  g.color(WOOD2).cyl(0.3, 0.36, 0.5, cx - 2.6, 0, cz + 1.2, 12); for (let i = 0; i < 7; i++) g.color('#e0a85a').at(cx - 2.6 + (i - 3) * 0.06, 0.25, cz + 1.2 + (i % 2) * 0.08 - 0.04, 0, 0, (i - 3) * 0.07).cyl(0.045, 0.045, 0.75, 0, 0, 0, 7).at();
  sign(g, cx, 2.95, cz + 4.3, 3.9, '#f29b1d', 'BAKERY');
}
function fridgeRun(g, cx, cz) {
  const z = cz + 3.5;
  for (let k = 0; k < 3; k++) {
    const x = cx - 1.95 + k * 1.95; g.color(WHITE).box(1.85, 0.3, 0.7, x, 0, z + 0.05).box(0.07, 2.0, 0.7, x - 0.89, 0.3, z + 0.05).box(0.07, 2.0, 0.7, x + 0.89, 0.3, z + 0.05).color('#2f8fe6').box(1.89, 0.26, 0.74, x, 2.3, z + 0.05).color('#eaf6ff').box(1.85, 2.0, 0.06, x, 0.3, z + 0.37);
    for (let s = 0; s < 4; s++) { const y = 0.34 + s * 0.46; g.color(STEEL).box(1.7, 0.04, 0.5, x, y, z);
      for (let i = 0; i < 8; i++) { const bx = x - 0.74 + i * 0.21, c = [['#ffffff', '#2f8fe6'], ['#fff3b0', '#f29b1d'], ['#ffd9e8', '#e8438b'], ['#d9f2cf', '#39b54a']][(s + k) % 4];
        if (s % 2) g.color(c[0]).box(0.15, 0.3, 0.15, bx, y + 0.04, z - 0.1).color(c[1]).box(0.155, 0.1, 0.155, bx, y + 0.14, z - 0.1).color(c[0]).box(0.07, 0.05, 0.07, bx, y + 0.34, z - 0.1);
        else g.color(c[0]).cyl(0.075, 0.06, 0.22, bx, y + 0.04, z - 0.1, 9).color(c[1]).cyl(0.078, 0.078, 0.03, bx, y + 0.26, z - 0.1, 9); } }
    const gl = new T.Mesh(new T.BoxGeometry(1.72, 1.9, 0.04), glass); gl.position.set(x, 1.25, z - 0.32); host.add(gl);
    g.color(STEEL).box(0.05, 1.94, 0.06, x - 0.88, 0.28, z - 0.32).box(0.05, 1.94, 0.06, x + 0.88, 0.28, z - 0.32).box(0.05, 1.94, 0.06, x, 0.28, z - 0.32).color(DARK).box(0.03, 0.5, 0.05, x - 0.1, 1.0, z - 0.37).box(0.03, 0.5, 0.05, x + 0.1, 1.0, z - 0.37);
    g.color('#dff2ff'); const lamp = new Geo(); lamp.color('#f4fbff').box(1.6, 0.05, 0.1, x, 2.2, z - 0.2); host.add(lamp.mesh(glow));
  }
  sign(g, cx, 2.95, cz + 4.3, 3.9, '#2f8fe6', 'DAIRY');
}
function gondolas(g, cx, cz) {
  const z = cz + 3.5, pal = [['#e5352c', '#ffd93b'], ['#2f8fe6', '#ffffff'], ['#ff9a1f', '#7a4a2a'], ['#39b54a', '#fff36b'], ['#8e44ad', '#ffd9e8'], ['#00b3b3', '#ffffff']];
  for (let k = 0; k < 3; k++) {
    const x = cx - 1.95 + k * 1.95; g.color('#e9edf2').box(1.86, 2.15, 0.1, x, 0, z + 0.3).color(STEEL).box(1.9, 0.16, 0.62, x, 0, z).color('#e8438b').box(1.9, 0.14, 0.64, x, 2.15, z + 0.02);
    for (let s = 0; s < 4; s++) { const y = 0.16 + s * 0.5; g.color(WHITE).box(1.84, 0.045, 0.56, x, y, z).color('#ffec5c').box(1.84, 0.07, 0.02, x, y - 0.02, z - 0.28);
      let bx = x - 0.86; while (bx < x + 0.8) { const p = pal[Math.floor(rnd() * pal.length)], kind = (s + k) % 3, w = kind === 0 ? 0.2 : kind === 1 ? 0.14 : 0.17, n = 2 + Math.floor(rnd() * 3);
        for (let i = 0; i < n && bx < x + 0.84; i++) {
          if (kind === 0) g.color(p[0]).box(w - 0.02, 0.36, 0.13, bx + w / 2, y + 0.045, z - 0.14).color(p[1]).box(w - 0.015, 0.12, 0.135, bx + w / 2, y + 0.17, z - 0.14);
          else if (kind === 1) g.color(p[0]).cyl(0.06, 0.06, 0.2, bx + w / 2, y + 0.045, z - 0.14, 9).color(p[1]).cyl(0.062, 0.062, 0.07, bx + w / 2, y + 0.1, z - 0.14, 9).color(STEEL).cyl(0.05, 0.05, 0.02, bx + w / 2, y + 0.245, z - 0.14, 9);
          else g.color(p[0]).at(bx + w / 2, y + 0.045, z - 0.14).ball(0.085, 0.16, 0.06, 0, 0.17, 0, 9, 6).color(p[1]).box(0.1, 0.08, 0.065, 0, 0.13, 0).at();
          bx += w; } bx += 0.03; } }
  }
  g.color('#e8438b').box(0.7, 1.3, 0.7, cx - 2.55, 0, cz + 1.25).color(WHITE).box(0.74, 0.1, 0.74, cx - 2.55, 0.6, cz + 1.25); for (let i = 0; i < 9; i++) g.color(pick(['#ffd93b', '#e5352c', '#2f8fe6'])).ball(0.1, 0.13, 0.07, cx - 2.75 + (i % 3) * 0.2, 1.42, cz + 1.05 + Math.floor(i / 3) * 0.2, 8, 5);
  sign(g, cx, 2.95, cz + 4.3, 3.9, '#e8438b', 'SNACKS');
}
function checkout(g, x, z, n, open) {
  g.color(WHITE).box(0.85, 0.82, 2.3, x, 0, z).color('#d43b3b').box(0.89, 0.12, 2.34, x, 0.3, z).color(STEEL).box(0.89, 0.05, 2.34, x, 0.82, z).color(DARK).box(0.6, 0.02, 1.3, x, 0.875, z - 0.35);
  g.color(DARK).box(0.34, 0.3, 0.3, x - 0.1, 0.87, z + 0.75).color('#7de0ff'); const scr = new Geo(); scr.color(open ? '#8dffb0' : '#7db8ff').at(x - 0.1, 1.2, z + 0.75, 0, -0.3).box(0.4, 0.3, 0.04).at(); host.add(scr.mesh(glow));
  g.color(STEEL).box(0.05, 1.9, 0.05, x - 0.36, 0.87, z + 1.05); const lamp = new Geo(); lamp.color(open ? '#52e07a' : '#ff5a5a').box(0.46, 0.46, 0.1, x - 0.36, 2.75, z + 1.05); host.add(lamp.mesh(glow)); g.color(WHITE).box(0.52, 0.52, 0.06, x - 0.36, 2.72, z + 1.02);
  for (let i = 0; i < 3; i++) g.color(pick(['#e5352c', '#ffd93b', '#2f8fe6', '#39b54a'])).box(0.16, 0.2, 0.14, x - 0.12 + i * 0.13, 0.895, z - 0.6 + i * 0.3);
  g.color('#c9a36b').box(0.5, 0.42, 0.3, x, 0.87, z + 0.25).color('#b58c52').box(0.5, 0.05, 0.3, x, 1.29, z + 0.25);
}
function person(g, x, z, ry, o) { // toy-like figure: large head, short body
  const skin = o.skin || pick(['#f6c9a0', '#e9b184', '#c98d5e', '#8f5b3a', '#fbd6b5']), top = o.top, bot = o.bot || pick(['#3b4a6b', '#55607a', '#7a5a3c', '#2f3642']), hair = o.hair || pick(['#3a2a20', '#6b4423', '#111418', '#c9a24a', '#8a3b22']), sw = o.walk ? 1 : 0;
  g.at(x, 0, z, ry);
  g.color('#2a2f38').at(x, 0, z, ry).box(0.17, 0.09, 0.3, -0.13, 0, 0.03 + sw * 0.14).box(0.17, 0.09, 0.3, 0.13, 0, 0.03 - sw * 0.14);
  g.color(bot).cyl(0.1, 0.11, 0.4, -0.13, 0.08, sw * 0.1, 10).cyl(0.1, 0.11, 0.4, 0.13, 0.08, -sw * 0.1, 10);
  g.color(top).ball(0.3, 0.36, 0.23, 0, 0.82, 0, 14, 9); g.color(bot).cyl(0.26, 0.27, 0.12, 0, 0.44, 0, 12);
  if (o.apron) { g.color(o.apron).box(0.36, 0.5, 0.05, 0, 0.5, 0.2).color(WHITE).box(0.14, 0.12, 0.06, 0, 0.72, 0.2); }
  const ax = o.push ? 0.5 : 0; // arms forward when pushing a cart
  for (const s of [-1, 1]) { g.color(top).at(x, 0, z, ry).at(...[0, 0, 0]); const m = new T.Matrix4().makeRotationFromEuler(new T.Euler(0, ry, 0)).setPosition(x, 0, z); g.m = m.clone().multiply(new T.Matrix4().makeRotationFromEuler(new T.Euler(-1.1 * ax - sw * s * 0.35, 0, s * -0.16)).setPosition(s * 0.33, 1.0, 0)); g.color(top).cyl(0.085, 0.09, 0.26, 0, -0.26, 0, 9).color(skin).cyl(0.07, 0.08, 0.2, 0, -0.46, 0, 9).ball(0.085, 0.085, 0.085, 0, -0.5, 0, 9, 6); }
  g.at(x, 0, z, ry);
  g.color(skin).cyl(0.1, 0.1, 0.08, 0, 1.12, 0, 9).ball(0.33, 0.31, 0.3, 0, 1.47, 0, 16, 11);
  g.color(hair).ball(0.345, 0.26, 0.32, 0, 1.56, -0.035, 16, 8); if (o.long) g.ball(0.3, 0.3, 0.16, 0, 1.3, -0.2, 12, 7);
  g.color('#20242c').ball(0.04, 0.055, 0.03, -0.12, 1.45, 0.28, 8, 5).ball(0.04, 0.055, 0.03, 0.12, 1.45, 0.28, 8, 5).color('#f08a8a').ball(0.05, 0.03, 0.02, -0.2, 1.36, 0.24, 8, 4).ball(0.05, 0.03, 0.02, 0.2, 1.36, 0.24, 8, 4);
  if (o.cap) g.color(o.cap).ball(0.35, 0.16, 0.33, 0, 1.68, 0, 16, 6).box(0.4, 0.04, 0.24, 0, 1.6, 0.34);
  g.at();
}
function cart(g, x, z, ry, full) {
  g.at(x, 0, z, ry); g.color(STEEL);
  for (const [dx, dz] of [[-0.24, -0.36], [0.24, -0.36], [-0.24, 0.36], [0.24, 0.36]]) g.color(DARK).cyl(0.07, 0.07, 0.06, dx, 0, dz, 8).color(STEEL).box(0.03, 0.34, 0.03, dx, 0.06, dz);
  g.color(STEEL).box(0.56, 0.03, 0.84, 0, 0.4, 0); for (let k = 0; k < 6; k++) { g.box(0.02, 0.4, 0.02, -0.28, 0.42, -0.42 + k * 0.168).box(0.02, 0.4, 0.02, 0.28, 0.42, -0.42 + k * 0.168); } for (let k = 0; k < 4; k++) g.box(0.02, 0.4, 0.02, -0.28 + k * 0.187, 0.42, 0.42).box(0.02, 0.4, 0.02, -0.28 + k * 0.187, 0.42, -0.42);
  g.box(0.6, 0.03, 0.03, 0, 0.82, 0.42).box(0.6, 0.03, 0.03, 0, 0.82, -0.42).box(0.03, 0.03, 0.87, -0.28, 0.82, 0).box(0.03, 0.03, 0.87, 0.28, 0.82, 0).color('#d43b3b').box(0.62, 0.05, 0.05, 0, 0.95, -0.5).color(STEEL).box(0.03, 0.16, 0.03, -0.27, 0.82, -0.48).box(0.03, 0.16, 0.03, 0.27, 0.82, -0.48);
  if (full) for (let i = 0; i < 7; i++) { const c = pick(['#e5352c', '#ffd93b', '#2f8fe6', '#39b54a', '#ff9a1f', '#ffffff']); if (i % 2) g.color(c).box(0.17, 0.26, 0.12, -0.14 + (i % 3) * 0.14, 0.44 + (i > 3 ? 0.2 : 0), -0.25 + (i % 4) * 0.17); else g.color(c).ball(0.1, 0.1, 0.1, -0.12 + (i % 3) * 0.13, 0.56 + (i > 3 ? 0.2 : 0), -0.22 + (i % 4) * 0.16, 8, 5); }
  g.at();
}
function car(g, x, z, ry, col) {
  g.at(x, 0, z, ry); const d = new T.Color(col).multiplyScalar(0.8).getStyle();
  g.color(col).box(1.75, 0.52, 4.0, 0, 0.3, 0).color(d).box(1.79, 0.12, 4.04, 0, 0.3, 0).color(col).box(1.56, 0.5, 2.1, 0, 0.82, -0.15).color('#bfe6ff').box(1.58, 0.36, 1.7, 0, 0.88, -0.15).color('#d9f1ff').box(1.36, 0.36, 2.12, 0, 0.88, -0.15).color(col).box(1.6, 0.06, 2.14, 0, 1.3, -0.15).box(0.08, 0.5, 0.1, -0.76, 0.82, -0.15).box(0.08, 0.5, 0.1, 0.76, 0.82, -0.15);
  for (const [dx, dz] of [[-0.82, 1.25], [0.82, 1.25], [-0.82, -1.3], [0.82, -1.3]]) { g.at(x, 0, z, ry); const m = g.m.clone().multiply(new T.Matrix4().makeRotationZ(Math.PI / 2).setPosition(dx + (dx < 0 ? -0.02 : 0.24), 0.33, dz)); g.m = m; g.color('#22262e').cyl(0.33, 0.33, 0.22, 0, 0, 0, 14).color(STEEL).cyl(0.17, 0.17, 0.24, 0, 0, 0, 10); }
  g.at(x, 0, z, ry).color('#fff7c2').box(0.34, 0.14, 0.04, -0.55, 0.52, 2.0).box(0.34, 0.14, 0.04, 0.55, 0.52, 2.0).color('#ff5a5a').box(0.3, 0.12, 0.04, -0.58, 0.55, -2.0).box(0.3, 0.12, 0.04, 0.58, 0.55, -2.0).color(DARK).box(1.5, 0.14, 0.06, 0, 0.34, 2.0).at();
}
function tree(g, x, z, s) { g.color('#8a5a34').cyl(0.16 * s, 0.2 * s, 1.1 * s, x, 0, z, 8); g.color('#3fa652').ball(1.0 * s, 0.9 * s, 1.0 * s, x, 1.9 * s, z, 12, 8).color('#57bf63').ball(0.72 * s, 0.66 * s, 0.72 * s, x - 0.35 * s, 2.45 * s, z + 0.25 * s, 11, 7).color('#6fd072').ball(0.5 * s, 0.46 * s, 0.5 * s, x + 0.4 * s, 2.6 * s, z - 0.1 * s, 10, 6); }

const shirts = ['#ff6b6b', '#4dabf7', '#ffd43b', '#69db7c', '#b197fc', '#ffa94d', '#f783ac', '#3bc9db', '#ffffff'];
// ---------- build ----------
ground();
const g = new Geo();
// shell: low side walls with the brand band, tall back wall, entrance portal with the name board
const RED = '#d43b3b';
g.color(WHITE).box(0.35, 2.6, STORE_Z0 - STORE_Z1, -W / 2 - 0.17, 0, (STORE_Z0 + STORE_Z1) / 2).box(0.35, 2.6, STORE_Z0 - STORE_Z1, W / 2 + 0.17, 0, (STORE_Z0 + STORE_Z1) / 2).box(W + 0.7, 4.2, 0.35, 0, 0, STORE_Z1 - 0.17);
g.color(RED).box(0.39, 0.42, STORE_Z0 - STORE_Z1 + 0.04, -W / 2 - 0.17, 2.0, (STORE_Z0 + STORE_Z1) / 2).box(0.39, 0.42, STORE_Z0 - STORE_Z1 + 0.04, W / 2 + 0.17, 2.0, (STORE_Z0 + STORE_Z1) / 2).box(W + 0.74, 0.6, 0.39, 0, 3.3, STORE_Z1 - 0.17);
g.color('#e9e4d8').box(0.43, 0.1, STORE_Z0 - STORE_Z1 + 0.08, -W / 2 - 0.17, 2.6, (STORE_Z0 + STORE_Z1) / 2).box(0.43, 0.1, STORE_Z0 - STORE_Z1 + 0.08, W / 2 + 0.17, 2.6, (STORE_Z0 + STORE_Z1) / 2);
for (const x of [-W / 2 - 0.17, -2.4, 2.4, W / 2 + 0.17]) g.color(WHITE).box(0.5, 3.0, 0.5, x, 0, 0.05).color(RED).box(0.54, 0.3, 0.54, x, 0, 0.05);
g.color(RED).box(5.4, 0.95, 0.4, 0, 3.0, 0.05).color(WHITE).box(5.0, 0.08, 0.44, 0, 3.08, 0.05).box(5.0, 0.08, 0.44, 0, 3.8, 0.05);
board('SOUQ MARKET', 5.0, 0.72, '#d43b3b', '#fff7d6', 0, 3.44, 0.262);
for (const d of DEPTS) {
  // built facing away, then the whole section is turned so fixtures and staff face the camera
  host = new T.Group(); const dg = new Geo(); ({ produce, bakery, dairy: fridgeRun, snacks: gondolas })[d.id](dg, 0, 0);
  for (let k = 0; k < 3; k++) person(dg, -1.6 + k * 1.6, 2.2, Math.PI, { top: WHITE, apron: d.col, cap: d.col, long: k === 1 });
  for (let k = 0; k < 3; k++) { const n = 1 + Math.floor(rnd() * 2); for (let i = 0; i < n; i++) { const x = -1.6 + k * 1.6, z = 0.75 - i * 1.55; cart(dg, x, z, 0, i === 0); person(dg, x, z - 0.85, 0, { top: pick(shirts), push: true, long: rnd() < 0.4 }); } }
  host.add(dg.mesh(solid)); host.rotation.y = Math.PI; host.position.set(d.x, 0, d.z + 1.85); scene.add(host); host = scene;
}
for (let k = 0; k < 5; k++) checkout(g, -5.4 + k * 2.7, -4.0, k + 1, k < 3);
// cart bay, planters, bollards, lamp posts
for (let i = 0; i < 5; i++) cart(g, -5.2, 0.7 + i * 0.3, Math.PI / 2, false);
g.color(STEEL).box(0.06, 0.9, 1.9, -5.75, 0, 1.4).box(0.06, 0.9, 1.9, -4.65, 0, 1.4).box(1.16, 0.06, 0.06, -5.2, 0.9, 2.35);
for (const x of [-3.4, 3.4]) { g.color('#b9b2a2').box(1.0, 0.5, 1.0, x, 0, 1.1).color('#6b4a2c').box(0.86, 0.06, 0.86, x, 0.5, 1.1); g.color('#3fa652').ball(0.5, 0.42, 0.5, x, 0.9, 1.1, 12, 7).color('#ff7aa8'); for (let i = 0; i < 6; i++) g.ball(0.09, 0.09, 0.09, x + Math.cos(i) * 0.3, 1.15 + (i % 2) * 0.08, 1.1 + Math.sin(i) * 0.3, 7, 5); }
for (const x of [-8.5, 8.5]) { g.color(DARK).cyl(0.07, 0.09, 4.2, x, 0, 2.2, 8).box(0.9, 0.08, 0.3, x + (x < 0 ? 0.4 : -0.4), 4.2, 2.2); const l = new Geo(); l.color('#fff6c8').box(0.6, 0.05, 0.22, x + (x < 0 ? 0.5 : -0.5), 4.16, 2.2); scene.add(l.mesh(glow)); }
for (const [x, z, s] of [[-11.5, -3, 1.2], [-12, -12, 1.4], [-11.2, -21, 1.1], [11.6, -6, 1.3], [12, -15, 1.15], [11.3, -24, 1.35], [-12.5, 7, 1.2], [12.6, 9, 1.3], [-11.8, 14, 1.1]]) tree(g, x, z, s);
// people: staff in section colours with aprons and caps, shoppers with carts
const shirts2 = ['#ff6b6b', '#4dabf7', '#ffd43b', '#69db7c', '#b197fc', '#ffa94d', '#f783ac', '#3bc9db', '#ffffff'];
for (let k = 0; k < 3; k++) { const x = -5.4 + k * 2.7; person(g, x - 0.75, -3.7, Math.PI / 2, { top: RED, apron: WHITE, cap: RED }); cart(g, x + 0.85, -3.3, 0, true); person(g, x + 0.85, -4.15, 0, { top: pick(shirts), push: true }); }
person(g, 0.5, 1.2, 0.4, { top: '#4dabf7', walk: true, long: true }); cart(g, 0.82, 0.45, 0.4 + Math.PI, false); person(g, -1.3, -1.6, Math.PI + 0.3, { top: '#ffd43b', walk: true }); person(g, 4.6, 1.4, -1.2, { top: '#f783ac', walk: true, long: true });
// cars and a delivery truck
['#e5484d', '#3b82f6', '#f4f4f5', '#f5a524', '#22b8a5', '#8b5cf6', '#f4f4f5', '#1f2937'].forEach((c, i) => { if (i !== 2 && i !== 5) car(g, -10.5 + i * 3, 8.7, Math.PI, c); });
['#3b82f6', '#f4f4f5', '#e5484d', '#22b8a5'].forEach((c, i) => car(g, -7.5 + i * 6, 14.3, 0, c));
{ const x = 8.6, z = 1.3; g.at(x, 0, z, Math.PI / 2).color(WHITE).box(2.0, 2.1, 3.6, 0, 0.55, -0.7).color(RED).box(2.04, 0.5, 3.64, 0, 1.2, -0.7).color('#ffd43b').box(1.9, 1.5, 1.4, 0, 0.5, 1.9).color('#bfe6ff').box(1.7, 0.55, 1.42, 0, 1.3, 1.92).color(DARK).box(2.0, 0.2, 5.2, 0, 0.35, 0.1); for (const [dx, dz] of [[-1, 1.8], [1, 1.8], [-1, -1.5], [1, -1.5]]) { g.at(x, 0, z, Math.PI / 2); g.m = g.m.clone().multiply(new T.Matrix4().makeRotationZ(Math.PI / 2).setPosition(dx + (dx < 0 ? -0.02 : 0.26), 0.4, dz)); g.color('#22262e').cyl(0.4, 0.4, 0.24, 0, 0, 0, 14).color(STEEL).cyl(0.2, 0.2, 0.26, 0, 0, 0, 10); } g.at(); }
scene.add(g.mesh(solid));

// ---------- camera: fixed pitch, framed so the store spans the screen width ----------
const cam = new T.PerspectiveCamera(26, 1, 1, 300); const PITCH = 52 * Math.PI / 180;
const views = { store: { z: -7.2, span: 15.4 }, aisle: { z: -13.5, span: 9.2 }, front: { z: -2.6, span: 9.6 }, lot: { z: 6.5, span: 17 }, hero: { z: -9.2, span: 6.6, x: -2.9 } };
function frame() {
  const w = canvas.clientWidth, h = canvas.clientHeight; renderer.setSize(w, h, false); cam.aspect = w / h;
  const v = views[q.get('shot')] || views.store, hfov = 2 * Math.atan(Math.tan(cam.fov * Math.PI / 360) * cam.aspect), dist = v.span / 2 / Math.tan(hfov / 2);
  cam.position.set(v.x || 0, Math.sin(PITCH) * dist, v.z + Math.cos(PITCH) * dist); cam.lookAt(v.x || 0, 0.6, v.z); cam.updateProjectionMatrix();
  renderer.render(scene, cam); document.title = 'ready';
}
addEventListener('resize', frame); frame();
window.__info = () => ({ tris: renderer.info.render.triangles, calls: renderer.info.render.calls });
})();
