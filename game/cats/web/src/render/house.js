/* 貓躲狗找 — the rest of the house around the living room: kitchen, genkan + stair hall + loft, tatami room, garden.
   Runs inside SG.buildRoom (room.js) with its builder context K. Every prop is procedural. */
(function () {
  'use strict';
  var SG = (window.SG = window.SG || {});
  SG.buildHouse = function (K) {
    var G = SG.geo, P = SG.P, M = K.m, begin = K.begin, add = K.add, B = K.B, C = K.C, L = K.L, S = K.S, PL = K.PL, plat = K.plat, platG = K.platG, col = K.col, tx = K.tx, mat = K.mat, cloth = K.cloth, r = K.r;
    var W = K.W, D = K.D, H = K.H, EN = K.EN, up = K.updaters, PI = Math.PI;
    function root() { return begin(null, 0, 0, 0); }
    /* wall along x (ax='z': constant z) or along z (ax='x': constant x); adds the collider too */
    function wall(ax, pos, a0, a1, o) {
      o = o || {}; var y0 = o.y0 || 0, h = o.h || (H - y0), th = o.th || 0.12, m = o.m || M.plaster, len = a1 - a0, c = (a0 + a1) / 2;
      if (ax === 'x') { add(G.boxM(th, h, len), m, pos, y0 + h / 2, c); if (!y0 && !o.plain) { add(G.boxM(th + 0.03, 0.75, len), o.wm || M.hinoki, pos, 0.375, c); add(G.boxM(th + 0.05, 0.05, len), M.dark, pos, 0.76, c); } plat(pos - th / 2, pos + th / 2, a0, a1, y0 + h, y0, true); }
      else { add(G.boxM(len, h, th), m, c, y0 + h / 2, pos); if (!y0 && !o.plain) { add(G.boxM(len, 0.75, th + 0.03), o.wm || M.hinoki, c, 0.375, pos); add(G.boxM(len, 0.05, th + 0.05), M.dark, c, 0.76, pos); } plat(a0, a1, pos - th / 2, pos + th / 2, y0 + h, y0, true); }
    }
    function ceil(x0, x1, z0, z1, y, m) { add(G.boxM(x1 - x0, 0.1, z1 - z0), m || M.ceilW, (x0 + x1) / 2, y + 0.05, (z0 + z1) / 2); plat(x0, x1, z0, z1, y + 0.12, y, true); }
    function light(x, y, z, c, i, d) { var l = new THREE.PointLight(c, i, d || 6, 1.7); l.position.set(x, y, z); l.layers.set(1); K.room.add(l); K.lights.push(l); return l; }
    function lampBall(x, y, z, rr) { begin('吸頂燈', x, y, z); S(rr || 0.16, mat('bulb', null), 0, 0, 0, 1, 0.45, 1); C(0.1, 0.1, 0.03, M.darker, 0, 0.05, 0, 12); }
    var steel = col(0xd8d6d0, 0.28, { metalness: 0.7 }), glassG = mat('winGlow', null);
    var pat = {
      gingham: tx('cGingham', function () { return P.gingham('#c8452e'); }, 0.12), ginghamB: tx('cGinghamB', function () { return P.gingham('#2f4b7c'); }, 0.12),
      dots: tx('cDots', function () { return P.dots('#f6efdc', '#c8452e'); }, 0.12), dotsB: tx('cDotsB', function () { return P.dots('#2f4b7c', '#f6efdc'); }, 0.1),
      tartan: tx('cTartan', function () { return P.tartan('#2e5a48', '#c8452e', '#d9a93a'); }, 0.3), tartanR: tx('cTartanR', function () { return P.tartan('#8a2f2a', '#2f4b7c', '#f6efdc'); }, 0.3),
      uroko: tx('cUroko', function () { return P.uroko('#f1e7d2', '#3f8f8a'); }, 0.14), urokoR: tx('cUrokoR', function () { return P.uroko('#f6efdc', '#c8452e'); }, 0.12),
      patch: tx('cPatch', function () { return P.patchwork(['#c8452e', '#2f4b7c', '#d9a93a', '#7a9a54', '#f1e7d2', '#e7a0a8', '#5e4a7a']); }, 0.6)
    };
    K.pat = pat;
    function label(key, text, bg, ink) { return mat('lab' + key, { map: SG.tex('lab' + key, function () { return P.label(text, bg || '#f6efdc', ink || '#2a2320'); }), roughness: 0.9 }); }

    /* ============================== KITCHEN ============================== */
    K.setRoom('廚房'); root();
    plat(-2.56, -2.44, -6.1, -3.5, H, 0, true); plat(2.44, 2.56, -6.1, -3.5, H, 0, true); plat(-2.5, 2.5, -6.22, -6.1, H, 0, true); plat(-2.5, 2.5, -6.1, -3.5, H + 0.12, H, true);
    plat(-1.5, 1.1, -6.0, -5.4, 0.87); plat(1.59, 2.31, -5.99, -5.31, 1.75);
    lampBall(0, H - 0.08, -4.8);
    begin('流理台水槽', -1.0, 0.87, -5.62); B(0.5, 0.02, 0.36, col(0x9aa0a6, 0.25, { metalness: 0.8 }), 0, 0.005, 0, 0.01); add(G.tube([[0, 0, -0.16], [0, 0.2, -0.16], [0, 0.24, -0.06], [0, 0.2, 0.0]], 0.012, 12, 6), steel);
    begin('瀝水架', -0.45, 0.87, -5.62); B(0.36, 0.02, 0.28, steel, 0, 0, 0, 0.008); for (var i = 0; i < 4; i++) { C(0.085, 0.085, 0.012, col([0xf5f1e8, 0x2f4b7c, 0xf5f1e8, 0x7a9a54][i], 0.3), -0.12 + i * 0.07, 0.09, 0, 16).rotation.z = PI / 2 - 0.2; }
    begin('砧板', 0.0, 0.875, -5.5, 0.15); B(0.3, 0.02, 0.2, M.hinoki, 0, 0, 0, 0.006); B(0.02, 0.012, 0.16, steel, 0.06, 0.02, 0.0, 0.003).rotation.y = 0.5; B(0.02, 0.014, 0.07, M.darker, 0.1, 0.02, 0.075, 0.004).rotation.y = 0.5;
    begin('白蘿蔔', -0.08, 0.895, -5.5, 0.4); add(new THREE.CapsuleGeometry(0.03, 0.2, 4, 10), col(0xf7f3ea, 0.6), 0, 0.03, 0, 0, 0, PI / 2); add(new THREE.ConeGeometry(0.035, 0.1, 6), M.leafM, 0.17, 0.03, 0, 0, 0, -PI / 2);
    begin('紅蘿蔔', 0.02, 0.895, -5.43, -0.5); add(new THREE.ConeGeometry(0.022, 0.16, 8), col(0xe9772a, 0.6), 0, 0.022, 0, 0, 0, PI / 2);
    begin('烤麵包機', 1.35 - 0.6, 0.87, -5.85); B(0.26, 0.17, 0.16, col(0xd9a93a, 0.35), 0, 0, 0, 0.04); B(0.18, 0.02, 0.03, M.black, 0, 0.165, 0.03, 0.005); B(0.18, 0.02, 0.03, M.black, 0, 0.165, -0.03, 0.005); B(0.1, 0.09, 0.012, col(0xc98a3a, 0.8), 0.02, 0.15, 0.03, 0.004);
    begin('筷子筒', -1.35, 0.87, -5.5); L([[0, 0], [0.04, 0], [0.045, 0.11]], col(0x3f8f8a, 0.3), 0, 0, 0, 12); for (i = 0; i < 5; i++) add(new THREE.CylinderGeometry(0.003, 0.003, 0.22, 4), i & 1 ? M.red : M.hinoki, (i - 2) * 0.012, 0.15, 0, (i - 2) * 0.06, 0, (i - 2) * 0.05);
    begin('掛鉤廚具', -0.2, 1.28, -6.03); B(1.2, 0.03, 0.03, steel, 0, 0, 0, 0.008);
    [['湯勺', -0.5], ['鍋鏟', -0.3], ['打蛋器', -0.1], ['平底鍋', 0.25]].forEach(function (u) {
      begin(u[0], -0.2 + u[1], 1.0, -6.02); add(new THREE.CylinderGeometry(0.008, 0.008, 0.26, 6), M.darker, 0, 0.13, 0);
      if (u[0] === '湯勺') S(0.04, steel, 0, -0.02, 0.01, 1, 0.6, 1); else if (u[0] === '鍋鏟') B(0.06, 0.09, 0.008, steel, 0, -0.08, 0, 0.004); else if (u[0] === '打蛋器') S(0.035, steel, 0, -0.03, 0, 0.8, 1.5, 0.8); else { C(0.13, 0.11, 0.03, M.iron, 0, -0.16, 0.015, 20).rotation.x = PI / 2; }
    });
    begin('擦手巾', 1.25, 1.02, -6.02); var tw = K.sway(pat.gingham.clone(), 0.02, 1.6); tw.side = THREE.DoubleSide; add(new THREE.PlaneGeometry(0.26, 0.4, 3, 6), tw, 0, 0, 0.01); B(0.3, 0.02, 0.02, steel, 0, 0.21, 0, 0.006);
    begin('冰箱磁鐵', 1.95, 1.35, -5.3); [[0xc8452e, -0.2, 0.1], [0xd9a93a, 0.05, 0.2], [0x4aa3e0, 0.18, 0.02], [0x7a9a54, -0.05, -0.1]].forEach(function (m) { C(0.025, 0.025, 0.008, col(m[0], 0.4), m[1], m[2], 0, 10).rotation.x = PI / 2; }); PL(0.14, 0.18, label('memo', 'かいもの', '#fff9d8', '#3a2a1e'), 0.2, -0.22, 0.004);
    // dining table with stools
    var tb = begin('餐桌', 1.45, 0, -4.35); B(1.0, 0.04, 0.72, M.hinoki, 0, 0.66, 0, 0.012, true); [[-1, -1], [1, -1], [-1, 1], [1, 1]].forEach(function (c) { B(0.05, 0.66, 0.05, M.hinoki, c[0] * 0.43, 0, c[1] * 0.3, 0.008); });
    PL(0.7, 0.5, pat.gingham, 0, 0.702, 0, -PI / 2, 0, 0, true); platG(tb, 1.0, 0.72, 0.7, 0.62); K.blob(1.45, -4.35, 1.4, 1.1);
    [[0.75, -4.0, 0.3], [1.5, -3.85, -0.2]].forEach(function (c) { var g = begin('圓凳', c[0], 0, c[1], c[2]); C(0.16, 0.16, 0.04, pat.dotsB, 0, 0.42, 0, 20); [0, 1, 2].forEach(function (k) { add(new THREE.CylinderGeometry(0.015, 0.02, 0.44, 6), M.darker, Math.cos(k * 2.09) * 0.1, 0.21, Math.sin(k * 2.09) * 0.1, Math.sin(k * 2.09) * 0.12, 0, -Math.cos(k * 2.09) * 0.12); }); plat(c[0] - 0.15, c[0] + 0.15, c[1] - 0.15, c[1] + 0.15, 0.46, 0.38); });
    begin('水果盤', 1.3, 0.704, -4.4); C(0.14, 0.09, 0.03, col(0xf5f1e8, 0.3), 0, 0, 0, 20);
    begin('牛奶盒', 1.75, 0.704, -4.5, 0.4); B(0.07, 0.17, 0.07, M.white, 0, 0, 0, 0.004); add(new THREE.ConeGeometry(0.05, 0.04, 4), M.white, 0, 0.19, 0, 0, PI / 4, 0); PL(0.06, 0.08, label('milk', '牛乳', '#4aa3e0', '#ffffff'), 0, 0.09, 0.036);
    begin('醬油瓶', 1.62, 0.704, -4.18); L([[0, 0], [0.03, 0], [0.035, 0.07], [0.015, 0.1], [0.015, 0.12]], col(0x2a1a10, 0.2), 0, 0, 0, 12); C(0.018, 0.018, 0.02, col(0xc8452e, 0.4), 0, 0.12, 0, 10);
    begin('吐司', 1.05, 0.704, -4.2, 0.5); B(0.11, 0.1, 0.16, col(0xd9a35e, 0.9), 0, 0, 0, 0.03); B(0.1, 0.012, 0.1, col(0xf3dfae, 0.9), 0.13, 0, 0.02, 0.005);
    begin('小桌曆', 1.85, 0.704, -4.15, -0.5); B(0.1, 0.08, 0.04, M.cream, 0, 0, 0, 0.004);
    // floor corner: cat bowls, rice bin, bin, shopping bag, mat
    begin('貓碗墊', -1.75, 0, -4.2); PL(0.6, 0.36, pat.dots, 0, 0.006, 0, -PI / 2, 0, 0, true);
    [['貓飼料碗', -1.9, 0xc8452e, 0x9a6a3a], ['貓水碗', -1.6, 0x4aa3e0, 0x9fd8e8]].forEach(function (b) { begin(b[0], b[1], 0.006, -4.2); L([[0, 0], [0.085, 0], [0.07, 0.04], [0.055, 0.04]], col(b[2], 0.4), 0, 0, 0, 16); C(0.055, 0.055, 0.004, col(b[3], 0.3), 0, 0.032, 0, 14); });
    begin('米桶', -2.1, 0, -5.0); B(0.34, 0.5, 0.34, M.cream, 0, 0, 0, 0.03); B(0.36, 0.03, 0.36, col(0xc8452e, 0.5), 0, 0.5, 0, 0.012); PL(0.2, 0.2, label('kome', '米', '#f6efdc', '#2a2320'), 0, 0.26, 0.172); plat(-2.27, -1.93, -5.17, -4.83, 0.53);
    begin('踏板垃圾桶', -2.1, 0, -5.55); L([[0, 0], [0.15, 0], [0.16, 0.4], [0.14, 0.44], [0, 0.46]], col(0x7a9a54, 0.4), 0, 0, 0, 16); B(0.1, 0.02, 0.08, M.black, 0, 0, 0.17, 0.006); plat(-2.26, -1.94, -5.71, -5.39, 0.46);
    begin('購物袋', -1.3, 0, -3.85, 0.3); B(0.3, 0.3, 0.16, pat.urokoR, 0, 0, 0, 0.03, true); for (i = 0; i < 3; i++) { add(new THREE.CylinderGeometry(0.012, 0.014, 0.4, 6), col(i ? 0xeef2dc : 0x7a9a54, 0.6), -0.06 + i * 0.05, 0.36, 0, 0, 0, 0.1 * (i - 1)); } add(new THREE.TorusGeometry(0.06, 0.006, 5, 12, PI), M.cream, 0, 0.3, 0.085);
    begin('地墊', 0, 0, -3.95); PL(0.9, 0.5, tx('matK', function () { return P.stripes(['#3f8f8a', '#f6efdc', '#d9a93a', '#f6efdc'], [18, 6, 8, 6]); }, [0.1, 0.1], 0.95), 0, 0.007, 0, -PI / 2, 0, 0, true);
    begin('微波爐推車', 2.05, 0, -4.9, -PI / 2); B(0.6, 0.03, 0.42, M.hinoki, 0, 0.72, 0, 0.01); B(0.6, 0.03, 0.42, M.hinoki, 0, 0.3, 0, 0.01); [[-1, -1], [1, -1], [-1, 1], [1, 1]].forEach(function (c) { B(0.03, 0.75, 0.03, steel, c[0] * 0.28, 0, c[1] * 0.19, 0.006); }); plat(1.84, 2.26, -5.2, -4.6, 0.75, 0.25);
    begin('微波爐', 2.05, 0.75, -4.9, -PI / 2); B(0.5, 0.28, 0.36, M.white, 0, 0, 0, 0.02); B(0.3, 0.2, 0.01, M.black, -0.07, 0.04, 0.181, 0.008); C(0.025, 0.025, 0.01, steel, 0.19, 0.18, 0.185, 10).rotation.x = PI / 2; plat(1.87, 2.23, -5.15, -4.65, 1.03, 0.75);
    begin('保溫瓶', 2.05, 0.33, -4.75); L([[0, 0], [0.04, 0], [0.04, 0.2], [0.03, 0.24], [0, 0.25]], col(0x2f4b7c, 0.25, { metalness: 0.5 }), 0, 0, 0, 12);
    begin('清酒瓶', 2.08, 0.33, -5.05); L([[0, 0], [0.045, 0], [0.047, 0.18], [0.02, 0.26], [0.018, 0.32]], col(0x35502e, 0.15), 0, 0, 0, 12); PL(0.06, 0.09, label('sake', '酒', '#f6efdc', '#2a2320'), 0, 0.1, 0.048);
    begin('圍裙', -2.42, 1.3, -4.4, PI / 2); var ap = K.sway(pat.dots.clone(), 0.012, 1.3); ap.side = THREE.DoubleSide; add(new THREE.PlaneGeometry(0.4, 0.62, 3, 6), ap, 0, -0.1, 0.02); C(0.012, 0.012, 0.05, M.brass, 0, 0.22, 0.02, 8).rotation.x = PI / 2;
    begin('掛鐘', 2.42, 1.9, -4.0, -PI / 2); C(0.15, 0.15, 0.03, col(0x3f8f8a, 0.4), 0, 0, 0, 24).rotation.x = PI / 2; C(0.125, 0.125, 0.032, M.cream, 0, 0, 0.002, 24).rotation.x = PI / 2;
    // rice cooker steam (the cooker itself is built in room.js)
    K.steamM2 = SG.steamProto.clone(); K.steamM2.uniforms = { uTime: SG.uTime, uAmt: { value: 0 } };
    var rs = new THREE.Mesh(new THREE.PlaneGeometry(0.2, 0.45), K.steamM2); rs.position.set(-0.9, 1.35, -5.7); rs.layers.set(1); K.dyn.add(rs); K.count('電鍋蒸氣');
    up.push(function (t) { K.steamM2.uniforms.uAmt.value = Math.max(0, Math.sin(t * 0.21 + 1.0)) * 0.9; });
    K.knockable('蘋果', 1.26, 0.74, -4.42, 0.04, function () { S(0.04, col(0xd9432b, 0.35), 0, 0, 0, 1, 0.92, 1); add(new THREE.CylinderGeometry(0.003, 0.003, 0.02, 4), M.darker, 0, 0.04, 0); });
    K.knockable('香蕉', 1.36, 0.735, -4.38, 0.035, function () { add(G.tube([[-0.07, 0, 0], [0, -0.02, 0], [0.07, 0, 0]], 0.018, 8, 6), col(0xf2d24a, 0.5)); });
    K.knockable('雞蛋', 0.9, 0.725, -4.5, 0.022, function () { S(0.022, col(0xf6e6cf, 0.5), 0, 0, 0, 1, 1.25, 1); }); K.knockable('雞蛋', 0.95, 0.725, -4.44, 0.022, function () { S(0.022, col(0xf2dcc0, 0.5), 0, 0, 0, 1, 1.25, 1); });
    K.knockable('洋蔥', 0.3, 0.9, -5.5, 0.035, function () { S(0.035, col(0xc98a4a, 0.5), 0, 0, 0, 1, 0.9, 1); add(new THREE.ConeGeometry(0.008, 0.03, 5), col(0xd9b27a), 0, 0.04, 0); });
    K.knockable('馬克杯', 1.6, 0.704, -4.55, 0.04, function () { L([[0, 0], [0.035, 0], [0.037, 0.08], [0.033, 0.08], [0.031, 0.01]], col(0xf29a4a, 0.3), 0, 0, 0, 14); add(new THREE.TorusGeometry(0.022, 0.006, 5, 10, PI), col(0xf29a4a, 0.3), 0.04, 0.04, 0, 0, 0, -PI / 2); }, 'cup');
    K.knockable('罐頭', -1.5, 0, -4.9, 0.036, function () { C(0.035, 0.035, 0.09, col(0xc8452e, 0.3, { metalness: 0.6 }), 0, 0, 0, 14); }, 'cup');
    light(0, 2.1, -4.8, 0xfff2dc, 5, 6.5);

    /* ============================== GENKAN + STAIR HALL ============================== */
    K.setRoom('玄關'); root();
    var hx0 = -6.7, hx1 = -4.5;
    plat(hx0 - 0.12, hx0, -3.5, 2.9, 4.6, 0, true); // west wall (double height along the stair)
    wall('x', hx0 - 0.05, -3.5, -0.3, { y0: H, h: 2.0, plain: true }); add(G.boxM(0.1, H, 3.2), M.plaster, hx0 - 0.05, H / 2, -1.9);
    wall('z', 2.95, hx0, -5.95, {}); wall('z', 2.95, -5.25, hx1, {}); wall('z', 2.95, -5.95, -5.25, { y0: 0.34, plain: true }); // south wall with a cat flap
    wall('z', 2.95, -5.95, -5.8, { h: 0.34, plain: true, m: M.red, th: 0.16 }); wall('z', 2.95, -5.4, -5.25, { h: 0.34, plain: true, m: M.red, th: 0.16 });
    wall('x', -4.44, -3.5, -0.3, { y0: H, h: 2.0, plain: true }); wall('z', -0.3, hx0, hx1, { y0: H, h: 2.0, plain: true });
    plat(hx0, hx1, -0.3, 2.9, H + 0.12, H, true); ceil(hx0, hx1, -3.5, -0.3, 4.5);
    add(G.planeM(2.2, 3.2), tx('genkanFloor', null, 0.7, 0.8), -5.6, 0.001, -1.9, -PI / 2);
    add(G.boxM(0.1, 2.0, 0.1), M.darker, hx1, H + 1.0, -0.3);
    // stairs: 18 steps, rise 0.15 (dogs and cats can both climb), going north to the loft at y 2.7
    var st = begin('樓梯', 0, 0, 0), run = 0.165, items = [];
    for (i = 0; i < 18; i++) { var z1 = -0.5 - i * run, top = (i + 1) * 0.15; items.push([G.boxM(0.95, 0.04, run + 0.02), G.mat4(-6.22, top - 0.02, z1 - run / 2)]); items.push([G.boxM(0.95, 0.15, 0.02), G.mat4(-6.22, top - 0.075, z1 - run + 0.01)]); plat(hx0, -5.75, z1 - run, z1, top); }
    add(G.merge(items), M.honey);
    var sk = add(new THREE.ShapeGeometry(new THREE.Shape([new THREE.Vector2(0.5, 0), new THREE.Vector2(3.47, 0), new THREE.Vector2(3.47, 2.66), new THREE.Vector2(0.66, 0.1)])), col(0xc89b5e, 0.7, { side: THREE.DoubleSide }), -5.74, 0, 0, 0, PI / 2, 0);
    wall('z', -3.56, -5.75, -4.44, { h: 2.6 });
    var rail = []; for (i = 0; i <= 6; i++) rail.push([new THREE.CylinderGeometry(0.02, 0.02, 0.75, 6), G.mat4(-5.76, 0.52 + i * 0.45, -0.55 - i * 0.495)]);
    add(G.merge(rail), M.darker); add(G.tube([[-5.76, 0.9, -0.5], [-5.76, 3.6, -3.47]], 0.03, 2, 8), M.darker);
    begin('樓梯下收納', -6.22, 0, -2.6); B(0.9, 0.02, 0.02, M.dark, 0, 0, 0, 0.004);
    begin('高窗', hx0 + 0.02, 3.5, -1.9, PI / 2); PL(1.4, 0.7, glassG, 0, 0, 0); B(1.5, 0.05, 0.05, M.hinoki, 0, 0.37, 0); B(1.5, 0.05, 0.05, M.hinoki, 0, -0.37, 0); B(0.05, 0.74, 0.05, M.hinoki, 0, -0.37, 0);
    // front door (with a cat flap cats fit through and dogs do not)
    begin('玄關門', -5.6, 0, 2.95); B(0.7, 1.6, 0.16, M.red, 0, 0.34, 0, 0.012, true); PL(0.3, 0.9, glassG, 0, 1.25, -0.085, 0, PI, 0); PL(0.3, 0.9, glassG, 0, 1.25, 0.085); S(0.03, M.brass, 0.27, 1.0, -0.1);
    var flap = begin('貓門', -5.6, 0.33, 2.93, 0, true); B(0.4, 0.3, 0.015, col(0x4aa3e0, 0.4, { transparent: true, opacity: 0.75 }), 0, -0.3, 0, 0.006);
    K.triggers.push({ kind: 'flap', g: flap, x: -5.6, z: 2.95, a: 0, v: 0 });
    begin('門墊', -5.6, 0, 2.45); PL(0.7, 0.42, tx('doormat', function () { return P.kikko('#7a5a36', '#c9a86a', 14); }, 0.1, 1), 0, 0.006, 0, -PI / 2, 0, 0, true);
    begin('掛衣板', -6.62, 1.55, 0.2, PI / 2); B(1.0, 0.08, 0.03, M.dark, 0, 0, 0, 0.01); for (i = 0; i < 4; i++) S(0.02, M.brass, -0.36 + i * 0.24, 0.02, 0.03);
    begin('外套', -6.6, 1.05, 0.02, PI / 2); B(0.36, 0.55, 0.08, cloth.indigo, 0, 0, 0, 0.04, true); B(0.1, 0.4, 0.07, cloth.indigo, -0.2, 0.1, 0, 0.03, true); B(0.1, 0.4, 0.07, cloth.indigo, 0.2, 0.1, 0, 0.03, true);
    begin('草帽', -6.6, 1.5, 0.45, PI / 2); C(0.16, 0.17, 0.012, col(0xd9c27a, 0.9), 0, 0, 0.03, 20).rotation.x = PI / 2; L([[0, 0], [0.09, 0], [0.08, 0.07], [0, 0.08]], col(0xd9c27a, 0.9), 0, 0, 0.03, 16).rotation.x = PI / 2;
    begin('書包', -6.56, 1.05, -0.1 + 0.6, PI / 2); B(0.3, 0.36, 0.14, col(0xc8452e, 0.4), 0, 0, 0, 0.04); B(0.3, 0.16, 0.02, col(0xa8301c, 0.4), 0, 0.2, 0.08, 0.01);
    begin('穿衣鏡', -4.56, 0.3, -1.2 + 0.3, -PI / 2); B(0.5, 1.3, 0.03, M.hinoki, 0, 0, 0, 0.01); PL(0.42, 1.2, mat('mirror', { color: 0xcfe0e6, roughness: 0.05, metalness: 1 }), 0, 0.65, 0.017);
    begin('鑰匙盤', -6.35, 0.9, 0.75); C(0.07, 0.05, 0.015, col(0x2f4b7c, 0.3), 0, 0, 0, 14); B(0.05, 0.006, 0.015, M.brass, 0, 0.016, 0, 0.002);
    begin('包裹', -4.85, 0, 2.55, 0.2); B(0.34, 0.24, 0.26, M.card, 0, 0, 0, 0.006, true); B(0.36, 0.01, 0.05, M.cream, 0, 0.24, 0, 0.002); plat(-5.02, -4.68, 2.42, 2.68, 0.24);
    begin('安全帽', -6.3, 0.9, 1.85); S(0.12, col(0xd9a93a, 0.25), 0, 0.08, 0, 1, 0.8, 1.15);
    begin('滑板', -4.9, 0, 0.2, 1.2); B(0.2, 0.015, 0.7, pat.tartanR, 0, 0.07, 0, 0.007, true); [[-0.07, 0.24], [0.07, 0.24], [-0.07, -0.24], [0.07, -0.24]].forEach(function (c) { C(0.03, 0.03, 0.03, col(0xf5f1e8, 0.4), c[0], 0.005, c[1], 10).rotation.z = PI / 2; });
    K.knockable('網球', -5.0, 0.035, 1.9, 0.035, function () { S(0.035, col(0xcfe04a, 0.9)); });
    lampBall(-5.6, H - 0.08, 1.3); light(-5.6, 2.0, 1.3, 0xffe2b8, 3.5, 5.5);
    // laundry corner under the tall hall
    K.setRoom('洗衣間'); root();
    begin('洗衣機', -5.1, 0, -3.12); B(0.62, 0.86, 0.6, M.white, 0, 0, 0, 0.03); B(0.5, 0.06, 0.03, col(0xd8d6d0, 0.4), 0, 0.76, 0.3, 0.01); plat(-5.41, -4.79, -3.42, -2.82, 0.86); K.blob(-5.1, -3.1, 1.0, 1.0);
    var drum = begin(null, -5.1, 0.42, -2.815, 0, true); add(new THREE.TorusGeometry(0.19, 0.03, 8, 24), steel, 0, 0, 0); var dr = begin(null, 0, 0, 0, 0, true); drum.add(dr);
    add(new THREE.CircleGeometry(0.17, 20), mat('drumGlass', { color: 0x9fc4d8, roughness: 0.1, transparent: true, opacity: 0.55 }), 0, 0, 0.012);
    [[0xc8452e, 0.07, 0.03], [0x2f4b7c, -0.06, 0.05], [0xf1e7d2, 0.0, -0.08], [0xd9a93a, -0.02, 0.1]].forEach(function (c) { S(0.05, col(c[0], 0.9), c[1], c[2], -0.03, 1.3, 0.8, 0.5); });
    K.count('洗衣機滾筒'); up.push(function (t) { var ph = (t % 24) / 24; dr.rotation.z = ph < 0.7 ? Math.sin(t * 2.2) * 1.4 + t * 0.6 : t * 14; drum.position.x = -5.1 + (ph >= 0.7 ? Math.sin(t * 40) * 0.004 : 0); });
    begin('洗衣精', -4.9, 0.86, -3.2); B(0.1, 0.2, 0.07, col(0x4aa3e0, 0.3), 0, 0, 0, 0.02); C(0.02, 0.02, 0.03, M.white, 0.02, 0.2, 0, 8); begin('柔軟精', -5.25, 0.86, -3.25); B(0.09, 0.17, 0.07, col(0xe7a0a8, 0.3), 0, 0, 0, 0.02); C(0.02, 0.02, 0.03, M.white, 0, 0.17, 0, 8);
    begin('洗衣籃（藤）', -4.82, 0, -2.4); L([[0, 0], [0.18, 0], [0.22, 0.4], [0.23, 0.41]], tx('basket', null, 0.08), 0, 0, 0, 16); B(0.3, 0.1, 0.26, pat.tartan, 0, 0.36, 0, 0.04, true); plat(-5.02, -4.62, -2.6, -2.2, 0.46);
    var rack = begin('室內晾衣架', -5.2, 0, -1.55, 0.1); add(G.merge([[new THREE.CylinderGeometry(0.012, 0.012, 1.0, 6), G.mat4(-0.35, 0.5, 0, 0, 0, 0.12)], [new THREE.CylinderGeometry(0.012, 0.012, 1.0, 6), G.mat4(0.35, 0.5, 0, 0, 0, -0.12)], [new THREE.CylinderGeometry(0.01, 0.01, 0.8, 6), G.mat4(0, 0.98, 0, 0, 0, PI / 2)], [new THREE.CylinderGeometry(0.01, 0.01, 0.8, 6), G.mat4(0, 0.7, 0.0, 0, 0, PI / 2)]]), steel);
    [['襪子', pat.urokoR, -0.25, 0.14, 0.26], ['襪子', pat.dotsB, -0.1, 0.14, 0.26], ['手帕', cloth.sakura, 0.1, 0.22, 0.22], ['小毛巾', pat.ginghamB, 0.28, 0.2, 0.34]].forEach(function (c, k) { K.count(c[0]); var m = K.sway(c[1].clone(), 0.02, 1.4 + k * 0.2); m.side = THREE.DoubleSide; add(new THREE.PlaneGeometry(c[3], c[4], 3, 5), m, c[2], 0.97 - c[4] / 2, 0); });
    begin('貓砂盆', -4.85, 0, -0.85); B(0.5, 0.14, 0.38, col(0x7a9a54, 0.5), 0, 0, 0, 0.03); B(0.44, 0.02, 0.32, col(0xd9cfb8, 1), 0, 0.1, 0, 0.01); plat(-5.1, -4.6, -1.04, -0.66, 0.14);
    begin('貓砂鏟', -4.6, 0.02, -0.5, 0.6); B(0.07, 0.01, 0.1, col(0xc8452e, 0.5), 0, 0, 0, 0.004); B(0.02, 0.01, 0.14, col(0xc8452e, 0.5), 0, 0, 0.12, 0.004);
    begin('拖把水桶', -5.5, 0, -0.6); L([[0, 0], [0.12, 0], [0.15, 0.26], [0.155, 0.27]], col(0x4aa3e0, 0.4), 0, 0, 0, 14); add(new THREE.CylinderGeometry(0.012, 0.012, 1.1, 6), M.hinoki, 0.03, 0.6, 0, 0, 0, 0.1); S(0.07, M.cream, 0.0, 0.08, 0, 1, 0.8, 1);
    begin('吸塵器', -5.55, 0, -1.0 - 0.1, 0.3); B(0.16, 0.5, 0.14, col(0xc8452e, 0.35), 0, 0.08, 0, 0.05); B(0.26, 0.08, 0.2, M.black, 0, 0, 0.04, 0.02); add(new THREE.CylinderGeometry(0.014, 0.014, 0.6, 6), steel, 0, 0.85, -0.02);
    begin('燙衣板', -4.62, 0, -1.55, PI / 2); B(1.0, 0.03, 0.3, pat.ginghamB, 0, 0.78, 0, 0.012, true); add(new THREE.CylinderGeometry(0.012, 0.012, 1.0, 6), steel, 0, 0.4, 0, 0, 0, 0.9); add(new THREE.CylinderGeometry(0.012, 0.012, 1.0, 6), steel, 0, 0.4, 0, 0, 0, -0.9); plat(-4.77, -4.47, -2.05, -1.05, 0.81, 0.74);
    begin('熨斗', -4.62, 0.81, -1.35, 0.4); B(0.1, 0.07, 0.2, col(0x3f8f8a, 0.3), 0, 0, 0, 0.03); add(new THREE.TorusGeometry(0.05, 0.012, 5, 10, PI), M.black, 0, 0.07, 0, 0, PI / 2, 0);
    begin('毛巾架', -4.62, 0, -3.2, -PI / 2); B(0.5, 1.1, 0.3, M.hinoki, 0, 0, 0, 0.012, true); for (i = 0; i < 3; i++) B(0.4, 0.12, 0.26, [cloth.cream, pat.ginghamB, cloth.stripeG][i], 0, 0.22 + i * 0.3, 0.03, 0.04, true); plat(-4.77, -4.47, -3.45, -2.95, 1.1);
    light(-5.4, 2.6, -1.9, 0xfff0d8, 4.5, 7);

    /* ============================== LOFT ============================== */
    K.setRoom('閣樓'); root();
    var lx0 = -6.7, lx1 = -2.6, lz0 = -6.5, lz1 = -3.5, LY = 2.7, LH = 4.5;
    var attic = tx('woodAttic', function () { return P.wood({ base: '#7a5a3c', planks: 6, seed: 81, contrast: 0.22 }); }, [1.2, 2.4], 0.8);
    add(G.boxM(lx1 - lx0, 0.1, lz1 - lz0), attic, (lx0 + lx1) / 2, LY - 0.05, (lz0 + lz1) / 2); plat(lx0, lx1, lz0, lz1, LY, LY - 0.1, true);
    var bw = { y0: LY, h: LH - LY, plain: true, m: tx('woodAtticW', function () { return P.wood({ base: '#a98660', planks: 8, seed: 82, contrast: 0.14 }); }, [1.6, 1.6], 0.85) };
    wall('z', lz0 - 0.06, lx0, lx1, bw); wall('x', lx1 + 0.06, lz0, lz1, bw); wall('x', lx0 - 0.06, lz0, lz1, bw); wall('z', lz1 + 0.02, -4.5, lx1, bw);
    plat(-5.75, -4.5, lz1 - 0.04, lz1 + 0.04, LY + 0.5, LY, false); for (i = 0; i < 6; i++) B(0.04, 0.5, 0.04, M.darker, -5.7 + i * 0.24, LY, lz1, 0.006); B(1.25, 0.05, 0.06, M.darker, -5.125, LY + 0.5, lz1, 0.01);
    ceil(lx0, lx1, lz0, lz1, LH, attic); for (i = 0; i < 4; i++) B(lx1 - lx0, 0.14, 0.12, M.dark, (lx0 + lx1) / 2, LH - 0.14, lz0 + 0.4 + i * 0.75, 0.01, true);
    begin('閣樓圓窗', (lx0 + lx1) / 2, LY + 1.15, lz0 + 0.01); add(new THREE.CircleGeometry(0.42, 24), glassG, 0, 0, 0); add(new THREE.TorusGeometry(0.42, 0.04, 8, 28), M.darker, 0, 0, 0.01); B(0.84, 0.03, 0.03, M.darker, 0, -0.015, 0.01); B(0.03, 0.84, 0.03, M.darker, 0, -0.42, 0.01);
    light(-4.6, LY + 1.3, -5.0, 0xffe6c0, 5, 6.5);
    // boxes (some stacked) and old toys
    K.cbox(-3.2, LY, -6.0, 0.6, 0.45, 0.5, 0.1, 'おもちゃ'); K.cbox(-3.25, LY + 0.45, -6.02, 0.48, 0.36, 0.42, -0.15, null); K.cbox(-3.1, LY, -5.3, 0.5, 0.4, 0.5, 0.4, null, true); K.cbox(-6.2, LY, -6.05, 0.55, 0.5, 0.5, -0.1, 'ふゆもの'); K.cbox(-5.55, LY, -6.1, 0.5, 0.36, 0.4, 0.2, null); K.cbox(-6.25, LY + 0.5, -6.05, 0.4, 0.3, 0.36, 0.3, null);
    var horse = begin('搖搖木馬', -4.6, LY, -5.6, 0.5, true); add(G.tube([[-0.3, 0.1, 0.14], [0, 0.0, 0.14], [0.3, 0.1, 0.14]], 0.02, 10, 6), M.red); add(G.tube([[-0.3, 0.1, -0.14], [0, 0.0, -0.14], [0.3, 0.1, -0.14]], 0.02, 10, 6), M.red);
    B(0.46, 0.2, 0.16, M.hinoki, 0, 0.3, 0, 0.06); S(0.09, M.hinoki, 0.26, 0.56, 0, 0.9, 1.1, 0.7); add(new THREE.CylinderGeometry(0.05, 0.06, 0.2, 8), M.hinoki, 0.2, 0.44, 0, 0, 0, -0.5); [[-0.15, 0.1], [0.15, 0.1], [-0.15, -0.1], [0.15, -0.1]].forEach(function (c) { add(new THREE.CylinderGeometry(0.02, 0.02, 0.26, 6), M.hinoki, c[0], 0.2, c[1]); }); B(0.2, 0.03, 0.18, pat.tartanR, 0, 0.5, 0, 0.012, true);
    K.triggers.push({ kind: 'rock', g: horse, x: -4.6, z: -5.6, y: LY, a: 0, v: 0, rad: 0.45 }); plat(-4.85, -4.35, -5.75, -5.45, LY + 0.5, LY + 0.2);
    begin('玩具火車', -4.2, LY, -4.3, 0.3); add(new THREE.TorusGeometry(0.4, 0.012, 5, 28), M.darker, 0, 0.006, 0, PI / 2); add(new THREE.TorusGeometry(0.34, 0.012, 5, 28), M.darker, 0, 0.006, 0, PI / 2);
    var train = begin(null, -4.2, LY, -4.3, 0, true); [[0xc8452e, 0], [0x2f4b7c, 0.32], [0xd9a93a, 0.62]].forEach(function (c, k) { var cg = new THREE.Group(); train.add(cg); cg.rotation.y = -c[1]; var m = new THREE.Mesh(G.rbox(0.09, 0.07, 0.15, 0.015), col(c[0], 0.4)); m.position.set(0.37, 0.05, 0); cg.add(m); if (!k) { var ch = new THREE.Mesh(new THREE.CylinderGeometry(0.015, 0.015, 0.05, 8), M.black); ch.position.set(0.37, 0.11, 0.04); cg.add(ch); } });
    K.count('玩具火車車廂', 3); up.push(function (t) { train.rotation.y = t * 0.5; });
    begin('泰迪熊', -3.15, LY + 0.81, -6.0, -0.4); S(0.11, col(0xb5804a, 0.95), 0, 0.1, 0, 1, 1.1, 0.9); S(0.085, col(0xb5804a, 0.95), 0, 0.26, 0); S(0.03, col(0xb5804a, 0.95), -0.06, 0.33, 0); S(0.03, col(0xb5804a, 0.95), 0.06, 0.33, 0); S(0.035, col(0xe9cfa0, 0.95), 0, 0.245, 0.07); S(0.01, M.black, -0.03, 0.28, 0.075); S(0.01, M.black, 0.03, 0.28, 0.075); [[-0.1, 0.12], [0.1, 0.12], [-0.07, 0.0], [0.07, 0.0]].forEach(function (c) { S(0.04, col(0xb5804a, 0.95), c[0], c[1], 0.05, 1, 1.3, 1); });
    begin('娃娃屋', -5.5, LY, -4.4, 0.6); B(0.5, 0.36, 0.3, col(0xf1e7d2, 0.8), 0, 0, 0, 0.01); var rf = add(new THREE.CylinderGeometry(0.01, 0.3, 0.2, 4, 1), col(0xc8452e, 0.7), 0, 0.46, 0, 0, PI / 4, 0); rf.scale.z = 0.62; B(0.08, 0.14, 0.01, M.red, 0, 0, 0.151, 0.004); B(0.09, 0.09, 0.01, col(0x9fd8e8, 0.3), -0.15, 0.18, 0.151, 0.004); B(0.09, 0.09, 0.01, col(0x9fd8e8, 0.3), 0.15, 0.18, 0.151, 0.004); plat(-5.78, -5.22, -4.6, -4.2, LY + 0.36);
    begin('舊皮箱', -6.3, LY, -4.6, PI / 2 + 0.1); B(0.7, 0.24, 0.45, col(0x7a4a2a, 0.5), 0, 0, 0, 0.03); B(0.72, 0.03, 0.04, col(0x4a3020, 0.5), 0, 0.1, 0.2, 0.01); B(0.72, 0.03, 0.04, col(0x4a3020, 0.5), 0, 0.1, -0.2, 0.01); S(0.02, M.brass, 0, 0.12, 0.23); plat(-6.53, -6.07, -4.95, -4.25, LY + 0.24);
    begin('地球儀', -6.3, LY + 0.24, -4.6); S(0.11, col(0x4aa3e0, 0.4), 0, 0.16, 0); S(0.112, col(0x7a9a54, 0.6), 0.02, 0.17, 0.01, 0.6, 0.7, 0.6); C(0.06, 0.07, 0.02, M.darker, 0, 0, 0, 12); add(new THREE.TorusGeometry(0.125, 0.006, 5, 20, PI), M.brass, 0, 0.16, 0, 0, 0, PI / 2 + 0.4);
    begin('雛人偶台', -3.05, LY, -4.2, -PI / 2); [0, 1, 2].forEach(function (k) { B(0.7, 0.14, 0.2, col(0xc8452e, 0.9), 0, k * 0.14, -k * 0.2 + 0.2, 0.006); }); plat(-3.25, -2.65, -4.55, -3.85, LY + 0.42);
    [[0, 2, 0x5e4a7a], [0.001, 2, 0xc8452e], [-0.22, 1, 0xd9a93a], [0, 1, 0x7a9a54], [0.22, 1, 0xe7a0a8], [-0.25, 0, 0x2f4b7c], [-0.08, 0, 0xf29a4a], [0.09, 0, 0x3f8f8a], [0.25, 0, 0xd9432b]].forEach(function (d, k) {
      begin('雛人偶', -3.05 + (0.2 - d[1] * 0.2) * -1 + 0.0, LY + (d[1] + 1) * 0.14, -4.2 + (k < 2 ? (k ? 0.12 : -0.12) : d[0]), -PI / 2); add(new THREE.ConeGeometry(0.045, 0.09, 8), col(d[2], 0.8), 0, 0.045, 0); S(0.022, M.cream, 0, 0.105, 0); S(0.024, M.black, 0, 0.115, -0.005, 1, 0.8, 0.9);
    });
    begin('鯉魚旗', -4.5, LY + 1.55, lz0 + 0.05); add(new THREE.CylinderGeometry(0.012, 0.012, 2.4, 6), M.hinoki, 0, 0, 0, 0, 0, PI / 2);
    [[0x2a2320, -0.75, 0.7], [0xc8452e, 0.05, 0.6], [0x2f4b7c, 0.75, 0.5]].forEach(function (k, n) { K.count('鯉魚旗'); var m = K.sway(tx('koi' + n, function () { return P.seigaiha('#' + k[0].toString(16).padStart(6, '0'), '#f6efdc', 24); }, 0.1).clone(), 0.03, 1.2 + n * 0.3); m.side = THREE.DoubleSide; add(new THREE.PlaneGeometry(k[2], 0.22, 6, 3), m, k[1], -0.14, 0.03); });
    begin('捲起的地毯', -5.0, LY, -6.25, 0); add(new THREE.CylinderGeometry(0.12, 0.12, 1.5, 16), pat.patch, 0, 0.12, 0, 0, 0, PI / 2); plat(-5.75, -4.25, -6.37, -6.13, LY + 0.24);
    begin('舊檯燈', -3.6, LY, -6.2); C(0.08, 0.1, 0.03, M.brass, 0, 0, 0, 14); C(0.012, 0.012, 0.36, M.brass, 0, 0.03, 0, 6); L([[0.05, 0], [0.14, -0.14]], mat('lampShade', null), 0, 0.52, 0, 16);
    begin('風箏', lx0 + 0.02, LY + 1.1, -5.0, PI / 2); var kt = add(new THREE.CircleGeometry(0.34, 4), tx('kite', function () { return P.yagasuri('#c8452e', '#f6efdc', 24); }, 0.2), 0, 0, 0.01); kt.scale.y = 1.3;
    begin('算盤', -3.3, LY + 0.36 + 0.0, -5.3, 0.4); B(0.3, 0.02, 0.1, M.darker, 0, 0.4, 0, 0.004);
    begin('球棒', -2.7, LY, -5.0); add(new THREE.CylinderGeometry(0.03, 0.018, 0.85, 8), M.hinoki, 0, 0.44, 0, 0, 0, 0.12);
    begin('棒球手套', -2.85, LY, -4.85, 0.4); S(0.1, col(0x9a5a2a, 0.7), 0, 0.05, 0, 1, 0.5, 1.1);
    begin('捕蟲網', lx0 + 0.1, LY, -3.9); add(new THREE.CylinderGeometry(0.01, 0.01, 1.4, 6), col(0x7a9a54, 0.5), 0, 0.7, 0, 0, 0, -0.08); add(new THREE.TorusGeometry(0.14, 0.008, 5, 16), steel, -0.06, 1.5, 0); add(new THREE.ConeGeometry(0.14, 0.3, 10, 1, true), mat('net', { color: 0xf6efdc, transparent: true, opacity: 0.45, side: THREE.DoubleSide }), -0.06, 1.35, 0, PI, 0, 0);
    begin('太鼓', -5.9, LY, -5.3); C(0.2, 0.2, 0.3, M.red, 0, 0, 0, 20); C(0.19, 0.19, 0.31, M.cream, 0, -0.005, 0, 20); plat(-6.1, -5.7, -5.5, -5.1, LY + 0.31);
    begin('舊電視', -3.4, LY, -3.75, PI); B(0.5, 0.4, 0.4, col(0x8a6a4a, 0.5), 0, 0, 0, 0.04); B(0.34, 0.26, 0.01, col(0x3a4a4a, 0.15), -0.05, 0.08, 0.2, 0.03); C(0.02, 0.02, 0.02, M.brass, 0.19, 0.28, 0.2, 8).rotation.x = PI / 2; C(0.02, 0.02, 0.02, M.brass, 0.19, 0.2, 0.2, 8).rotation.x = PI / 2; plat(-3.65, -3.15, -3.95, -3.55, LY + 0.4);
    K.knockable('陀螺', -4.0, LY + 0.04, -5.0, 0.04, function () { add(new THREE.ConeGeometry(0.04, 0.06, 12), col(0xd9a93a, 0.4), 0, -0.01, 0, PI, 0, 0); C(0.006, 0.006, 0.04, M.hinoki, 0, 0.02, 0, 6); });
    K.knockable('劍玉', -5.2, LY + 0.0, -5.0, 0.035, function () { C(0.012, 0.016, 0.12, M.hinoki, 0, 0, 0, 8); S(0.03, col(0xc8452e, 0.3), 0, 0.15, 0); }, 'cup');
    K.knockable('沙灘球', -4.2, LY + 0.14, -6.0, 0.14, function () { S(0.14, tx('beach', function () { return P.stripes(['#4aa3e0', '#f5f1e8', '#f29a4a', '#f5f1e8'], [24, 8, 24, 8]); }, [0.3, 0.3], 0.4)); });
    [[-3.9, -4.9, 0x4aa3e0], [-3.8, -4.95, 0xc8452e], [-3.85, -4.82, 0xd9a93a]].forEach(function (c) { K.knockable('積木', c[0], LY, c[1], 0.045, function () { B(0.075, 0.075, 0.075, col(c[2], 0.5), 0, 0, 0, 0.01); }, 'block'); });
    K.knockable('積木', -3.85, LY + 0.075, -4.9, 0.045, function () { B(0.075, 0.075, 0.075, col(0x7a9a54, 0.5), 0, 0, 0, 0.01); }, 'block'); K.knockable('積木', -3.85, LY + 0.15, -4.9, 0.045, function () { B(0.075, 0.075, 0.075, col(0x5e4a7a, 0.5), 0, 0, 0, 0.01); }, 'block');

    /* ============================== TATAMI ROOM ============================== */
    K.setRoom('和室'); root();
    var tx0 = 2.6, tx1 = 7.0, tz0 = -7.5, tz1 = -3.5, juraku = tx('juraku', function () { return P.plaster('#c9cfa8', 91); }, 1.2, 0.95);
    wall('x', tx0 - 0.02, tz0, tz1 - 0.12, { m: juraku, th: 0.08 }); wall('z', tz0 - 0.06, tx0, tx1, { m: juraku }); wall('x', tx1 + 0.06, tz0, tz1, { m: juraku }); wall('z', tz1 - 0.06, 4.5, tx1, { m: juraku });
    ceil(tx0, tx1, tz0, tz1, H);
    add(G.planeM(tx1 - tx0, tz1 - tz0), M.honey, (tx0 + tx1) / 2, 0.001, (tz0 + tz1) / 2, -PI / 2);
    // 8 mats
    for (var mj = 0; mj < 2; mj++) for (var mi = 0; mi < 4; mi++) { begin('榻榻米', 3.15 + mi * 0.9 + 0.45, 0, -6.9 + mj * 1.8 + 0.9 - 0.1); B(0.895, 0.03, 1.795, M.tatami, 0, 0, 0, 0.006, true); B(0.045, 0.032, 1.795, M.heri, -0.425, 0, 0, 0.004, true); B(0.045, 0.032, 1.795, M.heri, 0.425, 0, 0, 0.004, true); }
    plat(3.15, 6.75, -7.0, -3.4, 0.03);
    // sliding fusuma in the doorway (open when someone is near)
    var fusL = begin('襖', 3.15, 0, -D - 0.02, 0, true); B(0.82, 1.92, 0.035, M.black, 0, 0.02, 0, 0.006); PL(0.74, 1.84, mat('fus1', { map: SG.tex('fus1', function () { return P.byobu(1); }), roughness: 0.7 }), 0, 0.98, 0.019); PL(0.74, 1.84, mat('fus1', null), 0, 0.98, -0.019, 0, PI, 0);
    var fusR = begin('襖', 3.95, 0, -D - 0.07, 0, true); B(0.82, 1.92, 0.035, M.black, 0, 0.02, 0, 0.006); PL(0.74, 1.84, mat('fus2', { map: SG.tex('fus2', function () { return P.byobu(2); }), roughness: 0.7 }), 0, 0.98, 0.019); PL(0.74, 1.84, mat('fus2', null), 0, 0.98, -0.019, 0, PI, 0);
    K.triggers.push({ kind: 'slide', a: fusL, b: fusR, x: 3.55, z: -D, open: 0 });
    // shoji windows on the east wall, round window north
    [-6.6, -5.5, -4.4].forEach(function (z) { K.shoji(tx1 - 0.01, z, 1.0, 1.3, -PI / 2, '障子窗'); K.stat.children[K.stat.children.length - 1].position.y = 0.78; });
    begin('圓窗', 5.4, 1.45, tz0 + 0.01); add(new THREE.CircleGeometry(0.5, 28), K.shojiM, 0, 0, 0); add(new THREE.TorusGeometry(0.5, 0.045, 8, 32), M.darker, 0, 0, 0.01); for (i = -2; i <= 2; i++) { B(0.02, 2 * Math.sqrt(0.25 - i * i * 0.03), 0.02, M.hinoki, i * 0.17, -Math.sqrt(0.25 - i * i * 0.03), 0.01, 0.004); }
    // tokonoma + chigaidana
    begin('床之間（和室）', 3.5, 0, tz0 + 0.3); B(1.5, 0.12, 0.6, M.red, 0, 0, 0, 0.012, true); B(0.1, H, 0.1, M.darker, 0.78, 0, 0.25, 0.012, true); plat(2.75, 4.25, tz0, tz0 + 0.6, 0.12);
    var sc2 = SG.tex('scroll2', function () { var c = P.gyotaku(); var g = c.getContext('2d'); g.drawImage(P.washi('#f3e8d0', 63), 0, 0, 256, 256, 52, 128, 408, 748); SG.inkText(g, '一期一会', 256, 215, 120, '#1d1a1a', true, 10); g.fillStyle = SG.PAL.vermilion; g.fillRect(300, 760, 56, 56); SG.inkText(g, '寿', 328, 788, 40, '#f6ead2', false, 2); return c; });
    begin('掛軸', 3.5, 0.5, tz0 + 0.04); PL(0.62, 1.35, mat('scroll2', { map: sc2, roughness: 0.9 }), 0, 0.72, 0);
    begin('生花', 3.05, 0.12, tz0 + 0.3); L([[0, 0], [0.09, 0], [0.12, 0.05], [0.04, 0.09]], col(0x3a2a1e, 0.3), 0, 0, 0, 14); add(G.tube([[0, 0.08, 0], [-0.04, 0.4, 0], [0.1, 0.7, 0.03]], 0.008, 8, 5), M.darker); [[0.1, 0.72, 0xc8452e], [-0.03, 0.45, 0xf6efdc], [0.04, 0.3, 0xd9a93a]].forEach(function (f) { S(0.045, col(f[2], 0.6), f[0], f[1], 0.02, 1, 0.7, 1); }); for (i = 0; i < 4; i++) { var lf = add(new THREE.ConeGeometry(0.03, 0.3, 5), M.leafD, -0.05 + i * 0.03, 0.26, 0, 0, 0, 0.5 - i * 0.3); lf.scale.z = 0.3; }
    begin('違棚', 5.0, 0, tz0 + 0.2); B(0.9, 0.03, 0.3, M.dark, -0.2, 0.9, 0, 0.008, true); B(0.9, 0.03, 0.3, M.dark, 0.3, 1.25, 0, 0.008, true); B(0.03, 0.35, 0.03, M.dark, 0.05, 0.9, 0, 0.004); B(1.4, 0.5, 0.36, M.dark, 0.05, 0, 0, 0.01, true); plat(4.35, 5.75, tz0, tz0 + 0.38, 0.5); plat(4.35, 5.25, tz0, tz0 + 0.35, 0.93, 0.88);
    [['抹茶碗', 4.6, 0.93, 0x35502e], ['茶筒', 4.95, 0.93, 0xc8452e], ['香合', 5.15, 1.28, 0xd9a93a], ['德利', 5.45, 1.28, 0xf5f1e8]].forEach(function (c) { begin(c[0], c[1], c[2], tz0 + 0.2); if (c[0] === '抹茶碗') L([[0, 0], [0.04, 0], [0.065, 0.06], [0.06, 0.065]], col(c[3], 0.4), 0, 0, 0, 14); else if (c[0] === '茶筒') { C(0.04, 0.04, 0.12, col(c[3], 0.3), 0, 0, 0, 14); } else if (c[0] === '香合') S(0.04, col(c[3], 0.3, { metalness: 0.6 }), 0, 0.03, 0, 1, 0.6, 1); else L([[0, 0], [0.04, 0], [0.05, 0.07], [0.02, 0.13], [0.025, 0.15]], col(c[3], 0.3), 0, 0, 0, 12); });
    // oshiire with futon stacks (west wall)
    begin('押入', tx0 + 0.42, 0, -5.2, PI / 2); B(1.8, 0.05, 0.8, M.hinoki, 0, 0.9, 0, 0.01, true); B(1.8, 0.05, 0.8, M.hinoki, 0, 1.85, 0, 0.01, true); B(0.05, 1.9, 0.8, M.hinoki, -0.9, 0, 0, 0.01, true); B(0.05, 1.9, 0.8, M.hinoki, 0.9, 0, 0, 0.01, true); plat(tx0, tx0 + 0.82, -6.1, -4.3, 0.95, 0.88); plat(tx0, tx0 + 0.82, -6.15, -6.05, 1.9); plat(tx0, tx0 + 0.82, -4.35, -4.25, 1.9);
    ['sakura', 'seigaiha', 'cream'].forEach(function (c, k) { begin('棉被', tx0 + 0.42, 0.02 + k * 0.2, -5.6, PI / 2); B(0.8, 0.19, 0.72, cloth[c], 0, 0, 0, 0.07, true); }); plat(tx0 + 0.05, tx0 + 0.8, -6.0, -5.2, 0.62);
    begin('枕頭', tx0 + 0.42, 0.95, -5.5, PI / 2); B(0.5, 0.14, 0.32, cloth.ichiRed, 0, 0, 0, 0.06, true); begin('枕頭', tx0 + 0.42, 0.95, -4.8, PI / 2 + 0.2); B(0.5, 0.14, 0.32, cloth.stripe, 0, 0, 0, 0.06, true);
    begin('座墊堆', tx0 + 0.42, 0.02, -4.7, PI / 2); ['kikko', 'mustard', 'indigo', 'asanoha'].forEach(function (c, k) { B(0.5, 0.08, 0.5, cloth[c], 0, k * 0.08, 0, 0.035, true); }); plat(tx0 + 0.15, tx0 + 0.7, -4.95, -4.45, 0.34);
    // laid-out futon
    begin('敷布團', 5.9, 0.03, -5.0, 0); B(1.0, 0.08, 2.0, cloth.cream, 0, 0, 0, 0.035, true); plat(5.4, 6.4, -6.0, -4.0, 0.11);
    begin('掛布團', 5.9, 0.11, -4.75, 0); B(1.06, 0.1, 1.45, cloth.sakura, 0, 0, 0, 0.045, true); B(1.06, 0.1, 0.3, cloth.cream, 0, 0.02, -0.72, 0.045, true); plat(5.37, 6.43, -5.5, -4.0, 0.21);
    begin('蕎麥枕', 5.9, 0.11, -5.75); B(0.46, 0.1, 0.26, pat.urokoR, 0, 0, 0, 0.045, true);
    // low writing desk with calligraphy things
    var dk = begin('文机', 4.0, 0.03, -5.6, 0.1); B(0.9, 0.03, 0.45, M.red, 0, 0.3, 0, 0.01, true); B(0.04, 0.3, 0.4, M.red, -0.4, 0, 0, 0.008, true); B(0.04, 0.3, 0.4, M.red, 0.4, 0, 0, 0.008, true); platG(dk, 0.9, 0.45, 0.33, 0.28);
    begin('硯台', 3.75, 0.36, -5.6); B(0.1, 0.02, 0.14, M.black, 0, 0, 0, 0.005); begin('毛筆', 3.9, 0.365, -5.55, 0.4); add(new THREE.CylinderGeometry(0.005, 0.005, 0.2, 6), M.hinoki, 0, 0.006, 0, PI / 2, 0, 0); add(new THREE.ConeGeometry(0.008, 0.035, 6), M.black, 0, 0.006, 0.115, PI / 2, 0, 0);
    begin('半紙', 4.1, 0.362, -5.6, 0.1); PL(0.24, 0.33, mat('hanshi', { map: SG.tex('hanshi', function () { var c = P.washi('#fbf6ea', 71); SG.inkText(c.getContext('2d'), '猫', 128, 128, 170, '#1d1a1a', false, 12); return c; }), roughness: 0.9 }), 0, 0.002, 0, -PI / 2);
    begin('文鎮', 4.1, 0.364, -5.42); B(0.2, 0.015, 0.02, M.iron, 0, 0, 0, 0.004);
    begin('座椅', 4.0, 0.03, -5.05, 0.1); B(0.5, 0.07, 0.5, cloth.kikko, 0, 0, 0, 0.03, true); B(0.5, 0.42, 0.06, M.dark, 0, 0.07, 0.24, 0.02, true); plat(3.75, 4.25, -5.3, -4.8, 0.1);
    // go board, tea things, hibachi with iron kettle
    var gb = begin('碁盤', 5.0, 0.03, -4.3, 0.2); B(0.45, 0.18, 0.42, M.hinoki, 0, 0.06, 0, 0.012); [[-1, -1], [1, -1], [-1, 1], [1, 1]].forEach(function (c) { C(0.03, 0.02, 0.06, M.hinoki, c[0] * 0.17, 0, c[1] * 0.16, 8); }); platG(gb, 0.45, 0.42, 0.24);
    PL(0.4, 0.37, mat('goban', { map: SG.tex('goban', function () { var c = P.wood({ w: 256, h: 256, base: '#e2c08c', seed: 97, contrast: 0.06, knots: 0 }); var g = c.getContext('2d'); g.strokeStyle = '#2a2320'; g.lineWidth = 1.5; for (var k = 0; k < 13; k++) { var q = 16 + k * 18.6; g.beginPath(); g.moveTo(q, 16); g.lineTo(q, 240); g.moveTo(16, q); g.lineTo(240, q); g.stroke(); } return c; }), roughness: 0.6 }), 0, 0.241, 0, -PI / 2);
    for (i = 0; i < 12; i++) { K.count('碁石'); C(0.011, 0.011, 0.006, i & 1 ? M.black : M.white, -0.15 + (i * 37 % 11) * 0.03, 0.243, -0.14 + (i * 53 % 10) * 0.03, 10); }
    begin('碁笥', 4.6, 0.03, -4.15); L([[0, 0], [0.05, 0], [0.065, 0.04], [0.05, 0.075]], M.darker, 0, 0, 0, 14); begin('碁笥', 5.4, 0.03, -4.45); L([[0, 0], [0.05, 0], [0.065, 0.04], [0.05, 0.075]], M.darker, 0, 0, 0, 14);
    begin('火鉢', 4.9, 0.03, -6.3); L([[0, 0], [0.2, 0], [0.26, 0.14], [0.24, 0.3], [0.2, 0.3], [0.2, 0.26]], col(0x2f4b7c, 0.25), 0, 0, 0, 20); C(0.2, 0.2, 0.01, col(0xd9d2c2, 1), 0, 0.25, 0, 18); plat(4.65, 5.15, -6.55, -6.05, 0.33);
    begin('鐵瓶', 4.9, 0.29, -6.3, 0.5); L([[0, 0], [0.07, 0], [0.095, 0.05], [0.08, 0.1], [0.04, 0.12]], M.iron, 0, 0, 0, 14); add(new THREE.TorusGeometry(0.07, 0.007, 5, 14, PI), M.iron, 0, 0.12, 0); add(new THREE.CylinderGeometry(0.01, 0.018, 0.07, 6), M.iron, 0.1, 0.08, 0, 0, 0, -1);
    var ts = new THREE.Mesh(new THREE.PlaneGeometry(0.18, 0.4), (function () { var m = SG.steamProto.clone(); m.uniforms = { uTime: SG.uTime, uAmt: { value: 0.6 } }; return m; })()); ts.position.set(5.0, 0.62, -6.3); ts.layers.set(1); K.dyn.add(ts); K.count('鐵瓶蒸氣');
    begin('茶盤', 4.3, 0.03, -6.4, 0.3); B(0.36, 0.02, 0.26, M.darker, 0, 0, 0, 0.008); L([[0, 0], [0.045, 0], [0.065, 0.04], [0.05, 0.08], [0.02, 0.09]], col(0x7a4a2a, 0.3), -0.08, 0.02, 0, 12);
    K.knockable('湯吞', 4.36, 0.05, -6.38, 0.03, function () { L([[0, 0], [0.025, 0], [0.03, 0.06]], col(0x35502e, 0.3), 0, 0, 0, 12); }, 'cup'); K.knockable('湯吞', 4.4, 0.05, -6.47, 0.03, function () { L([[0, 0], [0.025, 0], [0.03, 0.06]], col(0x2f4b7c, 0.3), 0, 0, 0, 12); }, 'cup');
    // kimono rack, byobu, mirror stand, andon, koto
    begin('衣桁', 6.55, 0, -6.6, -PI / 2 + 0.25); B(0.04, 1.5, 0.04, M.black, -0.6, 0, 0, 0.008); B(0.04, 1.5, 0.04, M.black, 0.6, 0, 0, 0.008); B(1.4, 0.04, 0.04, M.black, 0, 1.5, 0, 0.008); B(0.2, 0.03, 0.3, M.black, -0.6, 0, 0, 0.008); B(0.2, 0.03, 0.3, M.black, 0.6, 0, 0, 0.008);
    begin('和服', 6.55, 0, -6.6, -PI / 2 + 0.25); var kim = tx('kimono', function () { return P.sakura('#5e4a7a', '#f6efdc', '#d9a93a'); }, 0.3); B(1.25, 0.5, 0.03, kim, 0, 1.0, 0.01, 0.01, true); B(0.6, 0.9, 0.03, kim, 0, 0.2, 0.012, 0.01, true); B(0.12, 1.0, 0.035, cloth.cream, 0, 0.5, 0.02, 0.01, true);
    plat(6.2, 6.9, -7.3, -5.95, 1.55, 1.45);
    var by = begin('屏風', 6.2, 0.03, -3.95, PI + 0.2); for (i = 0; i < 4; i++) { var pg = new THREE.Group(); by.add(pg); pg.position.set(-0.75 + i * 0.5 + 0.25, 0, (i & 1) ? 0.07 : -0.07); pg.rotation.y = (i & 1) ? 0.28 : -0.28; var bm = new THREE.Mesh(G.rbox(0.52, 1.3, 0.03, 0.008), M.black); bm.position.y = 0.65; pg.add(bm); var bp = new THREE.Mesh(new THREE.PlaneGeometry(0.47, 1.25), mat('byo' + i, { map: SG.tex('byo' + i, function () { return P.byobu(i); }), roughness: 0.6 })); bp.position.set(0, 0.65, 0.017); pg.add(bp); }
    plat(5.3, 6.9, -4.08, -3.82, 1.33);
    begin('鏡台', 6.6, 0.03, -3.75 - 1.6 + 0.0, -PI / 2); B(0.5, 0.3, 0.3, M.red, 0, 0, 0, 0.012, true); B(0.04, 0.5, 0.03, M.red, -0.18, 0.3, -0.1, 0.006); B(0.04, 0.5, 0.03, M.red, 0.18, 0.3, -0.1, 0.006); add(new THREE.CircleGeometry(0.17, 20), mat('mirror', null), 0, 0.62, -0.08); add(new THREE.TorusGeometry(0.17, 0.015, 6, 22), M.red, 0, 0.62, -0.08); plat(6.45, 6.75, -5.6, -5.1, 0.33);
    begin('行燈', 3.0, 0.03, -3.95); B(0.26, 0.5, 0.26, mat('andon', null), 0, 0.05, 0, 0.01); B(0.3, 0.03, 0.3, M.darker, 0, 0, 0, 0.008); B(0.3, 0.025, 0.3, M.darker, 0, 0.56, 0, 0.006); K.glow(3.0, 0.35, -3.95, 1.0, 0xffb060, 0.45); plat(2.85, 3.15, -4.1, -3.8, 0.6);
    begin('箏', 5.3, 0.03, -7.1, 0.05); B(1.7, 0.07, 0.24, M.hinoki, 0, 0.04, 0, 0.03, true); for (i = 0; i < 9; i++) add(new THREE.CylinderGeometry(0.0015, 0.0015, 1.6, 3), M.cream, 0, 0.115, -0.09 + i * 0.022, 0, 0, PI / 2); for (i = 0; i < 9; i++) add(new THREE.ConeGeometry(0.012, 0.03, 4), M.cream, -0.5 + i * 0.12, 0.125, -0.09 + i * 0.022); plat(4.45, 6.15, -7.25, -6.95, 0.14);
    begin('團扇', 5.5, 0.035, -5.2, 0.7); C(0.11, 0.11, 0.004, tx('uchiwa', function () { return P.seigaiha('#f6efdc', '#4aa3e0', 20); }, null), 0, 0, 0, 20); B(0.015, 0.006, 0.16, M.hinoki, 0, 0, 0.17, 0.002);
    begin('蚊帳勾／吊燈', 4.9, H - 0.1, -5.3); add(new THREE.CylinderGeometry(0.004, 0.004, 0.4, 4), M.black, 0, -0.2, 0); add(G.latheS([[0.05, 0], [0.2, -0.08], [0.22, -0.2], [0.1, -0.26]], 20), mat('lampShade', null), 0, -0.4, 0); S(0.045, mat('bulb', null), 0, -0.56, 0); K.glow(4.9, H - 0.6, -5.3, 1.2, 0xffc880, 0.45);
    K.knockable('手鞠', 4.5, 0.11, -4.5, 0.08, function () { S(0.08, tx('temari', function () { return P.asanoha('#c8452e', '#f6dc9a', 24); }, 0.1)); });
    K.knockable('紙氣球', 6.0, 0.1, -6.6, 0.07, function () { S(0.07, tx('kamifusen', function () { return P.stripes(['#c8452e', '#f6efdc', '#2f4b7c', '#f6efdc', '#d9a93a', '#f6efdc', '#7a9a54', '#f6efdc'], [10, 10, 10, 10, 10, 10, 10, 10]); }, [0.2, 0.2], 0.9), 0, 0, 0, 1, 0.85, 1); });
    light(4.9, H - 0.7, -5.3, 0xffcf90, 7, 7);

    /* ============================== GARDEN ============================== */
    K.setRoom('庭院'); root();
    // boundary fences / hedges + colliders, garden objects' colliders
    add(G.planeM(6.4, 1.7), M.bam, 7.95, 0.55, EN + 3.0, 0, -PI / 2, 0); add(G.planeM(6.4, 1.7), M.bam, -7.95, 0.55, EN + 3.0, 0, PI / 2, 0);
    plat(-8.1, -7.9, 2.4, 8.8, 1.4, -0.3, true); plat(7.9, 8.1, 2.4, 8.8, 1.4, -0.3, true); plat(-8, 8, EN + 6.15, EN + 6.3, 1.4, -0.3, true);
    plat(-8, -6.7, 2.3, 2.6, H, -0.3, true); plat(4.5, 8, 2.3, 2.6, H, -0.3, true); add(G.boxM(3.5, H + 0.3, 0.12), M.plaster, 6.25, H / 2 - 0.15, 2.45); add(G.boxM(1.3, H + 0.3, 0.12), M.plaster, -7.35, H / 2 - 0.15, 2.45);
    plat(-6.76, -6.64, 2.9, 4.05, H, -0.3, true);
    [[-4.8, EN + 1.45], [-1.6, EN + 1.45], [1.6, EN + 1.45], [4.8, EN + 1.45]].forEach(function (p) { plat(p[0] - 0.07, p[0] + 0.07, p[1] - 0.07, p[1] + 0.07, 2.3, 0, true); });
    plat(-2.72, -2.28, EN + 3.08, EN + 3.52, 0.9, -0.3); plat(3.5, 3.72, EN + 2.5, EN + 2.72, 2.0, -0.3, true);
    begin('沓脫石', 0, -0.3, EN + 1.8); B(1.2, 0.15, 0.55, M.stoneD, 0, 0, 0, 0.05, true); plat(-0.6, 0.6, EN + 1.52, EN + 2.08, -0.15, -0.3);
    begin('沓脫石', 4.2, -0.3, EN + 1.8); B(0.9, 0.15, 0.5, M.stoneM, 0, 0, 0, 0.05, true); plat(3.75, 4.65, EN + 1.55, EN + 2.05, -0.15, -0.3);
    begin('沓脫石', -4.0, -0.3, EN + 1.8); B(0.9, 0.15, 0.5, M.stoneM, 0, 0, 0, 0.05, true); plat(-4.45, -3.55, EN + 1.55, EN + 2.05, -0.15, -0.3);
    [[0.1, 2.5], [-0.5, 3.0], [-1.3, 3.3], [-2.0, 3.9], [-1.9, 4.7], [-1.2, 5.3]].forEach(function (p, k) { begin('飛石', p[0], -0.3, EN + p[1], k); S(0.26, k & 1 ? M.stoneM : M.stoneD, 0, 0.0, 0, 1, 0.22, 0.85); });
    // shishi-odoshi + stone basin
    begin('手水鉢', 2.9, -0.3, EN + 4.9); L([[0, 0], [0.2, 0], [0.24, 0.3], [0.17, 0.3], [0.15, 0.2]], M.stoneD, 0, 0, 0, 14); C(0.16, 0.16, 0.01, mat('basinWater', { color: 0x6fc3c0, roughness: 0.05 }), 0, 0.25, 0, 16); plat(2.66, 3.14, EN + 4.66, EN + 5.14, 0.02, -0.3);
    begin('鹿威', 3.35, -0.3, EN + 4.9); C(0.02, 0.02, 0.6, M.bam, -0.12, 0, 0, 8); C(0.02, 0.02, 0.6, M.bam, 0.12, 0, 0, 8); add(G.tube([[0.5, 0.75, -0.3], [0.2, 0.72, -0.1]], 0.02, 2, 8), M.bam);
    var sip = begin(null, 3.35, 0.2, EN + 4.9, 0, true); add(new THREE.CylinderGeometry(0.03, 0.03, 0.6, 10), M.bam, 0, 0, 0.05, PI / 2, 0, 0); K.count('鹿威竹筒');
    up.push(function (t) { var ph = (t % 7) / 7; sip.rotation.x = ph < 0.86 ? -0.35 + ph * 0.3 : (ph < 0.9 ? -0.09 + (ph - 0.86) * 18 : 0.63 - (ph - 0.9) * 9.8); SG.sipPhase = ph; });
    // tools and pots
    begin('灑水壺', -5.2, -0.3, EN + 2.4, 0.6); L([[0, 0], [0.1, 0], [0.11, 0.2], [0.08, 0.22]], col(0x4aa3e0, 0.35), 0, 0, 0, 14); add(G.tube([[0.09, 0.08, 0], [0.24, 0.2, 0], [0.28, 0.21, 0]], 0.015, 6, 6), col(0x4aa3e0, 0.35)); add(new THREE.TorusGeometry(0.08, 0.01, 5, 12, PI), col(0x4aa3e0, 0.35), -0.02, 0.2, 0);
    begin('水桶', -5.6, -0.3, EN + 2.9); L([[0, 0], [0.11, 0], [0.14, 0.24], [0.145, 0.25]], steel, 0, 0, 0, 14); add(new THREE.TorusGeometry(0.14, 0.006, 5, 14, PI), steel, 0, 0.25, 0);
    begin('竹耙', -7.75, -0.3, EN + 3.2, PI / 2); add(new THREE.CylinderGeometry(0.012, 0.012, 1.5, 6), M.bam, 0, 0.75, 0, 0, 0, 0.1); for (i = 0; i < 7; i++) add(new THREE.CylinderGeometry(0.004, 0.004, 0.24, 4), M.bam, 0.08 + (i - 3) * 0.03, 0.1, 0, 0, 0, (i - 3) * 0.1);
    begin('鏟子', -7.75, -0.3, EN + 3.7, PI / 2); add(new THREE.CylinderGeometry(0.014, 0.014, 0.9, 6), M.hinoki, 0, 0.6, 0, 0, 0, 0.08); B(0.16, 0.22, 0.01, steel, 0.04, 0, 0, 0.004);
    begin('竹掃帚', -7.75, -0.3, EN + 4.3, PI / 2); add(new THREE.CylinderGeometry(0.012, 0.012, 1.3, 6), M.bam, 0, 0.8, 0, 0, 0, 0.1); add(new THREE.ConeGeometry(0.12, 0.45, 8), col(0x9a7a4a, 0.95), 0.08, 0.22, 0);
    [[-6.9, 5.6, 0xc8452e, 0xf29a4a], [-6.4, 5.75, 0xd9a93a, 0xf6efdc], [-5.9, 5.6, 0x2f4b7c, 0xe7a0a8], [-5.4, 5.75, 0x7a4a2a, 0xd9432b]].forEach(function (p, k) { begin('花盆', p[0], -0.3, EN + p[1]); L([[0, 0], [0.08, 0], [0.12, 0.16], [0.125, 0.17]], col(p[2], 0.5), 0, 0, 0, 12); for (var q = 0; q < 5; q++) { add(new THREE.CylinderGeometry(0.004, 0.004, 0.16, 4), M.leafD, Math.cos(q * 1.26) * 0.05, 0.25, Math.sin(q * 1.26) * 0.05); S(0.035, col(p[3], 0.6), Math.cos(q * 1.26) * 0.05, 0.34, Math.sin(q * 1.26) * 0.05, 1, 0.6, 1); } });
    begin('番茄花槽', 6.6, -0.3, EN + 4.2, PI / 2); B(1.2, 0.26, 0.4, M.dark, 0, 0, 0, 0.02, true); B(1.1, 0.02, 0.3, col(0x4a3020, 1), 0, 0.25, 0, 0.004); for (i = 0; i < 4; i++) { add(new THREE.CylinderGeometry(0.008, 0.008, 0.7, 5), M.bam, -0.42 + i * 0.28, 0.6, 0); S(0.1, i & 1 ? M.leafM : M.leafD, -0.42 + i * 0.28, 0.55, 0, 1, 1.4, 1); K.count('番茄', 2); S(0.035, col(0xd9432b, 0.35), -0.42 + i * 0.28 + 0.06, 0.5, 0.07); S(0.03, col(i & 1 ? 0xd9432b : 0x9fb84a, 0.35), -0.42 + i * 0.28 - 0.05, 0.66, 0.06); } plat(6.4, 6.8, EN + 3.6, EN + 4.8, -0.04, -0.3);
    var bn = begin('庭院長椅', 5.6, -0.3, EN + 5.7, PI + 0.3); B(1.3, 0.05, 0.4, M.engW, 0, 0.4, 0, 0.012, true); B(1.3, 0.3, 0.04, M.engW, 0, 0.55, -0.2, 0.012, true); [[-0.55, 0], [0.55, 0]].forEach(function (c) { B(0.06, 0.4, 0.36, M.darker, c[0], 0, 0, 0.01); }); plat(5.0, 6.2, EN + 5.45, EN + 5.95, 0.15, 0.08);
    begin('狸貓擺飾', -6.9, -0.3, EN + 4.7, 0.9); L([[0, 0], [0.16, 0], [0.2, 0.14], [0.15, 0.34], [0, 0.36]], col(0x8a5a36, 0.5), 0, 0, 0, 14); S(0.13, col(0xf1e7d2, 0.5), 0, 0.17, 0.09, 1, 1.1, 0.7); S(0.12, col(0x8a5a36, 0.5), 0, 0.46, 0); S(0.07, col(0xf1e7d2, 0.5), 0, 0.44, 0.07); S(0.016, M.black, -0.04, 0.48, 0.105); S(0.016, M.black, 0.04, 0.48, 0.105); add(new THREE.ConeGeometry(0.2, 0.1, 14), col(0xd9c27a, 0.9), 0, 0.6, 0); L([[0, 0], [0.04, 0], [0.05, 0.08], [0.02, 0.12]], col(0xf5f1e8, 0.3), 0.2, 0.2, 0.05, 10); plat(-7.1, -6.7, EN + 4.5, EN + 4.9, 0.3, -0.3);
    begin('青蛙擺飾', 1.9, -0.25, EN + 4.6, -0.8); S(0.07, col(0x7a9a54, 0.3), 0, 0.05, 0, 1.1, 0.8, 1.2); S(0.022, col(0x7a9a54, 0.3), -0.035, 0.1, 0.04); S(0.022, col(0x7a9a54, 0.3), 0.035, 0.1, 0.04); S(0.01, M.black, -0.035, 0.105, 0.058); S(0.01, M.black, 0.035, 0.105, 0.058);
    begin('狗屋', 6.3, -0.3, EN + 2.75 + 0.3, PI + 0.2); B(0.9, 0.6, 0.8, M.hinoki, 0, 0, 0, 0.015, true); var roof = add(new THREE.CylinderGeometry(0.01, 0.75, 0.4, 4, 1), col(0xc8452e, 0.6), 0, 0.8, 0, 0, PI / 4, 0); roof.scale.z = 0.92; add(new THREE.CircleGeometry(0.2, 16), M.black, 0, 0.3, 0.405).scale.y = 1.3; PL(0.3, 0.1, label('inu', 'いぬ', '#f6efdc', '#2a2320'), 0, 0.68, 0.41); plat(5.8, 6.8, EN + 2.6, EN + 3.5, 0.3, -0.3); plat(5.7, 6.9, EN + 2.5, EN + 3.6, 0.72, 0.6);
    begin('狗碗', 5.5, -0.3, EN + 3.1); L([[0, 0], [0.1, 0], [0.085, 0.05], [0.07, 0.05]], col(0x4aa3e0, 0.4), 0, 0, 0, 16);
    K.knockable('骨頭玩具', 5.2, -0.27, EN + 3.3, 0.03, function () { add(new THREE.CapsuleGeometry(0.014, 0.1, 3, 8), M.white, 0, 0, 0, 0, 0, PI / 2); [[-0.06, 0.012], [-0.06, -0.012], [0.06, 0.012], [0.06, -0.012]].forEach(function (c) { S(0.02, M.white, c[0], 0, c[1]); }); });
    K.knockable('足球', -3.6, -0.19, EN + 5.3, 0.11, function () { S(0.11, tx('soccer', function () { return P.kikko('#f5f1e8', '#2a2320', 14); }, 0.09, 0.5)); });
    K.knockable('飛盤', 4.4, -0.29, EN + 4.6, 0.11, function () { C(0.11, 0.1, 0.02, col(0xf29a4a, 0.4), 0, 0, 0, 20); }, 'cup');
    begin('獨輪推車', -6.8, -0.3, EN + 3.3, 0.5); B(0.5, 0.2, 0.7, col(0x7a9a54, 0.5), 0, 0.3, 0, 0.04); C(0.16, 0.16, 0.06, M.black, 0, 0, 0.45, 14).rotation.z = PI / 2; add(new THREE.CylinderGeometry(0.014, 0.014, 0.7, 6), M.hinoki, -0.2, 0.36, -0.55, PI / 2 - 0.2, 0, 0); add(new THREE.CylinderGeometry(0.014, 0.014, 0.7, 6), M.hinoki, 0.2, 0.36, -0.55, PI / 2 - 0.2, 0, 0); plat(-7.1, -6.5, EN + 2.95, EN + 3.65, 0.2, -0.3);
    begin('水管捲盤', 7.6, -0.3, EN + 2.9, -PI / 2); add(new THREE.TorusGeometry(0.16, 0.05, 8, 20), col(0x3f8f8a, 0.6), 0, 0.25, 0); B(0.3, 0.06, 0.2, M.black, 0, 0, 0, 0.01);
    var pin = begin('風車', -5.0, -0.3, EN + 5.4, 0, true); add(new THREE.CylinderGeometry(0.008, 0.008, 0.7, 5), M.hinoki, 0, 0.35, 0); var pw = new THREE.Group(); pw.position.set(0, 0.68, 0.03); pin.add(pw);
    [0xc8452e, 0xd9a93a, 0x4aa3e0, 0x7a9a54].forEach(function (c, k) { var m = new THREE.Mesh(new THREE.CircleGeometry(0.1, 3), new THREE.MeshStandardMaterial({ color: c, side: THREE.DoubleSide, roughness: 0.6 })); m.rotation.z = k * PI / 2; m.position.set(Math.cos(k * PI / 2) * 0.06, Math.sin(k * PI / 2) * 0.06, 0); m.userData.keep = true; pw.add(m); });
    up.push(function (t) { pw.rotation.z = t * (3 + Math.sin(t * 0.37) * 2); });
    // sprinkler with rotating arcs of water
    var spr = begin('灑水器', -3.6, -0.3, EN + 4.4, 0, true); C(0.05, 0.07, 0.08, M.black, 0, 0, 0, 10); var sh = new THREE.Group(); sh.position.y = 0.09; spr.add(sh);
    var wm = new THREE.MeshBasicMaterial({ color: 0xdff4ff, transparent: true, opacity: 0.55, depthWrite: false }); [0, PI].forEach(function (a) { var w = new THREE.Mesh(G.tube([[0, 0, 0], [0.35, 0.3, 0], [0.8, 0.25, 0], [1.15, 0.0, 0]], 0.012, 14, 5), wm); w.rotation.y = a; w.layers.set(1); w.userData.keep = true; sh.add(w); });
    up.push(function (t) { sh.rotation.y = t * 1.6; sh.visible = (t % 30) < 18; });
    // butterflies and a dragonfly (time-driven paths)
    var bugs = [];
    [[0xf6efdc, 0], [0xf2d24a, 1], [0xe7a0a8, 2]].forEach(function (c) { var g = begin('蝴蝶', 0, 0, 0, 0, true), wings = [];[-1, 1].forEach(function (s) { var m = new THREE.Mesh(new THREE.CircleGeometry(0.045, 8), new THREE.MeshStandardMaterial({ color: c[0], side: THREE.DoubleSide, roughness: 0.8 })); m.position.x = s * 0.04; m.scale.y = 1.3; m.userData.keep = true; var pv = new THREE.Group(); pv.add(m); g.add(pv); wings.push([pv, s]); }); bugs.push({ g: g, w: wings, k: c[1], fly: 0 }); });
    var dfly = begin('蜻蜓', 0, 0, 0, 0, true); add(new THREE.CylinderGeometry(0.006, 0.004, 0.14, 5), col(0xc8452e, 0.3), 0, 0, 0, PI / 2, 0, 0).userData.keep = true; [-1, 1].forEach(function (s) { var m = new THREE.Mesh(new THREE.PlaneGeometry(0.11, 0.025), new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.5, side: THREE.DoubleSide })); m.position.set(s * 0.06, 0.005, 0.03); m.rotation.x = -PI / 2; m.userData.keep = true; dfly.add(m); });
    up.push(function (t) {
      bugs.forEach(function (b) { var a = t * 0.4 + b.k * 2.1, cx = [-5.5, 3.8, -1.5][b.k], cz = EN + [5.2, 4.4, 5.6][b.k]; b.g.position.set(cx + Math.sin(a) * 1.1 + Math.sin(a * 2.7) * 0.3, 0.35 + Math.sin(a * 3.1) * 0.25 + 0.2, cz + Math.cos(a * 1.3) * 0.8); b.g.rotation.y = a * 1.3; b.w.forEach(function (w) { w[0].rotation.z = w[1] * (0.3 + Math.abs(Math.sin(t * 14 + b.k)) * 1.1); }); });
      var d = t * 0.7; dfly.position.set(0.6 + Math.sin(d) * 1.9, 0.25 + Math.sin(d * 2.3) * 0.12, EN + 3.5 + Math.sin(d * 2) * 1.0); dfly.rotation.y = Math.atan2(Math.cos(d) * 1.9, Math.cos(d * 2) * 2.0);
    });
    [[0.9, 3.2], [0.2, 3.8], [1.1, 3.9]].forEach(function (p, k) { begin('睡蓮葉', p[0], -0.262, EN + p[1], k * 1.3); add(new THREE.CircleGeometry(0.13 + k * 0.02, 12, 0.3, 5.7), M.leafM, 0, 0, 0, -PI / 2, 0, 0); if (k === 1) S(0.04, col(0xf0c6c8, 0.5), 0.02, 0.03, 0, 1, 0.7, 1); });

    /* ============================== more living-room things that move ============================== */
    K.setRoom('客廳'); root();
    // a drawer of the step chest left ajar: push it shut by walking into it
    var drw = begin('半開的抽屜', -1.125, 0.04, -D + 0.6, 0, true); B(0.39, 0.37, 0.3, M.red, 0, 0, 0, 0.01); B(0.39, 0.37, 0.02, M.darker, 0, 0, 0.15, 0.012); add(new THREE.TorusGeometry(0.035, 0.007, 5, 10, PI), M.iron, 0, 0.16, 0.172, PI);
    var dpl = plat(-1.32, -0.93, -D + 0.6, -D + 0.92, 0.42, 0.04);
    K.triggers.push({ kind: 'drawer', g: drw, p: dpl, x: -1.125, z: -D + 0.92, out: 0.22 });
    // roly-poly daruma on the floor (wobbles when bumped)
    K.knockable('不倒翁', 0.95, 0, 1.2, 0.1, function () { L([[0, 0], [0.07, 0], [0.105, 0.08], [0.09, 0.17], [0, 0.2]], col(0xc8452e, 0.4)); S(0.055, M.cream, 0, 0.12, 0.05, 1, 0.9, 0.6); S(0.012, M.black, -0.022, 0.13, 0.085); S(0.012, M.black, 0.022, 0.13, 0.085); }, 'roly');
    var chair = begin('搖椅', 3.55, 0, -2.55, -2.2, true); add(G.tube([[-0.26, 0.09, 0.4], [-0.26, 0.0, 0], [-0.26, 0.09, -0.4]], 0.02, 10, 6), M.dark); add(G.tube([[0.26, 0.09, 0.4], [0.26, 0.0, 0], [0.26, 0.09, -0.4]], 0.02, 10, 6), M.dark);
    B(0.56, 0.06, 0.5, pat.tartan, 0, 0.36, 0.02, 0.03, true); B(0.56, 0.6, 0.06, M.dark, 0, 0.4, -0.24, 0.02, true); [[-0.26, 0.2], [0.26, 0.2], [-0.26, -0.2], [0.26, -0.2]].forEach(function (c) { add(new THREE.CylinderGeometry(0.02, 0.02, 0.34, 6), M.dark, c[0], 0.2, c[1]); }); B(0.06, 0.03, 0.5, M.dark, -0.28, 0.56, 0, 0.01); B(0.06, 0.03, 0.5, M.dark, 0.28, 0.56, 0, 0.01);
    K.triggers.push({ kind: 'rock', g: chair, x: 3.55, z: -2.55, y: 0, a: 0, v: 0, rad: 0.5, axis: 'x' }); plat(3.3, 3.8, -2.8, -2.3, 0.42, 0.3);
    begin('聖誕前的季節擺飾：鏡餅', 2.05, 0.412 + 0.372 * 2, -D + 0.24); S(0.06, M.white, 0, 0.035, 0, 1, 0.6, 1); S(0.045, M.white, 0, 0.085, 0, 1, 0.6, 1); S(0.022, col(0xf29a3a, 0.5), 0, 0.125, 0);

    /* hiding places and dog patrol route for the bots */
    K.spots = [[1.45, -4.35, 0.5, 'loaf', 0.7], [-2.1, -5.0, 0.3, 'sit', 0.53], [-5.1, -3.12, 0.2, 'loaf', 0.86], [-4.82, -2.4, 1.0, 'curl', 0.46], [5.9, -4.6, 0.4, 'curl', 0.21], [3.02, -5.6, 1.57, 'loaf', 0.62], [4.9, -6.3, 0, 'sit', 0.33], [-3.25, -6.02, 0.6, 'loaf', LY + 0.81], [-6.3, -4.6, 1.2, 'curl', LY + 0.24], [-5.0, -6.25, 0, 'side', LY + 0.24], [5.6, EN + 5.7, 2.8, 'loaf', 0.15], [-6.4, EN + 5.3, 0.6, 'sit', -0.3], [6.3, EN + 3.05, 2.9, 'loaf', 0.72], [-4.85, 2.55, 0.3, 'loaf', 0.24]];
    K.route = [[-5.6, 1.3], [-3.6, 1.3], [-2.2, 1.7], [0.4, 2.0], [2.2, 1.9], [3.1, 0.2], [2.9, -2.3], [3.55, -3.0], [3.55, -4.2], [4.6, -4.9], [5.2, -6.6], [3.6, -6.3], [3.55, -4.2], [3.55, -3.0], [1.6, -2.6], [0, -2.8], [0, -4.2], [-1.2, -4.6], [0.3, -5.0], [0, -4.0], [0, -2.8], [-1.2, -2.4], [-3.0, -2.3], [-3.4, -0.4], [-3.6, 1.3], [-5.3, 1.3], [-5.3, -0.4], [-5.25, -2.4], [-5.3, -0.45], [-6.22, -0.45], [-6.22, -3.4], [-6.0, -4.2], [-4.6, -4.8], [-3.6, -5.6], [-5.6, -5.4], [-6.22, -3.7], [-6.22, -0.45], [-5.3, -0.2], [-5.4, 1.3], [-3.6, 1.3], [-1.5, 2.2], [0, 3.3], [0, 4.4], [-1.5, 5.6], [-4.6, 6.6], [-6.2, 7.6], [-2.0, 7.9], [2.6, 7.6], [5.2, 6.9], [4.2, 5.2], [4.2, 4.3], [4.2, 3.3], [1.5, 3.3], [0.5, 2.2]];
  };
})();
