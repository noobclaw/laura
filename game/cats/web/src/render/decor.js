/* 貓躲狗找 — colour pass (owner's direction 2026-11-25: stylised-realistic and colour-rich, so that there is always a colour
   nearby to paint yourself into). Every interior area gets, in at least 24 hues:
   - thin things lying on the floor (mats, cloth, papers, tiles: 15-50 cm, no collision, 1-2 cm high),
   - a patchwork wainscot and hanging cloths / pictures along the walls,
   - one big multi-colour surface (a patchwork hanging and a patchwork rug).
   Everything is a flat-coloured box, so it all merges into the existing static batches: no extra draw calls.
   Three wall patches are left plain on purpose (contrast, and the camouflage measurement uses them). */
(function () {
  'use strict';
  var SG = (window.SG = window.SG || {});
  /* plan units, the same rectangles the palette tool measures */
  SG.AREAS = { '客廳': [-4.5, 4.5, -3.5, 2.55], '廚房': [-2.5, 2.5, -6.1, -3.5], '玄關': [-6.7, -4.5, -3.5, 2.9], '和室': [2.6, 7.0, -7.5, -3.5], '書房': [4.62, 8, -3.5, -0.55], '浴室': [4.62, 8, -0.55, 2.3], '倉庫': [-6.7, -2.56, -6.5, -3.62], '西巷': [-8.6, -6.82, -3.5, 2.3], '北巷': [-2.5, 8.6, -8.6, -6.3], '東巷': [8.0, 8.6, -8.6, 2.3], '庭院': [-8, 8, 4.0, 8.7] };
  var PLAIN = [[4.78, -1.05], [-0.3, -6.4], [7.4, -0.35]]; // kept plain within 1.3 m
  function hsl(h, s, l) { // -> 0xRRGGBB
    h = ((h % 360) + 360) % 360 / 360; var q = l < 0.5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q;
    function f(t) { t = (t + 1) % 1; return t < 1 / 6 ? p + (q - p) * 6 * t : t < 0.5 ? q : t < 2 / 3 ? p + (q - p) * (2 / 3 - t) * 6 : p; }
    return (Math.round(f(h + 1 / 3) * 255) << 16) | (Math.round(f(h) * 255) << 8) | Math.round(f(h - 1 / 3) * 255);
  }
  /* surface detail for flat-coloured materials: soft mottling, fine grain, dirty patches, grime where walls meet the floor,
     a little roughness variation and a shallow relief. All of it is worked out from the world position, so a body lying flush
     on a surface can show exactly the same detail (opt.flat: the uniform that says how flush it is, opt.flatN: that surface's normal).
     SG.detailU.value = 0 turns it off (the eyedropper and every other unlit base-colour render must not see dirt). */
  SG.detailU = { value: 1 };
  SG.surfaceDetail = function (mat, key, opt) {
    opt = opt || {}; var prev = mat.onBeforeCompile, hadPrev = prev !== THREE.Material.prototype.onBeforeCompile, k0 = mat.customProgramCacheKey && hadPrev ? mat.customProgramCacheKey() : '';
    mat.onBeforeCompile = function (sh, r) {
      if (hadPrev) prev.call(this, sh, r); sh.uniforms.uDet = SG.detailU;
      sh.vertexShader = sh.vertexShader.replace('#include <common>', '#include <common>\nvarying vec3 vSgW;').replace('#include <project_vertex>', '#include <project_vertex>\n vSgW = (modelMatrix * vec4(transformed, 1.0)).xyz;');
      var wn = opt.flat ? 'normalize(mix(inverseTransformDirection(normalize(vNormal), viewMatrix), uFlatN, step(0.5, uFlat)))' : 'inverseTransformDirection(normalize(vNormal), viewMatrix)', amt = opt.flat ? 'uDet * smoothstep(0.5, 0.9, uFlat)' : 'uDet';
      sh.fragmentShader = sh.fragmentShader.replace('#include <common>', ['#include <common>', 'varying vec3 vSgW; uniform float uDet; float sgDA = 0.0; vec2 sgDP = vec2(0.0); float sgDM = 0.5, sgDD = 0.0;',
        'float sgHs(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }',
        'float sgNs(vec2 p){ vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f); return mix(mix(sgHs(i), sgHs(i + vec2(1.0, 0.0)), f.x), mix(sgHs(i + vec2(0.0, 1.0)), sgHs(i + vec2(1.0, 1.0)), f.x), f.y); }',
        'float sgFb(vec2 p){ return sgNs(p) * 0.5 + sgNs(p * 2.3 + 7.1) * 0.3 + sgNs(p * 5.1 + 3.7) * 0.2; }',
        'float sgHt(vec2 p){ return sgFb(p * 7.0) * 0.6 + sgNs(p * 46.0) * 0.4; }'].join('\n'))
        .replace('#include <map_fragment>', ['#include <map_fragment>',
          '{ vec3 sgN3 = ' + wn + '; vec3 sgA = abs(sgN3); sgDP = sgA.y > sgA.x && sgA.y > sgA.z ? vSgW.xz : (sgA.x > sgA.z ? vSgW.zy : vSgW.xy); sgDA = ' + amt + ';',
          '  sgDM = sgFb(sgDP * 2.6); float sgFine = sgNs(sgDP * 46.0); sgDD = smoothstep(0.56, 0.86, sgFb(sgDP * 0.8 + 13.0));',
          '  float sgGr = sgA.y < 0.5 ? (1.0 - smoothstep(0.0, 0.3, vSgW.y)) * step(-0.05, vSgW.y) : 0.0;',
          '  diffuseColor.rgb *= 1.0 + sgDA * ((sgDM - 0.5) * 0.07 + (sgFine - 0.5) * 0.035 - sgDD * 0.04 - sgGr * 0.07); }'].join('\n'))
        .replace('#include <roughnessmap_fragment>', '#include <roughnessmap_fragment>\n roughnessFactor = clamp(roughnessFactor + sgDA * ((sgDM - 0.5) * 0.22 + sgDD * 0.08), 0.04, 1.0);');
      var bump = ['if (sgDA > 0.01) { vec3 sgQ = -vViewPosition, sgQx = dFdx(sgQ), sgQy = dFdy(sgQ); vec2 sgUx = dFdx(sgDP), sgUy = dFdy(sgDP); float sgH0 = sgHt(sgDP);',
        '  vec2 sgGd = vec2((sgHt(sgDP + sgUx) - sgH0) / max(length(sgQx), 1e-6), (sgHt(sgDP + sgUy) - sgH0) / max(length(sgQy), 1e-6)) * 0.0011 * sgDA;',
        '  vec3 sgTx = normalize(sgQx), sgTy = normalize(sgQy), sgB1 = cross(sgTy, normal), sgB2 = cross(normal, sgTx); float sgDt = dot(sgTx, sgB1); normal = normalize(abs(sgDt) * normal - sign(sgDt) * (sgGd.x * sgB1 + sgGd.y * sgB2)); }'].join('\n');
      if (opt.flat && sh.fragmentShader.indexOf('// SG_AFTER_FLAT') >= 0) sh.fragmentShader = sh.fragmentShader.replace('// SG_AFTER_FLAT', '\n' + bump);
      else sh.fragmentShader = sh.fragmentShader.replace('#include <normal_fragment_maps>', '#include <normal_fragment_maps>\n' + bump);
    };
    mat.customProgramCacheKey = function () { return k0 + '+detail:' + key; }; mat.needsUpdate = true;
  };
  SG.buildDecor = function (K) {
    var G = SG.geo, P = K.platforms, r = SG.rng(4242), add = K.add, col = K.col, stats = { floor: 0, wall: 0, big: 0 };
    K.setRoom('色彩'); K.begin(null, 0, 0, 0);
    // dyed-cloth / painted-wood colours: every 15 degrees of hue, three depths
    function hue(i, depth) { var h = (i % 24) * 15 + 7, d = depth == null ? Math.floor(r() * 3) : depth; return hsl(h, [0.36, 0.44, 0.38][d] + (h > 40 && h < 80 ? 0.1 : 0), [0.64, 0.47, 0.32][d]); } // dyed cloth and painted wood, not plastic
    function solidAt(x, z, y0, y1, pad) { for (var i = 0; i < P.length; i++) { var p = P[i]; if (p.y1 <= y0 || p.y0 >= y1) continue; if (x > p.x0 - pad && x < p.x1 + pad && z > p.z0 - pad && z < p.z1 + pad) return p; } return null; }
    function nearPlain(x, z) { for (var i = 0; i < PLAIN.length; i++) if (Math.hypot(x - PLAIN[i][0], z - PLAIN[i][1]) < 1.3) return true; return false; }
    function box(w, h, d, c, x, y, z, ry, rough) { var m = add(G.boxM(w, h, d), col(c, rough == null ? 0.86 : rough), x, y, z, 0, ry || 0, 0); m.userData.noShadow = true; return m; }
    var hi = 0;
    Object.keys(SG.AREAS).forEach(function (name) {
      var a = SG.AREAS[name], x0 = a[0], x1 = a[1], z0 = a[2], z1 = a[3], outdoor = name === '庭院', alley = /巷/.test(name), base = outdoor ? -0.3 : 0, area = (x1 - x0) * (z1 - z0);
      // ---- on the floor: thin mats, cloths, tiles, papers
      var want = Math.round(Math.max(44, Math.min(80, area * (alley ? 2.6 : 1.5)))), tries = 0, placed = [], mgx = Math.min(0.25, (x1 - x0) * 0.2), mgz = Math.min(0.25, (z1 - z0) * 0.2);
      for (var pass = 0, maxTop = 0.2; pass < 2; pass++, maxTop = 1.0, tries = 0) { if (pass && placed.length >= want * 0.75) break; // second pass (crowded rooms): cloths and mats also go on top of crates and low furniture
      while (placed.length < want && tries++ < want * 60) {
        var x = x0 + mgx + r() * (x1 - x0 - 2 * mgx), z = z0 + mgz + r() * (z1 - z0 - 2 * mgz), w = 0.16 + r() * 0.32, d = 0.16 + r() * 0.3;
        if (outdoor && z < 4.3) continue;
        var gp = solidAt(x, z, base - 0.2, base + 0.6, 0.16); if (gp) { if (gp.y1 > base + maxTop || gp.wall) continue; } // on the floor or on a low platform top, never inside furniture
        var top = base; for (var q = 0; q < P.length; q++) { var pp = P[q]; if (!pp.wall && pp.y1 <= base + maxTop && pp.y1 > top && x > pp.x0 + 0.2 && x < pp.x1 - 0.2 && z > pp.z0 + 0.2 && z < pp.z1 - 0.2) top = pp.y1; }
        if (gp && top === base) continue;
        var ok = true; for (q = 0; q < placed.length; q++) if (Math.hypot(placed[q][0] - x, placed[q][1] - z) < 0.36) { ok = false; break; } if (!ok) continue;
        placed.push([x, z]); var c = hue(hi++), kind = r(), ry = r() * Math.PI, y = top + 0.004 + (placed.length % 5) * 0.0012;
        if (kind < 0.4) { box(w, 0.012, d, c, x, y + 0.006, z, ry); box(w * 0.82, 0.014, d * 0.82, hue(hi + 7, 0), x, y + 0.007, z, ry); } // mat with a border
        else if (kind < 0.7) { box(w * 0.9, 0.018, d * 0.6, c, x, y + 0.009, z, ry); box(w * 0.9, 0.019, d * 0.14, hue(hi + 11), x, y + 0.0095, z, ry); } // folded cloth with a stripe
        else if (kind < 0.94) { var n = 2 + Math.floor(r() * 2), s = Math.min(w, d) * 0.62; for (var ti = 0; ti < n * n; ti++) box(s / n * 0.94, 0.01, s / n * 0.94, hue(hi + ti * 5, ti % 3), x + ((ti % n) - (n - 1) / 2) * s / n * Math.cos(ry) - (Math.floor(ti / n) - (n - 1) / 2) * s / n * Math.sin(ry), y + 0.005, z + ((ti % n) - (n - 1) / 2) * s / n * Math.sin(ry) + (Math.floor(ti / n) - (n - 1) / 2) * s / n * Math.cos(ry), -ry); } // little tiles
        else { box(0.21, 0.004, 0.3, hue(hi, 0), x, y + 0.002, z, ry, 0.7); box(0.21, 0.004, 0.3, hue(hi + 9, 0), x + 0.05, y + 0.006, z + 0.04, ry + 0.5, 0.7); } // sheets of coloured paper
        stats.floor++;
      } }
      if (outdoor) return;
      // ---- big rug: patchwork, where there is free floor
      for (tries = 0; tries < 40; tries++) { var rx = x0 + 1 + r() * Math.max(0.1, x1 - x0 - 2), rz = z0 + 0.8 + r() * Math.max(0.1, z1 - z0 - 1.6), nx = alley ? 2 : 5, nz = alley ? 6 : 3, ps = 0.3;
        if ((x1 - x0) < (z1 - z0) && !alley) { nx = 3; nz = 5; } if (rx - nx * ps / 2 < x0 + 0.1 || rx + nx * ps / 2 > x1 - 0.1 || rz - nz * ps / 2 < z0 + 0.1 || rz + nz * ps / 2 > z1 - 0.1) continue;
        var clear = true; for (var cx = -1; cx <= 1 && clear; cx++) for (var cz = -1; cz <= 1; cz++) if (solidAt(rx + cx * nx * ps / 2, rz + cz * nz * ps / 2, 0.02, 0.5, 0.05)) { clear = false; break; } if (!clear) continue;
        box(nx * ps + 0.08, 0.008, nz * ps + 0.08, hue(hi + 3, 2), rx, 0.004, rz); for (var i = 0; i < nx; i++) for (var j = 0; j < nz; j++) box(ps * 0.95, 0.01, ps * 0.95, hue(hi + i * 2 + j * 3, (i + j) % 3), rx + (i - (nx - 1) / 2) * ps, 0.0085, rz + (j - (nz - 1) / 2) * ps);
        stats.big++; hi += 5; break; }
      // ---- along the walls: a patchwork wainscot low down (where flat bodies hide) and hangings higher up
      var quilt = false;
      for (var wi = 0; wi < P.length; wi++) { var p = P[wi]; if (!p.wall || p.y0 > 0.1 || p.y1 < 1.6) continue; var tx = p.x1 - p.x0, tz = p.z1 - p.z0, alongZ = tx < 0.35 && tz > 0.9, alongX = tz < 0.35 && tx > 0.9; if (!alongZ && !alongX) continue;
        for (var side = -1; side <= 1; side += 2) {
          var u0 = alongZ ? Math.max(p.z0, z0) : Math.max(p.x0, x0), u1 = alongZ ? Math.min(p.z1, z1) : Math.min(p.x1, x1), face = alongZ ? (side > 0 ? p.x1 : p.x0) : (side > 0 ? p.z1 : p.z0), off = face + side * 0.3; if (u1 - u0 < 0.8) continue;
          if (alongZ ? (off < x0 || off > x1) : (off < z0 || off > z1)) continue;
          var step = 0.44, row = 0;
          for (var u = u0 + 0.3; u < u1 - 0.3; u += step, row++) { var px = alongZ ? face + side * 0.012 : u, pz = alongZ ? u : face + side * 0.012, fx = alongZ ? off : u, fz = alongZ ? u : off;
            if (nearPlain(px, pz)) continue; if (solidAt(fx, fz, 0.05, 1.9, 0.02)) continue; // something stands in front (or it is a doorway post): leave it
            var ry2 = alongZ ? Math.PI / 2 : 0;
                        if (r() < 0.72) { var bw = 0.22 + r() * 0.2, bh = 0.14 + r() * 0.3; box(bw, bh, 0.022, hue(hi + row * 5, row % 3), px, bh / 2 + 0.012, pz, ry2); if (r() < 0.5) box(bw * 0.7, 0.1 + r() * 0.12, 0.03, hue(hi + row * 5 + 13, (row + 1) % 3), px, bh + 0.08, pz, ry2); stats.wall++; } // boards, boxes and folded things standing against the wall
            if (row % 3 === 1) { // a hanging cloth or a framed print at eye height
              var hw = 0.3 + r() * 0.12, hh = 0.36 + r() * 0.2, hy = 1.0 + r() * 0.35; box(hw + 0.04, hh + 0.04, 0.012, hue(hi + row + 9, 2), px, hy, pz, ry2); box(hw, hh, 0.016, hue(hi + row * 7 + 2, 0), px, hy, pz, ry2); box(hw * 0.5, hh * 0.5, 0.02, hue(hi + row * 7 + 14, 1), px, hy - hh * 0.1, pz, ry2); stats.wall++; }
            if (!quilt && row === 2 && u + 1.4 < u1) { // the big multi-colour surface: a patchwork quilt on the wall
              var okq = true; for (var t = 0; t < 4; t++) { var qu = u + 0.3 + t * 0.35; if (solidAt(alongZ ? off : qu, alongZ ? qu : off, 0.6, 1.9, 0.02) || nearPlain(alongZ ? px : qu, alongZ ? qu : pz)) okq = false; }
              if (okq) { for (var qi = 0; qi < 5; qi++) for (var qj = 0; qj < 3; qj++) { var uu = u + 0.2 + qi * 0.3, yy = 0.85 + qj * 0.3; box(0.29, 0.29, 0.02, hue(hi + qi * 2 + qj * 3, (qi + qj) % 3), alongZ ? px + side * 0.008 : uu, yy, alongZ ? uu : pz + side * 0.008, ry2); } quilt = true; stats.big++; }
            }
          }
          hi += 3;
        } }
    });
    K.decorStats = stats; if (K.count) K.count('色彩佈置');
  };
})();
