/* 貓躲狗找 — HTML/CSS interface: title, HUD, paint panel, pose wheel, reveal. Listens to SG.bus, calls SG.game actions. */
(function () {
  'use strict';
  var SG = (window.SG = window.SG || {});
  var root, G, RULES, bus, els = {};
  function h(tag, cls, html, parent) { var e = document.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; if (parent) parent.appendChild(e); return e; }
  function show(e, on) { e.classList.toggle('hide', !on); }
  var IC = {
    paw: '<svg class="ic" viewBox="0 0 24 24"><ellipse cx="12" cy="16" rx="6" ry="4.8"/><ellipse cx="4.6" cy="10.6" rx="2.3" ry="3"/><ellipse cx="9.2" cy="6.2" rx="2.4" ry="3.2"/><ellipse cx="14.8" cy="6.2" rx="2.4" ry="3.2"/><ellipse cx="19.4" cy="10.6" rx="2.3" ry="3"/></svg>',
    brush: '<svg class="ic" viewBox="0 0 24 24"><path d="M20.7 3.3a2 2 0 0 0-2.8 0l-8.2 8.2 2.8 2.8 8.2-8.2a2 2 0 0 0 0-2.8zM8.5 12.9c-2.3.2-3.5 1.6-3.8 3.6-.2 1.4-.8 2.3-2 2.9 2.6 1.2 7.300 0.600 8.200-3.300z"/></svg>',
    drop: '<svg class="ic" viewBox="0 0 24 24"><path d="M19.8 4.2a3 3 0 0 0-4.2 0l-2.300 2.300-1.100-1.100-1.800 1.800 1.100 1.100-7.300 7.300L3.500 20.500l4.900-.7 7.300-7.300 1.100 1.100 1.800-1.800-1.100-1.100 2.300-2.300a3 3 0 0 0 0-4.200zM7.400 17.900l-1.600.2.2-1.600 6.700-6.700 1.400 1.400z"/></svg>',
    fill: '<svg class="ic" viewBox="0 0 24 24"><path d="M10.2 2.600 8.800 4l2.200 2.200-6.300 6.300a1.800 1.800 0 0 0 0 2.500l5 5a1.800 1.800 0 0 0 2.500 0l7.200-7.200zM6.300 13.500l5.900-5.900 5.900 5.900zM19.500 15s-2.300 2.700-2.300 4.300a2.300 2.300 0 0 0 4.600 0c0-1.600-2.300-4.300-2.300-4.300z"/></svg>',
    undo: '<svg class="ic" viewBox="0 0 24 24"><path d="M8.500 4 3 9.500 8.500 15v-3.700h5.700a3.300 3.300 0 0 1 0 6.600H9v2.700h5.200a6 6 0 0 0 0-12H8.500z"/></svg>',
    soft: '<svg class="ic" viewBox="0 0 24 24"><circle cx="12" cy="12" r="5"/><circle cx="12" cy="12" r="9" opacity=".3"/></svg>',
    eye: '<svg class="ic" viewBox="0 0 24 24"><path d="M12 5C6.500 5 2.500 9.500 1.500 12c1 2.500 5 7 10.500 7s9.500-4.500 10.500-7C21.500 9.500 17.500 5 12 5zm0 11.200a4.200 4.200 0 1 1 0-8.400 4.200 4.200 0 0 1 0 8.400zm0-6.400a2.200 2.200 0 1 0 0 4.400 2.200 2.200 0 0 0 0-4.400z"/></svg>'
  };
  var PHASE = { prep: '躲藏準備', seek: '搜索中', reveal: '揭曉', lobby: '大廳' };
  var GUIDE = ['用 <span class="key">W</span><span class="key">A</span><span class="key">S</span><span class="key">D</span> 走動，<span class="key">空白</span> 跳上家具，找個好位置', '按住 <span class="key">R</span> 或點左下角，擺一個姿勢', '按 <span class="key">F</span> 打開塗色', '按住 <span class="key">Alt</span> 點一下旁邊的東西取色，或點色票', '在自己身上按住左鍵塗色，右鍵拖曳可以轉視角', '很好！繼續塗到看不出來，準備好了按 <span class="key">Enter</span>'];

  /* ---------- colour helpers ---------- */
  function hsv2rgb(h, s, v) { var f = function (n) { var k = (n + h / 60) % 6; return Math.round(255 * (v - v * s * Math.max(0, Math.min(k, 4 - k, 1)))); }; return [f(5), f(3), f(1)]; }
  function rgb2hsv(r, g, b) { r /= 255; g /= 255; b /= 255; var mx = Math.max(r, g, b), mn = Math.min(r, g, b), d = mx - mn, hh = 0; if (d) { if (mx === r) hh = ((g - b) / d) % 6; else if (mx === g) hh = (b - r) / d + 2; else hh = (r - g) / d + 4; hh *= 60; if (hh < 0) hh += 360; } return [hh, mx ? d / mx : 0, mx]; }
  function hex(c) { return '#' + c.map(function (x) { return ('0' + Math.round(x).toString(16)).slice(-2); }).join(''); }
  function css(c) { return 'rgb(' + c[0] + ',' + c[1] + ',' + c[2] + ')'; }

  /* own slider (no browser default look) */
  function slider(parent, label, o) {
    var row = h('div', 'sl' + (o.wide ? ' wide' : ''), '<span>' + label + '</span><div class="tr hit"><div class="th"></div></div><span class="v"></span>', parent);
    var tr = row.children[1], th = tr.firstChild, vv = row.children[2], val = o.value;
    function set(v, silent) { val = Math.max(o.min, Math.min(o.max, v)); th.style.left = ((val - o.min) / (o.max - o.min) * 100) + '%'; vv.textContent = o.fmt ? o.fmt(val) : Math.round(val); if (!silent && o.on) o.on(val); }
    function fromEv(e) { var r = tr.getBoundingClientRect(); set(o.min + (e.clientX - r.left) / r.width * (o.max - o.min)); }
    tr.addEventListener('pointerdown', function (e) { tr.setPointerCapture(e.pointerId); fromEv(e); tr.onpointermove = fromEv; e.preventDefault(); });
    tr.addEventListener('pointerup', function () { tr.onpointermove = null; });
    set(val, true);
    return { set: function (v) { set(v, true); }, get: function () { return val; }, track: tr, row: row, label: row.firstChild };
  }

  var ui = (SG.ui = {
    init: function () {
      root = document.getElementById('ui'); G = SG.game; RULES = SG.RULES; bus = SG.bus;
      buildTitle(); buildHud(); buildPaint(); buildModals();
      bus.on('mode', onMode); bus.on('phase', onPhase); bus.on('frame', onFrame);
      bus.on('guide', function (d) { setGuide(d.step); });
      bus.on('pose', function (d) { markPose(d.pose); show(els.pw, false); });
      bus.on('paintmode', function (d) { els.pp.classList.toggle('off', !d.on); els.bPaint.classList.toggle('act', d.on); show(els.ring, d.on); if (d.on) refreshSug(); });
      bus.on('picked', function (d) { P.setRGB(d.rgb); P.rough.set(d.rough); P.metal.set(d.metal); addRecent(d.rgb); });
      bus.on('wheel', function (d) { if (!(G.me && G.me.team === 'cat' && G.state.phase !== 'reveal')) return; if (!d.open && ui.hoverPose && !els.pw.classList.contains('hide')) G.setPose(ui.hoverPose); if (d.open) ui.hoverPose = null; show(els.pw, d.open); });
      bus.on('brush', function (d) { var v = Math.max(RULES.paint.brushMinCm, Math.min(RULES.paint.brushMaxCm, G.paint.size * 100 + d.d * 100)); G.paint.size = v / 100; P.size.set(v); });
      bus.on('tool', function () { markTool(); });
      bus.on('hit', function (d) { toast(d.dog === 'you' ? '找到了！' + nameOf(d.cat) + ' 出局' : (d.cat === 'you' ? '被找到了…按 Enter 看結果' : nameOf(d.cat) + ' 被找到了')); balls(); });
      bus.on('miss', function (d) { if (d.dog === 'you') { toast(d.free ? '沒打中（逃跑中的貓不扣球）' : '打空了，少一顆球'); els.ammo.classList.remove('shake'); void els.ammo.offsetWidth; els.ammo.classList.add('shake'); } balls(); });
      bus.on('lowBalls', function (d) { if (d.dog === 'you') toast('只剩最後一顆球！'); });
      bus.on('alert', function (d) { if (d.cat === 'you' || G.decoys.some(function (x) { return x.id === d.cat; })) toast('狗狗盯上你了！'); });
      bus.on('suspicion', function (d) { els.susBar.style.width = Math.min(100, d.v * 100) + '%'; els.sus.classList.toggle('seen', d.seen); els.susTx.textContent = d.seen ? '狗狗正看著這邊' : '狗狗沒看到你'; });
      bus.on('end', function (d) { ui.lastEnd = d; });
      bus.on('decoy', function (d) { toast(d.n ? '放了一個分身（被打中你也出局）' : '分身收回'); });
      bus.on('denied', function () { toast(G.decoyCd > 0 ? '分身冷卻中 ' + Math.ceil(G.decoyCd) + ' 秒' : '分身已達上限'); });
      bus.on('cling', function (d) { toast(d.on ? '貼牆中：W/S 上下，Shift 放開' : '放開了'); });
      bus.on('menu', function () { openModal('help'); });
      bus.on('lineup', lineup);
      bus.on('undo', function () { toast('復原一步'); });
      root.addEventListener('mousemove', function (e) { ui.mx = e.clientX; ui.my = e.clientY; }, true);
      window.addEventListener('mousemove', function (e) { if (G.paint.on) { els.ring.style.left = e.clientX + 'px'; els.ring.style.top = e.clientY + 'px'; } });
    }
  });
  function nameOf(id) { var e = G.ent(id); return e ? e.name : id; }
  var toastT;
  function toast(t) { els.toast.textContent = t; els.toast.classList.add('on'); clearTimeout(toastT); toastT = setTimeout(function () { els.toast.classList.remove('on'); }, 2200); }
  ui.toast = toast;

  /* ---------- title ---------- */
  var pick = { cat: 'mochi', dog: 'shiba' };
  function buildTitle() {
    var t = els.title = h('div', '', '', root); t.id = 'title';
    var n = h('div', 'noren', '', t); for (var i = 0; i < 9; i++) h('i', '', '', n);
    h('div', 'furin', '<b class="str"></b><b class="bell"></b><b class="tan">涼</b>', t);
    for (i = 0; i < 9; i++) { var l = h('div', 'leaf', '', t); l.style.left = (18 + i * 11) + '%'; l.style.animationDuration = (11 + (i * 37 % 9)) + 's'; l.style.animationDelay = (-i * 2.7) + 's'; l.style.width = l.style.height = (16 + (i * 13 % 12)) + 'px'; }
    h('div', 'logo', '<div class="tile t1"><i class="ear l"></i><i class="ear r"></i><span>貓</span></div><div class="tile t2"><span>躲</span></div><div class="tile t3"><i class="ear l"></i><i class="ear r"></i><span>狗</span></div><div class="tile t4"><span>找</span></div>', t);
    h('div', 'tagline', '塗上顏色・藏進日常', t);
    h('div', 'sub', '日式老家裡的塗裝捉迷藏', t);
    var m = h('div', 'menu', '', t), r1 = h('div', 'row', '', m);
    function side(team, label, sub, list) {
      var s = h('div', 'side', '', r1), b = h('button', 'btn ' + team, IC.paw + ' ' + label + '<small>' + sub + '</small>', s);
      b.dataset.act = 'start-' + team; b.onclick = function () { G.start(team, pick[team]); };
      var br = h('div', 'breeds ' + team[0], '', s);
      Object.keys(list).forEach(function (k) { var p = h('b', k === pick[team] ? 'on' : '', list[k].name + '・' + list[k].tag, br); p.dataset.breed = k; p.onclick = function () { pick[team] = k; [].forEach.call(br.children, function (c) { c.classList.toggle('on', c === p); }); if (SG.audio) SG.audio.play('click'); }; });
    }
    side('cat', '當貓咪', '塗色躲起來', SG.CATS); side('dog', '當狗狗', '用網球找出來', SG.DOGS);
    var r2 = h('div', 'row row2', '', m);
    h('button', 'btn', '操作說明', r2).onclick = function () { openModal('help'); };
    h('button', 'btn', '設定', r2).onclick = function () { openModal('set'); };
    h('div', 'foot', '1 位玩家 + 機器人<i>・</i>全部美術與音效皆由程式生成<i>・</i>WebGL 垂直切片', t);
  }

  /* ---------- HUD ---------- */
  function buildHud() {
    var H = els.hud = h('div', 'hide', '', root); H.id = 'hud';
    var top = h('div', 'top', '', H);
    els.tCats = h('div', 'team c', '', top);
    var pl = h('div', 'plaque', '<span class="ph"></span><span class="sep"></span><span class="tm"></span>', top); els.ph = pl.children[0]; els.tm = pl.children[2];
    els.tDogs = h('div', 'team d', '', top);
    els.guide = h('div', 'guide panel', '<div class="steps"></div><div class="tx"></div>', H);
    for (var i = 0; i < 5; i++) h('b', '', String(i + 1), els.guide.firstChild);
    els.sus = h('div', 'sus hide', IC.eye + '<span></span><div class="bar"><i></i></div>', H); els.susTx = els.sus.children[1]; els.susBar = els.sus.querySelector('i');
    els.hints = h('div', 'hints', '', H);
    els.poses = h('div', 'poses panel', '<h4>' + IC.paw + '姿勢 <span class="key">R</span></h4>', H);
    SG.POSE_LIST.forEach(function (p) { var b = h('button', '', p[1], els.poses); b.dataset.pose = p[0]; b.onclick = function () { G.setPose(p[0]); b.blur(); }; });
    var a = els.acts = h('div', 'acts', '', H);
    els.bPaint = h('button', 'btn', IC.brush + ' 塗色 <span class="key">F</span>', a); els.bPaint.dataset.act = 'paint'; els.bPaint.onclick = function () { G.setPaintMode(!G.paint.on); els.bPaint.blur(); };
    els.bMeow = h('button', 'btn', '喵 <span class="key">1</span>', a); els.bMeow.onclick = function () { G.meow(); els.bMeow.blur(); };
    els.bDecoy = h('button', 'btn', '分身 <span class="key">Q</span><span class="cd"></span>', a); els.bDecoy.onclick = function () { G.decoy(); els.bDecoy.blur(); };
    els.cross = h('div', 'cross hide', '', H);
    els.ammo = h('div', 'ammo panel hide', '<em>網球</em><span class="n"></span><div class="balls"></div>', H);
    els.tags = h('div', 'tags', '', H);
    els.cap = h('div', 'cap hide', '', root);
    els.toast = h('div', 'toast', '', root);
    els.wait = h('div', 'wait hide', '<h2>在玄關等一下</h2><p>貓咪們正在屋裡塗色、找地方躲</p><div class="big"></div>', H);
    h('button', 'btn dog', '直接進屋 <span class="key">Enter</span>', els.wait).onclick = function () { G.skip(); };
    els.result = h('div', 'result panel hide', '', H);
    // pose wheel
    els.pw = h('div', 'pw hide', '', H);
    SG.POSE_LIST.forEach(function (p, i) {
      var b = h('button', '', p[1], els.pw); b.dataset.pose = p[0];
      if (i === 0) { b.style.left = '0'; b.style.top = '0'; } else { var a2 = (i - 1) / 8 * Math.PI * 2 - Math.PI / 2; b.style.left = Math.cos(a2) * 142 + 'px'; b.style.top = Math.sin(a2) * 132 + 'px'; }
      b.onmouseenter = function () { ui.hoverPose = p[0]; }; b.onclick = function () { G.setPose(p[0]); };
    });
    els.ring = h('div', 'ring hide', '', root);
  }
  function teamIcons() {
    var st = G.state; if (!st) return;
    var c = '<em>貓</em>', d = '<em>狗的球</em><div class="balls">';
    SGCore.list(st, 'cat').forEach(function (p) { c += IC.paw.replace('class="ic"', 'class="ic' + (p.out ? ' off' : '') + '"'); });
    var dogs = SGCore.list(st, 'dog'), n = 0; dogs.forEach(function (p) { n += p.balls; });
    for (var i = 0; i < Math.max(n, RULES.dog.startBalls); i++) d += '<i class="ball' + (i < n ? '' : ' off') + '"></i>';
    els.tCats.innerHTML = c; els.tDogs.innerHTML = d + '</div>';
  }
  function balls() {
    teamIcons(); var p = G.state.players.you; if (!p || p.team !== 'dog') return;
    var s = ''; for (var i = 0; i < Math.max(p.balls, RULES.dog.startBalls); i++) s += '<i class="ball' + (i < p.balls ? '' : ' off') + '"></i>';
    els.ammo.children[1].textContent = p.balls; els.ammo.children[2].innerHTML = s; els.ammo.classList.toggle('low', p.balls <= RULES.dog.lowBallWarn);
  }
  function setGuide(n) {
    var bs = els.guide.firstChild.children; for (var i = 0; i < bs.length; i++) bs[i].className = i < n ? 'done' : i === n ? 'on' : '';
    els.guide.lastChild.innerHTML = GUIDE[Math.min(n, GUIDE.length - 1)];
  }
  function markPose(p) { [].forEach.call(els.poses.querySelectorAll('button'), function (b) { b.classList.toggle('on', b.dataset.pose === p); }); }
  function hints(side, phase) {
    var k = function (a, b) { return '<span><span class="key">' + a + '</span> ' + b + '</span>'; };
    els.hints.innerHTML = phase === 'reveal' ? k('拖曳', '轉動視角') + k('Enter', '回標題') : side === 'cat'
      ? k('WASD', '移動') + k('空白', '跳') + k('右鍵拖曳', '視角') + k('Alt+點', '取色') + (phase === 'prep' ? k('Enter', '準備好了') : '') + k('Esc', '說明')
      : k('WASD', '移動') + k('滑鼠／方向鍵', '看') + k('左鍵／空白', '發射') + k('V', '第三人稱') + k('Esc', '說明');
  }
  function onMode(d) {
    show(els.title, d.mode === 'title'); show(els.hud, d.mode === 'play'); show(els.cap, false);
    els.pp.classList.add('off'); show(els.ring, false); show(els.result, false); els.tags.innerHTML = '';
    if (d.mode === 'play') {
      var cat = d.side === 'cat'; show(els.poses, cat); show(els.acts, cat); show(els.guide, cat); show(els.cross, false); show(els.ammo, !cat); show(els.sus, false);
      markPose('stand'); setGuide(0); teamIcons(); if (!cat) balls(); hints(d.side, 'prep');
    }
  }
  function onPhase(d) {
    if (!G.state || G.mode !== 'play') return;
    var cat = G.side === 'cat';
    els.ph.textContent = PHASE[d.phase] || ''; teamIcons(); hints(G.side, d.phase);
    show(els.wait, !cat && d.phase === 'prep'); show(els.cross, !cat && d.phase === 'seek'); show(els.ammo, !cat && d.phase !== 'reveal');
    show(els.sus, cat && d.phase === 'seek'); show(els.guide, cat && d.phase === 'prep');
    if (d.phase === 'seek') toast(cat ? '狗狗進屋了，別動！' : '開始找！球只有 ' + RULES.dog.startBalls + ' 顆');
    if (d.phase === 'reveal') { show(els.poses, false); show(els.acts, false); show(els.pw, false); els.pp.classList.add('off'); show(els.ring, false); result(); }
  }
  function result() {
    var st = G.state, e = ui.lastEnd || { winner: st.winner, reason: st.reason }, why = { time: '時間到，還有貓沒被找到', 'all-found': '所有貓都被找到了', 'no-balls': '狗狗的球用完了' }[e.reason] || '';
    var rows = SGCore.list(st, 'cat').map(function (p) { return '<tr><td>' + nameOf(p.id) + '</td><td>' + (p.out ? '✕ 被找到' : '○ 沒被找到') + '</td><td class="n">眼皮底下 ' + p.score + ' 分</td></tr>'; }).join('');
    var mine = st.players.you, won = (mine.team === 'cat') === (e.winner === 'cats');
    els.result.innerHTML = '<h2 class="' + e.winner + '">' + (e.winner === 'cats' ? '貓隊獲勝' : '狗隊獲勝') + '</h2><p>' + why + '・' + (won ? '你這隊贏了' : '你這隊輸了') + '</p><table>' + rows + '</table><div class="row"></div>';
    var r = els.result.lastChild; h('button', 'btn ' + (G.side === 'cat' ? 'cat' : 'dog'), '再來一局', r).onclick = function () { G.start(G.side, pick[G.side]); }; h('button', 'btn', '回標題', r).onclick = function () { G.toTitle(); };
    show(els.result, true);
    els.tags.innerHTML = ''; ui.tagEls = [];
    G.ents.forEach(function (en) { var t = h('div', 'tag ' + (en.team === 'dog' ? 'dogt' : en.found ? 'found' : 'safe'), (en.team === 'dog' ? '狗 ' : en.found ? '✕ ' : '○ ') + en.name, els.tags); ui.tagEls.push([en, t]); });
  }
  var lastSec = -1;
  function onFrame(d) {
    var s = Math.max(0, Math.ceil(d.left)); if (s !== lastSec) { lastSec = s; els.tm.textContent = Math.floor(s / 60) + ':' + ('0' + s % 60).slice(-2); els.tm.classList.toggle('warn', s <= 10 && d.phase !== 'reveal'); if (!els.wait.classList.contains('hide')) els.wait.querySelector('.big').textContent = s; }
    if (d.phase === 'reveal' && ui.tagEls) ui.tagEls.forEach(function (p) { var q = G.project(p[0]); p[1].style.left = q.x + 'px'; p[1].style.top = q.y + 'px'; p[1].style.display = q.vis ? '' : 'none'; });
    if (G.side === 'cat') { els.bDecoy.lastChild.textContent = G.decoyCd > 0 ? Math.ceil(G.decoyCd) + 's' : ''; if (G.paint.on) { var px = G.paint.size / Math.max(0.5, G.cam.dist * 0.62) / Math.tan(52 * Math.PI / 360) * G.vh; els.ring.style.width = els.ring.style.height = Math.max(6, px) + 'px'; } }
    else if (d.phase === 'seek') { var p = G.state.players.you; els.cross.classList.toggle('cd', G.simT - p.lastShot < RULES.dog.shotIntervalSec); }
  }
  function lineup(d) {
    var list = d.kind === 'cat' ? SG.CATS : d.kind === 'dog' ? SG.DOGS : null, s = '', keys = list ? Object.keys(list) : SG.POSE_LIST.slice(d.row * 3, d.row * 3 + 3);
    keys.forEach(function (k) { s += '<div style="position:absolute;transform:translateX(-50%)">' + (list ? '<b>' + list[k].name + '</b><small>' + list[k].tag + '</small>' : '<b>' + k[1] + '</b>') + '</div>'; });
    els.cap.innerHTML = s; show(els.cap, true); show(els.title, false);
    function posn() { SG.camera.updateMatrixWorld(true); [].forEach.call(els.cap.children, function (c, i) { var e = G.ents[i]; if (e) c.style.left = G.project(e).x + 'px'; }); }
    setTimeout(posn, 300); setTimeout(posn, 1500);
  }

  /* ---------- paint panel ---------- */
  var P = {}, PRESET = [[245, 241, 232], [239, 230, 211], [200, 155, 94], [107, 74, 46], [185, 178, 116], [47, 75, 124], [200, 69, 46], [217, 169, 58], [122, 154, 84], [30, 26, 24]], recent = [];
  function buildPaint() {
    var pp = els.pp = h('div', 'pp panel off', '', root);
    h('h4', '', IC.brush + '塗色 <span class="key">F</span>', pp);
    els.sug = h('div', 'sug', '', pp); ['腳下', '背後', '左邊', '右邊'].forEach(function (n) { var d = h('div', 'hit', '<i></i>' + n, els.sug); d.onclick = function () { if (d.rgb) { P.setRGB(d.rgb, true); addRecent(d.rgb); } }; });
    var wr = h('div', 'wheelrow', '', pp), wh = h('div', 'wheel hit', '<canvas width="150" height="150"></canvas><div class="dot"></div>', wr), cv = wh.firstChild, cx = cv.getContext('2d'), dot = wh.lastChild;
    var vb = h('div', 'vbar hit', '<div class="dot"></div>', wr), vdot = vb.firstChild, pv = h('div', 'prev', '<div class="sw"><i></i></div><input maxlength="7" spellcheck="false">', wr), sw = pv.firstChild, hexIn = pv.lastChild;
    var hsv = [215, 0.62, 0.49];
    function drawWheel() {
      var img = cx.createImageData(150, 150), d = img.data, v = Math.max(0.25, hsv[2]);
      for (var y = 0; y < 150; y++) for (var x = 0; x < 150; x++) { var dx = x - 74.5, dy = y - 74.5, r = Math.hypot(dx, dy) / 75; if (r > 1) continue; var a = Math.atan2(dy, dx) * 180 / Math.PI; if (a < 0) a += 360; var c = hsv2rgb(a, r, v), o = (y * 150 + x) * 4; d[o] = c[0]; d[o + 1] = c[1]; d[o + 2] = c[2]; d[o + 3] = 255; }
      cx.putImageData(img, 0, 0);
    }
    var lastV = -1;
    function sync(from) {
      var rgb = hsv2rgb(hsv[0], hsv[1], hsv[2]);
      if (Math.abs(lastV - hsv[2]) > 0.02) { lastV = hsv[2]; drawWheel(); }
      var a = hsv[0] * Math.PI / 180; dot.style.left = (75 + Math.cos(a) * hsv[1] * 75) + 'px'; dot.style.top = (75 + Math.sin(a) * hsv[1] * 75) + 'px'; dot.style.background = css(rgb);
      vb.style.background = 'linear-gradient(180deg,' + css(hsv2rgb(hsv[0], hsv[1], 1)) + ',#000)'; vdot.style.top = ((1 - hsv[2]) * 100) + '%'; vdot.style.background = css(rgb);
      sw.style.background = css(rgb); if (from !== 'hex') hexIn.value = hex(rgb).toUpperCase();
      if (P.mode === 'rgb') { P.s[0].set(rgb[0]); P.s[1].set(rgb[1]); P.s[2].set(rgb[2]); } else { P.s[0].set(hsv[0]); P.s[1].set(hsv[1] * 100); P.s[2].set(hsv[2] * 100); }
      tint(rgb);
      G.setColor(rgb);
    }
    function tint(rgb) {
      var g = function (a, b) { return 'linear-gradient(90deg,' + css(a) + ',' + css(b) + ')'; };
      if (P.mode === 'rgb') { P.s[0].track.style.background = g([0, rgb[1], rgb[2]], [255, rgb[1], rgb[2]]); P.s[1].track.style.background = g([rgb[0], 0, rgb[2]], [rgb[0], 255, rgb[2]]); P.s[2].track.style.background = g([rgb[0], rgb[1], 0], [rgb[0], rgb[1], 255]); }
      else { P.s[0].track.style.background = 'linear-gradient(90deg,#f00,#ff0,#0f0,#0ff,#00f,#f0f,#f00)'; P.s[1].track.style.background = g(hsv2rgb(hsv[0], 0, hsv[2]), hsv2rgb(hsv[0], 1, hsv[2])); P.s[2].track.style.background = g([0, 0, 0], hsv2rgb(hsv[0], hsv[1], 1)); }
    }
    P.setRGB = function (rgb) { var n = rgb2hsv(rgb[0], rgb[1], rgb[2]); if (n[1] < 0.01) n[0] = hsv[0]; hsv = n; sw.firstChild.style.background = css(rgb); sync(); };
    P.getRGB = function () { return hsv2rgb(hsv[0], hsv[1], hsv[2]); };
    function wheelEv(e) { var r = cv.getBoundingClientRect(), dx = e.clientX - r.left - 75, dy = e.clientY - r.top - 75, a = Math.atan2(dy, dx) * 180 / Math.PI; hsv[0] = a < 0 ? a + 360 : a; hsv[1] = Math.min(1, Math.hypot(dx, dy) / 75); sync(); }
    wh.addEventListener('pointerdown', function (e) { wh.setPointerCapture(e.pointerId); wheelEv(e); wh.onpointermove = wheelEv; e.preventDefault(); }); wh.addEventListener('pointerup', function () { wh.onpointermove = null; addRecent(P.getRGB()); });
    function vEv(e) { var r = vb.getBoundingClientRect(); hsv[2] = 1 - Math.max(0, Math.min(1, (e.clientY - r.top) / r.height)); sync(); }
    vb.addEventListener('pointerdown', function (e) { vb.setPointerCapture(e.pointerId); vEv(e); vb.onpointermove = vEv; e.preventDefault(); }); vb.addEventListener('pointerup', function () { vb.onpointermove = null; addRecent(P.getRGB()); });
    hexIn.addEventListener('input', function () { var m = /^#?([0-9a-f]{6})$/i.exec(hexIn.value.trim()); if (m) { var n = parseInt(m[1], 16); var rgb = [(n >> 16) & 255, (n >> 8) & 255, n & 255]; hsv = rgb2hsv(rgb[0], rgb[1], rgb[2]); sync('hex'); addRecent(rgb); } });
    hexIn.addEventListener('keydown', function (e) { e.stopPropagation(); if (e.key === 'Enter') hexIn.blur(); });
    var tabs = h('div', 'tabs', '<b class="on" data-m="rgb">RGB</b><b data-m="hsv">HSV</b>', pp); P.mode = 'rgb'; P.s = [];
    var box = h('div', '', '', pp); box.style.cssText = 'display:flex;flex-direction:column;gap:3px';
    function mkS() {
      box.innerHTML = ''; P.s = [];
      var L = P.mode === 'rgb' ? [['R', 255], ['G', 255], ['B', 255]] : [['H', 360], ['S', 100], ['V', 100]];
      L.forEach(function (l, i) { P.s.push(slider(box, l[0], { min: 0, max: l[1], value: 0, on: function (v) { if (P.mode === 'rgb') { var c = P.getRGB(); c[i] = Math.round(v); var n = rgb2hsv(c[0], c[1], c[2]); if (n[1] < 0.01) n[0] = hsv[0]; hsv = n; } else { hsv[i] = i === 0 ? v : v / 100; } sync(); } })); });
    }
    [].forEach.call(tabs.children, function (b) { b.classList.add('hit'); b.onclick = function () { P.mode = b.dataset.m; [].forEach.call(tabs.children, function (c) { c.classList.toggle('on', c === b); }); mkS(); sync(); }; });
    mkS();
    els.sws = h('div', 'swatches', '', pp); drawSwatches();
    var mb = h('div', '', '', pp); mb.style.cssText = 'display:flex;flex-direction:column;gap:3px';
    P.metal = slider(mb, '金屬度', { wide: true, min: 0, max: 1, value: 0, fmt: function (v) { return v.toFixed(2); }, on: function (v) { G.paint.metal = v; } });
    P.rough = slider(mb, '粗糙度', { wide: true, min: 0, max: 1, value: 0.8, fmt: function (v) { return v.toFixed(2); }, on: function (v) { G.paint.rough = v; } });
    P.size = slider(mb, '筆刷', { wide: true, min: RULES.paint.brushMinCm, max: RULES.paint.brushMaxCm, value: RULES.paint.brushDefaultCm, fmt: function (v) { return Math.round(v) + ' cm'; }, on: function (v) { G.paint.size = v / 100; } });
    P.metal.track.style.background = 'linear-gradient(90deg,#e9dcc0,#8a8f96 60%,#f4f6f8)'; P.rough.track.style.background = 'linear-gradient(90deg,#fff,#e9dcc0 30%,#b9a888)'; P.size.track.style.background = 'linear-gradient(90deg,#e9dcc0,#c9b08a)';
    P.metal.row.dataset.s = 'metal'; P.rough.row.dataset.s = 'rough'; P.size.row.dataset.s = 'size';
    var tl = els.tools = h('div', 'tools', '', pp);
    [['brush', '筆', IC.brush], ['pick', '取色', IC.drop], ['fill', '填滿', IC.fill], ['hard', '硬邊', IC.soft], ['undo', '復原', IC.undo]].forEach(function (t) {
      var b = h('button', '', t[2] + t[1], tl); b.dataset.tool = t[0];
      b.onclick = function () { if (t[0] === 'fill') G.fillAll(); else if (t[0] === 'undo') G.undo(); else if (t[0] === 'hard') { G.paint.hard = !G.paint.hard; b.lastChild.textContent = G.paint.hard ? '硬邊' : '軟邊'; } else G.paint.tool = t[0]; markTool(); b.blur(); };
    });
    markTool(); sync();
  }
  function markTool() { [].forEach.call(els.tools.children, function (b) { var t = b.dataset.tool; b.classList.toggle('on', t === G.paint.tool || (t === 'hard' && G.paint.hard)); }); }
  function drawSwatches() {
    els.sws.innerHTML = '';
    PRESET.forEach(function (c) { sw1(c); }); for (var i = 0; i < 20; i++) sw1(recent[i], i === 0 && recent.pop1);
    recent.pop1 = false;
    function sw1(c, pop) { var e = h('i', c ? 'hit' + (pop ? ' pop' : '') : 'empty', '', els.sws); if (c) { e.style.background = css(c); e.dataset.rgb = c.join(','); e.onclick = function () { P.setRGB(c); }; } }
  }
  function addRecent(c) { if (recent[0] && recent[0].join() === c.join()) return; recent = [c].concat(recent.filter(function (r) { return r.join() !== c.join(); })).slice(0, 20); recent.pop1 = true; drawSwatches(); }
  function refreshSug() { var s = G.suggest(); [].forEach.call(els.sug.children, function (d, i) { if (s[i]) { d.rgb = s[i]; d.firstChild.style.background = css(s[i]); } }); }
  setInterval(function () { if (G && G.paint && G.paint.on && G.me && G.mode === 'play') refreshSug(); }, 1500);
  ui.P = P; ui.refreshSug = refreshSug;

  /* ---------- modals ---------- */
  function buildModals() {
    var m = els.modal = h('div', 'modal hide', '<div class="panel"></div>', root);
    m.addEventListener('mousedown', function (e) { if (e.target === m) show(m, false); });
  }
  function openModal(kind) {
    var p = els.modal.firstChild, K = function (k) { return '<span class="key">' + k + '</span>'; };
    if (kind === 'help') p.innerHTML = '<h3>操作說明</h3><h5 class="c">' + IC.paw + ' 貓（躲）</h5><table>' +
      '<tr><td>' + K('W') + K('A') + K('S') + K('D') + '</td><td>移動（以鏡頭方向為準）</td></tr><tr><td>' + K('空白') + '</td><td>跳。朝牆跳會貼在牆上，' + K('W') + K('S') + ' 上下、' + K('Shift') + ' 放開</td></tr>' +
      '<tr><td>' + K('R') + '</td><td>按住開姿勢輪，放開選定</td></tr><tr><td>' + K('F') + '</td><td>開關塗色；左鍵在身上塗，' + K('Alt') + '+點 取場景顏色，滾輪調筆刷</td></tr>' +
      '<tr><td>' + K('Ctrl') + '+' + K('Z') + '</td><td>復原</td></tr><tr><td>' + K('1') + ' ' + K('Q') + ' ' + K('X') + '</td><td>喵叫／放分身／收回分身</td></tr><tr><td>右鍵拖曳</td><td>轉視角</td></tr></table>' +
      '<h5 class="d">' + IC.paw + ' 狗（找）</h5><table><tr><td>' + K('W') + K('A') + K('S') + K('D') + '</td><td>移動</td></tr><tr><td>滑鼠／方向鍵</td><td>看四周</td></tr><tr><td>左鍵／' + K('空白') + '</td><td>發射網球：打空少一顆、打中多一顆，每 ' + RULES.dog.shotIntervalSec + ' 秒一發</td></tr><tr><td>' + K('V') + '</td><td>第一／第三人稱</td></tr></table><div class="row"></div>';
    else {
      p.innerHTML = '<h3>設定</h3><div id="setbox" style="width:340px;display:flex;flex-direction:column;gap:10px"></div><div class="row"></div>';
      var b = p.querySelector('#setbox');
      slider(b, '音量', { wide: true, min: 0, max: 100, value: SG.audio ? SG.audio.volume * 100 : 70, on: function (v) { if (SG.audio) SG.audio.setVolume(v / 100); } });
      slider(b, '泛光', { wide: true, min: 0, max: 100, value: SG.post.final.uBloom.value * 100, on: function (v) { SG.post.final.uBloom.value = v / 100; } });
      slider(b, '陰影感', { wide: true, min: 0, max: 100, value: SG.post.final.uAO.value * 100, on: function (v) { SG.post.final.uAO.value = v / 100; } });
    }
    h('button', 'btn cat', '知道了', p.lastChild).onclick = function () { show(els.modal, false); };
    show(els.modal, true);
  }
  ui.openModal = openModal;
})();
