/* 貓躲狗找 — game glue: boot, entities, input, cameras, bots, round flow (rules live in core/rules.js). */
(function () {
  'use strict';
  var SG = (window.SG = window.SG || {});
  var RULES = (SG.RULES = JSON.parse(JSON.stringify(window.SG_RULES)));
  var Core = window.SGCore;
  var Q = new URLSearchParams(location.search);
  var bus = (SG.bus = { h: {}, on: function (t, f) { (this.h[t] = this.h[t] || []).push(f); }, emit: function (t, d) { (this.h[t] || []).forEach(function (f) { f(d); }); (this.h['*'] || []).forEach(function (f) { f(t, d); }); } });

  var canvas, post, scene, camera, room, ray = new THREE.Raycaster(), rnd = SG.rng(Q.get('seed') ? +Q.get('seed') : 7);
  var ELECTRON = /Electron/i.test(navigator.userAgent);
  var G = (SG.game = { electron: ELECTRON,
    mode: 'boot', side: null, state: null, ents: [], me: null, time: 0, roundT: 0, simT: 0,
    cam: { yaw: 0.6, pitch: 0.32, dist: 2.6, free: null }, keys: {}, mouse: { x: 0, y: 0, down: [false, false, false] },
    paint: { on: false, rgb: [47, 75, 124], rough: 0.8, metal: 0, size: RULES.paint.brushDefaultCm / 100, hard: true, tool: 'brush', undo: [], last: null },
    shots: [], marks: [], confetti: [], decoys: [], decoyCd: 0, decoySlots: [{ cd: 0, e: null }, { cd: 0, e: null }], guide: 0, hitstop: 0, labels: []
  });
  G.opts = { sens: 1, invertY: false, fov: 105, res: 1, shadows: true, post: true, lang: 'zh', sfx: 1, amb: 0.3, music: 0.125, searchMusic: false, fpsCap: 0, showFps: false, quality: Q.get('q') === 'low' ? 'low' : 'high' };
  var V = function (x, y, z) { return new THREE.Vector3(x, y, z); };
  var tmp = V(), tmp2 = V();

  /* ------------------------------------------------------------------ boot */
  SG.boot = function (onProgress) {
    canvas = document.getElementById('gl');
    var low = Q.get('q') === 'low';
    post = SG.post = new SG.Post(canvas, { low: low });
    scene = SG.scene = new THREE.Scene();
    camera = SG.camera = new THREE.PerspectiveCamera(52, 16 / 9, 0.06, 160);
    camera.layers.enable(1);
    // procedural environment for glossy / metallic paint
    var es = new THREE.Scene();
    es.add(new THREE.Mesh(new THREE.SphereGeometry(10, 24, 12), new THREE.ShaderMaterial({
      side: THREE.BackSide,
      vertexShader: 'varying vec3 vP; void main(){ vP=position; gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.); }',
      fragmentShader: 'varying vec3 vP; void main(){ vec3 d=normalize(vP); vec3 c=mix(vec3(0.55,0.4,0.26),vec3(0.75,0.62,0.45),smoothstep(-0.3,0.6,d.y)); c+=vec3(4.0,3.4,2.4)*smoothstep(0.75,0.95,dot(d,normalize(vec3(-0.2,0.35,0.9)))); c+=vec3(1.6,1.2,0.7)*smoothstep(0.9,0.99,d.y); gl_FragColor=vec4(c,1.); }'
    })));
    var pm = new THREE.PMREMGenerator(post.renderer);
    scene.environment = pm.fromScene(es, 0.03).texture; scene.environmentIntensity = 0.55;
    var T = SG.bootT = { t0: performance.now() };
    function stage(frac, text, fn) { return function (next) { if (onProgress) onProgress(frac, text); setTimeout(function () { try { fn(); } catch (e) { console.error(e); window.__error = String(e && e.stack || e); return; } next(); }, 0); }; }
    var steps = [
      stage(0.15, '蓋房子…', function () { room = SG.room = SG.buildRoom(scene, { low: low }); T.build = Math.round(performance.now() - T.t0); }),
      stage(0.7, '擺家具、開燈…', function () {
    resize(); window.addEventListener('resize', resize);
        G.fx = new SG.PaintFX(post.renderer, scene);
        bindInput();
        if (SG.ui) SG.ui.init(); if (SG.ui2) SG.ui2.init();
        if (SG.audio) SG.audio.init();
        var shot = Q.get('shot');
        if (shot && SHOTS[shot]) SHOTS[shot](); else toTitle();
        var last = performance.now();
        function frame(now) {
          if (G.opts.fpsCap && now - last < 1000 / G.opts.fpsCap - 1) { requestAnimationFrame(frame); return; }
          var raw = Math.max(0, Math.min(0.1, (now - last) / 1000)), dt = raw; last = now; G.ft = G.ft == null ? raw : G.ft + (raw - G.ft) * 0.08; G.ftMax = Math.max((G.ftMax || 0) * 0.995, raw);
          // smooth motion: (1) frame timestamps jitter by a millisecond or two even when the display is perfectly regular, so a frame time close to the running average
          // is replaced by that average (the small difference is paid back over the next frames); (2) a long frame is simulated in several short steps, so jumps,
          // easing and collisions behave the same at 30 fps as at 240. Simulated time always equals displayed time: nothing needs interpolating.
          G.dtAvg = G.dtAvg == null ? raw : G.dtAvg + (raw - G.dtAvg) * 0.08;
          if (Math.abs(raw - G.dtAvg) < G.dtAvg * 0.25) { G.dtDebt = (G.dtDebt || 0) + raw - G.dtAvg; var pay = Math.max(-0.001, Math.min(0.001, G.dtDebt * 0.1)); dt = G.dtAvg + pay; G.dtDebt -= pay; } else G.dtDebt = 0;
          if (!G.paused) { var nsub = Math.max(1, Math.ceil(dt / (1 / 90))); G.subSteps = nsub; for (var si = 0; si < nsub; si++) update(dt / nsub); }
          render(dt);
          G.frames = (G.frames || 0) + 1;
          requestAnimationFrame(frame);
        }
        requestAnimationFrame(frame);
        T.first = Math.round(performance.now() - T.t0);
      }),
      stage(1, '', function () { window.__ready = true; })
    ];
    (function run(i) { if (i < steps.length) steps[i](function () { run(i + 1); }); })(0);
  };
  function resize() {
    var w = window.innerWidth, h = window.innerHeight, dpr = Math.min(window.devicePixelRatio || 1, Q.get('q') === 'low' ? 1 : 1.5);
    post.setSize(w, h, dpr * G.opts.res); camera.aspect = w / h; camera.updateProjectionMatrix(); G.vw = w; G.vh = h;
  }

  /* ------------------------------------------------------------------ entities */
  var postDef = null;
  G.applyOpts = function () { var O = G.opts; if (!postDef) postDef = [post.final.uBloom.value, post.final.uAO.value]; resize(); room.sunLight.castShadow = !!O.shadows; post.final.uBloom.value = O.post ? postDef[0] : 0; post.final.uAO.value = O.post ? postDef[1] : 0; };
  /* top-down picture of the map for the lobby card and the room settings (ceilings cut away) */
  var mapUrl = null;
  G.mapImage = function () {
    if (mapUrl) return mapUrl; var b = room.bounds, W = 400, hw = (b.x1 - b.x0) / 2, hd = (b.z1 - b.z0) / 2, H = Math.round(W * hd / hw), cx = (b.x0 + b.x1) / 2, cz = (b.z0 + b.z1) / 2;
    var cam = new THREE.OrthographicCamera(-hw, hw, hd, -hd, 0.01, 60); cam.position.set(cx, 2.2 * SG.WS, cz); cam.up.set(0, 0, -1); cam.lookAt(cx, 0, cz); cam.updateMatrixWorld(true);
    var vis = G.ents.map(function (e) { var v = e.c.root.visible; e.c.root.visible = false; return v; }), px = post.renderAlbedo(scene, cam, W, H); G.ents.forEach(function (e, i) { e.c.root.visible = vis[i]; });
    var cv = document.createElement('canvas'); cv.width = W; cv.height = H; var x = cv.getContext('2d'), id = x.createImageData(W, H);
    for (var j = 0; j < H; j++) for (var i = 0; i < W; i++) { var sI = ((H - 1 - j) * W + i) * 4, dI = (j * W + i) * 4; id.data[dI] = px[sI]; id.data[dI + 1] = px[sI + 1]; id.data[dI + 2] = px[sI + 2]; id.data[dI + 3] = 255; }
    x.putImageData(id, 0, 0); return (mapUrl = cv.toDataURL('image/jpeg', 0.85));
  };
  function spawn(id, spec, team, o) {
    o = o || {};
    var size = o.size || 1, c = new SG.Critter(spec, { seed: G.ents.length + 1, atlas: RULES.paint.textureSize, scale: size });
    scene.add(c.root);
    if (team === 'cat') { c.tailMode = 'tuck'; c.faceSkin.visible = false; c.blank = true; c.rim.value = 0; c.mat.envMapIntensity = 1; } /* same shading as the scenery: no fur sheen, no extra reflection, so equal base colour + roughness looks equal */
    if (team === 'cat') { // OURS (labelled): a cat that lies flat against a surface is shaded with that surface's normal, so the same base colour gives the same lit colour as the wall
      c.flatU = { value: 0 }; c.flatN = { value: new THREE.Vector3(0, 1, 0) }; var obc = c.mat.onBeforeCompile;
      c.mat.onBeforeCompile = function (sh, r) { if (obc) obc.call(this, sh, r); sh.uniforms.uFlat = c.flatU; sh.uniforms.uFlatN = c.flatN;
        sh.fragmentShader = sh.fragmentShader.replace('#include <common>', '#include <common>\nuniform float uFlat; uniform vec3 uFlatN;').replace('#include <normal_fragment_maps>', '#include <normal_fragment_maps>\n normal = normalize(mix(normal, normalize((viewMatrix * vec4(uFlatN, 0.0)).xyz), uFlat)); // SG_AFTER_FLAT\n'); };
      c.mat.customProgramCacheKey = function () { return 'catflat'; };
      if (SG.surfaceDetail) SG.surfaceDetail(c.mat, 'cat', { flat: true }); } // a flush body shows the same grain and dirt as the surface it lies on
    var e = { size: size, id: id, c: c, spec: spec, team: team, bot: !!o.bot, x: o.x || 0, y: o.y || 0, z: o.z || 0, yaw: o.yaw || 0, vy: 0, vx: 0, vz: 0, speed: 0, air: false, out: false, name: o.name || spec.name,
      rad: team === 'dog' ? RULES.dog.bodyRad : Math.max(0.12, spec.bellyR * 0.95 * (spec.scale || 1)) * size, step: 0.16 * SG.WS, sus: 0, decoyOf: o.decoyOf || null, pid: o.pid || id, breed: o.breed, eyeH0: (team === 'dog' && G.settings.breedEyes && RULES.dog.eyeHeight[o.breed]) || RULES.dog.eyeHeightDefault, eyeH: (team === 'dog' && G.settings.breedEyes && RULES.dog.eyeHeight[o.breed]) || RULES.dog.eyeHeightDefault };
    if (o.pose) c.setPose(o.pose);
    place(e);
    if (c.measure) fitBody(e);
    G.ents.push(e); return e;
  }
  /* the animals are flat mats: the collider is a low capsule (half width `rad`, half length `halfLen` along the facing, height `h`)
     taken from the body's own measurements, and a dog's eye height comes from its eye anchor (low by default, higher when it rears up) */
  function fitBody(e) {
    var c = e.c, pose = c.pose, amt = c.poseAmount; c.setPose('stand'); c.rearUp = 0; if (c.settle) c.settle(); c.root.updateMatrixWorld(true);
    var ms = c.measure().size; e.rad = Math.max(0.09, ms[0] * 0.46); e.halfLen = Math.max(e.rad, ms[2] * 0.46); e.h = Math.max(0.1, ms[1] * 0.9); e.step = RULES.move.stepUp;
    if (e.team === 'dog' && c.anchor) { var a = c.anchor('eye', V()); e.eyeLo = Math.max(0.12, a.y - e.y); e.eyeF = Math.hypot(a.x - e.x, a.z - e.z); c.rearUp = 1; c.settle(); c.root.updateMatrixWorld(true); a = c.anchor('eye', a); e.eyeHi = Math.max(e.eyeLo, a.y - e.y); e.eyeFHi = Math.hypot(a.x - e.x, a.z - e.z); c.rearUp = 0; e.rear = 0; e.eyeH0 = e.eyeH = e.eyeLo; }
    c.setPose(pose, amt); if (c.settle) c.settle();
  }
  var _bx = V(), _by = V(), _bz = V(), _bm = new THREE.Matrix4();
  function place(e) { // on the ground: yaw only. Stuck to a surface: body up = surface normal, head along cling.f
    var r = e.c.root; r.position.set(e.x, e.y + (e.cling ? 0 : e.ryOff || 0), e.z);
    if (e.cling) { _by.fromArray(e.cling.n); _bz.fromArray(e.cling.f); _bx.crossVectors(_by, _bz); if (_bx.lengthSq() < 1e-6) _bx.set(1, 0, 0); _bx.normalize(); _bz.crossVectors(_bx, _by); _bm.makeBasis(_bx, _by, _bz); r.quaternion.setFromRotationMatrix(_bm); }
    else r.rotation.set(0, e.yaw, 0, 'YXZ');
  }
  function clearEnts() {
    G.ents.forEach(function (e) { scene.remove(e.c.root); e.c.dispose(); }); G.ents = []; G.decoys = [];
    G.shots.forEach(function (b) { if (b.m) scene.remove(b.m); }); G.shots = []; room.resetProps(); if (splats) { splats.count = 0; splatI = 0; } G.marks.forEach(function (m) { scene.remove(m); }); G.marks = [];
    G.confetti.forEach(function (p) { scene.remove(p.m); }); G.confetti = [];
    G.me = null; if (G.vm) { camera.remove(G.vm); scene.remove(camera); G.vm = null; }
  }
  function ent(id) { for (var i = 0; i < G.ents.length; i++) if (G.ents[i].id === id) return G.ents[i]; return null; }
  function cats() { return G.ents.filter(function (e) { return e.team === 'cat'; }); }

  function pushOut(x, z, r, y0, y1, out, qx, qz) { // a circle against the solids between two heights: moved out along the shortest way
    var P = room.platforms, hit = null;
    for (var i = 0; i < P.length; i++) { var p = P[i]; if (p.y1 <= y0 || p.y0 >= y1) continue; if (x < p.x0 - r || x > p.x1 + r || z < p.z0 - r || z > p.z1 + r) continue;
      var cx = x < p.x0 ? p.x0 : x > p.x1 ? p.x1 : x, cz = z < p.z0 ? p.z0 : z > p.z1 ? p.z1 : z, ex = x - cx, ez = z - cz, d2 = ex * ex + ez * ez;
      if (d2 >= r * r) continue; hit = p;
      if (d2 > 1e-10) { var d = Math.sqrt(d2), k = (r - d) / d; x += ex * k; z += ez * k; }
      else { // the centre itself is inside (a thin post entered in one step): go back out on the side it came from, never pop through to the far side
        var done = false; if (qx != null) { var bx = qx < p.x0 ? p.x0 : qx > p.x1 ? p.x1 : qx, bz = qz < p.z0 ? p.z0 : qz > p.z1 ? p.z1 : qz, fx2 = qx - bx, fz2 = qz - bz, fl = Math.hypot(fx2, fz2); if (fl > 1e-6) { x = bx + fx2 / fl * r; z = bz + fz2 / fl * r; done = true; } }
        if (!done) { var l = x - p.x0, rr = p.x1 - x, n = z - p.z0, f = p.z1 - z, m = Math.min(l, rr, n, f); if (m === l) x = p.x0 - r; else if (m === rr) x = p.x1 + r; else if (m === n) z = p.z0 - r; else z = p.z1 + r; } } }
    out[0] = x; out[1] = z; return hit;
  }
  var _po = [0, 0];
  function moveEnt(e, dx, dz, dt) {
    var r = e.rad, h = e.h || (e.team === 'dog' ? 0.62 : 0.3 * (e.size || 1)), y0 = e.y + e.step, y1 = e.y + h, hl = Math.max(0, (e.halfLen || r) - r), fx = Math.sin(e.yaw), fz = Math.cos(e.yaw);
    var dist = Math.hypot(dx, dz), n = Math.max(1, Math.ceil(dist / (r * 0.6))), sx = e.x, sz = e.z, hit = null, offs = hl > 0.01 ? [0, hl, -hl] : [0];
    for (var s = 0; s < n; s++) {
      var x = e.x + dx / n, z = e.z + dz / n;
      for (var it = 0; it < 3; it++) { var any = false; for (var q = 0; q < offs.length; q++) { var px = x + fx * offs[q], pz = z + fz * offs[q], hp = pushOut(px, pz, r, y0, y1, _po, e.x + fx * offs[q], e.z + fz * offs[q]); if (hp) { x += _po[0] - px; z += _po[1] - pz; hit = hp; any = true; } } if (!any) break; }
      // world edge, pond, the drop to the garden: the old point test, one axis at a time
      var wb = room.blocked(x, e.z, e.y, 0.05, e.step, 0.02); if (wb === true) { x = e.x; hit = hit || true; }
      wb = room.blocked(x, z, e.y, 0.05, e.step, 0.02); if (wb === true) { z = e.z; hit = hit || true; }
      e.x = x; e.z = z;
    }
    if (hit) { var gx = e.x - sx, gz = e.z - sz; if (Math.abs(dx) > 1e-6 && Math.abs(gx - dx) > Math.abs(dx) * 0.5) e.hitWallX = dx; if (Math.abs(dz) > 1e-6 && Math.abs(gz - dz) > Math.abs(dz) * 0.5) e.hitWallZ = dz; if (e.hitWallX || e.hitWallZ) e.hitPlat = hit; }
  }
  function physEnt(e, dt) {
    if (e.cling) return;
    var g = room.groundAt(e.x, e.z, e.y + e.step, e.rad * 0.4);
    if (e.y > g + 0.001 || e.vy > 0) {
      e.vy -= 9.8 * dt; e.y += e.vy * dt; e.air = true;
      if (e.y <= g && e.vy <= 0) { if (e.vy < -2) e.c.squash = 1; e.y = g; e.vy = 0; e.air = false; if (e === G.me) bus.emit('land'); }
    } else { if (g > e.y + 0.012) e.ryOff = (e.ryOff || 0) + e.y - g; /* stepping up: the collision height changes at once, the body you see rises over about a fifth of a second */ e.y = g; e.vy = 0; e.air = false; }
    if (e.ryOff) { e.ryV = e.ryV || { v: 0 }; e.ryOff = smoothDamp(e.ryOff, 0, e.ryV, 0.11, 10, dt); if (Math.abs(e.ryOff) < 0.0005) { e.ryOff = 0; e.ryV.v = 0; } }
    e.onVac = Math.abs(g - room.vac.top) < 1e-3 && Math.hypot(e.x - room.vac.x, e.z - room.vac.z) < 0.2 * SG.WS && !e.air;
  }

  /* ------------------------------------------------------------------ title */
  function toTitle() {
    G.lobby = null; if (lobbyMat) scene.remove(lobbyMat);
    clearEnts(); G.mode = 'title'; G.side = null; G.state = null; G.fly = null;
    var C = SG.CATS, Dg = SG.DOGS;
    spawn('t1', C.mochi, 'cat', { size: SG.WS, x: -0.55 * SG.WS, z: -0.25 * SG.WS, y: 0.38 * SG.WS, yaw: 0.35, pose: 'loaf' });
    var b = spawn('t2', C.soba, 'cat', { size: SG.WS, x: -1.8 * SG.WS, z: 1.3 * SG.WS, yaw: 0.7, pose: 'sit' });
    spawn('t3', C.wata, 'cat', { size: SG.WS, x: 0.57 * SG.WS, z: -0.25 * SG.WS, y: 0.12 * SG.WS, yaw: -0.6, pose: 'sit' });
    spawn('t4', C.dango, 'cat', { size: SG.WS, x: -0.75 * SG.WS, z: 1.75 * SG.WS, yaw: 0.9, pose: 'stretch' });
    spawn('t5', Dg.shiba, 'dog', { size: SG.WS, x: 2.15 * SG.WS, z: 1.5 * SG.WS, yaw: -0.75, pose: 'sit' }).c.wag = 1;
    spawn('t6', Dg.corgi, 'dog', { size: SG.WS, x: 1.35 * SG.WS, z: 1.95 * SG.WS, yaw: -0.5 });
    calico(b.c);
    G.cam.free = { p: V(0.0, 0.85 * SG.WS, 4.3 * SG.WS), t: V(0.0, 0.32 * SG.WS, 0.3 * SG.WS) };
    bus.emit('mode', { mode: 'title' });
  }
  /* a calico coat, as if a player had painted it (title screen) */
  function calico(c) {
    c.root.updateMatrixWorld(true); var inv = new THREE.Matrix4().copy(c.root.matrixWorld).invert().elements;
    c.eachTexel(function (x, y, z) {
      var lx = inv[0] * x + inv[4] * y + inv[8] * z + inv[12], ly = inv[1] * x + inv[5] * y + inv[9] * z + inv[13], lz = inv[2] * x + inv[6] * y + inv[10] * z + inv[14];
      var n = SG.vnoise(lx * 9 + 2.3, ly * 9, lz * 9), m = SG.vnoise(lx * 7 + 9.1, ly * 7 + 4, lz * 7);
      if (ly < 0.2) return null; return n > 0.6 ? [226, 138, 62] : m > 0.62 ? [58, 44, 38] : null;
    });
  }
  /* a few brush strokes so a cat on the title / paint shots shows what painting looks like */
  function demoPaint(c, n) {
    c.root.updateMatrixWorld(true);
    var cols = [[47, 75, 124], [200, 69, 46], [217, 169, 58], [122, 154, 84], [239, 230, 211]], r = SG.rng(5);
    c.parts.forEach(function (p, i) {
      if (r() < 0.45) return;
      var k = Math.floor(r() * p.samples.length / 3) * 3;
      tmp.set(p.samples[k], p.samples[k + 1], p.samples[k + 2]).applyMatrix4(p.mesh.matrixWorld);
      c.paint(tmp, 0.05 + r() * 0.07, cols[i % cols.length], 0.8, 0, 0.8);
    });
  }

  /* ------------------------------------------------------------------ round */
  var CAT_KEYS = Object.keys(SG.CATS), DOG_KEYS = Object.keys(SG.DOGS);
  function shuffled(a) { a = a.slice(); for (var i = a.length - 1; i > 0; i--) { var j = Math.floor(rnd() * (i + 1)), t = a[i]; a[i] = a[j]; a[j] = t; } return a; }
  G.settings = { mode: RULES.solo.mode, prep: RULES.solo.prepSec, seek: RULES.solo.seekSec, reveal: RULES.round.revealSec, dogs: 1, ammo: RULES.dog.startAmmo, breedEyes: false, paintAids: false, knockNoise: false, show: true, unlimited: true, forcedMeow: false, meowEvery: RULES.cat.forcedMeowSec, board: true, boardEvery: 30, night: false, map: 'home', fMono: false, fHorror: 0, fMosaic: 0 };
  G.pick = { cat: { breed: 'mochi', ear: '', tail: '' }, dog: { breed: 'shiba', ear: '', tail: '', collar: '' } };
  function specOf(team, o) { o = o || G.pick[team]; return SG.makeSpec((team === 'cat' ? SG.CATS : SG.DOGS)[o.breed], o); }
  G.specOf = specOf;
  function dogsOf() { return G.ents.filter(function (e) { return e.team === 'dog'; }); }
  /* the lobby: everyone walks about as a cat; whoever stands on the mat when the countdown ends enters the hunter lottery */
  var lobbyMat = null;
  G.enterLobby = function () {
    clearEnts(); G.mode = 'play'; G.roundT = 0; G.cam.free = null; G.fly = null; G.third = false; G.paint.on = false; G.paint.undo = []; G.decoyCd = 0; G.decoySlots = [{ cd: 0, e: null }, { cd: 0, e: null }]; G.viewLock = false; G.side = 'cat'; G.guide = 9;
    var WS = SG.WS, n = RULES.solo.botCatsWhenCat + RULES.solo.botDogsWhenCat, players = [{ id: 'you', team: 'cat' }], i;
    G.me = spawn('you', specOf('cat'), 'cat', { x: 0.2 * WS, z: 3.25 * WS, yaw: Math.PI / 2, name: '你', size: G.pick.cat.size || 1 });
    for (i = 0; i < n; i++) { var k = CAT_KEYS[i % CAT_KEYS.length]; spawn('lb' + i, SG.CATS[k], 'cat', { bot: true, x: (-3.4 + (i % 6) * 0.95) * WS, z: (2.95 + (i % 2) * 0.5 + (i > 5 ? 2.9 : 0)) * WS, y: i > 5 ? -0.3 * WS : 0, yaw: i * 1.7, name: SG.CATS[k].name + (i >= CAT_KEYS.length ? '二號' : ''), pose: ['sit', 'loaf', 'stand', 'stretch'][i % 4] }); players.push({ id: 'lb' + i, team: 'cat', bot: true }); }
    G.state = Core.createState(players, RULES, rnd, 'basic'); // stays in phase 'lobby' until the lottery is over
    G.lobby = { t: RULES.lobby.lotterySec, x: 3.3 * WS, z: 3.25 * WS, r: 0.62 * WS, n: n + 1, on: false };
    if (!lobbyMat) { var cv = document.createElement('canvas'); cv.width = cv.height = 512; var g = cv.getContext('2d'); g.fillStyle = '#2f6f6a'; g.fillRect(16, 16, 480, 480); g.strokeStyle = '#fff3d6'; g.lineWidth = 14; g.strokeRect(40, 40, 432, 432); g.fillStyle = '#fff3d6'; g.textAlign = 'center'; g.textBaseline = 'middle'; g.font = '84px SushiTC, sans-serif'; g.fillText('請站在', 256, 205); g.fillText('這裡', 256, 305);
      var tx = new THREE.CanvasTexture(cv); tx.colorSpace = THREE.SRGBColorSpace; lobbyMat = new THREE.Mesh(new THREE.CircleGeometry(1, 40), new THREE.MeshStandardMaterial({ map: tx, roughness: 0.9, transparent: true, polygonOffset: true, polygonOffsetFactor: -4 })); lobbyMat.rotation.x = -Math.PI / 2; lobbyMat.rotation.z = Math.PI / 2; }
    lobbyMat.scale.setScalar(G.lobby.r); lobbyMat.position.set(G.lobby.x, room.groundAt(G.lobby.x, G.lobby.z, 1, 0) + 0.012, G.lobby.z); scene.add(lobbyMat);
    room.setNight(false); G.cam.yaw = -Math.PI / 2; G.cam.pitch = 0.3; G.cam.dist = 3.0;
    bus.emit('mode', { mode: 'play', side: 'cat', lobby: true, breed: G.pick.cat.breed, gameMode: G.settings.mode });
  };
  G.setBody = function (breed, size) { // body picker in the lobby: build and size
    G.pick.cat.breed = breed; G.pick.cat.size = size; var m = G.me; if (!G.lobby || !m) return;
    var o = { x: m.x, y: m.y, z: m.z, yaw: m.yaw, name: '你', size: size }; scene.remove(m.c.root); m.c.dispose(); G.ents.splice(G.ents.indexOf(m), 1); m.ghost = null; G.seeThrough = false; G.me = spawn('you', specOf('cat'), 'cat', o); bus.emit('body', { breed: breed, size: size });
  };
  G.start = function (side, breed) {
    G.lobby = null; if (lobbyMat) scene.remove(lobbyMat);
    clearEnts(); G.mode = 'play'; G.roundT = 0; G.cam.free = null; G.fly = null; G.liked = false; G.likes = {}; G.seeThrough = true; G.cam.kk = null; G.cam.t3 = null; G.cam.look = null; G.third = false; G.paint.on = false; G.moved = 0; G.guide = 0; G.paint.undo = []; G.decoyCd = 0; G.decoySlots = [{ cd: 0, e: null }, { cd: 0, e: null }]; G.embedT = 0;
    var WS = SG.WS, S = G.settings, mode = S.mode, players = [], nd = Math.max(1, Math.min(3, S.dogs || (side === 'cat' && mode !== 'double' ? RULES.solo.botDogsWhenCat : RULES.solo.botDogsWhenDog + 1)));
    RULES.round.prepSec = S.prep; RULES.round.seekSec = S.seek; RULES.round.revealSec = S.reveal; RULES.dog.startAmmo = S.ammo; RULES.dog.unlimited = !!S.unlimited;
    if (mode === 'double') side = 'cat';
    if (breed) G.pick[side].breed = breed;
    function botCats(n, skip) { var pool = shuffled(CAT_KEYS.filter(function (k) { return k !== skip; })); while (pool.length < n) pool = pool.concat(shuffled(CAT_KEYS)); pool.slice(0, n).forEach(function (k, i) { var id = (mode === 'double' ? 'p' : 'cat') + i; var O = SG.CRITTER_OPTIONS.cat, sp = SG.makeSpec(SG.CATS[k], { ear: O.ear[Math.floor(rnd() * O.ear.length)][0], tail: O.tail[Math.floor(rnd() * O.tail.length)][0] }); spawn(id, sp, 'cat', { bot: true, name: SG.CATS[k].name + (i >= CAT_KEYS.length - 1 ? '二號' : '') }); players.push({ id: id, team: mode === 'double' ? undefined : 'cat', bot: true }); }); }
    function botDogs(n, from) { shuffled(DOG_KEYS).slice(0, n).forEach(function (k, i) { var id = 'dog' + (from + i), w0 = (from + i) ? ((from + i) * 19 + 3) % room.route.length : 0, w = room.route[w0]; var d = spawn(id, SG.DOGS[k], 'dog', { bot: true, x: (from + i) ? w[0] : -5.6 * WS, z: (from + i) ? w[1] : 2.0 * WS, yaw: Math.PI, breed: k }); d.wp0 = w0; players.push({ id: id, team: 'dog', bot: true }); }); }
    if (side === 'cat') {
      G.me = spawn('you', specOf('cat'), 'cat', { x: 0.4 * WS, z: 1.6 * WS, yaw: Math.PI, name: '你', size: G.pick.cat.size || 1 }); players.push({ id: 'you', team: mode === 'double' ? undefined : 'cat' });
      botCats(mode === 'double' ? 3 : RULES.solo.botCatsWhenCat, G.pick.cat.breed); if (mode !== 'double') botDogs(nd, 0);
      G.cam.yaw = 0; G.cam.pitch = 0.62; G.cam.dist = 1.7; // flat bodies: closer and from a little above, so the big top surface (the main canvas) is in view
    } else {
      G.me = spawn('you', specOf('dog'), 'dog', { x: -5.6 * WS, z: 1.3 * WS, yaw: Math.PI / 2, name: '你', breed: G.pick.dog.breed }); G.me.pitch = 0; players.push({ id: 'you', team: 'dog' });
      botCats(RULES.solo.botCatsWhenDog); botDogs(nd - 1, 1); buildLauncher();
    }
    G.dogSpawn = [-5.6 * WS, 1.6 * WS]; G.side = side; hideBots();
    if (G.me.team === 'cat') G.ents.forEach(function (e) { if (e !== G.me) e.c.root.visible = false; }); // while hiding you cannot see the others (original rule)
    G.state = Core.createState(players, RULES, rnd, mode);
    room.setNight(!!S.night); G.meowT = S.meowEvery;
    dispatch({ type: 'start' });
    bus.emit('mode', { mode: 'play', side: side, breed: G.pick[side].breed, gameMode: mode });
  };
  function dispatch(a) {
    var r = Core.apply(G.state, a, RULES); G.state = r.state;
    for (var i = 0; i < r.events.length; i++) onEvent(r.events[i]);
    return r;
  }
  G.dispatch = dispatch;
  function startAI(d) { d.ai = { wp: d.wp0 || 0, wait: 0, mode: 'patrol', look: 0, sus: {} }; }
  /* a player who becomes a hunter mid-round (infection) or at the start of the hunt (double) gets a dog body */
  function makeHunter(pid, x, y, z, yaw) {
    var human = pid === 'you', k = human ? G.pick.dog.breed : DOG_KEYS[Math.floor(rnd() * DOG_KEYS.length)], body = ent(pid);
    var d = spawn(pid + '#h', human ? specOf('dog') : SG.DOGS[k], 'dog', { bot: !human, x: x, y: y, z: z, yaw: yaw, breed: k, pid: pid, name: body ? body.name : pid });
    if (human) { G.me = d; d.pitch = 0; G.fly = null; G.paint.on = false; G.third = false; buildLauncher(); bus.emit('paintmode', { on: false }); bus.emit('role', { team: 'dog' }); }
    else { var best = 0, bd = 1e9; room.route.forEach(function (w, i) { var dd = Math.hypot(w[0] - x, w[1] - z); if (dd < bd) { bd = dd; best = i; } }); d.wp0 = best; startAI(d); }
    return d;
  }
  var VANISH = 0.45;
  function stepVanish(dt) { // found bodies shrink away in under half a second
    var L = G.ents.concat(G.decoys); for (var i = 0; i < L.length; i++) { var e = L[i]; if (!(e.vanish > 0)) continue; e.vanish -= dt; var k = Math.max(0, e.vanish / VANISH); e.c.root.scale.setScalar(e.c.scale * (0.12 + 0.88 * k * k));
      if (e.vanish <= 0) { e.c.root.visible = false; e.c.root.scale.setScalar(e.c.scale); e.gone = true; if (e.shell) e.shell.visible = false; } }
  }
  function onEvent(ev) {
    var st = G.state, c;
    if (ev.type === 'phase') {
      if (ev.phase === 'seek') {
        G.cam.free = null; G.ents.forEach(function (e) { e.c.root.visible = true; });
        if (st.mode === 'double') st.order.forEach(function (id, i) { var b = ent(id); b.c.frozen = true; b.speed = 0; var w = [[-5.6, 1.3], [-5.3, -1.0], [0, 3.3], [3.5, 3.3]][i % 4]; makeHunter(id, w[0], 0, w[1], i ? 0 : Math.PI / 2); });
        dogsOf().forEach(function (d) { if (d.bot && !d.ai) startAI(d); });
      }
      if (ev.phase === 'reveal') enterReveal();
      if (ev.phase === 'lobby') { toTitle(); }
    }
    if (ev.type === 'out') { // the original (patch notes 1.8.0 / 2.3.0): a hider who is shot disappears from the map at once, with all their clones
      c = ent(ev.cat);
      if (c) {
        var bodies = [c].concat(G.decoys.filter(function (dd) { return dd.decoyOf === c.id && dd.c.root.visible; })), hitB = G.lastHit && bodies.indexOf(G.lastHit) >= 0 ? G.lastHit : c;
        c.found = true; burst(hitB);
        // Double (single source): the body that was found stays for the other hunters, the player's other bodies go
        bodies.forEach(function (bd) { if (st.mode === 'double' && bd === hitB) return; bd.vanish = VANISH; });
        if (st.mode !== 'double') {
          if (c === G.me && st.mode === 'basic' && !G.fly) { var cd = V(); camera.getWorldDirection(cd); G.fly = { p: camera.position.clone(), yaw: Math.atan2(cd.x, cd.z), pitch: Math.asin(cd.y) }; G.paint.on = false; bus.emit('paintmode', { on: false }); bus.emit('spectate'); }
          c.out = true; c.speed = 0; // it keeps its pose and paint: the answer check shows it again exactly where it hid
        }
        bus.emit('found', { cat: c.id, by: ev.by || G.lastShooter || null, name: c.name });
      }
    }
    if (ev.type === 'infected') { c = ent(ev.cat); if (c) { var hs = G.dogSpawn || [c.x, c.z]; makeHunter(c.id, hs[0] + (rnd() - 0.5) * 0.8, room.groundAt(hs[0], hs[1], 0.4, 0), hs[1] + (rnd() - 0.5) * 0.8, Math.PI / 2); } } // comes back as a hunter at the hunters' entry point
    bus.emit(ev.type, ev);
  }
  /* bots choose a spot, strike a pose and camouflage themselves */
  /* places under furniture where a flat body fits: a solid whose underside is 13-45 cm above the floor */
  var underSpots = null;
  function findUnder() {
    var P = room.platforms, out = [];
    for (var i = 0; i < P.length; i++) { var p = P[i], w = p.x1 - p.x0, d = p.z1 - p.z0; if (p.wall || w < 0.5 || d < 0.5 || w > 4 || d > 4) continue; var cx = (p.x0 + p.x1) / 2, cz = (p.z0 + p.z1) / 2, g = room.groundAt(cx, cz, p.y0 - 0.01, 0), gap = p.y0 - g;
      if (gap < 0.13 || gap > 0.45 || g > 0.5) continue;
      for (var t = 0; t < 3; t++) { var x = p.x0 + 0.22 + rnd() * Math.max(0, w - 0.44), z = p.z0 + 0.22 + rnd() * Math.max(0, d - 0.44); if (room.groundAt(x, z, p.y0 - 0.01, 0) !== g) continue; if (pushOut(x, z, 0.2, g + 0.03, g + Math.min(gap - 0.02, 0.12), _po)) continue; out.push([x, z, rnd() * 6.28, ['pancake', 'stand', 'loaf', 'side'][Math.floor(rnd() * 4)], g, gap]); break; } }
    return out;
  }
  G.underSpots = function () { return underSpots || (underSpots = findUnder()); };
  function hideBots() {
    var spots = room.spots.slice(), under = shuffled(G.underSpots()).slice(0, 4); spots = spots.concat(under);
    var bots = cats().filter(function (e) { return e.bot; });
    bots.forEach(function (e, bi) {
      e.cling = null; var i = bi % 3 === 2 && under.length ? spots.indexOf(under.pop()) : Math.floor(rnd() * spots.length), s = spots.splice(i < 0 ? 0 : i, 1)[0]; // every third bot slides under a piece of furniture
      e.x = s[0]; e.z = s[1]; e.yaw = s[2]; e.y = s[4]; e.c.setPose(s[3]); e.c.frozen = true; place(e);
      if (bi % 2 === 1 && stickSomewhere(e, rnd)) { e.c.setPose(['pancake', 'stand', 'loaf', 'bolster', 'sphinx'][Math.floor(rnd() * 5)]); place(e); } // a third of the bots hide on walls, pillars and ceilings
      for (var k = 0; k < 30; k++) e.c.update(0.05, rnd);
      e.c.root.updateMatrixWorld(true);
    });
    bots.forEach(function (e, i) { e.skill = i % 4 === 3 ? 0.45 + rnd() * 0.2 : 0.8 + rnd() * 0.2; camoAllSides(e, e.skill); }); // every fourth bot is a sloppy painter, so finds come at different speeds
  }
  /* camouflage that holds from several viewpoints: capture the surroundings on all six sides from the cat's position,
     then give every texel the colour that lies behind the cat for someone looking at that texel head-on */
  var orthoCam = new THREE.OrthographicCamera(-0.42, 0.42, 0.42, -0.42, 0, 40), camoViews = [], camoBlur = new Uint8Array(40 * 40 * 4);
  function camoAllSides(e, quality) {
    var c = e.c, ctr = c.center(V()), N = 40, k, r = SG.rng(e.id.length * 31 + 7), NV = 9;
    var pitch = Math.atan2(RULES.dog.eyeHeightDefault - ctr.y, 2.2), cp = Math.cos(pitch), sp = Math.sin(pitch); // seekers look from dog eye height, about two metres away
    c.root.visible = false;
    for (k = 0; k < NV; k++) { // eight seekers around the cat and one looking straight down; each sees (orthographically) what lies behind the cat
      var a = k * Math.PI / 4, d = k < 8 ? [Math.cos(a) * cp, -sp, Math.sin(a) * cp] : [0, -1, 0];
      orthoCam.position.copy(ctr); orthoCam.up.set(0, k < 8 ? 1 : 0, k < 8 ? 0 : 1); orthoCam.lookAt(ctr.x + d[0], ctr.y + d[1], ctr.z + d[2]); orthoCam.updateMatrixWorld(true);
      camoViews[k] = { d: d, px: post.renderAlbedo(scene, orthoCam, N, N, (camoViews[k] && camoViews[k].px) || new Uint8Array(N * N * 4)), m: new THREE.Matrix4().multiplyMatrices(orthoCam.projectionMatrix, orthoCam.matrixWorldInverse).elements };
    }
    c.root.visible = true;
    for (k = 0; k < NV; k++) { // soften: a thin dark post painted sharply onto the body is wrong for every seeker who is not exactly on that line
      var src = camoViews[k].px, dst = camoBlur, B = 2, i, j, a2, b2, n, sr, sg, sb, o2;
      for (j = 0; j < N; j++) for (i = 0; i < N; i++) { n = sr = sg = sb = 0; for (b2 = Math.max(0, j - B); b2 <= Math.min(N - 1, j + B); b2++) for (a2 = Math.max(0, i - B); a2 <= Math.min(N - 1, i + B); a2++) { o2 = (b2 * N + a2) * 4; sr += src[o2]; sg += src[o2 + 1]; sb += src[o2 + 2]; n++; } o2 = (j * N + i) * 4; dst[o2] = sr / n; dst[o2 + 1] = sg / n; dst[o2 + 2] = sb / n; }
      src.set(dst);
    }
    // which way a texel faces: the body is a flat slab, so the direction from the centre is scaled by the slab's own half sizes (an ellipsoid's normal)
    c.root.updateMatrixWorld(true); var ms = c.measure ? c.measure() : null, bq = c.root.quaternion, ax = V(1, 0, 0).applyQuaternion(bq), ay = V(0, 1, 0).applyQuaternion(bq), az = V(0, 0, 1).applyQuaternion(bq), hx2 = 1, hy2 = 1, hz2 = 1, bc = ctr.clone();
    if (ms) { hx2 = Math.pow(Math.max(0.03, ms.size[0] / 2), 2); hy2 = Math.pow(Math.max(0.03, ms.size[1] / 2), 2); hz2 = Math.pow(Math.max(0.03, ms.size[2] / 2), 2); bc.copy(c.root.position).addScaledVector(ax, (ms.min[0] + ms.max[0]) / 2).addScaledVector(ay, (ms.min[1] + ms.max[1]) / 2).addScaledVector(az, (ms.min[2] + ms.max[2]) / 2); }
    c.eachTexel(function (x, y, z) {
      var qx = x - bc.x, qy = y - bc.y, qz = z - bc.z, lx = (qx * ax.x + qy * ax.y + qz * ax.z) / hx2, ly = (qx * ay.x + qy * ay.y + qz * ay.z) / hy2, lz = (qx * az.x + qy * az.y + qz * az.z) / hz2;
      var nx = ax.x * lx + ay.x * ly + az.x * lz, ny = ax.y * lx + ay.y * ly + az.y * lz, nz = ax.z * lx + ay.z * ly + az.z * lz, l = Math.sqrt(nx * nx + ny * ny + nz * nz) || 1, R0 = 0, G0 = 0, B0 = 0, W = 0, best = -2, bk = 0; nx /= l; ny /= l; nz /= l;
      for (var k = 0; k < NV; k++) { // each texel takes its colour from the seekers who would see it most head-on
        var F = camoViews[k], dt = -(nx * F.d[0] + ny * F.d[1] + nz * F.d[2]); if (dt > best) { best = dt; bk = k; } if (dt <= 0.2) continue;
        var w = dt * dt * dt * dt * dt * dt, m = F.m, sx = m[0] * x + m[4] * y + m[8] * z + m[12], sy = m[1] * x + m[5] * y + m[9] * z + m[13];
        var ix = Math.max(0, Math.min(N - 1, Math.floor((sx * 0.5 + 0.5) * N))), iy = Math.max(0, Math.min(N - 1, Math.floor((sy * 0.5 + 0.5) * N))), o = (iy * N + ix) * 4;
        R0 += F.px[o] * w; G0 += F.px[o + 1] * w; B0 += F.px[o + 2] * w; W += w;
      }
      if (!W) { var F2 = camoViews[bk], m2 = F2.m, o3 = (Math.max(0, Math.min(N - 1, Math.floor(((m2[1] * x + m2[5] * y + m2[9] * z + m2[13]) * 0.5 + 0.5) * N))) * N + Math.max(0, Math.min(N - 1, Math.floor(((m2[0] * x + m2[4] * y + m2[8] * z + m2[12]) * 0.5 + 0.5) * N)))) * 4; return [F2.px[o3], F2.px[o3 + 1], F2.px[o3 + 2]]; }
      return [R0 / W, G0 / W, B0 / W];
    });
    if (quality < 1 && ms) { // a sloppy painter leaves white patches, mostly on the big top surface
      var nb = Math.round((1 - quality) * 9) + (quality < 0.7 ? 2 : 0);
      for (var bi = 0; bi < nb; bi++) { var ux = (r() * 2 - 1) * ms.size[0] * 0.42, uz = (r() * 2 - 1) * ms.size[2] * 0.42, top = r() < 0.75; tmp.copy(bc).addScaledVector(ax, ux).addScaledVector(az, uz).addScaledVector(ay, top ? ms.size[1] * 0.45 : (r() - 0.5) * ms.size[1] * 0.6); c.paint(tmp, (0.035 + r() * 0.04) * (quality < 0.7 ? 1.7 : 1), [250, 250, 248], 0.82, 0, 0.6); } }
  }
  G.camoAllSides = camoAllSides;
  /* projection camouflage: render the albedo of the scene behind the cat from a seeker's eye and write it into the cat's texture */
  var camoCam = new THREE.PerspectiveCamera(30, 1, 0.05, 60);
  function autoCamoNote() { /* single-viewpoint projection (used for the demo shots; bots use camoAllSides) */ }
  function autoCamo(e, quality, eye) {
    var c = e.c, ctr = c.center(V());
    eye = eye || V(ctr.x * 0.35, 0.6 + ctr.y * 0.3, ctr.z * 0.35 + 0.4);
    if (eye.distanceTo(ctr) < 1.6) eye.add(V().subVectors(eye, ctr).setY(0).normalize().multiplyScalar(1.6));
    var d = eye.distanceTo(ctr), N = 384;
    camoCam.fov = 2 * Math.atan(0.75 / d) * 180 / Math.PI; camoCam.position.copy(eye); camoCam.lookAt(ctr); camoCam.updateProjectionMatrix(); camoCam.updateMatrixWorld(true);
    c.root.visible = false; var px = post.renderAlbedo(scene, camoCam, N, N); c.root.visible = true;
    var m = new THREE.Matrix4().multiplyMatrices(camoCam.projectionMatrix, camoCam.matrixWorldInverse).elements, r = SG.rng(e.id.length * 31 + 3);
    c.eachTexel(function (x, y, z) {
      var w = m[3] * x + m[7] * y + m[11] * z + m[15], sx = (m[0] * x + m[4] * y + m[8] * z + m[12]) / w, sy = (m[1] * x + m[5] * y + m[9] * z + m[13]) / w;
      var ix = Math.max(0, Math.min(N - 1, Math.round((sx * 0.5 + 0.5) * N))), iy = Math.max(0, Math.min(N - 1, Math.round((sy * 0.5 + 0.5) * N))), o = (iy * N + ix) * 4;
      return [px[o], px[o + 1], px[o + 2]];
    });
    // bots are not perfect painters: leave some white patches depending on skill
    if (quality < 1) { c.root.updateMatrixWorld(true); c.parts.forEach(function (p) { if (r() > quality) { var k = Math.floor(r() * p.samples.length / 3) * 3; tmp.set(p.samples[k], p.samples[k + 1], p.samples[k + 2]).applyMatrix4(p.mesh.matrixWorld); c.paint(tmp, 0.04 + r() * 0.04, [250, 250, 248], 0.82, 0, 0.6); } }); }
  }
  G.autoCamo = autoCamo;

  /* how different does a cat look from what is behind it, seen from `eye`? 0 = invisible. Uses two tiny albedo renders, so occlusion counts. */
  var misA = new Uint8Array(40 * 40 * 4), misB = new Uint8Array(40 * 40 * 4);
  function mismatch(e, eye) {
    var ctr = e.c.center(V()), d = eye.distanceTo(ctr), N = 40;
    camoCam.fov = 2 * Math.atan(0.55 / d) * 180 / Math.PI; camoCam.position.copy(eye); camoCam.lookAt(ctr); camoCam.updateProjectionMatrix(); camoCam.updateMatrixWorld(true);
    var hide = G.ents.filter(function (o) { return o.team === 'dog'; });
    hide.forEach(function (o) { o.c.root.visible = false; });
    var fv0 = e.c.faceSkin.visible; if (e.c.pose !== 'stand') e.c.faceSkin.visible = false; // the seeker does not get to see a posed cat's face
    post.renderAlbedo(scene, camoCam, N, N, misA); e.c.faceSkin.visible = fv0;
    e.c.root.visible = false; post.renderAlbedo(scene, camoCam, N, N, misB); e.c.root.visible = true;
    hide.forEach(function (o) { o.c.root.visible = !o.fp; });
    var sum = 0, cnt = 0;
    for (var i = 0; i < misA.length; i += 4) { var df = (Math.abs(misA[i] - misB[i]) + Math.abs(misA[i + 1] - misB[i + 1]) + Math.abs(misA[i + 2] - misB[i + 2])) / 765; sum += df; if (df > 0.012) cnt++; }
    return { m: sum / (N * N * 0.3), visible: cnt / (N * N) };
  }
  G.mismatch = mismatch;
  /* fraction of a seeker's screen each cat actually covers, counted in pixels of an ID render (so furniture in front counts as hidden) */
  var idMats = [], AW = 192, AH = 108, idPx = new Uint8Array(AW * AH * 4), areaCam = new THREE.PerspectiveCamera(50, 16 / 9, 0.05, 60);
  function visibleAreas(cam) {
    var list = cats().concat(G.decoys).filter(function (c) { return c.c.root.visible; }), saved = [], out = {}, cnt = [], i;
    list.forEach(function (c, k) { if (!idMats[k]) idMats[k] = new THREE.MeshBasicMaterial({ color: new THREE.Color().setRGB(1, (8 + 16 * k) / 255, 1) }); saved.push(c.c.skin.material); c.c.skin.material = idMats[k]; c.fv = c.c.faceSkin.visible; c.c.faceSkin.visible = false; cnt.push(0); });
    post.renderAlbedo(scene, cam, AW, AH, idPx, 'raw');
    list.forEach(function (c, k) { c.c.skin.material = saved[k]; c.c.faceSkin.visible = c.fv && !c.c.blank; });
    for (i = 0; i < idPx.length; i += 4) if (idPx[i] > 250 && idPx[i + 2] > 250 && idPx[i + 1] < 8 + 16 * list.length) { var k2 = Math.round((idPx[i + 1] - 8) / 16); if (k2 >= 0 && k2 < cnt.length) cnt[k2]++; }
    list.forEach(function (c, k) { out[c.id] = cnt[k] / (AW * AH); });
    return out;
  }
  G.visibleAreas = visibleAreas;
  /* THE mechanic: every tick, each hider that is really visible (pixels of an ID render) inside this hunter's view scores.
     45 when the hunter looks straight at it from close by, less toward the screen edge and with distance (numbers in rules.json). */
  function overlookTick(d, cam) {
    var st = G.state, pid = d.pid, dbl = st.mode === 'double', areas = visibleAreas(cam);
    cats().concat(G.decoys).forEach(function (c) { // a clone that goes unnoticed scores for its owner too
      if (!c.c.root.visible || c.id === pid || c.decoyOf === pid || (!dbl && c.out)) return; var a = areas[c.id] || 0; if (a <= 0) return; c.seenT = G.simT;
      var ctr = c.c.center(tmp2), dist = cam.position.distanceTo(ctr); tmp.copy(ctr).project(cam);
      dispatch({ type: 'overlook', cat: c.decoyOf || c.id, by: pid, area: a, centre: Math.min(1, Math.hypot(tmp.x, tmp.y)), dist: dist, speed: c.speed || 0 });
    });
    return areas;
  }
  G.overlookTick = overlookTick;
  /* a bot cat that nobody is looking at sometimes gets up, walks a few metres along the walking grid, and hides again */
  function botRelocate(dt) {
    var st = G.state; if (!st || st.phase !== 'seek' || st.mode === 'double') return;
    cats().forEach(function (c) {
      if (!c.bot || c.out || c.decoyOf) return; var RL = RULES.bot.relocateEverySec;
      if (c.reloT == null) c.reloT = RL[0] + rnd() * (RL[1] - RL[0]);
      if (c.walk) { // on the way
        var pt = c.walk.path[c.walk.i], dx = pt[0] - c.x, dz = pt[1] - c.z, l = Math.hypot(dx, dz), px = c.x, pz = c.z;
        if (l < 0.25) { c.walk.i++; if (c.walk.i >= c.walk.path.length) { c.walk = null; c.speed = 0; c.c.setPose(['loaf', 'sit', 'curl', 'sphinx'][Math.floor(rnd() * 4)]); if (rnd() < 0.4) stickSomewhere(c, rnd); place(c); for (var k = 0; k < 20; k++) c.c.update(0.05, rnd); c.c.root.updateMatrixWorld(true); camoAllSides(c, c.skill || 0.9); bus.emit('relocated', { id: c.id }); } return; }
        moveEnt(c, dx / l * RULES.cat.walkSpeed * dt, dz / l * RULES.cat.walkSpeed * dt, dt); c.yaw = turn(c.yaw, Math.atan2(dx, dz), dt * 10); c.speed = Math.hypot(c.x - px, c.z - pz) / dt; if (c.speed < 0.2 && (c.walk.stuck = (c.walk.stuck || 0) + dt) > 1) c.walk.i = c.walk.path.length - 1, c.walk.path[c.walk.i] = [c.x, c.z];
        return; }
      c.reloT -= dt; if (c.reloT > 0) return; c.reloT = RL[0] + rnd() * (RL[1] - RL[0]);
      if (G.simT - (c.seenT || -99) < 6) return; // somebody had it on screen a moment ago: stay put
      if (dogsOf().some(function (d) { return Math.hypot(d.x - c.x, d.z - c.z) < 7; })) return;
      if (c.cling) release(c); var a = rnd() * 6.283, r = 2.5 + rnd() * 3.5, path = navPath(c.x, c.z, c.x + Math.cos(a) * r, c.z + Math.sin(a) * r); if (!path || path.length < 4 || path.length > 40) return;
      c.walk = { path: path, i: 0 }; c.c.frozen = false; c.c.setPose('stand'); bus.emit('relocating', { id: c.id });
    });
  }
  function dogCam(d) { areaCam.position.set(d.x, d.y + d.eyeH, d.z); areaCam.lookAt(d.x + Math.sin(d.yaw), d.y + d.eyeH + (d.pitch || 0), d.z + Math.cos(d.yaw)); areaCam.updateMatrixWorld(true); return areaCam; }

  /* ------------------------------------------------------------------ shooting */
  /* paint pellets leave splats that stay (one instanced mesh), and mark the cats they hit */
  var SPLAT_N = 1800, splats = null, splatI = 0, _m4 = new THREE.Matrix4(), _qq = new THREE.Quaternion(), _zz = V(0, 0, 1), _sc = V(), _col = new THREE.Color();
  function splatMesh() {
    if (splats) return splats;
    var g = new THREE.CircleGeometry(1, 11), p = g.attributes.position, r = SG.rng(77);
    for (var i = 1; i < p.count; i++) { var k = 0.62 + r() * 0.55; p.setXY(i, p.getX(i) * k, p.getY(i) * k); }
    splats = new THREE.InstancedMesh(g, new THREE.MeshStandardMaterial({ roughness: 0.25, polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2 }), SPLAT_N);
    splats.count = 0; splats.frustumCulled = false; splats.receiveShadow = true; scene.add(splats); return splats;
  }
  function addSplat(pos, n, size, rgb) {
    var m = splatMesh(), i = splatI % SPLAT_N; splatI++;
    _qq.setFromUnitVectors(_zz, n); _qq.multiply(new THREE.Quaternion().setFromAxisAngle(_zz, rnd() * 6.28)); _sc.set(size, size * (0.7 + rnd() * 0.5), 1);
    _m4.compose(tmp.copy(pos).addScaledVector(n, 0.004), _qq, _sc); m.setMatrixAt(i, _m4); m.setColorAt(i, _col.setRGB(rgb[0] / 255, rgb[1] / 255, rgb[2] / 255, THREE.SRGBColorSpace));
    m.count = Math.min(SPLAT_N, splatI); m.instanceMatrix.needsUpdate = true; if (m.instanceColor) m.instanceColor.needsUpdate = true;
  }
  var PAINTS = [[74, 163, 224], [242, 154, 74], [231, 110, 150], [150, 200, 90]];
  /* one shot = a small spread of paint pellets. Returns false if the rules refused it (cooldown, no ammo). */
  function fire(dogEnt, origin, dir) {
    var now = G.simT, pid = dogEnt.pid || dogEnt.id, p = G.state.players[pid], dbl = G.state.mode === 'double';
    if (!p || G.state.phase !== 'seek' || (p.ammo <= 0 && !RULES.dog.unlimited) || now - p.lastShot < RULES.dog.shotIntervalSec) { if (dogEnt === G.me && p && G.state.phase === 'seek') bus.emit('dryfire'); return false; }
    var rgb = PAINTS[(G.state.order.indexOf(pid) + 4) % 4], N = RULES.dog.pellets, sp = RULES.dog.spreadRad;
    ray.set(origin, dir); ray.far = RULES.dog.range; ray.layers.set(0);
    var wh = ray.intersectObjects([room.batched, room.dyn], true)[0], wd = wh ? wh.distance : RULES.dog.range;
    var wn = wh && wh.face ? wh.face.normal.clone().transformDirection(wh.object.matrixWorld) : dir.clone().negate(), wp = wh ? wh.point.clone() : null;
    var targets = cats().concat(G.decoys).filter(function (c) { return (!c.out || dbl) && c.c.root.visible && c.id !== pid && c.decoyOf !== pid; });
    var right = V().crossVectors(dir, V(0, 1, 0)).normalize(), upv = V().crossVectors(right, dir), best = null, bestN = 0, hits = {}, d = V();
    for (var i = 0; i < N; i++) {
      var a = i ? i / (N - 1) * 6.283 : 0, rr = i ? sp * (0.45 + 0.55 * rnd()) : 0;
      d.copy(dir).addScaledVector(right, Math.cos(a) * rr).addScaledVector(upv, Math.sin(a) * rr).normalize();
      // where this pellet meets the surface the centre ray hit (cheap stand-in for a full raycast per pellet)
      var pd = wd; if (wp) { var den = d.dot(wn); if (den < -0.05) pd = Math.min(wd * 1.6, wp.clone().sub(origin).dot(wn) / den); }
      ray.set(origin, d); var hc = null, hd = pd, hp = null;
      targets.forEach(function (c) { ray.far = hd; var h = c.c.raycast(ray); if (h && h.distance < hd) { hd = h.distance; hc = c; hp = h.point; } });
      if (hc) { hits[hc.id] = (hits[hc.id] || 0) + 1; if (hits[hc.id] > bestN) { bestN = hits[hc.id]; best = hc; } hc.c.paint(hp, 0.06 + rnd() * 0.05, rgb, 0.25, 0, 0.85); } // paint mark on whoever was hit
      else if (wp && pd < RULES.dog.range) { addSplat(tmp2.copy(origin).addScaledVector(d, pd), wn, 0.09 + rnd() * 0.12, rgb); for (var sd = 0; sd < 2; sd++) addSplat(tmp.copy(tmp2).add(V((rnd() - 0.5) * 0.36, (rnd() - 0.75) * 0.4, (rnd() - 0.5) * 0.36)), wn, 0.02 + rnd() * 0.035, rgb); if (i < 5) puff(tmp2, wn, rgb); if (i === 0) room.kick(tmp2.x, tmp2.y, tmp2.z, dir.x, dir.z, 2.2); }
      if (!hc && G.me && G.me.team === 'cat' && !G.me.out && dogEnt !== G.me) { var mc = G.me.c.center(tmp), t0 = Math.max(0, Math.min(pd, mc.clone().sub(origin).dot(d))); if (mc.distanceTo(tmp2.copy(origin).addScaledVector(d, t0)) < RULES.feel.nearMissPelletM) G.nearPellet = true; }
    }
    var target = best ? (best.decoyOf ? ent(best.decoyOf) : best) : null, fleeing = false;
    if (!best) cats().forEach(function (c) { if (!c.out && c.c.root.visible && c.speed > RULES.dog.fleeingSpeed) { var to = tmp.subVectors(c.c.center(tmp2), origin); if (to.normalize().dot(dir) > 0.96) fleeing = true; } });
    G.shots.push({ o: origin.clone(), d: dir.clone(), dist: best ? origin.distanceTo(best.c.center(tmp)) : wd, t: 0, rgb: rgb });
    bus.emit('blast', { me: dogEnt === G.me, x: dogEnt.x, z: dogEnt.z });
    G.lastHit = best; G.lastShooter = pid; dispatch({ type: 'shoot', dog: pid, now: now, hit: target ? target.id : null, fleeing: fleeing, decoy: !!(best && best.decoyOf) }); G.lastHit = null;
    if (target) G.hitstop = 0.11;
    if (G.nearPellet) { G.nearPellet = false; if (!target || target !== G.me) bus.emit('nearmiss', { kind: 'pellet' }); }
    return true;
  }
  G.fire = fire;
  /* pellet tracers: short streaks that fly to the impact point */
  var tracerGeo = new THREE.CylinderGeometry(0.012, 0.012, 1, 5).rotateX(Math.PI / 2), tracers = [];
  function stepBalls(dt) {
    for (var i = G.shots.length - 1; i >= 0; i--) {
      var b = G.shots[i]; if (b.done) continue;
      if (!b.m) { b.m = new THREE.Mesh(tracerGeo, new THREE.MeshBasicMaterial({ color: new THREE.Color().setRGB(b.rgb[0] / 255, b.rgb[1] / 255, b.rgb[2] / 255, THREE.SRGBColorSpace) })); b.m.layers.set(1); scene.add(b.m); }
      b.t += dt; var d = Math.min(b.dist, b.t * RULES.dog.pelletSpeed), len = Math.min(1.2, d);
      b.m.position.copy(b.o).addScaledVector(b.d, d - len / 2); b.m.lookAt(tmp.copy(b.m.position).add(b.d)); b.m.scale.set(1, 1, Math.max(0.05, len));
      if (d >= b.dist) { scene.remove(b.m); b.done = true; bus.emit('bounce', {}); }
    }
  }
  /* paint chips fly off a cat that has been found */
  function burst(e) {
    var c = e.c, ctr = c.center(V()), r = SG.rng(Math.floor(G.simT * 100) + 1);
    for (var i = 0; i < 44; i++) {
      var p = c.parts[Math.floor(r() * c.parts.length)], o = ((p.ry + Math.floor(r() * p.th)) * c.A + p.rx + Math.floor(r() * p.tw)) * 4;
      var m = new THREE.Mesh(new THREE.PlaneGeometry(0.035, 0.05), new THREE.MeshBasicMaterial({ color: new THREE.Color(c.alb[o] / 255, c.alb[o + 1] / 255, c.alb[o + 2] / 255).convertSRGBToLinear(), side: THREE.DoubleSide }));
      m.position.copy(ctr); m.layers.set(1); scene.add(m);
      G.confetti.push({ m: m, v: V((r() - 0.5) * 3.2, 1.5 + r() * 2.8, (r() - 0.5) * 3.2), life: 1.6 + r(), sp: (r() - 0.5) * 20 });
    }
  }
  function stepConfetti(dt) {
    for (var i = G.confetti.length - 1; i >= 0; i--) {
      var p = G.confetti[i]; p.v.y -= 6 * dt; p.v.multiplyScalar(Math.exp(-dt * 1.5)); p.m.position.addScaledVector(p.v, dt); p.m.rotation.x += p.sp * dt; p.m.rotation.y += p.sp * 0.7 * dt;
      if (p.m.position.y < 0.01) { p.m.position.y = 0.01; p.v.set(0, 0, 0); p.sp = 0; p.m.rotation.x = Math.PI / 2; }
      p.life -= dt; if (p.life < -8) { scene.remove(p.m); G.confetti.splice(i, 1); }
    }
  }

  /* ------------------------------------------------------------------ dog first person */
  /* a chunky pump-action toy paint blaster held in the dog's paws (our own design) */
  /* paint builds up on the blaster: every shot leaves a couple more blobs on barrel and receiver */
  var GUNC = [[74, 163, 224], [242, 154, 74], [231, 110, 150], [150, 200, 90], [246, 207, 58], [150, 110, 200], [245, 241, 232], [200, 69, 46]], gunMats = [], gunGeo = null;
  function gunSplat(seed) {
    if (!G.vm || G.vmBlobs >= 70) return; var r = SG.rng(seed * 97 + 13), ci = Math.floor(r() * GUNC.length), c = GUNC[ci], k = r(), m;
    if (!gunGeo) gunGeo = new THREE.SphereGeometry(1, 8, 6);
    if (!gunMats[ci]) gunMats[ci] = new THREE.MeshStandardMaterial({ color: new THREE.Color(c[0] / 255, c[1] / 255, c[2] / 255).convertSRGBToLinear(), roughness: 0.22 });
    m = new THREE.Mesh(gunGeo, gunMats[ci]); m.layers.set(1); var s0 = 0.008 + r() * 0.014;
    if (k < 0.45) { var a = -0.5 + r() * 4.1, z = -0.2 - r() * 0.32; m.position.set(Math.cos(a) * 0.038, 0.018 + Math.sin(a) * 0.038, z); m.scale.set(s0, s0, s0 * (1 + r() * 1.6)); }      // barrel
    else if (k < 0.75) { m.position.set((r() - 0.5) * 0.07, 0.05, -0.21 + r() * 0.24); m.scale.set(s0 * (1 + r()), s0 * 0.45, s0 * (1 + r())); }                                       // top of the receiver
    else if (k < 0.92) { m.position.set(-0.0425, -0.04 + r() * 0.08, -0.21 + r() * 0.26); m.scale.set(s0 * 0.45, s0 * (1 + r() * 1.4), s0 * (1 + r())); }                              // the side you see
    else { m.position.set((r() - 0.5) * 0.05, 0.0 + r() * 0.03, 0.08 + r() * 0.12); m.scale.set(s0, s0 * 0.5, s0); }                                                                     // stock
    G.vm.add(m); G.vmBlobs++;
  }
  var puffGeo = null, puffMats = {};
  function puff(pos, n, rgb) { // flecks of paint flying off where a pellet lands
    if (!puffGeo) puffGeo = new THREE.PlaneGeometry(0.03, 0.03); var key = rgb.join(); if (!puffMats[key]) puffMats[key] = new THREE.MeshBasicMaterial({ color: new THREE.Color(rgb[0] / 255, rgb[1] / 255, rgb[2] / 255).convertSRGBToLinear(), side: THREE.DoubleSide });
    for (var i = 0; i < 3; i++) { var m = new THREE.Mesh(puffGeo, puffMats[key]); m.position.copy(pos); m.layers.set(1); m.userData.shared = true; scene.add(m); G.confetti.push({ m: m, v: V(n.x * 1.6 + (rnd() - 0.5) * 2.2, n.y * 1.6 + 0.6 + rnd() * 1.6, n.z * 1.6 + (rnd() - 0.5) * 2.2), life: 0.35 + rnd() * 0.35, sp: (rnd() - 0.5) * 24 }); }
  }
  function buildLauncher() {
    var g = new THREE.Group(), M = function (geo, mat, x, y, z, rx, ry, rz, par) { var m = new THREE.Mesh(geo, mat); m.position.set(x, y, z); m.rotation.set(rx || 0, ry || 0, rz || 0); (par || g).add(m); m.layers.set(1); return m; };
    var std = function (c, r) { return new THREE.MeshStandardMaterial({ color: c, roughness: r || 0.38 }); };
    var org = std(0xf29a4a), teal = std(0x2fb3a8), yel = std(0xf6cf3a), wht = std(0xf5f1e8, 0.45), drk = std(0x2a2624, 0.7), pawC = { shiba: 0xfaf0de, corgi: 0xfcf8f0, bull: 0xf8f4ec, poodle: 0xe2b48e, dachs: 0x70402a, husky: 0xf4f4f0 }[G.me.breed] || 0xffffff, paw = std(pawC, 0.9);
    M(SG.geo.rbox(0.085, 0.1, 0.3, 0.03), org, 0, 0, -0.08);                                  // receiver
    M(new THREE.CylinderGeometry(0.036, 0.04, 0.34, 18), teal, 0, 0.018, -0.36, Math.PI / 2);   // barrel
    M(new THREE.CylinderGeometry(0.058, 0.044, 0.06, 18), yel, 0, 0.018, -0.55, Math.PI / 2);   // flared muzzle
    M(new THREE.TorusGeometry(0.044, 0.008, 6, 18), wht, 0, 0.018, -0.26);
    M(SG.geo.rbox(0.06, 0.13, 0.07, 0.022), drk, 0, -0.1, 0.02, 0.3);                           // grip
    M(SG.geo.rbox(0.07, 0.085, 0.16, 0.03), org, 0, -0.01, 0.14, -0.12);                         // stock
    M(new THREE.SphereGeometry(0.044, 16, 12), new THREE.MeshStandardMaterial({ color: 0xe76e96, roughness: 0.15 }), 0, 0.075, -0.02); // paint hopper
    M(new THREE.CylinderGeometry(0.018, 0.018, 0.025, 10), wht, 0, 0.12, -0.02);
    M(new THREE.TorusGeometry(0.03, 0.007, 5, 12, Math.PI), drk, 0, -0.055, -0.02, 0, Math.PI / 2, Math.PI);
    var pump = new THREE.Group(); g.add(pump); G.vmPump = pump;
    M(SG.geo.rbox(0.07, 0.05, 0.13, 0.02), wht, 0, -0.03, -0.36, 0, 0, 0, pump); for (var i = 0; i < 4; i++) M(SG.geo.rbox(0.074, 0.008, 0.012, 0.003), drk, 0, -0.058, -0.4 + i * 0.028, 0, 0, 0, pump);
    M(new THREE.SphereGeometry(0.05, 12, 10), paw, 0.005, -0.075, -0.36, 0, 0, 0, pump).scale.set(1.1, 0.8, 1.3);  // front paw on the pump
    M(new THREE.SphereGeometry(0.055, 12, 10), paw, 0.0, -0.14, 0.03).scale.set(1.1, 0.9, 1.3);                   // rear paw on the grip
    var fl = new THREE.Mesh(new THREE.SphereGeometry(0.09, 10, 8), new THREE.MeshBasicMaterial({ color: 0xfff2b0, transparent: true, opacity: 0.9, blending: THREE.AdditiveBlending, depthWrite: false })); fl.position.set(0, 0.018, -0.62); fl.layers.set(1); fl.visible = false; g.add(fl); G.vmFlash = fl;
    g.position.set(0.2, -0.21, -0.4); g.scale.setScalar(0.85);
    camera.add(g); scene.add(camera); G.vm = g; G.recoil = 0; G.punch = 0; G.vmBlobs = 0;
    for (var sb = 0; sb < 26; sb++) gunSplat(sb); // the blaster has seen a lot of paint already
  }

  /* ------------------------------------------------------------------ walking grid for bots (ground level: house, engawa, garden, alleys) */
  var NAV = null;
  var NAVR = 0.3, NAVH = 0.24; // the walking grid is cut for the flat dog: its half length all round, its height (so it also runs under tables)
  function buildNav() {
    var b = room.bounds, cs = 0.3, nx = Math.ceil((b.x1 - b.x0) / cs), nz = Math.ceil((b.z1 - b.z0) / cs), g = new Float32Array(nx * nz), ok = new Uint8Array(nx * nz), i, j;
    for (j = 0; j < nz; j++) for (i = 0; i < nx; i++) { var x = b.x0 + (i + 0.5) * cs, z = b.z0 + (j + 0.5) * cs, y = room.groundAt(x, z, 0.3, 0); g[j * nx + i] = y; ok[j * nx + i] = y < 0.36 && !room.blocked(x, z, y, NAVR, RULES.move.stepUp, NAVH) ? 1 : 0; }
    NAV = { x0: b.x0, z0: b.z0, cs: cs, nx: nx, nz: nz, g: g, ok: ok, prev: new Int32Array(nx * nz), q: new Int32Array(nx * nz) };
  }
  function navCell(x, z, near, y) { // the cell under a point, or the closest walkable one within about a metre; with y: only cells at that height (a body that fell off a ledge starts from where it really is)
    var N = NAV, i = Math.max(0, Math.min(N.nx - 1, Math.floor((x - N.x0) / N.cs))), j = Math.max(0, Math.min(N.nz - 1, Math.floor((z - N.z0) / N.cs))), c0 = j * N.nx + i, lv = function (c) { return y == null || Math.abs(N.g[c] - y) < 0.3; }; if ((N.ok[c0] && lv(c0)) || !near) return N.ok[c0] ? c0 : -1;
    for (var r = 1; r <= 4; r++) for (var dj = -r; dj <= r; dj++) for (var di = -r; di <= r; di++) { var a = i + di, b2 = j + dj; if (a >= 0 && b2 >= 0 && a < N.nx && b2 < N.nz && N.ok[b2 * N.nx + a] && lv(b2 * N.nx + a)) return b2 * N.nx + a; } return y == null ? -1 : navCell(x, z, near);
  }
  function navPath(x0, z0, x1, z1, y0) {
    if (!NAV) buildNav(); var N = NAV, s = navCell(x0, z0, true, y0), e = navCell(x1, z1, true); if (s < 0 || e < 0) return null; if (s === e) return [[x1, z1]];
    var prev = N.prev, q = N.q, h = 0, t = 0, nx = N.nx, DI = [1, -1, 0, 0, 1, 1, -1, -1], DJ = [0, 0, 1, -1, 1, -1, 1, -1], k; prev.fill(-1); prev[e] = e; q[t++] = e; // search back from the goal
    while (h < t && prev[s] < 0) { var c = q[h++], ci = c % nx, cj = (c - ci) / nx;
      for (k = 0; k < 8; k++) { var ni = ci + DI[k], nj = cj + DJ[k]; if (ni < 0 || nj < 0 || ni >= nx || nj >= N.nz) continue; var n = nj * nx + ni; if (!N.ok[n] || prev[n] >= 0 || Math.abs(N.g[n] - N.g[c]) > RULES.move.stepUp + 0.02) continue; if (k > 3 && (!N.ok[cj * nx + ni] || !N.ok[nj * nx + ci])) continue; prev[n] = c; q[t++] = n; } }
    if (prev[s] < 0) return null; var out = [], c2 = prev[s], guard = 0; while (c2 !== e && guard++ < 9000) { out.push([N.x0 + (c2 % nx + 0.5) * N.cs, N.z0 + (Math.floor(c2 / nx) + 0.5) * N.cs]); c2 = prev[c2]; } out.push([N.x0 + (e % nx + 0.5) * N.cs, N.z0 + (Math.floor(e / nx) + 0.5) * N.cs]); return out;
  }
  G.navPath = navPath;
  /* last resort: a body that is being pushed but has not moved for a while is put on the nearest free spot (never through a wall: the spot must be connected on the walking grid) */
  function unstick(e) {
    if (!NAV) buildNav(); var best = null, bd = 1e9, y0 = e.y + e.step, y1 = e.y + (e.h || 0.2);
    for (var r = 0.08; r <= 0.56 && !best; r += 0.08) for (var a = 0; a < 6.28; a += 0.524) { var x = e.x + Math.cos(a) * r, z = e.z + Math.sin(a) * r; if (pushOut(x, z, (e.halfLen || e.rad) + 0.02, y0, y1, _po)) continue; if (room.blocked(x, z, e.y, 0.05, e.step, 0.02) === true || room.segWalls(e.x, e.y + 0.08, e.z, x, e.y + 0.08, z) < 1) continue; var d = Math.hypot(x - e.x, z - e.z); if (d < bd) { bd = d; best = [x, z]; } }
    if (best) { e.x = best[0]; e.z = best[1]; bus.emit('unstuck', { id: e.id }); } return !!best;
  }
  G.unstick = unstick;
  /* walk a dog-sized body along goals the way a player would (turn to the next point, push forward) and report every stall longer than a second.
     goals: 'route' = the patrol tour through every room and doorway; 'edges' = points along every wall and furniture edge of the walking grid */
  G.walkTest = function (which, o) {
    o = o || {}; if (!NAV) buildNav(); var N = NAV, goals = [], i, j, e = o.ent || G.me, sp = o.speed || RULES.dog.speed, dt = 1 / 60, out = { goals: 0, reached: 0, skipped: [], stalls: [], nudges: 0, dist: 0, time: 0 };
    if (which === 'route') goals = room.route.map(function (w) { return [w[0], w[1]]; });
    else { for (j = 1; j < N.nz - 1; j += 2) for (i = 1; i < N.nx - 1; i += 2) { var c = j * N.nx + i; if (!N.ok[c]) continue; if (N.ok[c - 1] && N.ok[c + 1] && N.ok[c - N.nx] && N.ok[c + N.nx]) continue; goals.push([N.x0 + (i + 0.5) * N.cs, N.z0 + (j + 0.5) * N.cs]); }
      var tour = [], cur = [e.x, e.z]; while (goals.length) { var bi = 0, bd = 1e9; for (i = 0; i < goals.length; i++) { var dd = Math.hypot(goals[i][0] - cur[0], goals[i][1] - cur[1]); if (dd < bd) { bd = dd; bi = i; } } cur = goals.splice(bi, 1)[0]; tour.push(cur); } goals = tour; if (o.max) goals = goals.slice(0, o.max); }
    out.goals = goals.length; var un = G.unstuckOff; G.unstuckOff = !!o.noNudge;
    for (var g = 0; g < goals.length; g++) {
      var path = navPath(e.x, e.z, goals[g][0], goals[g][1], e.y); if (!path) { out.skipped.push(goals[g].map(function (v) { return +(v / SG.WS).toFixed(2); })); continue; }
      var pi = 0, still = 0, lastD = 1e9, guard = 0, bad = false;
      while (pi < path.length && guard++ < 60 * 40) {
        var tx = path[pi][0], tz = path[pi][1], d = Math.hypot(tx - e.x, tz - e.z); if (d < 0.3) { pi++; lastD = 1e9; still = 0; continue; }
        e.yaw = turn(e.yaw, Math.atan2(tx - e.x, tz - e.z), dt * 10); var px = e.x, pz = e.z; e.hitWallX = e.hitWallZ = 0; e.hitPlat = null; moveEnt(e, Math.sin(e.yaw) * sp * dt, Math.cos(e.yaw) * sp * dt, dt); physEnt(e, dt);
        out.dist += Math.hypot(e.x - px, e.z - pz); out.time += dt;
        if (d < lastD - 0.004) { lastD = d; still = 0; } else { still += dt; if (still > 1) { if (!bad) out.stalls.push({ at: [+(e.x / SG.WS).toFixed(2), +(e.z / SG.WS).toFixed(2)], y: +e.y.toFixed(2), to: [+(tx / SG.WS).toFixed(2), +(tz / SG.WS).toFixed(2)], goal: g }); bad = true; if (!o.noNudge && unstick(e)) out.nudges++; still = 0; lastD = 1e9; if (o.noNudge || guard > 60 * 30) break; } }
      }
      if (pi >= path.length) out.reached++; else if (!bad) out.stalls.push({ at: [+(e.x / SG.WS).toFixed(2), +(e.z / SG.WS).toFixed(2)], timeout: true, goal: g });
    }
    G.unstuckOff = un; out.dist = +out.dist.toFixed(1); out.time = +out.time.toFixed(1); return out;
  };
  /* how much of the walking grid a dog can reach from the entry point with a given step-up height */
  G.navStats = function (step) { var s0 = RULES.move.stepUp; RULES.move.stepUp = step; NAV = null; buildNav(); var N = NAV, tot = 0, i; for (i = 0; i < N.ok.length; i++) tot += N.ok[i]; var un = []; room.route.forEach(function (w, k) { if (!navPath(G.dogSpawn[0], G.dogSpawn[1], w[0], w[1])) un.push(k); }); RULES.move.stepUp = s0; NAV = null; return { step: step, walkable: tot, routeGoals: room.route.length, unreachable: un }; };

  /* ------------------------------------------------------------------ bot dog */
  function botDog(d, dt) {
    var ai = d.ai; if (!ai || G.state.phase !== 'seek') { d.speed = 0; return; }
    var st = G.state, pid = d.pid, p = st.players[pid], eye = V(d.x, d.y + d.eyeH, d.z), dbl = st.mode === 'double';
    var targets = cats().concat(G.decoys).filter(function (c) { return c.c.root.visible && c.id !== pid && c.decoyOf !== pid && (dbl ? p.found.indexOf(c.id) < 0 : !c.out); });
    ai.scan = (ai.scan || 0) - dt; ai.seenMe = false;
    if (ai.scan <= 0) {
      ai.scan = RULES.overlooked.tickEverySec;
      var areas = overlookTick(d, dogCam(d));
      targets.forEach(function (c) {
        var ctr = c.c.center(tmp2), dist = eye.distanceTo(ctr), key = c.id;
        var ang = Math.atan2(ctr.x - d.x, ctr.z - d.z) - d.yaw; while (ang > Math.PI) ang -= 2 * Math.PI; while (ang < -Math.PI) ang += 2 * Math.PI;
        var inView = dist < RULES.bot.dogViewDistance && Math.abs(ang) < RULES.bot.dogFovDeg * Math.PI / 360 && Math.abs(ctr.y - eye.y) < 2.2, sv = ai.sus[key] || 0;
        if (inView) {
          var mm = mismatch(c, eye); c.lastMis = mm.m;
          var gain = Math.max(0, mm.m - RULES.bot.dogMismatchFloor) * RULES.bot.dogSuspicionGain * (1.4 - dist / RULES.bot.dogViewDistance) * (ai.mode === 'stare' && ai.target === c ? 1.6 : 1);
          if (c.speed > RULES.cat.stillSpeed && mm.visible > 0.01) gain += RULES.bot.catMoveSuspicion * Math.min(1, c.speed);
          if (c.exposed) gain += 3;
          if (mm.visible < 0.004) inView = false; else sv = Math.min(1.2, sv + gain * ai.scan * 2);
        }
        if (!inView) sv = Math.max(0, sv - RULES.bot.dogSuspicionDecay * ai.scan);
        ai.sus[key] = sv; c.sus = Math.max(sv, 0);
        if ((c === G.me || c.decoyOf === 'you') && inView) ai.seenMe = true;
      });
    }
    if (ai.mode !== 'aim' && (p.ammo > 0 || RULES.dog.unlimited)) {
      var sure = targets.filter(function (c) { return (ai.sus[c.id] || 0) >= 1; })[0];
      if (sure) { ai.mode = 'aim'; ai.target = sure; ai.wait = 0.8; d.c.tilt = 0; bus.emit('alert', { cat: sure.id }); bus.emit('say', { id: d.id, text: ['找到你了！', '就是你！', '汪！'][Math.floor(rnd() * 3)] }); }
      else if (ai.mode === 'patrol') { // something looks off: stop and stare at it for a moment before deciding
        var odd = targets.filter(function (c) { var v = ai.sus[c.id] || 0; return v >= 0.42 && v < 1 && Math.hypot(c.x - d.x, c.z - d.z) < RULES.bot.dogViewDistance; })[0];
        if (odd && !(ai.stareCd > 0)) { ai.mode = 'stare'; ai.target = odd; ai.stareT = RULES.feel.stareSecMin + rnd() * (RULES.feel.stareSecMax - RULES.feel.stareSecMin); bus.emit('say', { id: d.id, text: ['？', '嗯…？', '有味道…', '這個怪怪的'][Math.floor(rnd() * 4)] }); }
      }
    }
    if (ai.stareCd > 0) ai.stareCd -= dt;
    if (ai.mode === 'stare') {
      var sc = ai.target, sct = sc.c.center(tmp2); d.yaw = turn(d.yaw, Math.atan2(sct.x - d.x, sct.z - d.z), dt * 5); d.speed = 0; d.c.tilt = Math.sin(G.simT * 3) * 0.32; ai.stareT -= dt;
      if (ai.stareT <= 0 || targets.indexOf(sc) < 0) { ai.mode = 'patrol'; d.c.tilt = 0; ai.stareCd = 4; if ((ai.sus[sc.id] || 0) < 1) { ai.sus[sc.id] = (ai.sus[sc.id] || 0) * 0.45; bus.emit('say', { id: d.id, text: ['看錯了…', '算了', '只是靠墊吧'][Math.floor(rnd() * 3)] }); } }
      return;
    }
    var tx, tz;
    if (ai.mode === 'aim') {
      var t = ai.target; if (!t.c.root.visible || targets.indexOf(t) < 0) { ai.mode = 'patrol'; return; }
      var ctr = t.c.center(tmp2); d.yaw = turn(d.yaw, Math.atan2(ctr.x - d.x, ctr.z - d.z), dt * 6); d.speed = 0; ai.wait -= dt;
      if (ai.wait <= 0) {
        var er = 0.02 + 0.2 * Math.max(0, Math.min(1, 1 - (t.lastMis || 0) / 0.22)); // the better the camouflage from here, the worse the aim
        var dir = V().subVectors(ctr, eye).normalize(); dir.x += (rnd() - 0.5) * er; dir.y += (rnd() - 0.5) * er; dir.normalize();
        if (fire(d, eye, dir)) { ai.sus[t.id] = 0.3; ai.mode = 'patrol'; ai.wait = 1.0; } else ai.wait = 0.3;
      }
      return;
    }
    if (ai.heard) { tx = ai.heard[0]; tz = ai.heard[1]; ai.heardT = (ai.heardT || 0) + dt; if (Math.hypot(tx - d.x, tz - d.z) < 1.4 || ai.heardT > 6) { ai.heard = null; ai.heardT = 0; ai.wait = 2.0; } }
    else { // patrol: the tour gives the goals, the walking grid finds the way round furniture to each of them
      var WPS = G.botRoute || (G.botRoute = room.route.filter(function (q) { return !!navPath(G.dogSpawn[0], G.dogSpawn[1], q[0], q[1], 0); })), w = WPS[ai.wp % WPS.length];
      if (ai.pathWp !== ai.wp || !ai.path) { ai.path = navPath(d.x, d.z, w[0], w[1], d.y); ai.pathWp = ai.wp; ai.pi = 0; if (!ai.path) { ai.wp += 1; ai.path = null; return; } } // nowhere to stand there (upstairs, inside something): next goal
      var pt = ai.path[Math.min(ai.pi, ai.path.length - 1)]; tx = pt[0]; tz = pt[1];
      if (Math.hypot(tx - d.x, tz - d.z) < 0.36) { ai.pi++; if (ai.pi >= ai.path.length) { ai.path = null; if (rnd() < 0.04 && ai.wp > 3) { ai.wp -= 2; bus.emit('say', { id: d.id, text: '再看一次' }); } else ai.wp += 1; ai.wait = rnd() < 0.3 ? 0.6 + rnd() * 0.9 : 0; ai.look = (rnd() - 0.5) * 2.4; } } }
    if (ai.wait > 0) { ai.wait -= dt; d.speed = 0; d.rearT = ai.wait > 0.3 ? 1 : 0; d.pitch = 0.25; d.yaw += Math.sin(G.simT * 1.4) * dt * 0.9 + ai.look * dt * 0.4; return; }
    var want = Math.atan2(tx - d.x, tz - d.z); d.yaw = turn(d.yaw, want, dt * 9); var dA = want - d.yaw; while (dA > Math.PI) dA -= 2 * Math.PI; while (dA < -Math.PI) dA += 2 * Math.PI;
    var sp = RULES.bot.patrolSpeed * Math.max(0.15, Math.cos(dA)), px = d.x, pz = d.z; /* slows down to turn, so it never circles a point it cannot hit */ var gz = Math.max(0, Math.sin(G.simT * 0.55 + d.id.length)); d.pitch = 0.02 + 0.55 * gz * gz * gz; d.rearT = gz > 0.75 ? 1 : 0; /* its eye is low now: it rears up when it glances at the high places */ /* looks level most of the time and glances up now and then: shelves, beams and ceilings get checked too */ moveEnt(d, Math.sin(d.yaw) * sp * dt, Math.cos(d.yaw) * sp * dt, dt);
    d.speed = Math.hypot(d.x - px, d.z - pz) / dt; if (d.speed < 0.12) { ai.stuck = (ai.stuck || 0) + dt; if (ai.stuck > 0.9) { if (ai.heard) ai.heard = null; else if (ai.path && !ai.repath) { ai.path = null; ai.repath = 1; } else { ai.wp++; ai.path = null; ai.repath = 0; } ai.stuck = 0; } } else { ai.stuck = 0; if (d.speed > 1) ai.repath = 0; }
  }
  function turn(a, b, k) { var d = b - a; while (d > Math.PI) d -= 2 * Math.PI; while (d < -Math.PI) d += 2 * Math.PI; return a + d * Math.min(1, k); }

  /* ------------------------------------------------------------------ player actions */
  G.setPoseAmount = function (a) { var c = G.me && G.me.team === 'cat' && !G.me.out ? G.me.c : null; if (!c) return 0; c.poseAmount = Math.max(0, Math.min(1, a)); bus.emit('poseAmount', { amount: c.poseAmount }); return c.poseAmount; };
  G.setPose = function (name) { if (!G.me || G.me.team !== 'cat' || G.me.out) return; if (G.paint.on && name !== 'stand') G.setPaintMode(false); G.viewLock = false; G.me.c.setPose(name); bus.emit('pose', { pose: name }); if (name !== 'stand' && G.guide === 1) setGuide(2); };
  function meowFrom(e, forced) {
    bus.emit('meow', { x: e.x, z: e.z, id: e.id, forced: !!forced, me: e === G.me });
    dogsOf().forEach(function (d) {
      var dist = Math.hypot(d.x - e.x, d.z - e.z); if (dist > RULES.cat.meowRange) return;
      if (d.ai) { d.ai.heard = [e.x, e.z]; d.ai.heardT = 0; }
      else if (d === G.me) { var a = Math.atan2(e.x - d.x, e.z - d.z) - d.yaw; while (a > Math.PI) a -= 2 * Math.PI; while (a < -Math.PI) a += 2 * Math.PI; bus.emit('heard', { angle: a, dist: dist }); }
    });
  }
  G.meow = function () { if (!G.me || G.me.team !== 'cat' || G.me.out) return; meowFrom(G.me); G.meowT = G.settings.meowEvery; };
  G.decoy = function () {
    if (!G.me || G.me.team !== 'cat' || G.me.out) return false;
    if (G.state && G.state.mode === 'double' && G.state.phase === 'seek') return false;
    var SL = G.decoySlots, si = -1; for (var q = 0; q < SL.length; q++) if (!SL[q].e && SL[q].cd <= 0) { si = q; break; } // two clones, each with its own 30 s cooldown (left diamond = first, right = second)
    if (si < 0) { bus.emit('denied'); return false; }
    var c = new SG.Critter(G.me.spec, { seed: 9, atlas: RULES.paint.textureSize, scale: G.me.size }); c.copyPaintFrom(G.me.c); c.tailMode = G.me.c.tailMode; c.earMode = G.me.c.earMode; c.setPose(G.me.c.pose, G.me.c.poseAmount); if (c.settle) c.settle(); c.frozen = true; c.faceSkin.visible = false; scene.add(c.root);
    var e = { id: 'decoy' + G.decoys.length, c: c, team: 'cat', decoyOf: 'you', x: G.me.x, y: G.me.y, z: G.me.z, yaw: G.me.yaw, sus: 0, speed: 0, out: false };
    c.root.position.copy(G.me.c.root.position); c.root.quaternion.copy(G.me.c.root.quaternion); for (var k = 0; k < 20; k++) c.update(0.05, rnd); // a clone made on a wall stays on the wall
    e.slot = si; e.rad = G.me.rad; e.size = G.me.size; SL[si].e = e; SL[si].cd = RULES.cat.decoyCooldownSec; G.decoys.push(e);
    if (embedDepth(e) > e.rad * RULES.cat.embedRatio) { e.embed = true; c.glow.value.setRGB(0.9, 0.08, 0.04); bus.emit('cloneEmbed', {}); } // a clone pushed into the scenery shows a red warning
    bus.emit('decoy', { n: G.decoys.length }); return true;
  };
  G.recallDecoys = function () { if (G.state && G.state.mode === 'double' && G.state.phase === 'seek') return; /* Double: no clearing clones once you are a hunter */ G.decoySlots.forEach(function (sl) { sl.e = null; }); G.decoys.forEach(function (d) { scene.remove(d.c.root); d.c.dispose(); }); G.decoys = []; bus.emit('decoy', { n: 0 }); };
  G.skip = function () { // vote to skip prep / reveal (bots always agree, so alone it is instant)
    if (G.lobby) { G.lobby.t = Math.min(G.lobby.t, 0.01); return; }
    if (!G.state) return;
    if (G.state.phase === 'prep' || G.state.phase === 'reveal') dispatch({ type: 'vote', id: 'you' });
    else if (G.state.phase === 'seek' && G.fly && G.state.mode === 'basic') dispatch({ type: 'tick', dt: G.state.left }); // caught, nothing left to do alone: go to the result
  };
  G.toTitle = toTitle;
  function setGuide(n) { if (G.guide !== n) { G.guide = n; bus.emit('guide', { step: n }); } }

  /* painting */
  G.setPaintMode = function (on) { if (!G.me || G.me.team !== 'cat') return; if (on && !G.paint.on && !G.me.cling) { G.paint.pitch0 = G.cam.pitch; G.cam.pitch = Math.max(G.cam.pitch, 0.85); } else if (!on && G.paint.on && G.paint.pitch0 != null) { G.cam.pitch = G.paint.pitch0; G.paint.pitch0 = null; } G.paint.on = on; G.stroking = false; if (!Q.get('nolock')) { try { if (on && document.exitPointerLock) document.exitPointerLock(); else if (!on && canvas.requestPointerLock) canvas.requestPointerLock(); } catch (er) { } } /* paint mode: free cursor; leaving it takes the pointer back */ bus.emit('paintmode', { on: on }); if (on && G.guide === 2) setGuide(3); };
  function pointerRay(x, y) { tmp.set(x / G.vw * 2 - 1, -(y / G.vh) * 2 + 1, 0.5); ray.setFromCamera(new THREE.Vector2(tmp.x, tmp.y), camera); ray.far = 60; ray.layers.set(0); return ray; }
  var patDir = V(), patPerp = V(), patOn = false;
  function paintPattern(x, y, first) {
    var P = G.paint, c = G.me.c, pr = pointerRay(x, y), hit = c.raycast(pr);
    if (!hit) { P.last = null; return false; }
    if (!G.seeThrough) { // normal brush: whatever stands between the camera and the body blocks the stroke
      var blk = segSolid(camera.position, hit.point, 0.03); // against the collision boxes: cheap enough to do on every mouse move
      if (blk) { P.last = null; if (first) bus.emit('blocked'); return false; } }
    var thru = null; // (the through-the-body brush was our guess at key 3; the original's key 3 is camera pass-through, so it is gone)
    var hard = P.hard ? RULES.paint.hardnessHard : RULES.paint.hardnessSoft, pat = null;
    if (P.pattern) { // the pattern follows the direction of the stroke, fixed once the stroke has moved a little
      if (first) { patOn = false; P.last = (P.last || V()).copy(hit.point); P.first = hit.point.clone(); return true; }
      if (!patOn) { if (P.first.distanceTo(hit.point) < 0.008) return true; patDir.subVectors(hit.point, P.first).normalize(); patPerp.subVectors(hit.point, camera.position).normalize().cross(patDir).normalize(); patOn = true; P.last.copy(P.first); }
      var dk = P.pattern === 'wood' || P.pattern === 'tatami';
      pat = { type: P.pattern, dir: patDir, perp: patPerp, scale: Math.max(0.012, P.size * 0.5), rgb2: dk ? [P.rgb[0] * 0.62, P.rgb[1] * 0.6, P.rgb[2] * 0.55] : (P.rgb2 || [245, 241, 232]) };
    }
    if (P.last && !first) { var d = P.last.distanceTo(hit.point), n = Math.min(40, Math.ceil(d / (P.size * 0.25))); for (var i = 1; i < n; i++) c.paint(tmp2.lerpVectors(P.last, hit.point, i / n), P.size, P.rgb, P.rough, P.metal, hard, pat); }
    c.paint(hit.point, P.size, P.rgb, P.rough, P.metal, hard, pat);
    if (thru) for (var ti = 1, tn = Math.ceil(0.7 * G.me.size / (P.size * 0.6)); ti <= tn; ti++) c.paint(tmp2.copy(hit.point).addScaledVector(thru, ti * P.size * 0.6), P.size, P.rgb, P.rough, P.metal, hard, pat);
    P.last = (P.last || V()).copy(hit.point); bus.emit('stroke', { size: P.size });
    if (G.guide === 4 && c.paintedRatio() > 0.12) setGuide(5);
    return true;
  }
  /* the brush. The mouse path is smoothed (corners rounded with a quadratic curve) and resampled: ray hits about one brush
     radius apart, dabs every quarter radius between them, so a fast stroke is one continuous band and the paint is under the
     cursor in the same frame. */
  var SP = { pts: [], last: null, acc: 0, n: 0, dist: 0, touched: false, tPrev: 0, drop: 0 };
  G.strokeStats = { lat: 0, latMax: 0, evMs: 0, evMax: 0, dabsEv: 0, dabsMaxEv: 0 };
  function brushHit(x, y) { // the body under a screen point; hit.blocked when something stands in the way and see-through is off
    var hit = G.me.c.raycast(pointerRay(x, y)); if (!hit) return null;
    if (!G.seeThrough && segSolid(camera.position, hit.point, 0.03)) hit.blocked = true;
    return hit;
  }
  function dabAt(pt) { var P = G.paint; G.fx.dab(G.me.c, pt, P.size, P.rgb, P.rough, P.metal, P.hard ? RULES.paint.hardnessHard : RULES.paint.hardnessSoft, RULES.paint.opacity == null ? 1 : RULES.paint.opacity); SP.n++; }
  function strokeSeg(x0, y0, x1, y1) {
    var P = G.paint, len = Math.hypot(x1 - x0, y1 - y0), depth = SP.last ? SP.last.distanceTo(camera.position) : G.cam.dist, ppm = G.vh / (2 * Math.tan(camera.fov * Math.PI / 360) * Math.max(0.2, depth));
    var stepPx = Math.max(2, P.size * ppm * 0.8), n = Math.max(1, Math.ceil(len / stepPx)), sp = P.size * 0.25;
    for (var i = 1; i <= n; i++) {
      var hit = brushHit(x0 + (x1 - x0) * i / n, y0 + (y1 - y0) * i / n);
      if (!hit || hit.blocked) { SP.last = null; continue; }
      var h = hit.point;
      if (SP.last) { var d = SP.last.distanceTo(h);
        if (d < P.size * 4 && d > 1e-6) { var m = Math.floor((SP.acc + d) / sp); for (var q = 1; q <= m && SP.n < 8000; q++) dabAt(tmp2.lerpVectors(SP.last, h, (q * sp - SP.acc) / d)); SP.acc = SP.acc + d - m * sp; SP.dist += d; }
        else if (d >= P.size * 4) { dabAt(h); SP.acc = 0; } // jumped across a gap in the silhouette: no paint through the air
        SP.last.copy(h); }
      else { SP.last = h.clone(); dabAt(h); SP.acc = 0; if (!SP.touched) { SP.touched = true; bus.emit('touch', { size: P.size }); } }
      SP.nrm = hit.face && hit.face.normal ? hit.face.normal : null;
    }
  }
  function paintAt(x, y, first) {
    var P = G.paint, t0 = performance.now(), n0 = SP.n;
    if (P.pattern) return paintPattern(x, y, first);
    if (G.me.c._fx && G.me.c._fx.fillJob) G.fx.finishFill(G.me.c);
    if (first) {
      SP.pts = [[x, y]]; SP.last = null; SP.acc = 0; SP.n = 0; SP.dist = 0; SP.touched = false; SP.tPrev = t0; SP.drop = 0;
      var h0 = brushHit(x, y);
      if (h0 && h0.blocked) bus.emit('blocked');
      else if (h0) { SP.last = h0.point.clone(); dabAt(h0.point); SP.touched = true; bus.emit('touch', { size: P.size }); bus.emit('stroke', { size: P.size, speed: 0 }); }
    } else {
      var pts = SP.pts, a = pts[pts.length - 1]; if (Math.abs(x - a[0]) + Math.abs(y - a[1]) < 0.5) return true;
      var d0 = SP.dist, done = false;
      if (pts.length >= 2) { // round the corner at the previous sample
        var b = pts[pts.length - 2], m0x = (b[0] + a[0]) / 2, m0y = (b[1] + a[1]) / 2, m1x = (a[0] + x) / 2, m1y = (a[1] + y) / 2;
        var ex = m1x - m0x, ey = m1y - m0y, el = Math.hypot(ex, ey) || 1, dev = Math.abs((a[0] - m0x) * ey - (a[1] - m0y) * ex) / el;
        if (dev > 1.5) { var K = Math.max(3, Math.min(10, Math.ceil(el / 14))), px = m0x, py = m0y; SP.last = null; SP.acc = 0;
          for (var i = 1; i <= K; i++) { var t = i / K, u = 1 - t, qx = u * u * m0x + 2 * u * t * a[0] + t * t * m1x, qy = u * u * m0y + 2 * u * t * a[1] + t * t * m1y; if (i === 1) { var hs = brushHit(px, py); if (hs && !hs.blocked) SP.last = hs.point.clone(); } strokeSeg(px, py, qx, qy); px = qx; py = qy; }
          strokeSeg(m1x, m1y, x, y); done = true; }
      }
      if (!done) strokeSeg(a[0], a[1], x, y);
      pts.push([x, y]); if (pts.length > 4) pts.shift();
      var dtS = Math.max(0.004, (t0 - SP.tPrev) / 1000), speed = (SP.dist - d0) / dtS; SP.tPrev = t0; SP.speed = speed;
      if (SP.last) bus.emit('stroke', { size: P.size, speed: speed });
      // droplets fly off a fast stroke
      if (SP.last && speed > 1.1) { SP.drop += (SP.dist - d0); while (SP.drop > 0.07) { SP.drop -= 0.07; var c0 = G.me.c.center(tmp), nx = SP.last.x - c0.x, ny = SP.last.y - c0.y, nz = SP.last.z - c0.z, nl = Math.hypot(nx, ny, nz) || 1, k = 0.5 + rnd() * 0.7;
          G.fx.spray(SP.last, tmp2.set(nx / nl * k + (rnd() - 0.5) * 0.6, ny / nl * k + 0.7 + rnd() * 0.5, nz / nl * k + (rnd() - 0.5) * 0.6), P.rgb, P.size * (0.05 + rnd() * 0.06)); } }
    }
    if (G.guide === 4 && SP.n > 12 && G.me.c.paintedRatio() > 0.12) setGuide(5);
    var ST = G.strokeStats, ms = performance.now() - t0, nd = SP.n - n0; ST.evMs = ms; if (ms > ST.evMax) ST.evMax = ms; ST.dabsEv = nd; if (nd > ST.dabsMaxEv) ST.dabsMaxEv = nd; ST.pending = ST.pending || t0;
    return true;
  }
  G.undo = function () { var c = G.me.c; if (c._fx && c._fx.fillJob) G.fx.finishFill(c); var s = G.paint.undo.pop(); if (s) { c.undoStroke(s); if (c._fx) G.fx.reflag(c, s.parts); bus.emit('undo', { left: G.paint.undo.length }); } return !!s; };
  /* fill: the colour wipes down over the body (or over one body part: double-click it) */
  G.fillAll = function (parts) { var c = G.me.c; if (G.stroking) { G.stroking = false; pushUndo(c.endStroke()); } if (c._fx && c._fx.fillJob) G.fx.finishFill(c); c.beginStroke(); bus.emit('fill', { part: !!parts });
    G.fx.fill(c, G.paint.rgb.slice(), G.paint.rough, G.paint.metal, parts || null, parts ? 0.28 : 0.45, function () { pushUndo(c.endStroke()); bus.emit('strokeEnd', { undo: G.paint.undo.length }); }); if (G.guide === 4) setGuide(5); };
  G.fillPartAt = function (x, y) { var c = G.me.c, hit = brushHit(x, y); if (!hit || hit.blocked) return false; var pi = -1; c.parts.forEach(function (p, i) { if (p === hit.part || (p.mesh === hit.object && !hit.part)) pi = i; }); if (pi < 0) return false; var ps = {}; ps[pi] = true; G.fillAll(ps); return true; };
  function pushUndo(s) { if (!s) return; G.paint.undo.push(s); if (G.paint.undo.length > RULES.paint.undoSteps) G.paint.undo.shift(); }
  /* eyedropper: unlit surface colour under the cursor (+ the material's roughness / metalness) */
  G.pickAt = function (x, y, unlit) {
    var k = post.width / G.vw, rgb = post.pick(scene, camera, x * k, y * k, post.width, post.height, unlit ? 'albedo' : 'lit');
    var h = pointerRay(x, y).intersectObjects([room.batched, room.dyn], true)[0], rough = 1, metal = 0;
    if (h && h.object.material && h.object.material.isMeshStandardMaterial) { rough = h.object.material.roughness; metal = h.object.material.metalness; }
    G.paint.rgb = rgb; G.paint.rough = rough; G.paint.metal = metal;
    bus.emit('picked', { rgb: rgb, rough: rough, metal: metal, unlit: !!unlit }); if (G.guide === 3) setGuide(4);
    return rgb;
  };
  /* magnifier for the eyedropper: the unlit surface colours around the cursor (what Space would pick), n x n pixels, bottom row first */
  var lpCam = new THREE.PerspectiveCamera(), lpPx = new Uint8Array(11 * 11 * 4);
  G.loupeAt = function (x, y) { var k = post.width / G.vw, N = 11; lpCam.copy(camera); lpCam.setViewOffset(post.width, post.height, Math.floor(x * k) - 5, Math.floor(y * k) - 5, N, N); lpCam.updateProjectionMatrix(); lpCam.matrixWorld.copy(camera.matrixWorld); lpCam.matrixWorldInverse.copy(camera.matrixWorldInverse); lpCam.layers.mask = camera.layers.mask; post.renderAlbedo(scene, lpCam, N, N, lpPx); return lpPx; };
  G.setTail = function (m) { if (G.me && G.me.team === 'cat') { G.me.c.tailMode = m; bus.emit('tail', { mode: m }); } };
  G.setEars = function (flat) { if (G.me && G.me.team === 'cat') { G.me.c.earFlat = !!flat; bus.emit('ears', { flat: !!flat }); } };
  G.setColor = function (rgb) { G.paint.rgb = rgb; if (G.guide === 3) setGuide(4); };
  /* four suggested colours: under, behind, left and right of the cat */
  var sugCam = new THREE.PerspectiveCamera(8, 1, 0.05, 30), sugPx = new Uint8Array(4);
  G.suggest = function () {
    if (!G.me) return []; var c = G.me.c.center(V()), out = [], yaw = G.me.yaw, D = RULES.paint.suggestDistance;
    [[0, -1, 0], [-Math.sin(yaw), 0, -Math.cos(yaw)], [-Math.cos(yaw), 0, Math.sin(yaw)], [Math.cos(yaw), 0, -Math.sin(yaw)]].forEach(function (d) {
      sugCam.position.copy(c); sugCam.up.set(0, d[1] ? 0 : 1, d[1] ? 1 : 0); sugCam.lookAt(c.x + d[0] * D, c.y + d[1] * D - (d[1] ? 0 : 0.12), c.z + d[2] * D); sugCam.updateMatrixWorld(true);
      G.me.c.root.visible = false; post.renderAlbedo(scene, sugCam, 1, 1, sugPx); G.me.c.root.visible = true; out.push([sugPx[0], sugPx[1], sugPx[2]]);
    });
    return out;
  };

  /* ------------------------------------------------------------------ input */
  /* key layout follows the original: F paint, R pose wheel, right click view lock, 1 meow, 2 name tags, 3 see-through,
     Q decoy, X recall, G like, T chat, Space jump, Ctrl crouch (C also works), 4/5 spectate; seekers: left click fire, right click 1st/3rd person */
  function bindInput() {
    function lock() { if (!Q.get('nolock') && document.pointerLockElement !== canvas && canvas.requestPointerLock) { try { canvas.requestPointerLock(); } catch (er) { } } }
    window.addEventListener('keydown', function (e) {
      if (e.target && /INPUT|TEXTAREA/.test(e.target.tagName)) return;
      var k = e.key.length === 1 ? e.key.toLowerCase() : e.key; if (G.keys[k] && e.repeat) return; G.keys[k] = true;
      if (G.mode !== 'play' || !G.me) return;
      if (k === 'Tab' || k === ' ' || k === 'Alt') e.preventDefault();
      if (k === 'Control' && !G.electron && !document.fullscreenElement && !G.ctrlWarned) { G.ctrlWarned = true; bus.emit('ctrlwarn'); }
      if (k === 'Enter') { G.skip(); if (!G.me || G.mode !== 'play') return; }
      if (k === 'Escape') bus.emit('menu');
      if (k === '2') { G.tags = !G.tags; bus.emit('tags', { on: G.tags }); }
      if (k === 't') { bus.emit('chat'); e.preventDefault(); }
      if (k === 'y') { G.skip(); if (!G.me || G.mode !== 'play') return; }
      if (k === 'g' && G.state.phase === 'reveal' && !G.liked) { G.liked = true; var lt = null, ld = 1e9; cats().forEach(function (c) { if (c === G.me || c.id === (G.me.pid || G.me.id) || !c.c.root.visible) return; var q = G.project(c), dd = q.vis ? Math.hypot(q.x - G.vw / 2, q.y - G.vh / 2) : 1e8; if (dd < ld) { ld = dd; lt = c; } }); if (lt) giveLike(lt.id, G.me.id); }
      if (k === 'Tab' && G.state.phase === 'reveal') bus.emit('sidepanel');
      if (G.fly) { if (k === '4') { if (G.fly.hide) { G.follow = null; G.fly.move = !G.fly.move; bus.emit('spectate', { hide: true, move: G.fly.move }); } else spectateNext(); } /* original: 5 detaches the camera from the body, 4 inside it turns free flight on; X is ignored in here */ if (k === '5') { if (G.fly.hide) { G.fly = null; bus.emit('mode2'); bus.emit('viewlock', { on: G.viewLock }); } else { G.follow = null; bus.emit('follow', { name: null }); } } return; }
      var me = G.me;
      if (me.team === 'cat' && !me.out) {
        if (k === 'f') G.setPaintMode(!G.paint.on);
        if (k === 'r') bus.emit('wheel', { open: true });
        if (k === '1') G.meow();
        if (k === '3') G.setSeeThrough(!G.seeThrough);
        if (k === 'q') G.decoy();
        if (k === 'x') G.recallDecoys();
        if (k === 'z' && (e.ctrlKey || e.metaKey || G.paint.on)) { G.undo(); e.preventDefault(); }
        if (k === '[') bus.emit('brush', { d: -0.01 }); if (k === ']') bus.emit('brush', { d: 0.01 });
        if (k === ' ' && !G.paint.on && !me.cling) jump(); // jump INTO a wall or an object to stick to it (in paint mode Space is the 3D eyedropper)
        if (k === '5') { G.fly = { p: camera.position.clone(), yaw: G.cam.yaw + Math.PI, pitch: -G.cam.pitch, hide: true }; bus.emit('spectate', { hide: true }); return; } // free camera while hiding: the body stays where it is
        if (k === 'Shift' && me.cling) release(me);
        if (k === 'v' && G.paint.on) { G.paint.flat = !G.paint.flat; bus.emit('shading', { on: !G.paint.flat }); }
      } else if (me.team === 'dog') { if (k === ' ' && !me.cling) jump(); if (k === 'Shift' && me.cling) release(me); }
    });
    window.addEventListener('keyup', function (e) { var k = e.key.length === 1 ? e.key.toLowerCase() : e.key; G.keys[k] = false; if (k === 'r') bus.emit('wheel', { open: false }); });
    window.addEventListener('blur', function () { G.keys = {}; });
    canvas.addEventListener('contextmenu', function (e) { e.preventDefault(); });
    canvas.addEventListener('mousedown', function (e) {
      G.mouse.down[e.button] = true; G.mouse.x = e.clientX; G.mouse.y = e.clientY;
      if (SG.audio) SG.audio.unlock();
      if (G.mode !== 'play' || !G.me) return;
      var me = G.me;
      if (G.fly) { if (e.button === 0 && G.follow) spectateNext(); G.orbiting = true; return; }
      if (me.team === 'cat') {
        if (G.paint.on && !me.out) {
          if (e.button === 0 && !e.altKey) {
            if (G.keys[' '] || G.paint.tool === 'pick') { G.pickAt(e.clientX, e.clientY, !e.shiftKey); /* the 3D eyedropper takes the surface's base colour + roughness + metallic (the developer's own description); with Shift it takes the screen colour instead */ if (G.paint.tool === 'pick') { G.paint.tool = 'brush'; bus.emit('tool', { tool: 'brush' }); } return; }
            if (e.detail === 2 && !G.paint.pattern && G.fillPartAt(e.clientX, e.clientY)) return; // double-click: fill that body part
            if (me.c._fx && me.c._fx.fillJob) G.fx.finishFill(me.c);
            me.c.beginStroke(); G.paint.last = null; G.stroking = paintAt(e.clientX, e.clientY, true); if (!G.stroking) me.c.endStroke(); // a stroke may start beside the body and run onto it
          } else if (e.button === 2 && !e.altKey) G.sizing = true; // right-drag changes the brush size
          else if (e.button === 2) G.zooming = true;                // Alt + right-drag zooms
          else G.orbiting = true;                                  // middle-drag or Alt+drag turns the camera
        } else {
          if (e.button === 0) { if (!Q.get('nolock') && document.pointerLockElement !== canvas) { lock(); return; } G.orbitDrag = false; } // the click that takes the pointer is swallowed
          if (e.button === 2 && !me.out) { G.rmb = [e.clientX, e.clientY]; G.viewLock = true; bus.emit('viewlock', { on: true }); } G.orbiting = true; G.orbitDrag = false; // HOLD right mouse = the body's facing is locked while you move and look
        }
      } else if (me.team === 'dog' && G.state.phase === 'seek') {
        if (e.button === 0) { if (!Q.get('nolock') && document.pointerLockElement !== canvas) { lock(); return; } shootPlayer(); }
        if (e.button === 2) G.third = !G.third;
      } else G.orbiting = true;
    });
    window.addEventListener('mouseup', function (e) {
      G.mouse.down[e.button] = false;
      if (G.stroking) { G.stroking = false; pushUndo(G.me.c.endStroke()); bus.emit('strokeEnd', { undo: G.paint.undo.length }); }
      if (e.button === 2 && G.rmb) { G.rmb = null; if (G.viewLock) { G.viewLock = false; bus.emit('viewlock', { on: false }); } }
      G.orbiting = false; G.sizing = false; G.zooming = false;
    });
    window.addEventListener('mousemove', function (e) {
      var dx = e.movementX || (e.clientX - G.mouse.x), dy = e.movementY || (e.clientY - G.mouse.y), locked = document.pointerLockElement === canvas; G.mouse.x = e.clientX; G.mouse.y = e.clientY;
      if (G.mode === 'play' && G.me && G.me.team === 'dog' && G.state.phase !== 'reveal' && !G.fly) { if (locked || G.mouse.down[0] || G.mouse.down[2]) { var sn = 0.0032 * G.opts.sens; G.me.yaw -= dx * sn; G.me.pitch = Math.max(-1.3, Math.min(1.3, (G.me.pitch || 0) - dy * sn * (G.opts.invertY ? -1 : 1))); } return; }
      if (G.stroking) paintAt(e.clientX, e.clientY, false);
      else if (G.sizing) bus.emit('brush', { d: dx * 0.0006 });
      else if (G.zooming) G.cam.dist = Math.max(0.6, Math.min(8, G.cam.dist * (1 + dy * 0.006)));
      else if (G.fly && (G.orbiting || G.mouse.down[0] || G.mouse.down[2] || locked)) { G.fly.yaw -= dx * 0.004; G.fly.pitch = Math.max(-1.4, Math.min(1.4, G.fly.pitch - dy * 0.004)); }
      else if (G.orbiting || (locked && G.mode === 'play' && !G.paint.on)) { G.cam.yaw -= dx * 0.006; G.cam.pitch = Math.max(G.me && G.me.cling ? -1.25 : -0.25, Math.min(1.35, G.cam.pitch + dy * 0.005)); G.looked = true; }
    });
    canvas.addEventListener('wheel', function (e) {
      e.preventDefault();
      if (G.paint.on && e.shiftKey && G.me && G.me.team === 'cat') bus.emit('brush', { d: e.deltaY < 0 ? 0.01 : -0.01 });
      else G.cam.dist = Math.max(0.6, Math.min(8, G.cam.dist * (e.deltaY > 0 ? 1.1 : 0.9)));
    }, { passive: false });
  }
  function jump() {
    var m = G.me; if (m.cling || m.air || G.state.phase === 'reveal') return;
    var h = m.team === 'dog' ? RULES.dog.jumpHeight : m.spec.leg < 0.1 ? RULES.cat.jumpHeightShortLeg : RULES.cat.jumpHeight;
    m.vy = Math.sqrt(2 * 9.8 * h); m.y += 0.01; m.air = true; if (m.team === 'cat' && m.c.pose === 'crouch') G.setPose('stand'); bus.emit('jump'); /* a pose survives jumping and climbing */
  }
  function shootPlayer() {
    var m = G.me; if (!m || m.team !== 'dog' || G.state.phase !== 'seek') return;
    var o = V(), d = V(); camera.getWorldPosition(o); camera.getWorldDirection(d);
    if (G.third) { o.set(m.x, m.y + m.eyeH, m.z); d.set(Math.sin(m.yaw) * Math.cos(m.pitch), Math.sin(m.pitch), Math.cos(m.yaw) * Math.cos(m.pitch)); }
    if (fire(m, o, d)) { G.recoil = 1; G.punch = 1; gunSplat(G.vmBlobs + 1); gunSplat(G.vmBlobs + 7); }
  }
  /* 3: draw your own cat through objects (so you can see how you sit inside furniture) */
  G.setSeeThrough = function (on) {
    var me = G.me; if (!me || me.team !== 'cat') return; G.seeThrough = on;
    if (on && !me.ghost) { var g = new THREE.SkinnedMesh(me.c.skin.geometry, new THREE.MeshBasicMaterial({ map: me.c.skin.material.map, transparent: true, opacity: 0.55, depthTest: false, depthWrite: false })); g.bind(me.c.skin.skeleton, new THREE.Matrix4()); g.frustumCulled = false; g.renderOrder = 50; g.layers.set(1); me.c.root.add(g); me.ghost = g; }
    if (me.ghost) me.ghost.visible = on; bus.emit('seethrough', { on: on });
  };
  /* 4: follow the next player while spectating, 5: back to the free camera */
  function spectateNext() { var list = G.ents.filter(function (e) { return e.c.root.visible && !e.out; }); if (!list.length) return; var i = list.indexOf(G.follow); G.follow = list[(i + 1) % list.length]; bus.emit('follow', { name: G.follow.name }); }

  /* ------------------------------------------------------------------ update */
  function update(dt) {
    if (G.hitstop > 0) { G.hitstop -= dt; dt *= 0.05; }
    G.time += dt; G.simT += dt;
    var vx0 = room.vac.x, vz0 = room.vac.z;
    room.update(G.simT);
    var vdx = room.vac.x - vx0, vdz = room.vac.z - vz0;
    var st = G.state, me = G.me, k = G.keys;
    if (G.mode === 'play' && st) {
      if (G.lobby) { var Lb = G.lobby; Lb.t -= dt; Lb.on = !!me && !me.cling && Math.hypot(me.x - Lb.x, me.z - Lb.z) < Lb.r;
        if (Lb.t <= 0) { var sd = Lb.on ? 'dog' : 'cat'; bus.emit('lottery', { side: sd }); G.start(G.settings.mode === 'double' ? 'cat' : sd); return; } }
      if (st.phase !== 'lobby') dispatch({ type: 'tick', dt: dt });
      var dcd = 0, dfree = false; G.decoySlots.forEach(function (sl) { sl.cd = Math.max(0, sl.cd - dt); if (!sl.e) { dcd = dfree ? Math.min(dcd, sl.cd) : sl.cd; dfree = true; } }); G.decoyCd = dcd; // shortest wait among the empty slots (0 when both clones are out)
      if (me && !me.out && st.phase !== 'reveal' && !G.fly) {
        var f = (k.w || k.ArrowUp && me.team === 'cat' ? 1 : 0) - (k.s || k.ArrowDown && me.team === 'cat' ? 1 : 0), s = (k.d ? 1 : 0) - (k.a ? 1 : 0);
        if (me.team === 'cat') {
          var cy = G.cam.yaw, mvx = -Math.sin(cy) * f + Math.cos(cy) * s, mvz = -Math.cos(cy) * f - Math.sin(cy) * s, l = Math.hypot(mvx, mvz), px = me.x, pz = me.z;
          if (!me.cling && l <= 0.01 && (me.c.pose === 'crouch') !== !!(k.c || k.Control) && (me.c.pose === 'crouch' || me.c.pose === 'stand')) me.c.setPose(me.c.pose === 'crouch' ? 'stand' : 'crouch');
          if (!me.cling && l <= 0.01 && me.c.pose !== 'stand' && me.c.pose !== 'crouch' && !G.viewLock && !G.paint.on && G.looked && G.mouse.down[0]) me.yaw = turn(me.yaw, G.cam.yaw + Math.PI, dt * 10); /* drag with the left button to fine-tune a posed body's facing */
          G.looked = false;
          if (me.cling) { clingMove(me, f, s, dt);
            if (me.cling && !me.speed && G.looked && !G.viewLock && !G.paint.on) { // idle on a surface: the head follows where the camera looks, right mouse locks it
              var cn = me.cling.n, cp = G.cam.pitch, fx = -Math.sin(cy) * Math.cos(cp), fy = -Math.sin(cp), fz = -Math.cos(cy) * Math.cos(cp), dn = fx * cn[0] + fy * cn[1] + fz * cn[2]; fx -= cn[0] * dn; fy -= cn[1] * dn; fz -= cn[2] * dn; var fl = Math.hypot(fx, fy, fz); if (fl > 0.3) me.cling.f = [fx / fl, fy / fl, fz / fl]; } }
          else if (G.mouse.down[0] && !G.paint.on && !G.orbitDrag && (k.a || k.d) && !f) { me.yaw += ((k.a ? 1 : 0) - (k.d ? 1 : 0)) * dt * 3.2; me.velx = me.velz = 0; } // hold left mouse + A/D: turn the body on the spot
          else if (l > 0.01 || Math.hypot(me.velx || 0, me.velz || 0) > 0.05) {
            if (l > 0.01) { mvx /= l; mvz /= l; } else { mvx = mvz = 0; }
            var posed = me.c.pose !== 'stand' && me.c.pose !== 'crouch', crouch = !posed && (k.c || k.Control), sp = posed ? (k.Alt ? RULES.cat.nudgeSpeed : RULES.cat.posedSpeed) : crouch ? RULES.cat.crouchSpeed : k.Shift ? RULES.cat.runSpeed : RULES.cat.walkSpeed;
            // velocity eases toward the wanted velocity: quick start, a short skid when you let go
            var ka = 1 - Math.exp(-dt * (l > 0.01 ? RULES.cat.accel : RULES.cat.decel)); me.velx = (me.velx || 0) + (mvx * sp - (me.velx || 0)) * ka; me.velz = (me.velz || 0) + (mvz * sp - (me.velz || 0)) * ka;
            var vl = Math.hypot(me.velx, me.velz); if (l <= 0.01 && vl < 0.25) { me.velx = me.velz = 0; vl = 0; } sp = vl; if (vl > 1e-4) { mvx = me.velx / vl; mvz = me.velz / vl; }
            G.runK = (G.runK || 0) + ((k.Shift && l > 0.01 ? 1 : 0) - (G.runK || 0)) * Math.min(1, dt * 5);
            if (l > 0.01 && !posed && me.c.pose !== (crouch ? 'crouch' : 'stand')) { me.c.setPose(crouch ? 'crouch' : 'stand'); bus.emit('pose', { pose: 'stand' }); }
            me.hitWallX = me.hitWallZ = 0; me.hitPlat = null; moveEnt(me, mvx * sp * dt, mvz * sp * dt, dt); if (me.hitWallX) me.velx = 0; if (me.hitWallZ) me.velz = 0; if (!posed && !G.viewLock && !G.mouse.down[2] && l > 0.01) me.yaw = turn(me.yaw, Math.atan2(mvx, mvz), dt * 14); if (me.air && me.vy > 0 && !me.cling) tryAttach(me, 0, 0, [[1, 1]]); /* jumping up into a ceiling or the underside of a shelf sticks too */
            if (me.air && me.hitPlat && me.hitPlat !== true && me.y - room.groundAt(me.x, me.z, me.y + 0.1, 0) > 0.2) tryAttach(me, me.hitWallX || 0, me.hitWallX ? 0 : me.hitWallZ, [[me.hitWallX ? 0 : 2, (me.hitWallX || me.hitWallZ) > 0 ? 1 : -1]]); // jumping at anything tall sticks to it
            if (G.guide === 0 && (G.moved = (G.moved || 0) + sp * dt) > 1.5) setGuide(1);
          }
          me.speed = Math.hypot(me.x - px, me.z - pz) / Math.max(dt, 1e-4);
          stuckWatch(me, l > 0.01 && !me.cling, dt);
          if (me.onVac && me.speed < 0.05) { me.x += vdx; me.z += vdz; } // riding the robot vacuum counts as standing still
        } else {
          var yw = me.yaw; if (k.ArrowLeft) me.yaw += dt * 1.9; if (k.ArrowRight) me.yaw -= dt * 1.9; if (k.ArrowUp) me.pitch = Math.min(1.2, me.pitch + dt * 1.2); if (k.ArrowDown) me.pitch = Math.max(-1.2, me.pitch - dt * 1.2);
          var dcr = k.Control; me.crouch = !!dcr; me.rearT = k.c && !me.cling ? 1 : 0; /* hold C: rear up for a higher look (the body module's rearUp) */
          if (me.cling) { var cy0 = G.cam.yaw; G.cam.yaw = me.yaw + Math.PI; clingMove(me, f, s, dt); G.cam.yaw = cy0; }
          else if (st.phase === 'seek') { me.hitWallX = me.hitWallZ = 0; me.hitPlat = null; var sp2 = (k.Shift ? RULES.dog.runSpeed : RULES.dog.speed) * (dcr ? RULES.dog.crouchSpeed : 1), mx = Math.sin(yw) * f - Math.cos(yw) * s, mz = Math.cos(yw) * f + Math.sin(yw) * s, pl = Math.hypot(mx, mz), qx = me.x, qz = me.z, dka = 1 - Math.exp(-dt * (pl > 0.01 ? RULES.cat.accel : RULES.cat.decel)); me.velx = (me.velx || 0) + ((pl > 0.01 ? mx / pl * sp2 : 0) - (me.velx || 0)) * dka; me.velz = (me.velz || 0) + ((pl > 0.01 ? mz / pl * sp2 : 0) - (me.velz || 0)) * dka; if (pl <= 0.01 && Math.hypot(me.velx, me.velz) < 0.2) me.velx = me.velz = 0; /* the dog eases into and out of its speed like the cat does: no instant starts, stops or reversals */ if (me.velx || me.velz) moveEnt(me, me.velx * dt, me.velz * dt, dt); if (me.hitWallX) me.velx = 0; if (me.hitWallZ) me.velz = 0; me.speed = Math.hypot(me.x - qx, me.z - qz) / Math.max(dt, 1e-4); stuckWatch(me, pl > 0.01, dt); if (me.air && me.hitPlat && me.hitPlat !== true && me.y - room.groundAt(me.x, me.z, me.y + 0.1, 0) > 0.2) tryAttach(me, me.hitWallX || 0, me.hitWallX ? 0 : me.hitWallZ, [[me.hitWallX ? 0 : 2, (me.hitWallX || me.hitWallZ) > 0 ? 1 : -1]]); if (me.air && me.vy > 0 && !me.cling) tryAttach(me, 0, 0, [[1, 1]]); }
          // the player dog also feeds the 見落とし score: pixels of each cat actually visible on this dog's screen
          G.ovT = (G.ovT || 0) - dt; if (G.ovT <= 0 && st.phase === 'seek') { G.ovT = RULES.overlooked.tickEverySec; overlookTick(me, G.third ? dogCam(me) : camera); }
        }
      }
      G.ents.forEach(function (e) { if (e.bot && e.team === 'dog') botDog(e, dt); }); botRelocate(dt);
      roundExtras(dt);
    }
    // physics + animation for everyone
    G.ents.forEach(function (e) { if (e.team !== 'dog' || e.eyeLo == null) return; e.rear += ((e.rearT || 0) - e.rear) * Math.min(1, dt * 9); if (Math.abs(e.rear - (e.rearT || 0)) < 0.004) e.rear = e.rearT || 0; e.c.rearUp = e.rear; var eh = e.eyeLo + (e.eyeHi - e.eyeLo) * e.rear; e.eyeH0 = eh; e.eyeH += ((e.crouch ? Math.max(0.1, eh * 0.8) : eh) - e.eyeH) * Math.min(1, dt * 14); });
    var bumpers = [];
    for (var i = 0; i < G.ents.length; i++) {
      var e = G.ents[i];
      if (G.mode === 'play') physEnt(e, dt);
      e.c.speed = e.team === 'cat' && e.c.pose !== 'stand' && e.c.pose !== 'crouch' ? 0 : e.speed || 0; e.c.air = e.air ? 1 : 0;
      var dy = e.yaw - (e.pyaw == null ? e.yaw : e.pyaw); while (dy > Math.PI) dy -= 2 * Math.PI; while (dy < -Math.PI) dy += 2 * Math.PI; e.c.turn = dt > 0 ? dy / dt : 0; e.pyaw = e.yaw;
      // GDD hider-cat: a posed cat is perfectly still for everyone but its owner
      if (e.team === 'cat' && e.c.flatU) { var posedF = e.c.pose !== 'stand' && e.c.pose !== 'crouch', thin = posedF && !e.air && e.c.measure && e.c.measure().size[1] < 0.13, fT = (e.cling || thin) && posedF ? 0.9 : posedF && !e.air ? 0.45 : 0; /* OURS (labelled): a posed body that lies flat on a floor, wall or ceiling is shaded like that surface and casts no shadow */ e.c.flatU.value += (fT - e.c.flatU.value) * Math.min(1, dt * 6); if (e.cling) e.c.flatN.value.fromArray(e.cling.n); else e.c.flatN.value.set(0, 1, 0); e.c.skin.castShadow = !((e.cling || thin) && posedF); }
      if (e === me && e.team === 'cat') e.c.frozen = (e.c.pose !== 'stand' && e.c.pose !== 'crouch' || (G.paint.on && !(e.speed > 0.05) && !e.air)) || !!e.out; /* and it holds still under the brush */ /* your own posed body is perfectly still too */
      if (e.team === 'cat' && e !== me) { e.c.frozen = (e.c.pose !== 'stand' && !e.walk) || !!e.out || (G.state && G.state.mode === 'double' && G.state.phase === 'seek'); e.c.faceSkin.visible = false; } // a posed cat shows no eyes, nose or whiskers to anyone else
      place(e);
      e.c.update(dt, rnd);
      if (!e.out && (e.speed > 0.05 || e.air)) bumpers.push({ x: e.x, y: e.y, z: e.z, r: e.team === 'dog' ? 0.3 : RULES.cat.bumpRadius, speed: e.speed || 0 });
    }
    G.decoys.forEach(function (d) { if (d.c.root.visible) d.c.update(dt, rnd); });
    bumpers.push({ x: room.vac.x, y: 0, z: room.vac.z, r: 0.2, speed: 0.4 });
    room.stepTriggers(dt, G.ents.filter(function (e) { return !e.fp || true; }));
    room.stepProps(dt, bumpers, function (kp, landed) { bus.emit('bump', { type: kp.type, landed: !!landed, x: kp.x, z: kp.z }); if (!landed && !kp.shot && G.settings.knockNoise) dogsOf().forEach(function (d) { if (d.ai && !d.ai.heard && Math.hypot(d.x - kp.x, d.z - kp.z) < 6) { d.ai.heard = [kp.x, kp.z]; d.ai.heardT = 0; } }); });
    if (G.mode === 'play' && st && st.phase === 'reveal' && G.likeT != null) { G.likeT -= dt; if (G.likeT <= 0) { G.likeT = 1.2 + rnd() * 2.5; var bl = G.ents.filter(function (e) { return e.bot && !e.likedOnce && !e.decoyOf; }), cl = cats().filter(function (c) { return c.c.root.visible; }); if (bl.length && cl.length > 1) { var bb = bl[Math.floor(rnd() * bl.length)], best = cl.filter(function (c) { return c !== bb && c.id !== bb.pid; }).sort(function (a, b2) { return ((st.players[b2.id] || {}).score || 0) - ((st.players[a.id] || {}).score || 0); }); bb.likedOnce = true; if (best.length) giveLike(best[Math.floor(rnd() * Math.min(3, best.length))].id, bb.id); } else G.likeT = null; } }
    if (G.mode === 'play' && st && st.phase === 'reveal') { var fl = 0.5 + 0.5 * Math.sin(G.time * 7); G.ents.forEach(function (e) { if (e.team === 'cat' && e.found != null) e.c.glow.value.setRGB(e.found ? 0.02 : 0.85, e.found ? 0.22 : 0.05, e.found ? 0.95 : 0.03).multiplyScalar(0.25 + 0.75 * fl); }); G.ents.concat(G.decoys).forEach(function (e) { if (e.shell) e.shell.material.opacity = 0.25 + 0.5 * fl; }); }
    stepBalls(dt); stepConfetti(dt); stepVanish(dt);
    updateCamera(dt);
    paintFrame(dt);
    if (G.mode === 'play' && st) bus.emit('frame', { left: st.left, phase: st.phase });
  }
  function stuckWatch(e, pushing, dt) { if (pushing && e.speed < 0.08 && !e.air && !G.unstuckOff) { e.stuckT = (e.stuckT || 0) + dt; if (e.stuckT > 0.8) { e.stuckT = 0; var P0 = room.platforms, inside = pushOut(e.x, e.z, e.rad * 0.6, e.y + e.step, e.y + (e.h || 0.2), _po); if (inside) unstick(e); } } else e.stuckT = 0; } // only when the body is actually wedged inside something, not when it simply faces a wall
  /* per-frame paint feel: brush cursor on the body, droplets, fill wipe, "white left" */
  function sideBlocked(ctr, d) { var r = 0.34 * (G.me.size || 1), x = ctr.x + d[0] * r, y = ctr.y + d[1] * r, z = ctr.z + d[2] * r; if (y < room.base(x, z) + 0.01) return true; tmp2.set(x, y, z); return !!segSolid(ctr, tmp2, 0) || room.segWalls(ctr.x, ctr.y, ctr.z, x, y, z) < 0.999; }
  function paintFrame(dt) {
    var me = G.me, fx = G.fx; if (!fx) return;
    var on = G.mode === 'play' && me && me.team === 'cat' && G.paint.on && !me.out && !G.fly;
    fx.update(dt, me && me.team === 'cat' ? me.c : null);
    fx.hi += ((on && G.keys.h ? 1 : 0) - fx.hi) * Math.min(1, dt * 14);
    var cu = fx.cur, was = cu.on; cu.on = false; if (!on) { if (G.cur3d) { G.cur3d = false; bus.emit('cursor3d', { on: false }); } return; }
    if (!me.c._fx) fx.attach(me.c);
    var P = G.paint;
    if (G.sizing) cu.on = was; // the ring stays where it was while its size is dragged
    else if (G.stroking && SP.last) { cu.on = true; cu.pos.copy(SP.last); }
    else if (!G.orbiting && !G.zooming) { var hit = brushHit(G.mouse.x, G.mouse.y); if (hit && !hit.blocked) { cu.on = true; cu.pos.copy(hit.point); } }
    cu.c = me.c; cu.cam = camera; cu.r = P.size; cu.hard = P.hard ? RULES.paint.hardnessHard : RULES.paint.hardnessSoft; cu.rgb = P.rgb; cu.dot = !(G.keys[' '] || P.tool === 'pick');
    if (cu.on !== !!G.cur3d) { G.cur3d = cu.on; bus.emit('cursor3d', { on: cu.on }); }
    G.wlT = (G.wlT || 0) - dt; if (G.wlT <= 0) { G.wlT = 0.1; var pct = fx.whiteLeft(me.c, sideBlocked); if (pct !== G.whiteLeft) { G.whiteLeft = pct; bus.emit('whiteLeft', { pct: pct }); } }
  }
  /* forced meow, suspicion meter, buried-too-deep warning, torch */
  var torch = null;
  function roundExtras(dt) {
    var st = G.state, me = G.me, S = G.settings;
    if (st.phase === 'seek' && S.forcedMeow) { G.meowT -= dt; if (G.meowT <= 0) { G.meowT = S.meowEvery; cats().forEach(function (c) { if (!c.out && !c.decoyOf && c.c.root.visible) meowFrom(c, true); }); } }
    if (me && me.team === 'cat' && st.phase === 'seek') { var v = 0, seen = false; dogsOf().forEach(function (d) { if (!d.ai) return; v = Math.max(v, d.ai.sus.you || 0); G.decoys.forEach(function (q) { v = Math.max(v, d.ai.sus[q.id] || 0); }); seen = seen || d.ai.seenMe; }); G.susT = (G.susT || 0) - dt; if (G.susT <= 0) { G.susT = 0.25; bus.emit('suspicion', { v: v, seen: seen }); } }
    if (me && me.team === 'cat' && !me.out && st.phase === 'seek') { // how close to being found: drives heartbeat + vignette (feedback only)
      var dz = 0, aim = false;
      dogsOf().forEach(function (d) {
        var dist = Math.hypot(d.x - me.x, d.z - me.z), ang = Math.atan2(me.x - d.x, me.z - d.z) - d.yaw; while (ang > Math.PI) ang -= 2 * Math.PI; while (ang < -Math.PI) ang += 2 * Math.PI;
        var facing = Math.abs(ang) < 0.7 ? 1 : 0.45, v = Math.max(0, 1 - dist / 6.5) * facing; if (d.ai && (d.ai.mode === 'stare' || d.ai.mode === 'aim') && (d.ai.target === me || (d.ai.target && d.ai.target.decoyOf === 'you'))) { v = Math.max(v, 0.85); aim = true; }
        if (d.ai) v = Math.max(v, d.ai.sus.you || 0); dz = Math.max(dz, v);
        if (dist < RULES.feel.nearMissDogM && !aim) d.nearMe = true; else if (d.nearMe && dist > RULES.feel.nearMissDogM + 0.8) { d.nearMe = false; if (!me.out) bus.emit('nearmiss', { kind: 'dog' }); }
      });
      G.dangerT = (G.dangerT || 0) - dt; if (G.dangerT <= 0) { G.dangerT = 0.2; bus.emit('danger', { v: Math.min(1, dz), aim: aim }); }
    }
    if (st.phase === 'seek') cats().forEach(function (c) { // bots have small tells with long random gaps (bots only)
      if (!c.bot || c.out || c.decoyOf || !c.c.root.visible || st.mode === 'double') return;
      if (c.fidT == null) c.fidT = RULES.feel.fidgetMinSec + rnd() * (RULES.feel.fidgetMaxSec - RULES.feel.fidgetMinSec);
      c.fidT -= dt; if (c.fidT <= 0) { c.fidT = RULES.feel.fidgetMinSec + rnd() * (RULES.feel.fidgetMaxSec - RULES.feel.fidgetMinSec); c.c.fidget = 0.7; bus.emit('fidget', { id: c.id, x: c.x, z: c.z, d: me ? Math.hypot(c.x - me.x, c.z - me.z) : 99, sneeze: rnd() < 0.35 }); }
      if (me && me.team === 'dog' && me.speed > 1 && Math.hypot(c.x - me.x, c.z - me.z) < 1.4 && !(c.gigT > 0)) { c.gigT = 14; bus.emit('giggle', { id: c.id }); }
      if (c.gigT > 0) c.gigT -= dt;
    });
    // a cat pushed too far into an object gets a warning, then is exposed (GDD round-flow, edge cases)
    if (me && me.team === 'cat' && !me.out && st.phase !== 'reveal') {
      G.embedC = (G.embedC || 0) - dt;
      if (G.embedC <= 0) { G.embedC = 0.25; var dep = embedDepth(me); me.embed = dep > me.rad * RULES.cat.embedRatio; if (me.embed && !G.embedT) bus.emit('embed', { state: 'warn' }); if (!me.embed && me.exposed) { me.exposed = false; me.c.glow.value.setRGB(0, 0, 0); bus.emit('embed', { state: 'ok' }); } }
      if (me.embed) { G.embedT += dt; if (G.embedT > RULES.cat.embedSec && !me.exposed) { me.exposed = true; me.c.glow.value.setRGB(0.9, 0.45, 0.05); bus.emit('embed', { state: 'exposed' }); } } else G.embedT = 0;
    }
    // torch for the leading dog at night
    if (!torch) { torch = new THREE.SpotLight(0xfff0d0, 0, 10, 0.42, 0.55, 1.5); torch.layers.set(1); torch.target.layers.set(1); scene.add(torch, torch.target); G.torch = torch; }
    var lead = me && me.team === 'dog' ? me : dogsOf()[0];
    torch.intensity = S.night && lead && st.phase !== 'prep' ? 46 : 0;
    if (lead) { var dy = Math.sin(lead.pitch || 0), dc = Math.cos(lead.pitch || 0); torch.position.set(lead.x, lead.y + lead.eyeH, lead.z); torch.target.position.set(lead.x + Math.sin(lead.yaw) * dc * 3, lead.y + lead.eyeH + dy * 3 - 0.2, lead.z + Math.cos(lead.yaw) * dc * 3); }
  }
  function embedDepth(e) { // how deep the body centre sits inside any solid
    var c = e.c.center(tmp2), best = 0, P = room.platforms;
    for (var i = 0; i < P.length; i++) { var p = P[i]; if (c.x <= p.x0 || c.x >= p.x1 || c.z <= p.z0 || c.z >= p.z1 || c.y <= p.y0 || c.y >= p.y1) continue; var d = Math.min(c.x - p.x0, p.x1 - c.x, c.z - p.z0, p.z1 - c.z, p.y1 - c.y); if (d > best) best = d; }
    return best;
  }
  G.embedDepth = embedDepth;
  /* ---- climb and stick: every solid is an axis-aligned box, so every surface is one of six directions.
     While stuck, e.x/y/z is the contact point on the surface and e.cling = { n: surface normal, f: where the head points }.
     Nothing moves unless a key is held: no stamina, no sliding. */
  var FLOOR = { floor: true };
  function solidAt(x, y, z) { if (y < room.base(x, z)) return FLOOR; var P = room.platforms; for (var i = 0; i < P.length; i++) { var p = P[i]; if (x > p.x0 && x < p.x1 && z > p.z0 && z < p.z1 && y > p.y0 && y < p.y1) return p; } return null; }
  /* does the segment a -> b (stopping `back` short of b) pass through any solid box? */
  function segSolid(a, b, back) {
    var dx = b.x - a.x, dy = b.y - a.y, dz = b.z - a.z, L = Math.sqrt(dx * dx + dy * dy + dz * dz), tmax = Math.max(0, 1 - back / Math.max(L, 1e-6)), P = room.platforms;
    for (var i = 0; i < P.length; i++) { var p = P[i], t0 = 0, t1 = tmax, lo, hi, o, d, k, ok = true;
      for (k = 0; k < 3 && ok; k++) { o = k === 0 ? a.x : k === 1 ? a.y : a.z; d = k === 0 ? dx : k === 1 ? dy : dz; lo = pLo(p, k); hi = pHi(p, k);
        if (Math.abs(d) < 1e-9) { if (o < lo || o > hi) ok = false; } else { var u0 = (lo - o) / d, u1 = (hi - o) / d; if (u0 > u1) { var sw = u0; u0 = u1; u1 = sw; } if (u0 > t0) t0 = u0; if (u1 < t1) t1 = u1; if (t0 > t1) ok = false; } }
      if (ok) return p; }
    return null;
  }
  G.segSolid = segSolid;
  function pLo(p, a) { return a === 0 ? p.x0 : a === 1 ? p.y0 : p.z0; }
  function pHi(p, a) { return a === 0 ? p.x1 : a === 1 ? p.y1 : p.z1; }
  G.solidAt = solidAt;
  function tryAttach(e, dx, dz, only) {
    if (e.cling || e.bot && e.team === 'dog') return false; // hunters climb too (original); bot dogs stay on the floor
    var rad = e.rad, c = [e.x, e.y + rad, e.z], reach = rad + 0.16, ax = Math.abs(dx) >= Math.abs(dz) ? 0 : 2;
    var dirs = only || [[ax, (ax ? dz : dx) >= 0 ? 1 : -1], [2 - ax, (ax ? dx : dz) >= 0 ? 1 : -1], [1, 1]];
    for (var i = 0; i < dirs.length; i++) {
      var a = dirs[i][0], sg = dirs[i][1], q = c.slice(); q[a] += sg * reach; if (a === 1) q[1] += rad * 0.8; // a ceiling or shelf underside just above the head
      var p = solidAt(q[0], q[1], q[2]); if (!p || p === FLOOR) continue;
      if (a !== 1 && p.y1 - e.y < 0.3 && e.y - room.groundAt(e.x, e.z, e.y + 0.1, 0) < 0.05) continue; // standing next to something low: that is a step, not a wall
      var n = [0, 0, 0]; n[a] = -sg; c[a] = sg > 0 ? pLo(p, a) : pHi(p, a);
      e.x = c[0]; e.y = c[1]; e.z = c[2]; e.cling = { n: n, f: a === 1 ? [Math.sin(e.yaw), 0, Math.cos(e.yaw)] : [0, 1, 0] }; e.vy = 0; e.air = false; e.speed = 0;
      if (e === G.me) bus.emit('cling', { on: true }); return true;
    }
    return false;
  }
  G.tryAttach = tryAttach;
  function release(e) {
    if (!e.cling) return; var n = e.cling.n;
    e.x += n[0] * e.rad; e.z += n[2] * e.rad; e.y += n[1] < 0 ? -e.rad * 2.2 : -e.rad * 0.6; if (n[0] || n[2]) e.yaw = Math.atan2(-n[0], -n[2]);
    e.cling = null; e.vy = 0; e.air = true; if (e === G.me) bus.emit('cling', { on: false });
  }
  G.release = release;
  function clingMove(e, f, s, dt) {
    var k = G.keys, cl = e.cling, n = cl.n, rad = e.rad, sp = RULES.cat.clingSpeed, mv = [0, 0, 0], cy = G.cam.yaw, a, i;
    if (n[1] === 0) { mv[1] = (k[' '] || f > 0 ? 1 : 0) - (k.Control || f < 0 ? 1 : 0); var ta = n[0] ? 2 : 0, rr = ta ? -Math.sin(cy) : Math.cos(cy); mv[ta] = s * (rr >= 0 ? 1 : -1); }
    else { mv[0] = -Math.sin(cy) * f + Math.cos(cy) * s; mv[2] = -Math.cos(cy) * f - Math.sin(cy) * s; }
    // going round a corner keeps you going: while the same keys stay held, the direction is carried over the edge (wall -> ceiling -> beam ...)
    var sig = [f, s, k[' '] ? 1 : 0, k.Control ? 1 : 0].join(); if (cl.carry && cl.carry.sig === sig && Math.hypot(mv[0], mv[1], mv[2]) > 0.01) mv = cl.carry.mv.slice(); else cl.carry = null;
    var len = Math.hypot(mv[0], mv[1], mv[2]); e.speed = 0; if (len < 0.01) return;
    var c = [e.x + n[0] * rad, e.y + n[1] * rad, e.z + n[2] * rad], moved = false, lock = G.viewLock && e === G.me;
    for (a = 0; a < 3; a++) {
      if (!mv[a] || n[a]) continue;
      var step = mv[a] / len * sp * dt, sg = step > 0 ? 1 : -1, c2 = c.slice(); c2[a] += step;
      var ah = c2.slice(); ah[a] += sg * rad * 0.9; var pa = solidAt(ah[0], ah[1], ah[2]);
      if (pa) { // inside corner: carry on onto the surface that is in the way (wall -> ceiling -> beam ...)
        var face = pa === FLOOR ? room.base(c[0], c[2]) : sg > 0 ? pLo(pa, a) : pHi(pa, a);
        if (a === 1 && sg < 0) { e.x = c[0]; e.z = c[2]; e.y = face; e.yaw = Math.atan2(-n[0], -n[2]); e.cling = null; e.vy = 0; e.air = false; if (e === G.me) bus.emit('cling', { on: false }); return; } // down onto a floor or a top
        var on = n.slice(); n = [0, 0, 0]; n[a] = -sg; c[a] = face - sg * rad; cl.n = n; if (!lock) cl.f = on; else cl.f = fixF(cl.f, n, on); cl.carry = { sig: sig, mv: on.slice() }; moved = true; break;
      }
      var su = solidAt(c2[0] - n[0] * (rad + 0.06), c2[1] - n[1] * (rad + 0.06), c2[2] - n[2] * (rad + 0.06));
      if (su) { c = c2; moved = true; if (!lock) { cl.f = [0, 0, 0]; cl.f[a] = sg; } continue; }
      // outside corner: go round onto the neighbouring face of the same solid
      var c3 = c2.slice(), q; c3[a] += sg * rad; for (i = 0; i < 3; i++) c3[i] -= n[i] * rad * 1.35;
      q = c3.slice(); q[a] -= sg * (rad + 0.06); var s2 = solidAt(q[0], q[1], q[2]);
      if (s2 && s2 !== FLOOR && !solidAt(c3[0], c3[1], c3[2])) {
        if (a === 1 && sg > 0) { e.x = c3[0]; e.z = c3[2]; e.y = pHi(s2, 1); e.yaw = Math.atan2(-n[0], -n[2]); e.cling = null; e.vy = 0; e.air = false; if (e === G.me) bus.emit('cling', { on: false, top: true }); return; } // over the top edge: stand up there
        var on2 = n.slice(); n = [0, 0, 0]; n[a] = sg; c3[a] = (sg > 0 ? pHi(s2, a) : pLo(s2, a)) + sg * rad; c = c3; cl.n = n; var back = [-on2[0], -on2[1], -on2[2]]; cl.f = lock ? fixF(cl.f, n, back) : back; cl.carry = { sig: sig, mv: back.slice() }; moved = true;
      }
      break;
    }
    e.x = c[0] - n[0] * rad; e.y = c[1] - n[1] * rad; e.z = c[2] - n[2] * rad; e.speed = moved ? sp : 0;
  }
  function fixF(f, n, alt) { return Math.abs(f[0] * n[0] + f[1] * n[1] + f[2] * n[2]) > 0.5 ? alt : f; } // the head direction must stay in the surface
  /* bots: put a cat on a wall, a pillar or a ceiling somewhere reachable from (x, z) */
  function stickSomewhere(e, r) {
    for (var t = 0; t < 30; t++) {
      var x = e.x + (r() - 0.5) * 5, z = e.z + (r() - 0.5) * 5, y0 = room.groundAt(x, z, e.y + 0.2, 0), up = r() < 0.3;
      if (solidAt(x, y0 + 0.3, z) || Math.abs(y0 - e.y) > 0.5) continue;
      var sx = e.x, sy = e.y, sz = e.z; e.x = x; e.z = z; e.y = y0;
      if (up) { for (var h = y0 + 0.6; h < y0 + 6; h += 0.2) if (solidAt(x, h + e.rad * 1.8 + 0.16, z)) break; if (h < y0 + 6 && h > y0 + 1.6) { e.y = h; if (tryAttach(e, 0, 0, [[1, 1]])) return true; } }
      else { var a = r() < 0.5 ? 0 : 2, sg = r() < 0.5 ? 1 : -1; for (var d = 0; d < 6; d += 0.15) { var q = [x, y0 + 0.3, z]; q[a] += sg * d; var p = solidAt(q[0], q[1], q[2]); if (p) { if (p !== FLOOR && p.y1 - y0 > 2.0) { e.x = q[0] - (a === 0 ? sg * (e.rad + 0.1) : 0); e.z = q[2] - (a === 2 ? sg * (e.rad + 0.1) : 0); e.y = y0 + 1.2 + r() * Math.min(2.6, p.y1 - y0 - 1.7); if (!solidAt(e.x, e.y + e.rad, e.z) && tryAttach(e, 0, 0, [[a, sg]])) { e.cling.f = [[0, 1, 0], [0, -1, 0], a === 0 ? [0, 0, 1] : [1, 0, 0]][Math.floor(r() * 3)]; return true; } } break; } } }
      e.x = sx; e.y = sy; e.z = sz;
    }
    return false;
  }

  /* ------------------------------------------------------------------ cameras */
  /* critically damped approach with a top speed (the classic "smooth damp") */
  function smoothDamp(cur, target, vel, smoothTime, maxSpeed, dt) {
    if (!(dt > 0)) return cur; var om = 2 / smoothTime, x = om * dt, ex = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x), ch = cur - target, mc = maxSpeed * smoothTime; if (ch > mc) ch = mc; else if (ch < -mc) ch = -mc;
    var t2 = cur - ch, tmpv = (vel.v + om * ch) * dt; vel.v = (vel.v - om * tmpv) * ex; var out = t2 + (ch + tmpv) * ex; if ((target - cur > 0) === (out > target)) { out = target; vel.v = 0; } return out;
  }
  function updateCamera(dt) {
    var me = G.me, cm = G.cam;
    if (G.mode === 'title') {
      var a = G.time * 0.06, ws = SG.WS; cm.free.p.set(Math.sin(a) * 0.7 * ws, (0.85 + Math.sin(a * 0.7) * 0.05) * ws, (4.3 + Math.cos(a) * 0.12) * ws);
      camera.fov = 46; camera.position.copy(cm.free.p); camera.lookAt(cm.free.t);
    } else if (cm.free) { camera.position.copy(cm.free.p); camera.lookAt(cm.free.t); if (cm.free.fov) camera.fov = cm.free.fov; }
    else if (G.fly) { // free spectator camera: reveal, and after being caught
      var F = G.fly, k = G.keys, sp = (k.Shift ? 9 : 4) * dt, cdx = Math.sin(F.yaw) * Math.cos(F.pitch), cdy = Math.sin(F.pitch), cdz = Math.cos(F.yaw) * Math.cos(F.pitch);
      var fw = (k.w || k.ArrowUp ? 1 : 0) - (k.s || k.ArrowDown ? 1 : 0), st = (k.d || k.ArrowRight ? 1 : 0) - (k.a || k.ArrowLeft ? 1 : 0), ud = (k[' '] || k.e ? 1 : 0) - (k.c ? 1 : 0);
      if (F.hide && !F.move) fw = st = ud = 0; // stage one: the camera is only detached (look around); 4 turns flying on
      F.p.x += (cdx * fw - Math.cos(F.yaw) * st) * sp; F.p.z += (cdz * fw + Math.sin(F.yaw) * st) * sp; F.p.y += (cdy * fw + ud) * sp;
      var bd = room.bounds; F.p.x = Math.max(bd.x0, Math.min(bd.x1, F.p.x)); F.p.z = Math.max(bd.z0, Math.min(bd.z1, F.p.z)); F.p.y = Math.max(0.15, Math.min(5.5 * SG.WS, F.p.y));
      if (G.follow && G.follow.c.root.visible) { var fc = G.follow.c.center(tmp); F.p.set(fc.x - cdx * 2.2, fc.y + 0.5 - cdy * 2.2, fc.z - cdz * 2.2); }
      camera.fov = 62; camera.position.copy(F.p); camera.lookAt(F.p.x + cdx, F.p.y + cdy, F.p.z + cdz);
    } else if (me && me.team === 'cat') {
      var ctr = me.c.center(tmp); var ty = ctr.y + 0.04, dist = cm.dist * (G.paint.on ? 0.7 : 1);
      var ox = Math.sin(cm.yaw) * Math.cos(cm.pitch) * dist, oy = Math.sin(cm.pitch) * dist, oz = Math.cos(cm.yaw) * Math.cos(cm.pitch) * dist;
      if (me.cling) { // stuck to a wall or ceiling: aim a little off the surface and keep the camera on the room side of it, so it never ends up inside the wall or above the ceiling
        var cn = me.cling.n, dn = ox * cn[0] + oy * cn[1] + oz * cn[2], need = dist * 0.3; ty = ctr.y + cn[1] * 0.14; ctr.x += cn[0] * 0.14; ctr.z += cn[2] * 0.14;
        if (dn < need) { ox += cn[0] * (need - dn); oy += cn[1] * (need - dn); oz += cn[2] * (need - dn); } }
      var thru = G.paint.on && G.seeThrough !== false; // camera pass-through: in paint mode the camera goes through things and whatever is between it and you is cut away
      var tw = thru ? 1 : room.segWalls(ctr.x, ty, ctr.z, ctr.x + ox * 1.12, ty + oy * 1.12, ctr.z + oz * 1.12), kk = Math.max(0.12, Math.min(1, tw * 1.12 - 0.1 / dist));
      // the boom length follows a damped spring with a speed limit (never a jump); while the camera is still on its way in, whatever stands between
      // it and the body is cut away with the near plane instead, so the view is never blocked and the picture never jolts
      cm.kv = cm.kv || { v: 0 }; cm.kk = cm.kk == null ? kk : smoothDamp(cm.kk, kk, cm.kv, kk < cm.kk ? 0.16 : 0.5, 2.6 / Math.max(0.5, dist), dt); var lagK = Math.max(0, cm.kk - kk); kk = cm.kk;
      var nearT = thru ? Math.max(0.06, dist * kk - 0.42 * (me.size || 1)) : lagK > 0.004 ? Math.min(Math.max(0.06, dist * kk - 0.4 * (me.size || 1)), lagK * dist * 1.12 + 0.14) : 0.06; camera.near = nearT;
      var px = ctr.x + ox * kk, py = Math.max(room.base(ctr.x, ctr.z) + 0.1, ty + oy * kk), pz = ctr.z + oz * kk;
      camera.fov = 52 + (G.runK || 0) * 7; cm.look = (cm.look || V(ctr.x, ty, ctr.z)); cm.look.lerp(tmp2.set(ctr.x, ty, ctr.z), 1 - Math.exp(-dt * (22 + (me.speed || 0) * 7))); // the look-at point is damped too, so body bounce never shakes the picture
      camera.position.lerp(tmp2.set(px + cm.look.x - ctr.x, py + cm.look.y - ty, pz + cm.look.z - ctr.z), 1 - Math.exp(-dt * (18 + (me.speed || 0) * 7))); camera.lookAt(cm.look); // the faster the body, the tighter the camera follows, so it never falls behind in a lurch
    } else if (me && me.team === 'dog') {
      var eh = me.eyeH + (me.ryOff || 0), fp = !G.third;
      me.fp = fp; me.c.root.visible = !fp; if (G.vm) G.vm.visible = fp;
      var dx = Math.sin(me.yaw) * Math.cos(me.pitch), dy = Math.sin(me.pitch), dz = Math.cos(me.yaw) * Math.cos(me.pitch);
      camera.fov = G.opts.fov;
      if (fp) { var bob = me.speed > 0.2 ? Math.sin(G.simT * 11) * 0.006 : 0, ef = me.eyeF != null ? me.eyeF + (me.eyeFHi - me.eyeF) * me.rear : 0.12; camera.near = 0.03; camera.position.set(me.x + Math.sin(me.yaw) * ef, me.y + eh + bob, me.z + Math.cos(me.yaw) * ef); camera.lookAt(camera.position.x + dx, camera.position.y + dy, camera.position.z + dz); }
      else { var t3w = Math.max(0.15, room.segWalls(me.x, me.y + eh, me.z, me.x - dx * 1.7, me.y + eh + 0.75 - dy * 1.1, me.z - dz * 1.7) - 0.06); cm.t3v = cm.t3v || { v: 0 }; cm.t3 = cm.t3 == null ? t3w : smoothDamp(cm.t3, t3w, cm.t3v, t3w < cm.t3 ? 0.16 : 0.5, 1.6, dt); var t3 = cm.t3; camera.near = cm.t3 - t3w > 0.004 ? Math.min(1.2 * t3, (cm.t3 - t3w) * 1.9 + 0.14) : 0.03; camera.position.set(me.x - dx * 1.5 * t3, me.y + eh + (0.7 - dy * 1.0) * t3, me.z - dz * 1.5 * t3); camera.lookAt(me.x + dx, me.y + eh + dy, me.z + dz); }
      if (G.vm) { // idle sway, walk bob, recoil kick, pump stroke during the reload interval
        G.recoil = Math.max(0, G.recoil - dt * 3.0); G.punch = Math.max(0, (G.punch || 0) - dt * 5.5); camera.rotateX(G.punch * G.punch * 0.045); camera.fov = G.opts.fov + G.punch * 2.5; /* the shot punches the view up and out */ var rc = G.recoil * G.recoil, since = G.simT - G.state.players.you.lastShot, pu = since > 0.35 && since < 1.05 ? Math.sin((since - 0.35) / 0.7 * Math.PI) : 0, mv = me.speed > 0.2 ? 1 : 0;
        G.vm.position.set(0.2 + Math.sin(G.time * 1.3) * 0.004 + Math.sin(G.simT * 5.5) * 0.007 * mv, -0.21 + Math.sin(G.time * 1.9) * 0.004 - Math.abs(Math.sin(G.simT * 5.5)) * 0.012 * mv + pu * 0.012, -0.4 + rc * 0.2);
        G.vm.rotation.set(0.02 + rc * 0.66 - pu * 0.1, 0.09 + Math.sin(G.time * 0.9) * 0.01, pu * 0.14); G.vmPump.position.z = pu * 0.11;
        G.vmFlash.visible = since < 0.06; if (G.vmFlash.visible) G.vmFlash.scale.setScalar(0.7 + rnd() * 0.8);
        if (pu > 0.5 && !G.pumped && since < 1) { G.pumped = true; bus.emit('pump'); } if (since > 1.1) G.pumped = false; }
    }
    camera.updateProjectionMatrix(); camera.updateMatrixWorld(true);
  }
  function enterReveal() {
    G.paint.on = false; G.cam.free = null; G.third = true; if (G.vm) G.vm.visible = false;
    if (!G.fly) G.fly = { p: V(0.6 * SG.WS, 2.2 * SG.WS, 3.4 * SG.WS), yaw: Math.PI, pitch: -0.42 };
    if (document.exitPointerLock) try { document.exitPointerLock(); } catch (e) { }
    G.ents.concat(G.decoys).forEach(function (e) { if (e.vanish > 0 || e.gone) { e.vanish = 0; e.gone = false; e.c.root.scale.setScalar(e.c.scale); e.c.root.visible = true; } }); // found hiders and their clones are shown again where they hid
    G.ents.forEach(function (e) {
      e.c.root.visible = true; e.fp = false;
      if (e.team === 'cat' && G.state.players[e.id]) { var found = G.state.players[e.id].out; e.c.root.visible = true; e.c.glow.value.setRGB(found ? 0.02 : 0.85, found ? 0.22 : 0.05, found ? 0.95 : 0.03); e.found = found; }
    });
    G.decoys.forEach(function (d) { d.c.glow.value.setRGB(0.5, 0.28, 0.05); });
    G.ents.concat(G.decoys).forEach(function (e) {
      if (e.team !== 'cat' || !e.c.root.visible) return; var owner = e.decoyOf ? ent(e.decoyOf) : e, found = owner ? !!owner.found : false;
      if (!e.shell) { e.shell = new THREE.SkinnedMesh(e.c.skin.geometry, new THREE.MeshBasicMaterial({ transparent: true, depthTest: false, depthWrite: false, blending: THREE.AdditiveBlending })); e.shell.bind(e.c.skin.skeleton, new THREE.Matrix4()); e.shell.frustumCulled = false; e.shell.renderOrder = 60; e.shell.layers.set(1); e.c.root.add(e.shell); }
      e.shell.material.color.setRGB(found ? 0.1 : 1.0, found ? 0.45 : 0.12, found ? 1.0 : 0.08); e.shell.visible = true; e.shellOn = true;
    });
    answerMarks(); G.likeT = 2 + rnd() * 3;
    bus.emit('answer', { n: cats().length });
  }
  function giveLike(to, from) { G.likes[to] = (G.likes[to] || 0) + 1; bus.emit('like', { id: to, from: from, n: G.likes[to] }); }
  /* answer check: a thick outline that shows through walls (solid hull drawn over everything, then the body drawn again on top
     where nothing hides it), and a line from every clone to its owner */
  function hullMat(col) { var m = new THREE.MeshBasicMaterial({ color: col, side: THREE.BackSide, depthTest: false, depthWrite: false }); m.onBeforeCompile = function (sh) { sh.vertexShader = sh.vertexShader.replace('#include <begin_vertex>', 'vec3 transformed = position + normalize(normal) * 0.022;'); }; m.customProgramCacheKey = function () { return 'hull'; }; return m; }
  function answerMarks() {
    G.ents.concat(G.decoys).forEach(function (e) {
      if (e.team !== 'cat' || !e.c.root.visible || !e.c.skin.isSkinnedMesh) return; var owner = e.decoyOf ? ent(e.decoyOf) : e, found = owner ? !!owner.found : false, col = found ? 0x2f8cff : 0xff3a22;
      if (!e.hull) { e.hull = new THREE.SkinnedMesh(e.c.skin.geometry, hullMat(col)); e.redraw = new THREE.SkinnedMesh(e.c.skin.geometry, e.c.mat); [e.hull, e.redraw].forEach(function (m, i) { m.bind(e.c.skin.skeleton, new THREE.Matrix4()); m.frustumCulled = false; m.renderOrder = 56 + i; m.castShadow = false; m.receiveShadow = true; e.c.root.add(m); }); }
      e.hull.material.color.setHex(col); e.hull.visible = e.redraw.visible = true;
      if (e.decoyOf && owner) { var a = e.c.center(V()), b = owner.c.center(V()), L = a.distanceTo(b); if (L > 0.05) { var ln = new THREE.Mesh(new THREE.BoxGeometry(0.035, 0.035, 1), new THREE.MeshBasicMaterial({ color: col, depthTest: false, depthWrite: false, transparent: true, opacity: 0.85 })); ln.position.copy(a).add(b).multiplyScalar(0.5); ln.lookAt(b); ln.scale.z = L; ln.renderOrder = 61; ln.layers.set(1); scene.add(ln); G.marks.push(ln); } }
    });
  }
  /* screen positions for name tags (reveal) */
  G.project = function (e) { var w = e.c.center(tmp).clone(), dist = w.distanceTo(camera.position); w.y += 0.45; var v = w.clone().applyMatrix4(camera.matrixWorldInverse), p = w.project(camera); return { x: (p.x * 0.5 + 0.5) * G.vw, y: (-p.y * 0.5 + 0.5) * G.vh, vis: p.z < 1, dist: dist, vx: v.x, vy: v.y, vz: v.z }; };

  /* small turntable previews drawn straight onto the canvas inside the title cards */
  var pv = { scene: new THREE.Scene(), cam: new THREE.PerspectiveCamera(28, 1, 0.05, 30), items: {} };
  (function () { var h = new THREE.HemisphereLight(0xfff4e0, 0xb09070, 1.5), d = new THREE.DirectionalLight(0xfff0d8, 2.6); d.position.set(2, 4, 3); pv.scene.add(h, d); })();
  G.setPreview = function (team, el) {
    var it = pv.items[team]; if (it) { pv.scene.remove(it.g); it.c.dispose(); }
    var c = new SG.Critter(specOf(team), { seed: team === 'cat' ? 3 : 5 }), g = new THREE.Group(), x = team === 'cat' ? -12 : 12;
    var disc = new THREE.Mesh(new THREE.CylinderGeometry(0.46, 0.5, 0.05, 40), new THREE.MeshStandardMaterial({ color: team === 'cat' ? 0xf29a4a : 0x4aa3e0, roughness: 0.6 })); disc.position.y = -0.025;
    var top = new THREE.Mesh(new THREE.CylinderGeometry(0.42, 0.42, 0.01, 40), new THREE.MeshStandardMaterial({ color: 0xf6eedc, roughness: 0.8 })); top.position.y = 0.003;
    g.add(disc, top, c.root); g.position.x = x; pv.scene.add(g);
    pv.items[team] = { c: c, g: g, el: el, x: x, h: c.center(V()).y };
    return c;
  };
  var pvR = null;
  function renderPreviews(dt) { // own tiny renderer, copied into the 2D canvases inside the title cards
    if (G.mode !== 'title') return;
    for (var t in pv.items) {
      var it = pv.items[t], el = it.el; if (!el.clientWidth) continue;
      if (!pvR) { pvR = new THREE.WebGLRenderer({ alpha: true, antialias: true, preserveDrawingBuffer: true }); pvR.setSize(360, 300, false); pvR.toneMapping = THREE.ACESFilmicToneMapping; pvR.setClearColor(0x000000, 0); }
      if (el.width !== 360) { el.width = 360; el.height = 300; }
      it.g.rotation.y += dt * 0.7; it.c.update(dt, rnd);
      var size = Math.max(0.55, it.h * 2.4); pv.cam.aspect = 1.2; pv.cam.position.set(it.x, it.h + 0.35, size * 3.3); pv.cam.lookAt(it.x, it.h * 0.95, 0); pv.cam.updateProjectionMatrix();
      pvR.render(pv.scene, pv.cam); var g2 = el.getContext('2d'); g2.clearRect(0, 0, 360, 300); g2.drawImage(pvR.domElement, 0, 0);
    }
  }
  function render(dt) { var S2 = G.settings, hv = G.mode === 'play' && G.me && G.me.team === 'dog' && G.state && G.state.phase === 'seek' && !G.fly, fu = post.final; fu.uMono.value = hv && S2.fMono ? 1 : 0; fu.uHorror.value = hv ? +S2.fHorror || 0 : 0; fu.uMosaic.value = hv && S2.fMosaic ? (+S2.fMosaic + 1) * Math.max(1, post.height / 1080) : 0; /* 像素: 1/2, 1/3, 1/4 resolution, nearest-neighbour, never coarser than 270 lines at 1080p */ var flat = G.paint.on && G.paint.flat && G.mode === 'play', mk = camera.layers.mask, env = scene.environment; if (flat) { camera.layers.mask = 1 | 4; scene.environment = null; } if (G.fx && G.me && G.me.team === 'cat' && G.me.c._fx) G.fx.flush(G.me.c); post.render(scene, camera, G.time); if (G.strokeStats.pending) { var lt = performance.now() - G.strokeStats.pending; G.strokeStats.pending = 0; G.strokeStats.lat = lt; if (lt > G.strokeStats.latMax) G.strokeStats.latMax = lt; } if (flat) { camera.layers.mask = mk; scene.environment = env; } renderPreviews(dt || 0); }

  /* ------------------------------------------------------------------ test / capture API */
  G.step = function (sec, hz) { var n = Math.round(sec * (hz || 60)), dt = 1 / (hz || 60); for (var i = 0; i < n; i++) update(dt); if (!G.noRender) render(); };
  G.placeU = function (id, x, y, z, yaw) { G.place(id, x * SG.WS, y * SG.WS, z * SG.WS, yaw); }; // plan units
  G.ent = ent; G.place = function (id, x, y, z, yaw) { var e = ent(id); e.cling = null; e.ryOff = 0; e.x = x; e.y = y; e.z = z; if (yaw != null) e.yaw = yaw; e.vy = 0; place(e); e.c.root.updateMatrixWorld(true); };
  G.info = function () {
    var m = G.me, st = G.state;
    return { mode: G.mode, side: G.side, phase: st && st.phase, left: st && st.left, winner: st && st.winner, reason: st && st.reason, guide: G.guide, paintOn: G.paint.on,
      offFloor: cats().filter(function (c) { return c.bot && (c.cling || c.y - room.base(c.x, c.z) > 0.3); }).length, botCats: cats().filter(function (c) { return c.bot; }).length, gameMode: st && st.mode, lobby: G.lobby ? { t: G.lobby.t, on: G.lobby.on, n: G.lobby.n } : null, night: !!G.settings.night, splats: splatI, third: !!G.third, viewLock: !!G.viewLock, tags: !!G.tags, seeThrough: !!G.seeThrough,
      me: m && { id: m.id, team: m.team, x: m.x, y: m.y, z: m.z, yaw: m.yaw, pose: m.c.pose, embed: !!m.embed, exposed: !!m.exposed, out: m.out, speed: m.speed, cling: !!m.cling, clingN: m.cling ? m.cling.n : null, size: m.size, painted: m.team === 'cat' ? m.c.paintedRatio() : 0, sus: m.sus, fly: !!G.fly },
      players: st && st.players, undo: G.paint.undo.length, decoys: G.decoys.length, shots: G.shots.length, room: room.stats, draw: post.sceneCalls, tris: post.sceneTris };
  };

  /* ------------------------------------------------------------------ capture states (?shot=...) */
  function freeCam(px, py, pz, tx, ty, tz, fov) { var w = SG.WS; G.cam.free = { p: V(px * w, py * w, pz * w), t: V(tx * w, ty * w, tz * w), fov: fov || 50 }; } // plan units
  function qcam(def) { var c = Q.get('cam'); var v = (c ? c.split(',').map(Number) : def); freeCam(v[0], v[1], v[2], v[3], v[4], v[5], v[6]); }
  function settle(n) { for (var i = 0; i < (n || 40); i++) G.ents.forEach(function (e) { place(e); e.c.update(0.05, rnd); }); }
  var SHOTS = {
    title: toTitle,
    room: function () { G.mode = 'view'; qcam([-3.3, 1.55, 2.1, 0.8, 0.6, -1.0, 62]); bus.emit('mode', { mode: 'view' }); },
    cats: function () { G.mode = 'view'; CAT_KEYS.forEach(function (k, i) { spawn(k, SG.CATS[k], 'cat', { x: -1.65 + i * 0.66, z: 1.95, yaw: 0.5 - i * 0.2 }); }); settle(); qcam([0.0, 0.95, 4.9, 0.0, 0.08, 1.95, 40]); bus.emit('lineup', { kind: 'cat' }); },
    dogs: function () { G.mode = 'view'; DOG_KEYS.forEach(function (k, i) { spawn(k, SG.makeSpec(SG.DOGS[k], { collar: ['red', '', 'bell', 'scarf', '', 'red'][i] }), 'dog', { x: -1.85 + i * 0.74, z: 1.95, yaw: 0.7 - i * 0.28 }); }); settle(); qcam([0.0, 1.0, 5.2, 0.0, 0.1, 1.95, 40]); bus.emit('lineup', { kind: 'dog' }); },
    poses: function () { G.mode = 'view'; var b = Q.get('breed') || 'mochi', row = +(Q.get('row') || 0); SG.POSE_LIST.slice(row * 3, row * 3 + 3).forEach(function (p, i) { var e = spawn('p' + i, SG.CATS[b] || SG.DOGS[b], 'cat', { x: -0.4 + i * 0.95, z: 1.75, yaw: 0.7, pose: p[0] }); demoPaint(e.c); }); settle(60); qcam([0.55, 0.8, 3.9, 0.55, 0.22, 1.75, 40]); bus.emit('lineup', { kind: 'pose', row: row }); },
    /* one pose seen from three sides (front-quarter, side, back-quarter) */
    pose3: function () { G.mode = 'view'; var b = Q.get('breed') || 'mochi', p = Q.get('pose') || 'side'; [0.6, -1.57, 2.6].forEach(function (yaw, i) { var e = spawn('p' + i, SG.CATS[b], 'cat', { x: -0.5 + i * 1.05, z: 1.75, yaw: yaw, pose: p }); e.c.frozen = Q.get('live') ? false : true; calico(e.c); }); settle(60); if (Q.get('adv')) G.ents.forEach(function (e) { e.c.frozen = false; e.c.speed = +Q.get('adv'); for (var k = 0; k < +(Q.get('n') || 7); k++) e.c.update(0.03, rnd); }); qcam([0.55, 0.85, 4.1, 0.55, 0.22, 1.75, 40]); bus.emit('lineup', { kind: 'pose3', pose: p }); },
    paint: function () { G.start('cat', Q.get('breed') || 'mochi'); G.place('you', 1.9, 0.012, 0.6, 2.3); G.cam.yaw = 2.5; G.cam.pitch = 0.22; G.cam.dist = 2.3; G.setPose(Q.get('pose') || 'sit'); G.setPaintMode(true); G.step(1.5); camera.updateMatrixWorld(true); autoCamo(G.me, 1, camera.position.clone()); G.me.c.eachTexel(function (x, y, z, n) { return /head|ear|pad|cheek|neck/.test(n) ? [255, 255, 255] : null; }); G.guide = 4; bus.emit('guide', { step: 4 }); if (SG.ui) SG.ui.P.setRGB([47, 75, 124]); },
    /* a white cat in paint mode, seen from the side: for the brush checks */
    paintblank: function () { G.start('cat', Q.get('breed') || 'mochi'); G.place('you', 1.9, 0.012, 0.6, 2.3); G.cam.yaw = 2.3 + Math.PI / 2 + (+Q.get('yaw') || 0); G.cam.pitch = Q.get('pitch') ? +Q.get('pitch') : 0.18; G.cam.dist = +Q.get('dist') || 2.0; if (Q.get('pose')) G.setPose(Q.get('pose')); G.setPaintMode(true); G.step(1.5); G.guide = 5; bus.emit('guide', { step: 5 }); },
    painted: function () { G.start('cat', Q.get('breed') || 'mochi'); G.place('you', 2.9, 0.42, 1.25, -2.0); G.setPose(Q.get('pose') || 'loaf'); G.cam.yaw = -2.2; G.cam.pitch = 0.3; G.cam.dist = 2.2; G.step(1.5); camera.updateMatrixWorld(true); autoCamo(G.me, 1, camera.position.clone()); },
    dogfp: function () { G.start('dog', Q.get('breed') || 'shiba'); G.skip(); G.place('you', -1.6, 0, 1.5, 1.9); G.me.pitch = -0.12; G.step(0.3); },
    reveal: function () { G.start('dog', 'shiba'); G.skip(); G.step(0.2); var c0 = ent('cat0'), c = c0.c.center(V()); var o = V(c.x * 0.5, 0.7, c.z * 0.5); fire(G.me, o, V().subVectors(c, o).normalize()); G.step(0.5); dispatch({ type: "tick", dt: 999 }); G.step(1.2); }
  };
  G.SHOTS = SHOTS;
})();
