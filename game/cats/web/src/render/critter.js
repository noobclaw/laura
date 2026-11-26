/* 貓躲狗找 — the animals.
   Cats (the hiders) are a blank canvas: ONE continuous smooth skin (rounded-slab torso that runs straight into a
   plain head, short thick legs, thin ears, a tail), smooth-skinned to a small skeleton, with two built-in shape
   targets ("log": head drawn into the body line, "ball") so a pose can become a really simple shape. Everything on
   the body is in the paint atlas; there are no dark features.
   Dogs keep their older look (lathe parts on rigid bones) but go through the same mesh / atlas / paint pipeline. */
(function () {
  'use strict';
  var SG = (window.SG = window.SG || {});
  var D2R = Math.PI / 180, PI = Math.PI;
  function lerp(a, b, t) { return a + (b - a) * t; }
  function clamp(x, a, b) { return x < a ? a : x > b ? b : x; }
  function sstep(a, b, x) { x = clamp((x - a) / (b - a), 0, 1); return x * x * (3 - 2 * x); }
  function spow(v, e) { return v < 0 ? -Math.pow(-v, e) : Math.pow(v, e); }
  function capf(t, m) { t = clamp(t, 0, 1); return Math.pow(Math.max(0, 1 - Math.pow(t, m)), 1 / m); } // superellipse end profile

  /* ---------- lathe profiles (dogs): v in [0,1] -> [radius, y] ---------- */
  function ell(R, H) { return function (v) { var a = PI * v; return [R * Math.sin(a), -H * Math.cos(a)]; }; }
  function cap(L, r0, r1) {
    return function (v) {
      var a;
      if (v < 0.22) { a = v / 0.22 * PI / 2; return [r1 * Math.sin(a), -L - r1 * Math.cos(a)]; }
      if (v > 0.78) { a = (v - 0.78) / 0.22 * PI / 2; return [r0 * Math.cos(a), r0 * Math.sin(a)]; }
      var s = (v - 0.22) / 0.56; return [r1 + (r0 - r1) * s, -L * (1 - s)];
    };
  }
  function cone(h, w, pw) { return function (v) { return [w * Math.pow(1 - v, pw || 0.8) + 0.002 * (1 - v), h * (0.12 * v + 0.88 * v * v * (3 - 2 * v) * 0.5 + 0.44 * v)]; }; }

  /* ---------- builds ----------
     cats: len = torso length, hw/hh = torso half width / half height, sq = cross-section squareness (2 = ellipse, 4 = rounded
     slab, 9 = block), leg = visible leg length, headW/H/D = head half sizes, headUp = head centre above the spine.
     Shoulder height at scale 1 = leg + 2 * hh. bellyR/headR/chestR/hipR are kept for game.js (collision radius) and makeSpec. */
  /* cats are flat, ground-hugging mats with a cat's outline: len/hw/hh = slab length, half width, half thickness; plan = how round the
     corners are seen from above; stub = length of the four little legs; headW/H/D = the low head bump at the front. `leg` is only the
     jump class game.js reads (< 0.1 = low jumper). Top of the back when standing = stub + 2 * hh. */
  var TAB = { len: 0.07, r0: 0.045, r1: 0.036, up: 90, curl: 0, flat: 0.3, y: 0 }; // default tail: a short flat tab at the rear, in the plane of the body
  function tab(k) { return { len: TAB.len * k, r0: TAB.r0 * k, r1: TAB.r1 * k, up: 90, curl: 0, flat: 0.3, y: 0 }; }
  /* jelly figures (owner 2026-11-25, concept JARM/JSIZE): a soft white "dango" — a round body with a round head on it, two small ears,
     two short arms, two stubby feet, no tail. Rb/Rh = body / head radius, hc = head centre above the body centre, neck = how soft the
     waist between them is. Standing height at size 1 is about 0.9 m (owner: not too small, or hiding gets too easy).
     bellyR/headR/leg are kept for game.js (collision radius, jump class). */
  var JT = { len: 0.05, r0: 0.02, r1: 0.016, up: 90, curl: 0, none: true, y: 0 };
  var CATS = {
    mochi: { name: '糰子', tag: '圓頭', kind: 'cat', jelly: true, Rb: 0.245, Rh: 0.178, hc: 0.394, neck: 0.075, depth: 0.5, wide: 1.14, tall: 1.14, arm: 0.26, armR: 0.0696, foot: 0.087, ear: { type: 'point', h: 0.1, w: 0.052, spread: 0.55, tilt: 18 }, tail: JT, coat: 'jcat' },
    daifuku: { name: '大福', tag: '矮胖', kind: 'cat', jelly: true, Rb: 0.27, Rh: 0.19, hc: 0.334, neck: 0.11, depth: 0.5, wide: 1.14, tall: 1.14, arm: 0.247, armR: 0.0754, foot: 0.0928, ear: { type: 'round', h: 0.075, w: 0.056, spread: 0.56, tilt: 22 }, tail: JT, coat: 'jcat' },
    azuki: { name: '小豆', tag: '小隻', kind: 'cat', jelly: true, scale: 0.82, Rb: 0.245, Rh: 0.185, hc: 0.404, neck: 0.075, depth: 0.5, wide: 1.14, tall: 1.14, arm: 0.247, armR: 0.0696, foot: 0.087, ear: { type: 'point', h: 0.11, w: 0.054, spread: 0.55, tilt: 16 }, tail: JT, coat: 'jcat' }
  };
  Object.keys(CATS).forEach(function (k) { var c = CATS[k]; c.bellyR = c.chestR = c.hipR = c.Rb; c.headR = c.headW = c.Rh; c.leg = 0.18; c.len = 2 * c.Rb; });
  /* hunters: the same jelly figure with floppy ears, a snout, dark eyes and the toy paint blaster held in front */
  var DOGS = {
    shiba: { name: '小柴', tag: '柴色', kind: 'dog', jelly: true, Rb: 0.255, Rh: 0.185, hc: 0.404, neck: 0.075, depth: 0.5, wide: 1.14, tall: 1.14, arm: 0.247, armR: 0.0696, foot: 0.0928, snout: 0.075, ear: { type: 'flop', h: 0.13, w: 0.06, spread: 0.95, tilt: 168 }, tail: JT, eye: 0.02, coat: 'jshiba' },
    corgi: { name: '短短', tag: '橘白', kind: 'dog', jelly: true, Rb: 0.27, Rh: 0.18, hc: 0.364, neck: 0.09, depth: 0.5, wide: 1.14, tall: 1.14, arm: 0.234, armR: 0.0725, foot: 0.0957, snout: 0.07, ear: { type: 'point', h: 0.11, w: 0.06, spread: 0.62, tilt: 20 }, tail: JT, eye: 0.02, coat: 'jcorgi' },
    husky: { name: '阿雪', tag: '灰白', kind: 'dog', jelly: true, Rb: 0.255, Rh: 0.185, hc: 0.404, neck: 0.075, depth: 0.5, wide: 1.14, tall: 1.14, arm: 0.247, armR: 0.0696, foot: 0.0928, snout: 0.08, ear: { type: 'point', h: 0.1, w: 0.056, spread: 0.6, tilt: 16 }, tail: JT, eye: 0.02, eyeColor: 0x6fb7e8, coat: 'jhusky' }
  };
  Object.keys(DOGS).forEach(function (k) { var c = DOGS[k]; c.bellyR = c.chestR = c.hipR = c.Rb; c.headR = c.headW = c.Rh; c.leg = 0.18; c.len = 2 * c.Rb; });
  SG.JELLY_CATS = CATS; SG.JELLY_DOGS = DOGS; // owner 2026-11-26: the jelly cats and dogs are kept aside; for now the game follows the original (people)
  /* owner 2026-11-26 「模型和原版一樣都是人」: a smooth white glossy mannequin, person-sized (about 1.7 m once the plan scale 1.5 is applied).
     Our own shape: an egg head with no face, a soft torso, mitten hands, rounded feet. hunters are the same figure holding the paint gun. */
  var HU = { kind: 'cat', jelly: true, human: true, coat: 'blank', tail: JT, ear: { type: 'none', w: 0, h: 0, spread: 0, tilt: 0 }, Rb: 0.12, Rh: 0.08, hc: 0.47, neck: 0.04, depth: 0.7, arm: 0.48, armR: 0.035, foot: 0.04 };
  function human(o) { var c = {}; Object.keys(HU).forEach(function (k) { c[k] = HU[k]; }); Object.keys(o).forEach(function (k) { c[k] = o[k]; }); c.bellyR = c.chestR = c.hipR = c.Rb; c.headR = c.headW = c.Rh; c.leg = 0.38; c.len = 0.2; return c; }
  CATS = { person: human({ name: '人偶', tag: '標準' }), plump: human({ name: '圓滾', tag: '胖胖', girth: 1.28 }), lanky: human({ name: '高瘦', tag: '細長', girth: 0.86, height: 1.06 }) };
  DOGS = { hunter: human({ name: '獵人', tag: '持槍', kind: 'dog' }), hunter2: human({ name: '獵人', tag: '圓滾', kind: 'dog', girth: 1.2 }) };
  SG.CATS = CATS; SG.DOGS = DOGS;
  /* ears / tail / collar can be chosen separately from the build */
  SG.CRITTER_OPTIONS = {
    cat: { ear: [['', '原本'], ['point', '立耳'], ['fold', '摺耳'], ['big', '大耳'], ['round', '圓耳']], tail: [['', '短尾'], ['none', '無尾'], ['long', '長尾'], ['fluffy', '粗尾'], ['curl', '捲尾']] },
    dog: { ear: [['', '原本'], ['point', '立耳'], ['flop', '垂耳'], ['fold', '摺耳']], tail: [['', '原本'], ['curl', '捲尾'], ['nub', '短尾'], ['long', '長尾'], ['pom', '毛球尾']], collar: [['', '無'], ['red', '紅項圈'], ['bell', '鈴鐺'], ['scarf', '領巾']] }
  };
  SG.makeSpec = function (base, o) {
    o = o || {}; var S = {}, k; for (k in base) S[k] = base[k];
    var HR = S.headR, L = S.len, dog = S.kind === 'dog', lr = dog ? S.legRad : S.legRad * 0.8;
    var E = { point: { type: 'point', h: HR * 0.6, w: HR * 0.42, spread: 0.72, tilt: dog ? 28 : 34 }, fold: { type: 'tab', h: HR * 0.36, w: HR * 0.4, spread: 0.76, tilt: dog ? 60 : 52 }, big: { type: 'point', h: HR * 0.95, w: HR * 0.52, spread: 0.72, tilt: 36 }, round: { type: 'round', h: HR * 0.42, w: HR * 0.42, spread: 0.74, tilt: 44 }, flop: { type: 'flop', h: HR * 0.8, w: HR * 0.46, spread: 0.8, tilt: 102 } };
    /* cats: every tail is carried low (never up in the air); the long ones are a deliberate choice */
    var T = dog ? { long: { len: L * 0.3, r0: lr * 0.7, r1: lr * 0.45, up: 92, curl: 2, flat: 0.5, y: 0 }, nub: { len: 0.05, r0: lr * 0.8, r1: lr * 0.7, up: 90, curl: 0, flat: 0.5, y: 0 }, curl: { len: L * 0.24, r0: lr, r1: lr * 0.9, up: 108, curl: 28, flat: 0.5, y: 0.01 }, pom: { len: L * 0.18, r0: lr * 0.6, r1: lr * 1.2, up: 100, curl: 0, bushy: true, flat: 0.8, y: 0.01 } }
      : { long: { len: L * 0.7, r0: lr * 0.75, r1: lr * 0.5, up: 90, curl: 0, flat: 0.5, y: 0 }, bob: tab(1), none: { len: 0.05, r0: 0.02, r1: 0.016, up: 90, curl: 0, none: true, y: 0 }, fluffy: { len: L * 0.55, r0: lr * 1.0, r1: lr * 1.6, up: 90, curl: 0, bushy: true, flat: 0.45, y: 0 }, curl: { len: L * 0.6, r0: lr * 0.75, r1: lr * 0.55, up: 100, curl: 34, flat: 0.6, y: 0 } };
    if (o.ear && E[o.ear]) { S.ear = E[o.ear]; S.earPom = false; }
    if (o.tail && T[o.tail]) { S.tail = T[o.tail]; S.tailPomOff = !T[o.tail].pom; }
    if (o.collar) S.collar = o.collar;
    return S;
  };

  /* ---------- dog poses: degrees [x,y,z] per joint; sh/el/hp/kn apply to both sides (y,z mirrored) ---------- */
  var POSES = {
    stand: {},
    sit: { pivot: [-38, 0, 0], chest: [-6, 0, 0], neck: [20, 0, 0], head: [22, 0, 0], sh: [36, 0, 0], el: [6, 0, 0], hp: [-62, 0, -8], kn: [128, 0, 0], t0: [35, 40, 0], t1: [0, 30, 0], t2: [0, 30, 0], t3: [0, 25, 0] },
    loaf: { sh: [72, 0, 0], el: [-158, 0, 0], hp: [-74, 0, -8], kn: [156, 0, 0], chest: [-4, 0, 0], neck: [-6, 0, 0], head: [4, 0, 0], t0: [-30, 64, 0], t1: [0, 50, 0], t2: [0, 48, 0], t3: [0, 42, 0] },
    stretch: { pivot: [24, 0, 0], chest: [10, 0, 0], sh: [-104, 0, 0], el: [0, 0, 0], hp: [-26, 0, 0], kn: [4, 0, 0], neck: [-26, 0, 0], head: [-20, 0, 0], t0: [-30, 0, 0], t1: [-18, 0, 0], t2: [-18, 0, 0] },
    side: { pivot: [0, 0, 88], chest: [0, -6, 0], hip: [0, 6, 0], neck: [6, 0, 0], head: [0, 0, 6], shL: [-34, 0, 0], shR: [-48, 0, -18], elL: [28, 0, 0], elR: [40, 0, 0], hpL: [26, 0, 0], hpR: [38, 0, -18], knL: [-30, 0, 0], knR: [-44, 0, 0], t0: [-22, 0, 0], t1: [-10, 0, 0], t2: [-8, 0, 0] },
    curl: { pivot: [0, 0, 62], chest: [0, -58, 0], hip: [0, 58, 0], neck: [10, -50, 0], head: [20, -42, 0], sh: [-70, 0, 0], el: [120, 0, 0], hp: [-70, 0, 0], kn: [130, 0, 0], t0: [-36, 64, 0], t1: [0, 56, 0], t2: [0, 56, 0], t3: [0, 50, 0] },
    belly: { pivot: [0, 0, 176], chest: [-8, 10, 0], hip: [8, -6, 0], neck: [-30, 16, 0], head: [-34, 20, 0], shL: [-50, 0, -18], shR: [-30, 0, 18], elL: [96, 0, 0], elR: [80, 0, 0], hpL: [40, 0, -26], hpR: [26, 0, 26], knL: [-84, 0, 0], knR: [-60, 0, 0], t0: [-40, 30, 0], t1: [0, 22, 0], t2: [0, 22, 0] },
    hind: { pivot: [-78, 0, 0], chest: [-4, 0, 0], neck: [34, 0, 0], head: [40, 0, 0], shL: [58, 0, -10], shR: [58, 0, 10], el: [-96, 0, 0], hp: [74, 0, 0], kn: [4, 0, 0], t0: [86, 0, 0], t1: [-26, 0, 0], t2: [-26, 0, 0] },
    arch: { chest: [46, 0, 0], hip: [-46, 0, 0], neck: [-30, 0, 0], head: [-10, 0, 0], sh: [-42, 0, 0], el: [0, 0, 0], hp: [42, 0, 0], kn: [0, 0, 0], t0: [-70, 0, 0], t1: [-14, 0, 0], t2: [-6, 0, 0], t3: [14, 0, 0], earL: [30, 0, 0], earR: [30, 0, 0] },
    crouch: { sh: [-42, 0, 0], el: [84, 0, 0], hp: [-44, 0, 0], kn: [88, 0, 0], neck: [26, 0, 0], head: [-18, 0, 0], t0: [38, 0, 0], t1: [10, 0, 0] },
    box: { pivot: [-36, 0, 0], chest: [-8, 0, 0], neck: [24, 0, 0], head: [16, 0, 0], sh: [40, 0, 0], el: [2, 0, 0], hp: [-66, 0, -6], kn: [136, 0, 0], t0: [50, 78, 0], t1: [0, 62, 0], t2: [0, 58, 0], t3: [0, 50, 0] },
    sphinx: { sh: [-84, 0, 0], el: [0, 0, 0], hp: [-72, 0, -10], kn: [156, 0, 0], chest: [-12, 0, 0], neck: [-20, 0, 0], head: [-8, 0, 0], t0: [-20, 20, 0], t1: [0, 16, 0], t2: [0, 16, 0] },
    hang: { pivot: [26, 0, 0], chest: [26, 0, 0], neck: [34, 0, 0], head: [20, 0, 0], sh: [-36, 0, 0], el: [10, 0, 0], hp: [-70, 0, -12], kn: [150, 0, 0], t0: [-40, 0, 0], t1: [-10, 0, 0] },
    pawsup: { pivot: [-62, 0, 0], chest: [-10, 0, 0], neck: [30, 0, 0], head: [20, 0, 0], shL: [-70, 0, -8], shR: [-70, 0, 8], el: [-30, 0, 0], hp: [60, 0, 0], kn: [4, 0, 0], t0: [70, 0, 0], t1: [-20, 0, 0], t2: [-20, 0, 0] },
    roll: { pivot: [0, 0, 176], chest: [-6, 14, 0], hip: [6, -14, 0], neck: [-26, 0, 0], head: [-26, 0, 0], sh: [-40, 0, 0], el: [90, 0, 0], hp: [34, 0, 0], kn: [-74, 0, 0], t0: [-40, 0, 0], emote: true }
  };

  /* ---------- cat poses: f(amount 0..1, D = body dimensions) -> joint degrees + shape controls ----------
     keys: joints as above; pivot [x,y,z] deg; S [x,y,z] whole-figure scale; m [log, ball] shape targets 0..1;
     leg [front, hind] leg length 0..1 (0 = drawn in completely); g [zmin, zmax] = which part of the body rests on the ground */
  function L3(a, b, t) { return [lerp(a[0], b[0], t), lerp(a[1], b[1], t), lerp(a[2], b[2], t)]; }
  var CPOSE = {
    stand: { label: '站立', amt: 0.5, f: function () { return {}; } },
    crouch: { label: '壓低', amt: 0.5, f: function () { return { leg: [0.4, 0.4], S: [1.05, 0.72, 1.05] }; } },
    /* page 1: the eight simple shapes, all starting from the flat mat */
    ball: { label: '貓球', hint: '鬆 ↔ 緊', amt: 0.6, f: function (a) { return { m: [0, 1, 0], leg: [0, 0], S: [lerp(1.1, 0.93, a), lerp(0.88, 0.93, a), lerp(1.28, 0.93, a)] }; } },
    loaf: { label: '吐司', hint: '微鼓 ↔ 方塊', amt: 0.7, f: function (a) { return { m: [lerp(0.5, 1, a), 0, 0], leg: [0, 0], S: [lerp(1, 1.12, a), lerp(1, 1.05, a), lerp(0.96, 0.72, a)] }; } },
    bolster: { label: '捲筒', hint: '短粗 ↔ 細長', amt: 0.4, f: function (a) { return { m: [1, 0, 0], leg: [0, 0], S: [lerp(1, 0.74, a), lerp(1, 0.74, a), lerp(1, 1.7, a)] }; } },
    pancake: { label: '貓餅', hint: '厚 ↔ 薄', amt: 0.75, f: function (a) { return { leg: [0, 0], S: [lerp(1, 1.14, a), lerp(0.85, 0.28, a), lerp(1, 1.14, a)] }; } },
    arch: { label: '拱橋', hint: '低 ↔ 高', amt: 0.8, f: function (a) { return { m: [0, 0, lerp(0.45, 1, a)], leg: [0, 0] }; } },
    lsit: { label: '摺角', hint: '斜 ↔ 直角', amt: 0.85, f: function (a) { return { chest: [-lerp(35, 100, a), 0, 0], leg: [0, 0] }; } },
    tall: { label: '直立', hint: '板 ↔ 柱', amt: 0.3, f: function (a) { return { pivot: [-90, 0, 0], m: [a, 0, 0], leg: [0, 0] }; } },
    drape: { label: '掛邊', hint: '斜掛 ↔ 垂直', amt: 0.8, f: function (a, D) { return { chest: [lerp(40, 96, a), 0, 0], leg: [0, 0], g: [-9, D.zb2 - 0.03] }; } },
    /* page 2 */
    sit: { label: '抬頭', hint: '低 ↔ 高', amt: 0.5, f: function (a) { var p = lerp(20, 72, a); return { chest: [-p, 0, 0], neck: [p * 0.45, 0, 0], head: [p * 0.2, 0, 0] }; } },
    side: { label: '側立', hint: '伸腳 ↔ 收腳', amt: 0.6, f: function (a) { var lg = clamp((0.42 - a) / 0.08, 0, 1); return { pivot: [0, 0, 90], leg: [lg, lg] }; } },
    sphinx: { label: '趴臥', hint: '低頭 ↔ 仰頭', amt: 0.5, f: function (a) { return { neck: [-lerp(6, 40, a), 0, 0], head: [lerp(0, 12, a), 0, 0] }; } },
    stretch: { label: '斜坡', hint: '緩 ↔ 陡', amt: 0.5, f: function (a, D) { var p = lerp(8, 30, a); return { pivot: [p, 0, 0], hp: [-p, 0, 0], leg: [0, clamp(D.L * 0.86 * Math.sin(p * D2R) / D.H, 1, 9)] }; } },
    belly: { label: '翻肚', hint: '舉腳 ↔ 收腳', amt: 0.3, f: function (a) { var lg = clamp((0.42 - a) / 0.08, 0, 1); return { pivot: [0, 0, 180], leg: [lg * 1.4, lg * 1.4], shL: [-20, 0, -20], shR: [-20, 0, 20], hpL: [20, 0, -20], hpR: [20, 0, 20] }; } },
    curl: { label: '彎月', hint: '微彎 ↔ 半圈', amt: 0.6, f: function (a) { var t = lerp(22, 84, a); return { leg: [0, 0], chest: [0, t, 0], hip: [0, -t, 0], neck: [0, t * 0.35, 0] }; } },
    box: { label: '方塊', hint: '扁 ↔ 高', amt: 0.6, f: function (a) { return { m: [1, 0, 0], leg: [0, 0], S: [1.06, lerp(0.9, 1.3, a), lerp(0.52, 0.42, a)] }; } },
    pawsup: { label: '斜靠', hint: '斜 ↔ 貼牆', amt: 0.5, f: function (a) { return { pivot: [-lerp(38, 84, a), 0, 0], leg: [0, 0] }; } },
    roll: { label: '打滾', amt: 0.3, emote: true, f: function () { return { pivot: [0, 0, 180], leg: [1.4, 1.4] }; } }
  };
  /* jelly poses: the original's fixed poses (no free stretching, owner 2026-11-25). S = whole-figure scale (volume kept roughly the same),
     leg [arms, feet]: 0 = drawn into the body. Arms: sh/el (mirrored for R), feet: hp. */
  var JPOSE = {
    stand: { label: '站立', amt: 0.5, f: function (a, D) { return D.dog ? { sh: [-62, 0, 28], el: [-38, 0, 0] } : {}; } },
    crouch: { label: '壓低', amt: 0.5, f: function () { return { S: [1.06, 0.84, 1.06] }; } },
    ball: { label: '縮成球', hint: '鬆 ↔ 緊', amt: 0.6, f: function (a) { return { leg: [0, 0], S: [lerp(1.05, 1.0, a), lerp(0.9, 0.84, a), lerp(1.05, 1.0, a)], neck: [lerp(8, 22, a), 0, 0] }; } },
    loaf: { label: '壓低', hint: '微扁 ↔ 很扁', amt: 0.5, f: function (a) { return { leg: [0, 0.3], S: [lerp(1.08, 1.2, a), lerp(0.84, 0.68, a), lerp(1.08, 1.2, a)] }; } },
    bolster: { label: '側躺', hint: '伸手 ↔ 收手', amt: 0.6, f: function (a) { var lg = a > 0.5 ? 0 : 1; return { pivot: [0, 0, 90], leg: [lg, lg], S: [1, lerp(1, 0.88, a), 1] }; } },
    pancake: { label: '攤平', hint: '厚 ↔ 薄', amt: 0.7, f: function (a) { return { leg: [0, 0], S: [lerp(1.3, 1.62, a), lerp(0.56, 0.36, a), lerp(1.3, 1.62, a)] }; } },
    arch: { label: '趴下', hint: '手放下 ↔ 手往前', amt: 0.5, f: function (a) { return { pivot: [86, 0, 0], sh: [-lerp(60, 165, a), 0, 0], leg: [1, 0] }; } },
    lsit: { label: '坐下', hint: '直 ↔ 後仰', amt: 0.4, f: function (a) { return { pivot: [-lerp(8, 28, a), 0, 0], hp: [-85, 0, 0], sh: [0, 0, 14] }; } },
    tall: { label: '舉手', hint: '斜 ↔ 直', amt: 0.6, f: function (a) { return { sh: [0, 0, -lerp(115, 160, a)], S: [0.96, 1.06, 0.96] }; } },
    drape: { label: '掛邊', hint: '斜掛 ↔ 垂直', amt: 0.7, f: function (a) { return { chest: [lerp(40, 95, a), 0, 0], sh: [-lerp(30, 70, a), 0, 0] }; } },
    sit: { label: '抬頭', hint: '低 ↔ 高', amt: 0.5, f: function (a) { return { neck: [-lerp(12, 38, a), 0, 0], head: [-lerp(4, 14, a), 0, 0] }; } },
    side: { label: '側傾', hint: '微傾 ↔ 很斜', amt: 0.5, f: function (a) { return { pivot: [0, 0, lerp(25, 62, a)], sh: [0, 0, 20] }; } },
    sphinx: { label: '趴臥', hint: '低頭 ↔ 仰頭', amt: 0.5, f: function (a) { return { pivot: [84, 0, 0], neck: [-lerp(0, 40, a), 0, 0], sh: [-90, 0, 10], leg: [1, 0] }; } },
    stretch: { label: '伸懶腰', hint: '小 ↔ 大', amt: 0.5, f: function (a) { return { sh: [-lerp(120, 172, a), 0, -12], S: [0.95, lerp(1.04, 1.1, a), 0.95] }; } },
    belly: { label: '翻肚', hint: '收手 ↔ 張開', amt: 0.4, f: function (a) { return { pivot: [-86, 0, 0], sh: [0, 0, -lerp(10, 80, a)], hp: [-lerp(10, 40, a), 0, 0] }; } },
    curl: { label: '抱膝', hint: '鬆 ↔ 緊', amt: 0.6, f: function (a) { return { chest: [lerp(12, 32, a), 0, 0], neck: [lerp(8, 20, a), 0, 0], sh: [-lerp(40, 70, a), 0, 24], el: [-lerp(50, 85, a), 0, 0] }; } },
    box: { label: '扁平', hint: '略扁 ↔ 很扁', amt: 0.6, f: function (a) { return { leg: [0, 0], S: [lerp(1.12, 1.24, a), 1.02, lerp(0.7, 0.56, a)] }; } },
    pawsup: { label: '揮手', amt: 0.6, f: function (a) { return { shR: [0, 0, lerp(100, 140, a)], elR: [0, 0, -25] }; } },
    roll: { label: '打滾', amt: 0.3, emote: true, f: function () { return { pivot: [0, 0, 180] }; } }
  };
  /* owner 2026-11-26: the figures are people now, so the wheel holds the original's human poses (names from the owner's screenshot of page 1
     and the 23 June update for page 2, original-evidence.md section 8). The joint angles are our own. Degrees, 'YXZ'; L/R keys are one side only. */
  var HPOSE = {
    stand: { label: '站立', amt: 0.5, f: function (a, D) { return D.dog ? { sh: [-62, 0, 20], el: [-40, 0, 0] } : {}; } },
    crouch: { label: '蹲', amt: 0.5, f: function () { return { hp: [-70, 0, 4], kn: [110, 0, 0], chest: [18, 0, 0], sh: [-20, 0, 6] }; } },
    kneel: { label: '跪坐', hint: '直 ↔ 前傾', amt: 0.3, f: function (a) { return { hp: [-88, 0, 0], kn: [162, 0, 0], chest: [lerp(0, 25, a), 0, 0], sh: [-18, 0, 6], el: [-35, 0, 0] }; } },
    lieBack: { label: '仰躺', hint: '手貼身 ↔ 手張開', amt: 0.3, f: function (a) { return { pivot: [-90, 0, 0], sh: [0, 0, -lerp(6, 75, a)], hp: [0, 0, -4] }; } },
    bend: { label: '彎腰', hint: '小 ↔ 大', amt: 0.5, f: function (a) { var b = lerp(30, 65, a); return { body: [b, 0, 0], hp: [-b - 6, 0, 0], chest: [lerp(10, 25, a), 0, 0], sh: [-lerp(20, 45, a), 0, 4], neck: [-lerp(15, 30, a), 0, 0] }; } },
    raiseArm: { label: '舉臂', hint: '斜 ↔ 直', amt: 0.6, f: function (a) { return { shR: [0, 0, lerp(130, 172, a)], shL: [0, 0, -6] }; } },
    akimbo: { label: '叉腰', amt: 0.5, f: function () { return { sh: [8, 0, -42], el: [0, -20, 88] }; } },
    bothUp: { label: '雙手過頭', hint: '斜 ↔ 直', amt: 0.6, f: function (a) { return { sh: [0, 0, -lerp(140, 176, a)], S: [0.98, 1.03, 0.98] }; } },
    curl: { label: '蜷縮', hint: '鬆 ↔ 緊', amt: 0.6, f: function (a) { return { hp: [-lerp(105, 128, a), 0, 6], kn: [lerp(125, 150, a), 0, 0], chest: [lerp(25, 45, a), 0, 0], neck: [lerp(10, 25, a), 0, 0], sh: [-lerp(40, 62, a), 0, 18], el: [-lerp(60, 95, a), 0, 0] }; } },
    prone: { label: '趴平', hint: '手放身旁 ↔ 手往前', amt: 0.3, f: function (a) { return { pivot: [90, 0, 0], sh: [-lerp(5, 170, a), 0, -6], neck: [-10, 0, 0] }; } },
    tuck: { label: '蜷身', hint: '鬆 ↔ 緊', amt: 0.6, f: function (a) { return { hp: [-lerp(120, 138, a), 0, 0], kn: [lerp(140, 158, a), 0, 0], chest: [lerp(45, 70, a), 0, 0], neck: [lerp(20, 40, a), 0, 0], sh: [-lerp(70, 95, a), 0, 10], el: [-lerp(80, 110, a), 0, 0], S: [1, 0.96, 1] }; } },
    leanBack: { label: '後仰', hint: '小 ↔ 大', amt: 0.5, f: function (a) { var b = lerp(16, 34, a); return { body: [-b, 0, 0], hp: [b - lerp(10, 30, a), 0, 0], kn: [lerp(15, 45, a), 0, 0], chest: [-lerp(10, 25, a), 0, 0], neck: [-lerp(8, 20, a), 0, 0], sh: [lerp(10, 30, a), 0, -10] }; } },
    leanSide: { label: '斜身', hint: '微 ↔ 大', amt: 0.5, f: function (a) { var b = lerp(14, 30, a); return { body: [0, 0, b], hpL: [0, 0, -b + 3], hpR: [0, 0, -b - 3], chest: [0, 0, lerp(8, 20, a)], neck: [0, 0, -lerp(4, 12, a)], shL: [0, 0, -lerp(20, 50, a)] }; } },
    armLean: { label: '單臂靠', hint: '低 ↔ 高', amt: 0.5, f: function (a) { return { shL: [0, 0, -lerp(70, 115, a)], elL: [0, 0, -12], chest: [0, 0, -lerp(6, 14, a)], hpR: [0, 0, 8], shR: [0, 0, 4] }; } },
    squat: { label: '深蹲', hint: '淺 ↔ 深', amt: 0.6, f: function (a) { return { hp: [-lerp(90, 122, a), 0, 12], kn: [lerp(105, 145, a), 0, 0], chest: [lerp(18, 32, a), 0, 0], sh: [-lerp(50, 80, a), 0, 8], el: [-20, 0, 0] }; } },
    crossLeg: { label: '盤腿', amt: 0.5, f: function () { return { hp: [-88, 0, -52], kn: [135, 0, 0], ft: [0, 0, 0], sh: [-22, 0, 10], el: [-55, 0, 0] }; } },
    oneLeg: { label: '單腳', hint: '低 ↔ 高', amt: 0.5, f: function (a) { return { hpR: [-lerp(40, 85, a), 0, 0], knR: [lerp(60, 110, a), 0, 0], sh: [0, 0, -lerp(30, 70, a)] }; } },
    tpose: { label: 'T 字', amt: 0.5, f: function () { return { sh: [0, 0, -88] }; } },
    splits: { label: '劈腿', hint: '前後 ↔ 左右', amt: 0.2, f: function (a) { return a < 0.5 ? { hpL: [-86, 0, 0], hpR: [84, 0, 0], sh: [0, 0, -60] } : { hp: [0, 0, -86], sh: [0, 0, -60] }; } },
    fold: { label: '前彎', hint: '小 ↔ 大', amt: 0.6, f: function (a) { var b = lerp(80, 110, a); return { body: [b, 0, 0], hp: [-b, 0, 0], chest: [lerp(10, 25, a), 0, 0], sh: [-lerp(70, 100, a), 0, 4], neck: [lerp(5, 20, a), 0, 0] }; } },
    roll: { label: '打滾', amt: 0.3, emote: true, f: function () { return { pivot: [0, 0, 180] }; } }
  };
  ['ball', 'loaf', 'bolster', 'pancake', 'arch', 'lsit', 'tall', 'drape', 'sit', 'side', 'sphinx', 'stretch', 'belly', 'box', 'pawsup'].forEach(function (k) { if (!HPOSE[k]) HPOSE[k] = JPOSE[k] && { label: JPOSE[k].label, amt: JPOSE[k].amt, f: { ball: HPOSE.curl.f, loaf: HPOSE.crouch.f, bolster: HPOSE.lieBack.f, pancake: HPOSE.prone.f, arch: HPOSE.prone.f, lsit: HPOSE.kneel.f, tall: HPOSE.bothUp.f, drape: HPOSE.fold.f, sit: HPOSE.kneel.f, side: HPOSE.leanSide.f, sphinx: HPOSE.prone.f, stretch: HPOSE.bothUp.f, belly: HPOSE.lieBack.f, box: HPOSE.tpose.f, pawsup: HPOSE.raiseArm.f }[k] }; }); // old names still work (decoys, title screen, saved games)
  Object.keys(HPOSE).forEach(function (k) { if (!POSES[k]) POSES[k] = {}; }); // the human names are valid pose names too
  function PT(S) { return S && S.human ? HPOSE : S && S.jelly ? JPOSE : CPOSE; }
  var ALIAS = { hind: 'tall', hang: 'drape' };
  Object.keys(CPOSE).forEach(function (k) { if (!POSES[k]) POSES[k] = {}; }); // every name is a valid pose for both kinds
  POSES.tall = POSES.hind; POSES.drape = POSES.hang; POSES.lsit = POSES.sit; POSES.ball = POSES.curl; POSES.bolster = POSES.sphinx; POSES.pancake = POSES.sphinx;
  SG.POSES = POSES;
  SG.POSE_PAGES = [['kneel', 'lieBack', 'bend', 'raiseArm', 'akimbo', 'bothUp', 'curl', 'prone'], ['tuck', 'leanBack', 'leanSide', 'armLean', 'squat', 'crossLeg', 'oneLeg', 'tpose', 'splits', 'fold']]; // the original's two pages
  SG.POSE_INFO = {}; Object.keys(HPOSE).forEach(function (k) { SG.POSE_INFO[k] = { label: HPOSE[k].label, amount: HPOSE[k].amt, hint: HPOSE[k].hint || '' }; });
  SG.POSE_LIST = [['stand', '站立']].concat(SG.POSE_PAGES[0].concat(SG.POSE_PAGES[1]).map(function (k) { return [k, HPOSE[k].label]; }));

  /* =====================================================================================================
     mesh builder: joints + charts (vertices with skin weights and chart-space UVs) -> packed atlas, typed arrays,
     per-texel triangle/barycentric map (so a texel's 3D position is exactly what the renderer shows there)
     ===================================================================================================== */
  function Builder(A) {
    this.A = A; this.P = []; this.N = []; this.W = []; this.ST = []; this.CH = []; this.I = []; this.charts = [];
    this.jd = []; this.jmap = {}; this.MP = [null, null, null]; this.MN = [null, null, null]; // shape targets (absolute positions / normals for the vertices that have one)
  }
  var BP = Builder.prototype;
  BP.joint = function (name, parent, x, y, z, rx, ry, rz) {
    var m = new THREE.Matrix4().compose(new THREE.Vector3(x || 0, y || 0, z || 0), new THREE.Quaternion().setFromEuler(new THREE.Euler((rx || 0) * D2R, (ry || 0) * D2R, (rz || 0) * D2R)), new THREE.Vector3(1, 1, 1));
    var p = parent ? this.jmap[parent] : null, w = p ? p.w.clone().multiply(m) : m.clone();
    var j = { name: name, parent: p ? p.i : -1, pos: [x || 0, y || 0, z || 0], rot: [rx || 0, ry || 0, rz || 0], w: w, i: this.jd.length };
    this.jd.push(j); this.jmap[name] = j; return j;
  };
  BP.vert = function (p, n, w, s, t, ch) { this.P.push(p[0], p[1], p[2]); this.N.push(n[0], n[1], n[2]); this.W.push(w); this.ST.push(s, t); this.CH.push(ch); return this.P.length / 3 - 1; };
  BP.chart = function (name, w, h, o) {
    o = o || {}; var c = { name: name, w: w, h: h, dens: o.dens || 1, fixed: o.fixed || 0, block: o.block == null ? -1 : o.block, inner: o.inner, joint: o.joint, v0: this.P.length / 3, i0: this.I.length, id: this.charts.length, o: o.o || null, r0: o.r0 || 0, anchor: o.anchor || null };
    this.charts.push(c); return c;
  };
  BP.end = function (c) { c.v1 = this.P.length / 3; c.i1 = this.I.length; };

  /* normals of a ring grid P[(k*(NA+1)+i)*3] (column NA repeats column 0); rings that collapse to a point get the axis direction */
  function gridNormals(P, NR, NA, out) {
    var C = NA + 1, k, i, o, sgn = 0, pole = [];
    for (k = 0; k <= NR; k++) {
      var k0 = Math.max(0, k - 1), k1 = Math.min(NR, k + 1), rc = [0, 0, 0], rad = 0;
      for (i = 0; i < NA; i++) { o = (k * C + i) * 3; rc[0] += P[o] / NA; rc[1] += P[o + 1] / NA; rc[2] += P[o + 2] / NA; }
      for (i = 0; i < NA; i++) { o = (k * C + i) * 3; rad = Math.max(rad, Math.hypot(P[o] - rc[0], P[o + 1] - rc[1], P[o + 2] - rc[2])); }
      pole.push(rad < 1e-6);
      for (i = 0; i <= NA; i++) {
        var ii = i % NA, a = (k * C + (ii + 1) % NA) * 3, b = (k * C + (ii + NA - 1) % NA) * 3, d = (k1 * C + ii) * 3, e = (k0 * C + ii) * 3, q = (k * C + i) * 3;
        var ux = P[a] - P[b], uy = P[a + 1] - P[b + 1], uz = P[a + 2] - P[b + 2], vx = P[d] - P[e], vy = P[d + 1] - P[e + 1], vz = P[d + 2] - P[e + 2];
        var nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx, l = Math.hypot(nx, ny, nz);
        if (rad < 1e-6 || l < 1e-14) { // a ring that collapses to a point: straight away from the neighbouring ring
          var kn = k === 0 ? 1 : k === NR ? NR - 1 : k, m = [0, 0, 0];
          for (var t = 0; t < NA; t++) { var oo = (kn * C + t) * 3; m[0] += P[oo] / NA; m[1] += P[oo + 1] / NA; m[2] += P[oo + 2] / NA; }
          nx = rc[0] - m[0]; ny = rc[1] - m[1]; nz = rc[2] - m[2]; l = Math.hypot(nx, ny, nz) || 1; pole[k] = true;
        } else if (i < NA) sgn += (nx * (P[q] - rc[0]) + ny * (P[q + 1] - rc[1]) + nz * (P[q + 2] - rc[2])) / l;
        out[q] = nx / l; out[q + 1] = ny / l; out[q + 2] = nz / l;
      }
    }
    if (sgn < 0) for (k = 0; k <= NR; k++) if (!pole[k]) for (i = 0; i <= NA; i++) { o = (k * C + i) * 3; out[o] = -out[o]; out[o + 1] = -out[o + 1]; out[o + 2] = -out[o + 2]; }
    for (k = 0; k <= NR; k++) if (pole[k]) { // a pole looks the way its ring of neighbours looks on average
      var kk = k; while (kk < NR && pole[kk] && k < NR / 2) kk++; while (kk > 0 && pole[kk] && k >= NR / 2) kk--;
      var sx = 0, sy = 0, sz = 0; for (i = 0; i < NA; i++) { o = (kk * C + i) * 3; sx += out[o]; sy += out[o + 1]; sz += out[o + 2]; }
      var sl = Math.hypot(sx, sy, sz); if (sl < 1e-6) { sx = out[k * C * 3]; sy = out[k * C * 3 + 1]; sz = out[k * C * 3 + 2]; sl = Math.hypot(sx, sy, sz) || 1; }
      for (i = 0; i <= NA; i++) { o = (k * C + i) * 3; out[o] = sx / sl; out[o + 1] = sy / sl; out[o + 2] = sz / sl; }
    }
    return out;
  }
  /* skin weights along a chain of joints: bounds[i] is where names[i] hands over to names[i+1], blended over +-widths[i] */
  function chainW(names, bounds, widths, x) {
    var tt = [1], out = [], q, n = names.length;
    for (q = 0; q < n - 1; q++) tt.push(sstep(bounds[q] - widths[q], bounds[q] + widths[q], x)); tt.push(0);
    for (q = 0; q < n; q++) { var w = tt[q] * (1 - tt[q + 1]); if (w > 1e-4) out.push([names[q], w]); }
    return out;
  }
  /* ring where an end cap turns from "end face" into "side wall" (45 degrees), counted from the pole */
  function capCut(G, fromEnd) {
    var C = G.NA + 1, P = G.P, top = (G.NA >> 1), prev = null, k, n = 0;
    for (k = fromEnd ? G.NR : 0; fromEnd ? k > G.NR - 9 : k < 9; k += fromEnd ? -1 : 1, n++) {
      var o = (k * C + top) * 3, b = (k * C) * 3, r = Math.abs(P[o + 1] - P[b + 1]) / 2, z = P[o + 2];
      if (prev && n > 2 && Math.abs(z - prev[1]) > Math.abs(r - prev[0])) return fromEnd ? k + 1 : k - 1;
      prev = [r, z];
    }
    return fromEnd ? G.NR - 4 : 4;
  }
  /* is the (k,i)->(k,i+1)->(k+1,i) winding outward? */
  function gridFlip(P, Nn, NR, NA) {
    var C = NA + 1, s = 0;
    for (var k = 0; k < NR; k++) for (var i = 0; i < NA; i += 3) {
      var a = (k * C + i) * 3, b = a + 3, c = ((k + 1) * C + i) * 3;
      var ux = P[b] - P[a], uy = P[b + 1] - P[a + 1], uz = P[b + 2] - P[a + 2], vx = P[c] - P[a], vy = P[c + 1] - P[a + 1], vz = P[c + 2] - P[a + 2];
      s += (uy * vz - uz * vy) * Nn[a] + (uz * vx - ux * vz) * Nn[a + 1] + (ux * vy - uy * vx) * Nn[a + 2];
    }
    return s < 0;
  }
  /* put rings k0..k1 of a grid into a chart. type 'unroll' (u = arc length round the ring, v = length along) or 'planar' (ax = [uAxis, vAxis]) */
  BP.gridChart = function (name, G, k0, k1, type, o) {
    o = o || {}; var P = G.P, Nn = G.N, NA = G.NA, C = NA + 1, k, i, self = this;
    var ring = [], vv = [0], W = o.width || 0, mn = [1e9, 1e9], mx = [-1e9, -1e9], ax = o.ax || [0, 1];
    for (k = k0; k <= k1; k++) { // arc length round each ring, and mean distance to the previous ring
      var acc = [0], d = 0;
      for (i = 0; i < NA; i++) { var a = (k * C + i) * 3, b = (k * C + i + 1) * 3; acc.push(acc[i] + Math.hypot(P[b] - P[a], P[b + 1] - P[a + 1], P[b + 2] - P[a + 2]) * (o.uw ? o.uw(i) : 1)); }
      ring.push(acc); if (!o.width) W = Math.max(W, acc[NA]);
      if (k > k0) { for (i = 0; i < NA; i++) { a = (k * C + i) * 3; b = ((k - 1) * C + i) * 3; d += Math.hypot(P[b] - P[a], P[b + 1] - P[a + 1], P[b + 2] - P[a + 2]) / NA; } vv.push(vv[k - k0 - 1] + d); }
      for (i = 0; i < NA; i++) { a = (k * C + i) * 3; mn[0] = Math.min(mn[0], P[a + ax[0]]); mx[0] = Math.max(mx[0], P[a + ax[0]]); mn[1] = Math.min(mn[1], P[a + ax[1]]); mx[1] = Math.max(mx[1], P[a + ax[1]]); }
    }
    var H = vv[vv.length - 1], ch = type === 'planar' ? this.chart(name, mx[0] - mn[0], mx[1] - mn[1], o) : this.chart(name, W, H, o);
    var base = this.P.length / 3;
    for (k = k0; k <= k1; k++) for (i = 0; i <= NA; i++) {
      var q = (k * C + i) * 3, s, t, acc2 = ring[k - k0];
      if (type === 'planar') { s = P[q + ax[0]] - mn[0]; if (o.flip) s = (mx[0] - mn[0]) - s; t = P[q + ax[1]] - mn[1]; }
      else { s = (acc2[NA] > 1e-7 ? acc2[i] / acc2[NA] : i / NA) * W; t = vv[k - k0]; }
      var vi = this.vert([P[q], P[q + 1], P[q + 2]], [Nn[q], Nn[q + 1], Nn[q + 2]], G.W(k, i % NA), s, t, ch.id);
      if (G.M) G.M.forEach(function (M, mi) { if (!M) return; if (!self.MP[mi]) { self.MP[mi] = {}; self.MN[mi] = {}; } self.MP[mi][vi] = [M.P[q], M.P[q + 1], M.P[q + 2]]; self.MN[mi][vi] = [M.N[q], M.N[q + 1], M.N[q + 2]]; });
    }
    var flip = G.flip;
    for (k = k0; k < k1; k++) for (i = 0; i < NA; i++) {
      var A0 = base + (k - k0) * C + i, B0 = A0 + 1, C0 = A0 + C, D0 = C0 + 1;
      if (flip) this.I.push(A0, C0, B0, B0, C0, D0); else this.I.push(A0, B0, C0, B0, D0, C0);
    }
    this.end(ch); ch.vlen = H; ch.ulen = W; return ch;
  };

  /* a tube of rings in the local frame M: rings [{y, rx, rz, cx, cz, e}] (cross-section in the local xz plane, superellipse exponent e) */
  function tubeGrid(M, rings, NA, phi0, wfn) {
    var NR = rings.length - 1, C = NA + 1, P = new Float64Array((NR + 1) * C * 3), v = new THREE.Vector3();
    for (var k = 0; k <= NR; k++) {
      var r = rings[k], e = 2 / (r.e || 2);
      for (var i = 0; i <= NA; i++) {
        var ph = phi0 + (i % NA) / NA * PI * 2;
        v.set((r.cx || 0) + r.rx * spow(Math.cos(ph), e), r.y, (r.cz || 0) + r.rz * spow(Math.sin(ph), e)).applyMatrix4(M);
        var o = (k * C + i) * 3; P[o] = v.x; P[o + 1] = v.y; P[o + 2] = v.z;
      }
    }
    var Nn = gridNormals(P, NR, NA, new Float64Array(P.length));
    return { P: P, N: Nn, NR: NR, NA: NA, flip: gridFlip(P, Nn, NR, NA), W: function (k) { return wfn(rings[k], k); } };
  }

  /* ---------- the canvas cat ---------- */
  function catDims(S) {
    var D = { L: S.len, hw: S.hw, hh: S.hh, sq: S.sq || 5 }, L = D.L, hh = D.hh, hw = D.hw, blocky = D.sq > 6;
    D.leg = S.stub != null ? S.stub : S.leg;
    D.capm = blocky ? D.sq : 3; D.sqb = blocky ? D.sq : Math.max(D.sq, 6); D.hsq = blocky ? 6 : Math.min(D.sq, 3); D.lsq = blocky ? 6 : 2.6;
    D.zR = -L / 2; D.rcap = hh * (blocky ? 0.4 : 0.9); D.zc0 = D.zR + D.rcap;                    // the thin rounded edge at the back
    D.plan = clamp(S.plan == null ? 0.06 : S.plan, 0.012, L * 0.46); D.planm = S.planm || (blocky ? 6 : 2.3);  // corners seen from above
    D.hW = S.headW; D.hH = S.headH; D.hD = S.headD; D.hy = S.headUp != null ? S.headUp : D.hH - hh;   // chin level with the belly: the head is a low bump on the front edge
    D.zH = L / 2 + D.hD * 0.1; D.zF = D.zH + D.hD; D.fcap = D.hD * (blocky ? 0.5 : S.faceSq ? 0.7 : 1); D.fsq = S.faceSq || (D.hsq > 5 ? D.hsq : 3.2);
    D.zT0 = D.zH - D.hD * 1.0; D.zT1 = D.zH - D.hD * 0.1; D.zB0 = D.zT0; D.zB1 = D.zT1;
    D.rL = S.legRad; D.rP = S.paw; D.emb = 0.012; D.tuck = Math.min(hh * 0.55, 0.075); D.H = D.emb + D.leg; // leg pivot just inside the belly; a drawn-in leg is pulled up into the body
    D.zf = L / 2 - Math.max(0.065, D.plan * 0.5); D.zh = -D.zf; D.xl = planW(D, D.zf, L / 2) - D.rL - 0.016;
    D.zb1 = -0.13 * L; D.zb2 = 0.13 * L; D.bw = 0.105 * L;
    D.zb3 = D.zT0 + 0.012; D.zb4 = D.zH - D.hD * 0.45; if (D.zb3 < D.zb2 + D.bw + 0.01) D.zb3 = D.zb2 + D.bw + 0.01; if (D.zb4 < D.zb3 + 0.03) D.zb4 = D.zb3 + 0.03; D.bwn = Math.min(0.03, (D.zb4 - D.zb3) * 0.45, (D.zb3 - D.zb2 - D.bw) * 0.9);
    var hv = 8 * D.hW * D.hH * D.hD * 0.55; D.vol = 4 * hw * hh * L * 0.9 + hv;
    D.zE = L / 2 + hv / (4 * hw * hh * 0.95);                                 // front end of the head-less shapes (head volume drawn in)
    D.logS = Math.sqrt(hw * hh) * (S.logK || 1); D.logCap = D.logS * 0.85; D.logn = blocky ? 8 : 3.2;   // "log": the mat rolled up / puffed up into a bolster of the same volume
    D.archA = 172 * D2R; D.archR = (D.zE - D.zR) / D.archA;                   // "arch": the mat bent into a tent
    D.Rb = Math.pow(D.vol * 3 / (4 * PI), 1 / 3) * (blocky ? 0.84 : 1); D.bsq = blocky ? 5 : 2; D.zcb = 0.02;   // "ball"
    return D;
  }
  /* half width of the slab outline at z (rounded corners in plan); the slab runs from zR to zEnd */
  function planW(D, z, zEnd) {
    var a = D.hw;
    if (z < D.zR + D.plan) a *= capf((D.zR + D.plan - z) / D.plan, D.planm);
    if (z > zEnd - D.plan) a *= capf((z - (zEnd - D.plan)) / D.plan, D.planm);
    return a;
  }
  /* cross-section of the body at z: top, bottom, half width, exponents. mode 0 = the animal, 1 = log, 4 = plain slab without a head */
  function catSect(D, z, mode) {
    var T = D.hh, B = -D.hh, a, n = D.sq, nb = D.sqb, f = 1;
    if (mode === 1) {
      var s = D.logS, c = D.logCap; if (z > D.zE - c) f = capf((z - (D.zE - c)) / c, 2.6); if (z < D.zR + c) f = Math.min(f, capf((D.zR + c - z) / c, 2.6));
      return { T: s * f, B: -s * f, a: s * f, n: D.logn, nb: D.logn };
    }
    if (mode === 4) {
      if (z > D.zE - D.rcap) f = capf((z - (D.zE - D.rcap)) / D.rcap, D.capm); if (z < D.zc0) f = Math.min(f, capf((D.zc0 - z) / D.rcap, D.capm));
      return { T: T * f, B: B * f, a: planW(D, z, D.zE), n: n, nb: nb };
    }
    var wt = sstep(D.zT0, D.zT1, z), wb = sstep(D.zB0, D.zB1, z), aB = planW(D, z, D.L / 2), aH = D.hW * sstep(D.zT0 - D.hD * 0.5, D.zT1, z);
    a = Math.pow(Math.pow(aB, 6) + Math.pow(aH, 6), 1 / 6);
    T = lerp(D.hh, D.hy + D.hH, wt); B = lerp(-D.hh, D.hy - D.hH, wb); n = lerp(D.sq, D.hsq, wt); nb = lerp(D.sqb, Math.max(D.hsq, 4), wb);
    var zf0 = D.zF - D.fcap;
    if (z > zf0) { f = capf((z - zf0) / D.fcap, D.fsq); T = D.hy + (T - D.hy) * f; B = D.hy + (B - D.hy) * f; a *= f; }
    if (z < D.zc0) { f = capf((D.zc0 - z) / D.rcap, D.capm); T *= f; B *= f; }
    return { T: T, B: B, a: a, n: n, nb: nb };
  }
  function catBody(D, NA) {
    // ring stations
    var zs = [], j, nc = 6, nf = 7, z, zm = Math.min(D.zT0, D.zB0), zf0 = D.zF - D.fcap;
    for (j = 0; j < nc; j++) zs.push(D.zc0 - D.rcap * Math.cos(j / nc * PI / 2));
    var n1 = Math.max(5, Math.ceil((zm - D.zc0) / 0.026)); for (j = 0; j < n1; j++) zs.push(lerp(D.zc0, zm, j / n1));
    var n2 = Math.max(4, Math.ceil((zf0 - zm) / 0.02)); for (j = 0; j < n2; j++) zs.push(lerp(zm, zf0, j / n2));
    for (j = 0; j <= nf; j++) zs.push(zf0 + D.fcap * Math.sin(j / nf * PI / 2));
    var NR = zs.length - 1, C = NA + 1;
    // angles round the section: half way between even arc length and even parameter (more vertices on the rounded corners)
    var fine = 720, acc = [0], px = 0, py = -D.hh, i;
    for (i = 1; i <= fine; i++) { var ph = i / fine * PI * 2, e0 = 2 / (Math.cos(ph) > 0 ? D.sqb : D.sq), x = D.hw * spow(Math.sin(ph), e0), y = -D.hh * spow(Math.cos(ph), e0); acc.push(acc[i - 1] + Math.hypot(x - px, y - py)); px = x; py = y; }
    var phis = [], us = [], t = 0;
    for (i = 0; i <= NA; i++) { var tg = i / NA; while (t < fine && 0.5 * acc[t + 1] / acc[fine] + 0.5 * (t + 1) / fine < tg) t++; phis.push(Math.min(fine, t + (tg - (0.5 * acc[t] / acc[fine] + 0.5 * t / fine)) / Math.max(1e-9, (0.5 * (acc[Math.min(fine, t + 1)] - acc[t]) / acc[fine] + 0.5 / fine))) / fine * PI * 2); }
    phis[0] = 0; phis[NA] = PI * 2; for (i = 1; i < NA / 2; i++) phis[NA - i] = PI * 2 - phis[i]; phis[NA / 2] = PI;
    for (i = 0; i <= NA; i++) { var fi = phis[i] / (PI * 2) * fine, f0 = Math.floor(fi); us.push((acc[f0] + (acc[Math.min(fine, f0 + 1)] - acc[f0]) * (fi - f0)) / acc[fine]); }
    function fill(mode) {
      var P = new Float64Array((NR + 1) * C * 3), k, o;
      // length along the body for the ball mapping
      var sl = [0]; for (k = 1; k <= NR; k++) { var s0 = catSect(D, zs[k - 1], 0), s1 = catSect(D, zs[k], 0); sl.push(sl[k - 1] + Math.hypot(zs[k] - zs[k - 1], s1.T - s0.T)); }
      for (k = 0; k <= NR; k++) {
        var zz = zs[k];
        if (mode === 2) {
          var lat = (sl[k] / sl[NR] - 0.5) * PI, eb = 2 / D.bsq, rho = spow(Math.cos(lat), eb), zb = D.zcb + D.Rb * spow(Math.sin(lat), eb);
          if (k === 0 || k === NR) rho = 0;
          for (i = 0; i <= NA; i++) { var al = us[i % NA] * PI * 2; o = (k * C + i) * 3; P[o] = D.Rb * rho * spow(Math.sin(al), eb); P[o + 1] = -D.Rb * rho * spow(Math.cos(al), eb); P[o + 2] = zb; }
          continue;
        }
        if (mode !== 0 && zz > zm) zz = zm + (zz - zm) * (D.zE - zm) / (D.zF - zm);
        if (mode === 3) { // arch: the log bent into a half ring, thinner so the opening shows
          var sa = catSect(D, zz, 4), th = (zz - (D.zR + D.zE) / 2) / (D.zE - D.zR) * D.archA, ba = (sa.T - sa.B) / 2, aa = sa.a;
          if (k === 0 || k === NR) { aa = 0; ba = 0; }
          for (i = 0; i <= NA; i++) { var pa = phis[i % NA], ea = 2 / (Math.cos(pa) > 0 ? sa.nb : sa.n), rr = D.archR - ba * spow(Math.cos(pa), ea); o = (k * C + i) * 3; P[o] = aa * spow(Math.sin(pa), ea); P[o + 1] = rr * Math.cos(th); P[o + 2] = rr * Math.sin(th); }
          continue;
        }
        var s = catSect(D, zz, mode), cy = (s.T + s.B) / 2, b = (s.T - s.B) / 2, a = s.a, e;
        if (k === 0 || k === NR) { a = 0; b = 0; }
        for (i = 0; i <= NA; i++) { var p = phis[i % NA]; e = 2 / (Math.cos(p) > 0 ? s.nb : s.n); o = (k * C + i) * 3; P[o] = a * spow(Math.sin(p), e); P[o + 1] = cy - b * spow(Math.cos(p), e); P[o + 2] = zz; }
      }
      return { P: P, N: gridNormals(P, NR, NA, new Float64Array(P.length)) };
    }
    var base = fill(0), chain = ['hip', 'body', 'chest', 'neck', 'head'], bz = [D.zb1, D.zb2, D.zb3, D.zb4], bw = [D.bw, D.bw, D.bwn, D.bwn];
    function wz(zz) { return chainW(chain, bz, bw, zz); }
    return { P: base.P, N: base.N, NR: NR, NA: NA, zs: zs, us: us, phis: phis, flip: gridFlip(base.P, base.N, NR, NA), M: [fill(1), fill(2), fill(3)], W: function (k) { return wz(zs[k]); }, wz: wz, nc: nc, nf: nf };
  }
  function buildCat(S, B) {
    var D = catDims(S), NA = 44, L = D.L, hh = D.hh, i;
    B.joint('body', null); B.joint('chest', 'body', 0, 0, D.zb2); B.joint('hip', 'body', 0, 0, D.zb1);
    B.joint('neck', 'chest', 0, hh * 0.3, D.zb3 - D.zb2); B.joint('head', 'neck', 0, D.hy * 0.85 - hh * 0.3, D.zb4 - D.zb3);
    var G = catBody(D, NA), zs = G.zs, NR = G.NR;
    // charts: rump disc | bands of the unrolled tube (one block, no seams between them) | face disc
    function ringAt(z) { var b = 0; for (var k = 0; k <= NR; k++) if (Math.abs(zs[k] - z) < Math.abs(zs[b] - z)) b = k; return b; }
    var kc0 = capCut(G, false), kc1 = capCut(G, true), cuts = [kc0, ringAt(D.zb1), ringAt(D.zb2), ringAt(D.zb3 - D.bwn), ringAt(D.zb4), kc1], names = ['hips', 'belly', 'chest', 'neck', 'head'], W = 0, k;
    function uw(i) { return Math.cos((G.phis[i] + G.phis[i + 1]) / 2) > 0.3 ? 0.55 : 1; } // the underside gets about half the texel density: the big top plane is the canvas
    for (k = kc0; k <= kc1; k++) { var per = 0; for (i = 0; i < NA; i++) { var a = (k * (NA + 1) + i) * 3; per += Math.hypot(G.P[a + 3] - G.P[a], G.P[a + 4] - G.P[a + 1], G.P[a + 5] - G.P[a + 2]) * uw(i); } W = Math.max(W, per); }
    B.gridChart('rump', G, 0, kc0, 'planar', { ax: [0, 1], flip: true, dens: 1.2, anchor: [0, 0, D.zR] });
    for (i = 0; i < 5; i++) if (cuts[i + 1] > cuts[i]) B.gridChart(names[i], G, cuts[i], cuts[i + 1], 'unroll', { width: W, block: 1, uw: uw });
    B.gridChart('face', G, kc1, NR, 'planar', { ax: [0, 1], dens: 1.2, anchor: [0, D.hy, D.zF] });
    // legs: straight down from a pivot buried in the body, rounded sole
    var H = D.H, rL = D.rL, rP = D.rP, footH = Math.min(0.05, D.leg * 0.45), rc = Math.min(0.02, rP * 0.4, footH * 0.4);
    function legRings(side, zdir) { // local frame: pivot at the origin (just inside the belly), belly line at y = -emb, sole at y = -H
      var R = [], j, n, fz = Math.min(0.045, D.leg * 0.35), yb = -D.emb, y0 = yb - fz, fl = 0.22, top = Math.min(0.05, D.hh * 0.5);
      function ring(y, r, cz, k) { // a small fillet where the leg leaves the body, towards the middle of the body only (never outwards)
        var u = clamp((y - y0) / fz, 0, 1), m = 1 + fl * u * u; k = k == null ? 1 : k;
        R.push({ y: y, rx: r * k * (1 + (m - 1) * 0.5), rz: r * k * (1 + (m - 1) * 0.5), cx: -side * r * (m - 1) * 0.5, cz: (cz || 0) + zdir * r * (m - 1) * 0.5, e: D.lsq });
      }
      R.push({ y: top, rx: 0, rz: 0, e: 2 }); ring(top * 0.85, rL, 0, 0.55); ring(top * 0.45, rL, 0, 0.92); ring(0, rL);
      for (j = 0; j < 4; j++) ring(lerp(yb, y0, j / 4), rL);
      n = Math.max(1, Math.ceil((H - footH + y0) / 0.04)); for (j = 0; j <= n; j++) ring(lerp(y0, -(H - footH), j / n), rL);
      ring(-(H - footH * 0.45), lerp(rL, rP, 0.8), (rP - rL) * 0.9);
      for (j = 0; j <= 3; j++) { var be = j / 3 * PI / 2; ring(-H + rc * (1 - Math.sin(be)), rP - rc * (1 - Math.cos(be)), (rP - rL) * 1.2); }
      R.push({ y: -H, rx: 0, rz: 0, cz: (rP - rL) * 1.2, e: 2 });
      return R;
    }
    [['shL', 'elL', 'chest', -1, D.zf, 'legFL'], ['shR', 'elR', 'chest', 1, D.zf, 'legFR'], ['hpL', 'knL', 'hip', -1, D.zh, 'legHL'], ['hpR', 'knR', 'hip', 1, D.zh, 'legHR']].forEach(function (lg) {
      var pj = B.jmap[lg[2]], px = lg[3] * D.xl, py = -hh + D.emb, pz = lg[4];
      var up = B.joint(lg[0], lg[2], px, py, pz - pj.w.elements[14]); B.joint(lg[1], lg[0], 0, -H * 0.5, 0);
      var g = tubeGrid(up.w, legRings(lg[3], lg[2] === 'chest' ? -1 : 1), 14, lg[3] > 0 ? PI : 0, function (r) {
        var t = sstep(-H * 0.5 - H * 0.2, -H * 0.5 + H * 0.2, r.y);
        return t > 0.999 ? [[lg[0], 1]] : t < 0.001 ? [[lg[1], 1]] : [[lg[0], t], [lg[1], 1 - t]];
      });
      B.gridChart(lg[5], g, 0, g.NR, 'unroll', { dens: 0.85, anchor: [px, py, pz], inner: true, joint: lg[0] });
    });
    // tail: four joints, straight in the bind pose, pointing up and back
    var T = S.tail, tl = Math.max(0.05, T.len), tb = Math.min(0.05, D.rcap + 0.02), seg = tl / 4, r0 = T.r0, r1 = T.r1, tf = T.flat || 1;
    B.joint('t0', 'hip', 0, T.y != null ? T.y : hh * 0.5, D.zR + Math.min(0.05, D.rcap + 0.02) - D.zb1, T.up, 0, 0);
    for (i = 1; i < 4; i++) B.joint('t' + i, 't' + (i - 1), 0, -seg, 0);
    var TR = [{ y: tb, rx: 0, rz: 0 }], nt = Math.max(6, Math.ceil(tl / 0.035));
    TR.push({ y: tb * 0.9, rx: r0 * 0.7, rz: r0 * 0.7 });
    for (i = 0; i <= nt; i++) { var u = i / nt, rr = T.bushy ? r0 + (r1 - r0) * Math.sin(u * PI * 0.75) : lerp(r0, r1, u); TR.push({ y: -(tl - r1) * u, rx: rr, rz: rr }); }
    var re = TR[TR.length - 1].rx; for (i = 1; i <= 3; i++) { var bt = i / 3 * PI / 2; TR.push({ y: -(tl - r1) - r1 * Math.sin(bt), rx: re * Math.cos(bt), rz: re * Math.cos(bt) }); }
    TR.forEach(function (r) { r.rz *= tf; });
    var tg = tubeGrid(B.jmap.t0.w, TR, 10, -PI / 2, function (r) { return chainW(['t0', 't1', 't2', 't3'], [seg, seg * 2, seg * 3], [seg * 0.32, seg * 0.32, seg * 0.32], -r.y); });
    var tp = new THREE.Vector3().setFromMatrixPosition(B.jmap.t0.w);
    B.gridChart('tail', tg, 0, tg.NR, 'unroll', { dens: 0.8, anchor: [tp.x, tp.y, tp.z], inner: true, joint: 't0' });
    // ears: thin plates
    var E = S.ear, hj = B.jmap.head.w.elements;
    [-1, 1].forEach(function (s) {
      var ex = s * E.spread * D.hW * 0.86, sc = catSect(D, D.zH - D.hD * 0.1, 0), ey = sc.B + (sc.T - sc.B) * 0.5 + (sc.T - sc.B) * 0.5 * Math.pow(Math.max(0, 1 - Math.pow(Math.abs(ex) / sc.a, sc.n)), 1 / sc.n) - 0.007, ez = D.zH - D.hD * 0.1;
      var ej = B.joint(s < 0 ? 'earL' : 'earR', 'head', ex - hj[12], ey - hj[13], ez - hj[14], E.type === 'fold' ? 55 : 0, s * 24, -s * E.tilt);
      var R = [], ne = 5, th = Math.max(0.008, E.w * 0.16), j;
      R.push({ y: -0.012, rx: E.w, rz: th });
      for (j = 0; j <= ne; j++) { var t = j / ne, w = E.type === 'round' || E.type === 'fold' || E.type === 'tab' || E.type === 'flop' ? E.w * Math.sqrt(Math.max(0, 1 - t * t * 0.96)) : E.w * (Math.pow(1 - t, 0.82) * 0.94 + 0.06); R.push({ y: 0.004 + (E.h - 0.004) * t, rx: w, rz: th * (1 - 0.55 * t) }); }
      R.push({ y: E.h + th * 0.5, rx: 0, rz: 0 });
      R.forEach(function (r) { r.e = 2; });
      var g = tubeGrid(ej.w, R, 10, 0, function () { return [[ej.name, 1]]; });
      B.gridChart(s < 0 ? 'earL' : 'earR', g, 0, g.NR, 'unroll', { dens: 0.8, anchor: [ex, ey, ez], inner: false, joint: ej.name });
    });
    B.D = D; B.body = G;
    // where the simple face and the blaster go (dogs), and the anchors the game can ask for
    var fs = catSect(D, D.zH + D.hD * 0.15, 0), fx = fs.a * 0.5, fy = (fs.T + fs.B) / 2 + (fs.T - fs.B) / 2 * Math.pow(Math.max(0, 1 - Math.pow(fx / fs.a, fs.n)), 1 / fs.n), ns = catSect(D, D.zF - D.fcap * 0.18, 0);
    D.eyeP = [fx, fy - 0.004, D.zH + D.hD * 0.15]; D.noseP = [0, ns.T - 0.006, D.zF - D.fcap * 0.2]; D.mouthP = [0, (ns.T + ns.B) / 2 - (ns.T - ns.B) * 0.2, D.zF - 0.012]; D.gunY = hh; D.muzzleP = [0, hh + 0.066, 0.26];
    D.shoulder = D.leg + 2 * hh; D.top = D.leg + hh + D.hy + D.hH; D.eye = D.leg + hh + D.hy + D.hH * 0.4;
    return D;
  }

  /* ---------- jelly figures ----------
     one continuous skin for body + head (a tube of rings along y whose radius is the smooth union of the two circles), with arms, feet,
     ears (and a dog's snout) as small tubes on their own joints. Joint names match the mat cats, so poses and animation keep working. */
  function buildHuman(S, B) {
    var u = 1 / 1.5, G0 = S.girth || 1, H0 = S.height || 1, i, D = {}; // figures are built in metres and stored in plan units (the game scales everything by 1.5)
    function m(v) { return v * u; }
    B.MP = [{}, {}, {}]; B.MN = [{}, {}, {}];
    var hipY = m(0.84 * H0), yN = m(0.52 * H0), hcY = m(0.68 * H0), hR = m(0.152 * H0);
    B.joint('body', null); B.joint('hip', 'body', 0, m(-0.05), 0); B.joint('chest', 'body', 0, m(0.22 * H0), 0);
    B.joint('neck', 'chest', 0, yN - m(0.22 * H0), 0); B.joint('head', 'neck', 0, hcY - yN - m(0.03), 0);
    // torso keys [y, half width, half depth] in metres from the pelvis centre
    var K = [[-0.19, 0, 0], [-0.165, 0.15, 0.11], [-0.09, 0.212, 0.148], [0.04, 0.2, 0.142], [0.18, 0.19, 0.134], [0.26, 0.228, 0.13], [0.32, 0.262, 0.124], [0.375, 0.25, 0.116], [0.425, 0.198, 0.106], [0.465, 0.15, 0.1], [0.5, 0.116, 0.097], [0.53, 0.1, 0.095], [0.57, 0.1, 0.1]]; // the original's figure: a soft inflated body, sloping shoulders flowing into a short thick neck, a big round head
    function key(y, c) { var yy = y / u / H0; if (yy <= K[0][0] || yy >= K[K.length - 1][0] + 0.03) return 0; for (var j = 0; j < K.length - 1; j++) if (yy <= K[j + 1][0]) { var a = K[j], b = K[j + 1], t = (yy - a[0]) / (b[0] - a[0]), w = t * t * (3 - 2 * t); var gf = 1 + ((c === 1 ? G0 : Math.sqrt(G0)) - 1) * (1 - sstep(0.4, 0.5, yy)); return m(lerp(a[c], b[c], w)) * gf; } return m(K[K.length - 1][c]); }
    function smax(a, b, k) { var h = Math.max(k - Math.abs(a - b), 0) / k; return Math.max(a, b) + h * h * k * 0.25; }
    function head(y, c) { var d = (y - hcY) / hR; if (Math.abs(d) >= 1) return 0; var r = Math.sqrt(1 - d * d), egg = 1 - 0.02 * d; return m(c === 1 ? 0.15 : 0.148) * H0 * r * egg; }
    var y0 = m(-0.19 * H0), y1 = hcY + hR, NRg = 80, rings = [];
    for (i = 0; i <= NRg; i++) { var t = i / NRg, y = y0 + (y1 - y0) * (0.5 - 0.5 * Math.cos(PI * t)), end = i === 0 || i === NRg;
      rings.push({ y: y, rx: end ? 0 : Math.max(0.002, smax(key(y, 1), head(y, 1), m(0.06))), rz: end ? 0 : Math.max(0.002, smax(key(y, 2), head(y, 2), m(0.06))), e: 2 }); }
    var chain = ['hip', 'body', 'chest', 'neck', 'head'], bz = [m(-0.12), m(0.06), m(0.3) * H0, hcY - m(0.06)], bw = [m(0.08), m(0.1), m(0.08), m(0.05)];
    var GT = tubeGrid(B.jmap.body.w, rings, 48, -PI / 2, function (rg) { return chainW(chain, bz, bw, rg.y); });
    var kb = 8, kt = NRg - 10;
    B.gridChart('bottom', GT, 0, kb, 'planar', { ax: [0, 2], flip: true, dens: 0.8 });
    B.gridChart('body', GT, kb, kt, 'unroll', { dens: 1.15 });
    B.gridChart('top', GT, kt, NRg, 'planar', { ax: [0, 2], dens: 1.1 });
    function tube(jn, name, prof, k2, wfn, M) {
      var R = prof.map(function (p) { return { y: p[0], rx: p[1], rz: p[1] * (p[2] || 1), e: 2 }; });
      var g = tubeGrid(M || B.jmap[jn].w, R, 16, 0, wfn || function () { return [[jn, 1]]; });
      B.gridChart(name, g, 0, g.NR, 'unroll', { dens: k2 || 0.9 }); return g;
    }
    function blend(a, b, y0b, y1b) { return function (rg) { var w = sstep(y0b, y1b, rg.y); return w > 0.999 ? [[a, 1]] : w < 0.001 ? [[b, 1]] : [[a, w], [b, 1 - w]]; }; }
    // arms: shoulder -> elbow 0.29 -> wrist 0.56 -> mitten tip 0.72 (metres), hanging a little out from the body
    var uA = m(0.24 * H0), fA = m(0.2 * H0), hA = m(0.13 * H0), aR = m(0.085) * Math.sqrt(G0);
    [['shL', 'elL', -1, 'armL'], ['shR', 'elR', 1, 'armR']].forEach(function (A) {
      B.joint(A[0], 'chest', A[2] * m(0.2) * G0, m(0.07 * H0), 0, 0, 0, A[2] * 8); /* the arm top sits inside the sloping shoulder, so the shoulder flows into the arm */ B.joint(A[1], A[0], 0, -uA, 0);
      var P = [[m(0.1), 0], [m(0.088), aR * 0.62], [m(0.06), aR * 1.02], [m(0.02), aR * 1.12], [-uA * 0.3, aR * 1.0], [-uA * 0.6, aR * 0.92], [-uA, aR * 0.8], [-uA - fA * 0.45, aR * 0.84], [-uA - fA, aR * 0.8], [-uA - fA - hA * 0.3, aR * 0.92, 0.8], [-uA - fA - hA * 0.62, aR * 0.88, 0.78], [-uA - fA - hA * 0.9, aR * 0.6, 0.78], [-uA - fA - hA, 0]];
      tube(A[0], A[3], P, 0.9, blend(A[0], A[1], -uA * 1.12, -uA * 0.82));
    });
    // legs: hip -> knee 0.41 -> ankle 0.80, a rounded foot forward
    var tL = m(0.39 * H0), sL = m(0.36 * H0), lR = m(0.118) * Math.sqrt(G0);
    [['hpL', 'knL', -1, 'legL', 'footL'], ['hpR', 'knR', 1, 'legR', 'footR']].forEach(function (F) {
      B.joint(F[0], 'hip', F[2] * m(0.098) * G0, m(-0.04), 0); B.joint(F[1], F[0], 0, -tL, 0);
      var P = [[m(0.09), 0], [m(0.075), lR * 0.6], [m(0.045), lR * 0.9], [0, lR], [-tL * 0.5, lR * 0.86], [-tL, lR * 0.68], [-tL - sL * 0.3, lR * 0.8], [-tL - sL * 0.8, lR * 0.74], [-tL - sL, lR * 0.72], [-tL - sL - m(0.045), lR * 0.45], [-tL - sL - m(0.06), 0]];
      tube(F[0], F[3], P, 0.9, blend(F[0], F[1], -tL * 1.12, -tL * 0.85));
      var fm = B.jmap[F[1]].w.clone().multiply(new THREE.Matrix4().makeTranslation(0, -sL + m(0.01), -m(0.05))).multiply(new THREE.Matrix4().makeRotationX(-PI / 2));
      tube(F[1], F[4], [[m(0.03), 0], [m(0.01), m(0.075), 0.7], [-m(0.04), m(0.08), 0.66], [-m(0.09), m(0.07), 0.62], [-m(0.12), m(0.045), 0.6], [-m(0.135), 0]], 0.8, null, fm);
    });
    B.joint('t0', 'hip', 0, 0, -m(0.1), 90, 0, 0); for (i = 1; i < 4; i++) B.joint('t' + i, 't' + (i - 1), 0, -0.01, 0);
    var groundY = -hipY;
    D.L = m(0.22); D.leg = hipY; D.tuck = 0.02; D.hy = hcY; D.hH = hR; D.zH = 0; D.hW = m(0.1); D.hD = m(0.11); D.zF = m(0.11); D.hh = hipY; D.dog = S.kind === 'dog'; D.dp = 0.7; D.Rb = m(0.17); D.human = true;
    D.eyeP = [m(0.04), hcY + m(0.02), m(0.1)]; D.noseP = [0, hcY, m(0.11)]; D.mouthP = [0, hcY - m(0.05), m(0.1)];
    D.gunY = m(0.18); D.gunZ = m(0.2); D.muzzleP = [0, D.gunY + 0.066, D.gunZ + 0.26];
    D.shoulder = m(0.4); D.top = y1; D.eye = hcY + m(0.02); D.zb3 = 0; D.vol = m(0.07) * 1.5 * 1.5; D.ground = groundY;
    B.D = D; B.body = GT;
    return D;
  }
  function buildJelly(S, B) {
    var Rb = S.Rb, Rh = S.Rh, hc = S.hc, kN = S.neck, dog = S.kind === 'dog', i, D = {}, W = S.wide || 1, RbY = Rb * (S.tall || 1), dp = S.depth; // owner 2026-11-26: flatter, wider and a little taller than a ball
    B.MP = [{}, {}, {}]; B.MN = [{}, {}, {}]; // no shape targets
    var yN = hc - Rh * 0.82, yH = hc - Rh * 0.45;
    B.joint('body', null); B.joint('hip', 'body', 0, -0.1, 0); B.joint('chest', 'body', 0, 0.06, 0);
    B.joint('neck', 'chest', 0, yN - 0.06, 0); B.joint('head', 'neck', 0, yH - yN, 0);
    function smax(a, b, k) { var h = Math.max(k - Math.abs(a - b), 0) / k; return Math.max(a, b) + h * h * k * 0.25; }
    function rad(y) { var a = Math.abs(y) < RbY ? Rb * Math.sqrt(1 - y * y / (RbY * RbY)) : RbY - Math.abs(y), d = y - hc, b = Math.abs(d) < Rh ? Math.sqrt(Rh * Rh - d * d) : -Rh + (Rh - Math.abs(d)); return Math.max(0, smax(a, b, kN)); }
    var y0 = -RbY, y1 = hc + Rh, NRg = 64, rings = [];
    for (i = 0; i <= NRg; i++) { var t = i / NRg, y = y0 + (y1 - y0) * (0.5 - 0.5 * Math.cos(PI * t)), r = (i === 0 || i === NRg) ? 0 : rad(y); rings.push({ y: y, rx: r * W, rz: r * dp, e: 2 }); }
    var chain = ['hip', 'body', 'chest', 'neck', 'head'], bz = [-0.12, 0.05, yN - 0.015, yH], bw = [0.06, 0.07, 0.05, 0.04];
    var G = tubeGrid(B.jmap.body.w, rings, 44, -PI / 2, function (rg) { return chainW(chain, bz, bw, rg.y); });
    var kb = 9, kt = NRg - 10;
    B.gridChart('bottom', G, 0, kb, 'planar', { ax: [0, 2], flip: true, dens: 0.8 });
    B.gridChart('body', G, kb, kt, 'unroll', { dens: 1.15 });
    B.gridChart('top', G, kt, NRg, 'planar', { ax: [0, 2], dens: 1.1 });
    // a small tube on a joint, pointing down its -y: rings [y, r] then a round end
    function tube(jn, name, prof, k2, wfn, M) {
      var R = prof.map(function (p) { return { y: p[0], rx: p[1], rz: p[1] * (p[2] || 1), e: 2 }; });
      var g = tubeGrid(M || B.jmap[jn].w, R, 14, 0, wfn || function () { return [[jn, 1]]; });
      B.gridChart(name, g, 0, g.NR, 'unroll', { dens: k2 || 0.9 }); return g;
    }
    function capProf(L, r0, r1, top) { var P = [[top, 0], [top * 0.6, r0 * 0.75], [0, r0]], n = 5, j; for (j = 1; j <= n; j++) P.push([-(L - r1) * j / n, lerp(r0, r1, j / n)]); for (j = 1; j <= 4; j++) { var be = j / 4 * PI / 2; P.push([-(L - r1) - r1 * Math.sin(be), r1 * Math.cos(be)]); } P[P.length - 1][1] = 0; return P; }
    // arms: from the sides of the body, tilted outwards; elbow half way
    var aL = S.arm, aR = S.armR, ay = RbY * 0.42, ax = Rb * Math.sqrt(1 - 0.42 * 0.42) * 0.9 * W, az = 0.01;
    [['shL', 'elL', -1, 'armL'], ['shR', 'elR', 1, 'armR']].forEach(function (A) {
      var sj = B.joint(A[0], 'chest', A[2] * ax, ay - 0.06, az, 0, 0, A[2] * 48); B.joint(A[1], A[0], 0, -aL * 0.48, 0);
      tube(A[0], A[3], capProf(aL, aR, aR * 1.08, 0.035).map(function (q) { return [q[0], q[1], 0.82]; }), 0.9, function (rg) { var w = sstep(-aL * 0.62, -aL * 0.34, rg.y); return w > 0.999 ? [[A[0], 1]] : w < 0.001 ? [[A[1], 1]] : [[A[0], w], [A[1], 1 - w]]; });
    });
    // feet: stubby, just poking out under the body
    var fr = S.foot;
    [['hpL', 'knL', -1, 'footL'], ['hpR', 'knR', 1, 'footR']].forEach(function (F) {
      B.joint(F[0], 'hip', F[2] * Rb * 0.5 * W, -RbY + Rb * 0.28 + 0.1, 0.03); B.joint(F[1], F[0], 0, -0.03, 0);
      tube(F[0], F[3], [[0.045, 0], [0.03, fr * 0.7, 0.8], [0, fr, 0.8], [-0.03, fr * 1.02, 0.8], [-0.05, fr * 0.92, 0.8], [-0.065, fr * 0.6, 0.8], [-0.074, 0]], 0.8);
    });
    // no tail: the joints are there for the animation code, with nothing on them
    B.joint('t0', 'hip', 0, 0.05, -Rb * dp * 0.9, 90, 0, 0); for (i = 1; i < 4; i++) B.joint('t' + i, 't' + (i - 1), 0, -0.012, 0);
    // ears
    var E = S.ear, flop = E.type === 'flop', round = E.type === 'round';
    [-1, 1].forEach(function (s) {
      var ex = s * Rh * E.spread * W, ey = flop ? hc + Rh * 0.35 : hc + Math.sqrt(Math.max(0, Rh * Rh - ex * ex / (W * W))) - 0.012, ez = -0.01, nm = s < 0 ? 'earL' : 'earR', hj = B.jmap.head.w.elements;
      var ej = B.joint(nm, 'head', ex - hj[12], ey - hj[13], ez - hj[14], 0, 0, -s * (flop ? E.tilt : E.tilt));
      var P = [[-0.02, 0]], n = 6, j; for (j = 0; j <= n; j++) { var t2 = j / n, w = round ? E.w * Math.sqrt(Math.max(0, 1 - t2 * t2 * 0.92)) : E.w * (Math.pow(1 - t2, 0.85) * 0.9 + 0.1 * (1 - t2)); P.push([-0.01 + (E.h + 0.01) * t2, w, flop ? 0.38 : 0.55]); }
      P.push([E.h + 0.008, 0]);
      tube(nm, nm, P, 0.8);
    });
    if (dog) { // snout: a short soft tube forward from the face
      var hm = B.jmap.head.w.clone().multiply(new THREE.Matrix4().makeTranslation(0, hc - 0.035 - yH, Rh * dp * 0.8)).multiply(new THREE.Matrix4().makeRotationX(-PI / 2));
      tube('head', 'snout', [[0.01, 0], [0, 0.05], [-0.03, 0.058], [-S.snout + 0.03, 0.054], [-S.snout + 0.012, 0.042], [-S.snout, 0]], 0.9, null, hm);
    }
    D.L = 2 * Rb; D.leg = 0.18; D.tuck = 0.03; D.hy = hc; D.hH = Rh; D.zH = 0; D.hW = Rh * W; D.hD = Rh * dp; D.zF = Rh * dp + (dog ? S.snout : 0); D.hh = RbY * 0.9; D.dog = dog; D.dp = dp; D.Rb = Rb;
    D.eyeP = [Rh * 0.38 * W, hc + 0.035, Rh * dp * 0.97]; D.noseP = [0, hc - 0.035, Rh * dp * 0.8 + (dog ? S.snout : 0.2) - 0.004]; D.mouthP = [0, hc - 0.075, Rh * dp * 0.8 + (dog ? S.snout * 0.6 : 0.2)];
    D.gunY = -0.04; D.gunZ = Rb * dp + 0.05; D.muzzleP = [0, D.gunY + 0.066, D.gunZ + 0.26];
    D.shoulder = Rb + ay; D.top = hc + Rh; D.eye = hc + 0.035; D.zb3 = 0; D.vol = 4 / 3 * PI * (Rb * Rb * RbY + Rh * Rh * Rh * 0.8) * W * dp;
    B.D = D; B.body = G;
    return D;
  }

  /* ---------- dogs: lathe parts on rigid joints (the older look) ---------- */
  function lathe(B, name, jn, o) {
    var tw = o.tw || 96, th = o.th || 64, su = o.su || 20, sv = o.sv || 12, sx = o.sx || 1, sz = o.sz || 1, prof = o.prof, g = 4;
    var m = new THREE.Matrix4().compose(new THREE.Vector3().fromArray(o.pos || [0, 0, 0]), new THREE.Quaternion().setFromEuler(new THREE.Euler((o.rot ? o.rot[0] : 0) * D2R, (o.rot ? o.rot[1] : 0) * D2R, (o.rot ? o.rot[2] : 0) * D2R)), new THREE.Vector3(1, 1, 1));
    var M = B.jmap[jn].w.clone().multiply(m), v = new THREE.Vector3(), n3 = new THREE.Matrix3().setFromMatrix4(M);
    function pos(u, vv, out) { var a = u * PI * 2, p = prof(vv < 0 ? 0 : vv > 1 ? 1 : vv); out[0] = p[0] * Math.sin(a) * sx; out[1] = p[1]; out[2] = p[0] * Math.cos(a) * sz; }
    var t = [0, 0, 0], t1 = [0, 0, 0], t2 = [0, 0, 0], i, j, mn = [1e9, 1e9, 1e9], mx = [-1e9, -1e9, -1e9], loc = [];
    var ch = B.chart(name, tw - 2 * g, th - 2 * g, { fixed: 1 }), base = B.P.length / 3;
    for (j = 0; j <= sv; j++) for (i = 0; i <= su; i++) {
      var u = i / su, vv = j / sv; pos(u, vv, t); loc.push(t[0], t[1], t[2]);
      for (var q = 0; q < 3; q++) { mn[q] = Math.min(mn[q], t[q]); mx[q] = Math.max(mx[q], t[q]); }
      var px = t[0], py = t[1], pz = t[2], v2 = Math.min(Math.max(vv, 0.004), 0.996);
      pos(u + 0.002, v2, t1); pos(u - 0.002, v2, t2); var ax = t1[0] - t2[0], ay = t1[1] - t2[1], az = t1[2] - t2[2];
      pos(u, v2 + 0.003, t1); pos(u, v2 - 0.003, t2); var bx = t1[0] - t2[0], by = t1[1] - t2[1], bz = t1[2] - t2[2];
      var nx = ay * bz - az * by, ny = az * bx - ax * bz, nz = ax * by - ay * bx, l = Math.hypot(nx, ny, nz);
      if (l < 1e-9) { nx = 0; ny = vv < 0.5 ? -1 : 1; nz = 0; l = 1; }
      v.set(px, py, pz).applyMatrix4(M); var P3 = [v.x, v.y, v.z]; v.set(nx / l, ny / l, nz / l).applyMatrix3(n3).normalize();
      B.vert(P3, [v.x, v.y, v.z], [[jn, 1]], u * (tw - 2 * g), vv * (th - 2 * g), ch.id);
    }
    for (j = 0; j < sv; j++) for (i = 0; i < su; i++) { var a = base + j * (su + 1) + i, b = a + 1, c = a + su + 1, d = c + 1; B.I.push(a, b, c, b, d, c); }
    B.end(ch);
    var cx = (mn[0] + mx[0]) / 2, cy = (mn[1] + mx[1]) / 2, cz = (mn[2] + mx[2]) / 2, r = 0;
    for (i = 0; i < loc.length; i += 3) r = Math.max(r, Math.hypot(loc[i] - cx, loc[i + 1] - cy, loc[i + 2] - cz));
    v.set(0, 0, 0).applyMatrix4(M); ch.o = [v.x, v.y, v.z]; ch.r0 = r;
    return ch;
  }
  function dogCtx(S) {
    var dog = S.kind === 'dog', HR = S.headR, c = { nUp: dog ? 52 : 40, nl: S.neck, HR: HR, hc: [0, HR * 0.5, HR * 0.3], Rx: HR * S.headSx, Ry: HR * S.headSy, Rz: HR * 0.96 };
    c.mz = [0, c.hc[1] - HR * (dog ? 0.2 : 0.3), c.hc[2] + c.Rz * (dog ? 0.62 : 0.8)];
    c.onHead = function (dx, dy, dz, k) { var l = Math.hypot(dx, dy, dz); k = k || 1; return [c.hc[0] + dx / l * c.Rx * k, c.hc[1] + dy / l * c.Ry * k, c.hc[2] + dz / l * c.Rz * k]; };
    return c;
  }
  function buildDog(S, B) {
    var L = S.len, dog = S.kind === 'dog', X = dogCtx(S), HR = X.HR, hc = X.hc, mz = X.mz, i;
    function J(n, p, x, y, z, rx, ry, rz) { return B.joint(n, p, x, y, z, rx, ry, rz); }
    function part(n, j, o) { return lathe(B, n, j, o); }
    J('body', null);
    part('belly', 'body', { prof: ell(S.bellyR, L * 0.36), rot: [90, 0, 0], sz: 0.95, tw: 320, th: 224, su: 28, sv: 16 });
    J('chest', 'body', 0, 0, L * 0.18);
    part('chest', 'chest', { prof: ell(S.chestR, L * 0.27), rot: [90, 0, 0], pos: [0, 0.005, L * 0.07], sz: 1.0, tw: 320, th: 224, su: 28, sv: 16 });
    J('hip', 'body', 0, 0, -L * 0.18);
    part('hips', 'hip', { prof: ell(S.hipR, L * 0.27), rot: [90, 0, 0], pos: [0, 0, -L * 0.07], sz: 1.0, tw: 320, th: 224, su: 28, sv: 16 });
    J('neck', 'chest', 0, S.chestR * 0.42, L * 0.20);
    var nl = S.neck, nr = Math.min(S.chestR * 0.66, S.headR * 0.72), nUp = X.nUp;
    part('neck', 'neck', { prof: cap(nl + 0.02, nr * 0.9, nr * 1.05), rot: [180 - (90 - nUp), 0, 0], pos: [0, -0.01, -0.01], tw: 128, th: 80 });
    J('head', 'neck', 0, nl * Math.sin(nUp * D2R), nl * Math.cos(nUp * D2R));
    part('head', 'head', { prof: ell(HR, X.Ry), sx: S.headSx, sz: 0.96, pos: hc, tw: 384, th: 256, su: 32, sv: 20 });
    if (dog) part('muzzle', 'head', { prof: ell(S.muzzleR, S.muzzleL + S.muzzleR * 0.35), rot: [96, 0, 0], sx: 1.0, sz: 0.82, pos: [mz[0], mz[1], mz[2] + S.muzzleL * 0.45], tw: 128, th: 96, su: 18, sv: 10 });
    else [-1, 1].forEach(function (s) { part('pad' + (s < 0 ? 'L' : 'R'), 'head', { prof: ell(S.muzzleR * 0.62, S.muzzleR * 0.5), sz: 0.8, pos: [s * S.muzzleR * 0.46, mz[1], mz[2] + S.muzzleL * 0.3], tw: 64, th: 48, su: 14, sv: 8 }); });
    if (S.underbite) part('jaw', 'head', { prof: ell(S.muzzleR * 0.86, S.muzzleR * 0.5), sx: 1.15, pos: [0, mz[1] - S.muzzleR * 0.52, mz[2] + S.muzzleL + S.muzzleR * 0.34], tw: 96, th: 64, su: 16, sv: 8 });
    if (S.jowl) [-1, 1].forEach(function (s) { part('jowl' + s, 'head', { prof: ell(S.muzzleR * 0.62, S.muzzleR * 0.8), pos: [s * S.muzzleR * 0.7, mz[1] - S.muzzleR * 0.34, mz[2] + S.muzzleL * 0.5 + S.muzzleR * 0.1], tw: 64, th: 48, su: 14, sv: 8 }); });
    var E = S.ear;
    [-1, 1].forEach(function (s) {
      var p = X.onHead(s * E.spread, E.type === 'flop' ? 0.45 : 0.82, E.type === 'flop' ? 0.0 : -0.05, E.type === 'flop' ? 0.9 : 0.86), en = s < 0 ? 'earL' : 'earR';
      J(en, 'head', p[0], p[1], p[2], E.type === 'fold' ? 62 : (E.type === 'flop' ? 0 : -6), 0, E.type === 'flop' ? -s * 168 : -s * E.tilt);
      part(en, en, { prof: cone(E.h, E.w, E.type === 'flop' ? 0.45 : E.type === 'round' ? 0.36 : 0.8), sz: 0.42, pos: [0, -0.012, 0], tw: 80, th: 64, su: 14, sv: 8 });
      if (S.pom && S.earPom !== false) part('earPom' + s, en, { prof: ell(0.07, 0.085), pos: [0, E.h * 0.85, 0], tw: 96, th: 64, su: 14, sv: 8 });
    });
    if (S.pom) part('topPom', 'head', { prof: ell(HR * 0.72, HR * 0.6), pos: [0, hc[1] + X.Ry * 0.82, hc[2] - HR * 0.1], tw: 128, th: 96, su: 16, sv: 10 });
    if (S.fluff) part('ruff', 'chest', { prof: ell(S.chestR * 0.9, S.chestR * 0.82), pos: [0, -S.chestR * 0.3, L * 0.3], sx: 1.05, tw: 192, th: 128, su: 20, sv: 12 });
    var legF = S.leg, hipDrop = S.hipR * 0.3, shDrop = S.chestR * 0.35, legR = legF + (shDrop - hipDrop), st = S.stance || 1;
    function leg(pref, parent, x, y, z, len, fat) {
      var up = len * 0.5, lo = Math.max(0.01, len * 0.5 - S.paw * 0.75), lj = pref.replace('sh', 'el').replace('hp', 'kn');
      J(pref, parent, x, y, z); part(pref + 'U', pref, { prof: cap(up, S.legRad * fat, S.legRad * 1.12), tw: 112, th: 80, su: 14, sv: 10 });
      J(lj, pref, 0, -up, 0); part(pref + 'D', lj, { prof: cap(lo, S.legRad * 1.1, S.paw), sz: 1.12, pos: [0, 0, S.paw * 0.12], tw: 112, th: 96, su: 14, sv: 10 });
      if (S.pom) part(pref + 'P', lj, { prof: ell(S.paw * 1.35, S.paw * 1.2), pos: [0, -lo * 0.55, 0], tw: 96, th: 64, su: 14, sv: 8 });
    }
    leg('shL', 'chest', -S.chestR * 0.52 * st, -shDrop, L * 0.12, legF, 1.5); leg('shR', 'chest', S.chestR * 0.52 * st, -shDrop, L * 0.12, legF, 1.5);
    leg('hpL', 'hip', -S.hipR * 0.56 * st, -hipDrop, -L * 0.13, legR, 1.9); leg('hpR', 'hip', S.hipR * 0.56 * st, -hipDrop, -L * 0.13, legR, 1.9);
    var T = S.tail, n = T.segs || 4, sl = T.len / n, parent = 'hip';
    for (i = 0; i < n; i++) {
      J('t' + i, parent, 0, i === 0 ? S.hipR * 0.42 : -sl, i === 0 ? -L * 0.30 : 0, i === 0 ? T.up : T.curl, 0, 0);
      var k0 = i / n, k1 = (i + 1) / n, ra, rb;
      if (T.bushy) { ra = T.r0 + (T.r1 - T.r0) * Math.sin(k0 * PI * 0.8); rb = T.r0 + (T.r1 - T.r0) * Math.sin(k1 * PI * 0.8) * (i === n - 1 ? 0.6 : 1); } else { ra = T.r0 + (T.r1 - T.r0) * k0; rb = T.r0 + (T.r1 - T.r0) * k1; }
      part('tail' + i, 't' + i, { prof: cap(sl, ra, rb), tw: 80, th: 64, su: 12, sv: 8 });
      parent = 't' + i;
    }
    if ((S.pom && !S.tailPomOff) || T.pom) part('tailPom', parent, { prof: ell(0.065, 0.065), pos: [0, -sl, 0], tw: 96, th: 64, su: 14, sv: 8 });
    B.tailN = n;
    return null;
  }

  /* ---------- finish: pack the atlas, typed arrays, texel map ---------- */
  function pack(B, ppu, A, g) {
    var blocks = {}, list = [], k;
    B.charts.forEach(function (c) {
      var p = c.fixed ? A / 1024 : ppu * c.dens;
      c.pw = Math.max(2, Math.round(c.w * p)); c.ph = Math.max(2, Math.round(c.h * p));
      var key = c.block >= 0 ? 'b' + c.block : 'c' + c.id; if (!blocks[key]) { blocks[key] = { charts: [], w: 0, h: 0 }; list.push(blocks[key]); }
      blocks[key].charts.push(c);
    });
    list.forEach(function (b) { b.w = 0; b.h = 2 * g; b.charts.forEach(function (c) { b.w = Math.max(b.w, c.pw + 2 * g); b.h += c.ph; }); });
    var order = list.slice().sort(function (a, b) { return b.h - a.h; }), x = 0, y = 0, sh = 0;
    for (k = 0; k < order.length; k++) {
      var b = order[k]; if (b.w > A) return false;
      if (x + b.w > A) { x = 0; y += sh; sh = 0; }
      b.x = x; b.y = y; x += b.w; sh = Math.max(sh, b.h);
      if (y + b.h > A) return false;
    }
    list.forEach(function (b) {
      var yy = b.y;
      b.charts.forEach(function (c, i) { var first = i === 0, last = i === b.charts.length - 1; c.rx = b.x; c.ry = yy; c.gx = g; c.gy = first ? g : 0; c.tw = b.w; c.th = c.ph + (first ? g : 0) + (last ? g : 0); c.pw2 = b.w - 2 * g; yy += c.th; });
    });
    return true;
  }
  var BPC = {};
  function blueprint(S, A) {
    var key = A + ':' + JSON.stringify(S); if (BPC[key]) return BPC[key];
    var B = new Builder(A), canvas = !S.legacy, D = canvas ? (S.human ? buildHuman(S, B) : S.jelly ? buildJelly(S, B) : buildCat(S, B)) : buildDog(S, B);
    var nv = B.P.length / 3, nt = B.I.length / 3, i, k, g = Math.max(2, Math.round((canvas ? 8 : 4) * (A || 1024) / 1024)), AA = A || 1024; // gutter: wide enough that distant mip levels do not pull in the neighbouring chart
    if (canvas) { var lo = 100, hi = 4000; for (i = 0; i < 18; i++) { var mid = (lo + hi) / 2; if (pack(B, mid, AA, g)) lo = mid; else hi = mid; } pack(B, lo, AA, g); B.ppu = lo; }
    else if (!pack(B, 0, AA, g)) console.warn('critter atlas full', S.name);
    var bp = { key: key, canvas: canvas, D: D, nv: nv, nt: nt, A: A, ppu: B.ppu || 0, tailN: canvas ? 4 : B.tailN };
    bp.pos = new Float32Array(B.P); bp.nrm = new Float32Array(B.N); bp.idx = nv > 65535 ? new Uint32Array(B.I) : new Uint16Array(B.I);
    bp.uv = new Float32Array(nv * 2); bp.si = new Uint16Array(nv * 4); bp.sw = new Float32Array(nv * 4);
    for (i = 0; i < nv; i++) {
      var c = B.charts[B.CH[i]], w = B.W[i].slice().sort(function (a, b) { return b[1] - a[1]; }).slice(0, 4), tot = 0;
      bp.uv[i * 2] = (c.rx + c.gx + B.ST[i * 2] * (c.pw / c.w)) / AA; bp.uv[i * 2 + 1] = (c.ry + c.gy + B.ST[i * 2 + 1] * (c.ph / c.h)) / AA;
      for (k = 0; k < w.length; k++) tot += w[k][1];
      for (k = 0; k < w.length; k++) { bp.si[i * 4 + k] = B.jmap[w[k][0]].i; bp.sw[i * 4 + k] = w[k][1] / tot; }
    }
    bp.joints = B.jd.map(function (j) { return { name: j.name, parent: j.parent, pos: j.pos, rot: j.rot }; });
    bp.inv0 = new Float64Array(B.jd.length * 16); B.jd.forEach(function (j, q) { bp.inv0.set(j.w.clone().invert().elements, q * 16); });
    bp.rest0 = new Float64Array(B.jd.length * 16); B.jd.forEach(function (j, q) { bp.rest0.set(j.w.elements, q * 16); });
    // shape targets as deltas; things that hang off the body (legs, tail, ears) ride along with the nearest piece of skin
    bp.morph = []; bp.shift = {};
    if (canvas) for (var m = 0; m < 3; m++) {
      var dp = new Float32Array(nv * 3), dn = new Float32Array(nv * 3), MP = B.MP[m], MN = B.MN[m], ids = Object.keys(MP);
      ids.forEach(function (vi) { vi = +vi; for (var q = 0; q < 3; q++) { dp[vi * 3 + q] = MP[vi][q] - bp.pos[vi * 3 + q]; dn[vi * 3 + q] = MN[vi][q] - bp.nrm[vi * 3 + q]; } });
      B.charts.forEach(function (ch) {
        if (!ch.anchor || MP[ch.v0]) return;
        var best = -1, bd = 1e9, a = ch.anchor, sh = [0, 0, 0], G = B.body, C = G.NA + 1, q;
        if (ch.inner !== false) { // legs and tail: carried by the middle of the nearest body ring, so that drawn in they end up inside whatever the body has become
          var kb = 0; for (var k2 = 0; k2 <= G.NR; k2++) if (Math.abs(G.zs[k2] - a[2]) < Math.abs(G.zs[kb] - a[2])) kb = k2;
          for (var i2 = 0; i2 < G.NA; i2++) for (q = 0; q < 3; q++) sh[q] += (G.M[m].P[(kb * C + i2) * 3 + q] - G.P[(kb * C + i2) * 3 + q]) / G.NA;
        } else { // ears: ride on the nearest piece of skin
          ids.forEach(function (vi) { vi = +vi; var d = Math.hypot(bp.pos[vi * 3] - a[0], bp.pos[vi * 3 + 1] - a[1], bp.pos[vi * 3 + 2] - a[2]); if (d < bd) { bd = d; best = vi; } });
          sh = [dp[best * 3], dp[best * 3 + 1], dp[best * 3 + 2]];
        }
        (bp.shift[ch.joint] = bp.shift[ch.joint] || [])[m] = sh; // the joint moves (not the vertices), so drawing the limb in still pulls it to the right place
      });
      bp.morph.push({ dp: dp, dn: dn });
    }
    bp.parts = B.charts.map(function (c) {
      var sv = [], n = c.v1 - c.v0, st = Math.max(1, Math.floor(n / 30));
      for (var q = c.v0 + (st >> 1); q < c.v1 && sv.length < 30; q += st) sv.push(q);
      return { name: c.name, rx: c.rx, ry: c.ry, tw: c.tw, th: c.th, v0: c.v0, v1: c.v1, i0: c.i0 / 3, i1: c.i1 / 3, sv: sv, o: c.o, r0: c.r0, tix: null, tb: null };
    });
    if (A) raster(bp);
    bp.charts = B.charts;
    return (BPC[key] = bp);
  }
  /* which triangle (and where in it) each texel of each chart shows; texels outside the chart copy their nearest texel inside */
  function raster(bp) {
    var A = bp.A, uv = bp.uv, idx = bp.idx;
    bp.parts.forEach(function (p) {
      var tw = p.tw, th = p.th, n = tw * th, tix = new Int32Array(n).fill(-1), tb = new Float32Array(n * 2), E = 1e-5, t, i, j;
      for (t = p.i0; t < p.i1; t++) {
        var a = idx[t * 3], b = idx[t * 3 + 1], c = idx[t * 3 + 2];
        var x0 = uv[a * 2] * A - p.rx, y0 = uv[a * 2 + 1] * A - p.ry, x1 = uv[b * 2] * A - p.rx, y1 = uv[b * 2 + 1] * A - p.ry, x2 = uv[c * 2] * A - p.rx, y2 = uv[c * 2 + 1] * A - p.ry;
        var den = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2); if (Math.abs(den) < 1e-9) continue;
        var i0 = Math.max(0, Math.floor(Math.min(x0, x1, x2) - 0.5)), i1 = Math.min(tw - 1, Math.ceil(Math.max(x0, x1, x2) - 0.5)), j0 = Math.max(0, Math.floor(Math.min(y0, y1, y2) - 0.5)), j1 = Math.min(th - 1, Math.ceil(Math.max(y0, y1, y2) - 0.5));
        for (j = j0; j <= j1; j++) for (i = i0; i <= i1; i++) {
          var px = i + 0.5, py = j + 0.5, w0 = ((y1 - y2) * (px - x2) + (x2 - x1) * (py - y2)) / den, w1 = ((y2 - y0) * (px - x2) + (x0 - x2) * (py - y2)) / den, w2 = 1 - w0 - w1;
          if (w0 >= -E && w1 >= -E && w2 >= -E) { var k = j * tw + i; tix[k] = t; tb[k * 2] = w1; tb[k * 2 + 1] = w2; }
        }
      }
      // nearest covered texel (two-pass chamfer)
      var dist = new Float32Array(n), src = new Int32Array(n), k2;
      for (k2 = 0; k2 < n; k2++) { dist[k2] = tix[k2] >= 0 ? 0 : 1e9; src[k2] = k2; }
      function relax(k, q, d) { if (dist[q] + d < dist[k]) { dist[k] = dist[q] + d; src[k] = src[q]; } }
      for (j = 0; j < th; j++) for (i = 0; i < tw; i++) { k2 = j * tw + i; if (i > 0) relax(k2, k2 - 1, 1); if (j > 0) { relax(k2, k2 - tw, 1); if (i > 0) relax(k2, k2 - tw - 1, 1.414); if (i < tw - 1) relax(k2, k2 - tw + 1, 1.414); } }
      for (j = th - 1; j >= 0; j--) for (i = tw - 1; i >= 0; i--) { k2 = j * tw + i; if (i < tw - 1) relax(k2, k2 + 1, 1); if (j < th - 1) { relax(k2, k2 + tw, 1); if (i < tw - 1) relax(k2, k2 + tw + 1, 1.414); if (i > 0) relax(k2, k2 + tw - 1, 1.414); } }
      for (k2 = 0; k2 < n; k2++) if (tix[k2] < 0 && dist[k2] < 1e8) { var s = src[k2]; tix[k2] = tix[s]; tb[k2 * 2] = tb[s * 2]; tb[k2 * 2 + 1] = tb[s * 2 + 1]; }
      p.tix = tix; p.tb = tb;
    });
  }
  /* numbers for a build: triangles, heights, texel density per region (texels per cm at scale 1) */
  SG.critterStats = function (spec, atlas) {
    var bp = blueprint(spec, atlas || 1024), A = bp.A, out = { name: spec.name, tris: bp.nt, verts: bp.nv, atlas: A, shoulder: bp.D ? bp.D.shoulder : null, top: bp.D ? bp.D.top : null, parts: [] }, used = 0;
    bp.parts.forEach(function (p) {
      var lo = [], area = 0, tex = 0, wsum = 0, an = 0, t;
      for (t = p.i0; t < p.i1; t++) {
        var a = bp.idx[t * 3], b = bp.idx[t * 3 + 1], c = bp.idx[t * 3 + 2], P = bp.pos, U = bp.uv;
        var e1 = [P[b * 3] - P[a * 3], P[b * 3 + 1] - P[a * 3 + 1], P[b * 3 + 2] - P[a * 3 + 2]], e2 = [P[c * 3] - P[a * 3], P[c * 3 + 1] - P[a * 3 + 1], P[c * 3 + 2] - P[a * 3 + 2]];
        var l1 = Math.hypot(e1[0], e1[1], e1[2]); if (l1 < 1e-9) continue;
        var ex = [e1[0] / l1, e1[1] / l1, e1[2] / l1], d = e2[0] * ex[0] + e2[1] * ex[1] + e2[2] * ex[2], ey = [e2[0] - d * ex[0], e2[1] - d * ex[1], e2[2] - d * ex[2]], l2 = Math.hypot(ey[0], ey[1], ey[2]); if (l2 < 1e-9) continue;
        var u1 = (U[b * 2] - U[a * 2]) * A, v1 = (U[b * 2 + 1] - U[a * 2 + 1]) * A, u2 = (U[c * 2] - U[a * 2]) * A, v2 = (U[c * 2 + 1] - U[a * 2 + 1]) * A;
        // J maps the triangle's own 2D frame (metres) to texels
        var j11 = u1 / l1, j21 = v1 / l1, j12 = (u2 - j11 * d) / l2, j22 = (v2 - j21 * d) / l2, s1 = j11 * j11 + j21 * j21 + j12 * j12 + j22 * j22, det = Math.abs(j11 * j22 - j12 * j21), disc = Math.sqrt(Math.max(0, s1 * s1 / 4 - det * det));
        var smax = Math.sqrt(s1 / 2 + disc), smin = Math.sqrt(Math.max(0, s1 / 2 - disc)), ar = l1 * l2 / 2;
        if (ar < 2e-6) continue;
        lo.push([smin, ar]); area += ar; tex += det * ar; wsum += smin * ar; an += (smax / Math.max(1e-6, smin)) * ar;
      }
      lo.sort(function (x, y) { return x[0] - y[0]; }); var acc = 0, p5 = lo.length ? lo[0][0] : 0; for (t = 0; t < lo.length; t++) { acc += lo[t][1]; if (acc >= area * 0.05) { p5 = lo[t][0]; break; } }
      used += tex;
      out.parts.push({ name: p.name, rect: [p.rx, p.ry, p.tw, p.th], areaCm2: Math.round(area * 1e4), mean: +(wsum / area / 100).toFixed(2), p5: +(p5 / 100).toFixed(2), aniso: +(an / area).toFixed(2) });
    });
    out.used = +(used / (A * A)).toFixed(3); out.ppu = bp.ppu;
    return out;
  };
  SG._critterBlueprint = blueprint;

  /* =====================================================================================================
     runtime
     ===================================================================================================== */
  var _v = new THREE.Vector3(), _v2 = new THREE.Vector3(), _q = new THREE.Quaternion(), _e = new THREE.Euler(), _m = new THREE.Matrix4();
  var PM = new Float64Array(16), LM = new Float64Array(16);
  function compose(te, px, py, pz, x, y, z, w, sx, sy, sz) {
    var x2 = x + x, y2 = y + y, z2 = z + z, xx = x * x2, xy = x * y2, xz = x * z2, yy = y * y2, yz = y * z2, zz = z * z2, wx = w * x2, wy = w * y2, wz = w * z2;
    te[0] = (1 - (yy + zz)) * sx; te[1] = (xy + wz) * sx; te[2] = (xz - wy) * sx; te[3] = 0;
    te[4] = (xy - wz) * sy; te[5] = (1 - (xx + zz)) * sy; te[6] = (yz + wx) * sy; te[7] = 0;
    te[8] = (xz + wy) * sz; te[9] = (yz - wx) * sz; te[10] = (1 - (xx + yy)) * sz; te[11] = 0;
    te[12] = px; te[13] = py; te[14] = pz; te[15] = 1;
  }
  function mul(o, oo, a, ao, b, bo) { // affine o = a * b
    var a0 = a[ao], a1 = a[ao + 1], a2 = a[ao + 2], a4 = a[ao + 4], a5 = a[ao + 5], a6 = a[ao + 6], a8 = a[ao + 8], a9 = a[ao + 9], a10 = a[ao + 10];
    for (var c = 0; c < 4; c++) { var b0 = b[bo + c * 4], b1 = b[bo + c * 4 + 1], b2 = b[bo + c * 4 + 2]; o[oo + c * 4] = a0 * b0 + a4 * b1 + a8 * b2; o[oo + c * 4 + 1] = a1 * b0 + a5 * b1 + a9 * b2; o[oo + c * 4 + 2] = a2 * b0 + a6 * b1 + a10 * b2; o[oo + c * 4 + 3] = 0; }
    o[oo + 12] += a[ao + 12]; o[oo + 13] += a[ao + 13]; o[oo + 14] += a[ao + 14]; o[oo + 15] = 1;
  }
  /* the stock skinning shader turns normals with the bone matrix itself, which is wrong once a pose squashes the body;
     use the cofactor matrix so a flattened cat is lit like the flat thing it is */
  var SKIN_N = ['#ifdef USE_SKINNING', 'mat4 skinMatrix = mat4( 0.0 );', 'skinMatrix += skinWeight.x * boneMatX;', 'skinMatrix += skinWeight.y * boneMatY;', 'skinMatrix += skinWeight.z * boneMatZ;', 'skinMatrix += skinWeight.w * boneMatW;',
    'skinMatrix = bindMatrixInverse * skinMatrix * bindMatrix;', 'mat3 sm3 = mat3( skinMatrix );', 'objectNormal = normalize( mat3( cross( sm3[1], sm3[2] ), cross( sm3[2], sm3[0] ), cross( sm3[0], sm3[1] ) ) * objectNormal );', '#endif'].join('\n');
  /* uGlow is the game's feedback colour (answer check, "stuck inside furniture"); it is black in play, and then this is plain PBR */
  var GLOW_F = 'float fz = pow(1.0 - saturate(dot(normal, normalize(vViewPosition))), 2.6);\noutgoingLight += uGlow * (0.18 + fz * 1.6);\n';
  var DOG_F = 'float fzr = pow(1.0 - saturate(dot(normal, normalize(vViewPosition))), 2.6);\noutgoingLight += diffuseColor.rgb * vec3(0.9,0.82,0.7) * fzr * uRim * (1.0 - metalnessFactor) * roughnessFactor;\n';

  function Critter(spec, opt) {
    opt = opt || {};
    var S = this.spec = spec, self = this, i;
    this.kind = S.kind;
    this.root = new THREE.Group();      // world position + yaw
    this.pivot = new THREE.Group();     // pose rotation + shape + ground offset
    this.root.add(this.pivot);
    this.joints = {}; this.parts = []; this.meshes = []; this.decos = [];
    this.pose = 'stand'; this.poseAmount = 0.5; this.frozen = false; this.walk = 0; this.speed = 0; this.air = 0; this.turn = 0;
    this.t = (opt.seed || 0) * 3.7; this.blinkT = 2 + (opt.seed || 0); this.flickT = 1; this.twitchT = 3; this.lookT = 2;
    this.look = [0, 0]; this.lookTo = [0, 0]; this.eyesOpen = 1; this.wag = 0;
    var bare = !!opt.bare, A = this.A = bare ? 0 : (opt.atlas || 1024);
    var bp = this.bp = blueprint(S, A), cv = this.canvas = bp.canvas; this.tailN = bp.tailN;
    var dogc = cv && S.kind === 'dog'; this._ear = cv && !dogc ? 'flat' : 'up'; this.rearUp = 0;
    this.glow = { value: new THREE.Color(0, 0, 0) }; this.rim = { value: cv ? 0 : 0.2 }; // rim: only the old lathe dogs (spec.legacy) have the fur sheen
    if (bare) this.mat = new THREE.MeshBasicMaterial();
    else {
      this.alb = new Uint8Array(A * A * 4).fill(255);
      this.orm = new Uint8Array(A * A * 4);
      var rb = Math.round((this.spec && this.spec.jelly ? 0.3 : cv ? 0.9 : 0.82) * 255); // jelly bodies are glossy vinyl like the original's figures (owner 2026-11-26 video)
      for (i = 0; i < A * A * 4; i += 4) { this.orm[i] = 255; this.orm[i + 1] = rb; this.orm[i + 2] = 0; this.orm[i + 3] = 255; }
      this.texA = new THREE.DataTexture(this.alb, A, A, THREE.RGBAFormat); this.texA.colorSpace = THREE.SRGBColorSpace;
      this.texO = new THREE.DataTexture(this.orm, A, A, THREE.RGBAFormat);
      [this.texA, this.texO].forEach(function (t) { t.magFilter = THREE.LinearFilter; t.minFilter = THREE.LinearMipmapLinearFilter; t.generateMipmaps = true; t.anisotropy = 4; t.needsUpdate = true; });
      this.mat = new THREE.MeshStandardMaterial({ map: this.texA, roughnessMap: this.texO, metalnessMap: this.texO, roughness: 1, metalness: 1 });
      if (!cv) this.mat.envMapIntensity = 0.9;
      this.mat.onBeforeCompile = function (sh) {
        sh.uniforms.uGlow = self.glow; sh.uniforms.uRim = self.rim;
        sh.vertexShader = sh.vertexShader.replace('#include <skinnormal_vertex>', SKIN_N);
        sh.fragmentShader = sh.fragmentShader.replace('#include <common>', '#include <common>\nuniform vec3 uGlow; uniform float uRim;').replace('#include <opaque_fragment>', (cv ? '' : DOG_F) + GLOW_F + '#include <opaque_fragment>');
      };
      this.mat.customProgramCacheKey = function () { return cv ? 'critter-canvas' : 'critter-dog'; };
    }
    // skeleton
    var jl = this.jl = [], names = this.names = []; this.ji = {};
    bp.joints.forEach(function (d, q) {
      var g = new THREE.Group(); g.position.set(d.pos[0], d.pos[1], d.pos[2]); g.rotation.set(d.rot[0] * D2R, d.rot[1] * D2R, d.rot[2] * D2R); g.userData.q0 = g.quaternion.clone();
      (d.parent < 0 ? self.pivot : jl[d.parent]).add(g); jl.push(g); names.push(d.name); self.joints[d.name] = g; self.ji[d.name] = q;
    });
    var nj = jl.length, nv = bp.nv;
    if (cv) this.shJ = Object.keys(bp.shift).map(function (n) { return { g: self.joints[n], i: self.ji[n], p: self.joints[n].position.toArray(), sh: bp.shift[n], leg: n.length === 3 && n !== 'hip' && (n.slice(0, 2) === 'sh' || n.slice(0, 2) === 'hp') }; });
    this.cq = jl.map(function () { return new THREE.Quaternion(); }); this.cs = jl.map(function () { return new THREE.Vector3(1, 1, 1); });
    this.pq = new THREE.Quaternion(); this.ps = new THREE.Vector3(1, 1, 1); this.cm = [0, 0, 0]; this.am = [0, 0, 0]; this.madd = [0, 0, 0]; this.gz = null;
    this.REL = new Float64Array(nj * 16); this.SM = new Float64Array(nj * 16); this.SMp = new Float64Array(nj * 16); this.ver = 0; this._mdirty = true;
    this.RV = new Float32Array(bp.pos); this.RN = new Float32Array(bp.nrm); this.PV = new Float32Array(nv * 3);
    // one skinned mesh, one material
    var geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(this.RV, 3)); geo.setAttribute('normal', new THREE.BufferAttribute(this.RN, 3));
    geo.setAttribute('uv', new THREE.BufferAttribute(bp.uv, 2)); geo.setAttribute('skinIndex', new THREE.BufferAttribute(bp.si, 4)); geo.setAttribute('skinWeight', new THREE.BufferAttribute(bp.sw, 4));
    geo.setIndex(new THREE.BufferAttribute(bp.idx, 1)); geo.boundingSphere = new THREE.Sphere(new THREE.Vector3(0, 0.2, 0), 1.5);
    var sk = this.skin = new THREE.SkinnedMesh(geo, this.mat); sk.frustumCulled = false;
    sk.bind(new THREE.Skeleton(jl, jl.map(function (g, q) { return new THREE.Matrix4().fromArray(bp.inv0, q * 16); })), new THREE.Matrix4());
    this.root.add(sk); this.meshes.push(sk); sk.userData.critter = this;
    sk.castShadow = true; sk.receiveShadow = true;
    this.parts = bp.parts.map(function (b) { return { name: b.name, rx: b.rx, ry: b.ry, tw: b.tw, th: b.th, mesh: self.root, samples: new Float32Array(b.sv.length * 3), c: new THREE.Vector3(), r: 0, bp: b, tp: null, tpVer: -1, bVer: -1 }; });
    // face details: dogs only. A cat has nothing on it that is not paintable skin.
    this.eyes = []; this.face = [];
    if (!cv && !bare) this._dogFace(); else if (dogc && !bare) this._flatDogFace(); else { this.faceSkin = new THREE.Object3D(); this.root.add(this.faceSkin); }
    this.an = { sp: 0, psp: 0, acc: 0, turn: 0, loco: 0, shuf: 0, run: 0, air: 0, vy: 0, py: 0, wasAir: 0, launch: 0, bk: 0, p: 0, pv: 0 };
    this._off = new THREE.Vector3(); this.liftY = 0; this.bob = 0; this._minY = 0;
    this.scale = (opt.scale || 1) * (S.scale || 1); this.root.scale.setScalar(this.scale);
    this._blend(1); this._morph(); this._pose(); this._limbs(); this._solve(true); this._lift0 = this.liftY;
    if (S.coat && !bare) this.applyCoat(JCOATS[S.coat] || (cv ? FCOATS : COATS)[S.coat]);
    if (cv && S.collar && !bare) this._collar();
  }
  var P = Critter.prototype;
  Object.defineProperty(P, 'earMode', { get: function () { return this._ear; }, set: function (v) { this._ear = v === 'flat' ? 'flat' : 'up'; } });
  Object.defineProperty(P, 'earFlat', { get: function () { return this._ear === 'flat'; }, set: function (v) { this._ear = v ? 'flat' : 'up'; } });

  P._deco = function (joint, geo, mat, x, y, z) { var m = new THREE.Mesh(geo, mat); m.position.set(x, y, z); m.layers.set(3); joint.add(m); this.decos.push(m); return m; };
  P._dogFace = function () {
    var S = this.spec, self = this, dog = S.kind === 'dog', X = dogCtx(S), HR = X.HR, hc = X.hc, mz = X.mz, head = this.joints.head, neck = this.joints.neck, nl = X.nl, nUp = X.nUp;
    var dark = new THREE.MeshStandardMaterial({ color: S.eyeColor || 0x1b1512, roughness: 0.18, metalness: 0.0, envMapIntensity: 1.4 });
    var pink = new THREE.MeshStandardMaterial({ color: dog ? 0x241a18 : 0xe79a9a, roughness: dog ? 0.25 : 0.5 });
    [-1, 1].forEach(function (s) {
      var p = X.onHead(s * (dog ? 0.42 : 0.5), dog ? 0.2 : 0.06, 0.84, 0.985);
      var eg = new THREE.Group(); eg.position.set(p[0], p[1], p[2]); eg.lookAt(p[0] * 2 - hc[0], p[1] * 2 - hc[1] + 0.0, p[2] * 2 - hc[2]); head.add(eg);
      var e = new THREE.Mesh(new THREE.SphereGeometry(S.eye, 16, 12), dark); e.scale.set(0.9, 1.12, 0.42); eg.add(e);
      var hl = new THREE.Mesh(new THREE.SphereGeometry(S.eye * 0.26, 8, 6), new THREE.MeshBasicMaterial({ color: 0xffffff }));
      hl.position.set(-S.eye * 0.28, S.eye * 0.42, S.eye * 0.36); e.add(hl); hl.scale.set(1.1, 0.9, 2.2); hl.layers.set(3); e.layers.set(3); self.decos.push(e, hl);
      self.eyes.push(eg);
    });
    var noseP = [0, mz[1] + S.muzzleR * (dog ? 0.3 : 0.36), mz[2] + (dog ? S.muzzleL * 1.38 + S.muzzleR * 0.3 : S.muzzleL * 0.3 + S.muzzleR * 0.42)];
    this.nose = this._deco(head, new THREE.SphereGeometry(dog ? S.muzzleR * 0.34 : 0.013, 12, 8), pink, noseP[0], noseP[1], noseP[2]);
    this.nose.scale.set(1.25, 0.8, 0.8);
    this.face = [this.nose].concat(this.eyes);
    if (S.underbite) { var tm = new THREE.MeshStandardMaterial({ color: 0xfffdf4 }); [-1, 1].forEach(function (s) { self._deco(head, new THREE.ConeGeometry(0.011, 0.03, 6), tm, s * S.muzzleR * 0.42, mz[1] - S.muzzleR * 0.2, mz[2] + S.muzzleL + S.muzzleR * 0.86); }); }
    if (S.collar) { // not paintable
      var cc = { red: 0xc8452e, bell: 0x2f4b7c, scarf: 0xd9a93a }[S.collar] || 0xc8452e, cm = new THREE.MeshStandardMaterial({ color: cc, roughness: 0.6 }), nr2 = Math.min(S.chestR * 0.66, S.headR * 0.72);
      var col = self._deco(neck, new THREE.TorusGeometry(nr2 * 1.02, 0.014, 6, 20), cm, 0, nl * 0.35, nl * 0.3); col.rotation.x = PI / 2 - (90 - nUp) * PI / 180 + 1.1;
      if (S.collar === 'bell') self._deco(neck, new THREE.SphereGeometry(0.024, 10, 8), new THREE.MeshStandardMaterial({ color: 0xd9a93a, roughness: 0.3, metalness: 0.8 }), 0, nl * 0.35 - nr2 * 0.75, nl * 0.3 + nr2 * 0.75);
      if (S.collar === 'scarf') { var sc = self._deco(neck, new THREE.ConeGeometry(nr2 * 0.9, nr2 * 1.3, 3), cm, 0, nl * 0.35 - nr2 * 0.9, nl * 0.3 + nr2 * 0.8); sc.rotation.set(2.6, 0, 0); sc.scale.z = 0.25; }
    }
    if (dog) { // tongue for charm
      var tg = this._deco(head, SG.geo.rbox(S.muzzleR * 0.62, 0.012, S.muzzleR * 1.0, 0.005), new THREE.MeshStandardMaterial({ color: 0xe8788a, roughness: 0.45 }), 0, mz[1] - S.muzzleR * 0.62, mz[2] + S.muzzleL * 0.95);
      tg.rotation.x = 0.5; this.tongue = tg; this.tongue0 = tg.position.clone(); this.face.push(tg);
    }
    var ident = new THREE.Matrix4(), objs = this.decos;
    var g = SG.geo.merge(objs.map(function (o) { return [o.geometry, null, o.material.color]; })), n = g.attributes.position.count, si = new Uint16Array(n * 4), sw = new Float32Array(n * 4), k = 0;
    objs.forEach(function (o, b) { var c = o.geometry.attributes.position.count; for (var q = 0; q < c; q++, k++) { si[k * 4] = b; sw[k * 4] = 1; } });
    g.setAttribute('skinIndex', new THREE.BufferAttribute(si, 4)); g.setAttribute('skinWeight', new THREE.BufferAttribute(sw, 4));
    this.faceMat = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.28, envMapIntensity: 1.2 });
    var fs = this.faceSkin = new THREE.SkinnedMesh(g, this.faceMat); fs.frustumCulled = false;
    fs.bind(new THREE.Skeleton(objs, objs.map(function () { return ident.clone(); })), ident);
    this.root.add(fs); fs.userData.noShadow = true; fs.receiveShadow = true;
  };

  /* flat dogs: small dark eyes, a nose, a tongue that only comes out at a run, and the toy paint blaster riding on the back */
  P._flatDogFace = function () {
    var S = this.spec, self = this, D = this.bp.D, head = this.joints.head, body = this.joints.body, hw = this.bp.rest0, hi = this.ji.head * 16, hx = hw[hi + 12], hy = hw[hi + 13], hz = hw[hi + 14];
    var dark = new THREE.MeshStandardMaterial({ color: S.eyeColor || 0x1b1512, roughness: 0.2 }), nose = new THREE.MeshStandardMaterial({ color: 0x241a18, roughness: 0.3 });
    if (!S.human) [-1, 1].forEach(function (s) {
      var eg = new THREE.Group(); eg.position.set(s * D.eyeP[0] - hx, D.eyeP[1] - hy, D.eyeP[2] - hz); head.add(eg);
      var e = new THREE.Mesh(new THREE.SphereGeometry(S.eye || 0.013, 12, 8), dark); e.scale.set(1, 0.7, 1); e.layers.set(3); eg.add(e); self.decos.push(e); self.eyes.push(eg);
    });
    if (!S.human) { this.nose = this._deco(head, new THREE.SphereGeometry(0.02, 12, 8), nose, D.noseP[0] - hx, D.noseP[1] - hy, D.noseP[2] - hz); this.nose.scale.set(1.2, 0.6, 0.9);
    var tg = this._deco(head, SG.geo.rbox(0.04, 0.008, 0.06, 0.003), new THREE.MeshStandardMaterial({ color: 0xe8788a, roughness: 0.45 }), D.mouthP[0] - hx, D.mouthP[1] - hy, D.mouthP[2] - hz);
    tg.scale.set(1, 1, 0.01); this.tongue = tg; this.tongue0 = tg.position.clone(); this.tongueFlat = true; }
    if (S.collar === 'bell') this._deco(this.joints.neck, new THREE.SphereGeometry(0.02, 10, 8), new THREE.MeshStandardMaterial({ color: 0xd9a93a, roughness: 0.3, metalness: 0.8 }), 0, D.hh * 0.7 + 0.02, 0);
    if (S.gun !== false) { // a chunky toy blaster on a saddle: base, body, barrel with a fat muzzle ring, paint tank
      var y0 = D.gunY, gz = D.gunZ || 0, M = function (geo, col, x, y, z, rx, r) { var m = self._deco(body, geo, new THREE.MeshStandardMaterial({ color: col, roughness: r || 0.5 }), x, y, z + gz); if (rx) m.rotation.x = rx; return m; };
      M(new THREE.CylinderGeometry(0.055, 0.07, 0.03, 16), 0x3a3f46, 0, y0 + 0.012, 0.0);
      M(SG.geo.rbox(0.075, 0.06, 0.17, 0.016), 0xf29a4a, 0, y0 + 0.06, 0.02);
      M(new THREE.CylinderGeometry(0.02, 0.02, 0.14, 12), 0x596270, 0, y0 + 0.066, 0.17, Math.PI / 2, 0.35);
      M(new THREE.CylinderGeometry(0.03, 0.03, 0.035, 14), 0x2f4b7c, 0, y0 + 0.066, 0.243, Math.PI / 2);
      M(new THREE.SphereGeometry(0.042, 14, 10), 0x4aa3e0, 0, y0 + 0.118, -0.02, 0, 0.25);
    }
    var ident = new THREE.Matrix4(), objs = this.decos;
    var g = SG.geo.merge(objs.map(function (o) { return [o.geometry, null, o.material.color]; })), n = g.attributes.position.count, si = new Uint16Array(n * 4), sw = new Float32Array(n * 4), k = 0;
    objs.forEach(function (o, b) { var c = o.geometry.attributes.position.count; for (var q = 0; q < c; q++, k++) { si[k * 4] = b; sw[k * 4] = 1; } });
    g.setAttribute('skinIndex', new THREE.BufferAttribute(si, 4)); g.setAttribute('skinWeight', new THREE.BufferAttribute(sw, 4));
    this.faceMat = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.4 });
    var fs = this.faceSkin = new THREE.SkinnedMesh(g, this.faceMat); fs.frustumCulled = false;
    fs.bind(new THREE.Skeleton(objs, objs.map(function () { return ident.clone(); })), ident);
    this.root.add(fs); fs.userData.noShadow = true; fs.receiveShadow = true;
  };
  /* collar: painted on (a band across the neck), so it stays flat */
  P._collar = function () {
    if (this.spec.jelly) return; var D = this.bp.D, col = { red: [200, 69, 46], bell: [47, 75, 124], scarf: [217, 169, 58] }[this.spec.collar] || [200, 69, 46], z0 = D.zb3 - 0.012, w = this.spec.collar === 'scarf' ? 0.032 : 0.016, po = this.pivot.position;
    this.root.updateMatrixWorld(true); var inv = new THREE.Matrix4().copy(this.root.matrixWorld).invert().elements;
    this.eachTexel(function (x, y, z) { var lz = inv[2] * x + inv[6] * y + inv[10] * z + inv[14] - po.z; return Math.abs(lz - z0) < w ? col : null; });
  };
  /* c.anchor('eye' | 'muzzle' | 'head', out): world position of a point on the animal as it is posed now.
     eye = between the eyes; muzzle = the blaster's muzzle on a dog, the front of the head on a cat; head = top of the head */
  P.anchor = function (name, out) {
    out = out || new THREE.Vector3(); var D = this.bp.D, po = this.pivot.position, j, p;
    if (!D) return this.center(out);
    if (name === 'muzzle' && this.kind === 'dog' && this.spec.gun !== false) { j = this.ji.body; p = D.muzzleP; }
    else { j = this.ji.head; p = name === 'muzzle' ? [0, D.hy, D.zF] : name === 'head' ? [0, D.hy + D.hH, D.zH] : [0, D.eyeP[1], D.eyeP[2]]; }
    var r0 = this.bp.rest0, M = this.REL, o = j * 16, lx = p[0] - r0[o + 12], ly = p[1] - r0[o + 13], lz = p[2] - r0[o + 14];
    this.root.updateWorldMatrix(true, false);
    return out.set(M[o] * lx + M[o + 4] * ly + M[o + 8] * lz + M[o + 12] + po.x, M[o + 1] * lx + M[o + 5] * ly + M[o + 9] * lz + M[o + 13] + po.y, M[o + 2] * lx + M[o + 6] * ly + M[o + 10] * lz + M[o + 14] + po.z).applyMatrix4(this.root.matrixWorld);
  };

  /* ---------- pose ---------- */
  function poseEuler(P0, name) {
    var v = P0[name];
    if (!v) {
      var side = name.slice(-1), base = name.slice(0, -1);
      if ((side === 'L' || side === 'R') && P0[base]) { v = P0[base]; return side === 'R' ? [v[0], -v[1], -v[2]] : v; }
      return null;
    }
    return v;
  }
  /* c.setPose(name, amount): amount 0..1 is optional (each pose has its own default); it can also be changed later through c.poseAmount */
  P.setPose = function (name, amount) {
    if (!POSES[name]) return;
    var d = PT(this.spec)[ALIAS[name] || name];
    if (name !== this.pose || amount != null) this.poseAmount = amount != null ? clamp(+amount, 0, 1) : d ? d.amt : 0.5;
    this.pose = name;
  };
  var TUCK = [[-30, 64, 0], [0, 50, 0], [0, 48, 0], [0, 42, 0]], ZERO3 = [0, 0, 0], ONE3 = [1, 1, 1], CURL3 = [-40, 0, 0], EARF = [68, 0, 0], TINY = [1e-4, 1e-4, 1e-4], NOM = [0, 0, 0];
  /* move the current pose towards the target by k (1 = jump). Returns true when it has arrived. */
  P._blend = function (k) {
    var S = this.spec, cv = this.canvas, posed = this.pose !== 'stand' && this.pose !== 'crouch', P0, done = true, i, n, v, sc, T = S.tail, tm = this.tailMode;
    var PTb = PT(S); if (cv) P0 = (PTb[ALIAS[this.pose] || this.pose] || PTb.stand).f(clamp(+this.poseAmount || 0, 0, 1), this.bp.D); else P0 = POSES[this.pose] || POSES.stand;
    if (cv && this.rearUp > 0 && !posed) { var ru = clamp(this.rearUp, 0, 1), Q = {}; for (var qk in P0) Q[qk] = P0[qk]; if (S.jelly) { Q.S = [1 - 0.06 * ru, 1 + 0.16 * ru, 1 - 0.06 * ru]; Q.neck = [-14 * ru, 0, 0]; } else { Q.pivot = [-38 * ru, 0, 0]; Q.chest = [-42 * ru, 0, 0]; Q.neck = [36 * ru, 0, 0]; Q.head = [34 * ru, 0, 0]; } P0 = Q; } // c.rearUp 0..1: the front end lifts to look over things
    if (cv && S.jelly && this.climb && !posed) { var Qc = {}; for (var qc in P0) Qc[qc] = P0[qc]; Qc.S = [1.08, 1.07, 0.84]; Qc.sh = [-12, 0, -122]; Qc.el = [0, 0, -18]; Qc.hp = [0, 0, -24]; P0 = Qc; } // owner 2026-11-26: climbing a wall the body is pulled up, flatter and wider, arms reaching up, feet spread
    for (i = 0; i < this.names.length; i++) {
      n = this.names[i]; v = poseEuler(P0, n); sc = null;
      var c0 = n.charAt(0), c1 = n.charAt(1);
      if (cv) {
        if (c0 === 't' && n.length === 2) {
          var ti = +c1;
          if (posed) { var mode = tm || 'tuck'; if (mode === 'tuck') { v = ZERO3; if (ti === 0) sc = TINY; } else if (mode === 'straight') v = ti === 0 ? [90 - T.up, 0, 0] : ZERO3; else v = ti === 0 ? [28, 0, 0] : [56, 0, 0]; }
          else if (!v) v = ti === 0 ? ZERO3 : [T.curl, 0, 0];
          if (T.none && ti === 0) sc = TINY;
        } else if (c0 === 'e' && c1 === 'a') { if (posed && this._ear === 'flat') { v = [-95, 0, 0]; sc = TINY; } }
        else if (P0.leg && n.length === 3 && ((c0 === 's' && c1 === 'h') || (c0 === 'h' && c1 === 'p'))) { var lg = P0.leg[c0 === 's' ? 0 : 1]; if (lg <= 0.001) sc = TINY; else if (lg !== 1) { var th = lg < 1 ? lerp(0.3, 1, sstep(0, 0.8, lg)) : 1; sc = [th, lg, th]; } }
      } else {
        if (tm && posed && n.length === 2 && c0 === 't') v = tm === 'tuck' ? TUCK[Math.min(3, +c1)] : tm === 'straight' ? ZERO3 : CURL3;
        if (this._ear === 'flat' && (n === 'earL' || n === 'earR')) v = EARF;
      }
      if (P0[n + 'S']) sc = P0[n + 'S'];
      if (v) { _e.set(v[0] * D2R, v[1] * D2R, v[2] * D2R, 'YXZ'); _q.setFromEuler(_e); } else _q.identity();
      var cq = this.cq[i], cs = this.cs[i], sx = sc ? sc[0] : 1, sy = sc ? sc[1] : 1, sz = sc ? sc[2] : 1;
      if (k >= 1 || (1 - Math.abs(cq.dot(_q)) < 1e-7 && Math.abs(cs.x - sx) + Math.abs(cs.y - sy) + Math.abs(cs.z - sz) < 2e-4)) { cq.copy(_q); cs.set(sx, sy, sz); }
      else { cq.slerp(_q, k); cs.x += (sx - cs.x) * k; cs.y += (sy - cs.y) * k; cs.z += (sz - cs.z) * k; done = false; }
    }
    var pv = P0.pivot || ZERO3, s3 = P0.S || ONE3, m = P0.m || NOM, ps = this.ps, cm = this.cm;
    _e.set(pv[0] * D2R, pv[1] * D2R, pv[2] * D2R, 'YXZ'); _q.setFromEuler(_e);
    var m2 = m[2] || 0, dd = Math.abs(ps.x - s3[0]) + Math.abs(ps.y - s3[1]) + Math.abs(ps.z - s3[2]) + Math.abs(cm[0] - m[0]) + Math.abs(cm[1] - m[1]) + Math.abs(cm[2] - m2);
    if (k >= 1 || (1 - Math.abs(this.pq.dot(_q)) < 1e-7 && dd < 2e-4)) { this.pq.copy(_q); ps.set(s3[0], s3[1], s3[2]); cm[0] = m[0]; cm[1] = m[1]; cm[2] = m2; }
    else { this.pq.slerp(_q, k); ps.x += (s3[0] - ps.x) * k; ps.y += (s3[1] - ps.y) * k; ps.z += (s3[2] - ps.z) * k; cm[0] += (m[0] - cm[0]) * k; cm[1] += (m[1] - cm[1]) * k; cm[2] += (m2 - cm[2]) * k; done = false; }
    this.gz = P0.g || null; this._emote = cv ? !!(PTb[this.pose] && PTb[this.pose].emote) : !!P0.emote;
    return done;
  };
  /* shape targets are blended on the CPU into the rest mesh, so every mesh that shares this geometry (see-through ghost, answer-check shell) follows */
  P._morph = function () {
    var bp = this.bp, cm = this.cm, am = this.am; if (!bp.morph.length) return;
    var md = this.madd, a = cm[0] + md[0], b = cm[1] + md[1], c = cm[2] + md[2];
    if (Math.abs(a - am[0]) < 1e-5 && Math.abs(b - am[1]) < 1e-5 && Math.abs(c - am[2]) < 1e-5) return;
    var RV = this.RV, RN = this.RN, p0 = bp.pos, n0 = bp.nrm, d0 = bp.morph[0], d1 = bp.morph[1], d2 = bp.morph[2], n = bp.nv * 3, i;
    for (i = 0; i < n; i++) { RV[i] = p0[i] + a * d0.dp[i] + b * d1.dp[i] + c * d2.dp[i]; RN[i] = n0[i] + a * d0.dn[i] + b * d1.dn[i] + c * d2.dn[i]; }
    am[0] = a; am[1] = b; am[2] = c; this._mdirty = true;
    var g = this.skin.geometry; g.attributes.position.needsUpdate = true; g.attributes.normal.needsUpdate = true;
  };
  P._pose = function () {
    for (var i = 0; i < this.jl.length; i++) { var j = this.jl[i]; j.quaternion.copy(j.userData.q0).multiply(this.cq[i]); j.scale.copy(this.cs[i]); }
    this.pivot.quaternion.copy(this.pq); this.pivot.scale.copy(this.ps); this._off.set(0, 0, 0); this.bob = 0;
  };
  P._limbs = function () {
    var i;
    if (this.canvas) { // limbs ride on the body's shape targets; a drawn-in leg also goes up inside the body, all of it
      var cm = this.am, SJ = this.shJ;
      for (i = 0; i < SJ.length; i++) { var q = SJ[i], h = q.sh, g = q.g, k; g.position.set(q.p[0], q.p[1], q.p[2]); for (k = 0; k < 3; k++) if (cm[k] && h[k]) { g.position.x += cm[k] * h[k][0]; g.position.y += cm[k] * h[k][1]; g.position.z += cm[k] * h[k][2]; } if (q.leg) { var sy = this.cs[q.i].y; if (sy < 1) g.position.y += (1 - sy) * this.bp.D.tuck; } }
    }
  };
  /* bone matrices -> posed vertices (CPU, same maths as the GPU) -> ground contact, sample points */
  P._solve = function (snap) {
    var bp = this.bp, jl = this.jl, nj = jl.length, REL = this.REL, SM = this.SM, SMp = this.SMp, i, k;
    var pq = this.pivot.quaternion, psc = this.pivot.scale;
    compose(PM, 0, 0, 0, pq.x, pq.y, pq.z, pq.w, psc.x, psc.y, psc.z);
    for (i = 0; i < nj; i++) {
      var j = jl[i], p = j.position, q = j.quaternion, s = j.scale, par = bp.joints[i].parent;
      compose(LM, p.x, p.y, p.z, q.x, q.y, q.z, q.w, s.x, s.y, s.z);
      if (par < 0) mul(REL, i * 16, PM, 0, LM, 0); else mul(REL, i * 16, REL, par * 16, LM, 0);
      mul(SM, i * 16, REL, i * 16, bp.inv0, i * 16);
    }
    var ch = this._mdirty; for (i = 0; i < nj * 16 && !ch; i++) if (Math.abs(SM[i] - SMp[i]) > 1e-7) ch = true;
    var gz = this.gz, g0 = gz ? gz[0] : -1e9, g1 = gz ? gz[1] : 1e9;
    if (ch || g0 !== this._g0 || g1 !== this._g1) {
      SMp.set(SM); this.ver++; this._mdirty = false; this._g0 = g0; this._g1 = g1;
      var RV = this.RV, PV = this.PV, si = bp.si, sw = bp.sw, nv = bp.nv, minY = 1e9, B0 = bp.pos;
      for (var v = 0; v < nv; v++) {
        var x = RV[v * 3], y = RV[v * 3 + 1], z = RV[v * 3 + 2], ox = 0, oy = 0, oz = 0;
        for (k = 0; k < 4; k++) { var w = sw[v * 4 + k]; if (w === 0) break; var m = si[v * 4 + k] * 16; ox += w * (SM[m] * x + SM[m + 4] * y + SM[m + 8] * z + SM[m + 12]); oy += w * (SM[m + 1] * x + SM[m + 5] * y + SM[m + 9] * z + SM[m + 13]); oz += w * (SM[m + 2] * x + SM[m + 6] * y + SM[m + 10] * z + SM[m + 14]); }
        PV[v * 3] = ox; PV[v * 3 + 1] = oy; PV[v * 3 + 2] = oz;
        if (oy < minY) { var bz = B0[v * 3 + 2]; if (bz >= g0 && bz <= g1) minY = oy; }
      }
      this._minY = minY;
    }
    // keep the lowest point of the body on the surface it stands on (floor, wall or ceiling: the root's own "up"), whatever the pose
    var target = -this._minY, d; if (this._airK > 0.001 && this._lift0 > target) target += (this._lift0 - target) * this._airK; // in the air the body keeps its standing height over the root; the legs are free
    d = target - this.liftY;
    if (snap || Math.abs(d) < 2e-5) { this.liftY = target; this._grounded = true; } else { this.liftY += d * 0.5; this._grounded = false; }
    var po = this.pivot.position; po.set(this._off.x, this.liftY + this.bob + this._off.y, this._off.z);
    var PV2 = this.PV;
    for (i = 0; i < this.parts.length; i++) { var pt = this.parts[i], sv = pt.bp.sv, sm = pt.samples; for (k = 0; k < sv.length; k++) { var a = sv[k] * 3; sm[k * 3] = PV2[a] + po.x; sm[k * 3 + 1] = PV2[a + 1] + po.y; sm[k * 3 + 2] = PV2[a + 2] + po.z; } }
    this.root.updateMatrixWorld(true);
  };

  function addRot(j, x, y, z) { _e.set(x, y, z, 'XYZ'); _q.setFromEuler(_e); j.quaternion.multiply(_q); }

  /* c.update(dt, rnd). Inputs read every frame (all set by the game, all optional): c.speed (m/s over the ground),
     c.turn (yaw rate, rad/s), c.air (0/1), c.squash (set to 1 on landing), c.frozen, c.wag, c.tilt, c.fidget.
     Vertical speed for the jump pose is measured from the root's own movement. */
  P.update = function (dt, r) {
    r = r || Math.random; if (!(dt > 0)) dt = 0; if (dt > 0.1) dt = 0.1;
    var cv = this.canvas, posed = this.pose !== 'stand' && this.pose !== 'crouch';
    if (this.blank && this.faceSkin.visible) this.faceSkin.visible = false;
    var sig = this.pose + '|' + this.poseAmount + '|' + this.tailMode + '|' + this._ear + '|' + (this.frozen ? 1 : 0) + '|' + (this.rearUp || 0) + '|' + (this.climb ? 1 : 0);
    if (sig !== this._sig) { this._sig = sig; this._still = false; }
    var busy = this.fidget > 0;
    if (this.frozen && this._still && !busy) return; // a frozen, settled animal costs nothing and moves nothing
    this.t += dt;
    var settled = this._blend(1 - Math.exp(-dt * 9));
    this._pose();
    if (this.frozen) { this.madd[0] = this.madd[1] = this.madd[2] = 0; var A = this.an; A.loco = A.shuf = A.run = A.air = A.bk = A.p = A.pv = A.launch = A.acc = A.flip = A.airT = 0; A.sp = A.psp = this.speed || 0; A.py = this.root.position.y; this.squash = 0; this._airK = 0; this.lag = this.lagV = 0; }
    else this._animate(dt, r, posed, this._stroke ? 0 : 1);
    this._morph(); this._limbs();
    var J = this.joints;
    if (this.fidget > 0) { this.fidget -= dt; var fq = Math.sin(this.fidget * 26) * 0.35; if (J.earL) { addRot(J.earL, fq, 0, 0); } addRot(J['t' + (this.tailN - 1)], 0, 0, fq * 1.4); if (cv) addRot(J.body, 0, fq * 0.03, fq * 0.05); } // a tell: a quick twitch
    if (this.faceMat) this.faceSkin.visible = !this.blank && this.eyesOpen > 0.5 && (!cv || this.am[0] + this.am[1] + this.am[2] < 0.3); // the face and the blaster do not follow the shape targets, so they hide when the body becomes a ball or a roll
    this._solve(false);
    if (this.frozen && settled && !busy && this._grounded) this._still = true;
  };

  P._animate = function (dt, r, posed, live) {
    var S = this.spec, J = this.joints, cv = this.canvas, dog = this.kind === 'dog', A = this.an, i, k, t = this.t, TN = this.tailN;
    var RU = (SG.RULES && SG.RULES[dog ? 'dog' : 'cat']) || {}, vWalk = (dog ? RU.speed : RU.walkSpeed) || 2.4, vRun = RU.runSpeed || 5;
    var sp = Math.max(0, this.speed || 0), crouch = this.pose === 'crouch', loco = !posed && sp > 0.05, moving = sp > 0.05;
    var e12 = 1 - Math.exp(-dt * 12), e8 = 1 - Math.exp(-dt * 8);
    var acc = dt > 0 ? clamp((sp - A.psp) / dt, -40, 40) : 0; A.psp = sp; A.acc += (acc - A.acc) * e12; A.sp += (sp - A.sp) * e12;
    var turn = clamp(this.turn || 0, -9, 9); A.turn += (turn - A.turn) * e12;
    var turning = !posed && !loco && Math.abs(turn) > 0.8 && this.pose === 'stand';
    A.loco += ((loco ? 1 : 0) - A.loco) * (1 - Math.exp(-dt * (loco ? 16 : 10)));
    A.shuf += ((turning ? 1 : 0) - A.shuf) * e12;
    A.run += ((crouch ? 0 : sstep(vWalk + (vRun - vWalk) * 0.3, vWalk + (vRun - vWalk) * 0.72, sp)) - A.run) * e8;
    var wT = A.loco * (1 - A.run) + A.shuf * 0.45 * (1 - A.loco), wG = A.loco * A.run, sc = this.scale;
    var LG = cv ? this.bp.D.leg : S.leg, fT = clamp(sp / ((0.3 + 1.1 * LG) * sc), 2.4, cv ? 7.5 : 6.4), fG = clamp(sp / ((0.9 + 2.4 * LG) * sc), 2.4, 4.2), f = lerp(fT, fG, A.run), md = this.madd; md[0] = md[1] = md[2] = 0;
    if (!loco && A.shuf > 0.01) f = 5;
    if (A.loco > 0.01 || A.shuf > 0.01) this.walk += dt * PI * 2 * f;
    var ph = this.walk, hS = Math.sqrt(Math.max(0.05, LG) / 0.18), pitch = 0, roll = 0, sx = 1, sy = 1, sz = 1, s, c, e, lift;
    var hasEar = !!J.earL, flop = S.ear && S.ear.type === 'flop';
    if (S.human && wT + wG > 0.003) { // a person walking / running: legs swing with a knee bend on the way through, arms swing against them
      var wH = Math.min(1, wT + wG), RH = A.run, sH = Math.sin(ph), cH = Math.cos(ph), ampL = (crouch ? 0.32 : 0.42) + 0.26 * RH;
      addRot(J.hpL, -sH * ampL * wH, 0, 0); addRot(J.hpR, sH * ampL * wH, 0, 0);
      addRot(J.knL, Math.max(0, cH) * (0.55 + 0.6 * RH) * wH, 0, 0); addRot(J.knR, Math.max(0, -cH) * (0.55 + 0.6 * RH) * wH, 0, 0);
      if (!dog) { addRot(J.shL, sH * (0.34 + 0.4 * RH) * wH, 0, 0); addRot(J.shR, -sH * (0.34 + 0.4 * RH) * wH, 0, 0); addRot(J.elL, -(0.12 + 0.9 * RH) * wH, 0, 0); addRot(J.elR, -(0.12 + 0.9 * RH) * wH, 0, 0); } // a hunter keeps both hands on the gun
      addRot(J.chest, 0, sH * 0.08 * wH, 0); addRot(J.hip, 0, -sH * 0.1 * wH, 0); addRot(J.head, 0, -sH * 0.05 * wH, 0);
      roll += sH * 0.025 * wH; pitch += 0.1 * RH * wH;
      this.bob += Math.abs(cH) * (0.012 + 0.025 * RH) * wH;
      wT = 0; wG = 0;
    }
    if (S.jelly && wT + wG > 0.003) { // owner 2026-11-26: a soft, cute waddle (the jelly is a little biped, not a four-legged mat)
      var wJ = Math.min(1, wT + wG), R = A.run, amp = (crouch ? 0.6 : 1) * (0.8 + 0.5 * R), sP = Math.sin(ph), cP = Math.cos(ph), up2 = Math.cos(ph * 2);
      roll += sP * (0.15 + 0.05 * R) * wJ * amp; // rock from one foot onto the other
      pitch += (0.05 + 0.13 * R) * wJ; // lean into a run
      addRot(J.body, 0, sP * 0.07 * wJ, 0); // a little twist with each step
      addRot(J.hpL, -sP * 0.55 * wJ * amp, 0, Math.max(0, -cP) * 0.12 * wJ); addRot(J.hpR, sP * 0.55 * wJ * amp, 0, -Math.max(0, cP) * 0.12 * wJ); // short feet paddle
      J.hpL.scale.y *= 1 - Math.max(0, cP) * 0.25 * wJ; J.hpR.scale.y *= 1 - Math.max(0, -cP) * 0.25 * wJ; // the lifted foot tucks up
      addRot(J.shL, sP * (0.5 + 0.4 * R) * wJ, 0, -(0.12 + Math.abs(sP) * 0.22) * wJ); addRot(J.shR, -sP * (0.5 + 0.4 * R) * wJ, 0, (0.12 + Math.abs(sP) * 0.22) * wJ); // arms swing and flap out
      addRot(J.elL, Math.max(0, sP) * 0.35 * wJ, 0, 0); addRot(J.elR, Math.max(0, -sP) * 0.35 * wJ, 0, 0);
      addRot(J.head, Math.sin(ph * 2 - 0.7) * 0.06 * wJ, -sP * 0.06 * wJ, -Math.sin(ph - 0.6) * 0.12 * wJ); // the head lags the rock, like something soft on top
      this.bob += Math.abs(sP) * (0.03 + 0.03 * R) * wJ * amp;
      sy *= 1 - up2 * 0.055 * wJ; sx *= 1 + up2 * 0.03 * wJ; sz *= 1 + up2 * 0.03 * wJ; // squash as a foot lands, stretch between steps
      if (hasEar) { e = Math.sin(ph * 2 + 1.2) * 0.16 * wJ; if (flop) { addRot(J.earL, 0, 0, -Math.abs(e) * 2); addRot(J.earR, 0, 0, Math.abs(e) * 2); } else { addRot(J.earL, e, 0, -e * 0.5); addRot(J.earR, e, 0, e * 0.5); } }
      wT = 0; wG = 0;
    }
    if (wT > 0.003) { // trot: diagonal pairs, quick and bouncy, hips wiggle, tail whips
      var AT = (crouch ? 0.34 : 0.58) * (loco ? clamp(0.45 + sp / (vWalk * 1.5), 0.5, 1) : 0.6);
      var seq = [['shL', 'elL', 0], ['hpR', 'knR', 0.3], ['shR', 'elR', PI], ['hpL', 'knL', PI + 0.3]];
      for (i = 0; i < 4; i++) { s = Math.sin(ph + seq[i][2]); c = Math.cos(ph + seq[i][2]); lift = Math.max(0, c); addRot(J[seq[i][0]], -s * AT * wT, 0, 0); addRot(J[seq[i][1]], lift * AT * 1.5 * wT, 0, 0); J[seq[i][0]].scale.y *= 1 - lift * 0.15 * wT; }
      this.bob += Math.abs(Math.sin(ph)) * 0.03 * hS * wT * (crouch ? 0.4 : 1);
      if (cv) { // a mat scuttling: the whole flat body wobbles from side to side and a ripple runs along it
        addRot(J.body, Math.sin(ph * 2) * 0.03 * wT, 0, Math.sin(ph) * 0.11 * wT);
        addRot(J.hip, Math.sin(ph * 2 + 1.6) * 0.1 * wT, Math.sin(ph) * 0.26 * wT, -Math.cos(ph) * 0.12 * wT); addRot(J.chest, Math.sin(ph * 2) * 0.1 * wT, -Math.sin(ph) * 0.2 * wT, Math.cos(ph) * 0.1 * wT);
        addRot(J.neck, 0, Math.sin(ph) * 0.12 * wT, 0);
      } else {
        addRot(J.body, Math.sin(ph * 2) * 0.03 * wT, 0, Math.sin(ph) * 0.06 * wT);
        addRot(J.hip, 0, Math.sin(ph) * 0.17 * wT, -Math.cos(ph) * 0.1 * wT); addRot(J.chest, 0, -Math.sin(ph) * 0.09 * wT, 0);
      }
      addRot(J.head, Math.sin(ph * 2 + 0.6) * 0.06 * wT, Math.sin(ph) * 0.05 * wT, -Math.sin(ph) * 0.06 * wT);
      for (k = 0; k < TN; k++) addRot(J['t' + k], 0, 0, Math.sin(ph - 0.9 * k) * (0.14 + 0.07 * k) * wT);
      if (hasEar) { e = Math.sin(ph * 2 + 1) * 0.1 * wT; if (flop) { addRot(J.earL, 0, 0, -Math.abs(e) * 2); addRot(J.earR, 0, 0, Math.abs(e) * 2); } else { addRot(J.earL, e, 0, 0); addRot(J.earR, e, 0, 0); } }
    }
    if (wG > 0.003) { // gallop: fore pair and hind pair, the whole body stretches out and gathers up
      var ext = Math.cos(ph), fo = [['shL', 'elL', 0.2], ['shR', 'elR', -0.2]], hi = [['hpL', 'knL', 0.75], ['hpR', 'knR', 0.4]];
      for (i = 0; i < 2; i++) { e = Math.cos(ph + fo[i][2]); c = Math.max(0, -e); addRot(J[fo[i][0]], (-(e > 0 ? e * 1.05 : e * 0.6) - 0.06) * wG, 0, 0); addRot(J[fo[i][1]], c * 0.55 * wG, 0, 0); J[fo[i][0]].scale.y *= 1 - c * 0.26 * wG; }
      for (i = 0; i < 2; i++) { e = Math.cos(ph + hi[i][2]); c = Math.max(0, -e); addRot(J[hi[i][0]], ((e > 0 ? e * 1.05 : e * 0.7) + 0.04) * wG, 0, 0); addRot(J[hi[i][1]], c * 0.6 * wG, 0, 0); J[hi[i][0]].scale.y *= 1 - c * 0.26 * wG; }
      var gk = cv ? 0.45 : 1; if (cv) md[2] = Math.max(0, -ext) * 0.62 * wG; // the mat humps up like an inch-worm, then slaps down flat and long
      addRot(J.chest, -ext * 0.24 * gk * wG, 0, 0); addRot(J.hip, ext * 0.28 * gk * wG, 0, 0); addRot(J.neck, ext * 0.16 * wG, 0, 0); addRot(J.head, ext * 0.08 * wG, 0, 0);
      if (cv) roll += Math.sin(ph) * 0.06 * wG;
      pitch += (Math.sin(ph + 0.9) * 0.1 - 0.03) * wG;
      sx *= 1 - ext * 0.04 * wG; sy *= 1 - ext * 0.09 * wG; sz *= 1 + ext * 0.14 * wG;
      this.bob += (0.5 + 0.5 * Math.cos(ph - 0.25)) * (cv ? 0.05 : 0.13 * hS) * wG; // the stretched-out moment is the top of the bound
      addRot(J.t0, (90 - S.tail.up) * D2R * (cv ? 0.5 : 0.75) * wG, 0, 0);
      for (k = 1; k < TN; k++) addRot(J['t' + k], Math.sin(ph - 0.7 * k - 1) * 0.22 * wG - (cv ? S.tail.curl * D2R * 0.8 * wG : 0), 0, 0);
      if (hasEar) { if (flop) { e = (0.55 + 0.45 * Math.sin(ph + 1)) * 1.0 * wG; addRot(J.earL, 0, 0, -e); addRot(J.earR, 0, 0, e); } else { e = (-0.55 + Math.sin(ph * 2) * 0.12) * wG; addRot(J.earL, e, 0, 0); addRot(J.earR, e, 0, 0); } }
    }
    if (this.tongue && this.tongueFlat) { var tf2 = this.tongue; tf2.scale.set(1, 1, 0.01 + 1.3 * wG); tf2.rotation.set(0.25 * wG, Math.sin(ph * 0.5) * 0.7 * wG, 0); tf2.position.z = this.tongue0.z + 0.03 * wG; tf2.position.x = Math.sin(ph * 0.5) * 0.02 * wG; }
    else if (this.tongue) { var tg = this.tongue, tw = Math.sin(ph * 0.5); tg.scale.set(1, 1, 1 + 1.4 * wG); tg.rotation.set(0.5 - 0.25 * wG, tw * 0.9 * wG, Math.sin(ph) * 0.3 * wG); tg.position.x = this.tongue0.x + tw * S.muzzleR * 0.45 * wG; }
    if (!posed) { // lean into turns, the spine bends into them, the tail lags behind
      roll += clamp(-A.turn * 0.05 * (0.25 + Math.min(1.6, A.sp / 2.2)), -0.5, 0.5) * (0.2 + 0.8 * A.loco) * (cv ? 0.4 : 1);   // a mat turns by pivoting flat
      var yb = clamp(A.turn * (cv ? 0.075 : 0.045), -0.45, 0.45) * (0.4 + 0.6 * A.loco);
      addRot(J.chest, 0, yb, 0); addRot(J.hip, 0, -yb * 0.9, 0); addRot(J.head, 0, yb * 1.1, 0);
    }
    var lagT = posed ? 0 : clamp(-A.turn * 0.13, -0.9, 0.9);
    this.lagV = (this.lagV || 0) + ((lagT - (this.lag || 0)) * 60 - (this.lagV || 0) * 7) * dt; this.lag = (this.lag || 0) + this.lagV * dt;
    if (Math.abs(this.lag) > 0.003) for (k = 0; k < TN; k++) addRot(J['t' + k], 0, 0, this.lag * (0.5 + k * 0.3));
    // speeding up tips the nose down, braking sits back on the haunches with the front legs braced (a skid), then it springs back
    var brake = posed ? 0 : clamp(-A.acc / 12, 0, 1) * clamp(A.sp / 1.2, 0, 1), go = posed ? 0 : clamp(A.acc / 14, 0, 1);
    A.bk += (brake - A.bk) * (1 - Math.exp(-dt * (brake > A.bk ? 30 : 7)));
    A.pv += ((-A.bk * 0.3 + go * 0.14 - A.p) * 160 - A.pv * 15) * dt; A.p += A.pv * dt; pitch += A.p;
    if (A.bk > 0.01) { e = A.bk; addRot(J.shL, -e * 0.7, 0, 0); addRot(J.shR, -e * 0.7, 0, 0); addRot(J.hpL, -e * 0.55, 0, 0); addRot(J.hpR, -e * 0.55, 0, 0); J.hpL.scale.y *= 1 - e * 0.22; J.hpR.scale.y *= 1 - e * 0.22; sz *= 1 - e * 0.07; sy *= 1 - e * 0.04; if (hasEar && !flop) { addRot(J.earL, -e * 0.5, 0, 0); addRot(J.earR, -e * 0.5, 0, 0); } }
    // in the air: pop off the ground, stretch on the way up, reach for the floor on the way down
    var yw = this.root.position.y, vy = dt > 0 ? clamp((yw - A.py) / dt, -12, 12) : 0; A.py = yw; var inAir = this.air > 0.02 ? 1 : 0; if (!inAir) vy = 0;
    A.vy += (vy - A.vy) * (1 - Math.exp(-dt * 20)); if (inAir && !A.wasAir) A.launch = 1; A.wasAir = inAir;
    A.air += (inAir - A.air) * (1 - Math.exp(-dt * 16));
    if (cv) { // a jumping mat is a tossed pancake: it flips in the air and settles flat when it lands
      if (inAir) { A.airT = (A.airT || 0) + dt; if (A.airT > 0.07) A.flip = (A.flip || 0) + dt * PI * 2 / 0.85; }
      else { A.airT = 0; if (A.flip) { var ft = Math.round(A.flip / (PI * 2)) * PI * 2; A.flip += (ft - A.flip) * (1 - Math.exp(-dt * 18)); if (Math.abs(ft - A.flip) < 0.002) A.flip = 0; } }
      if (A.flip) pitch -= A.flip;
      if (A.air > 0.003) { var uu = clamp(A.vy / (2.5 * Math.sqrt(sc)), -1, 1); sz *= 1 + 0.1 * Math.max(0, uu) * A.air; sy *= 1 - 0.1 * Math.max(0, uu) * A.air; }
    } else if (A.air > 0.003) {
      var u = clamp(A.vy / (2.5 * Math.sqrt(sc)), -1, 1), up = Math.max(0, u), dn = Math.max(0, -u), a = A.air;
      addRot(J.shL, (-1.0 * up - 0.5 * dn) * a, 0, 0); addRot(J.shR, (-1.0 * up - 0.5 * dn) * a, 0, 0); addRot(J.elL, 0.5 * dn * a, 0, 0); addRot(J.elR, 0.5 * dn * a, 0, 0);
      addRot(J.hpL, (0.85 * up - 0.5 * dn) * a, 0, 0); addRot(J.hpR, (0.85 * up - 0.5 * dn) * a, 0, 0); addRot(J.knL, 0.7 * dn * a, 0, 0); addRot(J.knR, 0.7 * dn * a, 0, 0);
      pitch += (-0.28 * up + 0.24 * dn) * a; sz *= 1 + 0.15 * up * a; sy *= 1 - 0.08 * up * a; sx *= 1 - 0.04 * up * a;
      addRot(J.t0, -0.5 * a, 0, 0);
    }
    if (A.launch > 0) { A.launch = Math.max(0, A.launch - dt / 0.24); e = 1 - A.launch; var q0 = e < 0.3 ? -Math.sin(e / 0.3 * PI) * 0.2 : Math.sin((e - 0.3) / 0.7 * PI) * 0.14; sy *= 1 + q0; sx *= 1 - q0 * 0.5; sz *= 1 - q0 * 0.5; }
    if (this.squash > 0) { this.squash = Math.max(0, this.squash - dt * 5.5); var q2 = Math.sin(this.squash * PI) * (cv ? 0.45 : 0.26); sy *= 1 - q2; sx *= 1 + q2 * 0.45; sz *= 1 + q2 * 0.45; } // splat
    if (this.jig > 0) { this.jig = Math.max(0, this.jig - dt * 2.4); var wj = Math.sin(t * 24) * this.jig * (cv ? 0.09 : 0.05); sy *= 1 + wj; sx *= 1 - wj * 0.55; sz *= 1 - wj * 0.55; } // jelly wobble while being painted (owner 2026-11-26: painting must feel good)
    if (this._emote && live) { roll += Math.sin(t * 3.4) * 0.95; addRot(J.shL, Math.sin(t * 6.8) * 0.3, 0, 0); addRot(J.shR, -Math.sin(t * 6.8) * 0.3, 0, 0); addRot(J.hpL, -Math.sin(t * 6.8) * 0.25, 0, 0); addRot(J.hpR, Math.sin(t * 6.8) * 0.25, 0, 0); }
    if (this.tilt) addRot(J.head, 0, 0, this.tilt);
    if (live) { // idle life: only ever on a body that is not frozen
      var br = Math.sin(t * 2.2);
      if (cv) { J.chest.scale.x *= 1 + br * 0.008; J.chest.scale.y *= 1 + br * 0.01; J.body.scale.x *= 1 + br * 0.008; J.body.scale.y *= 1 + br * 0.01; }
      else { J.chest.scale.setScalar(1 + br * 0.012); J.body.scale.set(1 + br * 0.01, 1 + br * 0.014, 1); }
      this.flickT -= dt; if (this.flickT < 0) { this.flickT = 2.5 + r() * 4; this.flick = 1; }
      this.flick = Math.max(0, (this.flick || 0) - dt * 1.6);
      var wagA = this.wag ? 0.55 : 0.0, tw2 = Math.sin(t * (this.wag ? 13 : 1.7)) * (0.07 + wagA) + Math.sin(t * 9) * 0.5 * this.flick;
      for (k = 0; k < TN; k++) addRot(J['t' + k], 0, 0, tw2 * (0.5 + k * 0.35) * (dog && !this.wag ? 0.5 : 1));
      this.twitchT -= dt; if (this.twitchT < 0) { this.twitchT = 2 + r() * 5; this.twitch = 1; this.twSide = r() < 0.5 ? 'earL' : 'earR'; }
      this.twitch = Math.max(0, (this.twitch || 0) - dt * 5);
      if (this.twitch > 0 && J[this.twSide]) { addRot(J[this.twSide], Math.sin(this.twitch * 12) * 0.3, 0, 0); if (cv && !moving) addRot(J[this.twSide === 'earL' ? 'hpR' : 'shL'], Math.sin(this.twitch * 12) * 0.5, 0, 0); } // an ear, and a corner of the mat
      this.blinkT -= dt; if (this.blinkT < 0) this.blinkT = 2.2 + r() * 4;
      var bl = this.blinkT < 0.14 ? 0.12 : 1;
      this.lookT -= dt; if (this.lookT < 0) { this.lookT = 1.5 + r() * 3.5; this.lookTo = [(r() - 0.5) * 0.7, (r() - 0.5) * 0.3]; }
      this.look[0] += (this.lookTo[0] - this.look[0]) * Math.min(1, dt * 4); this.look[1] += (this.lookTo[1] - this.look[1]) * Math.min(1, dt * 4);
      var lk = cv ? Math.max(0, 1 - this.cm[0] - this.cm[1] - this.cm[2]) : 1;
      if (!moving && lk > 0.01) addRot(J.head, this.look[1] * lk, this.look[0] * lk, 0);
      for (i = 0; i < this.eyes.length; i++) this.eyes[i].scale.set(1, bl * this.eyesOpen + 0.02, 1);
    } else if (!cv) { J.chest.scale.setScalar(1); J.body.scale.setScalar(1); }
    this._airK = posed ? 0 : A.air;
    if (pitch || roll) addRot(this.pivot, pitch, 0, roll);
    var ps = this.pivot.scale; ps.x *= sx; ps.y *= sy; ps.z *= sz;
  };

  /* ---------- painting ---------- */
  P._bsphere = function () {
    if (this._bsVer === this.ver) return;
    var PV = this.PV, n = this.bp.nv * 3, mn = [1e9, 1e9, 1e9], mx = [-1e9, -1e9, -1e9], i, q, r = 0;
    for (i = 0; i < n; i += 3) for (q = 0; q < 3; q++) { var v = PV[i + q]; if (v < mn[q]) mn[q] = v; if (v > mx[q]) mx[q] = v; }
    var c = this._bc || (this._bc = [0, 0, 0]); c[0] = (mn[0] + mx[0]) / 2; c[1] = (mn[1] + mx[1]) / 2; c[2] = (mn[2] + mx[2]) / 2;
    this._br = Math.hypot(mx[0] - mn[0], mx[1] - mn[1], mx[2] - mn[2]) / 2; this._bmn = mn; this._bmx = mx; this._bsVer = this.ver;
  };
  P._bounds = function (p) {
    if (p.bVer === this.ver) return;
    var PV = this.PV, b = p.bp, mn = [1e9, 1e9, 1e9], mx = [-1e9, -1e9, -1e9], i, q, r = 0;
    for (i = b.v0 * 3; i < b.v1 * 3; i += 3) for (q = 0; q < 3; q++) { var v = PV[i + q]; if (v < mn[q]) mn[q] = v; if (v > mx[q]) mx[q] = v; }
    p.c.set((mn[0] + mx[0]) / 2, (mn[1] + mx[1]) / 2, (mn[2] + mx[2]) / 2); p.r = Math.hypot(mx[0] - mn[0], mx[1] - mn[1], mx[2] - mn[2]) / 2; p.bVer = this.ver;
  };
  /* posed position of every texel of a part (pivot space), from the triangle it shows */
  P._tp = function (p) {
    if (p.tp && p.tpVer === this.ver) return p.tp;
    var b = p.bp, n = p.tw * p.th, tp = p.tp || (p.tp = new Float32Array(n * 3)), tix = b.tix, tb = b.tb, idx = this.bp.idx, PV = this.PV;
    for (var k = 0; k < n; k++) {
      var t = tix[k]; if (t < 0) { tp[k * 3] = 1e9; continue; }
      var a = idx[t * 3] * 3, bb = idx[t * 3 + 1] * 3, c = idx[t * 3 + 2] * 3, w1 = tb[k * 2], w2 = tb[k * 2 + 1], w0 = 1 - w1 - w2;
      tp[k * 3] = w0 * PV[a] + w1 * PV[bb] + w2 * PV[c]; tp[k * 3 + 1] = w0 * PV[a + 1] + w1 * PV[bb + 1] + w2 * PV[c + 1]; tp[k * 3 + 2] = w0 * PV[a + 2] + w1 * PV[bb + 2] + w2 * PV[c + 2];
    }
    p.tpVer = this.ver; return tp;
  };
  /* nearest hit of a ray on the body as it is posed right now. Returns { distance, point, part, faceIndex, face: { normal } } (world space) or null */
  P.raycast = function (raycaster) {
    this.root.updateWorldMatrix(true, false);
    _m.copy(this.root.matrixWorld).invert();
    var ray = raycaster.ray, po = this.pivot.position, o = _v.copy(ray.origin).applyMatrix4(_m), d = _v2.copy(ray.origin).add(ray.direction).applyMatrix4(_m).sub(o), len = d.length();
    d.multiplyScalar(1 / len); o.sub(po);
    this._bsphere();
    var bc = this._bc, cx = bc[0] - o.x, cy = bc[1] - o.y, cz = bc[2] - o.z, tc = cx * d.x + cy * d.y + cz * d.z, d2 = cx * cx + cy * cy + cz * cz - tc * tc;
    if (d2 > this._br * this._br) return null;
    var far = (raycaster.far == null ? Infinity : raycaster.far) * len, near = (raycaster.near || 0) * len, best = far, bt = -1;
    if (tc - this._br > far) return null;
    var PV = this.PV, idx = this.bp.idx, nt = this.bp.nt, ox = o.x, oy = o.y, oz = o.z, dx = d.x, dy = d.y, dz = d.z;
    for (var t = 0; t < nt; t++) {
      var a = idx[t * 3] * 3, b = idx[t * 3 + 1] * 3, c = idx[t * 3 + 2] * 3, ax = PV[a], ay = PV[a + 1], az = PV[a + 2];
      var e1x = PV[b] - ax, e1y = PV[b + 1] - ay, e1z = PV[b + 2] - az, e2x = PV[c] - ax, e2y = PV[c + 1] - ay, e2z = PV[c + 2] - az;
      var px = dy * e2z - dz * e2y, py = dz * e2x - dx * e2z, pz = dx * e2y - dy * e2x, det = e1x * px + e1y * py + e1z * pz;
      if (det < 1e-14) continue;
      var tx = ox - ax, ty = oy - ay, tz = oz - az, u = tx * px + ty * py + tz * pz; if (u < 0 || u > det) continue;
      var qx = ty * e1z - tz * e1y, qy = tz * e1x - tx * e1z, qz = tx * e1y - ty * e1x, v = dx * qx + dy * qy + dz * qz; if (v < 0 || u + v > det) continue;
      var tt = (e2x * qx + e2y * qy + e2z * qz) / det; if (tt > near && tt < best) { best = tt; bt = t; }
    }
    if (bt < 0) return null;
    var dist = best / len, part = null, i;
    for (i = 0; i < this.parts.length; i++) if (bt >= this.parts[i].bp.i0 && bt < this.parts[i].bp.i1) { part = this.parts[i]; break; }
    a = idx[bt * 3] * 3; b = idx[bt * 3 + 1] * 3; c = idx[bt * 3 + 2] * 3;
    var nrm = new THREE.Vector3().set((PV[b + 1] - PV[a + 1]) * (PV[c + 2] - PV[a + 2]) - (PV[b + 2] - PV[a + 2]) * (PV[c + 1] - PV[a + 1]), (PV[b + 2] - PV[a + 2]) * (PV[c] - PV[a]) - (PV[b] - PV[a]) * (PV[c + 2] - PV[a + 2]), (PV[b] - PV[a]) * (PV[c + 1] - PV[a + 1]) - (PV[b + 1] - PV[a + 1]) * (PV[c] - PV[a])).transformDirection(this.root.matrixWorld);
    return { distance: dist, point: ray.origin.clone().addScaledVector(ray.direction, dist), object: this.skin, part: part, faceIndex: bt, face: { normal: nrm } };
  };
  /* 3D brush: every texel within `radius` of the world point is painted, on every part — seams and joints just work */
  /* pat (optional): { type: 'stripe'|'check'|'wood'|'tatami', dir, perp (world unit vectors: along / across the stroke), rgb2, scale } */
  P.paint = function (wp, radius, rgb, rough, metal, hard, pat) {
    if (!this.alb) return false;
    var A = this.A, alb = this.alb, orm = this.orm, any = false, R = radius / this.scale, R2 = R * R, po = this.pivot.position;
    hard = hard == null ? 0.7 : hard;
    var inner = R * hard, span = Math.max(1e-5, R - inner), rb = Math.round(rough * 255), mb = Math.round(metal * 255);
    this.root.updateWorldMatrix(true, false);
    var E = this.root.matrixWorld.elements;
    _m.copy(this.root.matrixWorld).invert(); _v.copy(wp).applyMatrix4(_m);
    var lx = _v.x - po.x, ly = _v.y - po.y, lz = _v.z - po.z, cr = rgb[0], cg = rgb[1], cb = rgb[2];
    if (pat) { var D = pat.dir, Q = pat.perp, sc = pat.scale, c2 = pat.rgb2;
      var dlx = E[0] * D.x + E[1] * D.y + E[2] * D.z, dly = E[4] * D.x + E[5] * D.y + E[6] * D.z, dlz = E[8] * D.x + E[9] * D.y + E[10] * D.z, dof = (E[12] + E[0] * po.x + E[4] * po.y + E[8] * po.z) * D.x + (E[13] + E[1] * po.x + E[5] * po.y + E[9] * po.z) * D.y + (E[14] + E[2] * po.x + E[6] * po.y + E[10] * po.z) * D.z;
      var plx = E[0] * Q.x + E[1] * Q.y + E[2] * Q.z, ply = E[4] * Q.x + E[5] * Q.y + E[6] * Q.z, plz = E[8] * Q.x + E[9] * Q.y + E[10] * Q.z, pof = (E[12] + E[0] * po.x + E[4] * po.y + E[8] * po.z) * Q.x + (E[13] + E[1] * po.x + E[5] * po.y + E[9] * po.z) * Q.y + (E[14] + E[2] * po.x + E[6] * po.y + E[10] * po.z) * Q.z; }
    for (var pi = 0; pi < this.parts.length; pi++) {
      var p = this.parts[pi];
      this._bounds(p);
      if (Math.hypot(lx - p.c.x, ly - p.c.y, lz - p.c.z) > R + p.r) continue;
      var tp = this._tp(p), tw = p.tw, th = p.th, k = 0, saved = !this._stroke;
      for (var j = 0; j < th; j++) {
        var row = ((p.ry + j) * A + p.rx) * 4;
        for (var i = 0; i < tw; i++, k += 3) {
          var dx = tp[k] - lx; if (dx > R || dx < -R) continue;
          var dy = tp[k + 1] - ly, dz = tp[k + 2] - lz, d2 = dx * dx + dy * dy + dz * dz;
          if (d2 > R2) continue;
          if (!saved) { this._save(pi); saved = true; }
          var d = Math.sqrt(d2), a = d <= inner ? 1 : 1 - (d - inner) / span;
          a = a * a * (3 - 2 * a);
          var o = row + i * 4;
          if (pat) { // pattern coordinates are world-space, so the pattern runs unbroken across body parts
            var sC = tp[k] * dlx + tp[k + 1] * dly + tp[k + 2] * dlz + dof, tC = tp[k] * plx + tp[k + 1] * ply + tp[k + 2] * plz + pof, m = 0, v;
            if (pat.type === 'stripe') m = Math.floor(tC / sc) & 1;
            else if (pat.type === 'check') m = (Math.floor(sC / sc) + Math.floor(tC / sc)) & 1;
            else if (pat.type === 'wood') { v = tC / sc * 2.2 + Math.sin(sC * 11) * 0.22 + Math.sin(sC * 3.1 + tC * 40) * 0.1; var fv = v - Math.floor(v), hv = Math.sin(Math.floor(v) * 127.1) * 43758.5; m = fv < 0.16 ? 1 : (hv - Math.floor(hv)) * 0.4; }
            else { v = tC / 0.0055; m = (Math.floor(v) & 1) ? 0.4 : 0; var cv2 = sC / 0.034; if (cv2 - Math.floor(cv2) < 0.09) m = 0.75; }
            cr = rgb[0] + (c2[0] - rgb[0]) * m; cg = rgb[1] + (c2[1] - rgb[1]) * m; cb = rgb[2] + (c2[2] - rgb[2]) * m;
          }
          alb[o] += (cr - alb[o]) * a; alb[o + 1] += (cg - alb[o + 1]) * a; alb[o + 2] += (cb - alb[o + 2]) * a;
          orm[o + 1] += (rb - orm[o + 1]) * a; orm[o + 2] += (mb - orm[o + 2]) * a;
          any = true;
        }
      }
    }
    if (any) { this.texA.needsUpdate = true; this.texO.needsUpdate = true; }
    return any;
  };
  P._save = function (pi) {
    var st = this._stroke; if (!st || st.parts[pi]) return;
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
  P.copyPaintFrom = function (other) { if (other.A !== this.A || other.bp !== this.bp) console.warn('copyPaintFrom: different build or atlas size'); this.alb.set(other.alb); this.orm.set(other.orm); this.texA.needsUpdate = true; this.texO.needsUpdate = true; };
  P.fill = function (rgb, rough, metal) {
    if (this._stroke) for (var q = 0; q < this.parts.length; q++) this._save(q);
    var alb = this.alb, orm = this.orm, rb = Math.round(rough * 255), mb = Math.round(metal * 255);
    for (var pi = 0; pi < this.parts.length; pi++) { var p = this.parts[pi]; for (var j = 0; j < p.th; j++) { var i = ((p.ry + j) * this.A + p.rx) * 4, e = i + p.tw * 4; for (; i < e; i += 4) { alb[i] = rgb[0]; alb[i + 1] = rgb[1]; alb[i + 2] = rgb[2]; orm[i + 1] = rb; orm[i + 2] = mb; } } }
    this.texA.needsUpdate = true; this.texO.needsUpdate = true;
  };
  P.snapshot = function () { return { a: this.alb.slice(), o: this.orm.slice() }; };
  P.restore = function (s) { this.alb.set(s.a); this.orm.set(s.o); this.texA.needsUpdate = true; this.texO.needsUpdate = true; };
  /* visit every texel with its current world position: fn(x,y,z, partName, i, j) -> [r,g,b] or null */
  P.eachTexel = function (fn, step) {
    var A = this.A, alb = this.alb, po = this.pivot.position, idx = this.bp.idx, PV = this.PV;
    this.root.updateMatrixWorld(true);
    var e = this.root.matrixWorld.elements;
    for (var pi = 0; pi < this.parts.length; pi++) {
      var p = this.parts[pi], b = p.bp, tix = b.tix, tb = b.tb, tw = p.tw, th = p.th;
      for (var j = 0; j < th; j++) for (var i = 0; i < tw; i++) {
        var k = j * tw + i, t = tix[k]; if (t < 0) continue;
        var a = idx[t * 3] * 3, bb = idx[t * 3 + 1] * 3, cc = idx[t * 3 + 2] * 3, w1 = tb[k * 2], w2 = tb[k * 2 + 1], w0 = 1 - w1 - w2;
        var x = w0 * PV[a] + w1 * PV[bb] + w2 * PV[cc] + po.x, y = w0 * PV[a + 1] + w1 * PV[bb + 1] + w2 * PV[cc + 1] + po.y, z = w0 * PV[a + 2] + w1 * PV[bb + 2] + w2 * PV[cc + 2] + po.z;
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
    var out = [], po = this.pivot.position;
    this.root.updateWorldMatrix(true, false);
    for (var i = 0; i < this.parts.length; i++) { var p = this.parts[i]; this._bounds(p); out.push({ c: p.c.clone().add(po).applyMatrix4(this.root.matrixWorld), r: p.r * this.scale * 0.85 }); }
    return out;
  };
  P.center = function (out) {
    out = out || new THREE.Vector3(); var b = this.ji.body * 16, po = this.pivot.position;
    this.root.updateWorldMatrix(true, false);
    return out.set(this.REL[b + 12] + po.x, this.REL[b + 13] + po.y, this.REL[b + 14] + po.z).applyMatrix4(this.root.matrixWorld);
  };
  /* size of the body as posed right now, in world units: { min, max, size } along the root's own axes (y = away from the surface it is on) */
  P.measure = function () {
    this._bsphere(); var s = this.scale, mn = this._bmn, mx = this._bmx, po = this.pivot.position;
    return { min: [(mn[0] + po.x) * s, (mn[1] + po.y) * s, (mn[2] + po.z) * s], max: [(mx[0] + po.x) * s, (mx[1] + po.y) * s, (mx[2] + po.z) * s], size: [(mx[0] - mn[0]) * s, (mx[1] - mn[1]) * s, (mx[2] - mn[2]) * s] };
  };
  /* jump straight to the pose (no blending): for spawning already-posed bodies, icons and tests */
  P.settle = function () { this.madd[0] = this.madd[1] = this.madd[2] = 0; this._blend(1); this._morph(); this._pose(); this._limbs(); this._solve(true); };

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
      if (name === 'head') under = Math.max(under, (Math.abs(p[0]) > S.headR * 0.5 && p[1] < S.headY ? 1.5 : -1));
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
      if (name === 'muzzle' || name.indexOf('jowl') === 0 || name === 'jaw') w = -2;
      if (name === 'head') w = p[0] > S.headR * 0.12 ? 2 : -2;
      if (name === 'earR') w = 2;
      if (name.slice(-1) === 'D') w = -2;
      var c = mix3(wh, br, w), k = vnoise(p[0] * 80, p[1] * 80, p[2] * 80) * 10 - 5; return [c[0] + k, c[1] + k, c[2] + k];
    },
    dachs: function (p, h, name, S) {
      var br = [112, 62, 36], tan = [206, 150, 96];
      var w = (0.22 - h) * 10; if (name === 'muzzle') w = p[1] < S.headY - S.headR * 0.25 ? 2 : -1; if (name.slice(-1) === 'D') w = 2; if (name === 'chest') w = Math.max(w, (p[2] - S.len * 0.36) * 30);
      var c = mix3(br, tan, w), n = vnoise(p[0] * 90, p[1] * 90, p[2] * 90) * 10 - 5; return [c[0] + n, c[1] + n, c[2] + n];
    },
    husky: function (p, h, name, S) {
      var gr = [96, 102, 112], wh = [250, 250, 246];
      var w = (0.42 - h) * 9 + vnoise(p[0] * 20, p[1] * 20, p[2] * 20) * 0.8;
      if (name === 'muzzle') w = 2; if (name === 'head') w = Math.max((S.headR * 0.5 - Math.abs(p[0])) * 30 - (p[1] - S.headY) * 40 - 1.2, (S.headY - p[1]) * 30); if (name.slice(-1) === 'D' || name === 'ruff') w = 2; if (name.indexOf('ear') === 0) w = -1;
      if (name.indexOf('tail') === 0) w = p[1] < 0.1 ? 1.5 : -1;
      var c = mix3(gr, wh, w), n = vnoise(p[0] * 90, p[1] * 90, p[2] * 90) * 12 - 6; return [c[0] + n, c[1] + n, c[2] + n];
    },
    poodle: function (p, h, name, S) {
      var a = [226, 180, 142], b = [196, 146, 108];
      var n = vnoise(p[0] * 60, p[1] * 60, p[2] * 60), n2 = vnoise(p[0] * 150 + 9, p[1] * 150, p[2] * 150);
      return mix3(b, a, n * 0.8 + n2 * 0.5 - 0.1);
    }
  };
  /* coats for the flat dogs. p = rest position relative to the middle of the slab (x across, y up, z forward), name = atlas part, D = body dimensions */
  function under(p, D, name) { return name.indexOf('leg') === 0 ? 2 : (-p[1] / D.hh - 0.15) * 4; } // > 0 on the underside and the stubs
  var FCOATS = {
    shiba: function (p, h, name, D) { var u = Math.max(under(p, D, name), (p[2] - (D.zH + D.hD * 0.45)) * 40, name === 'tail' ? (-p[2] - D.L / 2 - 0.05) * 60 : -1) + vnoise(p[0] * 30, p[1] * 30, p[2] * 30) * 0.5 - 0.25, c = mix3([214, 136, 62], [250, 240, 222], u), n = vnoise(p[0] * 90, p[1] * 90, p[2] * 90) * 12 - 6; return [c[0] + n, c[1] + n, c[2] + n]; },
    corgi: function (p, h, name, D) { var blaze = p[2] > D.zb3 - 0.02 ? (D.hW * 0.28 - Math.abs(p[0])) * 60 : -1, u = Math.max(under(p, D, name), blaze, (p[2] - (D.zH + D.hD * 0.55)) * 40), c = mix3([226, 150, 72], [252, 248, 240], u), n = vnoise(p[0] * 90, p[1] * 90, p[2] * 90) * 10 - 5; return [c[0] + n, c[1] + n, c[2] + n]; },
    bull: function (p, h, name, D) { var w = (vnoise(p[0] * 6 + 3.1, p[1] * 6, p[2] * 6 + 1.7) - 0.5) * 16; if (name === 'head' || name === 'face' || name === 'neck') w = p[0] > D.hW * 0.1 && p[2] < D.zH + D.hD * 0.4 ? 2 : -2; if (name === 'earR') w = 2; if (name.indexOf('leg') === 0) w = -2; var c = mix3([248, 244, 236], [128, 86, 58], w), k = vnoise(p[0] * 80, p[1] * 80, p[2] * 80) * 8 - 4; return [c[0] + k, c[1] + k, c[2] + k]; },
    poodle: function (p) { return mix3([196, 146, 108], [226, 180, 142], vnoise(p[0] * 60, p[1] * 60, p[2] * 60) * 0.8 + vnoise(p[0] * 150 + 9, p[1] * 150, p[2] * 150) * 0.5 - 0.1); },
    dachs: function (p, h, name, D) { var u = Math.max(under(p, D, name), (p[2] - (D.zH + D.hD * 0.3)) * 30 - (p[1] > D.hy ? 3 : 0)), c = mix3([112, 62, 36], [206, 150, 96], u), n = vnoise(p[0] * 90, p[1] * 90, p[2] * 90) * 10 - 5; return [c[0] + n, c[1] + n, c[2] + n]; },
    husky: function (p, h, name, D) { var mask = p[2] > D.zb4 ? (D.hW * 0.42 - Math.abs(p[0])) * 50 + (p[2] - D.zH) * 20 : -1, u = Math.max(under(p, D, name) + vnoise(p[0] * 20, p[1] * 20, p[2] * 20) * 0.8 - 0.4, mask, name === 'tail' ? (-p[2] - D.L / 2 - 0.07) * 50 : -1), c = mix3([96, 102, 112], [250, 250, 246], u), n = vnoise(p[0] * 90, p[1] * 90, p[2] * 90) * 10 - 5; if (name.indexOf('ear') === 0) c = [96, 102, 112]; return [c[0] + n, c[1] + n, c[2] + n]; }
  };
  /* jelly coats. Cats: plain white with two light-grey eye dots, all of it paintable. Dogs: one soft colour, darker ears, light snout */
  function jEyes(p, D, rgb) { var e = D.eyeP, dx = Math.abs(p[0]) - e[0], dy = p[1] - e[1]; return p[2] > D.hD * 0.45 && dx * dx / (0.017 * 0.017) + dy * dy / (0.024 * 0.024) < 1 ? rgb : null; }
  var JCOATS = {
    blank: function () { return [245, 245, 243]; },
    jcat: function (p, h, name, D) { return (name === 'body' && jEyes(p, D, [132, 126, 118])) || [246, 245, 241]; },
    jshiba: function (p, h, name, D) { if (name.indexOf('ear') === 0) return [150, 98, 58]; if (name === 'snout' || (name === 'body' && p[1] < 0 && p[2] > D.Rb * D.dp * 0.4)) return [248, 236, 214]; var n = vnoise(p[0] * 40, p[1] * 40, p[2] * 40) * 8 - 4; return [222 + n, 168 + n, 108 + n]; },
    jcorgi: function (p, h, name, D) { if (name === 'snout' || (name === 'body' && p[2] > D.Rb * D.dp * 0.55 && Math.abs(p[0]) < 0.09)) return [252, 246, 236]; return [232, 150, 72]; },
    jhusky: function (p, h, name, D) { if (name.indexOf('ear') === 0) return [96, 102, 112]; if (name === 'snout' || (name === 'body' && (p[1] < D.hy - 0.05 ? p[2] > D.Rb * D.dp * 0.4 : p[2] > D.hD * 0.5 && Math.abs(p[0]) < 0.07))) return [250, 250, 246]; return [120, 126, 136]; }
  };
  P.applyCoat = function (fn) {
    var self = this, S = this.spec, ext = { len: S.len, headR: S.headR }, po = this.pivot.position;
    this.root.updateMatrixWorld(true);
    var inv = new THREE.Matrix4().copy(this.root.matrixWorld).invert(), bi = this.ji.body * 16, hi = this.ji.head * 16;
    var by = this.REL[bi + 13] + po.y, bz = this.REL[bi + 14] + po.z, hy = this.REL[hi + 13] + po.y, top = 0;
    ext.headY = hy - by + S.headR * 0.42; ext.neckY = hy - by;
    this.parts.forEach(function (p) { var y; if (p.bp.o) y = p.bp.o[1] + po.y + p.bp.r0; else { self._bounds(p); y = p.c.y + po.y + p.r; } if (y > top) top = y; });
    var e = inv.elements, pp = [0, 0, 0];
    this.eachTexel(function (x, y, z, name) {
      var lx = e[0] * x + e[4] * y + e[8] * z + e[12], ly = e[1] * x + e[5] * y + e[9] * z + e[13], lz = e[2] * x + e[6] * y + e[10] * z + e[14];
      pp[0] = lx; pp[1] = ly - by; pp[2] = lz - bz;
      var c = fn(pp, ly / top, name, self.canvas ? self.bp.D : ext);
      return [Math.max(0, Math.min(255, c[0])), Math.max(0, Math.min(255, c[1])), Math.max(0, Math.min(255, c[2]))];
    });
  };
  P.dispose = function () {
    if (this.texA) { this.texA.dispose(); this.texO.dispose(); } this.mat.dispose(); this.skin.geometry.dispose(); this.skin.skeleton.dispose();
    if (this.faceMat) { this.faceMat.dispose(); this.faceSkin.geometry.dispose(); this.faceSkin.skeleton.dispose(); this.decos.forEach(function (m) { m.geometry.dispose(); }); }
    this.parts.forEach(function (p) { p.tp = null; });
  };

  /* ---------- pose icons: a small picture of the real mesh in each pose, drawn on a 2D canvas (no extra GL context) ----------
     SG.poseIcon(pose, { size = 96, spec = SG.CATS.person, amount, yaw = 0.75, pitch = 0.42, tail = 'tuck', ears = 'flat', color = '#f6f3ec', line = 'rgba(54,40,30,0.9)' }) -> canvas
     SG.poseIconURL(pose, opts) -> data URL (cached) */
  var ICONC = {}, ICONU = {};
  SG.poseIcon = function (pose, o) {
    o = o || {}; var size = o.size || 96, spec = o.spec || CATS.person, yaw = o.yaw == null ? 0.75 : o.yaw, pit = o.pitch == null ? 0.42 : o.pitch, key = JSON.stringify(spec);
    var c = ICONC[key] || (ICONC[key] = new Critter(spec, { bare: true }));
    c.tailMode = o.tail || 'tuck'; c.earMode = o.ears || 'flat'; c.setPose(pose, o.amount); if (o.amount == null) c.setPose(pose, (PT(spec)[ALIAS[pose] || pose] || PT(spec).stand).amt); c.settle();
    var cvs = document.createElement('canvas'); cvs.width = cvs.height = size * 2;
    var g = cvs.getContext('2d'), PV = c.PV, idx = c.bp.idx, nt = c.bp.nt, nv = c.bp.nv, X = new Float32Array(nv), Y = new Float32Array(nv), Z = new Float32Array(nv), i;
    var cy = Math.cos(yaw), sy = Math.sin(yaw), cp = Math.cos(pit), sp = Math.sin(pit), mnx = 1e9, mxx = -1e9, mny = 1e9, mxy = -1e9;
    for (i = 0; i < nv; i++) { var x = PV[i * 3], y = PV[i * 3 + 1] + c.liftY, z = PV[i * 3 + 2], xr = x * cy - z * sy, zr = x * sy + z * cy, yr = y * cp - zr * sp, zz = y * sp + zr * cp; X[i] = xr; Y[i] = yr; Z[i] = zz; if (xr < mnx) mnx = xr; if (xr > mxx) mxx = xr; if (yr < mny) mny = yr; if (yr > mxy) mxy = yr; }
    var span = Math.max(o.span || 0, mxx - mnx, mxy - mny), k = size * 2 * 0.86 / span, ox = size - (mnx + mxx) / 2 * k, oy = size + (mny + mxy) / 2 * k;
    var tris = [];
    for (i = 0; i < nt; i++) {
      var a = idx[i * 3], b = idx[i * 3 + 1], d = idx[i * 3 + 2], ux = X[b] - X[a], uy = Y[b] - Y[a], uz = Z[b] - Z[a], vx = X[d] - X[a], vy = Y[d] - Y[a], vz = Z[d] - Z[a];
      var nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx, l = Math.hypot(nx, ny, nz); if (l < 1e-12 || nz <= 0) continue; // faces turned to the viewer only
      tris.push([Z[a] + Z[b] + Z[d], a, b, d, clamp(0.3 + 0.7 * ((nx * -0.35 + ny * 0.75 + nz * 0.56) / l), 0, 1)]);
    }
    tris.sort(function (p, q) { return p[0] - q[0]; });
    function path(t) { g.beginPath(); g.moveTo(ox + X[t[1]] * k, oy - Y[t[1]] * k); g.lineTo(ox + X[t[2]] * k, oy - Y[t[2]] * k); g.lineTo(ox + X[t[3]] * k, oy - Y[t[3]] * k); g.closePath(); }
    g.lineJoin = 'round'; g.strokeStyle = g.fillStyle = o.line || 'rgba(54,40,30,0.9)'; g.lineWidth = Math.max(3, size * 0.07);
    for (i = 0; i < tris.length; i++) { path(tris[i]); g.stroke(); }
    var col = o.color || '#f6f3ec', r0 = parseInt(col.slice(1, 3), 16), g0 = parseInt(col.slice(3, 5), 16), b0 = parseInt(col.slice(5, 7), 16);
    g.lineWidth = 1.2;
    for (i = 0; i < tris.length; i++) { var sh = 0.66 + 0.34 * tris[i][4]; g.fillStyle = g.strokeStyle = 'rgb(' + Math.round(r0 * sh) + ',' + Math.round(g0 * sh) + ',' + Math.round(b0 * sh) + ')'; path(tris[i]); g.fill(); g.stroke(); }
    var out = document.createElement('canvas'); out.width = out.height = size; var g2 = out.getContext('2d'); g2.imageSmoothingQuality = 'high'; g2.drawImage(cvs, 0, 0, size, size);
    return out;
  };
  SG.poseIconURL = function (pose, o) { var key = pose + JSON.stringify(o || {}); return ICONU[key] || (ICONU[key] = SG.poseIcon(pose, o).toDataURL()); };

  SG.Critter = Critter;
})();
