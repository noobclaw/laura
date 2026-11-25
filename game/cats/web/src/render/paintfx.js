/* 貓躲狗找 — paint feel. Works on a Critter from outside (critter.js is not edited):
   - fast 3D dabs: a spatial grid per body part, so a dab only visits the texels near it
   - partial texture uploads (dirty rectangles + CPU mip levels) instead of re-uploading the whole atlas every frame
   - a wet layer (stamp + coverage): fresh paint is glossy and slightly raised with a soft bead at the stroke edge,
     and settles to the chosen roughness in about 1.5 s
   - the brush cursor drawn on the body (true size, hardness ring, colour dot)
   - fill with a wipe, droplets on fast strokes, "white left" measurement, highlight of unpainted areas */
(function () {
  'use strict';
  var SG = (window.SG = window.SG || {});
  var TICK = 16, WRAP = 254, WET_SEC = 1.5;
  var _v = new THREE.Vector3(), _m = new THREE.Matrix4();

  /* The body module exists in two shapes and both are supported: rigid parts (texel positions fixed in each part's own space,
     p.mesh.matrixWorld places them) and one posed skin (c._tp(p) gives texel positions in pivot space for the current pose,
     c.ver changes when the pose does). world = E * (tp + off). */
  function space(c, p) {
    if (c._tp) { c.root.updateWorldMatrix(true, false); if (c._bounds) c._bounds(p); return { tp: c._tp(p), E: c.root.matrixWorld, off: c.pivot.position, ver: c.ver || 0 }; }
    return { tp: p.tp, E: p.mesh.matrixWorld, off: ZERO, ver: 0 };
  }
  var ZERO = new THREE.Vector3();
  function buildGrid(p, tp, ver) {
    var n = p.tw * p.th, x0 = 1e9, y0 = 1e9, z0 = 1e9, x1 = -1e9, y1 = -1e9, z1 = -1e9, i, k;
    for (i = 0, k = 0; i < n; i++, k += 3) { var x = tp[k], y = tp[k + 1], z = tp[k + 2]; if (x > 1e8) continue; if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y; if (z < z0) z0 = z; if (z > z1) z1 = z; }
    var ext = Math.max(x1 - x0, y1 - y0, z1 - z0, 1e-4), cs = ext / 24, nx = Math.max(1, Math.min(24, Math.ceil((x1 - x0) / cs + 1e-6))), ny = Math.max(1, Math.min(24, Math.ceil((y1 - y0) / cs + 1e-6))), nz = Math.max(1, Math.min(24, Math.ceil((z1 - z0) / cs + 1e-6)));
    var nc = nx * ny * nz, cell = new Int32Array(n), start = new Int32Array(nc + 1), idx = new Int32Array(n);
    for (i = 0, k = 0; i < n; i++, k += 3) { if (tp[k] > 1e8) { cell[i] = -1; continue; } var cx = Math.min(nx - 1, ((tp[k] - x0) / cs) | 0), cy = Math.min(ny - 1, ((tp[k + 1] - y0) / cs) | 0), cz = Math.min(nz - 1, ((tp[k + 2] - z0) / cs) | 0), c = (cz * ny + cy) * nx + cx; cell[i] = c; start[c + 1]++; }
    for (i = 0; i < nc; i++) start[i + 1] += start[i];
    var fill = start.slice(0, nc);
    for (i = 0; i < n; i++) if (cell[i] >= 0) idx[fill[cell[i]]++] = i;
    return (p._g = { ver: ver, x0: x0, y0: y0, z0: z0, cs: cs, nx: nx, ny: ny, nz: nz, start: start, idx: idx });
  }
  function down(src, sw, dst, x0, y0, x1, y1) { // box filter one mip level, inside a rectangle of the destination level
    var dw = sw >> 1, r = sw * 4;
    for (var y = y0; y < y1; y++) for (var x = x0, o = (y * dw + x0) * 4, i = (y * 2 * sw + x0 * 2) * 4; x < x1; x++, o += 4, i += 8) {
      dst[o] = (src[i] + src[i + 4] + src[i + r] + src[i + r + 4] + 2) >> 2; dst[o + 1] = (src[i + 1] + src[i + 5] + src[i + r + 1] + src[i + r + 5] + 2) >> 2;
      dst[o + 2] = (src[i + 2] + src[i + 6] + src[i + r + 2] + src[i + r + 6] + 2) >> 2; dst[o + 3] = (src[i + 3] + src[i + 7] + src[i + r + 3] + src[i + r + 7] + 2) >> 2; }
  }
  function mipChain(src, A) { var L = [src], s = A; while (s > 1) { var d = new Uint8Array((s >> 1) * (s >> 1) * 4); down(L[L.length - 1], s, d, 0, 0, s >> 1, s >> 1); L.push(d); s >>= 1; } return L; }

  function PaintFX(renderer, scene) {
    this.R = renderer; this.scene = scene; this.t = 0; this.stats = { dabs: 0, dabMs: 0, dabMax: 0, flushMs: 0, flushMax: 0, texels: 0, sub: 0, full: 0 };
    this.cur = { on: false, pos: new THREE.Vector3(), r: 0.06, hard: 0.85, rgb: [0, 0, 0] }; this.hi = 0;
    // droplets: one instanced draw call, only visible while some are alive
    var dm = this.drops = new THREE.InstancedMesh(new THREE.SphereGeometry(1, 7, 5), new THREE.MeshStandardMaterial({ roughness: 0.12, metalness: 0 }), 40);
    dm.instanceMatrix.setUsage(THREE.DynamicDrawUsage); dm.count = 0; dm.visible = false; dm.frustumCulled = false; dm.castShadow = false; dm.layers.set(1); scene.add(dm);
    this.dl = []; for (var i = 0; i < 40; i++) { this.dl.push({ t: 0, p: new THREE.Vector3(), v: new THREE.Vector3(), s: 0 }); dm.setColorAt(i, new THREE.Color(1, 1, 1)); }
    this.rt = new THREE.WebGLRenderTarget(40, 40, { type: THREE.UnsignedByteType, depthBuffer: true }); this.px = new Uint8Array(40 * 40 * 4);
    this.wcam = new THREE.OrthographicCamera(-0.5, 0.5, 0.5, -0.5, 0.01, 6);
    this.wmat = new THREE.ShaderMaterial({ uniforms: { map: { value: null }, uWet: { value: null } },
      vertexShader: ['#include <common>', '#include <skinning_pars_vertex>', 'varying vec2 vUv2;', 'void main(){', 'vUv2 = uv;', '#include <skinbase_vertex>', '#include <begin_vertex>', '#include <skinning_vertex>', '#include <project_vertex>', '}'].join('\n'),
      fragmentShader: 'uniform sampler2D map; uniform sampler2D uWet; varying vec2 vUv2; void main(){ vec3 a = texture2D(map, vUv2).rgb; float fl = texture2D(uWet, vUv2).b; float w = (fl < 0.5 && min(a.r, min(a.g, a.b)) > 0.86) ? 1.0 : 0.0; gl_FragColor = vec4(w, 1.0 - w, 0.0, 1.0); }' });
    this.wl = { i: 0, w: 0, n: 0, pct: 100 };
  }
  var P = PaintFX.prototype;

  /* give a critter its wet layer and the shader hooks. Safe to call again. */
  P.attach = function (c) {
    if (c._fx) return c._fx;
    var A = c.A, self = this, fx = (c._fx = { A: A, wet: new Uint8Array(A * A * 4), dirty: {}, live: false, lastDab: -9, sweepT: 0, mipA: null, mipO: null, verA: -1, verO: -1, fillJob: null, fast: !!(c.parts && c.parts.length && (c._tp || c.parts[0].tp) && c.alb && c.orm) });
    for (var i = 3; i < fx.wet.length; i += 4) fx.wet[i] = 255;
    // anything that is already coloured counts as painted (bots, copied decoys, a body restored from a snapshot)
    this.reflag(c, null, true);
    fx.tex = new THREE.DataTexture(fx.wet, A, A, THREE.RGBAFormat); fx.tex.magFilter = THREE.LinearFilter; fx.tex.minFilter = THREE.LinearFilter; fx.tex.generateMipmaps = false; fx.tex.needsUpdate = true;
    fx.u = { uWet: { value: fx.tex }, uWetNow: { value: 1 }, uWetA: { value: A }, uCurV: { value: new THREE.Vector3() }, uCur: { value: new THREE.Vector4(0.06, 0.85, 0, 0) }, uCurCol: { value: new THREE.Color() }, uHiW: { value: 0 }, uWetK: { value: 1 } };
    var obc = c.mat.onBeforeCompile, key0 = c.mat.customProgramCacheKey ? c.mat.customProgramCacheKey() : '';
    c.mat.onBeforeCompile = function (sh, r) {
      if (obc) obc.call(this, sh, r); for (var k in fx.u) sh.uniforms[k] = fx.u[k];
      sh.fragmentShader = sh.fragmentShader.replace('#include <common>', ['#include <common>',
        'uniform sampler2D uWet; uniform float uWetNow, uWetA, uHiW, uWetK; uniform vec3 uCurV, uCurCol; uniform vec4 uCur;',
        'float sgWet = 0.0; vec4 sgW = vec4(0.0);',
        'float sgH(vec2 uv){ float g = texture2D(uWet, uv).g; return g + 1.5 * g * (1.0 - g); }'].join('\n'))
        .replace('#include <map_fragment>', ['#include <map_fragment>',
          'sgW = texture2D(uWet, vMapUv); vec4 sgNr = texture2D(uWet, (floor(vMapUv * uWetA) + 0.5) / uWetA);',
          'float sgAge = mod(uWetNow - sgNr.r * 255.0 + ' + WRAP + '.0, ' + WRAP + '.0) / ' + TICK + '.0;',
          'sgWet = sgNr.r > 0.002 ? clamp(1.0 - sgAge / ' + WET_SEC.toFixed(2) + ', 0.0, 1.0) * smoothstep(0.02, 0.35, sgW.g) * uWetK : 0.0;',
          'diffuseColor.rgb *= 1.0 - 0.05 * sgWet;',
          'if (uHiW > 0.0 && sgW.b < 0.5 && min(diffuseColor.r, min(diffuseColor.g, diffuseColor.b)) > 0.86) { float sgS = step(0.5, fract((gl_FragCoord.x + gl_FragCoord.y) / 18.0)); diffuseColor.rgb = mix(diffuseColor.rgb, mix(vec3(1.0, 0.0, 0.5), vec3(0.3, 0.0, 0.28), sgS), uHiW); }'].join('\n'))
        .replace('#include <roughnessmap_fragment>', '#include <roughnessmap_fragment>\n roughnessFactor = mix(roughnessFactor, 0.06, sgWet * sgWet * 0.94);')
        .replace('#include <normal_fragment_maps>', ['#include <normal_fragment_maps>',
          'if (sgWet > 0.003) { vec2 sgDx = dFdx(vMapUv), sgDy = dFdy(vMapUv); vec3 sgP = -vViewPosition, sgPx = dFdx(sgP), sgPy = dFdy(sgP);',
          '  if (max(dot(sgDx, sgDx), dot(sgDy, sgDy)) < 0.0004) {', // not across an atlas seam
          '  float sgH0 = sgH(vMapUv), sgK = 0.0016 * sgWet; vec2 sgG = vec2((sgH(vMapUv + sgDx) - sgH0) / max(length(sgPx), 1e-6), (sgH(vMapUv + sgDy) - sgH0) / max(length(sgPy), 1e-6)) * sgK;',
          '  vec3 sgSx = normalize(sgPx), sgSy = normalize(sgPy), sgR1 = cross(sgSy, normal), sgR2 = cross(normal, sgSx); float sgDet = dot(sgSx, sgR1);',
          '  normal = normalize(abs(sgDet) * normal - sign(sgDet) * (sgG.x * sgR1 + sgG.y * sgR2)); } }'].join('\n'))
        .replace('#include <opaque_fragment>', [
          'if (sgWet > 0.003) outgoingLight += sgWet * (pow(max(dot(normal, normalize(vec3(-0.3, 0.62, 0.72))), 0.0), 42.0) * 0.6 + pow(1.0 - saturate(dot(normal, normalize(vViewPosition))), 3.0) * 0.14);', // wet paint always catches a highlight, wherever the room lights are
          'if (uCur.z > 0.5) { float sgD = length(-vViewPosition - uCurV), sgPx1 = max(fwidth(sgD), 1e-5);',
          '  float sgOut = 1.0 - smoothstep(sgPx1 * 2.2, sgPx1 * 3.6, abs(sgD - uCur.x)), sgRing = 1.0 - smoothstep(sgPx1 * 0.9, sgPx1 * 2.0, abs(sgD - uCur.x));',
          '  float sgIn = (1.0 - smoothstep(sgPx1 * 0.5, sgPx1 * 1.5, abs(sgD - uCur.x * uCur.y))) * step(uCur.y, 0.97) * 0.5;',
          '  float sgDot = 1.0 - smoothstep(uCur.x * 0.11, uCur.x * 0.11 + sgPx1 * 1.5, sgD), sgDotO = 1.0 - smoothstep(uCur.x * 0.11 + sgPx1 * 1.5, uCur.x * 0.11 + sgPx1 * 3.0, sgD);',
          '  outgoingLight = mix(outgoingLight, vec3(0.03), max(sgOut * 0.6, sgDotO * 0.6 * uCur.w)); outgoingLight = mix(outgoingLight, vec3(1.0), max(sgRing, sgIn));',
          '  outgoingLight = mix(outgoingLight, uCurCol, sgDot * uCur.w); }',
          '#include <opaque_fragment>'].join('\n'));
    };
    c.mat.customProgramCacheKey = function () { return key0 + '+paintfx'; };
    c.mat.needsUpdate = true;
    return fx;
  };
  /* painted flag (wet.b): set wherever the body is no longer plain white. parts = only these part indices. */
  P.reflag = function (c, parts, keep) {
    var fx = c._fx, A = c.A, alb = c.alb, w = fx.wet; if (!fx.fast) return;
    for (var pi = 0; pi < c.parts.length; pi++) { if (parts && !parts[pi]) continue; var p = c.parts[pi];
      for (var j = 0; j < p.th; j++) for (var o = ((p.ry + j) * A + p.rx) * 4, e = o + p.tw * 4; o < e; o += 4) { var wh = alb[o] === 255 && alb[o + 1] === 255 && alb[o + 2] === 255; if (!wh) w[o + 2] = 255; else if (!keep) w[o + 2] = 0; } }
    if (fx.tex) fx.tex.needsUpdate = true;
  };
  P.tick = function () { return 1 + (Math.floor(this.t * TICK) % WRAP); };

  /* one dab of the 3D brush. Same result on albedo/roughness/metalness as Critter.paint, plus the wet layer. Returns texels touched. */
  P.dab = function (c, wp, radius, rgb, rough, metal, hard, op) {
    var fx = c._fx || this.attach(c), t0 = performance.now(), n = 0;
    if (!fx.fast) { n = c.paint(wp, radius, rgb, rough, metal, hard) ? 1 : 0; return n; }
    var A = c.A, alb = c.alb, orm = c.orm, wet = fx.wet, R = radius / c.scale, R2 = R * R, tick = this.tick();
    hard = hard == null ? 0.7 : hard; op = op == null ? 1 : op;
    var inner = R * hard, span = Math.max(1e-5, R - inner), wIn = R * 0.5, wSpan = R * 0.5, rb = Math.round(rough * 255), mb = Math.round(metal * 255), cr = rgb[0], cg = rgb[1], cb = rgb[2];
    for (var pi = 0; pi < c.parts.length; pi++) {
      var p = c.parts[pi];
      var sp = space(c, p); _v.copy(wp).applyMatrix4(_m.copy(sp.E).invert()).sub(sp.off);
      if (_v.distanceTo(p.c) > R + p.r) continue;
      var g = p._g && p._g.ver === sp.ver ? p._g : buildGrid(p, sp.tp, sp.ver), lx = _v.x, ly = _v.y, lz = _v.z, cs = g.cs;
      var ax0 = Math.max(0, Math.floor((lx - R - g.x0) / cs)), ax1 = Math.min(g.nx - 1, Math.floor((lx + R - g.x0) / cs)), ay0 = Math.max(0, Math.floor((ly - R - g.y0) / cs)), ay1 = Math.min(g.ny - 1, Math.floor((ly + R - g.y0) / cs)), az0 = Math.max(0, Math.floor((lz - R - g.z0) / cs)), az1 = Math.min(g.nz - 1, Math.floor((lz + R - g.z0) / cs));
      if (ax0 > ax1 || ay0 > ay1 || az0 > az1) continue;
      var tp = sp.tp, tw = p.tw, st = g.start, idx = g.idx, saved = false, dr = fx.dirty[pi], i0 = 1e9, j0 = 1e9, i1 = -1, j1 = -1, base = (p.ry * A + p.rx) * 4;
      for (var cz = az0; cz <= az1; cz++) for (var cy = ay0; cy <= ay1; cy++) { var row = (cz * g.ny + cy) * g.nx;
        for (var q = st[row + ax0], qe = st[row + ax1 + 1]; q < qe; q++) {
          var k = idx[q], k3 = k * 3, dx = tp[k3] - lx, dy = tp[k3 + 1] - ly, dz = tp[k3 + 2] - lz, d2 = dx * dx + dy * dy + dz * dz;
          if (d2 > R2) continue;
          if (!saved) { saved = true; if (c._stroke && c._save) c._save(pi); }
          var d = Math.sqrt(d2), a = d <= inner ? 1 : 1 - (d - inner) / span; a = a * a * (3 - 2 * a) * op;
          var ti = k % tw, tj = (k - ti) / tw, o = base + (tj * A + ti) * 4;
          alb[o] += (cr - alb[o]) * a; alb[o + 1] += (cg - alb[o + 1]) * a; alb[o + 2] += (cb - alb[o + 2]) * a;
          orm[o + 1] += (rb - orm[o + 1]) * a; orm[o + 2] += (mb - orm[o + 2]) * a;
          var wa = d <= wIn ? 1 : 1 - (d - wIn) / wSpan; wa = wa * wa * (3 - 2 * wa) * 255;
          var s0 = wet[o], dry = s0 === 0 || ((tick - s0 + WRAP) % WRAP) > WET_SEC * TICK;
          wet[o + 1] = dry ? wa : Math.max(wet[o + 1], wa); wet[o] = tick; if (a > 0.35) wet[o + 2] = 255;
          if (ti < i0) i0 = ti; if (ti > i1) i1 = ti; if (tj < j0) j0 = tj; if (tj > j1) j1 = tj; n++;
        } }
      if (i1 >= 0) { if (!dr) fx.dirty[pi] = [p.rx + i0, p.ry + j0, p.rx + i1 + 1, p.ry + j1 + 1]; else { dr[0] = Math.min(dr[0], p.rx + i0); dr[1] = Math.min(dr[1], p.ry + j0); dr[2] = Math.max(dr[2], p.rx + i1 + 1); dr[3] = Math.max(dr[3], p.ry + j1 + 1); } }
    }
    if (n) { fx.live = true; fx.lastDab = this.t; fx.any = true; }
    var ms = performance.now() - t0, S = this.stats; S.dabs++; S.dabMs += ms; if (ms > S.dabMax) S.dabMax = ms; S.texels += n;
    return n;
  };

  function glTex(R, tex) { var pr = R.properties.get(tex); return pr && pr.__webglTexture && pr.__version === tex.version ? pr.__webglTexture : null; }
  /* push the texels painted since the last frame to the GPU. Called once per frame before the scene is drawn. */
  P.flush = function (c) {
    var fx = c._fx; if (!fx) return;
    var R = this.R, gl = R.getContext(), st = R.state, t0 = performance.now(), A = c.A, keys = Object.keys(fx.dirty), S = this.stats;
    if (keys.length) {
      var gA = glTex(R, c.texA), gO = glTex(R, c.texO), gW = glTex(R, fx.tex);
      if (!gA || !gO || !st.pixelStorei) { c.texA.needsUpdate = true; c.texO.needsUpdate = true; fx.tex.needsUpdate = true; S.full++; } // not on the GPU yet (or changed elsewhere): the normal full upload does it
      else {
        if (fx.verA !== c.texA.version || !fx.mipA) { fx.mipA = mipChain(c.alb, A); fx.verA = c.texA.version; }
        if (fx.verO !== c.texO.version || !fx.mipO) { fx.mipO = mipChain(c.orm, A); fx.verO = c.texO.version; }
        st.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, false); st.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false); st.pixelStorei(gl.UNPACK_ALIGNMENT, 4);
        var jobs = [[gA, fx.mipA, true], [gO, fx.mipO, true]]; if (gW) jobs.push([gW, [fx.wet], false]); else fx.tex.needsUpdate = true;
        for (var ji = 0; ji < jobs.length; ji++) { var job = jobs[ji], L = job[1]; st.bindTexture(gl.TEXTURE_2D, job[0]);
          for (var ki = 0; ki < keys.length; ki++) { var d = fx.dirty[keys[ki]], x0 = d[0], y0 = d[1], x1 = d[2], y1 = d[3], s = A;
            for (var lv = 0; lv < L.length; lv++) {
              if (lv > 0) { x0 >>= 1; y0 >>= 1; x1 = (x1 + 1) >> 1; y1 = (y1 + 1) >> 1; down(L[lv - 1], s, L[lv], x0, y0, x1, y1); s >>= 1; }
              st.pixelStorei(gl.UNPACK_ROW_LENGTH, s); st.pixelStorei(gl.UNPACK_SKIP_PIXELS, x0); st.pixelStorei(gl.UNPACK_SKIP_ROWS, y0);
              gl.texSubImage2D(gl.TEXTURE_2D, lv, x0, y0, x1 - x0, y1 - y0, gl.RGBA, gl.UNSIGNED_BYTE, L[lv]); S.sub++;
              if (!job[2]) break; } } }
        st.pixelStorei(gl.UNPACK_ROW_LENGTH, 0); st.pixelStorei(gl.UNPACK_SKIP_PIXELS, 0); st.pixelStorei(gl.UNPACK_SKIP_ROWS, 0); st.bindTexture(gl.TEXTURE_2D, null);
      }
      fx.dirty = {};
    }
    // dry stamps are cleared now and then so the 8-bit clock can wrap
    if (fx.live && this.t - fx.sweepT > 4) { fx.sweepT = this.t; var w = fx.wet, tk = this.tick(), left = 0;
      for (var o = 0; o < w.length; o += 4) { var s0 = w[o]; if (s0) { if (((tk - s0 + WRAP) % WRAP) > (WET_SEC + 0.5) * TICK) { w[o] = 0; w[o + 1] = 0; } else left++; } }
      fx.live = left > 0; fx.tex.needsUpdate = true; }
    var u = fx.u, cu = this.cur; u.uWetNow.value = 1 + ((this.t * TICK) % WRAP);
    u.uCur.value.set(cu.r, cu.hard, cu.on && cu.c === c ? 1 : 0, cu.dot ? 1 : 0); u.uCurV.value.copy(cu.pos).applyMatrix4(cu.cam ? cu.cam.matrixWorldInverse : _m.identity()); u.uCurCol.value.setRGB(cu.rgb[0] / 255, cu.rgb[1] / 255, cu.rgb[2] / 255, THREE.SRGBColorSpace);
    u.uHiW.value = this.hi * (0.78 + 0.2 * Math.sin(this.t * 9));
    var ms = performance.now() - t0; if (keys.length) { S.flushMs = ms; if (ms > S.flushMax) S.flushMax = ms; }
  };

  /* fill with a wipe: top to bottom over `sec` seconds. parts = {index: true} or null for the whole body. done() is called at the end. */
  P.fill = function (c, rgb, rough, metal, parts, sec, done) {
    var fx = c._fx || this.attach(c); if (fx.fillJob) this.finishFill(c);
    if (!fx.fast) { c.fill(rgb, rough, metal); if (done) done(); return; }
    var lo = 1e9, hi = -1e9, keys = [], pi, p;
    c.root.updateMatrixWorld(true);
    for (pi = 0; pi < c.parts.length; pi++) { if (parts && !parts[pi]) continue; p = c.parts[pi]; if (c._stroke && c._save) c._save(pi);
      var sp = space(c, p), e = sp.E.elements, tp = sp.tp, ox = sp.off.x, oy = sp.off.y, oz = sp.off.z, n = p.tw * p.th, key = new Float32Array(n);
      for (var i = 0, k = 0; i < n; i++, k += 3) { if (tp[k] > 1e8) { key[i] = 1e9; continue; } var tx = tp[k] + ox, ty = tp[k + 1] + oy, tz = tp[k + 2] + oz, y = e[1] * tx + e[5] * ty + e[9] * tz + e[13] + 0.25 * (e[0] * tx + e[4] * ty + e[8] * tz + e[12]); key[i] = y; if (y < lo) lo = y; if (y > hi) hi = y; }
      keys.push([pi, key]); }
    fx.fillJob = { keys: keys, lo: lo, hi: hi, t: 0, sec: sec || 0.45, p: 0, rgb: rgb, rb: Math.round(rough * 255), mb: Math.round(metal * 255), done: done };
  };
  P.finishFill = function (c) { var fx = c._fx; if (fx && fx.fillJob) { fx.fillJob.t = fx.fillJob.sec; this._fillStep(c, 0); } };
  P._fillStep = function (c, dt) {
    var fx = c._fx, J = fx.fillJob; J.t += dt; var p1 = Math.min(1, J.t / J.sec), A = c.A, alb = c.alb, orm = c.orm, wet = fx.wet, tick = this.tick();
    var hiY = J.hi - (J.hi - J.lo) * J.p, loY = p1 >= 1 ? -1e9 : J.hi - (J.hi - J.lo) * p1, band = (J.hi - J.lo) * 0.06 + 1e-6;
    for (var q = 0; q < J.keys.length; q++) { var p = c.parts[J.keys[q][0]], key = J.keys[q][1], tw = p.tw, th = p.th, k = 0;
      for (var j = 0; j < th; j++) for (var o = ((p.ry + j) * A + p.rx) * 4, i = 0; i < tw; i++, k++, o += 4) { var y = key[k];
        if (y > 1e8) { if (J.p === 0) { alb[o] = J.rgb[0]; alb[o + 1] = J.rgb[1]; alb[o + 2] = J.rgb[2]; orm[o + 1] = J.rb; orm[o + 2] = J.mb; wet[o + 2] = 255; } continue; } // padding texels take the colour at once
        if (y > hiY + band || y < loY) continue;
        alb[o] = J.rgb[0]; alb[o + 1] = J.rgb[1]; alb[o + 2] = J.rgb[2]; orm[o + 1] = J.rb; orm[o + 2] = J.mb; wet[o + 2] = 255;
        wet[o] = tick; wet[o + 1] = Math.max(40, Math.min(255, 255 - (y - loY) / band * 215)); } } // thick bead at the wipe front, thinning behind it
    J.p = p1; fx.live = true; fx.lastDab = this.t; c.texA.needsUpdate = true; c.texO.needsUpdate = true; fx.tex.needsUpdate = true; fx.dirty = {};
    if (p1 >= 1) { fx.fillJob = null; if (J.done) J.done(); }
  };

  /* droplets flung off a fast stroke */
  P.spray = function (pos, vel, rgb, size) {
    var d = null; for (var i = 0; i < this.dl.length; i++) if (this.dl[i].t <= 0) { d = this.dl[i]; this.drops.setColorAt(i, new THREE.Color().setRGB(rgb[0] / 255, rgb[1] / 255, rgb[2] / 255, THREE.SRGBColorSpace)); break; }
    if (!d) return; d.t = 0.55; d.p.copy(pos); d.v.copy(vel); d.s = size; this.drops.instanceColor.needsUpdate = true;
  };
  P.update = function (dt, c) {
    this.t += dt;
    if (c && c._fx && c._fx.fillJob) this._fillStep(c, dt);
    var any = false, dm = this.drops, n = 0;
    for (var i = 0; i < this.dl.length; i++) { var d = this.dl[i]; if (d.t <= 0) { _m.makeScale(0, 0, 0); dm.setMatrixAt(i, _m); continue; }
      d.t -= dt; d.v.y -= 6.5 * dt; d.p.addScaledVector(d.v, dt); var s = d.s * Math.min(1, d.t / 0.2); _m.makeScale(s, s, s).setPosition(d.p); dm.setMatrixAt(i, _m); any = true; n = i + 1; }
    dm.count = n; dm.visible = any; if (any || this._hadDrops) dm.instanceMatrix.needsUpdate = true; this._hadDrops = any;
  };

  /* "white left": the share of the outward-facing body that is still unpainted white. One view per call (six views around the
     body; a view whose side is pressed against something is skipped by blocked(dir)). Returns the latest percentage. */
  var DIRS = [[1, 0, 0], [-1, 0, 0], [0, 0, 1], [0, 0, -1], [0, 1, 0], [0, -1, 0]];
  P.whiteLeft = function (c, blocked, all) {
    var fx = c._fx || this.attach(c), W = this.wl, R = this.R, ctr = c.center(_v).clone(), h = 0.55 * c.scale, cam = this.wcam, rounds = all ? 6 : 1;
    if (all) { W.i = 0; W.w = 0; W.n = 0; }
    for (var r = 0; r < rounds; r++) {
      var d = DIRS[W.i];
      if (!(blocked && blocked(ctr, d))) {
        cam.left = -h; cam.right = h; cam.top = h; cam.bottom = -h; cam.near = 0.01; cam.far = 4; cam.updateProjectionMatrix();
        cam.position.set(ctr.x + d[0] * 2, ctr.y + d[1] * 2, ctr.z + d[2] * 2); cam.up.set(0, d[1] ? 0 : 1, d[1] ? 1 : 0); cam.lookAt(ctr); cam.updateMatrixWorld(true);
        var om = c.skin.material, rt0 = R.getRenderTarget(), au = R.autoClear; this.wmat.uniforms.map.value = c.texA; this.wmat.uniforms.uWet.value = fx.tex; c.skin.material = this.wmat;
        var lm = cam.layers.mask; cam.layers.mask = c.skin.layers.mask; R.autoClear = true; R.setRenderTarget(this.rt); R.setClearColor(0x000000, 0); R.clear(); R.render(c.skin, cam); R.readRenderTargetPixels(this.rt, 0, 0, 40, 40, this.px); R.setRenderTarget(rt0); R.autoClear = au; cam.layers.mask = lm; c.skin.material = om;
        for (var i = 0, px = this.px; i < px.length; i += 4) { if (px[i + 3] > 128) { W.n++; if (px[i] > 128) W.w++; } }
      }
      W.i++; if (W.i >= 6) { W.pct = W.n ? Math.round(100 * W.w / W.n) : 0; W.i = 0; W.w = 0; W.n = 0; }
    }
    return W.pct;
  };
  SG.PaintFX = PaintFX;
})();
