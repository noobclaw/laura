/* 貓躲狗找 — the parts of the property around the main house: east wing (study + bath), the storehouse under the loft,
   and the alley that runs all the way round, so the map has loops. Authored in plan units like the rest (the whole
   property is scaled by SG.WS when the room is finished). Every prop is procedural. */
(function () {
  'use strict';
  var SG = (window.SG = window.SG || {});
  SG.buildAnnex = function (K) {
    var G = SG.geo, P = SG.P, M = K.m, begin = K.begin, add = K.add, B = K.B, C = K.C, L = K.L, S = K.S, plat = K.plat, col = K.col, tx = K.tx, mat = K.mat, cloth = K.cloth, r = K.r, H = K.H, PI = Math.PI;
    function root() { return begin(null, 0, 0, 0); }
    function wall(ax, pos, a0, a1, o) { // wall along x (ax='z') or along z (ax='x'), with its collider
      o = o || {}; var y0 = o.y0 || 0, h = o.h || (H - y0), th = o.th || 0.12, m = o.m || M.plaster, len = a1 - a0, c = (a0 + a1) / 2;
      if (ax === 'x') { add(G.boxM(th, h, len), m, pos, y0 + h / 2, c); if (!y0 && !o.plain) { add(G.boxM(th + 0.03, 0.75, len), M.hinoki, pos, 0.375, c); add(G.boxM(th + 0.05, 0.05, len), M.dark, pos, 0.76, c); } plat(pos - th / 2, pos + th / 2, a0, a1, y0 + h, y0, true); }
      else { add(G.boxM(len, h, th), m, c, y0 + h / 2, pos); if (!y0 && !o.plain) { add(G.boxM(len, 0.75, th + 0.03), M.hinoki, c, 0.375, pos); add(G.boxM(len, 0.05, th + 0.05), M.dark, c, 0.76, pos); } plat(a0, a1, pos - th / 2, pos + th / 2, y0 + h, y0, true); }
    }
    function light(x, y, z, c, i, d) { var l = new THREE.PointLight(c, i, d || 6, 1.7); l.position.set(x, y, z); l.layers.set(1); K.room.add(l); K.lights.push(l); return l; }
    function lamp(x, z) { begin('吸頂燈', x, H - 0.08, z); S(0.16, mat('bulb', null), 0, 0, 0, 1, 0.45, 1); C(0.1, 0.1, 0.03, M.darker, 0, 0.05, 0, 12); light(x, H - 0.5, z, 0xffe6c0, 4.5, 6); }
    function label(key, text, bg, ink) { return mat('lab' + key, { map: SG.tex('lab' + key, function () { return P.label(text, bg || '#f6efdc', ink || '#2a2320'); }), roughness: 0.9 }); }
    /* a box prop with its collider; open = no lid, a cat can sit inside */
    function crate(type, x, y, z, w, h, d, m, open) {
      begin(type, x, y, z);
      if (open) { var t = 0.02; B(w, t, d, m, 0, 0, 0, 0.004, true); B(t, h, d, m, -w / 2 + t / 2, 0, 0, 0.004, true); B(t, h, d, m, w / 2 - t / 2, 0, 0, 0.004, true); B(w, h, t, m, 0, 0, -d / 2 + t / 2, 0.004, true); B(w, h, t, m, 0, 0, d / 2 - t / 2, 0.004, true);
        plat(x - w / 2, x + w / 2, z - d / 2, z + d / 2, y + 0.03, y); plat(x - w / 2, x - w / 2 + 0.03, z - d / 2, z + d / 2, y + h, y); plat(x + w / 2 - 0.03, x + w / 2, z - d / 2, z + d / 2, y + h, y); plat(x - w / 2, x + w / 2, z - d / 2, z - d / 2 + 0.03, y + h, y); plat(x - w / 2, x + w / 2, z + d / 2 - 0.03, z + d / 2, y + h, y); }
      else { B(w, h, d, m, 0, 0, 0, 0.012, true); plat(x - w / 2, x + w / 2, z - d / 2, z + d / 2, y + h, y); }
    }
    var steel = col(0xb9bcc0, 0.35, { metalness: 0.7 }), wood = M.hinoki, dkw = M.dark, tileB = tx('bathTile', function () { return P.ichimatsu('#dfe8ea', '#9fc3cf'); }, 0.3, 0.35), fenceM = tx('fenceW', function () { return P.wood({ base: '#8a6a48', seed: 11, contrast: 0.2, planks: 6 }); }, 1.2, 0.9);
    var cardM = M.card, rubber = col(0x2b2a2c, 0.9), enamel = col(0xf4f1ea, 0.25), blue = col(0x4a86b8, 0.5), redM = col(0xc8452e, 0.5), green = col(0x5d8a57, 0.6), yellow = col(0xe2b53c, 0.5);

    /* ============================== GROUND + FENCE ROUND THE PROPERTY ============================== */
    K.setRoom('後巷'); root();
    add(G.boxM(17.4, 0.06, 11.2), M.gravel, 0, -0.035, -3.1);
    [['z', -8.66, -8.7, 8.7], ['x', -8.66, -8.7, 2.4], ['x', 8.66, -8.7, 2.4], ['z', 2.45, -8.7, -8.0], ['z', 2.45, 8.0, 8.7]].forEach(function (f) { wall(f[0], f[1], f[2], f[3], { h: 1.7, th: 0.08, m: fenceM, plain: true }); });
    for (var i = 0; i < 9; i++) { begin('圍籬柱', -8.6 + i * 2.15, 0, -8.6); B(0.12, 1.8, 0.12, dkw, 0, 0, 0, 0.01, true); }
    // stepping stones along the alleys, bins, crates, pipes: cover on the long straight runs
    [[-7.7, 1.2], [-7.6, 0.2], [-7.75, -0.9], [-7.6, -2.0], [-7.7, -3.1], [-1.0, -7.5], [0.2, -7.4], [1.4, -7.55], [8.3, -6.0], [8.3, -4.9], [8.3, -3.6], [8.3, -1.2], [8.3, 0.4]].forEach(function (s, i) { begin('踏石', s[0], 0, s[1], i * 1.3); C(0.24, 0.26, 0.03, M.stoneM, 0, 0, 0, 9); });
    begin('垃圾桶', -8.15, 0, 1.5); C(0.26, 0.22, 0.62, blue, 0, 0, 0, 16); C(0.28, 0.28, 0.04, col(0x3a6d98, 0.5), 0, 0.62, 0, 16); plat(-8.4, -7.9, 1.25, 1.75, 0.66);
    begin('垃圾桶', -8.15, 0, 0.85); C(0.26, 0.22, 0.62, green, 0, 0, 0, 16); plat(-8.4, -7.9, 0.6, 1.1, 0.62, 0.6); plat(-8.42, -7.88, 0.58, 0.62, 0.62); plat(-8.42, -7.88, 1.08, 1.12, 0.62); // lid off: a cat fits inside
    crate('啤酒箱', -8.2, 0, -1.6, 0.5, 0.32, 0.36, yellow, true); crate('啤酒箱', -8.2, 0.32, -1.6, 0.5, 0.32, 0.36, redM, true); crate('啤酒箱', -8.2, 0, -2.1, 0.5, 0.32, 0.36, redM, true);
    begin('瓦斯桶', -7.05, 0, -3.1); C(0.17, 0.17, 0.7, col(0x9aa3a8, 0.4, { metalness: 0.4 }), 0, 0, 0, 16); S(0.17, col(0x9aa3a8, 0.4, { metalness: 0.4 }), 0, 0.7, 0, 1, 0.6, 1); C(0.05, 0.05, 0.1, redM, 0, 0.8, 0, 8); plat(-7.22, -6.88, -3.27, -2.93, 0.86);
    begin('室外機', 2.0, 0, -6.6); B(0.8, 0.6, 0.32, enamel, 0, 0.05, 0, 0.02, true); C(0.22, 0.22, 0.02, col(0x555a5e, 0.6), 0, 0.13, -0.17, 20).rotation.x = PI / 2; plat(1.6, 2.4, -6.76, -6.44, 0.65);
    begin('排水管', 2.5, 0, -6.3); C(0.05, 0.05, H, col(0x8c8f92, 0.5), 0, 0, 0, 10); plat(2.44, 2.56, -6.36, -6.24, H);
    begin('竹掃把', -6.9, 0, 0.3, 0.4); C(0.012, 0.012, 1.3, M.bam, 0, 0, 0, 6).rotation.z = 0.18; add(new THREE.ConeGeometry(0.12, 0.35, 8), M.bam, -0.04, 0.17, 0);
    begin('盆栽架', 8.25, 0, -7.2); B(0.5, 0.03, 0.9, wood, 0, 0.45, 0, 0.005, true); B(0.5, 0.03, 0.9, wood, 0, 0.9, 0, 0.005, true); [[-0.22, -0.42], [0.22, -0.42], [-0.22, 0.42], [0.22, 0.42]].forEach(function (p) { B(0.04, 0.93, 0.04, dkw, p[0], 0, p[1], 0.004, true); }); plat(8.0, 8.5, -7.65, -6.75, 0.48, 0.45); plat(8.0, 8.5, -7.65, -6.75, 0.93, 0.9);
    for (i = 0; i < 4; i++) { begin('素燒盆', 8.25 + (i % 2 ? 0.1 : -0.1), i < 2 ? 0.48 : 0.93, -7.5 + i * 0.22); L([[0, 0], [0.07, 0], [0.1, 0.14], [0.085, 0.14], [0.06, 0.02], [0, 0.02]], col(0xb8643c, 0.8), 0, 0, 0, 14); if (i % 2) S(0.08, M.leafD, 0, 0.2, 0, 1, 1.1, 1); }
    begin('梯子', 4.9, 0, -8.35, 0); B(0.05, 2.4, 0.04, wood, -0.22, 0, 0, 0.004, true).rotation.x = 0.16; B(0.05, 2.4, 0.04, wood, 0.22, 0, 0, 0.004, true).rotation.x = 0.16; for (i = 0; i < 7; i++) B(0.44, 0.03, 0.03, wood, 0, 0.3 + i * 0.3, 0.05 + i * 0.048, 0.004, true);
    crate('木箱', -7.9, 0, -8.2, 0.7, 0.5, 0.5, fenceM); crate('木箱', -7.2, 0, -8.25, 0.5, 0.36, 0.4, fenceM, true); crate('木箱', -7.85, 0.5, -8.2, 0.5, 0.4, 0.4, wood); // in the wide north-west yard, clear of the narrow passage
    begin('花盆堆', 1.0, 0, -8.3); for (i = 0; i < 4; i++) L([[0, 0], [0.12, 0], [0.16, 0.2], [0.14, 0.2], [0.1, 0.02], [0, 0.02]], col(0xb8643c, 0.8), 0, i * 0.06, 0, 14); plat(0.84, 1.16, -8.46, -8.14, 0.4);
    begin('水桶', 0.3, 0, -8.3); L([[0, 0], [0.13, 0], [0.17, 0.3], [0.155, 0.3], [0.12, 0.02], [0, 0.02]], blue, 0, 0, 0, 16); plat(0.13, 0.47, -8.47, -8.13, 0.03); plat(0.13, 0.16, -8.47, -8.13, 0.3); plat(0.44, 0.47, -8.47, -8.13, 0.3); plat(0.13, 0.47, -8.47, -8.44, 0.3); plat(0.13, 0.47, -8.16, -8.13, 0.3);
    // gate from the garden into the west alley: stone step up from the garden level
    begin('門前石', -7.4, -0.3, 2.78); B(0.9, 0.3, 0.36, M.stoneD, 0, 0, 0, 0.03, true); begin('門前石', -7.4, -0.3, 3.2); B(0.8, 0.15, 0.5, M.stoneM, 0, 0, 0, 0.04, true); plat(-7.8, -7.0, 2.95, 3.45, -0.15, -0.3);
    begin('木門', -7.82, 0, 2.5, -0.5); B(0.8, 1.8, 0.04, fenceM, 0.4, 0, 0, 0.006, true);

    // things standing on the loft floor were given colliders that reach down to the ground: lift their undersides to the loft floor so the space below is free
    K.platforms.forEach(function (p) { if (!p.wall && p.y0 === 0 && p.y1 > 2.72 && p.x0 >= -6.75 && p.x1 <= -2.55 && p.z0 >= -6.55 && p.z1 <= -0.25) p.y0 = 2.7; });
    /* ============================== STOREHOUSE under the loft ============================== */
    K.setRoom('倉庫'); root();
    add(G.boxM(4.2, 0.04, 3.0), col(0x9a968e, 0.95), -4.63, 0.0, -5.06); // concrete slab
    [[-6.6, -6.4], [-2.72, -6.4], [-4.66, -6.4], [-6.6, -3.75]].forEach(function (p) { begin('柱子', p[0], 0, p[1]); B(0.16, 2.7, 0.16, M.darker, 0, 0, 0, 0.012, true); plat(p[0] - 0.08, p[0] + 0.08, p[1] - 0.08, p[1] + 0.08, 2.7); });
    wall('z', -3.68, -5.75, -2.6, { th: 0.06, plain: true, m: fenceM }); // back wall against the house
    begin('鐵架', -2.82, 0, -5.0, 0); // tall steel rack along the kitchen wall: four shelves, a cat fits on each
    [[-0.17, -1.2], [0.17, -1.2], [-0.17, 1.2], [0.17, 1.2], [-0.17, 0], [0.17, 0]].forEach(function (p) { B(0.03, 2.4, 0.03, steel, p[0], 0, p[1], 0.003); });
    [0.12, 0.72, 1.32, 1.92, 2.38].forEach(function (y) { B(0.4, 0.025, 2.46, steel, 0, y, 0, 0.004); plat(-3.02, -2.62, -6.23, -3.77, y + 0.03, y); });
    crate('紙箱', -2.84, 0.15, -5.9, 0.34, 0.3, 0.44, cardM); crate('紙箱', -2.84, 0.75, -4.2, 0.34, 0.34, 0.5, cardM, true); crate('紙箱', -2.84, 1.35, -5.4, 0.34, 0.3, 0.4, cardM); crate('紙箱', -2.84, 1.95, -4.6, 0.34, 0.28, 0.5, cardM, true);
    begin('油漆罐', -2.84, 0.75, -5.5); [[0, 0, 0x4a86b8], [0, 0.22, 0xc8452e], [0.02, -0.24, 0xf4f1ea]].forEach(function (p) { C(0.085, 0.085, 0.2, col(p[2], 0.4), p[0], 0, p[1], 14); C(0.088, 0.088, 0.012, steel, p[0], 0.2, p[1], 14); });
    K.knockable('噴漆罐', -2.86, 1.42, -4.3, 0.035, function () { C(0.03, 0.03, 0.16, yellow, 0, -0.035, 0, 10); C(0.02, 0.02, 0.03, enamel, 0, 0.125, 0, 8); }, 'cyl');
    K.knockable('膠帶', -2.8, 1.375, -4.75, 0.05, function () { add(new THREE.TorusGeometry(0.04, 0.018, 8, 18), col(0xc9a56a, 0.6), 0, 0.018, 0, PI / 2); }, 'cyl');
    begin('輪胎堆', -6.15, 0, -5.9); for (i = 0; i < 3; i++) add(new THREE.TorusGeometry(0.24, 0.1, 10, 22), rubber, 0, 0.1 + i * 0.2, 0, PI / 2); plat(-6.5, -5.8, -6.25, -5.55, 0.6, 0.58); plat(-6.5, -6.38, -6.25, -5.55, 0.6); plat(-5.92, -5.8, -6.25, -5.55, 0.6); plat(-6.5, -5.8, -6.25, -6.13, 0.6); plat(-6.5, -5.8, -5.67, -5.55, 0.6); // hollow middle
    begin('三輪車', -4.9, 0, -5.9, 0.4); add(new THREE.TorusGeometry(0.16, 0.03, 8, 20), rubber, 0, 0.16, 0.3, 0, PI / 2); add(new THREE.TorusGeometry(0.1, 0.025, 8, 16), rubber, -0.18, 0.1, -0.2, 0, PI / 2); add(new THREE.TorusGeometry(0.1, 0.025, 8, 16), rubber, 0.18, 0.1, -0.2, 0, PI / 2); add(G.tube([[0, 0.16, 0.3], [0, 0.42, 0.18], [0, 0.3, -0.2]], 0.02, 10, 6), redM); B(0.2, 0.04, 0.22, redM, 0, 0.3, -0.12, 0.02); add(G.tube([[-0.16, 0.5, 0.16], [0, 0.44, 0.18], [0.16, 0.5, 0.16]], 0.015, 8, 6), steel); plat(-5.15, -4.65, -6.2, -5.6, 0.34, 0.26);
    begin('工作台', -4.4, 0, -4.0); B(1.5, 0.05, 0.6, wood, 0, 0.72, 0, 0.008, true); [[-0.7, -0.25], [0.7, -0.25], [-0.7, 0.25], [0.7, 0.25]].forEach(function (p) { B(0.06, 0.72, 0.06, dkw, p[0], 0, p[1], 0.006, true); }); B(1.4, 0.03, 0.5, wood, 0, 0.2, 0, 0.006, true); plat(-5.15, -3.65, -4.3, -3.7, 0.77, 0.72); plat(-5.1, -3.7, -4.25, -3.75, 0.23, 0.2);
    begin('工具箱', -4.9, 0.77, -4.0, 0.2); B(0.4, 0.16, 0.2, redM, 0, 0, 0, 0.02); B(0.2, 0.02, 0.03, steel, 0, 0.18, 0, 0.008); plat(-5.1, -4.7, -4.1, -3.9, 0.93, 0.77);
    K.knockable('螺絲起子', -4.3, 0.785, -3.95, 0.02, function () { C(0.012, 0.012, 0.09, yellow, 0, 0, 0, 8).rotation.z = PI / 2; C(0.004, 0.004, 0.1, steel, 0.09, 0.008, 0, 6).rotation.z = PI / 2; }, 'cyl');
    K.knockable('捲尺', -4.0, 0.79, -4.1, 0.035, function () { C(0.035, 0.035, 0.03, yellow, 0, -0.015, 0, 14); }, 'cyl');
    begin('洞洞板', -4.4, 1.0, -3.74); B(1.4, 0.8, 0.02, col(0xcdb892, 0.9), 0, 0, 0, 0.004, true); [[-0.5, 0.5, 0.22], [-0.2, 0.55, 0.3], [0.15, 0.45, 0.26], [0.5, 0.5, 0.2]].forEach(function (t, i) { B(0.03, t[2], 0.02, i % 2 ? steel : redM, t[0], t[1] - t[2] / 2, 0.02, 0.004); });
    begin('雪橇', -6.35, 0, -4.2, 0.1); B(0.36, 0.03, 0.9, redM, 0, 0.14, 0, 0.01); B(0.03, 0.14, 0.9, wood, -0.15, 0, 0, 0.01); B(0.03, 0.14, 0.9, wood, 0.15, 0, 0, 0.01); plat(-6.55, -6.15, -4.65, -3.75, 0.18, 0.14);
    crate('紙箱', -5.5, 0, -4.5, 0.6, 0.45, 0.5, cardM, true); crate('紙箱', -3.6, 0, -6.0, 0.5, 0.4, 0.5, cardM); crate('紙箱', -3.6, 0.4, -6.0, 0.4, 0.3, 0.4, cardM, true); crate('收納箱', -3.5, 0, -5.2, 0.5, 0.34, 0.36, col(0x8fb8c9, 0.4, { transparent: false }));
    begin('提燈', -4.66, 2.25, -5.1); C(0.01, 0.01, 0.4, M.darker, 0, 0.05, 0, 6); C(0.09, 0.07, 0.16, mat('bulb', null), 0, -0.12, 0, 12); C(0.11, 0.11, 0.02, M.darker, 0, 0.04, 0, 12); light(-4.66, 2.0, -5.1, 0xffd9a0, 4, 6);
    begin('漁網浮球', -6.5, 1.5, -5.0); S(0.14, col(0x6fb7a8, 0.2), 0, 0, 0); S(0.11, col(0xd9a93a, 0.25), 0.05, -0.26, 0.1); C(0.006, 0.006, 0.7, M.darker, 0, 0.1, 0, 5);

    /* ============================== EAST WING: study + bath ============================== */
    var X0 = 4.62, X1 = 8.0, ZN = -3.5, ZS = 2.3, ZP = -0.55;
    K.setRoom('書房'); root();
    add(G.boxM(X1 - X0, 0.1, ZP - ZN), M.honey, (X0 + X1) / 2, -0.05, (ZN + ZP) / 2);
    wall('x', X1 + 0.06, ZN - 0.12, ZS + 0.3); // east wall
    wall('z', ZN - 0.06, 7.0, 7.15); wall('z', ZN - 0.06, 7.95, X1 + 0.12); wall('z', ZN - 0.06, 7.15, 7.95, { y0: 1.9 }); K.lintel(7.1, 8.0, ZN, 1.84); // north door to the back alley
    wall('z', ZP, X0, 6.0, { th: 0.1 }); wall('z', ZP, 6.9, X1, { th: 0.1 }); wall('z', ZP, 6.0, 6.9, { y0: 1.9, th: 0.1 }); K.lintel(5.95, 6.95, ZP, 1.84);
    add(G.boxM(X1 - X0, 0.1, ZS - ZN), M.ceilW, (X0 + X1) / 2, H + 0.05, (ZN + ZS) / 2); plat(X0, X1, ZN, ZS, H + 0.12, H, true);
    [-2.6, -1.4].forEach(function (z) { begin('橫樑', (X0 + X1) / 2, 2.44, z); B(X1 - X0, 0.16, 0.14, M.darker, 0, 0, 0, 0.012, true); plat(X0, X1, z - 0.07, z + 0.07, 2.6, 2.44); }); // exposed beams to cling to
    lamp(6.3, -2.0);
    begin('書櫃牆', 7.8, 0, -2.0); // floor-to-ceiling shelves with open cubbies
    B(0.34, 2.4, 2.6, wood, 0, 0, 0, 0.01, true); for (i = 0; i < 6; i++) for (var j = 0; j < 4; j++) { if ((i * 3 + j) % 4 === 0) continue; add(G.boxM(0.3, 0.33, 0.58), M.darker, -0.03, 0.22 + i * 0.4, -0.95 + j * 0.64); }
    plat(7.63, 7.97, -3.3, -0.7, 2.4, 2.38); for (i = 0; i < 6; i++) plat(7.63, 7.97, -3.3, -0.7, 0.06 + i * 0.4, 0.02 + i * 0.4); plat(7.94, 7.97, -3.3, -0.7, 2.4); plat(7.63, 7.97, -3.33, -3.3, 2.4); plat(7.63, 7.97, -0.7, -0.67, 2.4);
    for (i = 0; i < 6; i++) for (j = 0; j < 4; j++) { var k2 = (i * 5 + j * 3) % 7; if (k2 < 2) { begin('書', 7.74, 0.06 + i * 0.4, -3.0 + j * 0.64); for (var b = 0; b < 4; b++) B(0.2, 0.24 + ((b * 7 + i) % 3) * 0.03, 0.045, col([0x2f4b7c, 0xc8452e, 0x5d8a57, 0xd9a93a, 0x5e4a7a][(b + i + j) % 5], 0.7), 0, 0, b * 0.05, 0.004); } else if (k2 === 2) { begin('地球儀', 7.74, 0.06 + i * 0.4, -3.0 + j * 0.64 + 0.1); C(0.06, 0.07, 0.02, M.darker, 0, 0, 0, 12); S(0.1, tx('globe', function () { return P.dots('#3f8f8a', '#7a9a54'); }, 0.2, 0.4), 0, 0.14, 0); } else if (k2 === 3) { begin('相框', 7.72, 0.06 + i * 0.4, -3.0 + j * 0.64 + 0.1, -PI / 2); B(0.2, 0.26, 0.02, M.darker, 0, 0, 0, 0.004); add(new THREE.PlaneGeometry(0.15, 0.2), col([0xe7a0a8, 0x9fc3cf, 0xf1e7d2][i % 3], 0.8), 0, 0.13, 0.012); } }
    begin('書桌', 5.5, 0, -3.05); B(1.4, 0.05, 0.62, dkw, 0, 0.72, 0, 0.01, true); B(0.05, 0.72, 0.05, dkw, -0.66, 0, -0.25, 0.006, true); B(0.05, 0.72, 0.05, dkw, -0.66, 0, 0.25, 0.006, true); B(0.42, 0.56, 0.56, dkw, 0.46, 0.16, 0, 0.008, true); // two legs on the door side: you can walk under the desk for (i = 0; i < 3; i++) B(0.36, 0.14, 0.02, wood, 0.46, 0.2 + i * 0.17, 0.28, 0.006, true);
    plat(4.8, 6.2, -3.36, -2.74, 0.77, 0.72); plat(5.75, 6.17, -3.33, -2.77, 0.72, 0.16);
    begin('檯燈', 4.95, 0.77, -3.2); C(0.07, 0.08, 0.02, green, 0, 0, 0, 14); add(G.tube([[0, 0.02, 0], [0, 0.25, 0], [0.1, 0.34, 0.06]], 0.008, 10, 6), M.brass); add(new THREE.ConeGeometry(0.09, 0.1, 14, 1, true), green, 0.12, 0.33, 0.07, 0.5, 0, -0.5); light(5.1, 1.05, -3.1, 0xffdca0, 1.6, 2.5);
    begin('打字機', 5.45, 0.77, -3.05); B(0.34, 0.08, 0.3, col(0x3f6f6a, 0.4), 0, 0, 0, 0.02); B(0.3, 0.05, 0.1, col(0x2a2320, 0.5), 0, 0.08, -0.08, 0.02); C(0.025, 0.025, 0.36, M.darker, 0, 0.14, -0.1, 10).rotation.z = PI / 2; add(new THREE.PlaneGeometry(0.2, 0.16), M.paper, 0, 0.2, -0.12, -0.2); plat(5.28, 5.62, -3.2, -2.9, 0.9, 0.77);
    K.knockable('墨水瓶', 5.85, 0.8, -3.2, 0.03, function () { C(0.03, 0.03, 0.05, col(0x23324f, 0.2), 0, -0.025, 0, 10); C(0.015, 0.015, 0.02, M.darker, 0, 0.025, 0, 8); }, 'cyl');
    K.knockable('紙鎮', 5.95, 0.79, -2.95, 0.035, function () { S(0.035, col(0x9fc3cf, 0.1), 0, 0, 0, 1, 0.7, 1); });
    K.knockable('鉛筆筒', 6.05, 0.82, -3.2, 0.04, function () { C(0.035, 0.035, 0.09, redM, 0, -0.045, 0, 12); for (var q = 0; q < 3; q++) C(0.005, 0.005, 0.13, [yellow, blue, green][q], q * 0.015 - 0.015, -0.02, 0.01, 6); }, 'cyl');
    begin('旋轉椅', 5.4, 0, -2.4, 2.8); C(0.2, 0.2, 0.05, cloth.indigo, 0, 0.42, 0, 18); C(0.02, 0.02, 0.4, steel, 0, 0.02, 0, 8); for (i = 0; i < 5; i++) { var a = i * PI * 0.4; B(0.24, 0.025, 0.04, steel, Math.cos(a) * 0.12, 0, Math.sin(a) * 0.12, 0.008).rotation.y = -a; } B(0.36, 0.34, 0.04, cloth.indigo, 0, 0.56, -0.19, 0.03); plat(5.2, 5.6, -2.6, -2.2, 0.47, 0.42);
    begin('字紙簍', 6.5, 0, -3.15); L([[0, 0], [0.12, 0], [0.16, 0.3], [0.15, 0.3], [0.11, 0.02], [0, 0.02]], tx('basket', null, 0.08), 0, 0, 0, 14); plat(6.34, 6.66, -3.31, -2.99, 0.03); plat(6.34, 6.37, -3.31, -2.99, 0.3); plat(6.63, 6.66, -3.31, -2.99, 0.3); plat(6.34, 6.66, -3.31, -3.28, 0.3); plat(6.34, 6.66, -3.02, -2.99, 0.3);
    K.knockable('紙團', 6.75, 0.03, -2.85, 0.035, function () { S(0.035, M.paper, 0, 0, 0, 1, 0.9, 1.1); }); K.knockable('紙團', 6.2, 0.03, -2.6, 0.03, function () { S(0.03, M.paper, 0, 0, 0, 1.1, 0.9, 1); });
    begin('沙發床', 5.3, 0, -1.05, PI); B(1.3, 0.2, 0.62, cloth.kikko, 0, 0.24, 0, 0.06, true); B(1.3, 0.4, 0.14, cloth.kikko, 0, 0.3, -0.28, 0.05, true); [[-0.6, -0.26], [0.6, -0.26], [-0.6, 0.26], [0.6, 0.26]].forEach(function (p) { C(0.025, 0.02, 0.24, dkw, p[0], 0, p[1], 8); }); plat(4.65, 5.95, -1.36, -0.74, 0.44, 0.24); plat(4.65, 5.95, -0.86, -0.7, 0.72, 0.44); // a cat passes underneath
    begin('靠枕', 4.9, 0.44, -1.05, 0.3); B(0.34, 0.12, 0.34, cloth.mustard, 0, 0, 0, 0.05, true); begin('靠枕', 5.7, 0.44, -1.1, -0.2); B(0.32, 0.12, 0.32, cloth.sakura, 0, 0, 0, 0.05, true);
    begin('地毯', 6.3, 0, -2.0, 0.1); add(G.boxM(1.7, 0.012, 1.2), tx('studyRug', function () { return P.rug(); }, 1.7, 0.95), 0, 0.008, 0);
    begin('落地燈', 7.3, 0, -0.85); C(0.14, 0.15, 0.03, M.darker, 0, 0, 0, 14); C(0.012, 0.012, 1.5, M.brass, 0, 0.03, 0, 8); L([[0.1, 0], [0.18, 0.26]], M.washi, 0, 1.4, 0, 16); light(7.3, 1.5, -0.85, 0xffd9a0, 2.4, 3.5); plat(7.16, 7.44, -0.99, -0.71, 0.04);
    begin('掛軸', 4.7, 1.2, -1.9, PI / 2); add(new THREE.PlaneGeometry(0.5, 1.1), tx('scrollYume', function () { var c = P.washi('#f3e8d0', 77); SG.inkText(c.getContext('2d'), '夢', 128, 128, 170, '#1d1a1a', false, 12); return c; }, null, 0.9), 0, 0.2, 0.01); C(0.018, 0.018, 0.56, M.darker, 0, -0.36, 0.012, 8).rotation.z = PI / 2;
    crate('紙箱', 7.0, 0, -3.1, 0.5, 0.4, 0.44, cardM, true);
    begin('窗', 8.0, 1.5, -2.0, -PI / 2); add(new THREE.PlaneGeometry(1.2, 0.9), mat('winGlow', null), 0, 0.35, 0.005);

    K.setRoom('浴室'); root();
    add(G.boxM(X1 - X0, 0.1, ZS - ZP), tileB, (X0 + X1) / 2, -0.05, (ZP + ZS) / 2);
    lamp(6.3, 0.9);
    begin('檜木浴缸', 7.2, 0, 1.5); // hollow tub: a cat can sit in it, a dog has to look over the rim
    [[0, -0.42, 1.4, 0.06], [0, 0.42, 1.4, 0.06], [-0.67, 0, 0.06, 0.84], [0.67, 0, 0.06, 0.84]].forEach(function (s) { B(s[2], 0.6, s[3], wood, s[0], 0, s[1], 0.012, true); }); B(1.3, 0.05, 0.8, wood, 0, 0, 0, 0.01, true); add(new THREE.PlaneGeometry(1.28, 0.78), col(0x8fd0d8, 0.08, { transparent: true, opacity: 0.55 }), 0, 0.3, 0, -PI / 2);
    plat(6.5, 7.9, 1.05, 1.11, 0.6); plat(6.5, 7.9, 1.89, 1.95, 0.6); plat(6.5, 6.56, 1.05, 1.95, 0.6); plat(7.84, 7.9, 1.05, 1.95, 0.6); plat(6.5, 7.9, 1.05, 1.95, 0.06);
    begin('浴缸蓋', 6.9, 0.6, 1.5); B(0.6, 0.03, 0.86, wood, 0, 0, 0, 0.008, true); plat(6.6, 7.2, 1.07, 1.93, 0.64, 0.6);
    begin('風呂椅', 6.1, 0, 1.7); B(0.3, 0.03, 0.22, wood, 0, 0.2, 0, 0.008, true); B(0.03, 0.2, 0.2, wood, -0.12, 0, 0, 0.006); B(0.03, 0.2, 0.2, wood, 0.12, 0, 0, 0.006); plat(5.95, 6.25, 1.59, 1.81, 0.23, 0.2);
    K.knockable('風呂桶', 5.7, 0.07, 1.85, 0.11, function () { L([[0, -0.07], [0.09, -0.07], [0.11, 0.05], [0.1, 0.05], [0.085, -0.055], [0, -0.055]], wood, 0, 0, 0, 16); }, 'cyl');
    K.knockable('小鴨', 7.4, 0.36, 1.4, 0.05, function () { S(0.05, yellow, 0, 0, 0, 1, 0.8, 1.2); S(0.032, yellow, 0, 0.05, 0.04); add(new THREE.ConeGeometry(0.012, 0.03, 6), col(0xf29a3a, 0.5), 0, 0.045, 0.08, PI / 2); });
    K.knockable('洗髮精', 6.35, 0.1, 2.1, 0.035, function () { C(0.032, 0.035, 0.16, col(0xe7a0a8, 0.3), 0, -0.08, 0, 12); C(0.012, 0.012, 0.04, enamel, 0, 0.08, 0, 8); }, 'cyl');
    K.knockable('肥皂', 6.6, 0.03, 2.05, 0.03, function () { B(0.07, 0.025, 0.045, col(0xf1e7d2, 0.3), 0, -0.012, 0, 0.012); });
    begin('洗手台', 4.95, 0, 0.3, PI / 2); B(0.9, 0.7, 0.46, enamel, 0, 0.1, 0, 0.02, true); B(0.94, 0.05, 0.5, col(0xd8d6d0, 0.2), 0, 0.8, 0, 0.012, true); S(0.17, enamel, 0, 0.82, 0.02, 1, 0.25, 0.8); add(G.tube([[0, 0.85, -0.18], [0, 1.0, -0.18], [0, 1.02, -0.08]], 0.012, 10, 6), steel); plat(4.7, 5.2, -0.15, 0.75, 0.85, 0.1);
    begin('鏡子', 4.69, 1.35, 0.3, PI / 2); B(0.7, 0.8, 0.03, wood, 0, 0, 0, 0.01, true); add(new THREE.PlaneGeometry(0.62, 0.72), col(0xcfe3ea, 0.05, { metalness: 0.9 }), 0, 0.4, 0.017);
    K.knockable('漱口杯', 4.95, 0.9, 0.0, 0.03, function () { C(0.03, 0.025, 0.08, blue, 0, -0.04, 0, 10); C(0.004, 0.004, 0.12, redM, 0.01, -0.02, 0, 5).rotation.z = 0.3; }, 'cyl');
    begin('毛巾架', 7.85, 0, 0.2, -PI / 2); for (i = 0; i < 4; i++) { B(0.8, 0.02, 0.3, wood, 0, 0.3 + i * 0.45, 0, 0.005, true); } B(0.03, 1.7, 0.3, wood, -0.4, 0, 0, 0.005, true); B(0.03, 1.7, 0.3, wood, 0.4, 0, 0, 0.005, true); for (i = 0; i < 4; i++) plat(7.68, 7.98, -0.2, 0.6, 0.33 + i * 0.45, 0.3 + i * 0.45);
    [[0.32, 'stripe'], [0.77, 'sakura'], [1.22, 'indigo']].forEach(function (t, q) { begin('毛巾疊', 7.83, t[0] + 0.01, 0.05 + q * 0.14); B(0.24, 0.1, 0.3, cloth[t[1]] || cloth.indigo, 0, 0, 0, 0.03, true); });
    begin('洗衣籃', 5.1, 0, 1.25); L([[0, 0], [0.2, 0], [0.26, 0.4], [0.245, 0.4], [0.19, 0.02], [0, 0.02]], tx('basket', null, 0.08), 0, 0, 0, 16); plat(4.84, 5.36, 0.99, 1.51, 0.03); plat(4.84, 4.87, 0.99, 1.51, 0.4); plat(5.33, 5.36, 0.99, 1.51, 0.4); plat(4.84, 5.36, 0.99, 1.02, 0.4); plat(4.84, 5.36, 1.48, 1.51, 0.4);
    begin('腳踏墊', 5.45, 0, 1.95); add(G.boxM(0.7, 0.014, 0.45), cloth.mustard, 0, 0.008, 0);
    begin('體重計', 6.0, 0, 0.0, 0.2); B(0.3, 0.04, 0.3, enamel, 0, 0, 0, 0.015); C(0.07, 0.07, 0.008, col(0x2a2320, 0.4), 0, 0.04, 0.06, 16); plat(5.85, 6.15, -0.15, 0.15, 0.045);
    begin('晾衣桿', 6.3, 2.05, 0.3); C(0.015, 0.015, 3.3, steel, 0, 0, 0, 8).rotation.z = PI / 2; plat(X0, X1, 0.27, 0.33, 2.07, 2.03); [[-0.9, 'stripe'], [-0.2, 'sakura'], [0.7, 'kikko']].forEach(function (t) { add(new THREE.PlaneGeometry(0.4, 0.7), cloth[t[1]] || cloth.indigo, t[0], -0.33, 0).material.side = THREE.DoubleSide; });
    begin('窗', 8.0, 1.6, 1.4, -PI / 2); add(new THREE.PlaneGeometry(0.9, 0.6), mat('winGlow', null), 0, 0.2, 0.005);
    begin('暖簾', 6.45, 1.55, ZP + 0.07); add(new THREE.PlaneGeometry(0.86, 0.36), tx('norenYu', function () { return P.noren('ゆ', false); }, null, 0.9, { side: THREE.DoubleSide }), 0, 0.14, 0);


    /* ============================== COLOUR PASS: things a cat can become ==============================
       Owner's direction (2026-11-25): colour is gameplay. Every area gets many distinct hues in cat-sized patches
       (crates, tins, cushions, buckets, cloth) next to big multi-colour surfaces (painted fence, laundry, posters). */
    var HUES = [0xc8452e, 0xe8782a, 0xe2b53c, 0xf2d24a, 0xa8c64a, 0x5d8a57, 0x2e7a5a, 0x3f8f8a, 0x4aa3e0, 0x2f4b7c, 0x5e4a7a, 0x9a6bb0, 0xe7a0a8, 0xd8507a, 0x8a5a3a, 0xc9a56a, 0xf1e7d2, 0x8c9296, 0x3a3a40, 0x6fb7a8, 0xf29a4a, 0x7a9a54];
    function hue(i, rough) { return col(HUES[((i % HUES.length) + HUES.length) % HUES.length], rough == null ? 0.6 : rough); }
    function hx(c) { return '#' + ('000000' + c.toString(16)).slice(-6); } function dk(c, k) { return ((Math.round(((c >> 16) & 255) * k) << 16) | (Math.round(((c >> 8) & 255) * k) << 8) | Math.round((c & 255) * k)); }
    function hueW(i) { var c = [0xc8452e, 0x3f8f8a, 0xe2b53c][((i % 3) + 3) % 3]; // three painted-wood colours (each textured material is its own draw call)
      return tx('pw' + c, function () { return P.wood({ base: hx(c), seed: c % 23, contrast: 0.16, planks: 3 }); }, 0.9, 0.82); } // painted wood: the grain shows through, edges read as planks
    function tin(x, y, z, i, s) { s = s || 1; begin('罐頭', x, y, z); C(0.07 * s, 0.07 * s, 0.16 * s, hue(i, 0.35), 0, 0, 0, 14); C(0.072 * s, 0.072 * s, 0.07 * s, hue(i + 7, 0.6), 0, 0.045 * s, 0, 14); C(0.073 * s, 0.073 * s, 0.012 * s, steel, 0, 0.16 * s, 0, 14); }
    function bigCrate(x, y, z, w, h, d, i, open) { crate('彩色木箱', x, y, z, w, h, d, hueW(i), open); }
    function poster(x, y, z, ry, i, w, h) { begin('海報', x, y, z, ry); add(G.boxM(w || 0.6, h || 0.8, 0.012), hue(i, 0.8), 0, 0, 0); add(G.boxM((w || 0.6) * 0.7, (h || 0.8) * 0.28, 0.014), hue(i + 9, 0.8), 0, (h || 0.8) * 0.2, 0.002); add(new THREE.CircleGeometry((w || 0.6) * 0.2, 18), hue(i + 4, 0.8), 0, -(h || 0.8) * 0.16, 0.009); }
    K.setRoom('後巷'); root();
    // west alley: a painted fence (one big multi-colour surface) and a market-stall stack of crates
    for (i = 0; i < 9; i++) { add(G.boxM(0.02, 1.3, 0.62), hueW(i * 5 + 1), -8.6, 0.72, -3.2 + i * 0.64); }
    [[-8.25, 0, -0.6, 0.45, 0.4, 0.45, 3, 1], [-8.25, 0.4, -0.6, 0.4, 0.34, 0.4, 9, 0], [-8.25, 0, -0.1, 0.42, 0.36, 0.42, 13, 0], [-7.0, 0, -1.2, 0.5, 0.3, 0.4, 5, 1], [-7.0, 0, -2.3, 0.44, 0.44, 0.44, 10, 0], [-7.0, 0.44, -2.3, 0.36, 0.3, 0.36, 1, 1], [-8.2, 0, -4.3, 0.5, 0.36, 0.5, 20, 0]].forEach(function (c) { bigCrate(c[0], c[1], c[2], c[3], c[4], c[5], c[6], c[7]); });
    for (i = 0; i < 6; i++) tin(-6.98 + (i % 2) * 0.16, 0.3, -1.3 + Math.floor(i / 2) * 0.17 - 0.07, i * 3, 0.9);
    poster(-6.87, 1.3, -1.0, PI / 2 + PI, 2); poster(-6.87, 1.25, 0.9, PI / 2 + PI, 11, 0.7, 0.5); poster(-6.87, 1.4, -2.4, PI / 2 + PI, 15, 0.5, 0.7);
    // north alley: a laundry line (big patterned cloths) and a row of buckets, pots and cushions
    begin('曬衣繩', 0, 1.75, -7.9); C(0.008, 0.008, 9.5, M.darker, 0.2, 0, 0, 5).rotation.z = PI / 2; [-4.6, 5.0].forEach(function (x) { B(0.07, 1.8, 0.07, wood, x, -1.75, 0, 0.008, true); plat(x - 0.04, x + 0.04, -7.94, -7.86, 1.8); });
    ['stripe', 'sakura', 'indigo', 'kikko', 'mustard'].concat(Object.keys(K.pat || {})).slice(0, 11).forEach(function (n, q) { var m = cloth[n] || (K.pat && K.pat[n]) || cloth.indigo, w = 0.5 + (q % 3) * 0.14, hh = 0.7 + (q % 2) * 0.3, o = add(G.boxM(w, hh, 0.012), m, -4.0 + q * 0.82, -hh / 2 - 0.01, 0); o.material.side = THREE.DoubleSide; });
    for (i = 0; i < 9; i++) { var bx = -1.9 + i * 0.52; begin('彩色水桶', bx, 0, -6.55 - (i % 2) * 0.12); L([[0, 0], [0.12, 0], [0.16, 0.28], [0.148, 0.28], [0.11, 0.02], [0, 0.02]], hue(i * 7 + 2, 0.45), 0, 0, 0, 14); plat(bx - 0.15, bx + 0.15, -6.7 - (i % 2) * 0.12, -6.4 - (i % 2) * 0.12, 0.03); }
    for (i = 0; i < 6; i++) { begin('戶外坐墊', -6.0 + i * 0.5, 0, -8.25, i * 0.4); B(0.42, 0.1, 0.42, hue(i * 4 + 12, 0.9), 0, 0, 0, 0.04, true); }
    poster(0.6, 1.3, -6.28, PI, 6, 0.9, 0.6); poster(-1.2, 1.35, -6.28, PI, 17, 0.5, 0.7); poster(4.4, 1.3, -7.68, PI, 8, 0.8, 0.8); poster(6.2, 1.2, -7.68, PI, 19, 0.6, 0.5);
    // east alley: a shelf of tins like a little shop, crates in a row
    begin('罐頭架', 8.42, 0, -5.4, -PI / 2); for (i = 0; i < 4; i++) B(1.6, 0.03, 0.3, wood, 0, 0.3 + i * 0.4, 0, 0.005, true); B(0.04, 1.6, 0.3, dkw, -0.8, 0, 0, 0.005, true); B(0.04, 1.6, 0.3, dkw, 0.8, 0, 0, 0.005, true); for (i = 0; i < 4; i++) plat(8.27, 8.57, -6.2, -4.6, 0.33 + i * 0.4, 0.3 + i * 0.4);
    for (i = 0; i < 24; i++) tin(8.42, 0.33 + Math.floor(i / 8) * 0.4, -6.1 + (i % 8) * 0.2, i * 5 + Math.floor(i / 8), 0.95);
    [[8.3, 0, -2.6, 0.4, 0.34, 0.5, 6, 0], [8.3, 0.34, -2.6, 0.36, 0.28, 0.4, 14, 1], [8.3, 0, -1.9, 0.4, 0.4, 0.4, 0, 0], [8.3, 0, 1.2, 0.42, 0.36, 0.5, 11, 1], [8.3, 0, 1.8, 0.4, 0.3, 0.4, 18, 0], [8.3, 0.3, 1.8, 0.34, 0.26, 0.34, 4, 0]].forEach(function (c) { bigCrate(c[0], c[1], c[2], c[3], c[4], c[5], c[6], c[7]); });
    for (i = 0; i < 7; i++) add(G.boxM(0.02, 1.25, 0.6), hueW(i * 3 + 8), 8.6, 0.7, -3.4 + i * 0.63);
    // storehouse and garden: more cat-sized colour
    K.setRoom('倉庫'); root();
    [[-5.4, 0, -6.1, 0.44, 0.4, 0.44, 8, 1], [-4.2, 0, -6.15, 0.4, 0.3, 0.4, 16, 0], [-4.2, 0.3, -6.15, 0.34, 0.3, 0.34, 12, 0]].forEach(function (c) { bigCrate(c[0], c[1], c[2], c[3], c[4], c[5], c[6], c[7]); });
    for (i = 0; i < 8; i++) tin(-2.84, 1.35, -6.1 + i * 0.17 + (i > 3 ? 1.2 : 0), i * 4 + 1, 0.9);
    poster(-4.4, 1.55, -3.72, PI, 13, 0.7, 0.5);
    K.setRoom('庭院'); root();
    for (i = 0; i < 10; i++) { var gx = [-7.2, -6.3, -3.4, -2.2, 2.4, 3.6, 6.8, 7.3, -5.0, 5.6][i], gz = [4.3, 8.1, 8.3, 4.6, 8.2, 4.7, 4.5, 6.4, 5.4, 8.2][i]; if (i % 2) { begin('彩色花盆', gx, -0.3, gz); L([[0, 0], [0.13, 0], [0.19, 0.26], [0.17, 0.26], [0.12, 0.02], [0, 0.02]], hue(i * 6 + 3, 0.5), 0, 0, 0, 14); S(0.15, i % 4 === 1 ? M.leafM : M.leafD, 0, 0.36, 0, 1, 0.9, 1); plat(gx - 0.18, gx + 0.18, gz - 0.18, gz + 0.18, -0.04, -0.3); } else { begin('戶外坐墊', gx, -0.3, gz, i); B(0.45, 0.12, 0.45, hue(i * 6 + 9, 0.9), 0, 0, 0, 0.05, true); plat(gx - 0.22, gx + 0.22, gz - 0.22, gz + 0.22, -0.18, -0.3); } }
    for (i = 0; i < 8; i++) add(G.boxM(0.6, 0.9, 0.02), hueW(i * 4 + 5), -6.6 + i * 1.9, 0.35, 8.68);


    // ground-level colour: painted paving tiles along the alleys, mats and tubs in the bath, tarps and buckets in the storehouse
    function tile(x, z, i, w, d) { add(G.boxM(w || 0.46, 0.016, d || 0.46), hue(i, 0.85), x, 0.008, z); }
    K.setRoom('後巷'); root();
    for (i = 0; i < 11; i++) tile(-7.72 + (i % 2) * 0.5, 1.9 - i * 0.5, i * 7 + 3); for (i = 0; i < 20; i++) tile(-1.6 + i * 0.5, -7.25 - (i % 2) * 0.5, i * 5 + 1); for (i = 0; i < 18; i++) tile(8.3, -8.2 + i * 0.56, i * 9 + 4, 0.4, 0.4);
    K.setRoom('浴室'); root();
    [[6.9, 0.55, 2, 0.7, 0.45], [5.6, 0.45, 13, 0.6, 0.4], [5.2, -0.2, 20, 0.5, 0.5], [6.3, 2.0, 8, 0.5, 0.36], [5.0, 2.05, 16, 0.4, 0.3]].forEach(function (m) { begin('浴墊', m[0], 0, m[1]); add(G.boxM(m[3], 0.02, m[4]), hue(m[2], 0.95), 0, 0.01, 0); });
    [[7.35, 0.75, 0], [7.35, 0.75, 5], [7.35, 0.75, 9], [7.3, -0.25, 14], [7.3, -0.25, 3]].forEach(function (b, q) { begin('塑膠臉盆', b[0], (q === 1 ? 0.07 : q === 2 ? 0.14 : q === 4 ? 0.07 : 0), b[1]); L([[0, 0], [0.16, 0], [0.21, 0.1], [0.195, 0.1], [0.15, 0.015], [0, 0.015]], hue(b[2], 0.35), 0, 0, 0, 16); });
    plat(7.14, 7.56, 0.54, 0.96, 0.24); plat(7.09, 7.51, -0.46, -0.04, 0.17);
    for (i = 0; i < 6; i++) { begin('沐浴瓶', 6.62 + i * 0.11, 0.6, 1.08); C(0.035, 0.04, 0.17, hue(i * 4 + 6, 0.3), 0, 0, 0, 10); C(0.014, 0.014, 0.04, enamel, 0, 0.17, 0, 6); }
    K.setRoom('倉庫'); root();
    [[-5.0, -5.2, 9, 1.1, 0.8], [-3.7, -4.6, 1, 0.8, 0.6], [-6.0, -3.95, 15, 0.7, 0.5]].forEach(function (m) { begin('防水布', m[0], 0, m[1], m[2]); add(G.boxM(m[3], 0.02, m[4]), hue(m[2], 0.7), 0, 0.012, 0); });
    for (i = 0; i < 5; i++) { var sx = -3.3 - i * 0.42; begin('彩色水桶', sx, 0, -4.1); L([[0, 0], [0.12, 0], [0.16, 0.28], [0.148, 0.28], [0.11, 0.02], [0, 0.02]], hue(i * 5 + 4, 0.45), 0, 0, 0, 14); plat(sx - 0.15, sx + 0.15, -4.25, -3.95, 0.03); }

    /* where bots like to hide: [x, z, yaw, pose, surfaceY]; and the extra patrol legs (appended to the house tour) */
    K.spots = (K.spots || []).concat([[7.74, -2.36, -1.57, 'loaf', 1.26], [7.74, -1.08, -1.57, 'sit', 0.46], [5.3, -1.2, 0.2, 'side', 0.0], [6.5, -3.15, 0.5, 'curl', 0.03], [7.0, -3.1, 0, 'loaf', 0.03], [7.4, 1.5, 1.2, 'sit', 0.06], [5.1, 1.25, 0, 'curl', 0.03], [7.83, 0.35, -1.57, 'loaf', 1.68],
      [-2.84, -5.0, 1.57, 'loaf', 1.95], [-6.15, -5.9, 0.3, 'curl', 0.0], [-5.5, -4.5, 0.4, 'loaf', 0.03], [-4.4, -4.0, 0.2, 'sphinx', 0.23], [-8.15, 0.85, 0.2, 'sit', 0.0], [-7.2, -8.25, 0.3, 'loaf', 0.03], [0.3, -8.3, 0, 'sit', 0.03], [8.25, -7.2, -1.2, 'loaf', 0.48], [-8.25, -0.6, 0.4, 'loaf', 0.74], [-7.0, -1.2, 0, 'curl', 0.03], [8.3, -1.9, -1.2, 'loaf', 0.4], [8.3, 1.2, 0, 'curl', 0.03], [8.42, -5.0, -1.57, 'loaf', 1.13], [-5.4, -6.1, 0.4, 'sit', 0.03], [-4.2, -6.15, 0, 'loaf', 0.6]]);
    K.route = (K.route || []).concat([[3.1, 0.2], [2.9, -2.3], [3.55, -3.05], [4.95, -3.05], [6.2, -2.3], [6.45, -0.55], [5.65, 0.9], [5.45, 2.0], [5.45, 3.2], [4.2, 3.3], [1.5, 3.3], [0, 3.3], [0, 4.4], [-1.5, 5.6], [-4.6, 6.6], [-6.2, 7.6], [-7.4, 5.5], [-7.4, 3.2], [-7.4, 2.0], [-7.6, -2.0], [-7.6, -5.0], [-4.6, -5.0], [-3.9, -7.4], [0, -7.3], [2.0, -8.1], [7.85, -8.15], [7.9, -4.2], [7.55, -3.0], [6.2, -2.6], [4.95, -3.05], [3.55, -3.05], [1.6, -2.6], [0, -2.8], [-1.2, -2.4], [-3.0, -2.3], [-3.4, -0.4], [-3.6, 1.3]]);
  };
})();
