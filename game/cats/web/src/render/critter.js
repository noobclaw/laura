/* 貓躲狗找 — parametric quadrupeds (cats and dogs): rig, paintable texture atlas, poses, idle life. */
(function () {
  'use strict';
  var SG = (window.SG = window.SG || {});
  var D2R = Math.PI / 180;

  /* ---------- profiles: v in [0,1] -> [radius, y] ---------- */
  function ell(R, H) { return function (v) { var a = Math.PI * v; return [R * Math.sin(a), -H * Math.cos(a)]; }; }
  function cap(L, r0, r1) { // joint at y=0 (radius r0) down to y=-L (radius r1), round ends
    return function (v) {
      var a;
      if (v < 0.22) { a = v / 0.22 * Math.PI / 2; return [r1 * Math.sin(a), -L - r1 * Math.cos(a)]; }
      if (v > 0.78) { a = (v - 0.78) / 0.22 * Math.PI / 2; return [r0 * Math.cos(a), r0 * Math.sin(a)]; }
      var s = (v - 0.22) / 0.56; return [r1 + (r0 - r1) * s, -L * (1 - s)];
    };
  }
  function cone(h, w, pw) { // ear: base at y=0, tip at y=h
    return function (v) { return [w * Math.pow(1 - v, pw || 0.8) + 0.002 * (1 - v), h * (0.12 * v + 0.88 * v * v * (3 - 2 * v) * 0.5 + 0.44 * v)]; };
  }

  /* ---------- breeds ---------- */
  var CATS = {
    mochi: { name: '麻糬', tag: '圓滾滾', kind: 'cat', len: 0.44, chestR: 0.150, bellyR: 0.170, hipR: 0.160, leg: 0.17, legRad: 0.044, paw: 0.052, headR: 0.150, headSx: 1.12, headSy: 0.9, neck: 0.05, muzzleR: 0.058, muzzleL: 0.040, ear: { type: 'point', h: 0.085, w: 0.062, spread: 0.6, tilt: 22 }, tail: { len: 0.34, r0: 0.036, r1: 0.03, up: 118, curl: 16 }, eye: 0.03 },
    soba: { name: '蕎麥', tag: '修長', kind: 'cat', len: 0.52, chestR: 0.108, bellyR: 0.104, hipR: 0.106, leg: 0.27, legRad: 0.031, paw: 0.038, headR: 0.118, headSx: 1.02, headSy: 0.92, neck: 0.10, muzzleR: 0.046, muzzleL: 0.040, ear: { type: 'point', h: 0.125, w: 0.066, spread: 0.52, tilt: 14 }, tail: { len: 0.52, r0: 0.024, r1: 0.017, up: 112, curl: 22 }, eye: 0.026 },
    wata: { name: '棉花', tag: '長毛', kind: 'cat', len: 0.48, chestR: 0.165, bellyR: 0.170, hipR: 0.168, leg: 0.19, legRad: 0.052, paw: 0.058, headR: 0.150, headSx: 1.1, headSy: 0.92, neck: 0.05, muzzleR: 0.058, muzzleL: 0.036, ear: { type: 'point', h: 0.08, w: 0.058, spread: 0.66, tilt: 30 }, tail: { len: 0.44, r0: 0.05, r1: 0.085, up: 105, curl: 12, bushy: true }, eye: 0.028, fluff: true },
    dango: { name: '糰子', tag: '短腿', kind: 'cat', len: 0.50, chestR: 0.132, bellyR: 0.140, hipR: 0.134, leg: 0.085, legRad: 0.042, paw: 0.048, headR: 0.142, headSx: 1.1, headSy: 0.9, neck: 0.05, muzzleR: 0.055, muzzleL: 0.038, ear: { type: 'fold', h: 0.06, w: 0.06, spread: 0.68, tilt: 38 }, tail: { len: 0.14, r0: 0.045, r1: 0.05, up: 125, curl: 10, segs: 2 }, eye: 0.03 }
  };
  var DOGS = {
    shiba: { name: '小柴', tag: '柴系', kind: 'dog', len: 0.62, chestR: 0.150, bellyR: 0.135, hipR: 0.135, leg: 0.30, legRad: 0.044, paw: 0.05, headR: 0.135, headSx: 1.06, headSy: 0.94, neck: 0.15, muzzleR: 0.066, muzzleL: 0.095, ear: { type: 'point', h: 0.10, w: 0.058, spread: 0.6, tilt: 12 }, tail: { len: 0.34, r0: 0.05, r1: 0.045, up: 150, curl: 62, bushy: true }, eye: 0.022, coat: 'shiba' },
    corgi: { name: '短短', tag: '柯基系', kind: 'dog', len: 0.70, chestR: 0.150, bellyR: 0.145, hipR: 0.150, leg: 0.115, legRad: 0.046, paw: 0.052, headR: 0.135, headSx: 1.06, headSy: 0.92, neck: 0.13, muzzleR: 0.062, muzzleL: 0.105, ear: { type: 'point', h: 0.15, w: 0.075, spread: 0.62, tilt: 20 }, tail: { len: 0.08, r0: 0.05, r1: 0.045, up: 120, curl: 0, segs: 1 }, eye: 0.022, coat: 'corgi' },
    bull: { name: '阿虎', tag: '鬥牛系', kind: 'dog', len: 0.56, chestR: 0.190, bellyR: 0.160, hipR: 0.140, leg: 0.19, legRad: 0.056, paw: 0.062, headR: 0.165, headSx: 1.2, headSy: 0.86, neck: 0.08, muzzleR: 0.095, muzzleL: 0.05, ear: { type: 'fold', h: 0.06, w: 0.055, spread: 0.72, tilt: 40 }, tail: { len: 0.07, r0: 0.035, r1: 0.03, up: 110, curl: 0, segs: 1 }, eye: 0.024, coat: 'bull', jowl: true, stance: 1.25 },
    poodle: { name: '捲捲', tag: '貴賓系', kind: 'dog', len: 0.50, chestR: 0.125, bellyR: 0.105, hipR: 0.11, leg: 0.36, legRad: 0.03, paw: 0.05, headR: 0.118, headSx: 1.0, headSy: 0.96, neck: 0.17, muzzleR: 0.05, muzzleL: 0.10, ear: { type: 'flop', h: 0.15, w: 0.06, spread: 0.8, tilt: 0 }, tail: { len: 0.20, r0: 0.02, r1: 0.018, up: 160, curl: 0, segs: 2 }, eye: 0.02, coat: 'poodle', pom: true }
  };
  SG.CATS = CATS; SG.DOGS = DOGS;

  /* ---------- poses: degrees [x,y,z] per joint; sh/el/hp/kn apply to both sides (y,z mirrored) ---------- */
  var POSES = {
    stand: {},
    sit: { pivot: [-38, 0, 0], chest: [-6, 0, 0], neck: [20, 0, 0], head: [22, 0, 0], sh: [36, 0, 0], el: [6, 0, 0], hp: [-62, 0, -8], kn: [128, 0, 0], t0: [35, 40, 0], t1: [0, 30, 0], t2: [0, 30, 0], t3: [0, 25, 0] },
    loaf: { sh: [72, 0, 0], el: [-158, 0, 0], hp: [-74, 0, -8], kn: [156, 0, 0], chest: [-4, 0, 0], neck: [-6, 0, 0], head: [4, 0, 0], t0: [-30, 64, 0], t1: [0, 50, 0], t2: [0, 48, 0], t3: [0, 42, 0] },
    stretch: { pivot: [24, 0, 0], chest: [10, 0, 0], sh: [-104, 0, 0], el: [0, 0, 0], hp: [-26, 0, 0], kn: [4, 0, 0], neck: [-26, 0, 0], head: [-20, 0, 0], t0: [-30, 0, 0], t1: [-18, 0, 0], t2: [-18, 0, 0] },
    side: { pivot: [0, 0, 86], chest: [0, -8, 0], hip: [0, 8, 0], neck: [0, 0, 0], head: [0, 0, 10], shL: [-52, 0, 10], shR: [-30, 0, 0], elL: [30, 0, 0], elR: [22, 0, 0], hpL: [34, 0, 8], hpR: [16, 0, 0], knL: [-30, 0, 0], knR: [-20, 0, 0], t0: [-20, 0, 0], t1: [-14, 0, 0] },
    curl: { pivot: [0, 0, 62], chest: [0, -58, 0], hip: [0, 58, 0], neck: [10, -50, 0], head: [20, -42, 0], sh: [-70, 0, 0], el: [120, 0, 0], hp: [-70, 0, 0], kn: [130, 0, 0], t0: [-36, 64, 0], t1: [0, 56, 0], t2: [0, 56, 0], t3: [0, 50, 0] },
    belly: { pivot: [0, 0, 176], chest: [-8, 10, 0], hip: [8, -6, 0], neck: [-30, 16, 0], head: [-34, 20, 0], shL: [-50, 0, -18], shR: [-30, 0, 18], elL: [96, 0, 0], elR: [80, 0, 0], hpL: [40, 0, -26], hpR: [26, 0, 26], knL: [-84, 0, 0], knR: [-60, 0, 0], t0: [-40, 30, 0], t1: [0, 22, 0], t2: [0, 22, 0] },
    hind: { pivot: [-78, 0, 0], chest: [-4, 0, 0], neck: [34, 0, 0], head: [40, 0, 0], shL: [58, 0, -10], shR: [58, 0, 10], el: [-96, 0, 0], hp: [74, 0, 0], kn: [4, 0, 0], t0: [86, 0, 0], t1: [-26, 0, 0], t2: [-26, 0, 0] },
    arch: { chest: [30, 0, 0], hip: [-30, 0, 0], neck: [26, 0, 0], head: [14, 0, 0], sh: [-22, 0, 0], el: [-6, 0, 0], hp: [26, 0, 0], kn: [0, 0, 0], t0: [-34, 0, 0], t1: [-10, 0, 0], t2: [10, 0, 0], t3: [16, 0, 0] }
  };
  SG.POSES = POSES;
  SG.POSE_LIST = [['stand', '站立'], ['sit', '坐下'], ['loaf', '母雞蹲'], ['stretch', '伸懶腰'], ['side', '側躺'], ['curl', '蜷成團'], ['belly', '翻肚'], ['hind', '站起來'], ['arch', '拱背']];

  var _v = new THREE.Vector3(), _q = new THREE.Quaternion(), _e = new THREE.Euler(), _m = new THREE.Matrix4();

  function Critter(spec, opt) {
    opt = opt || {};
    var S = this.spec = spec, self = this;
    this.kind = S.kind;
    this.root = new THREE.Group();      // world position + yaw
    this.pivot = new THREE.Group();     // pose rotation + ground offset
    this.root.add(this.pivot);
    this.joints = {}; this.parts = []; this.meshes = [];
    this.pose = 'stand'; this.frozen = false; this.walk = 0; this.speed = 0; this.air = 0;
    this.t = (opt.seed || 0) * 3.7; this.blinkT = 2 + (opt.seed || 0); this.flickT = 1; this.twitchT = 3; this.lookT = 2;
    this.look = [0, 0]; this.lookTo = [0, 0];
    this.eyesOpen = 1; this.wag = 0;
    var A = this.A = opt.atlas || 1024;
    this.alb = new Uint8Array(A * A * 4).fill(255);
    this.orm = new Uint8Array(A * A * 4);
    var baseRough = 0.82;
    for (var i = 0; i < A * A * 4; i += 4) { this.orm[i] = 255; this.orm[i + 1] = Math.round(baseRough * 255); this.orm[i + 2] = 0; this.orm[i + 3] = 255; }
    this.texA = new THREE.DataTexture(this.alb, A, A, THREE.RGBAFormat);
    this.texA.colorSpace = THREE.SRGBColorSpace;
    this.texO = new THREE.DataTexture(this.orm, A, A, THREE.RGBAFormat);
    [this.texA, this.texO].forEach(function (t) { t.magFilter = THREE.LinearFilter; t.minFilter = THREE.LinearMipmapLinearFilter; t.generateMipmaps = true; t.needsUpdate = true; });
    this.mat = new THREE.MeshStandardMaterial({ map: this.texA, roughnessMap: this.texO, metalnessMap: this.texO, roughness: 1, metalness: 1, envMapIntensity: 0.9 });
    this.glow = { value: new THREE.Color(0, 0, 0) }; this.rim = { value: S.kind === 'cat' ? 0.28 : 0.2 };
    this.mat.onBeforeCompile = function (sh) {
      sh.uniforms.uGlow = self.glow; sh.uniforms.uRim = self.rim;
      sh.fragmentShader = sh.fragmentShader.replace('#include <common>', '#include <common>\nuniform vec3 uGlow; uniform float uRim;')
        .replace('#include <opaque_fragment>', [
          'float fz = pow(1.0 - saturate(dot(normal, normalize(vViewPosition))), 2.6);',
          'outgoingLight += diffuseColor.rgb * (reflectedLight.indirectDiffuse * 0.0 + vec3(0.9,0.82,0.7)) * fz * uRim * (1.0 - metalnessFactor) * roughnessFactor;', // soft fur sheen
          'outgoingLight += uGlow * (0.18 + fz * 1.6);',
          '#include <opaque_fragment>'].join('\n'));
    };
    this._shelf = { x: 0, y: 0, h: 0 };
    this._build();
    this.skin.castShadow = true; this.skin.receiveShadow = true; this.faceSkin.receiveShadow = true;
    // pose state
    this.cur = {}; this.names = Object.keys(this.joints);
    this.names.forEach(function (n) { self.cur[n] = new THREE.Quaternion(); });
    this.groundY = 0; this.liftY = 0;
    this.root.scale.setScalar(opt.scale || 1); this.scale = opt.scale || 1;
    this._applyPose(1, 0); this._ground(true);
    if (S.coat) this.applyCoat(COATS[S.coat]);
  }

  var P = Critter.prototype;

  P._joint = function (name, parent, x, y, z, rx, ry, rz) {
    var g = new THREE.Group(); g.position.set(x || 0, y || 0, z || 0);
    g.rotation.set((rx || 0) * D2R, (ry || 0) * D2R, (rz || 0) * D2R);
    g.userData.q0 = g.quaternion.clone();
    (parent || this.pivot).add(g); this.joints[name] = g; return g;
  };

  /* add a paintable lathe part. o: {prof, sx, sz, tw, th, su, sv, pos:[x,y,z], rot:[x,y,z] (deg)} */
  P._part = function (name, joint, o) {
    var A = this.A, g = 4, tw = o.tw || 96, th = o.th || 64, sh = this._shelf;
    if (sh.x + tw > A) { sh.x = 0; sh.y += sh.h; sh.h = 0; }
    var rx = sh.x, ry = sh.y; sh.x += tw; sh.h = Math.max(sh.h, th);
    if (ry + th > A) console.warn('critter atlas full', name);
    var sx = o.sx || 1, sz = o.sz || 1, prof = o.prof;
    function pos(u, v, out, k) {
      var a = u * Math.PI * 2, p = prof(v < 0 ? 0 : v > 1 ? 1 : v);
      out[k] = p[0] * Math.sin(a) * sx; out[k + 1] = p[1]; out[k + 2] = p[0] * Math.cos(a) * sz;
    }
    var su = o.su || 20, sv = o.sv || 12, P3 = [], N3 = [], UV = [], IX = [], i, j, t = [0, 0, 0], t1 = [0, 0, 0], t2 = [0, 0, 0];
    for (j = 0; j <= sv; j++) for (i = 0; i <= su; i++) {
      var u = i / su, v = j / sv;
      pos(u, v, t, 0); P3.push(t[0], t[1], t[2]);
      var vv = Math.min(Math.max(v, 0.004), 0.996);
      pos(u + 0.002, vv, t1, 0); pos(u - 0.002, vv, t2, 0);
      var ax = t1[0] - t2[0], ay = t1[1] - t2[1], az = t1[2] - t2[2];
      pos(u, vv + 0.003, t1, 0); pos(u, vv - 0.003, t2, 0);
      var bx = t1[0] - t2[0], by = t1[1] - t2[1], bz = t1[2] - t2[2];
      var nx = ay * bz - az * by, ny = az * bx - ax * bz, nz = ax * by - ay * bx, l = Math.hypot(nx, ny, nz);
      if (l < 1e-9) { nx = 0; ny = v < 0.5 ? -1 : 1; nz = 0; l = 1; }
      N3.push(nx / l, ny / l, nz / l);
      UV.push((rx + g + u * (tw - 2 * g)) / A, (ry + g + v * (th - 2 * g)) / A);
    }
    for (j = 0; j < sv; j++) for (i = 0; i < su; i++) { var a = j * (su + 1) + i, b = a + 1, c = a + su + 1, d = c + 1; IX.push(a, b, c, b, d, c); }
    var geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.Float32BufferAttribute(P3, 3));
    geo.setAttribute('normal', new THREE.Float32BufferAttribute(N3, 3));
    geo.setAttribute('uv', new THREE.Float32BufferAttribute(UV, 2));
    geo.setIndex(IX); geo.computeBoundingSphere();
    var mesh = new THREE.Mesh(geo, this.mat); mesh.layers.set(3); // not drawn: the merged skinned mesh is; kept for raycasts and as a bone
    if (o.pos) mesh.position.set(o.pos[0], o.pos[1], o.pos[2]);
    if (o.rot) mesh.rotation.set(o.rot[0] * D2R, o.rot[1] * D2R, o.rot[2] * D2R);
    joint.add(mesh);
    // per-texel local positions (gutters included: u wraps, v clamps)
    var tp = new Float32Array(tw * th * 3);
    for (j = 0; j < th; j++) for (i = 0; i < tw; i++) pos((i + 0.5 - g) / (tw - 2 * g), (j + 0.5 - g) / (th - 2 * g), tp, (j * tw + i) * 3);
    var smp = [];
    for (j = 0; j <= 4; j++) for (i = 0; i < 6; i++) { pos(i / 6, j / 4, t, 0); smp.push(t[0], t[1], t[2]); }
    var part = { name: name, mesh: mesh, rx: rx, ry: ry, tw: tw, th: th, tp: tp, samples: new Float32Array(smp), c: geo.boundingSphere.center.clone(), r: geo.boundingSphere.radius, inv: new THREE.Matrix4() };
    mesh.userData.part = part; mesh.userData.critter = this;
    this.parts.push(part); this.meshes.push(mesh);
    return part;
  };

  P._deco = function (joint, geo, mat, x, y, z) { var m = new THREE.Mesh(geo, mat); m.position.set(x, y, z); m.layers.set(3); joint.add(m); (this.decos = this.decos || []).push(m); return m; };

  P._build = function () {
    var S = this.spec, L = S.len, J = this._joint.bind(this), self = this, dog = S.kind === 'dog';
    var body = J('body', this.pivot);
    this._part('belly', body, { prof: ell(S.bellyR, L * 0.36), rot: [90, 0, 0], sz: 0.95, tw: 320, th: 224, su: 28, sv: 16 });
    var chest = J('chest', body, 0, 0, L * 0.18);
    this._part('chest', chest, { prof: ell(S.chestR, L * 0.27), rot: [90, 0, 0], pos: [0, 0.005, L * 0.07], sz: 1.0, tw: 320, th: 224, su: 28, sv: 16 });
    var hip = J('hip', body, 0, 0, -L * 0.18);
    this._part('hips', hip, { prof: ell(S.hipR, L * 0.27), rot: [90, 0, 0], pos: [0, 0, -L * 0.07], sz: 1.0, tw: 320, th: 224, su: 28, sv: 16 });
    // neck + head
    var nUp = dog ? 52 : 40;
    var neck = J('neck', chest, 0, S.chestR * 0.42, L * 0.20, 0, 0, 0);
    var nl = S.neck, nr = Math.min(S.chestR * 0.66, S.headR * 0.72);
    this._part('neck', neck, { prof: cap(nl + 0.02, nr * 0.9, nr * 1.05), rot: [180 - (90 - nUp), 0, 0], pos: [0, -0.01, -0.01], tw: 128, th: 80 });
    var head = J('head', neck, 0, nl * Math.sin(nUp * D2R), nl * Math.cos(nUp * D2R));
    var HR = S.headR, hc = [0, HR * 0.5, HR * 0.3], Rx = HR * S.headSx, Ry = HR * S.headSy, Rz = HR * 0.96;
    this._part('head', head, { prof: ell(HR, Ry), sx: S.headSx, sz: 0.96, pos: hc, tw: 384, th: 256, su: 32, sv: 20 });
    function onHead(dx, dy, dz, k) { var l = Math.hypot(dx, dy, dz); k = k || 1; return [hc[0] + dx / l * Rx * k, hc[1] + dy / l * Ry * k, hc[2] + dz / l * Rz * k]; }
    this.onHead = onHead;
    var mz = [0, hc[1] - HR * (dog ? 0.2 : 0.3), hc[2] + Rz * (dog ? 0.62 : 0.8)];
    if (dog) this._part('muzzle', head, { prof: ell(S.muzzleR, S.muzzleL + S.muzzleR * 0.35), rot: [96, 0, 0], sx: 1.0, sz: 0.82, pos: [mz[0], mz[1], mz[2] + S.muzzleL * 0.45], tw: 128, th: 96, su: 18, sv: 10 });
    else [-1, 1].forEach(function (s) { // cats: two whisker pads instead of a snout
      self._part('pad' + (s < 0 ? 'L' : 'R'), head, { prof: ell(S.muzzleR * 0.62, S.muzzleR * 0.5), sz: 0.8, pos: [s * S.muzzleR * 0.46, mz[1], mz[2] + S.muzzleL * 0.3], tw: 64, th: 48, su: 14, sv: 8 });
    });
    if (S.jowl) [-1, 1].forEach(function (s) {
      self._part('jowl' + s, head, { prof: ell(S.muzzleR * 0.7, S.muzzleR * 0.72), pos: [s * S.muzzleR * 0.62, mz[1] - S.muzzleR * 0.4, mz[2] + S.muzzleL * 0.5], tw: 64, th: 48, su: 14, sv: 8 });
    });
    // face details (not paintable)
    var dark = new THREE.MeshStandardMaterial({ color: 0x1b1512, roughness: 0.18, metalness: 0.0, envMapIntensity: 1.4 });
    var pink = new THREE.MeshStandardMaterial({ color: dog ? 0x241a18 : 0xe79a9a, roughness: dog ? 0.25 : 0.5 });
    this.eyes = [];
    [-1, 1].forEach(function (s) {
      var p = onHead(s * (dog ? 0.42 : 0.5), dog ? 0.2 : 0.06, 0.84, 0.985);
      var eg = new THREE.Group(); eg.position.set(p[0], p[1], p[2]); eg.lookAt(p[0] * 2 - hc[0], p[1] * 2 - hc[1] + 0.0, p[2] * 2 - hc[2]); head.add(eg);
      var e = new THREE.Mesh(new THREE.SphereGeometry(S.eye, 16, 12), dark); e.scale.set(0.9, 1.12, 0.42); eg.add(e);
      var hl = new THREE.Mesh(new THREE.SphereGeometry(S.eye * 0.26, 8, 6), new THREE.MeshBasicMaterial({ color: 0xffffff }));
      hl.position.set(-S.eye * 0.28, S.eye * 0.42, S.eye * 0.36); e.add(hl); hl.scale.set(1.1, 0.9, 2.2); hl.layers.set(3); e.layers.set(3); self.decos = self.decos || []; self.decos.push(e, hl);
      self.eyes.push(eg);
    });
    var noseP = [0, mz[1] + S.muzzleR * (dog ? 0.3 : 0.36), mz[2] + (dog ? S.muzzleL * 1.38 + S.muzzleR * 0.3 : S.muzzleL * 0.3 + S.muzzleR * 0.42)];
    this.nose = this._deco(head, new THREE.SphereGeometry(dog ? S.muzzleR * 0.34 : 0.013, 12, 8), pink, noseP[0], noseP[1], noseP[2]);
    this.nose.scale.set(1.25, 0.8, 0.8);
    this.face = [this.nose].concat(this.eyes);
    if (!dog) { // whiskers
      var wm = new THREE.MeshBasicMaterial({ color: 0xffffff }), wg = new THREE.CylinderGeometry(0.0012, 0.0006, HR * 0.75, 4);
      [-1, 1].forEach(function (s) { for (var w = 0; w < 3; w++) { var m = self._deco(head, wg, wm, s * (S.muzzleR * 0.9 + HR * 0.34), mz[1] + (w - 1) * 0.012, mz[2] + S.muzzleL * 0.2); m.rotation.set(0, 0, s * (Math.PI / 2 + (w - 1) * 0.22)); m.rotation.y = -s * 0.35; self.face.push(m); m.castShadow = false; } });
    }
    if (dog) { // tongue for charm
      var tg = this._deco(head, SG.geo.rbox(S.muzzleR * 0.62, 0.012, S.muzzleR * 1.0, 0.005), new THREE.MeshStandardMaterial({ color: 0xe8788a, roughness: 0.45 }), 0, mz[1] - S.muzzleR * 0.62, mz[2] + S.muzzleL * 0.95);
      tg.rotation.x = 0.5; this.tongue = tg; this.face.push(tg);
    }
    // ears
    var E = S.ear;
    [-1, 1].forEach(function (s) {
      var p = onHead(s * E.spread, E.type === 'flop' ? 0.45 : 0.82, E.type === 'flop' ? 0.0 : -0.05, E.type === 'flop' ? 0.9 : 0.86);
      var ej = J(s < 0 ? 'earL' : 'earR', head, p[0], p[1], p[2], E.type === 'fold' ? 62 : (E.type === 'flop' ? 0 : -6), 0, E.type === 'flop' ? -s * 168 : -s * E.tilt);
      self._part('ear' + (s < 0 ? 'L' : 'R'), ej, { prof: cone(E.h, E.w, E.type === 'flop' ? 0.45 : 0.8), sz: 0.42, pos: [0, -0.012, 0], tw: 80, th: 64, su: 14, sv: 8 });
      if (E.type === 'point' && !dog) { // inner ear
        var inn = self._deco(ej, new THREE.ConeGeometry(E.w * 0.58, E.h * 0.72, 10), new THREE.MeshStandardMaterial({ color: 0xf2b6b0, roughness: 0.8 }), 0, E.h * 0.28, E.w * 0.2);
        inn.scale.z = 0.3; self.face.push(inn);
      }
      if (S.pom) self._part('earPom' + s, ej, { prof: ell(0.07, 0.085), pos: [0, E.h * 0.85, 0], tw: 96, th: 64, su: 14, sv: 8 });
    });
    if (S.pom) this._part('topPom', head, { prof: ell(HR * 0.72, HR * 0.6), pos: [0, hc[1] + Ry * 0.82, hc[2] - HR * 0.1], tw: 128, th: 96, su: 16, sv: 10 });
    if (S.fluff) {
      [-1, 1].forEach(function (s) {
        var p = onHead(s * 0.9, -0.42, 0.25, 0.86);
        self._part('cheek' + s, head, { prof: cone(HR * 0.62, HR * 0.5, 0.7), sz: 0.6, pos: p, rot: [0, 0, -s * 112], tw: 96, th: 64, su: 14, sv: 8 });
      });
      this._part('ruff', chest, { prof: ell(S.chestR * 0.9, S.chestR * 0.82), pos: [0, -S.chestR * 0.3, L * 0.3], sx: 1.05, tw: 192, th: 128, su: 20, sv: 12 });
    }
    // legs
    var legF = S.leg, hipDrop = S.hipR * 0.3, shDrop = S.chestR * 0.35, legR = legF + (shDrop - hipDrop);
    var st = S.stance || 1;
    function leg(pref, parent, x, y, z, len, fat) {
      var up = len * 0.5, lo = Math.max(0.01, len * 0.5 - S.paw * 0.75);
      var a = J(pref, parent, x, y, z);
      self._part(pref + 'U', a, { prof: cap(up, S.legRad * fat, S.legRad * 1.12), tw: 112, th: 80, su: 14, sv: 10 });
      var b = J(pref.replace('sh', 'el').replace('hp', 'kn'), a, 0, -up, 0);
      self._part(pref + 'D', b, { prof: cap(lo, S.legRad * 1.1, S.paw), sz: 1.12, pos: [0, 0, S.paw * 0.12], tw: 112, th: 96, su: 14, sv: 10 });
      if (S.pom) self._part(pref + 'P', b, { prof: ell(S.paw * 1.35, S.paw * 1.2), pos: [0, -lo * 0.55, 0], tw: 96, th: 64, su: 14, sv: 8 });
    }
    leg('shL', chest, -S.chestR * 0.52 * st, -shDrop, L * 0.12, legF, 1.5);
    leg('shR', chest, S.chestR * 0.52 * st, -shDrop, L * 0.12, legF, 1.5);
    leg('hpL', hip, -S.hipR * 0.56 * st, -hipDrop, -L * 0.13, legR, 1.9);
    leg('hpR', hip, S.hipR * 0.56 * st, -hipDrop, -L * 0.13, legR, 1.9);
    // tail
    var T = S.tail, n = T.segs || 4, sl = T.len / n, parent = hip, i;
    this.tailN = n;
    for (i = 0; i < n; i++) {
      var tj = J('t' + i, parent, 0, i === 0 ? S.hipR * 0.42 : -sl, i === 0 ? -L * 0.30 : 0, i === 0 ? T.up : T.curl, 0, 0);
      var k0 = i / n, k1 = (i + 1) / n, ra, rb;
      if (T.bushy) { ra = T.r0 + (T.r1 - T.r0) * Math.sin(k0 * Math.PI * 0.8); rb = T.r0 + (T.r1 - T.r0) * Math.sin(k1 * Math.PI * 0.8) * (i === n - 1 ? 0.6 : 1); }
      else { ra = T.r0 + (T.r1 - T.r0) * k0; rb = T.r0 + (T.r1 - T.r0) * k1; }
      this._part('tail' + i, tj, { prof: cap(sl, ra, rb), tw: 80, th: 64, su: 12, sv: 8 });
      parent = tj;
    }
    if (S.pom) this._part('tailPom', parent, { prof: ell(0.065, 0.065), pos: [0, -sl, 0], tw: 96, th: 64, su: 14, sv: 8 });
    this._skin();
  };

  /* one skinned mesh for the body (bones = the rigid parts) and one for the face details: 2 draw calls per animal */
  P._skin = function () {
    var ident = new THREE.Matrix4(), self = this;
    function build(objs, mat, colored) {
      var items = objs.map(function (o) { return [o.geometry, null, colored ? o.material.color : null]; });
      var g = SG.geo.merge(items), n = g.attributes.position.count, si = new Uint16Array(n * 4), sw = new Float32Array(n * 4), k = 0;
      objs.forEach(function (o, b) { var c = o.geometry.attributes.position.count; for (var i = 0; i < c; i++, k++) { si[k * 4] = b; sw[k * 4] = 1; } });
      g.setAttribute('skinIndex', new THREE.BufferAttribute(si, 4)); g.setAttribute('skinWeight', new THREE.BufferAttribute(sw, 4));
      var sk = new THREE.SkinnedMesh(g, mat); sk.frustumCulled = false;
      sk.bind(new THREE.Skeleton(objs, objs.map(function () { return ident.clone(); })), ident);
      self.root.add(sk); return sk;
    }
    this.skin = build(this.meshes, this.mat, false);
    this.faceMat = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.28, envMapIntensity: 1.2 });
    this.faceSkin = build(this.decos || [], this.faceMat, true); this.faceSkin.userData.noShadow = true;
  };

  /* ---------- pose + animation ---------- */
  function poseEuler(P0, name) {
    var v = P0[name];
    if (!v) {
      var side = name.slice(-1), base = name.slice(0, -1);
      if ((side === 'L' || side === 'R') && P0[base]) { v = P0[base]; return side === 'R' ? [v[0], -v[1], -v[2]] : v; }
      return null;
    }
    return v;
  }
  P.setPose = function (name) { if (POSES[name]) this.pose = name; };

  P._applyPose = function (k, dt) {
    var P0 = POSES[this.pose] || POSES.stand, J = this.joints, n, i;
    for (i = 0; i < this.names.length; i++) {
      n = this.names[i];
      var v = poseEuler(P0, n);
      if (v) { _e.set(v[0] * D2R, v[1] * D2R, v[2] * D2R, 'YXZ'); _q.setFromEuler(_e); } else _q.identity();
      this.cur[n].slerp(_q, k);
      J[n].quaternion.copy(J[n].userData.q0).multiply(this.cur[n]);
    }
    var pv = P0.pivot || [0, 0, 0];
    _e.set(pv[0] * D2R, pv[1] * D2R, pv[2] * D2R, 'YXZ'); _q.setFromEuler(_e);
    if (!this.pq) this.pq = new THREE.Quaternion();
    this.pq.slerp(_q, k); this.pivot.quaternion.copy(this.pq);
  };

  function addRot(j, x, y, z) { _e.set(x, y, z); _q.setFromEuler(_e); j.quaternion.multiply(_q); }

  P.update = function (dt, r) {
    r = r || Math.random;
    this.t += dt;
    var J = this.joints, t = this.t, live = this.frozen ? 0 : 1, moving = this.speed > 0.05, S = this.spec;
    this._applyPose(1 - Math.exp(-dt * 9), dt);
    // walk / run cycle
    if (moving && this.pose === 'stand') {
      var run = Math.min(1, Math.max(0, (this.speed - 1.6) / 1.4));
      this.walk += dt * (5.5 + this.speed * 3.2) * Math.max(0.6, 0.2 / Math.max(0.1, S.leg)) * 0.75;
      var A = (0.42 + run * 0.35), ph = this.walk, off = run > 0.5 ? 0.6 : Math.PI;
      var legs = [['shL', 'elL', 0, 1], ['hpR', 'knR', run > 0.5 ? Math.PI * 0.8 : 0, -1], ['shR', 'elR', off, 1], ['hpL', 'knL', off + (run > 0.5 ? Math.PI * 0.8 : 0), -1]];
      for (var i = 0; i < 4; i++) {
        var s = Math.sin(ph + legs[i][2]), c = Math.cos(ph + legs[i][2]);
        addRot(J[legs[i][0]], -s * A, 0, 0);
        addRot(J[legs[i][1]], Math.max(0, c) * A * 1.5 * (legs[i][3] > 0 ? 1 : -0.0) + (legs[i][3] < 0 ? Math.max(0, c) * A * 1.2 : 0), 0, 0);
      }
      this.pivot.position.z = 0;
      addRot(J.body, Math.sin(ph * 2) * 0.02 + run * Math.sin(ph) * 0.1, 0, Math.sin(ph) * 0.03);
      addRot(J.chest, 0, Math.sin(ph) * 0.07, 0); addRot(J.hip, 0, -Math.sin(ph) * 0.09, 0);
      addRot(J.head, Math.sin(ph * 2) * 0.03, 0, 0);
      this.bob = Math.abs(Math.sin(ph)) * (0.008 + run * 0.03);
    } else this.bob = 0;
    if (this.air > 0.02) { // jump: legs reach out
      var a = Math.min(1, this.air * 5);
      ['shL', 'shR'].forEach(function (n) { addRot(J[n], -0.9 * a, 0, 0); });
      ['hpL', 'hpR'].forEach(function (n) { addRot(J[n], 0.8 * a, 0, 0); });
      addRot(J.t0, -0.5 * a, 0, 0);
    }
    // idle life
    if (live) {
      var br = Math.sin(t * 2.2);
      J.chest.scale.setScalar(1 + br * 0.012); J.body.scale.set(1 + br * 0.01, 1 + br * 0.014, 1);
      // tail sway + occasional flick
      this.flickT -= dt; if (this.flickT < 0) { this.flickT = 2.5 + r() * 4; this.flick = 1; }
      this.flick = Math.max(0, (this.flick || 0) - dt * 1.6);
      var wagA = this.wag ? 0.55 : 0.0, tw = Math.sin(t * (this.wag ? 13 : 1.7)) * (0.07 + wagA) + Math.sin(t * 9) * 0.5 * this.flick;
      for (var k = 0; k < this.tailN; k++) addRot(J['t' + k], 0, 0, tw * (0.5 + k * 0.35) * (this.kind === 'dog' && !this.wag ? 0.5 : 1));
      // ear twitch
      this.twitchT -= dt; if (this.twitchT < 0) { this.twitchT = 2 + r() * 5; this.twitch = 1; this.twSide = r() < 0.5 ? 'earL' : 'earR'; }
      this.twitch = Math.max(0, (this.twitch || 0) - dt * 5);
      if (this.twitch > 0 && J[this.twSide]) addRot(J[this.twSide], Math.sin(this.twitch * 12) * 0.3, 0, 0);
      // blink
      this.blinkT -= dt; if (this.blinkT < 0) this.blinkT = 2.2 + r() * 4;
      var bl = this.blinkT < 0.14 ? 0.12 : 1;
      // head look-around
      this.lookT -= dt; if (this.lookT < 0) { this.lookT = 1.5 + r() * 3.5; this.lookTo = [(r() - 0.5) * 0.7, (r() - 0.5) * 0.3]; }
      this.look[0] += (this.lookTo[0] - this.look[0]) * Math.min(1, dt * 4); this.look[1] += (this.lookTo[1] - this.look[1]) * Math.min(1, dt * 4);
      if (!moving) addRot(J.head, this.look[1], this.look[0], 0);
      for (var q = 0; q < this.eyes.length; q++) this.eyes[q].scale.set(1, bl * this.eyesOpen + 0.02, 1);
    } else {
      J.chest.scale.setScalar(1); J.body.scale.setScalar(1);
    }
    this.faceSkin.visible = this.eyesOpen > 0.5;
    this._ground();
  };

  /* keep the lowest point of the body on the ground whatever the pose */
  P._ground = function (snap) {
    this.pivot.position.y = 0;
    this.root.updateMatrixWorld(true);
    var min = 1e9, ry = this.root.matrixWorld.elements[13], i, k;
    for (i = 0; i < this.parts.length; i++) {
      var p = this.parts[i], e = p.mesh.matrixWorld.elements, s = p.samples;
      for (k = 0; k < s.length; k += 3) { var y = e[1] * s[k] + e[5] * s[k + 1] + e[9] * s[k + 2] + e[13]; if (y < min) min = y; }
    }
    var target = (ry - min) / this.scale;
    this.liftY = snap ? target : this.liftY + (target - this.liftY) * 0.5;
    this.pivot.position.y = this.liftY + (this.bob || 0);
    this.root.updateMatrixWorld(true);
  };

  /* ---------- painting ---------- */
  P.raycast = function (raycaster) { // the part meshes live on layer 3
    var m = raycaster.layers.mask; raycaster.layers.set(3);
    var hits = raycaster.intersectObjects(this.meshes, false); raycaster.layers.mask = m;
    return hits.length ? hits[0] : null;
  };
  /* 3D brush: every texel within `radius` of the world point is painted, on every part — so seams and joints just work */
  P.paint = function (wp, radius, rgb, rough, metal, hard) {
    var A = this.A, alb = this.alb, orm = this.orm, any = false, R = radius / this.scale, R2 = R * R;
    hard = hard == null ? 0.7 : hard;
    var inner = R * hard, span = Math.max(1e-5, R - inner), rb = Math.round(rough * 255), mb = Math.round(metal * 255);
    for (var pi = 0; pi < this.parts.length; pi++) {
      var p = this.parts[pi];
      p.inv.copy(p.mesh.matrixWorld).invert();
      _v.copy(wp).applyMatrix4(p.inv);
      if (_v.distanceTo(p.c) > R + p.r) continue;
      if (this._stroke) this._save(pi);
      var lx = _v.x, ly = _v.y, lz = _v.z, tp = p.tp, tw = p.tw, th = p.th, k = 0;
      for (var j = 0; j < th; j++) {
        var row = ((p.ry + j) * A + p.rx) * 4;
        for (var i = 0; i < tw; i++, k += 3) {
          var dx = tp[k] - lx, dy = tp[k + 1] - ly, dz = tp[k + 2] - lz, d2 = dx * dx + dy * dy + dz * dz;
          if (d2 > R2) continue;
          var d = Math.sqrt(d2), a = d <= inner ? 1 : 1 - (d - inner) / span;
          a = a * a * (3 - 2 * a);
          var o = row + i * 4;
          alb[o] += (rgb[0] - alb[o]) * a; alb[o + 1] += (rgb[1] - alb[o + 1]) * a; alb[o + 2] += (rgb[2] - alb[o + 2]) * a;
          orm[o + 1] += (rb - orm[o + 1]) * a; orm[o + 2] += (mb - orm[o + 2]) * a;
          any = true;
        }
      }
    }
    if (any) { this.texA.needsUpdate = true; this.texO.needsUpdate = true; }
    return any;
  };
  P._save = function (pi) {
    var st = this._stroke; if (st.parts[pi]) return;
    var p = this.parts[pi], A = this.A, n = p.tw * 4, a = new Uint8Array(n * p.th), o = new Uint8Array(n * p.th);
    for (var j = 0; j < p.th; j++) { var off = ((p.ry + j) * A + p.rx) * 4; a.set(this.alb.subarray(off, off + n), j * n); o.set(this.orm.subarray(off, off + n), j * n); }
    st.parts[pi] = { a: a, o: o };
  };
  P.beginStroke = function () { this._stroke = { parts: {} }; };
  P.endStroke = function () { var s = this._stroke; this._stroke = null; return s && Object.keys(s.parts).length ? s : null; };
  P.undoStroke = function (st) {
    var A = this.A;
    for (var pi in st.parts) { var p = this.parts[pi], n = p.tw * 4, rec = st.parts[pi]; for (var j = 0; j < p.th; j++) { var off = ((p.ry + j) * A + p.rx) * 4; this.alb.set(rec.a.subarray(j * n, j * n + n), off); this.orm.set(rec.o.subarray(j * n, j * n + n), off); } }
    this.texA.needsUpdate = true; this.texO.needsUpdate = true;
  };
  P.copyPaintFrom = function (other) { this.alb.set(other.alb); this.orm.set(other.orm); this.texA.needsUpdate = true; this.texO.needsUpdate = true; };
  P.fill = function (rgb, rough, metal) {
    if (this._stroke) for (var q = 0; q < this.parts.length; q++) this._save(q);
    var alb = this.alb, orm = this.orm, rb = Math.round(rough * 255), mb = Math.round(metal * 255);
    for (var pi = 0; pi < this.parts.length; pi++) { var p = this.parts[pi]; for (var j = 0; j < p.th; j++) { var i = ((p.ry + j) * this.A + p.rx) * 4, e = i + p.tw * 4; for (; i < e; i += 4) { alb[i] = rgb[0]; alb[i + 1] = rgb[1]; alb[i + 2] = rgb[2]; orm[i + 1] = rb; orm[i + 2] = mb; } } }
    this.texA.needsUpdate = true; this.texO.needsUpdate = true;
  };
  P.snapshot = function () { return { a: this.alb.slice(), o: this.orm.slice() }; };
  P.restore = function (s) { this.alb.set(s.a); this.orm.set(s.o); this.texA.needsUpdate = true; this.texO.needsUpdate = true; };
  /* visit every texel with its current world position: fn(x,y,z, partName) -> [r,g,b] or null */
  P.eachTexel = function (fn, step) {
    var A = this.A, alb = this.alb; step = step || 1;
    this.root.updateMatrixWorld(true);
    for (var pi = 0; pi < this.parts.length; pi++) {
      var p = this.parts[pi], e = p.mesh.matrixWorld.elements, tp = p.tp;
      for (var j = 0; j < p.th; j++) for (var i = 0; i < p.tw; i++) {
        var k = (j * p.tw + i) * 3, x = tp[k], y = tp[k + 1], z = tp[k + 2];
        var c = fn(e[0] * x + e[4] * y + e[8] * z + e[12], e[1] * x + e[5] * y + e[9] * z + e[13], e[2] * x + e[6] * y + e[10] * z + e[14], p.name, i, j);
        if (c) { var o = ((p.ry + j) * A + p.rx + i) * 4; alb[o] = c[0]; alb[o + 1] = c[1]; alb[o + 2] = c[2]; }
      }
    }
    this.texA.needsUpdate = true;
  };
  /* fraction of texels that are no longer plain white (for the tutorial + stats) */
  P.paintedRatio = function () {
    var n = 0, tot = 0, alb = this.alb, A = this.A;
    for (var pi = 0; pi < this.parts.length; pi++) {
      var p = this.parts[pi];
      for (var j = 0; j < p.th; j += 4) for (var i = 0; i < p.tw; i += 4) { var o = ((p.ry + j) * A + p.rx + i) * 4; tot++; if (alb[o] < 240 || alb[o + 1] < 240 || alb[o + 2] < 240) n++; }
    }
    return n / tot;
  };

  /* world-space bounding spheres of the parts (ball hits, dog vision framing) */
  P.spheres = function () {
    var out = [];
    for (var i = 0; i < this.parts.length; i++) { var p = this.parts[i]; var c = p.c.clone().applyMatrix4(p.mesh.matrixWorld); out.push({ c: c, r: p.r * this.scale * 0.85 }); }
    return out;
  };
  P.center = function (out) {
    out = out || new THREE.Vector3();
    return out.setFromMatrixPosition(this.joints.body.matrixWorld);
  };

  /* ---------- dog coats (drawn into the same atlas the cats paint on) ---------- */
  function h3(x, y, z) { var s = Math.sin(x * 127.1 + y * 311.7 + z * 74.7) * 43758.5453; return s - Math.floor(s); }
  function vnoise(x, y, z) {
    var xi = Math.floor(x), yi = Math.floor(y), zi = Math.floor(z), xf = x - xi, yf = y - yi, zf = z - zi;
    xf = xf * xf * (3 - 2 * xf); yf = yf * yf * (3 - 2 * yf); zf = zf * zf * (3 - 2 * zf);
    function L(a, b, t) { return a + (b - a) * t; }
    return L(L(L(h3(xi, yi, zi), h3(xi + 1, yi, zi), xf), L(h3(xi, yi + 1, zi), h3(xi + 1, yi + 1, zi), xf), yf),
      L(L(h3(xi, yi, zi + 1), h3(xi + 1, yi, zi + 1), xf), L(h3(xi, yi + 1, zi + 1), h3(xi + 1, yi + 1, zi + 1), xf), yf), zf);
  }
  SG.vnoise = vnoise;
  function mix3(a, b, t) { t = t < 0 ? 0 : t > 1 ? 1 : t; return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t]; }
  var COATS = {
    // p = rest position relative to body centre (y up, z forward), h = height above ground 0..1, name = part
    shiba: function (p, h, name, S) {
      var tan = [214, 136, 62], cream = [250, 240, 222];
      var under = (0.36 - h) * 9 + vnoise(p[0] * 30, p[1] * 30, p[2] * 30) * 0.6;
      if (name === 'muzzle' || name.indexOf('jowl') === 0) under = 2;
      if (name === 'head') under = Math.max(under, (0.18 - Math.abs(p[0]) * 0 - (p[1] - S.neckY)) * 0 + (Math.abs(p[0]) > S.headR * 0.5 && p[1] < S.headY ? 1.5 : -1));
      if (name === 'chest') under = Math.max(under, (p[2] - S.len * 0.33) * 30);
      if (name.slice(-1) === 'D') under = Math.max(under, 0.8);
      if (name.indexOf('tail') === 0) under = Math.max(under, p[2] > -S.len * 0.42 ? 1 : -1);
      var c = mix3(tan, cream, under);
      var n = vnoise(p[0] * 90, p[1] * 90, p[2] * 90) * 14 - 7; return [c[0] + n, c[1] + n, c[2] + n];
    },
    corgi: function (p, h, name, S) {
      var or = [226, 150, 72], wh = [252, 248, 240];
      var w = (0.30 - h) * 10;
      if (name === 'muzzle') w = 2;
      if (name === 'head') w = (S.headR * 0.2 - Math.abs(p[0])) * 60;
      if (name === 'chest' || name === 'neck') w = Math.max(w, (p[2] - S.len * 0.3) * 22 + (0.0 - (p[1])) * 8);
      if (name.slice(-1) === 'D' || name.slice(-1) === 'U' && name.indexOf('sh') === 0) w = 2;
      if (name.indexOf('ear') === 0) w = -1;
      var c = mix3(or, wh, w), n = vnoise(p[0] * 90, p[1] * 90, p[2] * 90) * 12 - 6; return [c[0] + n, c[1] + n, c[2] + n];
    },
    bull: function (p, h, name, S) {
      var wh = [248, 244, 236], br = [128, 86, 58];
      var n = vnoise(p[0] * 7 + 3.1, p[1] * 7, p[2] * 7 + 1.7);
      var w = (n - 0.52) * 14;
      if (name === 'muzzle' || name.indexOf('jowl') === 0) w = -2;
      if (name === 'head') w = p[0] > S.headR * 0.12 ? 2 : -2;
      if (name === 'earR') w = 2;
      if (name.slice(-1) === 'D') w = -2;
      var c = mix3(wh, br, w), k = vnoise(p[0] * 80, p[1] * 80, p[2] * 80) * 10 - 5; return [c[0] + k, c[1] + k, c[2] + k];
    },
    poodle: function (p, h, name, S) {
      var a = [226, 180, 142], b = [196, 146, 108];
      var n = vnoise(p[0] * 60, p[1] * 60, p[2] * 60), n2 = vnoise(p[0] * 150 + 9, p[1] * 150, p[2] * 150);
      return mix3(b, a, n * 0.8 + n2 * 0.5 - 0.1);
    }
  };
  P.applyCoat = function (fn) {
    var self = this, S = this.spec, ext = { len: S.len, headR: S.headR };
    this.root.updateMatrixWorld(true);
    var inv = new THREE.Matrix4().copy(this.root.matrixWorld).invert(), bodyM = new THREE.Matrix4().multiplyMatrices(inv, this.joints.body.matrixWorld);
    var by = bodyM.elements[13], top = 0;
    var hw = new THREE.Vector3().setFromMatrixPosition(new THREE.Matrix4().multiplyMatrices(inv, this.joints.head.matrixWorld));
    ext.headY = hw.y - by + S.headR * 0.42; ext.neckY = hw.y - by;
    this.parts.forEach(function (p) { var y = new THREE.Vector3().setFromMatrixPosition(new THREE.Matrix4().multiplyMatrices(inv, p.mesh.matrixWorld)).y + p.r; if (y > top) top = y; });
    var e = inv.elements, pp = [0, 0, 0];
    this.eachTexel(function (x, y, z, name) {
      var lx = e[0] * x + e[4] * y + e[8] * z + e[12], ly = e[1] * x + e[5] * y + e[9] * z + e[13], lz = e[2] * x + e[6] * y + e[10] * z + e[14];
      pp[0] = lx; pp[1] = ly - by; pp[2] = lz - bodyM.elements[14];
      var c = fn(pp, ly / top, name, ext);
      return [Math.max(0, Math.min(255, c[0])), Math.max(0, Math.min(255, c[1])), Math.max(0, Math.min(255, c[2]))];
    });
  };
  P.dispose = function () { this.texA.dispose(); this.texO.dispose(); this.mat.dispose(); this.faceMat.dispose(); this.skin.geometry.dispose(); this.faceSkin.geometry.dispose(); this.skin.skeleton.dispose(); this.faceSkin.skeleton.dispose(); this.meshes.forEach(function (m) { m.geometry.dispose(); }); };

  SG.Critter = Critter;
})();
