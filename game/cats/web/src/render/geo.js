/* 貓躲狗找 — geometry helpers: rounded boxes, lathes, merging, small utilities. */
(function () {
  'use strict';
  var SG = (window.SG = window.SG || {});
  var G = (SG.geo = {});

  /* Rounded box with real box UVs. uvm=true gives UVs in metres (for repeating textures). */
  G.rbox = function (w, h, d, r, opt) {
    opt = opt || {};
    var k = opt.k || 3, uvm = opt.uvm;
    r = Math.min(r, w / 2 - 1e-4, h / 2 - 1e-4, d / 2 - 1e-4);
    function samples(half) {
      var s = [], i;
      for (i = k; i >= 0; i--) s.push(-(half - r) - r * Math.tan((i / k) * Math.PI / 4));
      for (i = 0; i <= k; i++) s.push((half - r) + r * Math.tan((i / k) * Math.PI / 4));
      return s;
    }
    var pos = [], nor = [], uv = [], idx = [];
    var dims = [w / 2, h / 2, d / 2];
    // faces: axis index for u, v, and normal with sign
    var faces = [[2, 1, 0, 1, -1], [2, 1, 0, -1, 1], [0, 2, 1, 1, -1], [0, 2, 1, -1, 1], [0, 1, 2, 1, 1], [0, 1, 2, -1, -1]];
    faces.forEach(function (f) {
      var ua = f[0], va = f[1], na = f[2], sg = f[3], uflip = f[4];
      var su = samples(dims[ua]), sv = samples(dims[va]), base = pos.length / 3, nu = su.length, nv = sv.length;
      for (var j = 0; j < nv; j++) for (var i = 0; i < nu; i++) {
        var p = [0, 0, 0]; p[ua] = su[i]; p[va] = sv[j]; p[na] = sg * dims[na];
        var c = [0, 0, 0], q;
        for (q = 0; q < 3; q++) c[q] = Math.max(-(dims[q] - r), Math.min(dims[q] - r, p[q]));
        var dx = p[0] - c[0], dy = p[1] - c[1], dz = p[2] - c[2], l = Math.hypot(dx, dy, dz) || 1;
        dx /= l; dy /= l; dz /= l;
        pos.push(c[0] + dx * r, c[1] + dy * r, c[2] + dz * r); nor.push(dx, dy, dz);
        var U = su[i] * uflip * sg, V = sv[j];
        if (na === 1) { U = su[i]; V = -sv[j] * sg; }
        if (uvm) uv.push(U + dims[ua], V + dims[va]); else uv.push(U / (2 * dims[ua]) + 0.5, V / (2 * dims[va]) + 0.5);
      }
      // pick winding by testing the centre quad against the face normal
      var mi = Math.floor(nu / 2) - 1, mj = Math.floor(nv / 2) - 1, A = base + mj * nu + mi, B = A + 1, C = A + nu;
      var e1 = [pos[B * 3] - pos[A * 3], pos[B * 3 + 1] - pos[A * 3 + 1], pos[B * 3 + 2] - pos[A * 3 + 2]];
      var e2 = [pos[C * 3] - pos[A * 3], pos[C * 3 + 1] - pos[A * 3 + 1], pos[C * 3 + 2] - pos[A * 3 + 2]];
      var cr = [e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0]];
      var cw = cr[na] * sg < 0;
      for (j = 0; j < nv - 1; j++) for (i = 0; i < nu - 1; i++) {
        var a = base + j * nu + i, b = a + 1, cc = a + nu, dd = cc + 1;
        if (cw) idx.push(a, cc, b, b, cc, dd); else idx.push(a, b, cc, b, dd, cc);
      }
    });
    var g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
    g.setAttribute('normal', new THREE.Float32BufferAttribute(nor, 3));
    g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
    g.setIndex(idx);
    return g;
  };

  /* Lathe from [r,y] pairs. */
  G.lathe = function (pts, seg) {
    return new THREE.LatheGeometry(pts.map(function (p) { return new THREE.Vector2(Math.max(p[0], 0.0001), p[1]); }), seg || 24);
  };
  /* smooth lathe through control points (Catmull-Rom) */
  G.latheS = function (pts, seg, div) {
    var c = new THREE.SplineCurve(pts.map(function (p) { return new THREE.Vector2(p[0], p[1]); }));
    var out = c.getPoints(div || pts.length * 5).map(function (v) { return new THREE.Vector2(Math.max(v.x, 0.0001), v.y); });
    return new THREE.LatheGeometry(out, seg || 24);
  };
  G.tube = function (pts, r, seg, rad) {
    var c = new THREE.CatmullRomCurve3(pts.map(function (p) { return new THREE.Vector3(p[0], p[1], p[2]); }));
    return new THREE.TubeGeometry(c, seg || 24, r, rad || 8, false);
  };

  /* merge geometries (position/normal/uv, indexed or not). items: [geometry, Matrix4?] */
  var _m3 = new THREE.Matrix3(), _v = new THREE.Vector3();
  G.merge = function (items) {
    var pos = [], nor = [], uv = [], idx = [], base = 0;
    items.forEach(function (it) {
      var g = it[0] || it, m = it[1];
      var p = g.attributes.position, n = g.attributes.normal, u = g.attributes.uv, i;
      if (m) _m3.getNormalMatrix(m);
      for (i = 0; i < p.count; i++) {
        _v.fromBufferAttribute(p, i); if (m) _v.applyMatrix4(m); pos.push(_v.x, _v.y, _v.z);
        _v.fromBufferAttribute(n, i); if (m) _v.applyMatrix3(_m3).normalize(); nor.push(_v.x, _v.y, _v.z);
        if (u) uv.push(u.getX(i), u.getY(i)); else uv.push(0, 0);
      }
      if (g.index) for (i = 0; i < g.index.count; i++) idx.push(g.index.getX(i) + base);
      else for (i = 0; i < p.count; i++) idx.push(i + base);
      base += p.count;
    });
    var out = new THREE.BufferGeometry();
    out.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
    out.setAttribute('normal', new THREE.Float32BufferAttribute(nor, 3));
    out.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
    out.setIndex(idx);
    return out;
  };
  G.mat4 = function (x, y, z, rx, ry, rz, sx, sy, sz) {
    var m = new THREE.Matrix4();
    m.compose(new THREE.Vector3(x || 0, y || 0, z || 0), new THREE.Quaternion().setFromEuler(new THREE.Euler(rx || 0, ry || 0, rz || 0)),
      new THREE.Vector3(sx == null ? 1 : sx, sy == null ? (sx == null ? 1 : sx) : sy, sz == null ? (sx == null ? 1 : sx) : sz));
    return m;
  };

  /* plane with UVs in metres, facing +Z, centred */
  G.planeM = function (w, h) {
    var g = new THREE.PlaneGeometry(w, h);
    var u = g.attributes.uv;
    for (var i = 0; i < u.count; i++) u.setXY(i, u.getX(i) * w, u.getY(i) * h);
    return g;
  };
  /* box with UVs in metres */
  G.boxM = function (w, h, d) {
    var g = new THREE.BoxGeometry(w, h, d), u = g.attributes.uv, n = g.attributes.normal;
    for (var i = 0; i < u.count; i++) {
      var ax = Math.abs(n.getX(i)), ay = Math.abs(n.getY(i));
      var su = ax > 0.5 ? d : w, sv = ay > 0.5 ? d : h;
      u.setXY(i, u.getX(i) * su, u.getY(i) * sv);
    }
    return g;
  };
})();
