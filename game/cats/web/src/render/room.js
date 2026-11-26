/* 貓躲狗找 — the living room of a Japanese house, densely dressed, with doorways to kitchen / genkan and an engawa + garden.
   Everything is procedural. Static meshes are batched per material at the end; anything that moves is built under a `dyn` group. */
(function () {
  'use strict';
  var SG = (window.SG = window.SG || {});
  var G = SG.geo, PAL = SG.PAL, P = SG.P;
  var uTime = (SG.uTime = { value: 0 });

  /* ---------- materials ---------- */
  var mats = {};
  function mat(key, o) {
    if (mats[key]) return mats[key];
    var m = new THREE.MeshStandardMaterial(Object.assign({ roughness: 0.8, metalness: 0 }, o));
    m.name = key; mats[key] = m; return m;
  }
  function col(hex, rough, extra) { return mat('c' + hex + (rough || '') + (extra ? JSON.stringify(extra) : ''), Object.assign({ color: hex, roughness: rough == null ? 0.8 : rough }, extra || {})); }
  function tx(key, fn, size, rough, extra) { return mat('t' + key, Object.assign({ map: SG.tex(key, fn, size ? { size: size } : null), roughness: rough == null ? 0.85 : rough }, extra || {})); }
  /* cloth / leaf sway in the vertex shader: hangs from the top edge (uv.y = 1) */
  function sway(m, amp, freq, mode) {
    m.onBeforeCompile = function (sh) {
      sh.uniforms.uTime = uTime;
      sh.vertexShader = sh.vertexShader.replace('#include <common>', '#include <common>\nuniform float uTime;')
        .replace('#include <begin_vertex>', '#include <begin_vertex>\n' + (mode === 'leaf'
          ? 'vec4 wp0 = modelMatrix * vec4(position,1.0); float k = smoothstep(0.0,0.5,position.y); transformed.x += sin(uTime*' + freq.toFixed(2) + '+wp0.x*3.0+wp0.z*2.0)*' + amp.toFixed(3) + '*k; transformed.z += cos(uTime*' + (freq * 0.8).toFixed(2) + '+wp0.x*2.0)*' + (amp * 0.7).toFixed(3) + '*k;'
          : 'vec4 wp0 = modelMatrix * vec4(position,1.0); float k = (1.0-uv.y); k*=k; transformed.z += (sin(uTime*' + freq.toFixed(2) + '+wp0.x*2.5+wp0.z*2.5)+0.5*sin(uTime*' + (freq * 2.3).toFixed(2) + '+wp0.x*6.0))*' + amp.toFixed(3) + '*k;'));
    };
    m.customProgramCacheKey = function () { return 'sway' + amp + freq + mode; };
    return m;
  }

  SG.buildRoom = function (scene, opt) {
    opt = opt || {};
    var room = new THREE.Group(); scene.add(room);
    var stat = new THREE.Group(), dyn = new THREE.Group(); room.add(stat, dyn);
    var inv = {}, platforms = [], updaters = [], knock = [], cur = stat, r = SG.rng(20261124);
    var curRoom = '客廳', invRoom = {};
    function count(type, n) { inv[type] = (inv[type] || 0) + (n || 1); var ir = invRoom[curRoom] = invRoom[curRoom] || {}; ir[type] = (ir[type] || 0) + (n || 1); }
    /* begin a prop: a group at (x,y,z) rotated ry; following primitives go into it */
    function begin(type, x, y, z, ry, isDyn) { var g = new THREE.Group(); g.name = type || ''; g.position.set(x, y, z); g.rotation.y = ry || 0; (isDyn ? dyn : stat).add(g); cur = g; if (type) count(type); return g; }
    function add(geo, m, x, y, z, rx, ry, rz) { var o = new THREE.Mesh(geo, m); o.position.set(x || 0, y || 0, z || 0); if (rx || ry || rz) o.rotation.set(rx || 0, ry || 0, rz || 0); cur.add(o); return o; }
    function B(w, h, d, m, x, y, z, rad, uvm) { return add(G.rbox(w, h, d, rad == null ? Math.min(w, h, d) * 0.12 : rad, { uvm: uvm, k: 2 }), m, x, (y || 0) + h / 2, z); } // base-centred rounded box
    function C(rt, rb, h, m, x, y, z, seg) { return add(new THREE.CylinderGeometry(rt, rb, h, seg || 20), m, x, (y || 0) + h / 2, z); }
    function L(pts, m, x, y, z, seg) { return add(G.latheS(pts, seg || 20), m, x, y, z); }
    function S(rad, m, x, y, z, sx, sy, sz) { var o = add(new THREE.SphereGeometry(rad, 18, 14), m, x, y, z); if (sx) o.scale.set(sx, sy, sz); return o; }
    function PL(w, h, m, x, y, z, rx, ry, rz, uvm) { return add(uvm ? G.planeM(w, h) : new THREE.PlaneGeometry(w, h), m, x, y, z, rx, ry, rz); }
    function plat(x0, x1, z0, z1, top, bottom, wall) { var p = { x0: Math.min(x0, x1), x1: Math.max(x0, x1), z0: Math.min(z0, z1), z1: Math.max(z0, z1), y1: top, y0: bottom || 0, wall: !!wall }; platforms.push(p); return p; }
    /* platform from the current prop group (axis aligned props only) */
    function platG(g, w, d, top, bottom) { var c = Math.abs(Math.cos(g.rotation.y)), s = Math.abs(Math.sin(g.rotation.y)), hw = (w * c + d * s) / 2, hd = (w * s + d * c) / 2; plat(g.position.x - hw, g.position.x + hw, g.position.z - hd, g.position.z + hd, g.position.y + top, bottom == null ? 0 : g.position.y + bottom); }
    var fxMat = function (t, op) { return new THREE.MeshBasicMaterial({ map: t, transparent: true, depthWrite: false, opacity: op == null ? 1 : op, toneMapped: false }); };
    var blobT = SG.tex('blob', P.shadowBlob), aoT = SG.tex('ao', P.aoStrip), glowT = SG.tex('glow', P.glow);
    var fx = new THREE.Group(); room.add(fx);
    var blobM = fxMat(blobT, 0.55), aoM = fxMat(aoT, 0.8);
    function blob(x, z, w, d, y, op) { var o = new THREE.Mesh(new THREE.PlaneGeometry(w, d), op ? fxMat(blobT, op) : blobM); o.rotation.x = -Math.PI / 2; o.position.set(x, (y || 0) + 0.004 + r() * 0.002, z); o.layers.set(1); o.renderOrder = 2; fx.add(o); return o; }
    function glow(x, y, z, s, colr, op) { var m = new THREE.SpriteMaterial({ map: glowT, color: colr || 0xffd9a0, transparent: true, opacity: op || 0.7, depthWrite: false, blending: THREE.AdditiveBlending }); var sp = new THREE.Sprite(m); sp.position.set(x, y, z); sp.scale.setScalar(s); sp.layers.set(1); fx.add(sp); return sp; }

    var W = 4.5, D = 3.5, H = 2.6, EN = 2.55; // half width, half depth, ceiling, engawa line (z)
    SG.ROOM = { W: W, D: D, H: H, EN: EN };

    /* ---------- palette of shared materials ---------- */
    var honey = tx('woodHoney', function () { return P.wood({ base: '#c89b5e', planks: 5, seed: 3, contrast: 0.12 }); }, [1.1, 2.2], 0.55);
    var dark = tx('woodDark', function () { return P.wood({ base: '#6b4a2e', seed: 4, contrast: 0.2 }); }, 0.9, 0.6);
    var darker = tx('woodDarker', function () { return P.wood({ base: '#4a3020', seed: 8, contrast: 0.2 }); }, 0.9, 0.55);
    var hinoki = tx('woodHinoki', function () { return P.wood({ base: '#e2c08c', seed: 6, contrast: 0.08, knots: 0.2 }); }, 0.8, 0.6);
    var red = tx('woodRed', function () { return P.wood({ base: '#8a4a2c', seed: 12, contrast: 0.16 }); }, 0.8, 0.5);
    var engW = tx('woodEng', function () { return P.wood({ base: '#b98a55', planks: 7, seed: 14, contrast: 0.16 }); }, [1.05, 2.0], 0.5);
    var ceilW = tx('woodCeil', function () { return P.wood({ base: '#a47a4c', planks: 4, seed: 15, contrast: 0.1, joints: false }); }, [1.8, 1.8], 0.8);
    var plaster = tx('plaster', function () { return P.plaster('#efe6d3', 31); }, 1.2, 0.95);
    var plasterG = tx('plasterG', function () { return P.plaster('#cfd3b4', 33); }, 1.2, 0.95);
    var tatami = tx('tatami', P.tatami, 0.45, 0.9);
    var washi = tx('washi', function () { return P.washi(); }, 0.6, 0.9);
    var iron = col(0x2a2624, 0.45, { metalness: 0.7 });
    var brass = col(0xc9a04a, 0.35, { metalness: 0.9 });
    var white = col(0xf5f1e8, 0.6), black = col(0x1e1a18, 0.5), cream = col(0xefe2c4, 0.8);
    var cloth = {
      asanoha: tx('cAsanoha', function () { return P.asanoha('#7a9a54', '#eef0dc', 48); }, 0.22),
      seigaiha: tx('cSeigaiha', function () { return P.seigaiha('#2f4b7c', '#e9eef2', 40); }, 0.24),
      yagasuri: tx('cYagasuri', function () { return P.yagasuri('#c8452e', '#f3e6cf', 40); }, 0.26),
      shippo: tx('cShippo', function () { return P.shippo('#d9a93a', '#fbf2d8', 48, '#c8452e'); }, 0.22),
      ichimatsu: tx('cIchimatsu', function () { return P.ichimatsu('#2f4b7c', '#efe6d3', 48); }, 0.2),
      ichiRed: tx('cIchiRed', function () { return P.ichimatsu('#c8452e', '#f1dcc0', 48); }, 0.24),
      kikko: tx('cKikko', function () { return P.kikko('#5e4a7a', '#e9dff0', 30); }, 0.2),
      sakura: tx('cSakura', function () { return P.sakura('#f0c6c8', '#fff6f2', '#d9667a'); }, 0.3),
      stripe: tx('cStripe', function () { return P.stripes(['#f3ecd9', '#2f4b7c', '#f3ecd9', '#c8452e'], [28, 12, 28, 6]); }, [0.16, 0.16]),
      stripeG: tx('cStripeG', function () { return P.stripes(['#e9efdc', '#7a9a54', '#e9efdc', '#d9a93a'], [22, 14, 22, 6]); }, [0.14, 0.14]),
      mustard: tx('cMustard', function () { return P.washi('#d9a93a', 5); }, 0.3), teal: tx('cTeal', function () { return P.washi('#3f8f8a', 6); }, 0.3),
      indigo: tx('cIndigo', function () { return P.washi('#2f4b7c', 8); }, 0.3), cream: tx('cCream', function () { return P.washi('#f1e7d2', 9); }, 0.3)
    };
    var clothKeys = Object.keys(cloth);

    /* ================= SHELL ================= */
    cur = stat;
    // floors
    add(G.boxM(W * 2, 0.1, D + EN + 0.0), honey, 0, -0.05, (EN - D) / 2).rotation.y = 0; // main floor: z[-D, EN]
    var eng = add(G.boxM(W * 2 + 3, 0.1, 1.5), engW, 0, -0.07, EN + 0.75); // engawa strip z[EN, EN+1.5]
    // tatami island (6 mats) with heri borders
    var TX = -0.55, TZ = -0.25, mw = 0.9, ml = 1.8, heri = tx('heri', function () { return P.kikko('#1f3a2e', '#c9b46a', 12); }, 0.08, 0.8);
    function mat1(x, z, rot) {
      begin('榻榻米', TX + x, 0, TZ + z, rot ? Math.PI / 2 : 0);
      B(mw - 0.005, 0.03, ml - 0.005, tatami, 0, 0, 0, 0.006, true);
      B(0.045, 0.032, ml - 0.005, heri, -mw / 2 + 0.024, 0, 0, 0.004, true); B(0.045, 0.032, ml - 0.005, heri, mw / 2 - 0.024, 0, 0, 0.004, true);
    }
    mat1(-1.35, -0.45); mat1(-0.45, -0.45); mat1(0.9, -0.9, 1); mat1(0.9, 0, 1); mat1(-0.9, 0.9, 1); mat1(0.9, 0.9, 1);
    plat(TX - 1.8, TX + 1.8, TZ - 1.35, TZ + 1.35, 0.03);
    cur = stat;
    // ceiling + beams
    add(G.boxM(W * 2, 0.08, D * 2 + 3), ceilW, 0, H + 0.04, 1.5);
    for (var bz = -2.6; bz <= 3.6; bz += 1.24) B(W * 2, 0.16, 0.12, dark, 0, H - 0.16, bz, 0.01, true);
    B(0.16, 0.2, D * 2 + 3, darker, 0, H - 0.2, 1.5, 0.01, true);
    // wall builder: plaster panel + wainscot + posts; openings are simply left out
    function wallX(x, z0, z1, side, m) { // wall on x = const, facing side (+1 faces +x)
      var len = z1 - z0, zc = (z0 + z1) / 2;
      add(G.boxM(0.1, H - 0.75, len), m || plaster, x - side * 0.05, 0.75 + (H - 0.75) / 2, zc);
      add(G.boxM(0.12, 0.75, len), hinoki, x - side * 0.04, 0.375, zc);
      B(0.03, 0.06, len, dark, x + side * 0.03, 0.75, zc, 0.008, true);
      B(0.035, 0.09, len, dark, x + side * 0.025, 0, zc, 0.008, true);
    }
    function wallZ(z, x0, x1, side, m) {
      var len = x1 - x0, xc = (x0 + x1) / 2;
      add(G.boxM(len, H - 0.75, 0.1), m || plaster, xc, 0.75 + (H - 0.75) / 2, z - side * 0.05);
      add(G.boxM(len, 0.75, 0.12), hinoki, xc, 0.375, z - side * 0.04);
      B(len, 0.06, 0.03, dark, xc, 0.75, z + side * 0.03, 0.008, true);
      B(len, 0.09, 0.035, dark, xc, 0, z + side * 0.025, 0.008, true);
    }
    function post(x, z, h) { B(0.13, h || H, 0.13, darker, x, 0, z, 0.012, true); }
    function lintel(x0, x1, z, y, alongZ) { if (alongZ) B(0.14, 0.12, x1 - x0, darker, z, y, (x0 + x1) / 2, 0.012, true); else B(x1 - x0, 0.12, 0.14, darker, (x0 + x1) / 2, y, z, 0.012, true); }
    // north wall (z=-D): tokonoma recess x[-4.5,-2.9], doorway to kitchen x[-0.55,0.55]
    wallZ(-D, -2.9, -0.55, 1); wallZ(-D, 0.55, 2.75, 1); wallZ(-D, 4.35, W, 1);
    add(G.boxM(1.6, H - 2.0, 0.1), plaster, 3.55, 2.0 + (H - 2.0) / 2, -D - 0.05); lintel(2.68, 4.42, -D + 0.02, 1.94);
    add(G.boxM(1.1, H - 2.0, 0.1), plaster, 0, 2.0 + (H - 2.0) / 2, -D - 0.05); lintel(-0.62, 0.62, -D + 0.02, 1.94);
    [-2.9, -0.62, 0.62, 2.68, 4.42].forEach(function (x) { post(x, -D + 0.03); });
    // west wall (x=-W): doorway to genkan z[0.7,1.9]
    wallX(-W, -D, 0.7, 1); wallX(-W, 1.9, EN, 1);
    add(G.boxM(0.1, H - 2.0, 1.2), plaster, -W - 0.05, 2.0 + (H - 2.0) / 2, 1.3); lintel(0.63, 1.97, -W + 0.02, 1.94, true);
    [-D + 0.03, -1.4, 0.63, 1.97, EN].forEach(function (z) { post(-W + 0.03, z); });
    // east wall (x=W)
    wallX(W, -D, -3.3, -1, plasterG); wallX(W, -2.4, EN, -1, plasterG); // low doorway to the east wing in the corner
    add(G.boxM(0.1, H - 1.2, 0.9), plasterG, W + 0.05, 1.2 + (H - 1.2) / 2, -2.85); lintel(-3.34, -2.36, W - 0.02, 1.14, true);
    [-D + 0.03, -1.6, 0.4, EN].forEach(function (z) { post(W - 0.03, z); });
    // nageshi rail round the room + ranma strip above the engawa opening
    B(W * 2, 0.07, 0.04, dark, 0, 2.0, -D + 0.07, 0.008, true); B(0.04, 0.07, D + EN, dark, W - 0.07, 2.0, (EN - D) / 2, 0.008, true); B(0.04, 0.07, D + EN, dark, -W + 0.07, 2.0, (EN - D) / 2, 0.008, true);
    // south side: posts, lintel, transom (ranma) lattice, shoji at both ends, open in the middle
    lintel(-W, W, EN, 2.0); B(W * 2, 0.05, 0.16, darker, 0, 0, EN, 0.01, true);
    [-W + 0.03, -2.3, 2.3, W - 0.03].forEach(function (x) { post(x, EN); });
    add(G.boxM(W * 2, H - 2.12, 0.06), plaster, 0, 2.12 + (H - 2.12) / 2, EN);
    var shojiM = mat('shoji', { map: SG.tex('shoji', P.shoji), roughness: 0.9, emissive: 0xfff0d0, emissiveMap: SG.tex('shoji', P.shoji), emissiveIntensity: 0.55, side: THREE.DoubleSide });
    function shoji(x, z, w, h, ry, type) {
      begin(type || '障子', x, 0, z, ry);
      PL(w - 0.06, h - 0.06, shojiM, 0, h / 2, 0);
      var bars = [];
      [-1, 1].forEach(function (s) { bars.push([G.rbox(0.045, h, 0.035, 0.006), G.mat4(s * (w / 2 - 0.022), h / 2, 0)]); bars.push([G.rbox(w, 0.05, 0.035, 0.006), G.mat4(0, s > 0 ? h - 0.025 : 0.025, 0)]); });
      for (var i = 1; i < 3; i++) bars.push([new THREE.BoxGeometry(0.014, h, 0.02), G.mat4(-w / 2 + i * w / 3, h / 2, 0)]);
      for (i = 1; i < 6; i++) bars.push([new THREE.BoxGeometry(w, 0.014, 0.02), G.mat4(0, i * h / 6, 0)]);
      bars.push([G.rbox(w - 0.05, 0.3, 0.02, 0.004), G.mat4(0, 0.17, 0)]);
      add(G.merge(bars), hinoki, 0, 0, 0);
    }
    shoji(-3.38, EN, 2.1, 1.98, 0); shoji(3.38, EN, 2.1, 1.98, 0); shoji(-2.45, EN + 0.05, 1.0, 1.98, 0); shoji(2.45, EN + 0.05, 1.0, 1.98, 0);
    plat(-W, -1.95, EN - 0.06, EN + 0.1, 2.0); plat(1.95, W, EN - 0.06, EN + 0.1, 2.0);
    // engawa posts + eave
    [-4.8, -1.6, 1.6, 4.8].forEach(function (x) { post(x, EN + 1.45, 2.3); });
    add(G.boxM(W * 2 + 3.4, 0.08, 2.0), dark, 0, 2.34, EN + 1.0).rotation.x = 0.1;
    cur = stat;

    /* ================= GARDEN (beyond the engawa) ================= */
    curRoom = '庭院';
    var grass = tx('moss', function () { return P.plaster('#7f9a55', 51); }, 1.0, 1), gravel = tx('gravel', function () { return P.plaster('#cfc6b4', 52); }, 0.6, 1);
    add(G.planeM(26, 9), grass, 0, -0.3, EN + 5.5, -Math.PI / 2);
    add(new THREE.CircleGeometry(2.6, 28), gravel, -0.6, -0.29, EN + 3.2, -Math.PI / 2).scale.set(1.5, 1, 1);
    // pond (custom water shader) with koi
    var waterM = new THREE.ShaderMaterial({
      uniforms: { uTime: uTime, uDeep: { value: new THREE.Color(0x1f5a66) }, uShallow: { value: new THREE.Color(0x6fc3c0) } },
      vertexShader: 'varying vec2 vUv; varying vec3 vW; void main(){ vUv=uv; vec4 w=modelMatrix*vec4(position,1.); vW=w.xyz; gl_Position=projectionMatrix*viewMatrix*w; }',
      fragmentShader: [
        'uniform float uTime; uniform vec3 uDeep,uShallow; varying vec2 vUv; varying vec3 vW;',
        'float h(vec2 p){ return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }',
        'float n(vec2 p){ vec2 i=floor(p),f=fract(p); f=f*f*(3.-2.*f); return mix(mix(h(i),h(i+vec2(1,0)),f.x),mix(h(i+vec2(0,1)),h(i+vec2(1,1)),f.x),f.y); }',
        'void main(){ vec2 p=vW.xz*2.2; float w=n(p+uTime*0.25)+0.5*n(p*2.3-uTime*0.4);',
        '  float d=length(vUv-0.5)*2.; vec3 c=mix(uDeep,uShallow,smoothstep(0.3,1.0,d)+w*0.18);',
        '  float rip=sin(length(vW.xz-vec2(0.4,6.1))*16.-uTime*2.4)*0.5+0.5; c+=vec3(0.9,1.0,0.95)*pow(rip,10.)*0.12*(1.-d);',
        '  c+=vec3(1.0,0.97,0.86)*smoothstep(1.18,1.32,w)*0.75;', // sun glints
        '  gl_FragColor=vec4(c*1.25,1.); }'].join('\n')
    });
    begin('池塘', 0.6, -0.27, EN + 3.5);
    add(new THREE.CircleGeometry(1.25, 32), waterM, 0, 0, 0, -Math.PI / 2).scale.set(1.35, 1, 1);
    var stoneM = tx('stone', function () { return P.plaster('#8f8c84', 53); }, 0.5, 0.95), stoneD = tx('stoneD', function () { return P.plaster('#6c6a64', 54); }, 0.5, 0.95);
    for (var si = 0; si < 16; si++) { var a = si / 16 * Math.PI * 2, sr = 0.13 + r() * 0.12; begin('庭石', 0.6 + Math.cos(a) * 1.78, -0.3, EN + 3.5 + Math.sin(a) * 1.3, r() * 3); S(sr, si % 3 ? stoneM : stoneD, 0, sr * 0.45, 0, 1.2, 0.7, 1); }
    var koi = [];
    [[0xf06a2a, 0xffffff], [0xf5f0e6, 0xd9432b], [0xe9b23a, 0xf5f0e6], [0xf06a2a, 0x1e1a18], [0xffffff, 0xf06a2a]].forEach(function (c, i) {
      var g = begin('錦鯉', 0, -0.25, 0, 0, true);
      S(0.1, col(c[0], 0.4), 0, 0, 0, 0.42, 0.3, 1.5); S(0.05, col(c[1], 0.4), 0, 0.012, 0.02, 0.7, 0.3, 1.2);
      var tl = add(new THREE.ConeGeometry(0.05, 0.12, 6), col(c[0], 0.4), 0, 0, -0.19, Math.PI / 2, 0, 0); tl.scale.x = 0.25; tl.userData.keep = true;
      koi.push({ g: g, tl: tl, ph: i * 1.3, rad: 0.5 + (i % 3) * 0.28, sp: 0.35 + i * 0.05 });
    });
    updaters.push(function (t) { koi.forEach(function (k) { var a = t * k.sp + k.ph, x = 0.6 + Math.cos(a) * k.rad * 1.35, z = EN + 3.5 + Math.sin(a * 1.0) * k.rad * 0.9; k.g.position.x = x; k.g.position.z = z; k.g.rotation.y = -a + Math.sin(t * 5 + k.ph) * 0.16; k.tl.rotation.y = Math.sin(t * 7 + k.ph) * 0.6; }); });
    // stone lantern
    begin('石燈籠', -2.5, -0.3, EN + 3.3);
    C(0.2, 0.26, 0.14, stoneM, 0, 0, 0, 6); C(0.09, 0.11, 0.55, stoneM, 0, 0.14, 0, 8); C(0.24, 0.16, 0.1, stoneD, 0, 0.69, 0, 6);
    B(0.26, 0.24, 0.26, stoneM, 0, 0.79, 0, 0.03); B(0.14, 0.14, 0.28, mat('lampGlow', { color: 0xffd9a0, emissive: 0xffb560, emissiveIntensity: 2.2 }), 0, 0.84, 0, 0.02);
    add(new THREE.ConeGeometry(0.36, 0.22, 6), stoneD, 0, 1.14, 0); S(0.06, stoneM, 0, 1.28, 0);
    // bushes, maple, fence, distant roofs
    var leafM = sway(tx('leaf', function () { return P.plaster('#5d8a45', 55); }, 0.4, 0.9), 0.02, 1.6, 'leaf'), leafD = sway(tx('leafD', function () { return P.plaster('#3f6b3a', 56); }, 0.4, 0.9), 0.02, 1.3, 'leaf');
    var mapleM = sway(tx('maple', function () { return P.plaster('#d0552e', 57); }, 0.4, 0.9), 0.035, 1.4, 'leaf'), mapleO = sway(tx('mapleO', function () { return P.plaster('#e58a36', 58); }, 0.4, 0.9), 0.035, 1.7, 'leaf');
    [[-4.6, 4.6, 0.6], [-3.5, 5.6, 0.75], [3.2, 5.3, 0.7], [4.6, 3.4, 0.55], [5.6, 5.2, 0.8], [-5.8, 3.6, 0.6], [2.3, 6.0, 0.5]].forEach(function (b, i) {
      begin('灌木', b[0], -0.3, EN + b[1] - 2.2); var br = b[2] * 0.75; plat(b[0] - br, b[0] + br, EN + b[1] - 2.2 - br, EN + b[1] - 2.2 + br, -0.3 + b[2] * 1.05, -0.3); // owner bug report: cats hid inside bushes. Bushes are solid now
      for (var k = 0; k < 4; k++) S(b[2] * (0.55 + r() * 0.3), k & 1 ? leafM : leafD, (r() - 0.5) * b[2], b[2] * (0.4 + r() * 0.3), (r() - 0.5) * b[2], 1, 0.8, 1);
    });
    begin('楓樹', 3.6, -0.3, EN + 2.6); plat(3.5, 3.72, EN + 2.5, EN + 2.72, 1.9, -0.3);
    add(G.tube([[0, 0, 0], [0.08, 0.7, 0.03], [-0.1, 1.4, -0.02], [0.05, 2.0, 0.05]], 0.09, 12, 8), darker);
    add(G.tube([[-0.05, 1.2, 0], [-0.5, 1.7, 0.2], [-0.9, 1.9, 0.3]], 0.04, 8, 6), darker); add(G.tube([[0, 1.4, 0], [0.5, 1.9, -0.2], [0.8, 2.3, -0.3]], 0.04, 8, 6), darker);
    for (var mi = 0; mi < 9; mi++) S(0.42 + r() * 0.3, mi & 1 ? mapleM : mapleO, (r() - 0.5) * 1.9, 2.0 + r() * 0.8, (r() - 0.5) * 1.4, 1.2, 0.7, 1.1);
    begin('竹籬', 0, -0.3, EN + 6.2);
    var bam = tx('bamboo', function () { return P.wood({ base: '#c4b074', planks: 16, seed: 60, contrast: 0.06, knots: 0, joints: true }); }, [1.6, 1.6], 0.6);
    add(G.planeM(26, 1.7), bam, 0, 0.85, 0); B(26, 0.07, 0.07, darker, 0, 1.25, 0.04, 0.02); B(26, 0.07, 0.07, darker, 0, 0.4, 0.04, 0.02);
    cur = stat;
    [[-7, 2.4, 5, 0x6f7f8c], [1, 2.9, 7, 0x7d6f66], [8.5, 2.2, 5, 0x66788a]].forEach(function (h) { // neighbours' roofs
      count('遠處屋頂'); var m = add(new THREE.CylinderGeometry(0.01, h[2] * 0.72, 1.3, 4, 1), col(h[3], 0.9), h[0], h[1] + 0.2, EN + 9.5); m.rotation.y = Math.PI / 4; m.scale.z = 0.5;
      add(new THREE.BoxGeometry(h[2] * 0.8, 2.4, 2.4), col(0xe9dfc8, 0.95), h[0], h[1] - 1.5, EN + 9.5);
    });
    // sky dome (shader gradient, drawn first)
    var sky = new THREE.Mesh(new THREE.SphereGeometry(60, 24, 12), new THREE.ShaderMaterial({
      side: THREE.BackSide, depthWrite: false,
      vertexShader: 'varying vec3 vP; void main(){ vP=position; gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.); }',
      uniforms: { uNight: { value: 0 } },
      fragmentShader: 'uniform float uNight; varying vec3 vP; float hh(vec2 p){ return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); } void main(){ vec3 d=normalize(vP); float h=d.y; vec3 c=mix(vec3(1.25,1.12,0.92),vec3(0.42,0.68,1.05),smoothstep(-0.02,0.55,h)); c+=vec3(1.2,0.9,0.5)*pow(max(0.,dot(d,normalize(vec3(-0.3,0.55,0.8)))),24.); vec3 n=mix(vec3(0.05,0.07,0.16),vec3(0.01,0.015,0.05),smoothstep(0.,0.6,h)); vec2 g=floor(d.xz/max(0.2,d.y+0.3)*60.); n+=vec3(1.0,0.95,0.8)*step(0.992,hh(g))*step(0.05,h)*0.9; n+=vec3(0.9,0.95,1.0)*smoothstep(0.994,0.999,dot(d,normalize(vec3(-0.3,0.55,0.8))))*3.0; gl_FragColor=vec4(mix(c*1.5,n,uNight),1.); }'
    }));
    room.add(sky);
    // laundry pole with swaying washing
    begin('晾衣竿', -3.2, -0.3, EN + 3.9);
    C(0.025, 0.025, 1.9, iron, -1.2, 0, 0); C(0.025, 0.025, 1.9, iron, 1.2, 0, 0); add(new THREE.CylinderGeometry(0.018, 0.018, 2.6, 8), hinoki, 0, 1.85, 0, 0, 0, Math.PI / 2);
    [['asanoha', 0.5, 0.7], ['stripe', 0.42, 0.55], ['ichiRed', 0.5, 0.62], ['cream', 0.6, 0.8], ['seigaiha', 0.4, 0.5]].forEach(function (c, i) {
      count(i % 2 ? '晾著的毛巾' : '晾著的衣服');
      var m = sway(cloth[c[0]].clone(), 0.09, 1.5 + i * 0.2); m.side = THREE.DoubleSide;
      add(new THREE.PlaneGeometry(c[1], c[2], 6, 8), m, -1.0 + i * 0.5, 1.84 - c[2] / 2, 0);
    });

    /* ================= ROOMS BEYOND THE DOORWAYS ================= */
    // kitchen (north): tiled floor, counter, fridge, shelf, kettle with steam
    curRoom = '廚房';
    cur = stat;
    var tile = tx('tile', function () { return P.ichimatsu('#e9e2d0', '#9fb7b0', 64); }, 0.6, 0.35);
    add(G.planeM(5, 2.6), tile, 0, 0.001, -D - 1.3, -Math.PI / 2);
    add(G.boxM(5, H, 0.1), tx('plasterK', function () { return P.plaster('#f1e3c2', 34); }, 1.2, 0.95), 0, H / 2, -D - 2.6);
    add(G.boxM(0.1, H, 2.6), plaster, -2.5, H / 2, -D - 1.3); add(G.boxM(0.1, H, 2.6), plaster, 2.5, H / 2, -D - 1.3);
    add(G.boxM(5, 0.08, 2.6), ceilW, 0, H + 0.04, -D - 1.3);
    begin('流理台', -0.2, 0, -D - 2.2); B(2.6, 0.82, 0.6, hinoki, 0, 0, 0, 0.02, true); B(2.66, 0.05, 0.66, col(0xd8d6d0, 0.25, { metalness: 0.6 }), 0, 0.82, 0, 0.012);
    for (var kd = 0; kd < 4; kd++) { B(0.56, 0.6, 0.02, tx('woodHoney2', function () { return P.wood({ base: '#d2a86c', seed: 70 }); }, 0.7), -0.96 + kd * 0.64, 0.12, 0.31, 0.012); C(0.012, 0.012, 0.16, brass, -0.96 + kd * 0.64, 0.6, 0.33); }
    begin('瓦斯爐', 0.5, 0.87, -D - 2.2); B(0.6, 0.05, 0.42, black, 0, 0, 0, 0.012); C(0.1, 0.1, 0.02, iron, -0.15, 0.05, 0, 12); C(0.1, 0.1, 0.02, iron, 0.15, 0.05, 0, 12);
    var kettle = begin('水壺', 0.35, 0.94, -D - 2.2);
    L([[0, 0], [0.1, 0], [0.115, 0.06], [0.1, 0.13], [0.05, 0.16], [0, 0.165]], col(0xc8452e, 0.25, { metalness: 0.2 })); add(new THREE.TorusGeometry(0.075, 0.009, 6, 16, Math.PI), black, 0, 0.16, 0); add(new THREE.CylinderGeometry(0.012, 0.022, 0.1, 8), col(0xc8452e, 0.25), 0.13, 0.1, 0, 0, 0, -0.9); S(0.016, black, 0, 0.175, 0);
    begin('鍋子', 0.65, 0.94, -D - 2.2); L([[0, 0], [0.11, 0], [0.12, 0.1], [0.125, 0.11]], col(0x8a8f96, 0.3, { metalness: 0.8 })); C(0.127, 0.127, 0.012, col(0x6f747a, 0.3, { metalness: 0.8 }), 0, 0.11, 0); S(0.02, black, 0, 0.135, 0);
    begin('電鍋', -0.9, 0.87, -D - 2.2); L([[0, 0], [0.14, 0], [0.155, 0.1], [0.14, 0.2], [0.06, 0.24], [0, 0.245]], white); B(0.09, 0.05, 0.02, col(0xd9a93a, 0.5), 0, 0.06, 0.15, 0.008);
    begin('冰箱', 1.95, 0, -D - 2.15); B(0.72, 1.75, 0.68, col(0xcfe0dc, 0.3), 0, 0, 0, 0.04); B(0.7, 0.012, 0.02, col(0x8fa6a2, 0.4), 0, 1.1, 0.345); C(0.014, 0.014, 0.4, brass, -0.28, 1.2, 0.36); C(0.014, 0.014, 0.4, brass, -0.28, 0.55, 0.36);
    begin('蔬果籃', 1.95, 1.75, -D - 2.1); L([[0, 0], [0.16, 0], [0.2, 0.12]], tx('basket', function () { return P.kikko('#b98a4a', '#7a5626', 10); }, 0.08)); S(0.07, col(0xd9432b, 0.4), -0.05, 0.12, 0); S(0.065, col(0x7a9a54, 0.5), 0.07, 0.12, 0.03); S(0.06, col(0xe9b23a, 0.5), 0, 0.13, -0.07);
    begin('廚房吊架', -0.2, 1.5, -D - 2.5); B(2.4, 0.04, 0.24, dark, 0, 0, 0, 0.01, true);
    var bowlC = [0x2f4b7c, 0xf5f1e8, 0xc8452e, 0x7a9a54, 0xd9a93a, 0x3f8f8a];
    for (var bi = 0; bi < 9; bi++) { begin(bi % 3 === 2 ? '湯碗' : '盤子', -1.25 + bi * 0.27, 1.54, -D - 2.5); if (bi % 3 === 2) L([[0, 0], [0.04, 0], [0.085, 0.07], [0.09, 0.075]], col(bowlC[bi % 6], 0.3)); else for (var pk = 0; pk < 3; pk++) C(0.1, 0.07, 0.016, col(bowlC[(bi + pk) % 6], 0.3), 0, pk * 0.018, 0); }
    for (bi = 0; bi < 6; bi++) { begin('調味罐', -1.0 + bi * 0.13, 0.87, -D - 2.42); C(0.035, 0.04, 0.12 + (bi % 3) * 0.03, col([0x7a4a2a, 0xe9dfc8, 0x3a2a1e, 0xb5462a, 0xd9c27a, 0x35502e][bi], 0.3), 0, 0, 0, 10); C(0.03, 0.03, 0.02, bi & 1 ? black : col(0xc8452e, 0.4), 0, 0.12 + (bi % 3) * 0.03, 0, 10); }
    begin('廚房窗', -0.2, 1.75, -D - 2.54); PL(1.5, 0.8, mat('winGlow', { color: 0xdff0ff, emissive: 0xcfe8ff, emissiveIntensity: 1.3 }), 0, 0.2, 0); B(1.6, 0.06, 0.06, hinoki, 0, 0.6, 0); B(1.6, 0.06, 0.06, hinoki, 0, -0.26, 0); B(0.05, 0.86, 0.05, hinoki, 0, -0.23, 0);
    // steam (shader billboards)
    var steamM = new THREE.ShaderMaterial({
      transparent: true, depthWrite: false, side: THREE.DoubleSide, uniforms: { uTime: uTime, uAmt: { value: 1 } },
      vertexShader: 'varying vec2 vUv; void main(){ vUv=uv; gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.); }',
      fragmentShader: ['uniform float uTime,uAmt; varying vec2 vUv;',
        'float h(vec2 p){ return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }',
        'float n(vec2 p){ vec2 i=floor(p),f=fract(p); f=f*f*(3.-2.*f); return mix(mix(h(i),h(i+vec2(1,0)),f.x),mix(h(i+vec2(0,1)),h(i+vec2(1,1)),f.x),f.y); }',
        'void main(){ vec2 p=vUv; p.x+=(n(vec2(p.y*3.-uTime*0.9,1.))-0.5)*0.35*p.y; float d=abs(p.x-0.5)*2./(0.25+p.y*0.75);',
        '  float a=smoothstep(1.,0.2,d)*smoothstep(0.,0.12,p.y)*smoothstep(1.,0.45,p.y)*(0.45+0.55*n(vec2(p.x*5.,p.y*5.-uTime*1.6)));',
        '  gl_FragColor=vec4(vec3(1.6,1.55,1.5),a*0.5*uAmt); }'].join('\n')
    });
    SG.steamProto = steamM;
    var steam = new THREE.Mesh(new THREE.PlaneGeometry(0.34, 0.75), steamM); steam.position.set(0.5, 1.5, -D - 2.2); steam.layers.set(1); dyn.add(steam);
    count('蒸氣');
    // kitchen noren in the doorway (sways)
    var norenG = begin('暖簾', 0, 0, -D + 0.02, 0, true);
    add(new THREE.CylinderGeometry(0.014, 0.014, 1.16, 8), darker, 0, 1.86, 0, 0, 0, Math.PI / 2);
    ['台', null, '所'].forEach(function (ch, i) {
      var m = sway(new THREE.MeshStandardMaterial({ map: SG.tex('noren' + i, function () { return P.noren(ch, !ch); }), roughness: 0.9, side: THREE.DoubleSide }), 0.05, 1.3 + i * 0.25);
      add(new THREE.PlaneGeometry(0.355, 0.62, 4, 8), m, -0.365 + i * 0.365, 1.55, 0);
    });
    // genkan (west): step-down stone floor, shoe cabinet, shoes, umbrella stand
    curRoom = '玄關';
    cur = stat;
    add(G.planeM(2.2, 3.2), tx('genkanFloor', function () { return P.plaster('#b9b2a4', 35); }, 0.7, 0.8), -W - 1.1, 0.001, 1.3, -Math.PI / 2);
    add(G.boxM(0.1, H, 3.2), plaster, -W - 2.2, H / 2, 1.3); add(G.boxM(2.2, 0.08, 3.2), ceilW, -W - 1.1, H + 0.04, 1.3);
    begin('鞋櫃', -W - 1.85, 0, 1.3, Math.PI / 2); B(1.5, 0.9, 0.42, hinoki, 0, 0, 0, 0.02, true); for (var sd = 0; sd < 3; sd++) { B(0.46, 0.76, 0.02, honey, -0.5 + sd * 0.5, 0.07, 0.215, 0.012); S(0.015, iron, -0.5 + sd * 0.5 + 0.17, 0.5, 0.235); }
    begin('招財貓', -W - 1.85, 0.9, 1.0, Math.PI / 2); L([[0, 0], [0.1, 0], [0.12, 0.08], [0.09, 0.19], [0, 0.2]], white); S(0.085, white, 0, 0.26, 0.01, 1.1, 0.95, 1);
    add(new THREE.ConeGeometry(0.03, 0.05, 4), white, -0.055, 0.34, 0); add(new THREE.ConeGeometry(0.03, 0.05, 4), white, 0.055, 0.34, 0); add(new THREE.TorusGeometry(0.075, 0.012, 6, 16), col(0xc8452e, 0.5), 0, 0.2, 0, Math.PI / 2); S(0.02, brass, 0, 0.185, 0.085);
    add(new THREE.CapsuleGeometry(0.026, 0.09, 4, 8), white, 0.1, 0.27, 0.03, 0, 0, -0.2); S(0.012, black, -0.03, 0.275, 0.085); S(0.012, black, 0.03, 0.275, 0.085); S(0.045, brass, -0.02, 0.1, 0.1, 0.8, 1.1, 0.3);
    begin('玄關花瓶', -W - 1.85, 0.9, 1.75); L([[0, 0], [0.06, 0], [0.09, 0.1], [0.05, 0.22], [0.03, 0.3], [0.045, 0.33]], col(0x3f8f8a, 0.25)); for (var fl = 0; fl < 5; fl++) { add(new THREE.CylinderGeometry(0.004, 0.004, 0.3, 4), col(0x5d7a3a), (fl - 2) * 0.03, 0.46, 0, 0, 0, (fl - 2) * -0.16); S(0.03, col([0xf0c6c8, 0xffffff, 0xd9a93a][fl % 3], 0.6), (fl - 2) * 0.075, 0.62 - Math.abs(fl - 2) * 0.02, 0); }
    var shoeC = [0xc8452e, 0x2f4b7c, 0xf5f1e8, 0x6b4a2e, 0xd9a93a, 0x1e1a18, 0x7a9a54, 0xf29a4a];
    for (var sh = 0; sh < 8; sh++) {
      var gg = begin(sh < 2 ? '木屐' : sh < 5 ? '球鞋' : '拖鞋', -W - 0.5 - (sh % 4) * 0.02, 0, 0.75 + sh * 0.15, -Math.PI / 2 + (r() - 0.5) * 0.3);
      if (sh < 2) { B(0.1, 0.02, 0.24, hinoki, 0, 0.04, 0, 0.008); B(0.09, 0.04, 0.03, hinoki, 0, 0, 0.06, 0.004); B(0.09, 0.04, 0.03, hinoki, 0, 0, -0.06, 0.004); add(new THREE.TorusGeometry(0.035, 0.008, 5, 10, Math.PI), col(shoeC[sh], 0.7), 0, 0.06, 0.05); }
      else if (sh < 5) { B(0.1, 0.035, 0.26, white, 0, 0, 0, 0.015); S(0.06, col(shoeC[sh], 0.7), 0, 0.06, -0.03, 0.8, 0.75, 1.9); }
      else { B(0.1, 0.02, 0.25, col(shoeC[sh], 0.8), 0, 0, 0, 0.01); S(0.055, col(shoeC[sh], 0.8), 0, 0.03, 0.05, 0.92, 0.7, 1.2); }
    }
    begin('傘架', -W - 0.35, 0, 2.55); L([[0, 0], [0.12, 0], [0.13, 0.4], [0.14, 0.42]], col(0x3f8f8a, 0.3), 0, 0, 0, 12);
    [[0xc8452e, -0.2], [0x2f4b7c, 0.15], [0xd9a93a, 0.02]].forEach(function (u, i) { count('雨傘'); add(new THREE.ConeGeometry(0.045, 0.7, 8), col(u[0], 0.6), (i - 1) * 0.05, 0.5, 0.02 * i, 0, 0, u[1]); add(new THREE.TorusGeometry(0.03, 0.008, 5, 10, Math.PI), darker, (i - 1) * 0.05 - u[1] * 0.4, 0.88, 0.02 * i); });
    begin('玄關掛畫', -W - 2.14, 1.5, 1.3, Math.PI / 2); B(0.7, 0.5, 0.03, darker, 0, 0, 0, 0.01); PL(0.6, 0.4, tx('pSeig', function () { return P.seigaiha('#f1e7d2', '#2f4b7c', 32); }, null), 0, 0.25, 0.02);

    /* ================= NORTH WALL: tokonoma, step tansu, bookshelf, closet ================= */
    curRoom = '客廳';
    // tokonoma
    cur = stat;
    add(G.boxM(1.6, H, 0.1), tx('plasterT', function () { return P.plaster('#d9c9a0', 36); }, 1.2, 0.95), -3.7, H / 2, -D - 0.6); add(G.boxM(0.1, H, 0.6), plaster, -2.85, H / 2, -D - 0.3);
    begin('床之間', -3.7, 0, -D - 0.28); B(1.56, 0.12, 0.6, red, 0, 0, 0, 0.012, true); B(1.56, 0.1, 0.06, darker, 0, 2.0, 0.26, 0.01, true);
    plat(-4.5, -2.9, -D - 0.6, -D + 0.02, 0.12);
    var scrollT = SG.tex('scroll', function () { var c = P.gyotaku(); var g = c.getContext('2d'); g.drawImage(P.washi('#f3e8d0', 62), 0, 0, 256, 256, 52, 128, 408, 748); SG.inkText(g, '日日是好日', 256, 190, 104, '#1d1a1a', true, 9); g.fillStyle = PAL.vermilion; g.fillRect(300, 760, 56, 56); SG.inkText(g, '福', 328, 788, 40, '#f6ead2', false, 2); return c; });
    begin('掛軸', -3.7, 0.55, -D - 0.53); PL(0.62, 1.35, mat('scroll', { map: scrollT, roughness: 0.9 }), 0, 0.72, 0); add(new THREE.CylinderGeometry(0.022, 0.022, 0.7, 8), darker, 0, 0.04, 0.01, 0, 0, Math.PI / 2);
    begin('花器', -4.1, 0.12, -D - 0.25); L([[0, 0], [0.07, 0], [0.11, 0.08], [0.1, 0.2], [0.04, 0.3], [0.05, 0.34]], col(0x2f4b7c, 0.2)); add(G.tube([[0, 0.3, 0], [0.05, 0.6, 0.02], [0.22, 0.85, 0], [0.3, 1.0, 0.04]], 0.008, 10, 5), darker);
    for (var ik = 0; ik < 6; ik++) S(0.035, col(ik % 2 ? 0xf0c6c8 : 0xfff6f2, 0.6), 0.05 + ik * 0.05, 0.6 + ik * 0.075, (ik % 2) * 0.03, 1, 0.8, 1);
    begin('香爐', -3.25, 0.12, -D - 0.2); L([[0, 0], [0.04, 0], [0.07, 0.04], [0.06, 0.08]], brass); C(0.002, 0.002, 0.12, col(0x7a5a3a), 0, 0.08, 0, 4);
    // step tansu (stairs for cats): 4 steps, each 0.45 wide and 0.45 high
    var tansu = begin('階段箪笥', -1.8, 0, -D + 0.32);
    for (var st = 0; st < 4; st++) {
      var hh = 0.45 * (4 - st), xx = -0.675 + st * 0.45;
      B(0.45, hh, 0.56, red, xx, 0, 0, 0.012, true);
      for (var dr = 0; dr < 4 - st; dr++) { B(0.39, 0.37, 0.02, darker, xx, dr * 0.45 + 0.04, 0.275, 0.012); add(new THREE.TorusGeometry(0.035, 0.007, 5, 10, Math.PI), iron, xx, dr * 0.45 + 0.2, 0.292, Math.PI); }
      plat(-1.8 + xx - 0.225, -1.8 + xx + 0.225, -D + 0.04, -D + 0.6, hh);
    }
    function daruma(x, y, z, s) { begin('達摩', x, y, z); L([[0, 0], [0.07 * s, 0], [0.1 * s, 0.08 * s], [0.085 * s, 0.17 * s], [0, 0.2 * s]], col(0xc8452e, 0.4)); S(0.055 * s, cream, 0, 0.12 * s, 0.05 * s, 1, 0.9, 0.6); S(0.012 * s, black, -0.022 * s, 0.13 * s, 0.085 * s); S(0.012 * s, black, 0.022 * s, 0.13 * s, 0.085 * s); }
    function kokeshi(x, y, z, c) { begin('木芥子', x, y, z); L([[0, 0], [0.04, 0], [0.045, 0.1], [0.035, 0.16]], hinoki); C(0.046, 0.046, 0.04, col(c, 0.5), 0, 0.03, 0, 12); S(0.05, cream, 0, 0.2, 0); S(0.052, black, 0, 0.215, -0.008, 1, 0.8, 0.9); }
    daruma(-2.47, 1.8, -D + 0.3, 1.2); kokeshi(-2.05, 1.35, -D + 0.3, 0xc8452e); kokeshi(-1.93, 1.35, -D + 0.36, 0x2f4b7c); daruma(-1.6, 0.9, -D + 0.28, 0.8);
    begin('座鐘', -1.12, 0.45, -D + 0.3); B(0.18, 0.2, 0.08, darker, 0, 0, 0, 0.03); C(0.07, 0.07, 0.085, cream, 0, 0.03, 0, 16).rotation.x = Math.PI / 2;
    // bookshelf with many books
    var bs = begin('書架', 1.5, 0, -D + 0.24);
    B(1.5, 1.9, 0.04, dark, 0, 0, -0.2, 0.008, true); B(0.05, 1.9, 0.44, dark, -0.75, 0, 0, 0.01, true); B(0.05, 1.9, 0.44, dark, 0.75, 0, 0, 0.01, true);
    for (var sv = 0; sv < 6; sv++) B(1.5, 0.04, 0.44, dark, 0, sv * 0.372, 0, 0.008, true);
    plat(0.75, 2.25, -D + 0.02, -D + 0.46, 1.9);
    var bookC = [0xc8452e, 0x2f4b7c, 0xd9a93a, 0x7a9a54, 0xf1e7d2, 0x5e4a7a, 0x3f8f8a, 0xf29a4a, 0x6b4a2e, 0xe7a0a8, 0x1e1a18, 0x4aa3e0];
    var paper = col(0xf6efdc, 0.9);
    function book(x, y, z, hgt, th, dep, c, lean, flat) {
      begin('書', x, y, z); cur.rotation.z = lean || 0; if (flat) { cur.rotation.z = Math.PI / 2; cur.rotation.y = flat; }
      B(th, hgt, dep, col(c, 0.7), 0, 0, 0, 0.004); B(th * 0.78, hgt * 0.96, dep * 0.96, paper, 0, hgt * 0.02, -dep * 0.04, 0.002);
      B(th * 1.01, hgt * 0.1, dep * 0.4, col(0xf6efdc, 0.8), 0, hgt * 0.68, dep * 0.31, 0.002);
    }
    for (sv = 0; sv < 5; sv++) {
      var bx = -0.7, yy = sv * 0.372 + 0.04, kind = sv;
      while (bx < 0.66) {
        var th = 0.045 + r() * 0.05, hg = 0.22 + r() * 0.1;
        if (kind === 1 && bx > -0.1 && bx < 0.3) { bx += 0.4; continue; } // gap for the radio
        if (kind === 3 && bx > 0.25) { bx = 1; continue; }                // gap for the plant
        if (r() < 0.08) { bx += 0.05; continue; }
        book(1.5 + bx + th / 2, yy, -D + 0.22, hg, th, 0.2 + r() * 0.06, bookC[Math.floor(r() * bookC.length)], r() < 0.12 ? -0.14 : 0);
        bx += th + 0.004;
      }
    }
    begin('收音機', 1.6, 0.412, -D + 0.24); B(0.32, 0.18, 0.12, col(0x7a9a54, 0.5), 0, 0, 0, 0.03); C(0.055, 0.055, 0.01, black, -0.07, 0.035, 0.062, 16).rotation.x = Math.PI / 2; C(0.02, 0.02, 0.02, brass, 0.09, 0.1, 0.062, 10).rotation.x = Math.PI / 2; C(0.02, 0.02, 0.02, brass, 0.09, 0.04, 0.062, 10).rotation.x = Math.PI / 2;
    function plantPot(x, y, z, s, c, type, leaves) {
      begin(type, x, y, z);
      var pr = (leaves === monstera ? 0.34 : leaves === snake ? 0.1 : 0.16) * s, ph = (leaves === monstera ? 0.62 : leaves === snake ? 0.56 : 0.5) * s; plat(x - pr, x + pr, z - pr, z + pr, y + ph, y); // owner bug report: a cat could hide inside a plant. Pot and leaves are solid now L([[0, 0], [0.07 * s, 0], [0.1 * s, 0.14 * s], [0.105 * s, 0.15 * s]], col(c, 0.5)); C(0.095 * s, 0.095 * s, 0.01, col(0x3a2a1e, 1), 0, 0.14 * s, 0, 12);
      leaves(s);
    }
    function snake(s) { for (var i = 0; i < 7; i++) { var a = i * 0.9, m = add(new THREE.ConeGeometry(0.03 * s, (0.35 + (i % 3) * 0.1) * s, 5), i & 1 ? leafM : leafD, Math.cos(a) * 0.04 * s, (0.15 + 0.2) * s, Math.sin(a) * 0.04 * s, Math.sin(a) * 0.2, 0, -Math.cos(a) * 0.2); m.scale.z = 0.35; } }
    function monstera(s) { for (var i = 0; i < 8; i++) { var a = i * 0.85, rr = (0.16 + (i % 3) * 0.06) * s, hh2 = (0.3 + (i % 4) * 0.12) * s; add(G.tube([[0, 0.14 * s, 0], [Math.cos(a) * rr * 0.5, hh2 * 0.8, Math.sin(a) * rr * 0.5], [Math.cos(a) * rr, hh2, Math.sin(a) * rr]], 0.007 * s, 6, 4), leafD); var lf = add(new THREE.CircleGeometry(0.11 * s, 9), i & 1 ? leafM : leafD, Math.cos(a) * rr, hh2 + 0.01, Math.sin(a) * rr, -1.1, a, 0); lf.material.side = THREE.DoubleSide; lf.scale.y = 1.25; } }
    function bonsai(s) { add(G.tube([[0, 0.14 * s, 0], [0.04 * s, 0.26 * s, 0], [-0.03 * s, 0.36 * s, 0.02 * s], [0.05 * s, 0.44 * s, 0]], 0.016 * s, 8, 6), darker); S(0.09 * s, leafD, 0.06 * s, 0.47 * s, 0, 1.3, 0.6, 1); S(0.07 * s, leafM, -0.06 * s, 0.38 * s, 0.02 * s, 1.3, 0.6, 1); S(0.06 * s, leafD, 0.1 * s, 0.33 * s, -0.02 * s, 1.3, 0.6, 1); }
    plantPot(2.05, 1.156, -D + 0.24, 0.7, 0xf5f1e8, '虎尾蘭', snake);
    plantPot(1.05, 1.9, -D + 0.24, 0.9, 0x2f4b7c, '盆栽松', bonsai);
    begin('紙箱', 1.75, 1.9, -D + 0.24, 0.1); B(0.42, 0.24, 0.3, tx('card', function () { return P.plaster('#c9a36c', 37); }, 0.5, 0.9), 0, 0, 0, 0.008); B(0.44, 0.02, 0.06, cream, 0, 0.23, 0, 0.004);
    /* ================= CENTRE: kotatsu on the tatami ================= */
    var KX = TX, KZ = TZ;
    begin('暖桌', KX, 0.03, KZ);
    B(1.5, 0.3, 1.5, cloth.ichiRed, 0, 0, 0, 0.14, true); B(1.56, 0.02, 1.56, cloth.ichiRed, 0, 0.0, 0, 0.008, true); B(1.1, 0.05, 1.1, red, 0, 0.3, 0, 0.02, true);
    plat(KX - 0.55, KX + 0.55, KZ - 0.55, KZ + 0.55, 0.38); blob(KX, KZ, 2.3, 2.3, 0.03);
    [['seigaiha', 0, 1.12], ['asanoha', 1.12, 0], ['shippo', 0, -1.12], ['yagasuri', -1.12, 0]].forEach(function (z, i) {
      begin('座墊', KX + z[1], 0.03, KZ + z[2], (r() - 0.5) * 0.3); B(0.56, 0.09, 0.56, cloth[z[0]], 0, 0, 0, 0.04, true); S(0.02, col(0xc8452e, 0.7), 0, 0.09, 0);
      plat(KX + z[1] - 0.28, KX + z[1] + 0.28, KZ + z[2] - 0.28, KZ + z[2] + 0.28, 0.12);
    });
    begin('蜜柑籃', KX + 0.05, 0.38, KZ - 0.05); L([[0, 0], [0.11, 0], [0.15, 0.07], [0.155, 0.075]], tx('basket', null, 0.08));
    begin('茶壺', KX - 0.3, 0.38, KZ + 0.25, 0.6); L([[0, 0], [0.06, 0], [0.085, 0.05], [0.07, 0.1], [0.03, 0.115]], col(0x4a3020, 0.35)); S(0.015, col(0x4a3020, 0.35), 0, 0.125, 0); add(new THREE.CylinderGeometry(0.01, 0.016, 0.07, 6), col(0x4a3020, 0.35), 0.09, 0.07, 0, 0, 0, -1); add(new THREE.TorusGeometry(0.06, 0.006, 5, 12, Math.PI), darker, 0, 0.11, 0);
    begin('仙貝盤', KX + 0.32, 0.38, KZ + 0.28); C(0.11, 0.08, 0.02, col(0x2f4b7c, 0.3), 0, 0, 0); for (var sn = 0; sn < 4; sn++) C(0.035, 0.035, 0.01, col(0xc98a3a, 0.7), Math.cos(sn * 1.6) * 0.04, 0.022 + sn * 0.006, Math.sin(sn * 1.6) * 0.04, 10);
    begin('面紙盒', KX - 0.32, 0.38, KZ - 0.3, 0.3); B(0.22, 0.07, 0.12, cloth.sakura, 0, 0, 0, 0.012, true); add(new THREE.ConeGeometry(0.03, 0.06, 5), white, 0, 0.09, 0);
    begin('遙控器', KX + 0.3, 0.38, KZ - 0.33, -0.5); B(0.05, 0.018, 0.17, black, 0, 0, 0, 0.006); C(0.007, 0.007, 0.004, col(0xc8452e), 0, 0.018, 0.06, 8);
    begin('報紙', KX + 1.05, 0.031, KZ + 1.0, 0.4); B(0.3, 0.012, 0.42, tx('news', function () { return P.stripes(['#e9e4d6', '#8a8880', '#e9e4d6', '#b5b2a8'], [6, 2, 5, 1]); }, [0.04, 0.04]), 0, 0, 0, 0.004, true);
    // pendant lamp above the kotatsu (cord sways)
    var lamp = begin('吊燈', KX, H - 0.1, KZ, 0, true);
    add(new THREE.CylinderGeometry(0.004, 0.004, 0.62, 5), black, 0, -0.31, 0);
    var shade = mat('lampShade', { map: SG.tex('washi2', function () { return P.lantern('', '#f7ecd2', '#000', 26); }), emissive: 0xffc070, emissiveIntensity: 1.5, roughness: 0.9, side: THREE.DoubleSide });
    add(G.latheS([[0.07, 0], [0.26, -0.1], [0.3, -0.2], [0.24, -0.3], [0.12, -0.34]], 24), shade, 0, -0.6, 0); add(new THREE.TorusGeometry(0.12, 0.012, 6, 20), darker, 0, -0.94, 0, Math.PI / 2); add(new THREE.CylinderGeometry(0.075, 0.075, 0.03, 12), darker, 0, -0.6, 0);
    S(0.05, mat('bulb', { color: 0xfff0d0, emissive: 0xffd9a0, emissiveIntensity: 6 }), 0, -0.82, 0);
    var cord = add(new THREE.CylinderGeometry(0.002, 0.002, 0.3, 4), black, 0.1, -1.08, 0); var knob = S(0.015, col(0xc8452e), 0.1, -1.24, 0); cord.userData.keep = knob.userData.keep = true;
    glow(KX, H - 0.9, KZ, 1.5, 0xffc880, 0.5);
    updaters.push(function (t) { lamp.rotation.z = Math.sin(t * 1.1) * 0.012; lamp.rotation.x = Math.cos(t * 0.9) * 0.01; cord.rotation.z = knob.position.x = 0; knob.position.x = 0.1 + Math.sin(t * 2.1) * 0.02; cord.position.x = 0.1 + Math.sin(t * 2.1) * 0.01; });

    /* ================= WEST: sofa, side table, floor lamp, boxes ================= */
    begin('沙發', -W + 0.55, 0, -1.55, Math.PI / 2);
    B(2.0, 0.26, 0.86, cloth.teal, 0, 0.1, 0, 0.09, true); B(2.0, 0.5, 0.24, cloth.teal, 0, 0.3, -0.33, 0.1, true); B(0.2, 0.36, 0.86, cloth.teal, -1.0, 0.2, 0, 0.09, true); B(0.2, 0.36, 0.86, cloth.teal, 1.0, 0.2, 0, 0.09, true);
    [-0.8, 0.8].forEach(function (x) { C(0.03, 0.02, 0.1, darker, x, 0, 0.3, 8); C(0.03, 0.02, 0.1, darker, x, 0, -0.3, 8); });
    plat(-W + 0.1, -W + 1.0, -2.65, -0.45, 0.36); plat(-W + 0.08, -W + 0.36, -2.65, -0.45, 0.8); blob(-W + 0.55, -1.55, 1.3, 2.5);
    [['yagasuri', -0.6, 0.2], ['shippo', -0.1, -0.15], ['kikko', 0.5, 0.25], ['mustard', 0.75, -0.1]].forEach(function (c) { begin('抱枕', -W + 0.42, 0.42, -1.55 + c[1], Math.PI / 2 + c[2]); cur.rotation.z = 0; cur.rotation.x = -0.35; B(0.4, 0.4, 0.14, cloth[c[0]], 0, 0, 0, 0.065, true); });
    begin('毛毯', -W + 0.7, 0.36, -2.3, 0.2); B(0.55, 0.07, 0.5, cloth.stripeG, 0, 0, 0, 0.03, true); B(0.3, 0.3, 0.07, cloth.stripeG, 0.3, -0.22, 0.15, 0.03, true);
    begin('邊桌', -W + 0.5, 0, -0.05); C(0.26, 0.26, 0.03, hinoki, 0, 0.5, 0, 24); C(0.025, 0.025, 0.5, darker, 0, 0, 0, 8); C(0.16, 0.18, 0.02, darker, 0, 0, 0, 16); plat(-W + 0.26, -W + 0.74, -0.29, 0.19, 0.53);
    begin('熱水瓶', -W + 0.42, 0.53, -0.1); L([[0, 0], [0.07, 0], [0.075, 0.2], [0.05, 0.26], [0, 0.27]], col(0xf5f1e8, 0.3)); B(0.05, 0.03, 0.04, col(0xc8452e, 0.4), 0, 0.2, 0.07, 0.008); add(new THREE.TorusGeometry(0.05, 0.007, 5, 12, Math.PI), black, 0, 0.26, 0);
    var andon = begin('行燈', -W + 0.45, 0, 0.42);
    B(0.3, 0.03, 0.3, darker, 0, 0, 0, 0.008); B(0.26, 0.5, 0.26, mat('andon', { map: SG.tex('washi', null), emissive: 0xffb860, emissiveIntensity: 1.3, roughness: 0.9 }), 0, 0.05, 0, 0.01);
    [[-1, -1], [1, -1], [-1, 1], [1, 1]].forEach(function (c) { B(0.025, 0.6, 0.025, darker, c[0] * 0.135, 0, c[1] * 0.135, 0.004); }); B(0.3, 0.025, 0.3, darker, 0, 0.56, 0, 0.006); glow(-W + 0.45, 0.32, 0.42, 1.0, 0xffb060, 0.45); plat(-W + 0.3, -W + 0.6, 0.27, 0.57, 0.6);
    begin('雜誌架', -W + 0.3, 0, -2.95, 0.3); B(0.36, 0.3, 0.2, tx('basket', null, 0.08), 0, 0, 0, 0.02); for (var mg = 0; mg < 4; mg++) B(0.3, 0.26, 0.012, col(bookC[mg * 2], 0.6), 0, 0.12, -0.06 + mg * 0.035, 0.003).rotation.z = (mg - 1.5) * 0.06;
    // cardboard boxes by the genkan door
    var card = tx('card', null, 0.5, 0.9);
    function cbox(x, y, z, w, h, d, ry, label, open) {
      var g = begin('紙箱', x, y, z, ry); B(w, h, d, card, 0, 0, 0, 0.008, true);
      var cr = Math.abs(Math.cos(ry || 0)), sr = Math.abs(Math.sin(ry || 0)), hx = cr * w / 2 + sr * d / 2, hz = sr * w / 2 + cr * d / 2; plat(x - hx, x + hx, z - hz, z + hz, y + h, y); // owner bug report: cats walked into boxes. Boxes are solid now (and so count for the buried-too-deep warning) B(0.07, h * 1.004, d * 1.01, cream, 0, 0, 0, 0.003);
      if (label) PL(w * 0.5, h * 0.5, mat('lab' + label, { map: SG.tex('lab' + label, function () { return P.label(label, '#c9a36c', '#7a3a1e'); }), roughness: 0.9 }), w * 0.2, h * 0.5, d / 2 + 0.002);
      if (open) { B(w, 0.01, d * 0.48, card, 0, h, -d * 0.7, 0.003).rotation.x = 0.9; B(w, 0.01, d * 0.48, card, 0, h, d * 0.7, 0.003).rotation.x = -0.9; }
      platG(g, w, d, h); return g;
    }
    cbox(-W + 0.55, 0, 2.15, 0.62, 0.44, 0.46, 0.05, 'みかん'); cbox(-W + 0.5, 0.44, 2.13, 0.46, 0.34, 0.4, -0.12, '割れ物'); cbox(-W + 1.25, 0, 2.1, 0.5, 0.4, 0.5, 0.25, null, true);
    blob(-W + 0.8, 2.12, 1.7, 1.0);
    begin('掃帚', -W + 0.14, 0, 0.45, 0); add(new THREE.CylinderGeometry(0.012, 0.012, 1.2, 6), hinoki, 0, 0.75, 0, 0, 0, 0.08); add(new THREE.ConeGeometry(0.1, 0.3, 8), col(0xc9a86a, 0.9), 0.05, 0.15, 0).scale.z = 0.4;
    // west wall decor
    begin('月曆', -W + 0.06, 1.25, -0.9, Math.PI / 2);
    PL(0.42, 0.6, mat('cal', { map: SG.tex('cal', function () { var c = P.washi('#fbf6ea', 44); var g = c.getContext('2d'); g.fillStyle = PAL.vermilion; g.fillRect(0, 0, 256, 70); SG.inkText(g, '十一月', 128, 36, 40, '#fff6e6', false, 3); g.fillStyle = '#2a2320'; g.font = '18px sans-serif'; g.textAlign = 'center'; for (var d = 1; d <= 30; d++) { g.fillStyle = (d + 5) % 7 === 0 ? PAL.vermilion : '#2a2320'; g.fillText(String(d), 24 + ((d + 5) % 7) * 35, 104 + Math.floor((d + 5) / 7) * 30); } return c; }), roughness: 0.9 }), 0, 0.3, 0);
    [['pAsa', 'asanoha', -2.4, 1.5, 0.5, 0.5], ['pYaga', 'yagasuri', -1.75, 1.35, 0.36, 0.5], ['pShip', 'shippo', -2.0, 0.95 + 0.9, 0.3, 0.3]].forEach(function (f) {
      begin('掛畫', -W + 0.06, f[3] - f[5] / 2, f[2], Math.PI / 2); B(f[4] + 0.08, f[5] + 0.08, 0.03, f[1] === 'yagasuri' ? brass : darker, 0, 0, 0, 0.008); PL(f[4], f[5], cloth[f[1]], 0, f[5] / 2 + 0.04, 0.018, 0, 0, 0, true);
    });

    /* ================= EAST: TV, fish tank, clock, cat shelves, cat tree ================= */
    begin('電視櫃', W - 0.36, 0, -0.75, -Math.PI / 2); B(1.9, 0.42, 0.5, dark, 0, 0, 0, 0.02, true); B(0.86, 0.3, 0.02, honey, -0.46, 0.06, 0.25, 0.01); B(0.86, 0.3, 0.02, honey, 0.46, 0.06, 0.25, 0.01); S(0.016, brass, -0.1, 0.22, 0.27); S(0.016, brass, 0.1, 0.22, 0.27);
    plat(W - 0.62, W - 0.1, -1.7, 0.2, 0.42); blob(W - 0.36, -0.75, 0.8, 2.2);
    var tvM = new THREE.ShaderMaterial({
      uniforms: { uTime: uTime },
      vertexShader: 'varying vec2 vUv; void main(){ vUv=uv; gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.); }',
      fragmentShader: ['uniform float uTime; varying vec2 vUv;',
        'void main(){ float sc=floor(uTime/4.); vec2 p=vUv; vec3 skyc=mix(vec3(0.95,0.75,0.5),vec3(0.35,0.6,0.95),p.y+0.2*sin(sc));',
        '  float hill=0.32+0.08*sin(p.x*6.+sc*2.)+0.04*sin(p.x*17.+uTime*0.3); vec3 c=mix(vec3(0.3,0.62,0.35)+0.1*sin(sc*vec3(1.,2.,3.)),skyc,smoothstep(hill-0.005,hill+0.005,p.y));',
        '  vec2 b=vec2(fract(uTime*0.11+0.2),0.72+0.06*sin(uTime*1.3)); c=mix(c,vec3(1.),smoothstep(0.07,0.05,length((p-b)*vec2(1.,1.7))));', // drifting cloud
        '  c*=0.9+0.1*sin(p.y*240.); c*=1.-0.35*smoothstep(0.35,0.75,length(p-0.5));',
        '  gl_FragColor=vec4(c*1.9,1.); }'].join('\n')
    });
    begin('電視', W - 0.3, 0.42, -0.75, -Math.PI / 2); B(1.25, 0.74, 0.05, black, 0, 0.06, 0, 0.015); PL(1.17, 0.66, tvM, 0, 0.43, 0.027); B(0.4, 0.06, 0.2, black, 0, 0, 0, 0.01);
    begin('遊戲機', W - 0.36, 0.42, -1.5, -Math.PI / 2 + 0.2); B(0.26, 0.05, 0.2, col(0xf5f1e8, 0.4), 0, 0, 0, 0.012); C(0.02, 0.02, 0.006, col(0xc8452e), 0.07, 0.05, 0.03, 10);
    begin('盆栽松', W - 0.36, 0.42, 0.02); L([[0, 0], [0.07, 0], [0.1, 0.1]], col(0x7a4a2a, 0.5)); bonsai(0.75);
    var tvL = new THREE.PointLight(0x9fc4ff, 1.2, 4.5, 2); tvL.position.set(W - 1.0, 0.9, -0.75); tvL.layers.set(1); room.add(tvL);
    updaters.push(function (t) { var sc = Math.floor(t / 4); tvL.intensity = 1.1 + 0.5 * Math.sin(sc * 12.9898) + 0.12 * Math.sin(t * 9); tvL.color.setHSL(0.58 + 0.08 * Math.sin(sc * 3.1), 0.6, 0.7); });
    // fish tank on a cabinet
    begin('魚缸櫃', W - 0.36, 0, 1.25, -Math.PI / 2); B(1.0, 0.7, 0.46, honey, 0, 0, 0, 0.02, true); B(0.44, 0.56, 0.02, hinoki, -0.24, 0.07, 0.23, 0.01); B(0.44, 0.56, 0.02, hinoki, 0.24, 0.07, 0.23, 0.01);
    plat(W - 0.6, W - 0.12, 0.75, 1.75, 1.2); blob(W - 0.36, 1.25, 0.8, 1.3);
    var tank = begin('魚缸', W - 0.36, 0.7, 1.25, -Math.PI / 2, true);
    B(0.86, 0.03, 0.38, black, 0, 0, 0, 0.008); B(0.86, 0.03, 0.38, black, 0, 0.47, 0, 0.008);
    add(new THREE.BoxGeometry(0.8, 0.05, 0.32), tx('gravelT', function () { return P.plaster('#d9c9a0', 59); }, 0.2, 1), 0, 0.055, 0);
    var tankW = new THREE.ShaderMaterial({
      transparent: true, depthWrite: false, uniforms: { uTime: uTime },
      vertexShader: 'varying vec3 vN; varying vec3 vV; varying vec3 vP; void main(){ vP=position; vN=normalize(normalMatrix*normal); vec4 mv=modelViewMatrix*vec4(position,1.); vV=normalize(-mv.xyz); gl_Position=projectionMatrix*mv; }',
      fragmentShader: 'uniform float uTime; varying vec3 vN; varying vec3 vV; varying vec3 vP; void main(){ float f=pow(1.-abs(dot(vN,vV)),2.5); float ca=sin(vP.x*26.+uTime*1.7)*sin(vP.y*21.-uTime*1.3)*0.5+0.5; vec3 c=mix(vec3(0.35,0.75,0.85),vec3(0.9,1.0,1.0),f)+ca*0.12; gl_FragColor=vec4(c*1.2,0.2+f*0.5+ca*0.05); }'
    });
    add(new THREE.BoxGeometry(0.82, 0.42, 0.34), tankW, 0, 0.25, 0).renderOrder = 5;
    for (var wd = 0; wd < 5; wd++) { var w0 = add(new THREE.ConeGeometry(0.02, 0.2 + wd * 0.03, 5), leafM, -0.3 + wd * 0.14, 0.17, -0.08 + (wd % 2) * 0.1); w0.scale.z = 0.4; }
    S(0.05, stoneD, 0.2, 0.09, 0.05, 1.3, 0.8, 1);
    var fish = [];
    [0xf06a2a, 0xe9b23a, 0xf5f0e6, 0xd9432b, 0x4aa3e0, 0xf29a4a].forEach(function (c, i) {
      var g = new THREE.Group(); tank.add(g); cur = g; count('金魚');
      S(0.03, col(c, 0.35), 0, 0, 0, 0.6, 0.85, 1.3); var tl = add(new THREE.ConeGeometry(0.025, 0.045, 5), col(c, 0.35), 0, 0, -0.05, Math.PI / 2, 0, 0); tl.scale.x = 0.2; tl.userData.keep = true; S(0.005, black, 0.012, 0.006, 0.03);
      fish.push({ g: g, tl: tl, ph: i * 1.7, y: 0.14 + (i % 3) * 0.1, sp: 0.5 + (i % 4) * 0.12 });
    });
    var bubbles = []; for (var bb = 0; bb < 8; bb++) { cur = tank; bubbles.push(S(0.006 + (bb % 3) * 0.003, mat('bubble', { color: 0xffffff, emissive: 0xbfefff, emissiveIntensity: 1.2, transparent: true, opacity: 0.7 }), -0.3, 0.1, 0.1)); }
    count('氣泡');
    updaters.push(function (t) {
      fish.forEach(function (f) { var a = t * f.sp + f.ph, x = Math.sin(a) * 0.3, z = Math.sin(a * 2.0 + f.ph) * 0.09; f.g.position.set(x, f.y + Math.sin(a * 1.3) * 0.03, z); f.g.rotation.y = Math.cos(a) > 0 ? Math.PI / 2 : -Math.PI / 2; f.tl.rotation.y = Math.sin(t * 9 + f.ph) * 0.7; });
      bubbles.forEach(function (b, i) { var k = (t * 0.35 + i * 0.125) % 1; b.position.set(-0.3 + Math.sin(k * 9 + i) * 0.012, 0.09 + k * 0.36, 0.1); });
    });
    var tankL = new THREE.PointLight(0x9fe8ff, 0.5, 2.2, 2); tankL.position.set(W - 0.6, 1.0, 1.25); tankL.layers.set(1); room.add(tankL);
    begin('飼料罐', W - 0.36, 0.7, 1.82); C(0.035, 0.035, 0.1, col(0xd9a93a, 0.4), 0, 0, 0, 10); C(0.037, 0.037, 0.02, col(0xc8452e, 0.4), 0, 0.1, 0, 10);
    // pendulum clock
    var clock = begin('擺鐘', W - 0.09, 1.25, 0.42, -Math.PI / 2, true);
    B(0.3, 0.72, 0.1, red, 0, 0, 0, 0.02); C(0.11, 0.11, 0.012, cream, 0, 0.49, 0.052, 20).rotation.x = Math.PI / 2; add(new THREE.TorusGeometry(0.115, 0.012, 6, 24), brass, 0, 0.5, 0.058); add(new THREE.ConeGeometry(0.19, 0.08, 4), darker, 0, 0.76, 0, 0, Math.PI / 4, 0);
    var hHand = B(0.012, 0.06, 0.004, black, 0, 0, 0, 0.001), mHand = B(0.008, 0.09, 0.004, black, 0, 0, 0, 0.001);
    var hp = new THREE.Group(), mp = new THREE.Group(); hp.position.set(0, 0.5, 0.062); mp.position.set(0, 0.5, 0.066); clock.add(hp, mp); hp.add(hHand); mp.add(mHand); hHand.position.set(0, 0.03, 0); mHand.position.set(0, 0.045, 0);
    var pend = new THREE.Group(); pend.position.set(0, 0.34, 0.03); clock.add(pend); cur = pend; add(new THREE.CylinderGeometry(0.004, 0.004, 0.24, 5), brass, 0, -0.12, 0); C(0.04, 0.04, 0.01, brass, 0, -0.27, 0, 16).rotation.x = Math.PI / 2;
    updaters.push(function (t) { pend.rotation.z = Math.sin(t * Math.PI) * 0.32; mp.rotation.z = -t / 60 * Math.PI * 2 / 60 - 1.0; hp.rotation.z = -t / 3600 * Math.PI * 2 / 12 - 2.4; });
    // cat shelves stepping up the east wall
    [[-2.9, 0.75], [-2.35, 1.15], [-2.9, 1.55]].forEach(function (s, i) {
      begin('貓跳台', W - 0.2, s[1], s[0], -Math.PI / 2); B(0.5, 0.04, 0.3, hinoki, 0, 0, 0, 0.012, true); B(0.04, 0.14, 0.04, darker, -0.18, -0.14, -0.1, 0.006); B(0.04, 0.14, 0.04, darker, 0.18, -0.14, -0.1, 0.006);
      plat(W - 0.36, W - 0.04, s[0] - 0.25, s[0] + 0.25, s[1] + 0.04, s[1] - 0.02);
    });
    daruma(W - 0.2, 1.59, -2.9, 0.7);
    // cat tree
    var ct = begin('貓爬架', W - 0.55, 0, 2.05, 0);
    var sisal = tx('sisal', function () { return P.stripes(['#cdb48a', '#b59a6c'], [5, 4]); }, [0.03, 0.03], 0.95), carpet = tx('carpet', function () { return P.plaster('#d9c8a8', 63); }, 0.3, 1);
    B(0.7, 0.06, 0.7, carpet, 0, 0, 0, 0.02, true); add(new THREE.CylinderGeometry(0.05, 0.05, 1.5, 12), sisal, -0.2, 0.75, -0.2).rotation.y = 0; add(new THREE.CylinderGeometry(0.05, 0.05, 0.95, 12), sisal, 0.2, 0.5, 0.15);
    B(0.46, 0.05, 0.46, carpet, 0.14, 0.52, 0.12, 0.02, true); B(0.5, 0.05, 0.5, carpet, -0.05, 1.0, -0.1, 0.02, true); B(0.4, 0.05, 0.4, carpet, -0.2, 1.5, -0.2, 0.02, true);
    add(G.latheS([[0.2, 0], [0.21, 0.08], [0.19, 0.1]], 16), cloth.mustard, -0.2, 1.55, -0.2);
    plat(W - 0.9, W - 0.2, 1.7, 2.4, 0.06); plat(W - 0.64, W - 0.18, 1.94, 2.4, 0.57, 0.5); plat(W - 0.85, W - 0.35, 1.7, 2.2, 1.05, 0.98); plat(W - 0.95, W - 0.55, 1.65, 2.05, 1.6, 1.48); blob(W - 0.55, 2.05, 1.1, 1.1);
    var dangle = begin(null, W - 0.42, 1.0, 2.2, 0, true); add(new THREE.CylinderGeometry(0.002, 0.002, 0.25, 4), black, 0, -0.125, 0); S(0.03, col(0xc8452e, 0.7), 0, -0.27, 0);
    updaters.push(function (t) { dangle.rotation.z = Math.sin(t * 2.3) * 0.25; dangle.rotation.x = Math.cos(t * 1.7) * 0.15; });
    // framed prints + wall scroll on the east wall
    [['seigaiha', -0.75, 1.75, 0.5, 0.36], ['sakura', 1.55, 1.85, 0.34, 0.34], ['ichimatsu', 2.05, 1.7, 0.26, 0.4]].forEach(function (f) { begin('掛畫', W - 0.06, f[2] - f[4] / 2, f[1], -Math.PI / 2); B(f[3] + 0.07, f[4] + 0.07, 0.03, hinoki, 0, 0, 0, 0.008); PL(f[3], f[4], cloth[f[0]], 0, f[4] / 2 + 0.035, 0.018, 0, 0, 0, true); });

    /* ================= OPEN FLOOR: rug, toys, laundry, fan, plants ================= */
    begin('地毯', 2.55, 0, 0.9, 0); PL(2.3, 1.7, mat('rug', { map: SG.tex('rug', P.rug), roughness: 0.95 }), 0, 0.012, 0, -Math.PI / 2); plat(1.4, 3.7, 0.05, 1.75, 0.012);
    begin('懶骨頭', 2.9, 0.012, 1.25); S(0.42, cloth.mustard, 0, 0.22, 0, 1, 0.62, 1); plat(2.6, 3.2, 0.95, 1.55, 0.42); blob(2.9, 1.25, 1.2, 1.2, 0.012);
    begin('洗衣籃', -2.6, 0, 2.05); L([[0, 0], [0.2, 0], [0.25, 0.3], [0.26, 0.31]], tx('basket', null, 0.08), 0, 0, 0, 16); B(0.34, 0.1, 0.3, cloth.stripe, 0, 0.26, 0, 0.04, true); B(0.26, 0.08, 0.22, cloth.sakura, 0.03, 0.33, 0.02, 0.035, true); plat(-2.84, -2.36, 1.81, 2.29, 0.4); blob(-2.6, 2.05, 0.8, 0.8);
    [['asanoha', 0], ['ichimatsu', 1], ['yagasuri', 2], ['cream', 3], ['seigaiha', 4]].forEach(function (c) { begin('摺好的毛巾', -1.9, 0.0 + c[1] * 0.055, 2.1, 0.1 * (c[1] % 2)); B(0.34, 0.055, 0.24, cloth[c[0]], 0, 0, 0, 0.025, true); });
    plat(-2.08, -1.72, 1.97, 2.23, 0.28);
    // electric fan (oscillates, blades spin)
    var fan = begin('電風扇', -3.55, 0, 0.1, 0.9, true);
    C(0.16, 0.18, 0.04, white, 0, 0, 0, 20); C(0.025, 0.03, 0.62, white, 0, 0.04, 0, 10);
    var fanHead = new THREE.Group(); fanHead.position.set(0, 0.72, 0); fan.add(fanHead); cur = fanHead;
    S(0.07, white, 0, 0, -0.03, 1, 1, 1.3); add(new THREE.TorusGeometry(0.2, 0.008, 6, 28), col(0xd8d6d0, 0.3, { metalness: 0.6 }), 0, 0, 0.07); add(new THREE.TorusGeometry(0.2, 0.008, 6, 28), col(0xd8d6d0, 0.3, { metalness: 0.6 }), 0, 0, 0.0);
    for (var gr = 0; gr < 12; gr++) add(new THREE.CylinderGeometry(0.003, 0.003, 0.4, 4), col(0xd8d6d0, 0.3, { metalness: 0.6 }), 0, 0, 0.075, 0, 0, gr * Math.PI / 12);
    var blades = new THREE.Group(); blades.position.z = 0.04; fanHead.add(blades); cur = blades;
    for (var bl = 0; bl < 3; bl++) { var bm = add(new THREE.CircleGeometry(0.09, 10), mat('blade', { color: 0x4aa3e0, roughness: 0.3, transparent: true, opacity: 0.8, side: THREE.DoubleSide }), Math.cos(bl * 2.094) * 0.09, Math.sin(bl * 2.094) * 0.09, 0); bm.scale.y = 0.6; bm.rotation.z = bl * 2.094; }
    updaters.push(function (t) { blades.rotation.z = t * 22; fanHead.rotation.y = Math.sin(t * 0.55) * 0.75; });
    blob(-3.55, 0.1, 0.6, 0.6);
    // ceiling fan
    var cfan = begin('吊扇', 2.4, H - 0.02, 0.6, 0, true); C(0.03, 0.03, 0.3, darker, 0, -0.3, 0, 8); C(0.1, 0.12, 0.1, darker, 0, -0.4, 0, 16); S(0.07, mat('bulb', null), 0, -0.44, 0);
    var cb = new THREE.Group(); cb.position.y = -0.33; cfan.add(cb); cur = cb; for (var cf = 0; cf < 4; cf++) { var b4 = B(0.62, 0.012, 0.13, hinoki, 0.4, 0, 0, 0.005); var pv = new THREE.Group(); pv.rotation.y = cf * Math.PI / 2; cb.add(pv); pv.add(b4); b4.rotation.x = 0.16; }
    updaters.push(function (t) { cb.rotation.y = t * 2.6; });
    // plants
    plantPot(-W + 0.42, 0, -3.1 + 0.0, 1.9, 0xd9a93a, '龜背芋', monstera); plat(-W + 0.2, -W + 0.64, -3.32, -2.88, 0.28); blob(-W + 0.42, -3.1, 1.0, 1.0);
    plantPot(W - 0.4, 0, -2.0 + 0.2, 1.7, 0xc8452e, '虎尾蘭', snake); blob(W - 0.4, -1.8, 0.7, 0.7);
    plantPot(3.9, 0, EN + 0.9, 1.5, 0x2f4b7c, '龜背芋', monstera); plantPot(-3.9, 0, EN + 1.0, 1.4, 0xf5f1e8, '盆栽松', bonsai);
    begin('垃圾桶', 0.95, 0, -D + 0.75 + 0.0); L([[0, 0], [0.1, 0], [0.13, 0.28], [0.135, 0.29]], col(0x5e4a7a, 0.5), 0, 0, 0, 14);
    begin('蚊香豬', -1.0, 0, EN + 0.55, 2.4); S(0.11, col(0xe9dfc8, 0.4), 0, 0.1, 0, 1, 0.9, 1.25); C(0.05, 0.06, 0.03, col(0xe9dfc8, 0.4), 0, 0.07, 0.13, 10).rotation.x = Math.PI / 2; S(0.012, black, -0.04, 0.14, 0.1); S(0.012, black, 0.04, 0.14, 0.1);
    begin('座布團堆', 1.3, 0, EN + 0.75, 0.3); ['indigo', 'kikko', 'mustard'].forEach(function (c, i) { B(0.5, 0.09, 0.5, cloth[c], (i - 1) * 0.02, i * 0.09, 0, 0.04, true); }); plat(1.05, 1.55, EN + 0.5, EN + 1.0, 0.28);
    begin('西瓜', -1.9, 0, EN + 0.8); S(0.17, tx('melon', function () { return P.stripes(['#3f7a3a', '#1f4a24'], [22, 10]); }, [0.12, 0.12], 0.4), 0, 0.165, 0);
    // wind chime under the eave
    var chime = begin('風鈴', 0.9, 2.26, EN + 1.25, 0, true); add(new THREE.CylinderGeometry(0.002, 0.002, 0.12, 4), black, 0, -0.06, 0);
    add(G.latheS([[0.0, 0], [0.05, -0.015], [0.065, -0.06], [0.06, -0.09]], 16), mat('chimeGlass', { color: 0xbfe8f0, roughness: 0.1, transparent: true, opacity: 0.6, side: THREE.DoubleSide, emissive: 0x4a8a9a, emissiveIntensity: 0.4 }), 0, -0.12, 0);
    var tanzaku = new THREE.Group(); tanzaku.position.y = -0.2; chime.add(tanzaku); cur = tanzaku; add(new THREE.CylinderGeometry(0.0015, 0.0015, 0.14, 4), black, 0, -0.07, 0); var tz = PL(0.05, 0.2, mat('tanzaku', { map: SG.tex('tanzaku', function () { return P.label('涼', '#f6efdc', '#2f4b7c'); }), side: THREE.DoubleSide, roughness: 0.9 }), 0, -0.24, 0);
    updaters.push(function (t) { var w = Math.sin(t * 1.3) * 0.5 + Math.sin(t * 0.37) * 0.5; chime.rotation.z = w * 0.07; tanzaku.rotation.z = w * 0.5; tanzaku.rotation.y = t * 0.8 + Math.sin(t * 2.1); });
    // robot vacuum (roams a fixed loop, deterministic in round time)
    var vac = begin('掃地機器人', 0, 0, 0, 0, true); C(0.17, 0.17, 0.07, col(0xf5f1e8, 0.35), 0, 0.01, 0, 28); C(0.1, 0.1, 0.012, col(0x4aa3e0, 0.3), 0, 0.08, 0, 20); C(0.02, 0.02, 0.006, mat('vacLed', { color: 0x9fe870, emissive: 0x7fff60, emissiveIntensity: 3 }), 0, 0.092, 0.11, 8);
    var vblob = blob(0, 0, 0.5, 0.5); vblob.userData.keep = true;
    var vPath = [[1.5, -2.6], [3.6, -2.4], [3.4, -0.2], [1.6, -0.6], [1.5, 1.9], [-0.3, 2.1], [-3.2, 1.6], [-3.4, -0.3], [-2.7, -2.4], [0.2, -2.7]], vLen = [], vTot = 0;
    vPath.forEach(function (p, i) { var q = vPath[(i + 1) % vPath.length], l = Math.hypot(q[0] - p[0], q[1] - p[1]); vLen.push(l); vTot += l; });
    var vacState = { x: 0, z: 0, r: 0.17, top: 0.09 };
    updaters.push(function (t) {
      var d = (t * 0.32) % vTot, i = 0; while (d > vLen[i]) { d -= vLen[i]; i++; }
      var p = vPath[i], q = vPath[(i + 1) % vPath.length], k = d / vLen[i];
      vac.position.set(p[0] + (q[0] - p[0]) * k, 0, p[1] + (q[1] - p[1]) * k); vblob.position.x = vac.position.x; vblob.position.z = vac.position.z;
      var want = Math.atan2(q[0] - p[0], q[1] - p[1]); var dy = want - vac.rotation.y; while (dy > Math.PI) dy -= Math.PI * 2; while (dy < -Math.PI) dy += Math.PI * 2; vac.rotation.y += dy * 0.08;
      vacState.x = vac.position.x; vacState.z = vac.position.z;
    });

    /* ================= KNOCKABLE SMALL PROPS (simple physics) ================= */
    function knockable(type, x, y, z, rad, build, shape) {
      var g = begin(type, x, y, z, r() * 6, true); build();
      knock.push({ g: g, type: type, x: x, y: y, z: z, vx: 0, vy: 0, vz: 0, r: rad, shape: shape || 'ball', home: [x, y, z] });
    }
    var mk = col(0xf29a3a, 0.55);
    [[0, 0], [0.06, 0.03], [-0.05, 0.04], [0.01, -0.06], [0.02, 0.01]].forEach(function (m, i) { knockable('蜜柑', KX + 0.05 + m[0], 0.38 + 0.045 + (i === 4 ? 0.07 : 0.02), KZ - 0.05 + m[1], 0.042, function () { S(0.042, mk, 0, 0, 0, 1, 0.85, 1); S(0.006, leafD, 0, 0.034, 0); }); });
    knockable('蜜柑', KX - 0.1, 0.38 + 0.042, KZ + 0.4, 0.042, function () { S(0.042, mk, 0, 0, 0, 1, 0.85, 1); S(0.006, leafD, 0, 0.034, 0); });
    [[-0.36, 0.05, 0x7a9a54], [0.12, 0.38, 0x2f4b7c], [0.42, -0.12, 0xc8452e]].forEach(function (c) { knockable('茶杯', KX + c[0], 0.38, KZ + c[1], 0.04, function () { L([[0, 0], [0.028, 0], [0.04, 0.07], [0.041, 0.075]], col(c[2], 0.3), 0, 0, 0, 14); C(0.034, 0.034, 0.004, col(0x8a9a3a, 0.2), 0, 0.058, 0, 12); }, 'cup'); });
    [[2.0, 0.5, 0xc8452e, 'asanoha'], [2.5, 0.25, 0x2f4b7c, 'ichiRed'], [1.75, 1.2, 0xd9a93a, 'seigaiha'], [-0.9, 2.2, 0x7a9a54, 'shippo']].forEach(function (c, i) { knockable('毛線球', c[0], 0.085, c[1], 0.085, function () { S(0.085, tx('yarn' + i, function () { return P.stripes([SG.shade('#' + c[2].toString(16).padStart(6, '0'), 0.15), SG.shade('#' + c[2].toString(16).padStart(6, '0'), -0.15)], [4, 3]); }, [0.02, 0.02], 0.95), 0, 0, 0); }); });
    [[3.2, 0.35, 0xc8452e], [3.33, 0.42, 0x4aa3e0], [3.15, 0.5, 0xd9a93a], [3.42, 0.3, 0x7a9a54], [3.3, 0.6, 0xf29a4a], [3.05, 0.25, 0x5e4a7a]].forEach(function (c) { knockable('積木', c[0], 0.012, c[1], 0.045, function () { B(0.075, 0.075, 0.075, col(c[2], 0.5), 0, 0, 0, 0.01); }, 'block'); });
    knockable('皮球', 0.9, 0.12, 1.9, 0.12, function () { S(0.12, tx('ball', function () { return P.stripes(['#c8452e', '#f5f1e8', '#2f4b7c', '#f5f1e8', '#d9a93a', '#f5f1e8'], [20, 6, 20, 6, 20, 6]); }, [0.25, 0.25], 0.4), 0, 0, 0); });
    [[-3.0, 2.25], [0.2, -2.9], [-2.2, -1.9]].forEach(function (c) { knockable('紙團', c[0], 0.04, c[1], 0.04, function () { add(new THREE.IcosahedronGeometry(0.04, 0), white, 0, 0, 0); }); });
    [[1.15, -2.5, 0x4aa3e0], [-3.9, 1.2, 0xc8452e]].forEach(function (c) { knockable('空罐', c[0], 0, c[1], 0.035, function () { C(0.033, 0.033, 0.12, col(c[2], 0.25, { metalness: 0.7 }), 0, 0, 0, 14); C(0.03, 0.03, 0.004, col(0xd8d6d0, 0.2, { metalness: 0.9 }), 0, 0.12, 0, 12); }, 'cup'); });
    [[W - 0.36, 0.42, -0.3], [-W + 0.6, 0.53, 0.08]].forEach(function (c, i) { knockable('小盆栽', c[0], c[1], c[2], 0.05, function () { L([[0, 0], [0.035, 0], [0.05, 0.07]], col(i ? 0xf29a4a : 0x3f8f8a, 0.5), 0, 0, 0, 12); S(0.05, leafM, 0, 0.1, 0, 1, 0.9, 1); }, 'cup'); });

    /* ---- colliders for the living-room shell (walls are platforms flagged `wall`) ---- */
    [[-W - 0.12, -W, -D, 0.7], [-W - 0.12, -W, 1.9, EN], [W, W + 0.12, -D, -3.3], [W, W + 0.12, -2.4, EN]].forEach(function (w) { plat(w[0], w[1], w[2], w[3], H, 0, true); }); plat(W, W + 0.12, -3.3, -2.4, H, 1.2, true);
    [[-2.9, -0.55], [0.55, 2.75], [4.35, W]].forEach(function (w) { plat(w[0], w[1], -D - 0.12, -D, H, 0, true); });
    plat(-W, -2.9, -D - 0.72, -D - 0.6, H, 0, true); plat(-2.9, -2.78, -D - 0.6, -D, H, 0, true); // tokonoma recess
    plat(-W - 0.12, -W, 0.7, 1.9, H, 1.94, true); plat(-0.55, 0.55, -D - 0.12, -D, H, 1.94, true); plat(2.75, 4.35, -D - 0.12, -D, H, 1.94, true); // lintels
    plat(-W, W, -D, EN, H + 0.12, H, true); // ceiling
    /* ---- the rest of the house lives in house.js ---- */
    var K = { scene: scene, room: room, stat: stat, dyn: dyn, fx: fx, begin: begin, add: add, B: B, C: C, L: L, S: S, PL: PL, plat: plat, platG: platG, blob: blob, glow: glow, fxMat: fxMat, aoM: aoM,
      mat: mat, col: col, tx: tx, sway: sway, cloth: cloth, count: count, knockable: knockable, knock: knock, updaters: updaters, r: r, lintel: lintel, post: post, shoji: shoji, shojiM: shojiM,
      setRoom: function (n) { curRoom = n; cur = stat; }, platforms: platforms, lights: [], triggers: [], spots: [], opt: opt,
      m: { honey: honey, dark: dark, darker: darker, hinoki: hinoki, red: red, engW: engW, ceilW: ceilW, plaster: plaster, plasterG: plasterG, tatami: tatami, washi: washi, iron: iron, brass: brass, white: white, black: black, cream: cream, leafM: leafM, leafD: leafD, stoneM: stoneM, stoneD: stoneD, card: card, heri: heri, paper: paper, mapleM: mapleM, mapleO: mapleO, grass: grass, gravel: gravel, bam: bam, tile: tile },
      plantPot: plantPot, snake: snake, monstera: monstera, bonsai: bonsai, daruma: daruma, kokeshi: kokeshi, book: book, cbox: cbox, bookC: bookC, W: W, D: D, H: H, EN: EN };
    if (SG.buildHouse) SG.buildHouse(K);
    if (SG.buildAnnex) SG.buildAnnex(K);
    if (SG.buildDecor) SG.buildDecor(K);
    cur = stat; curRoom = '客廳';

    /* ================= AO skirts + light shafts + dust ================= */
    function skirt(x, z, len, ry, h) { var o = new THREE.Mesh(new THREE.PlaneGeometry(len, h || 0.5), aoM); o.position.set(x, (h || 0.5) / 2, z); o.rotation.y = ry; o.layers.set(1); o.renderOrder = 1; fx.add(o); }
    skirt(0, -D + 0.012, W * 2, 0); skirt(W - 0.012, (EN - D) / 2, D + EN, -Math.PI / 2); skirt(-W + 0.012, (EN - D) / 2, D + EN, Math.PI / 2);
    var floorAO = new THREE.Mesh(new THREE.PlaneGeometry(W * 2, 0.7), aoM); floorAO.rotation.x = -Math.PI / 2; floorAO.position.set(0, 0.006, -D + 0.35); floorAO.layers.set(1); fx.add(floorAO);
    [[W - 0.35, -Math.PI / 2], [-W + 0.35, Math.PI / 2]].forEach(function (s) { var o = new THREE.Mesh(new THREE.PlaneGeometry(D + EN, 0.7), aoM); o.rotation.set(-Math.PI / 2, 0, s[1]); o.position.set(s[0], 0.006, (EN - D) / 2); o.layers.set(1); fx.add(o); });
    // sun shafts through the engawa opening (additive shader quads) + dust motes that only show inside the light
    var sunDir = new THREE.Vector3(-1.9, 4.3, 6.2).normalize();
    var shaftM = new THREE.ShaderMaterial({
      transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide, uniforms: { uTime: uTime },
      vertexShader: 'varying vec2 vUv; void main(){ vUv=uv; gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.); }',
      fragmentShader: 'uniform float uTime; varying vec2 vUv; float h(vec2 p){ return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); } void main(){ float a=smoothstep(0.,0.18,vUv.x)*smoothstep(1.,0.82,vUv.x)*smoothstep(0.,0.3,vUv.y)*smoothstep(1.,0.5,vUv.y); a*=0.6+0.4*sin(vUv.x*37.+sin(uTime*0.3)*2.); gl_FragColor=vec4(vec3(1.0,0.84,0.6)*a*0.11,1.); }'
    });
    [-1.2, -0.4, 0.4, 1.2].forEach(function (x, i) {
      var len = 3.3, o = new THREE.Mesh(new THREE.PlaneGeometry(0.75, len), shaftM);
      o.position.set(x + sunDir.x * -len / 2 * 0.0 + 0.45, 1.0, EN - 1.25); o.lookAt(o.position.x + 1, o.position.y, o.position.z);
      o.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), sunDir); o.rotateY(0.5 + i * 0.3); o.layers.set(1); fx.add(o);
    });
    count('光柱');
    var dn = 260, dp = new Float32Array(dn * 3), ds = new Float32Array(dn);
    for (var di = 0; di < dn; di++) { dp[di * 3] = (r() - 0.5) * 4.6 + 0.3; dp[di * 3 + 1] = 0.1 + r() * 1.9; dp[di * 3 + 2] = EN - 0.2 - r() * 3.2; ds[di] = r() * 6.28; }
    var dg = new THREE.BufferGeometry(); dg.setAttribute('position', new THREE.BufferAttribute(dp, 3)); dg.setAttribute('seed', new THREE.BufferAttribute(ds, 1));
    var dust = new THREE.Points(dg, new THREE.ShaderMaterial({
      transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, uniforms: { uTime: uTime, uEN: { value: EN } },
      vertexShader: 'attribute float seed; uniform float uTime,uEN; varying float vA; void main(){ vec3 p=position; p.x+=sin(uTime*0.23+seed)*0.25; p.y+=sin(uTime*0.17+seed*2.)*0.2; p.z+=cos(uTime*0.19+seed*3.)*0.2; float inLight=smoothstep(0.0,0.5,(uEN+1.0-p.z)*0.69-p.y+0.35)*smoothstep(2.0,1.2,p.y); vA=inLight*(0.5+0.5*sin(uTime*1.3+seed*5.)); vec4 mv=modelViewMatrix*vec4(p,1.); gl_PointSize=(1.2+1.8*fract(seed*7.))*3.0/max(0.5,-mv.z); gl_Position=projectionMatrix*mv; }',
      fragmentShader: 'varying float vA; void main(){ float d=length(gl_PointCoord-0.5); gl_FragColor=vec4(vec3(1.0,0.9,0.7)*smoothstep(0.5,0.0,d)*vA*0.5,1.); }'
    }));
    dust.layers.set(1); dust.frustumCulled = false; fx.add(dust); count('光中的灰塵');

    /* ================= LIGHTS ================= */
    var sun = new THREE.DirectionalLight(0xffdfb4, 4.2); sun.position.copy(sunDir).multiplyScalar(14).add(new THREE.Vector3(0, 0, 1.5)); sun.target.position.set(0, 0, 1.5);
    sun.castShadow = true; sun.shadow.mapSize.set(opt.low ? 1024 : 2048, opt.low ? 1024 : 2048);
    var sc = sun.shadow.camera; sc.left = -11; sc.right = 11; sc.top = 11; sc.bottom = -12; sc.near = 1; sc.far = 40; sun.shadow.bias = -0.0006; sun.shadow.normalBias = 0.03; sun.shadow.radius = 5;
    var hemi = new THREE.HemisphereLight(0xd6e4ff, 0xb39a7a, 1.25); // cool sky from above, warm bounce from the floors
    var lampL = new THREE.PointLight(0xffc27a, 9, 8, 1.7); lampL.position.set(KX, H - 0.95, KZ);
    var bounce = new THREE.PointLight(0xffd7a0, 3.2, 8, 1.4); bounce.position.set(0.2, 1.25, 1.2); // sunlight bouncing off the floor
    var kitL = new THREE.PointLight(0xfff2dc, 5, 6, 1.8); kitL.position.set(0, 2.0, -D - 1.3);
    var genL = new THREE.PointLight(0xffe2b8, 3, 5, 1.8); genL.position.set(-W - 1.1, 2.0, 1.3);
    [sun, sun.target, hemi, lampL, bounce, kitL, genL].forEach(function (l) { l.layers.set(1); room.add(l); });
    scene.add(SG.post ? SG.post.flatLight : new THREE.Group());

    /* ================= static batching =================
       flat-colour materials collapse into three vertex-coloured batches; textured ones get one batch each;
       a single invisible proxy casts all static shadows. Moving props are baked per group. */
    var flat = {
      R: new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.82 }),
      G: new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.32 }),
      M: new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.38, metalness: 0.8 })
    };
    flat.D = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.5 }); flat.D.name = 'flatDyn';
    flat.R.name = 'flatRough'; flat.G.name = 'flatGloss'; flat.M.name = 'flatMetal';
    if (SG.surfaceDetail) [flat.R, flat.G, flat.D].forEach(function (m, i) { SG.surfaceDetail(m, 'flat' + i); });
    function bucket(m) {
      if (!m.isMeshStandardMaterial || m.map || m.transparent || m.onBeforeCompile !== THREE.Material.prototype.onBeforeCompile || m.side !== THREE.FrontSide) return null;
      if (m.emissiveIntensity > 0 && (m.emissive.r + m.emissive.g + m.emissive.b) > 0) return null;
      return m.metalness > 0.5 ? 'M' : m.roughness >= 0.6 ? 'R' : 'G';
    }
    stat.updateMatrixWorld(true);
    var groups = new Map(), tris = 0, statCount = 0, casters = [];
    stat.traverse(function (o) {
      if (!o.isMesh) return; statCount++;
      var bk = bucket(o.material), k = bk ? flat[bk] : o.material;
      if (!groups.has(k)) groups.set(k, []);
      groups.get(k).push([o.geometry, o.matrixWorld.clone(), bk ? o.material.color : null]);
      if (!o.material.transparent && !o.material.isShaderMaterial && !o.userData.noShadow) casters.push([o.geometry, o.matrixWorld]);
    });
    var batched = new THREE.Group(); room.add(batched);
    groups.forEach(function (items, m) {
      var g = G.merge(items), mesh = new THREE.Mesh(g, m);
      mesh.castShadow = false; mesh.receiveShadow = !m.isShaderMaterial;
      tris += g.index.count / 3; batched.add(mesh);
    });
    var proxy = new THREE.Mesh(G.merge(casters), new THREE.MeshBasicMaterial({ colorWrite: false, depthWrite: false, depthFunc: THREE.NeverDepth }));
    proxy.castShadow = true; proxy.name = 'shadowProxy'; room.add(proxy);
    room.remove(stat);
    // moving props: merge the plain meshes directly under each group (sub-groups keep animating)
    var dynMeshes = 0;
    function bakeGroup(g) {
      var kids = g.children.slice(), by = {};
      kids.forEach(function (o) {
        if (o.isGroup) { bakeGroup(o); return; }
        if (!o.isMesh || o.userData.keep) return;
        var bk = bucket(o.material); if (!bk) return; if (bk !== 'M') bk = 'D'; // moving props: one plain batch each
        o.updateMatrix(); (by[bk] = by[bk] || []).push([o.geometry, o.matrix.clone(), o.material.color]); g.remove(o);
      });
      Object.keys(by).forEach(function (bk) { var m = new THREE.Mesh(G.merge(by[bk]), flat[bk]); m.userData.baked = true; g.add(m); });
    }
    dyn.children.forEach(function (g) { if (g.isGroup) bakeGroup(g); });
    dyn.traverse(function (o) {
      if (!o.isMesh) return; dynMeshes++;
      var ok = !o.material.transparent && !o.material.isShaderMaterial;
      if (ok) { o.receiveShadow = true; if (!o.geometry.boundingSphere) o.geometry.computeBoundingSphere(); o.castShadow = o.geometry.boundingSphere.radius > 0.075 && !o.userData.noShadow; }
    });
    // fx planes that share a material become one mesh
    var fxBy = new Map(); fx.updateMatrixWorld(true);
    fx.children.slice().forEach(function (o) { if (!o.isMesh || o.userData.keep) return; if (!fxBy.has(o.material)) fxBy.set(o.material, []); fxBy.get(o.material).push(o); });
    fxBy.forEach(function (list, m) { if (list.length < 2) return; var mm = new THREE.Mesh(G.merge(list.map(function (o) { return [o.geometry, o.matrixWorld.clone()]; })), m); mm.layers.set(1); mm.renderOrder = list[0].renderOrder; list.forEach(function (o) { fx.remove(o); }); fx.add(mm); });

    /* ================= world queries ================= */
    var bounds = { x0: -8.55, x1: 8.55, z0: -8.55, z1: 8.55 };
    function base(x, z) { return (z > EN + 1.5 || (z > EN + 0.4 && Math.abs(x) > 6.0)) ? -0.3 : 0; } // garden is 30 cm below the house floor
    function groundAt(x, z, y, rad) { // highest surface under the footprint that is not above y
      var g = base(x, z); rad = rad || 0;
      for (var i = 0; i < platforms.length; i++) { var p = platforms[i]; if (x > p.x0 - rad && x < p.x1 + rad && z > p.z0 - rad && z < p.z1 + rad && p.y1 <= y + 0.001 && p.y1 > g) g = p.y1; }
      var dx = x - vacState.x, dz = z - vacState.z; if (dx * dx + dz * dz < 0.2 * 0.2 && vacState.top <= y + 0.001 && vacState.top > g) g = vacState.top;
      return g;
    }
    /* would a body of radius rad standing at height y collide? returns the blocking platform, or true for the outer bounds / water */
    function blocked(x, z, y, rad, step, height) {
      if (x < bounds.x0 + rad || x > bounds.x1 - rad || z < bounds.z0 + rad || z > bounds.z1 - rad) return true;
      var px = (x - 0.6) / 1.5, pz = (z - (EN + 3.5)) / 1.1; if (px * px + pz * pz < 1 && y < 0.2) return true; // the pond
      if (base(x, z) > y + step) return true;
      for (var i = 0; i < platforms.length; i++) { var p = platforms[i]; if (p.y1 <= y + step) continue; if (p.y0 >= y + (height || 0.3)) continue; if (x > p.x0 - rad && x < p.x1 + rad && z > p.z0 - rad && z < p.z1 + rad) return p; }
      return false;
    }
    /* first wall between two points (third-person camera): returns 0..1 along a->b */
    function segWalls(ax, ay, az, bx, by, bz) {
      var best = 1, dx = bx - ax, dy = by - ay, dz = bz - az;
      for (var i = 0; i < platforms.length; i++) {
        var p = platforms[i]; if (!p.wall) continue;
        var t0 = 0, t1 = best, lo, hi, a, d, k, t;
        for (k = 0; k < 3; k++) {
          a = k === 0 ? ax : k === 1 ? ay : az; d = k === 0 ? dx : k === 1 ? dy : dz; lo = k === 0 ? p.x0 : k === 1 ? p.y0 : p.z0; hi = k === 0 ? p.x1 : k === 1 ? p.y1 : p.z1;
          if (Math.abs(d) < 1e-9) { if (a < lo || a > hi) { t0 = 2; break; } } else { var ta = (lo - a) / d, tb = (hi - a) / d; if (ta > tb) { t = ta; ta = tb; tb = t; } if (ta > t0) t0 = ta; if (tb < t1) t1 = tb; if (t0 > t1) { t0 = 2; break; } }
        }
        if (t0 <= 1 && t0 < best) best = t0;
      }
      return best;
    }

    /* ---- small rigid-body sim for the knockable props and the tennis balls ----
       bodies are discs with a height: they collide with each other and with the room, rest on each other (stacks),
       upright ones rock about their base edge and topple past the critical angle, lying cylinders roll across their axis. */
    var GRAV = 9.8 / (opt.scale || 1.5), /* plan units: 9.8 m/s² once the property is scaled */ _gdummy = 0, _ax = new THREE.Vector3(), _q = new THREE.Quaternion(), _q2 = new THREE.Quaternion();
    knock.forEach(initBody);
    function initBody(k) {
      k.ball = k.shape === 'ball'; k.h = k.h || (k.ball ? k.r * 2 : k.shape === 'block' ? 0.075 : k.shape === 'roly' ? 0.2 : Math.max(0.07, k.r * 2.4));
      k.hw = k.shape === 'block' ? 0.0375 : k.r * 0.8; k.m = k.m || Math.max(0.03, k.r * k.r * k.h * 900);
      k.th = 0; k.tw = 0; k.dir = 0; k.lying = false; k.sleep = true; k.q0 = k.g.quaternion.clone(); k.cool = 0;
      if (k.ball) k.y -= 0; return k;
    }
    function bodyBase(k) { return k.ball ? k.y - k.r : k.y; }
    function wake(k) { k.sleep = false; k.still = 0; }
    function tip(k, nx, nz, sp) { // horizontal impulse at mid height -> rocking
      if (k.ball || k.lying) return;
      if (Math.abs(k.th) < 0.05) k.dir = Math.atan2(nx, nz);
      var along = Math.cos(k.dir) * nz + Math.sin(k.dir) * nx;
      k.tw += along * sp * (k.shape === 'roly' ? 9 : 2.2 / Math.max(0.05, k.h)) * 0.35;
    }
    function addBall(mesh, x, y, z, vx, vy, vz) { var k = initBody({ g: mesh, type: '網球', x: x, y: y, z: z, vx: vx, vy: vy, vz: vz, r: 0.035, shape: 'ball', m: 0.25, home: [x, y, z], shot: true }); wake(k); knock.push(k); return k; }
    function kick(x, y, z, dx, dz, sp) { for (var i = 0; i < knock.length; i++) { var k = knock[i]; if (Math.abs(k.x - x) < k.r + 0.12 && Math.abs(k.z - z) < k.r + 0.12 && Math.abs(bodyBase(k) + k.h / 2 - y) < k.h / 2 + 0.15) { wake(k); k.vx += dx * sp; k.vz += dz * sp; k.vy += 0.8; tip(k, dx, dz, sp); } } }
    function resetProps() { // new round: balls are removed, props go home
      for (var i = knock.length - 1; i >= 0; i--) { var k = knock[i]; if (k.shot) { knock.splice(i, 1); continue; } k.x = k.home[0]; k.y = k.home[1]; k.z = k.home[2]; k.vx = k.vy = k.vz = 0; k.th = k.tw = 0; k.lying = false; k.sleep = true; k.g.quaternion.copy(k.q0); k.g.position.set(k.x, k.y, k.z); }
      K.triggers.forEach(function (t) { if (t.kind === 'drawer') { t.out = 0.22; t.p.z1 = t.p.z0 + 0.32; } });
    }
    function stepProps(dt, bumpers, onBump) {
      var n = knock.length, i, j, k, o;
      for (i = 0; i < n; i++) {
        k = knock[i]; if (k.cool > 0) k.cool -= dt;
        // critters, vacuum
        for (j = 0; j < bumpers.length; j++) {
          var c = bumpers[j], dx = k.x - c.x, dz = k.z - c.z, d = Math.hypot(dx, dz), rr = c.r + k.r;
          if (d < rr && bodyBase(k) < c.y + 0.4 && bodyBase(k) + k.h > c.y - 0.02) {
            var nx = d > 1e-4 ? dx / d : 1, nz = d > 1e-4 ? dz / d : 0, push = Math.max(c.speed, 0.5);
            k.x = c.x + nx * rr; k.z = c.z + nz * rr; wake(k);
            if (k.ball || k.lying) { k.vx = nx * push * 1.25; k.vz = nz * push * 1.25; } else { k.vx += nx * push * 0.5; k.vz += nz * push * 0.5; tip(k, nx, nz, push); }
            if (onBump && k.cool <= 0) { onBump(k); k.cool = 0.4; }
          }
        }
      }
      // body against body
      for (i = 0; i < n; i++) {
        k = knock[i];
        for (j = i + 1; j < n; j++) {
          o = knock[j]; if (k.sleep && o.sleep) continue;
          var ex = o.x - k.x, ez = o.z - k.z, rs = k.r + o.r; if (Math.abs(ex) > rs || Math.abs(ez) > rs) continue;
          var dd = Math.hypot(ex, ez); if (dd >= rs) continue;
          var kb = bodyBase(k), ob = bodyBase(o);
          if (ob >= kb + k.h - 0.012 || kb >= ob + o.h - 0.012) continue; // one rests on the other: handled as support
          var ux = dd > 1e-4 ? ex / dd : 1, uz = dd > 1e-4 ? ez / dd : 0, im = 1 / k.m, om = 1 / o.m, pen = rs - dd;
          k.x -= ux * pen * im / (im + om); k.z -= uz * pen * im / (im + om); o.x += ux * pen * om / (im + om); o.z += uz * pen * om / (im + om);
          var vn = (o.vx - k.vx) * ux + (o.vz - k.vz) * uz;
          if (vn < 0) { var J = -(1.5) * vn / (im + om); k.vx -= J * im * ux; k.vz -= J * im * uz; o.vx += J * om * ux; o.vz += J * om * uz; tip(k, -ux, -uz, J * im); tip(o, ux, uz, J * om); if (onBump && -vn > 0.5 && k.cool <= 0) { onBump(k, false, o); k.cool = 0.25; } }
          wake(k); wake(o);
        }
      }
      for (i = 0; i < n; i++) {
        k = knock[i]; if (k.sleep) continue;
        var base = bodyBase(k), g = groundAt(k.x, k.z, base + 0.03, 0);
        for (j = 0; j < n; j++) { // resting on another prop
          o = knock[j]; if (o === k) continue; var top = bodyBase(o) + (o.lying ? o.hw * 2 : o.h);
          if (top > g && top <= base + 0.03 && Math.hypot(o.x - k.x, o.z - k.z) < (k.hw + o.hw) * 0.9) g = top;
        }
        if (base > g + 0.002 || k.vy > 0) {
          k.vy -= GRAV * dt; k.y += k.vy * dt;
          if (bodyBase(k) <= g && k.vy <= 0) { k.y += g - bodyBase(k); if (k.vy < -1.0) { if (onBump) onBump(k, true); k.vy = -k.vy * (k.ball ? 0.5 : 0.25); if (!k.ball && !k.lying) k.tw += (k.vx * Math.sin(k.dir) + k.vz * Math.cos(k.dir)) * 2 + 0.8; } else k.vy = 0; }
        } else { k.y += g - base; k.vy = 0; }
        var sp = Math.hypot(k.vx, k.vz);
        if (sp > 1e-3) {
          var hx = k.x + k.vx * dt, hz = k.z + k.vz * dt, bb = bodyBase(k);
          if (blocked(hx, k.z, bb, k.r * 0.8, 0.02, k.h)) { k.vx *= -0.45; hx = k.x; if (onBump && sp > 1.5 && k.cool <= 0) { onBump(k, true); k.cool = 0.2; } }
          if (blocked(k.x, hz, bb, k.r * 0.8, 0.02, k.h)) { k.vz *= -0.45; hz = k.z; if (onBump && sp > 1.5 && k.cool <= 0) { onBump(k, true); k.cool = 0.2; } }
          k.x = hx; k.z = hz;
          var grounded = bodyBase(k) <= g + 0.004;
          if (k.ball) { if (grounded) { var f = Math.exp(-dt * 0.9); k.vx *= f; k.vz *= f; } _ax.set(k.vz, 0, -k.vx).normalize(); k.g.rotateOnWorldAxis(_ax, sp * dt / k.r); }
          else if (k.lying && k.shape !== 'block') { // rolls across its axis, scrapes along it
            var axx = Math.cos(k.dir), axz = -Math.sin(k.dir), al = k.vx * axx + k.vz * axz, acx = k.vx - al * axx, acz = k.vz - al * axz, fa = Math.exp(-dt * 6), fr = Math.exp(-dt * 1.1);
            if (grounded) { k.vx = acx * fr + al * fa * axx; k.vz = acz * fr + al * fa * axz; } k.roll = (k.roll || 0) + (acx * Math.sin(k.dir) + acz * Math.cos(k.dir)) * dt / k.hw;
          } else if (grounded) { var fs = Math.exp(-dt * 5); k.vx *= fs; k.vz *= fs; }
        }
        // rocking / toppling about the base edge
        if (!k.ball && !k.lying) {
          if (k.shape === 'roly') { k.tw += (-k.th * 55 - k.tw * 1.6) * dt; k.th += k.tw * dt; }
          else {
            var thc = Math.atan2(k.hw, k.h / 2), R = Math.hypot(k.hw, k.h / 2), sgn = k.th >= 0 ? 1 : -1, a = Math.abs(k.th);
            k.tw += (a < thc ? -sgn * (0.75 * GRAV / R) * Math.sin(thc - a) * (a > 0.002 ? 1 : 0) : sgn * (0.75 * GRAV / R) * Math.sin(a - thc)) * dt;
            var prev = k.th; k.th += k.tw * dt;
            if (prev * k.th < 0 || (Math.abs(k.th) < 0.004 && Math.abs(k.tw) < 0.5)) { k.tw *= -0.35; k.th = 0; if (Math.abs(k.tw) < 0.25) k.tw = 0; else if (onBump && k.cool <= 0) { onBump(k, true); k.cool = 0.15; } } // base slaps back down
            if (Math.abs(k.th) >= Math.PI / 2) { k.th = sgn * Math.PI / 2; k.tw = 0; k.lying = true; k.vx += Math.sin(k.dir) * sgn * 0.5; k.vz += Math.cos(k.dir) * sgn * 0.5; if (onBump) onBump(k, true); }
          }
        }
        // pose the mesh
        if (!k.ball) {
          _ax.set(Math.cos(k.dir), 0, -Math.sin(k.dir)); _q.setFromAxisAngle(_ax, k.th); k.g.quaternion.copy(_q).multiply(k.q0);
          if (k.lying && k.roll) { _ax.set(Math.sin(k.dir), 0, Math.cos(k.dir)); _q2.setFromAxisAngle(_ax, k.roll * 0); }
        }
        var lift = k.ball ? 0 : (k.shape === 'roly' ? 0 : Math.sin(Math.min(Math.abs(k.th), Math.PI / 2)) * k.hw);
        k.g.position.set(k.x - (k.ball ? 0 : Math.sin(k.dir) * Math.sin(k.th) * 0), k.y + lift, k.z);
        // wake what sits on top of a moving body; fall asleep when still
        var moving = sp > 0.02 || Math.abs(k.vy) > 0.02 || Math.abs(k.tw) > 0.02 || (!k.lying && Math.abs(k.th) > 0.002);
        if (moving) { k.still = 0; for (j = 0; j < n; j++) { o = knock[j]; if (o.sleep && Math.abs(o.x - k.x) < k.r + o.r + 0.03 && Math.abs(o.z - k.z) < k.r + o.r + 0.03 && bodyBase(o) > base - 0.02 && bodyBase(o) < base + k.h + 0.3) wake(o); } }
        else { k.still = (k.still || 0) + dt; if (k.still > 0.6) { k.sleep = true; k.vx = k.vz = k.vy = 0; } }
      }
    }

    /* things that react to whoever passes: sliding fusuma, cat flap, a drawer left ajar, rocking chair / horse */
    function stepTriggers(dt, bodies) {
      for (var i = 0; i < K.triggers.length; i++) {
        var t = K.triggers[i], near = 9, nb = null, j;
        for (j = 0; j < bodies.length; j++) { var b = bodies[j], d = Math.hypot(b.x - t.x, b.z - t.z); if (t.y != null && Math.abs(b.y - t.y) > 1.2) continue; if (d < near) { near = d; nb = b; } }
        if (t.kind === 'slide') { t.open += ((near < 1.5 ? 1 : 0) - t.open) * Math.min(1, dt * 5); t.a.position.x = 3.15 - t.open * 0.42; t.b.position.x = 3.95 + t.open * 0.42; }
        else if (t.kind === 'flap') { if (near < 0.42 && nb) t.v += (nb.z > t.z ? -1 : 1) * dt * 40; t.v += (-t.a * 30 - t.v * 2.2) * dt; t.a += t.v * dt; t.a = Math.max(-1.4, Math.min(1.4, t.a)); t.g.rotation.x = t.a; }
        else if (t.kind === 'drawer') { if (t.out > 0 && near < 0.42 && nb && nb.z > t.z - 0.1) { t.out = Math.max(0, t.out - dt * 0.9); if (t.out === 0) { t.p.z1 = t.p.z0; t.shut = true; } } t.g.position.z = -D + 0.6 - 0.22 + t.out; }
        else if (t.kind === 'rock') { if (near < t.rad && nb && nb.speed > 0.3) t.v += dt * 9 * Math.min(1.5, nb.speed); t.v += (-t.a * 14 - t.v * 0.9) * dt; t.a += t.v * dt; if (t.axis === 'x') t.g.rotation.x = t.a * 0.5; else t.g.rotation.z = t.a * 0.5; }
      }
    }

    /* night mode: house lights off, moonlight through the garden side, TV and fish tank still glow */
    var dayL = [[sun, sun.intensity, sun.color.getHex()], [hemi, hemi.intensity, hemi.color.getHex()], [lampL, lampL.intensity], [bounce, bounce.intensity], [kitL, kitL.intensity], [genL, genL.intensity]].concat(K.lights.map(function (l) { return [l, l.intensity]; }));
    var glowMats = Object.keys(mats).map(function (k) { return mats[k]; }).filter(function (m) { return m.emissiveIntensity > 0 && (m.emissive.r + m.emissive.g + m.emissive.b) > 0; }).map(function (m) { return [m, m.emissiveIntensity]; });
    var fxDay = fx.children.filter(function (o) { return o.isSprite || o.material === shaftM || o === dust || (o.geometry && o.material && o.material.uniforms && o.material === shaftM); });
    function setNight(on) {
      dayL.forEach(function (d, i) { d[0].intensity = on ? (i === 0 ? 0.5 : i === 1 ? 0.2 : i === 3 ? 0.15 : 0) : d[1]; if (d[2] != null) d[0].color.setHex(on ? (i === 0 ? 0x93aaff : 0x7f8fc8) : d[2]); });
      glowMats.forEach(function (g) { g[0].emissiveIntensity = on ? g[1] * 0.06 : g[1]; });
      fx.children.forEach(function (o) { if (o.isSprite || o === dust || o.material === shaftM) o.visible = !on; });
      sky.material.uniforms.uNight.value = on ? 1 : 0; ret.night = on;
    }

    var types = Object.keys(inv), total = types.reduce(function (a, k) { return a + inv[k]; }, 0);
    var ret = {
      group: room, batched: batched, dyn: dyn, fx: fx, platforms: platforms, bounds: bounds, knock: knock, inventory: inv,
      stats: { types: types.length, items: total, staticMeshes: statCount, batches: groups.size, dynMeshes: dynMeshes, tris: Math.round(tris), moving: updaters.length, knockables: knock.length },
      sun: sun, steam: steamM, kettle: kettle, vac: vacState, vacGroup: vac,
      groundAt: groundAt, blocked: blocked, stepProps: stepProps, addBall: addBall, kick: kick, resetProps: resetProps, segWalls: segWalls, stepTriggers: stepTriggers, triggers: K.triggers, route: K.route || [], lights: K.lights, base: base, inventoryByRoom: invRoom, K: K,
      update: function (t) { uTime.value = t; for (var i = 0; i < updaters.length; i++) updaters[i](t); var boil = (t % 40) / 40; steamM.uniforms.uAmt.value = 0.35 + 0.65 * Math.max(0, Math.sin(boil * Math.PI * 2)); },
      /* places bots know about: [x, z, yaw, pose, surfaceY] */
      spots: [[-W + 0.5, -1.15, Math.PI / 2, 'loaf', 0.36], [KX + 0.0, KZ + 1.12, Math.PI, 'curl', 0.12], [2.9, 0.4, -2.2, 'loaf', 0.012], [-1.35, -D + 0.32, 0, 'sit', 1.35], [W - 0.7, 1.9, -1.9, 'sit', 1.05], [-W + 0.55, 2.15, 1.2, 'loaf', 0.78], [1.3, EN + 0.75, 0.4, 'curl', 0.28], [-2.3, 1.2, 2.0, 'side', 0.03], [-3.7, -D - 0.28, 0, 'hind', 0.12], [W - 0.5, -2.3, -1.2, 'arch', 0.0], [0.3, 2.0, 2.6, 'belly', 0]].concat(K.spots || [])
    };
    ret.setNight = setNight; ret.sunLight = sun;
    /* ---- world scale: the property is authored in plan units and then enlarged as a whole, so the animals are small in a big house
       (ceilings H*WS, doors, furniture and distances all grow together). Everything the game talks to is converted here, at the boundary;
       the prop physics and the triggers keep running in plan units. */
    var WS = SG.WS = opt.scale || 1.5;
    room.scale.setScalar(WS); room.updateMatrixWorld(true);
    [lampL, bounce, kitL, genL].concat(K.lights).forEach(function (l) { if (l.isPointLight) { l.distance *= WS; l.intensity *= Math.pow(WS, l.decay); } });
    dayL.forEach(function (d) { d[1] = d[0].intensity; });
    sc.left = -14 * WS; sc.right = 14 * WS; sc.top = 14 * WS; sc.bottom = -14 * WS; sc.far = 44 * WS; sc.updateProjectionMatrix();
    var PW = [];
    function sync() { for (var i = 0; i < platforms.length; i++) { var a = platforms[i], b = PW[i] || (PW[i] = {}); b.x0 = a.x0 * WS; b.x1 = a.x1 * WS; b.z0 = a.z0 * WS; b.z1 = a.z1 * WS; b.y0 = a.y0 * WS; b.y1 = a.y1 * WS; b.wall = a.wall; } PW.length = platforms.length; }
    sync();
    var up0 = ret.update;
    ret.raw = { platforms: platforms, groundAt: groundAt, blocked: blocked, stepProps: stepProps, stepTriggers: stepTriggers, kick: kick, vac: vacState, WS: WS };
    ret.WS = WS; ret.platforms = PW;
    ret.groundAt = function (x, z, y, rad) { return groundAt(x / WS, z / WS, y / WS, (rad || 0) / WS) * WS; };
    ret.blocked = function (x, z, y, rad, step, h) { return blocked(x / WS, z / WS, y / WS, rad / WS, step / WS, h / WS); };
    ret.segWalls = function (a, b, c, d, e, f) { return segWalls(a / WS, b / WS, c / WS, d / WS, e / WS, f / WS); };
    ret.base = function (x, z) { return base(x / WS, z / WS) * WS; };
    ret.stepProps = function (dt, bumpers, onBump) { return stepProps(dt, bumpers.map(function (b) { return { x: b.x / WS, y: b.y / WS, z: b.z / WS, r: b.r / WS, speed: b.speed }; }), onBump && function (k, landed) { onBump({ type: k.type, x: k.x * WS, z: k.z * WS, shot: k.shot }, landed); }); };
    ret.stepTriggers = function (dt, bodies) { return stepTriggers(dt, bodies.map(function (e) { return { x: e.x / WS, y: e.y / WS, z: e.z / WS, speed: e.speed }; })); };
    ret.kick = function (x, y, z, dx, dz, sp) { return kick(x / WS, y / WS, z / WS, dx, dz, sp); };
    ret.vac = { get x() { return vacState.x * WS; }, get z() { return vacState.z * WS; }, get top() { return vacState.top * WS; }, r: vacState.r * WS };
    ret.update = function (t) { up0(t); sync(); };
    ret.spots = ret.spots.map(function (s) { return [s[0] * WS, s[1] * WS, s[2], s[3], s[4] * WS]; });
    ret.route = ret.route.map(function (p) { return [p[0] * WS, p[1] * WS]; });
    // a patrol goal that now sits under a solid prop (boxes and pots became solid 2026-11-26) moves just outside it, on the cheapest side
    ret.route.forEach(function (q) { ret.platforms.forEach(function (p) { if (p.wall || p.y0 > 0.3 || p.y1 < 0.1 || q[0] <= p.x0 - 0.6 || q[0] >= p.x1 + 0.6 || q[1] <= p.z0 - 0.6 || q[1] >= p.z1 + 0.6) return;
      var o = [[p.x0 - 0.75 - q[0], 0], [p.x1 + 0.75 - q[0], 0], [0, p.z0 - 0.75 - q[1]], [0, p.z1 + 0.75 - q[1]]].sort(function (a, b) { return Math.abs(a[0] + a[1]) - Math.abs(b[0] + b[1]); })[0]; q[0] += o[0]; q[1] += o[1]; }); });
    ret.bounds = { x0: bounds.x0 * WS, x1: bounds.x1 * WS, z0: bounds.z0 * WS, z1: bounds.z1 * WS };
    return ret;
  };
})();
