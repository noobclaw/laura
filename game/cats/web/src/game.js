/* 貓躲狗找 — game glue: boot, entities, input, cameras, bots, round flow (rules live in core/rules.js). */
(function () {
  'use strict';
  var SG = (window.SG = window.SG || {});
  var RULES = (SG.RULES = JSON.parse(JSON.stringify(window.SG_RULES)));
  var Core = window.SGCore;
  var Q = new URLSearchParams(location.search);
  var bus = (SG.bus = { h: {}, on: function (t, f) { (this.h[t] = this.h[t] || []).push(f); }, emit: function (t, d) { (this.h[t] || []).forEach(function (f) { f(d); }); (this.h['*'] || []).forEach(function (f) { f(t, d); }); } });

  var canvas, post, scene, camera, room, ray = new THREE.Raycaster(), rnd = SG.rng(Q.get('seed') ? +Q.get('seed') : 7);
  var G = (SG.game = {
    mode: 'boot', side: null, state: null, ents: [], me: null, time: 0, roundT: 0, simT: 0,
    cam: { yaw: 0.6, pitch: 0.32, dist: 2.6, free: null }, keys: {}, mouse: { x: 0, y: 0, down: [false, false, false] },
    paint: { on: false, rgb: [47, 75, 124], rough: 0.8, metal: 0, size: RULES.paint.brushDefaultCm / 100, hard: true, tool: 'brush', undo: [], last: null },
    balls: [], marks: [], confetti: [], decoys: [], decoyCd: 0, guide: 0, hitstop: 0, labels: []
  });
  var V = function (x, y, z) { return new THREE.Vector3(x, y, z); };
  var tmp = V(), tmp2 = V();

  /* ------------------------------------------------------------------ boot */
  SG.boot = function () {
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
    room = SG.room = SG.buildRoom(scene, { low: low });
    resize(); window.addEventListener('resize', resize);
    bindInput();
    if (SG.ui) SG.ui.init();
    if (SG.audio) SG.audio.init();
    var shot = Q.get('shot');
    if (shot && SHOTS[shot]) SHOTS[shot](); else toTitle();
    var last = performance.now();
    function frame(now) {
      var dt = Math.max(0, Math.min(0.1, (now - last) / 1000)); last = now;
      if (!G.paused) update(dt);
      render();
      G.frames = (G.frames || 0) + 1;
      requestAnimationFrame(frame);
    }
    requestAnimationFrame(frame);
    window.__ready = true;
  };
  function resize() {
    var w = window.innerWidth, h = window.innerHeight, dpr = Math.min(window.devicePixelRatio || 1, Q.get('q') === 'low' ? 1 : 1.5);
    post.setSize(w, h, dpr); camera.aspect = w / h; camera.updateProjectionMatrix(); G.vw = w; G.vh = h;
  }

  /* ------------------------------------------------------------------ entities */
  function spawn(id, spec, team, o) {
    o = o || {};
    var c = new SG.Critter(spec, { seed: G.ents.length + 1, atlas: RULES.paint.textureSize });
    scene.add(c.root);
    var e = { id: id, c: c, spec: spec, team: team, bot: !!o.bot, x: o.x || 0, y: o.y || 0, z: o.z || 0, yaw: o.yaw || 0, vy: 0, vx: 0, vz: 0, speed: 0, air: false, out: false, name: o.name || spec.name,
      rad: team === 'dog' ? 0.22 : Math.max(0.13, spec.bellyR * 0.95), step: 0.14, sus: 0, decoyOf: o.decoyOf || null };
    if (o.pose) c.setPose(o.pose);
    place(e); G.ents.push(e); return e;
  }
  function place(e) { e.c.root.position.set(e.x, e.y, e.z); if (e.cling) e.c.root.rotation.set(-1.25, Math.atan2(-e.cling.nx, -e.cling.nz), 0, 'YXZ'); else e.c.root.rotation.set(0, e.yaw, 0, 'YXZ'); }
  function clearEnts() {
    G.ents.forEach(function (e) { scene.remove(e.c.root); e.c.dispose(); }); G.ents = []; G.decoys = [];
    G.balls.forEach(function (b) { scene.remove(b.m); }); G.balls = []; G.marks.forEach(function (m) { scene.remove(m); }); G.marks = [];
    G.confetti.forEach(function (p) { scene.remove(p.m); }); G.confetti = [];
    G.me = null; if (G.vm) { camera.remove(G.vm); scene.remove(camera); G.vm = null; }
  }
  function ent(id) { for (var i = 0; i < G.ents.length; i++) if (G.ents[i].id === id) return G.ents[i]; return null; }
  function cats() { return G.ents.filter(function (e) { return e.team === 'cat'; }); }

  function moveEnt(e, dx, dz, dt) {
    var h = e.team === 'dog' ? 0.5 : 0.3;
    if (dx && !room.blocked(e.x + dx, e.z, e.y, e.rad, e.step, h)) e.x += dx; else if (dx) e.hitWallX = dx;
    if (dz && !room.blocked(e.x, e.z + dz, e.y, e.rad, e.step, h)) e.z += dz; else if (dz) e.hitWallZ = dz;
  }
  function physEnt(e, dt) {
    if (e.cling) return;
    var g = room.groundAt(e.x, e.z, e.y + e.step, e.rad * 0.4);
    if (e.y > g + 0.001 || e.vy > 0) {
      e.vy -= 9.8 * dt; e.y += e.vy * dt; e.air = true;
      if (e.y <= g && e.vy <= 0) { e.y = g; e.vy = 0; e.air = false; if (e === G.me) bus.emit('land'); }
    } else { e.y = g; e.vy = 0; e.air = false; }
    e.onVac = Math.abs(g - room.vac.top) < 1e-3 && Math.hypot(e.x - room.vac.x, e.z - room.vac.z) < 0.2 && !e.air;
  }

  /* ------------------------------------------------------------------ title */
  function toTitle() {
    clearEnts(); G.mode = 'title'; G.side = null; G.state = null;
    var C = SG.CATS, Dg = SG.DOGS;
    spawn('t1', C.mochi, 'cat', { x: -0.55, z: -0.25, y: 0.38, yaw: 0.35, pose: 'loaf' });
    var b = spawn('t2', C.soba, 'cat', { x: -1.8, z: 1.3, yaw: 0.7, pose: 'sit' });
    spawn('t3', C.wata, 'cat', { x: 0.57, z: -0.25, y: 0.12, yaw: -0.6, pose: 'sit' });
    spawn('t4', C.dango, 'cat', { x: -0.75, z: 1.75, yaw: 0.9, pose: 'stretch' });
    spawn('t5', Dg.shiba, 'dog', { x: 2.15, z: 1.5, yaw: -0.75, pose: 'sit' }).c.wag = 1;
    spawn('t6', Dg.corgi, 'dog', { x: 1.25, z: 2.45, yaw: -0.5 });
    calico(b.c);
    G.cam.free = { p: V(0.0, 0.95, 4.3), t: V(0.0, 0.5, 0.3) };
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
  var CAT_KEYS = ['mochi', 'soba', 'wata', 'dango'], DOG_KEYS = ['shiba', 'corgi', 'bull', 'poodle'];
  G.start = function (side, breed) {
    clearEnts(); G.side = side; G.mode = 'play'; G.roundT = 0; G.cam.free = null; G.third = false; G.paint.on = false; G.moved = 0; G.guide = 0; G.paint.undo = []; G.decoyCd = 0;
    var players = [];
    if (side === 'cat') {
      breed = breed || 'mochi';
      G.me = spawn('you', SG.CATS[breed], 'cat', { x: 0.4, z: 1.6, yaw: Math.PI, name: '你' });
      players.push({ id: 'you', team: 'cat' });
      var others = CAT_KEYS.filter(function (k) { return k !== breed; });
      others.forEach(function (k, i) { spawn('cat' + i, SG.CATS[k], 'cat', { bot: true }); players.push({ id: 'cat' + i, team: 'cat' }); });
      var dk = DOG_KEYS[Math.floor(rnd() * 4)];
      var d = spawn('dog0', SG.DOGS[dk], 'dog', { bot: true, x: -6.0, z: 1.3, yaw: Math.PI / 2 }); d.breed = dk; players.push({ id: 'dog0', team: 'dog' });
      G.cam.yaw = 0; G.cam.pitch = 0.3; G.cam.dist = 2.4;
    } else {
      breed = breed || 'shiba';
      G.me = spawn('you', SG.DOGS[breed], 'dog', { x: -3.7, z: 1.3, yaw: Math.PI / 2, name: '你' }); G.me.breed = breed;
      G.me.pitch = 0; players.push({ id: 'you', team: 'dog' });
      CAT_KEYS.forEach(function (k, i) { spawn('cat' + i, SG.CATS[k], 'cat', { bot: true }); players.push({ id: 'cat' + i, team: 'cat' }); });
      buildLauncher();
    }
    hideBots();
    G.state = Core.createState(players, RULES, rnd);
    dispatch({ type: 'start' });
    bus.emit('mode', { mode: 'play', side: side, breed: breed });
  };
  function dispatch(a) {
    var r = Core.apply(G.state, a, RULES); G.state = r.state;
    for (var i = 0; i < r.events.length; i++) onEvent(r.events[i]);
    return r;
  }
  G.dispatch = dispatch;
  function onEvent(ev) {
    if (ev.type === 'phase') {
      if (ev.phase === 'seek') { G.cam.free = null; var d = ent('dog0'); if (d && d.bot) { d.ai = { wp: 0, wait: 0, mode: 'enter', look: 0 }; } }
      if (ev.phase === 'reveal') enterReveal();
      if (ev.phase === 'lobby') { toTitle(); }
    }
    if (ev.type === 'out') { var c = ent(ev.cat); if (c) { c.out = true; c.c.setPose('stand'); c.c.frozen = false; c.vy = 3.2; c.y += 0.02; burst(c); G.decoys.filter(function (dd) { return dd.decoyOf === c.id; }).forEach(function (dd) { dd.c.root.visible = false; }); } }
    bus.emit(ev.type, ev);
  }
  /* bots choose a spot, strike a pose and camouflage themselves against what a seeker would see behind them */
  function hideBots() {
    var spots = room.spots.slice(), bots = cats().filter(function (e) { return e.bot; });
    bots.forEach(function (e) {
      var i = Math.floor(rnd() * spots.length), s = spots.splice(i, 1)[0];
      e.x = s[0]; e.z = s[1]; e.yaw = s[2]; e.y = s[4]; e.c.setPose(s[3]); e.c.frozen = true; place(e);
      for (var k = 0; k < 30; k++) e.c.update(0.05, rnd);
      e.c.root.updateMatrixWorld(true);
    });
    bots.forEach(function (e) { autoCamo(e, 0.82 + rnd() * 0.14); });
  }
  /* projection camouflage: render the albedo of the scene behind the cat from a seeker's eye and write it into the cat's texture */
  var camoCam = new THREE.PerspectiveCamera(30, 1, 0.05, 60);
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
    post.renderAlbedo(scene, camoCam, N, N, misA);
    e.c.root.visible = false; post.renderAlbedo(scene, camoCam, N, N, misB); e.c.root.visible = true;
    hide.forEach(function (o) { o.c.root.visible = !o.fp; });
    var sum = 0, cnt = 0;
    for (var i = 0; i < misA.length; i += 4) { var df = (Math.abs(misA[i] - misB[i]) + Math.abs(misA[i + 1] - misB[i + 1]) + Math.abs(misA[i + 2] - misB[i + 2])) / 765; sum += df; if (df > 0.012) cnt++; }
    return { m: sum / (N * N * 0.3), visible: cnt / (N * N) };
  }
  G.mismatch = mismatch;
  /* fraction of a seeker's screen the cat covers (0 when outside the view cone) — feeds the 見落とし score */
  function screenArea(e, eye, yaw, fovDeg) {
    var ctr = e.c.center(tmp), dx = ctr.x - eye.x, dz = ctr.z - eye.z, d = Math.hypot(dx, dz, ctr.y - eye.y);
    var ang = Math.atan2(dx, dz) - yaw; while (ang > Math.PI) ang -= 2 * Math.PI; while (ang < -Math.PI) ang += 2 * Math.PI;
    if (Math.abs(ang) > fovDeg * Math.PI / 360 * 1.6) return 0;
    var rho = 0.3 / (d * Math.tan(fovDeg * Math.PI / 360)); return Math.min(1, Math.PI * rho * rho / (4 * 1.78));
  }

  /* ------------------------------------------------------------------ shooting */
  var ballGeo, ballMat;
  function ballMesh() {
    if (!ballGeo) { ballGeo = new THREE.SphereGeometry(0.035, 14, 10); ballMat = new THREE.MeshStandardMaterial({ map: SG.tex('tennis', function () { var c = document.createElement('canvas'); c.width = 128; c.height = 64; var g = c.getContext('2d'); g.fillStyle = '#cfe04a'; g.fillRect(0, 0, 128, 64); g.strokeStyle = '#f6f6ea'; g.lineWidth = 5; g.beginPath(); for (var x = 0; x <= 128; x += 4) g.lineTo(x, 32 + Math.sin(x / 128 * Math.PI * 4) * 16); g.stroke(); return c; }), roughness: 0.9, emissive: 0x556010, emissiveIntensity: 0.35 }); }
    var m = new THREE.Mesh(ballGeo, ballMat); m.castShadow = true; return m;
  }
  /* fire a ball from origin along dir. Resolves the hit on the straight line (40 m/s over a room is ~0.1 s), then animates the flight and bounce. */
  function fire(dogEnt, origin, dir) {
    var now = G.simT, p = G.state.players[dogEnt.id];
    if (!p || G.state.phase !== 'seek' || p.balls <= 0 || now - p.lastShot < RULES.dog.shotIntervalSec) { if (dogEnt === G.me && p && p.balls > 0 && G.state.phase === 'seek') bus.emit('dryfire'); return false; }
    ray.set(origin, dir); ray.far = RULES.dog.ballRange; ray.layers.set(0);
    var wh = ray.intersectObjects([room.batched, room.dyn], true)[0], wd = wh ? wh.distance : RULES.dog.ballRange;
    var best = null, bd = wd;
    cats().concat(G.decoys).forEach(function (c) { // exact test against the cat's own meshes
      if (c.out || !c.c.root.visible) return;
      ray.far = bd; var h = ray.intersectObjects(c.c.meshes, false)[0];
      if (h && h.distance < bd) { bd = h.distance; best = c; }
    });
    var target = best ? (best.decoyOf ? ent(best.decoyOf) : best) : null;
    var fleeing = false;
    if (!best) cats().forEach(function (c) { if (!c.out && c.speed > RULES.dog.fleeingSpeed) { var to = tmp.subVectors(c.c.center(tmp2), origin); if (to.normalize().dot(dir) > 0.96) fleeing = true; } });
    var m = ballMesh(); m.position.copy(origin); scene.add(m);
    var nrm = wh && wh.face ? wh.face.normal.clone().transformDirection(wh.object.matrixWorld) : dir.clone().negate();
    G.balls.push({ m: m, o: origin.clone(), d: dir.clone(), t: 0, hitD: bd, state: 'fly', v: V(), n: best ? dir.clone().negate() : nrm, hitCat: best, mark: !best && !!wh });
    dispatch({ type: 'shoot', dog: dogEnt.id, now: now, hit: target ? target.id : null, fleeing: fleeing, decoy: !!(best && best.decoyOf) });
    if (best && best.decoyOf) { best.c.root.visible = false; burst(best); }
    if (target) G.hitstop = 0.09;
    return true;
  }
  G.fire = fire;
  function stepBalls(dt) {
    for (var i = 0; i < G.balls.length; i++) {
      var b = G.balls[i];
      if (b.state === 'fly') {
        b.t += dt; var d = b.t * RULES.dog.ballSpeed;
        if (d >= b.hitD) {
          d = b.hitD; b.state = 'roll'; b.m.position.copy(b.o).addScaledVector(b.d, d - 0.04);
          b.v.copy(b.d).reflect(b.n).multiplyScalar(b.hitCat ? 2.2 : 3.5); b.v.y += 1.2;
          if (b.mark) { var mk = new THREE.Mesh(new THREE.CircleGeometry(0.045, 14), new THREE.MeshBasicMaterial({ color: 0xcfe04a, transparent: true, opacity: 0.7, depthWrite: false })); mk.position.copy(b.o).addScaledVector(b.d, b.hitD).addScaledVector(b.n, 0.006); mk.lookAt(tmp.copy(mk.position).add(b.n)); mk.layers.set(1); scene.add(mk); G.marks.push(mk); }
          bus.emit('bounce', { hit: !!b.hitCat });
        } else { b.m.position.copy(b.o).addScaledVector(b.d, d); b.m.position.y -= 0.5 * RULES.dog.ballGravity * b.t * b.t; }
      } else if (b.state === 'roll') {
        b.v.y -= 9.8 * dt; var p = b.m.position; p.addScaledVector(b.v, dt);
        var g = room.groundAt(p.x, p.z, p.y + 0.1, 0) + 0.035;
        if (p.y < g) { p.y = g; if (b.v.y < -0.8) b.v.y *= -0.45; else b.v.y = 0; b.v.x *= 0.985; b.v.z *= 0.985; }
        var bn = room.bounds; if (p.x < bn.x0 || p.x > bn.x1) { b.v.x *= -0.5; p.x = Math.max(bn.x0, Math.min(bn.x1, p.x)); } if (p.z < bn.z0 || p.z > bn.z1 + 3) { b.v.z *= -0.5; p.z = Math.max(bn.z0, Math.min(bn.z1 + 3, p.z)); }
        var sp = Math.hypot(b.v.x, b.v.z); b.v.x *= Math.exp(-dt * 0.9); b.v.z *= Math.exp(-dt * 0.9); b.m.rotation.x += sp * dt / 0.035; b.m.rotation.z += sp * dt * 6;
        if (sp < 0.03 && Math.abs(b.v.y) < 0.05 && p.y <= g + 0.001) b.state = 'rest'; // balls stay where they land: the reveal shows where the dog guessed wrong
      }
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
  function buildLauncher() {
    var g = new THREE.Group(), M = function (geo, mat, x, y, z, rx, ry, rz) { var m = new THREE.Mesh(geo, mat); m.position.set(x, y, z); m.rotation.set(rx || 0, ry || 0, rz || 0); g.add(m); m.layers.set(1); return m; };
    var body = new THREE.MeshStandardMaterial({ color: 0x4aa3e0, roughness: 0.35 }), trim = new THREE.MeshStandardMaterial({ color: 0xf5f1e8, roughness: 0.4 }), grip = new THREE.MeshStandardMaterial({ color: 0x2a2624, roughness: 0.7 }), org = new THREE.MeshStandardMaterial({ color: 0xf29a4a, roughness: 0.4 });
    M(new THREE.CylinderGeometry(0.05, 0.055, 0.42, 20), body, 0, 0, -0.2, Math.PI / 2); M(new THREE.TorusGeometry(0.054, 0.012, 8, 20), org, 0, 0, -0.41); M(new THREE.TorusGeometry(0.056, 0.01, 8, 20), trim, 0, 0, -0.2); M(new THREE.TorusGeometry(0.058, 0.012, 8, 20), trim, 0, 0, 0.0);
    M(SG.geo.rbox(0.05, 0.16, 0.06, 0.02), grip, 0, -0.11, -0.05, 0.25); M(SG.geo.rbox(0.035, 0.03, 0.12, 0.012), org, 0, 0.065, -0.12); M(new THREE.SphereGeometry(0.06, 16, 12), body, 0, 0, 0.02);
    G.vmBall = ballMesh(); G.vmBall.position.set(0, 0, -0.4); G.vmBall.layers.set(1); G.vmBall.castShadow = false; g.add(G.vmBall);
    // the dog's own paw holding it (breed colour)
    var pawC = { shiba: 0xfaf0de, corgi: 0xfcf8f0, bull: 0xf8f4ec, poodle: 0xe2b48e }[G.me.breed] || 0xffffff;
    M(new THREE.SphereGeometry(0.06, 14, 10), new THREE.MeshStandardMaterial({ color: pawC, roughness: 0.9 }), 0.0, -0.17, -0.02).scale.set(1.1, 0.9, 1.5);
    g.position.set(0.2, -0.17, -0.42); g.rotation.set(0.02, 0.1, 0); g.scale.setScalar(0.8);
    camera.add(g); scene.add(camera); G.vm = g; G.recoil = 0;
  }

  /* ------------------------------------------------------------------ bot dog */
  var WPS = [[-3.6, 1.3], [-2.2, 1.7], [-0.4, 2.0], [1.6, 2.1], [3.1, 1.2], [3.2, -0.6], [2.6, -2.3], [0.9, -2.5], [-1.0, -2.3], [-2.9, -2.2], [-3.3, -0.3], [-2.3, 0.9], [0.9, 0.9], [1.0, -1.4]];
  function botDog(d, dt) {
    var ai = d.ai; if (!ai || G.state.phase !== 'seek') { d.speed = 0; return; }
    var eyeH = RULES.dog.eyeHeight[d.breed] || 0.6, eye = V(d.x, d.y + eyeH, d.z), p = G.state.players[d.id];
    ai.scan = (ai.scan || 0) - dt;
    if (ai.scan <= 0) {
      ai.scan = RULES.overlooked.checkEverySec;
      cats().concat(G.decoys).forEach(function (c) {
        if (c.out || !c.c.root.visible) return;
        var ctr = c.c.center(tmp2), dist = eye.distanceTo(ctr);
        var ang = Math.atan2(ctr.x - d.x, ctr.z - d.z) - d.yaw; while (ang > Math.PI) ang -= 2 * Math.PI; while (ang < -Math.PI) ang += 2 * Math.PI;
        var inView = dist < RULES.bot.dogViewDistance && Math.abs(ang) < RULES.bot.dogFovDeg * Math.PI / 360;
        var owner = c.decoyOf ? ent(c.decoyOf) : c;
        if (!c.decoyOf) dispatch({ type: 'overlook', cat: c.id, area: inView ? screenArea(c, eye, d.yaw, RULES.bot.dogFovDeg) : 0, speed: c.speed });
        if (inView) {
          var mm = mismatch(c, eye); c.lastMis = mm.m;
          var gain = Math.max(0, mm.m - RULES.bot.dogMismatchFloor) * RULES.bot.dogSuspicionGain * (1.4 - dist / RULES.bot.dogViewDistance);
          if (c.speed > RULES.cat.stillSpeed && mm.visible > 0.01) gain += RULES.bot.catMoveSuspicion * Math.min(1, c.speed);
          c.sus = Math.min(1.2, c.sus + gain * ai.scan * 2);
        } else c.sus = Math.max(0, c.sus - RULES.bot.dogSuspicionDecay * ai.scan);
        if (c === G.me || (c.decoyOf === 'you')) bus.emit('suspicion', { v: Math.max(G.me.sus, c.sus), seen: inView });
      });
    }
    // pick a target once sure
    if (ai.mode !== 'aim' && p.balls > 0) {
      var sure = cats().concat(G.decoys).filter(function (c) { return !c.out && c.c.root.visible && c.sus >= 1; })[0];
      if (sure) { ai.mode = 'aim'; ai.target = sure; ai.wait = 0.9; bus.emit('alert', { cat: sure.id }); }
    }
    var tx, tz;
    if (ai.mode === 'aim') {
      var t = ai.target; if (t.out || !t.c.root.visible) { ai.mode = 'patrol'; return; }
      var ctr = t.c.center(tmp2); d.yaw = turn(d.yaw, Math.atan2(ctr.x - d.x, ctr.z - d.z), dt * 6); d.speed = 0; ai.wait -= dt;
      if (ai.wait <= 0) {
        var dir = V().subVectors(ctr, eye).normalize(); dir.x += (rnd() - 0.5) * 0.03; dir.y += (rnd() - 0.5) * 0.03; dir.normalize();
        if (fire(d, eye, dir)) { t.sus = 0.3; ai.mode = 'patrol'; ai.wait = 1.0; } else ai.wait = 0.3;
      }
      return;
    }
    if (ai.heard) { tx = ai.heard[0]; tz = ai.heard[1]; if (Math.hypot(tx - d.x, tz - d.z) < 1.4) { ai.heard = null; ai.wait = 2.2; } }
    else { var w = WPS[ai.wp % WPS.length]; tx = w[0]; tz = w[1]; if (Math.hypot(tx - d.x, tz - d.z) < 0.25) { ai.wp += 1 + Math.floor(rnd() * 2); ai.wait = 1.2 + rnd() * 1.6; ai.look = (rnd() - 0.5) * 2.4; } }
    if (ai.wait > 0) { ai.wait -= dt; d.speed = 0; d.yaw += Math.sin(G.simT * 1.4) * dt * 0.9 + ai.look * dt * 0.4; return; }
    var want = Math.atan2(tx - d.x, tz - d.z); d.yaw = turn(d.yaw, want, dt * 4);
    var sp = RULES.dog.speed * 0.55, px = d.x, pz = d.z; moveEnt(d, Math.sin(d.yaw) * sp * dt, Math.cos(d.yaw) * sp * dt, dt);
    if (ai.mode === 'enter' && d.x < -4.3) { d.x += sp * dt; d.z += (1.3 - d.z) * dt * 3; if (d.x > -4.3) ai.mode = 'patrol'; }
    d.speed = Math.hypot(d.x - px, d.z - pz) / dt; if (d.speed < 0.2 && ai.mode !== 'enter') { ai.stuck = (ai.stuck || 0) + dt; if (ai.stuck > 0.8) { ai.wp++; ai.stuck = 0; ai.heard = null; } } else ai.stuck = 0;
  }
  function turn(a, b, k) { var d = b - a; while (d > Math.PI) d -= 2 * Math.PI; while (d < -Math.PI) d += 2 * Math.PI; return a + d * Math.min(1, k); }

  /* ------------------------------------------------------------------ player actions */
  G.setPose = function (name) { if (!G.me || G.me.team !== 'cat' || G.me.out) return; G.me.c.setPose(name); bus.emit('pose', { pose: name }); if (name !== 'stand' && G.guide === 1) setGuide(2); };
  G.meow = function () {
    if (!G.me || G.me.team !== 'cat') return; bus.emit('meow', { x: G.me.x, z: G.me.z });
    var d = ent('dog0'); if (d && d.ai && Math.hypot(d.x - G.me.x, d.z - G.me.z) < RULES.cat.meowRange) d.ai.heard = [G.me.x, G.me.z];
  };
  G.decoy = function () {
    if (!G.me || G.me.team !== 'cat' || G.me.out) return false;
    if (G.decoys.filter(function (d) { return d.c.root.visible; }).length >= RULES.cat.maxDecoys || G.decoyCd > 0) { bus.emit('denied'); return false; }
    var c = new SG.Critter(G.me.spec, { seed: 9, atlas: RULES.paint.textureSize }); c.copyPaintFrom(G.me.c); c.setPose(G.me.c.pose); c.frozen = true; scene.add(c.root);
    var e = { id: 'decoy' + G.decoys.length, c: c, team: 'cat', decoyOf: 'you', x: G.me.x, y: G.me.y, z: G.me.z, yaw: G.me.yaw, sus: 0, speed: 0, out: false };
    c.root.position.set(e.x, e.y, e.z); c.root.rotation.y = e.yaw; for (var k = 0; k < 20; k++) c.update(0.05, rnd);
    G.decoys.push(e); G.decoyCd = RULES.cat.decoyCooldownSec; bus.emit('decoy', { n: G.decoys.length }); return true;
  };
  G.recallDecoys = function () { G.decoys.forEach(function (d) { scene.remove(d.c.root); d.c.dispose(); }); G.decoys = []; bus.emit('decoy', { n: 0 }); };
  G.skip = function () {
    if (!G.state) return;
    if (G.state.phase === 'prep' || G.state.phase === 'reveal') dispatch({ type: 'skip' });
    else if (G.state.phase === 'seek' && G.me && G.me.team === 'cat' && G.me.out) dispatch({ type: 'tick', dt: G.state.left }); // single player: nothing left to do, go to the result
  };
  G.toTitle = toTitle;
  function setGuide(n) { if (G.guide !== n) { G.guide = n; bus.emit('guide', { step: n }); } }

  /* painting */
  G.setPaintMode = function (on) { if (!G.me || G.me.team !== 'cat') return; G.paint.on = on; bus.emit('paintmode', { on: on }); if (on && G.guide === 2) setGuide(3); };
  function pointerRay(x, y) { tmp.set(x / G.vw * 2 - 1, -(y / G.vh) * 2 + 1, 0.5); ray.setFromCamera(new THREE.Vector2(tmp.x, tmp.y), camera); ray.far = 60; ray.layers.set(0); return ray; }
  function paintAt(x, y, first) {
    var P = G.paint, c = G.me.c, hit = c.raycast(pointerRay(x, y));
    if (!hit) { P.last = null; return false; }
    var hard = P.hard ? RULES.paint.hardnessHard : RULES.paint.hardnessSoft;
    if (P.last && !first) { var d = P.last.distanceTo(hit.point), n = Math.min(24, Math.ceil(d / (P.size * 0.35))); for (var i = 1; i < n; i++) c.paint(tmp2.lerpVectors(P.last, hit.point, i / n), P.size, P.rgb, P.rough, P.metal, hard); }
    c.paint(hit.point, P.size, P.rgb, P.rough, P.metal, hard);
    P.last = (P.last || V()).copy(hit.point); bus.emit('stroke', { size: P.size });
    if (G.guide === 4 && c.paintedRatio() > 0.12) setGuide(5);
    return true;
  }
  G.undo = function () { var s = G.paint.undo.pop(); if (s) { G.me.c.undoStroke(s); bus.emit('undo', { left: G.paint.undo.length }); } return !!s; };
  G.fillAll = function () { var c = G.me.c; c.beginStroke(); c.fill(G.paint.rgb, G.paint.rough, G.paint.metal); pushUndo(c.endStroke()); bus.emit('fill'); if (G.guide === 4) setGuide(5); };
  function pushUndo(s) { if (!s) return; G.paint.undo.push(s); if (G.paint.undo.length > RULES.paint.undoSteps) G.paint.undo.shift(); }
  /* eyedropper: unlit surface colour under the cursor (+ the material's roughness / metalness) */
  G.pickAt = function (x, y) {
    var k = post.width / G.vw, rgb = post.pick(scene, camera, x * k, y * k, post.width, post.height);
    var h = pointerRay(x, y).intersectObjects([room.batched, room.dyn], true)[0], rough = 1, metal = 0;
    if (h && h.object.material && h.object.material.isMeshStandardMaterial) { rough = h.object.material.roughness; metal = h.object.material.metalness; }
    G.paint.rgb = rgb; G.paint.rough = rough; G.paint.metal = metal;
    bus.emit('picked', { rgb: rgb, rough: rough, metal: metal }); if (G.guide === 3) setGuide(4);
    return rgb;
  };
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
  function bindInput() {
    window.addEventListener('keydown', function (e) {
      if (e.target && /INPUT|TEXTAREA/.test(e.target.tagName)) return;
      var k = e.key.length === 1 ? e.key.toLowerCase() : e.key; if (G.keys[k] && e.repeat) return; G.keys[k] = true;
      if (G.mode !== 'play' || !G.me) return;
      if (k === 'Tab' || k === ' ' || k === 'Alt') e.preventDefault();
      if (k === 'Enter') { G.skip(); if (!G.me || G.mode !== 'play') return; }
      if (k === 'Escape') bus.emit('menu');
      if (G.me.team === 'cat' && !G.me.out) {
        if (k === 'f') G.setPaintMode(!G.paint.on);
        if (k === 'r') bus.emit('wheel', { open: true });
        if (k === '1') G.meow();
        if (k === 'q') G.decoy();
        if (k === 'x') G.recallDecoys();
        if (k === 'z' && (e.ctrlKey || e.metaKey || G.paint.on)) G.undo();
        if (k === '[') bus.emit('brush', { d: -0.01 }); if (k === ']') bus.emit('brush', { d: 0.01 });
        if (k === ' ') jump();
        if (k === 'Shift' && G.me.cling) { G.me.cling = null; G.me.vy = 0; bus.emit('cling', { on: false }); }
      } else if (G.me.team === 'dog') {
        if (k === ' ') shootPlayer();
        if (k === 'v') { G.third = !G.third; }
      }
    });
    window.addEventListener('keyup', function (e) { var k = e.key.length === 1 ? e.key.toLowerCase() : e.key; G.keys[k] = false; if (k === 'r') bus.emit('wheel', { open: false }); });
    window.addEventListener('blur', function () { G.keys = {}; });
    canvas.addEventListener('contextmenu', function (e) { e.preventDefault(); });
    canvas.addEventListener('mousedown', function (e) {
      G.mouse.down[e.button] = true; G.mouse.x = e.clientX; G.mouse.y = e.clientY;
      if (SG.audio) SG.audio.unlock();
      if (G.mode !== 'play' || !G.me) return;
      if (G.me.team === 'cat') {
        if (e.button === 0 && G.paint.on && !G.me.out) {
          if (e.altKey || G.paint.tool === 'pick') { G.pickAt(e.clientX, e.clientY); if (G.paint.tool === 'pick') { G.paint.tool = 'brush'; bus.emit('tool', { tool: 'brush' }); } return; }
          G.me.c.beginStroke(); G.paint.last = null; G.stroking = paintAt(e.clientX, e.clientY, true); if (!G.stroking) { G.me.c.endStroke(); G.orbiting = true; }
        } else G.orbiting = true;
      } else if (G.me.team === 'dog' && G.state.phase === 'seek') {
        if (e.button === 0) { if (!Q.get('nolock') && document.pointerLockElement !== canvas && canvas.requestPointerLock) { try { canvas.requestPointerLock(); } catch (er) { } } shootPlayer(); }
        if (e.button === 2) G.third = !G.third;
      } else G.orbiting = true;
    });
    window.addEventListener('mouseup', function (e) {
      G.mouse.down[e.button] = false;
      if (G.stroking) { G.stroking = false; pushUndo(G.me.c.endStroke()); bus.emit('strokeEnd', { undo: G.paint.undo.length }); }
      G.orbiting = false;
    });
    window.addEventListener('mousemove', function (e) {
      var dx = e.movementX || (e.clientX - G.mouse.x), dy = e.movementY || (e.clientY - G.mouse.y); G.mouse.x = e.clientX; G.mouse.y = e.clientY;
      if (G.mode === 'play' && G.me && G.me.team === 'dog' && G.state.phase !== 'reveal') { if (document.pointerLockElement === canvas || G.mouse.down[0] || G.mouse.down[2]) { G.me.yaw -= dx * 0.0032; G.me.pitch = Math.max(-1.2, Math.min(1.2, (G.me.pitch || 0) - dy * 0.0032)); } return; }
      if (G.stroking) paintAt(e.clientX, e.clientY, false);
      else if (G.orbiting) { G.cam.yaw -= dx * 0.006; G.cam.pitch = Math.max(-0.25, Math.min(1.35, G.cam.pitch + dy * 0.005)); }
    });
    canvas.addEventListener('wheel', function (e) {
      e.preventDefault();
      if (G.paint.on && !e.shiftKey && G.me && G.me.team === 'cat') bus.emit('brush', { d: e.deltaY < 0 ? 0.01 : -0.01 });
      else G.cam.dist = Math.max(0.9, Math.min(6, G.cam.dist * (e.deltaY > 0 ? 1.1 : 0.9)));
    }, { passive: false });
  }
  function jump() {
    var m = G.me; if (m.cling || m.air) return;
    var h = m.spec === SG.CATS.dango ? RULES.cat.jumpHeightShortLeg : RULES.cat.jumpHeight;
    m.vy = Math.sqrt(2 * 9.8 * h); m.y += 0.01; m.air = true; if (m.c.pose !== 'stand') G.setPose('stand'); bus.emit('jump');
  }
  function shootPlayer() {
    var m = G.me; if (!m || m.team !== 'dog' || G.state.phase !== 'seek') return;
    var o = V(), d = V(); camera.getWorldPosition(o); camera.getWorldDirection(d);
    if (G.third) { o.set(m.x, m.y + RULES.dog.eyeHeight[m.breed], m.z); d.set(Math.sin(m.yaw) * Math.cos(m.pitch), Math.sin(m.pitch), Math.cos(m.yaw) * Math.cos(m.pitch)); }
    if (fire(m, o, d)) G.recoil = 1;
  }

  /* ------------------------------------------------------------------ update */
  function update(dt) {
    if (G.hitstop > 0) { G.hitstop -= dt; dt *= 0.05; }
    G.time += dt; G.simT += dt;
    var vx0 = room.vac.x, vz0 = room.vac.z;
    room.update(G.simT);
    var vdx = room.vac.x - vx0, vdz = room.vac.z - vz0;
    var st = G.state, me = G.me, k = G.keys;
    if (G.mode === 'play' && st) {
      if (st.phase !== 'lobby') dispatch({ type: 'tick', dt: dt });
      G.decoyCd = Math.max(0, G.decoyCd - dt);
      if (me && !me.out && st.phase !== 'reveal') {
        var f = (k.w || k.ArrowUp && me.team === 'cat' ? 1 : 0) - (k.s || k.ArrowDown && me.team === 'cat' ? 1 : 0), s = (k.d ? 1 : 0) - (k.a ? 1 : 0);
        if (me.team === 'cat') {
          var cy = G.cam.yaw, mvx = -Math.sin(cy) * f + Math.cos(cy) * s, mvz = -Math.cos(cy) * f - Math.sin(cy) * s, l = Math.hypot(mvx, mvz), px = me.x, pz = me.z;
          if (me.cling) clingMove(me, f, s, dt);
          else if (l > 0.01) {
            mvx /= l; mvz /= l; var sp = RULES.cat.walkSpeed * (me.c.pose === 'stand' ? 1 : 0.0);
            if (me.c.pose !== 'stand') G.setPose('stand');
            me.hitWallX = me.hitWallZ = 0; moveEnt(me, mvx * sp * dt, mvz * sp * dt, dt); me.yaw = turn(me.yaw, Math.atan2(mvx, mvz), dt * 12);
            if (me.air && (me.hitWallX || me.hitWallZ) && me.y > 0.25 && atWall(me)) { me.cling = { nx: me.hitWallX ? -Math.sign(me.hitWallX) : 0, nz: me.hitWallZ ? -Math.sign(me.hitWallZ) : 0 }; me.vy = 0; me.air = false; bus.emit('cling', { on: true }); }
            if (G.guide === 0 && (G.moved = (G.moved || 0) + sp * dt) > 1.5) setGuide(1);
          }
          me.speed = Math.hypot(me.x - px, me.z - pz) / Math.max(dt, 1e-4);
          if (me.onVac && me.speed < 0.05) { me.x += vdx; me.z += vdz; } // riding the robot vacuum counts as standing still
        } else {
          var yw = me.yaw; if (k.ArrowLeft) me.yaw += dt * 1.9; if (k.ArrowRight) me.yaw -= dt * 1.9; if (k.ArrowUp) me.pitch = Math.min(1.2, me.pitch + dt * 1.2); if (k.ArrowDown) me.pitch = Math.max(-1.2, me.pitch - dt * 1.2);
          if (st.phase === 'seek') { var sp2 = RULES.dog.speed, mx = Math.sin(yw) * f - Math.cos(yw) * s, mz = Math.cos(yw) * f + Math.sin(yw) * s, pl = Math.hypot(mx, mz), qx = me.x, qz = me.z; if (pl > 0.01) moveEnt(me, mx / pl * sp2 * dt, mz / pl * sp2 * dt, dt); me.speed = Math.hypot(me.x - qx, me.z - qz) / Math.max(dt, 1e-4); }
          // the player dog also feeds the 見落とし score of the cats in front of it
          G.ovT = (G.ovT || 0) - dt; if (G.ovT <= 0 && st.phase === 'seek') { G.ovT = RULES.overlooked.checkEverySec; var eye = V(me.x, me.y + RULES.dog.eyeHeight[me.breed], me.z); cats().forEach(function (c) { if (!c.out) dispatch({ type: 'overlook', cat: c.id, area: screenArea(c, eye, me.yaw, 52 * 1.4), speed: c.speed }); }); }
        }
      }
      G.ents.forEach(function (e) { if (e.bot && e.team === 'dog') botDog(e, dt); });
    }
    // physics + animation for everyone
    var bumpers = [];
    for (var i = 0; i < G.ents.length; i++) {
      var e = G.ents[i];
      if (G.mode === 'play') physEnt(e, dt);
      e.c.speed = e.speed || 0; e.c.air = e.air ? 1 : 0;
      // GDD hider-cat: a posed cat is perfectly still for everyone but its owner
      if (e.team === 'cat' && e !== me) e.c.frozen = e.c.pose !== 'stand' && !e.out;
      place(e);
      e.c.update(dt, rnd);
      if (!e.out && (e.speed > 0.05 || e.air)) bumpers.push({ x: e.x, y: e.y, z: e.z, r: e.team === 'dog' ? 0.3 : RULES.cat.bumpRadius, speed: e.speed || 0 });
    }
    G.decoys.forEach(function (d) { if (d.c.root.visible) d.c.update(dt, rnd); });
    bumpers.push({ x: room.vac.x, y: 0, z: room.vac.z, r: 0.2, speed: 0.4 });
    G.balls.forEach(function (b) { if (b.state === 'roll') bumpers.push({ x: b.m.position.x, y: b.m.position.y - 0.03, z: b.m.position.z, r: 0.06, speed: b.v.length() * 0.4 }); });
    room.stepProps(dt, bumpers, function (kp, landed) { bus.emit('bump', { type: kp.type, landed: !!landed, x: kp.x, z: kp.z }); var d = ent('dog0'); if (d && d.ai && !landed) d.ai.heard = d.ai.heard || [kp.x, kp.z]; });
    stepBalls(dt); stepConfetti(dt);
    updateCamera(dt);
    if (G.mode === 'play' && st) bus.emit('frame', { left: st.left, phase: st.phase });
  }
  function atWall(e) { var b = room.bounds; return e.x < b.x0 + e.rad + 0.05 || e.x > b.x1 - e.rad - 0.05 || e.z < b.z0 + e.rad + 0.05; }
  function clingMove(e, f, s, dt) {
    var k = G.keys, up = (k[' '] || f > 0 ? 1 : 0) - (f < 0 ? 1 : 0), sp = RULES.cat.clingSpeed; // no Ctrl here: Ctrl+W would close the browser tab
    e.y = Math.max(0.15, Math.min(SG.ROOM.H - 0.5, e.y + up * sp * dt));
    var ax = e.cling.nz, az = -e.cling.nx; if (s) { var nx = e.x + ax * s * sp * dt, nz = e.z + az * s * sp * dt; if (!room.blocked(nx, nz, e.y, e.rad * 0.5, 0.05, 0.2)) { e.x = nx; e.z = nz; } }
    e.speed = Math.abs(up) + Math.abs(s) > 0 ? sp : 0;
  }

  /* ------------------------------------------------------------------ cameras */
  function updateCamera(dt) {
    var me = G.me, cm = G.cam;
    if (G.mode === 'title') {
      var a = G.time * 0.06; cm.free.p.set(Math.sin(a) * 0.7, 0.95 + Math.sin(a * 0.7) * 0.05, 4.3 + Math.cos(a) * 0.12);
      camera.fov = 46; camera.position.copy(cm.free.p); camera.lookAt(cm.free.t);
    } else if (cm.free) { camera.position.copy(cm.free.p); camera.lookAt(cm.free.t); if (cm.free.fov) camera.fov = cm.free.fov; }
    else if (G.state && G.state.phase === 'reveal') {
      if (!G.orbiting) cm.yaw += dt * 0.1;
      camera.fov = 70; camera.position.set(Math.sin(cm.yaw) * 3.9, 1.95, Math.cos(cm.yaw) * 2.9 - 0.2); camera.lookAt(Math.sin(cm.yaw) * -1.0, 0.25, Math.cos(cm.yaw) * -0.8 - 0.2);
    } else if (me && me.team === 'cat') {
      var ctr = me.c.center(tmp); var ty = ctr.y + 0.12, dist = cm.dist * (G.paint.on ? 0.62 : 1);
      var px = ctr.x + Math.sin(cm.yaw) * Math.cos(cm.pitch) * dist, py = ty + Math.sin(cm.pitch) * dist, pz = ctr.z + Math.cos(cm.yaw) * Math.cos(cm.pitch) * dist;
      var W = SG.ROOM.W - 0.2, D = SG.ROOM.D - 0.2;
      px = Math.max(-W, Math.min(W, px)); pz = Math.max(-D, Math.min(SG.ROOM.EN + 1.3, pz)); py = Math.max(0.12, Math.min(SG.ROOM.H - 0.25, py));
      camera.fov = 52; camera.position.lerp(tmp2.set(px, py, pz), 1 - Math.exp(-dt * 14)); camera.lookAt(ctr.x, ty, ctr.z);
    } else if (me && me.team === 'dog') {
      var eh = RULES.dog.eyeHeight[me.breed] || 0.6, fp = !G.third;
      me.fp = fp; me.c.root.visible = !fp; if (G.vm) G.vm.visible = fp;
      var dx = Math.sin(me.yaw) * Math.cos(me.pitch), dy = Math.sin(me.pitch), dz = Math.cos(me.yaw) * Math.cos(me.pitch);
      camera.fov = 62;
      if (fp) { var bob = me.speed > 0.2 ? Math.sin(G.simT * 11) * 0.012 : 0; camera.position.set(me.x + Math.sin(me.yaw) * 0.12, me.y + eh + bob, me.z + Math.cos(me.yaw) * 0.12); camera.lookAt(camera.position.x + dx, camera.position.y + dy, camera.position.z + dz); }
      else { camera.position.set(me.x - dx * 2.0, me.y + eh + 0.5 - dy * 1.2, me.z - dz * 2.0); camera.position.x = Math.max(-4.3, Math.min(4.3, camera.position.x)); camera.position.z = Math.max(-3.3, Math.min(3.8, camera.position.z)); camera.lookAt(me.x + dx, me.y + eh + dy, me.z + dz); }
      if (G.vm) { G.recoil = Math.max(0, G.recoil - dt * 3.2); var rc = G.recoil * G.recoil; G.vm.position.set(0.21, -0.185 - Math.abs(Math.sin(G.simT * 5.5)) * (me.speed > 0.2 ? 0.008 : 0), -0.42 + rc * 0.09); G.vm.rotation.x = 0.02 + rc * 0.35; var p = G.state.players.you; G.vmBall.visible = p.balls > 0 && G.simT - p.lastShot > RULES.dog.shotIntervalSec * 0.6; }
    }
    camera.updateProjectionMatrix(); camera.updateMatrixWorld(true);
  }
  function enterReveal() {
    G.paint.on = false; G.cam.free = null; G.cam.pitch = 0.5; G.third = true; if (G.vm) G.vm.visible = false;
    if (document.exitPointerLock) try { document.exitPointerLock(); } catch (e) { }
    G.ents.forEach(function (e) {
      e.c.root.visible = true; e.fp = false;
      if (e.team === 'cat') { var found = G.state.players[e.id].out; e.c.glow.value.setRGB(found ? 0.02 : 0.85, found ? 0.22 : 0.05, found ? 0.95 : 0.03); e.found = found; }
    });
    G.decoys.forEach(function (d) { d.c.glow.value.setRGB(0.5, 0.28, 0.05); });
  }
  /* screen positions for name tags (reveal) */
  G.project = function (e) { var p = e.c.center(tmp).clone(); p.y += 0.45; p.project(camera); return { x: (p.x * 0.5 + 0.5) * G.vw, y: (-p.y * 0.5 + 0.5) * G.vh, vis: p.z < 1 }; };

  function render() { post.render(scene, camera, G.time); }

  /* ------------------------------------------------------------------ test / capture API */
  G.step = function (sec, hz) { var n = Math.round(sec * (hz || 60)), dt = 1 / (hz || 60); for (var i = 0; i < n; i++) update(dt); render(); };
  G.ent = ent; G.place = function (id, x, y, z, yaw) { var e = ent(id); e.x = x; e.y = y; e.z = z; if (yaw != null) e.yaw = yaw; e.vy = 0; place(e); };
  G.info = function () {
    var m = G.me, st = G.state;
    return { mode: G.mode, side: G.side, phase: st && st.phase, left: st && st.left, winner: st && st.winner, reason: st && st.reason, guide: G.guide, paintOn: G.paint.on,
      me: m && { x: m.x, y: m.y, z: m.z, yaw: m.yaw, pose: m.c.pose, out: m.out, speed: m.speed, cling: !!m.cling, painted: m.team === 'cat' ? m.c.paintedRatio() : 0, sus: m.sus },
      players: st && st.players, undo: G.paint.undo.length, decoys: G.decoys.length, balls: G.balls.length, room: room.stats, draw: post.sceneCalls, tris: post.sceneTris };
  };

  /* ------------------------------------------------------------------ capture states (?shot=...) */
  function freeCam(px, py, pz, tx, ty, tz, fov) { G.cam.free = { p: V(px, py, pz), t: V(tx, ty, tz), fov: fov || 50 }; }
  function qcam(def) { var c = Q.get('cam'); var v = (c ? c.split(',').map(Number) : def); freeCam(v[0], v[1], v[2], v[3], v[4], v[5], v[6]); }
  function settle(n) { for (var i = 0; i < (n || 40); i++) G.ents.forEach(function (e) { place(e); e.c.update(0.05, rnd); }); }
  var SHOTS = {
    title: toTitle,
    room: function () { G.mode = 'view'; qcam([-3.3, 1.55, 2.1, 0.8, 0.6, -1.0, 62]); bus.emit('mode', { mode: 'view' }); },
    cats: function () { G.mode = 'view'; CAT_KEYS.forEach(function (k, i) { spawn(k, SG.CATS[k], 'cat', { x: -1.2 + i * 0.8, z: 1.75, yaw: 0.45 - i * 0.25 }); }); settle(); qcam([0.0, 0.6, 4.75, 0.0, 0.3, 1.7, 36]); bus.emit('lineup', { kind: 'cat' }); },
    dogs: function () { G.mode = 'view'; DOG_KEYS.forEach(function (k, i) { spawn(k, SG.DOGS[k], 'dog', { x: -1.5 + i * 1.0, z: 1.7, yaw: 0.5 - i * 0.28 }); }); settle(); qcam([0.0, 0.75, 5.2, 0.0, 0.4, 1.7, 38]); bus.emit('lineup', { kind: 'dog' }); },
    poses: function () { G.mode = 'view'; var b = Q.get('breed') || 'mochi', row = +(Q.get('row') || 0); SG.POSE_LIST.slice(row * 3, row * 3 + 3).forEach(function (p, i) { var e = spawn('p' + i, SG.CATS[b] || SG.DOGS[b], 'cat', { x: -0.4 + i * 0.95, z: 1.75, yaw: 0.7, pose: p[0] }); demoPaint(e.c); }); settle(60); qcam([0.55, 0.8, 3.9, 0.55, 0.22, 1.75, 40]); bus.emit('lineup', { kind: 'pose', row: row }); },
    paint: function () { G.start('cat', Q.get('breed') || 'mochi'); G.place('you', 1.9, 0.012, 0.6, 2.3); G.cam.yaw = 2.5; G.cam.pitch = 0.22; G.cam.dist = 2.3; G.setPose(Q.get('pose') || 'sit'); G.setPaintMode(true); G.step(1.5); camera.updateMatrixWorld(true); autoCamo(G.me, 1, camera.position.clone()); G.me.c.eachTexel(function (x, y, z, n) { return /head|ear|pad|cheek|neck/.test(n) ? [255, 255, 255] : null; }); G.guide = 4; bus.emit('guide', { step: 4 }); if (SG.ui) SG.ui.P.setRGB([47, 75, 124]); },
    painted: function () { G.start('cat', Q.get('breed') || 'mochi'); G.place('you', 2.9, 0.42, 1.25, -2.0); G.setPose(Q.get('pose') || 'loaf'); G.cam.yaw = -2.2; G.cam.pitch = 0.3; G.cam.dist = 2.2; G.step(1.5); camera.updateMatrixWorld(true); autoCamo(G.me, 1, camera.position.clone()); },
    dogfp: function () { G.start('dog', Q.get('breed') || 'shiba'); G.skip(); G.place('you', -1.6, 0, 1.5, 1.9); G.me.pitch = -0.12; G.step(0.3); },
    reveal: function () { G.start('dog', 'shiba'); G.skip(); G.step(0.2); var c0 = ent('cat0'), c = c0.c.center(V()); var o = V(c.x * 0.5, 0.7, c.z * 0.5); fire(G.me, o, V().subVectors(c, o).normalize()); G.step(0.5); dispatch({ type: "tick", dt: 999 }); G.step(1.2); }
  };
  G.SHOTS = SHOTS;
})();
