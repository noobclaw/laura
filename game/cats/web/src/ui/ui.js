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
    pat: '<svg class="ic" viewBox="0 0 24 24"><path d="M3 3h6v6H3zM15 3h6v6h-6zM9 9h6v6H9zM3 15h6v6H3zM15 15h6v6h-6z"/></svg>',
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
    bus.on('answer', function () { var el = h('div', 'answerbar', '<b>對答案</b><span>紅＝沒被找到　藍＝被找到　' + '<span class="key">G</span> 給最厲害的偽裝按讚　<span class="key">Y</span> 結束　<span class="key">5</span> 自由鏡頭</span>', els.hud); setTimeout(function () { el.classList.add('small'); }, 2600); var rm = function () { el.remove(); }; bus.on('mode', rm); });
      bus.on('guide', function (d) { setGuide(d.step); });
      bus.on('pose', function (d) { markPose(d.pose); show(els.pw, false); });
      bus.on('paintmode', function (d) { if (G.state) hints(ui.role, G.state.phase); if (d.on && document.exitPointerLock) document.exitPointerLock(); els.pp.classList.toggle('off', !d.on); els.bPaint.classList.toggle('act', d.on); show(els.ring, d.on); if (d.on) refreshSug(); });
      bus.on('picked', function (d) { P.setRGB(d.rgb); P.rough.set(d.rough); P.metal.set(d.metal); addRecent(d.rgb); });
      bus.on('wheel', function (d) { if (!(G.me && G.me.team === 'cat' && G.state.phase !== 'reveal')) return; if (!d.open && ui.hoverPose && !els.pw.classList.contains('hide')) G.setPose(ui.hoverPose); if (d.open) ui.hoverPose = null; show(els.pw, d.open); });
      bus.on('brush', function (d) { var v = Math.max(RULES.paint.brushMinCm, Math.min(RULES.paint.brushMaxCm, G.paint.size * 100 + d.d * 100)); G.paint.size = v / 100; P.size.set(v); });
      bus.on('tool', function () { markTool(); });
      bus.on('hit', function (d) { if (d.dog === 'you') { var ar = els.ammo.getBoundingClientRect(); pop('+1', ar.right + 4, ar.top, 'am'); }
        toast(d.dog === 'you' ? '找到了！' + nameOf(d.cat) + ' 出局' : (d.cat === 'you' ? '被找到了…按 Enter 看結果' : nameOf(d.cat) + ' 被找到了')); balls(); });
      bus.on('miss', function (d) { if (d.dog === 'you' && !d.free && !SG.RULES.dog.unlimited) { var ar = els.ammo.getBoundingClientRect(); pop('−1', ar.right + 4, ar.top, 'am bad'); }
        if (d.dog === 'you') { toast(d.free ? '沒打中（逃跑中的貓不扣彈藥）' : '打空了，少一發'); els.ammo.classList.remove('shake'); void els.ammo.offsetWidth; els.ammo.classList.add('shake'); } balls(); });
      bus.on('lowAmmo', function (d) { if (d.dog === 'you') toast('只剩最後一發！'); });
      bus.on('alert', function (d) { if (d.cat === 'you' || G.decoys.some(function (x) { return x.id === d.cat; })) toast('狗狗盯上你了！'); });
      bus.on('suspicion', function (d) { els.susBar.style.width = Math.min(100, d.v * 100) + '%'; els.sus.classList.toggle('seen', d.seen); els.susTx.textContent = d.seen ? '狗狗正看著這邊' : '狗狗沒看到你'; });
      bus.on('end', function (d) { ui.lastEnd = d; });
      bus.on('spectate', function () { ui.spect = true; hints(G.side, G.state.phase); show(els.poses, false); show(els.acts, false); });
      bus.on('mode', function () { ui.spect = false; });
      bus.on('decoy', function (d) { toast(d.n ? '放了一個分身（被打中你也出局）' : '分身收回'); });
      bus.on('cloneEmbed', function () { toast('⚠ 分身卡進物體裡了'); els.toast.classList.add('red'); setTimeout(function () { els.toast.classList.remove('red'); }, 2300); });
      bus.on('denied', function () { toast(G.decoyCd > 0 ? '分身冷卻中 ' + Math.ceil(G.decoyCd) + ' 秒' : '分身已達上限'); });
      bus.on('cling', function (d) { ui.cling = d.on; if (ui.hints) ui.hints(); if (d.on) toast('黏住了：空白 往上、Ctrl 往下、WASD 沿著表面爬、Shift 放開'); });
      bus.on('cursor3d', function (d) { els.ring.style.opacity = d.on ? 0 : 1; }); // on the body the brush is drawn on the body itself
      bus.on('whiteLeft', function (d) { if (!els.wl) return; els.wl.querySelector('u').style.width = d.pct + '%'; els.wl.querySelector('span').textContent = d.pct + '%'; els.wl.classList.toggle('done', d.pct <= 2); });
      var lpN = 0; bus.on('frame', function () { // eyedropper magnifier while Space is held (or the pick tool is armed)
        var on = G.paint.on && G.me && G.me.team === 'cat' && (G.keys[' '] || G.paint.tool === 'pick'); show(els.loupe, !!on); if (!on) return;
        els.loupe.style.left = G.mouse.x + 'px'; els.loupe.style.top = G.mouse.y + 'px'; if (lpN++ % 2) return;
        var px = G.loupeAt(G.mouse.x, G.mouse.y), cv = els.loupe.firstChild, x = cv.getContext('2d'), N = 11, c = 12;
        for (var j = 0; j < N; j++) for (var i = 0; i < N; i++) { var o = ((N - 1 - j) * N + i) * 4; x.fillStyle = 'rgb(' + px[o] + ',' + px[o + 1] + ',' + px[o + 2] + ')'; x.fillRect(i * c, j * c, c, c); }
        var m = (5 * N + 5) * 4, col = 'rgb(' + px[m] + ',' + px[m + 1] + ',' + px[m + 2] + ')'; x.strokeStyle = '#000'; x.lineWidth = 3; x.strokeRect(5 * c - 0.5, 5 * c - 0.5, c + 1, c + 1); x.strokeStyle = '#fff'; x.lineWidth = 1.5; x.strokeRect(5 * c - 0.5, 5 * c - 0.5, c + 1, c + 1);
        els.loupe.style.borderColor = col; els.loupe.lastChild.textContent = '#' + [px[m], px[m + 1], px[m + 2]].map(function (v) { return ('0' + v.toString(16)).slice(-2); }).join('').toUpperCase(); });
      bus.on('blocked', function () { toast('被東西擋住了：按 3 開啟「穿透描繪」就能隔著畫'); });
      bus.on('shading', function (d) { toast(d.on ? '陰影：開' : '陰影：關（只看顏色）'); });
      bus.on('menu', function () { openModal('help'); });
      bus.on('say', function (d) { bubble(G.ent(d.id), d.text, 2200); });
      bus.on('like', function (d) { bubble(G.ent(d.id), '👍 +1', 1500); (ui.tagEls || []).forEach(function (p) { if (p[0].id === d.id) { var u = p[1].querySelector('.lk'); if (u) u.textContent = '👍 ' + d.n; } }); });
      bus.on('sidepanel', function () { els.result.classList.toggle('mini'); });
      bus.on('chat', function () { show(els.chat, true); els.chat.focus(); if (document.exitPointerLock) document.exitPointerLock(); });
      bus.on('danger', function (d) { els.vig.style.opacity = Math.max(0, d.v - 0.2) * 0.9; els.vig.classList.toggle('aim', !!d.aim); });
      bus.on('nearmiss', function (d) { banner(d.kind === 'dog' ? '狗從你旁邊走過！' : '子彈擦過耳朵！'); });
      // THE mechanic: while a hunter has you on screen without finding you, a counter runs at the bottom right of YOUR screen and grows the longer it lasts
      var ovN = 0, ovSum = 0, ovLast = -9, rankT = 0;
      bus.on('score', function (d) {
        rankT = 0; if (!G.me || d.add <= 0 || d.cat !== G.me.pid || (ui.role !== 'cat' && G.state.mode !== 'double')) return;
        if (G.simT - ovLast > SG.RULES.overlooked.streakGapSec) { ovN = 0; ovSum = 0; } ovLast = G.simT; ovN++; ovSum += d.add;
        els.myScore.lastChild.textContent = d.score;
        els.ovl.className = 'ovl lv' + Math.min(4, Math.floor(ovN / 4)); els.ovl.innerHTML = '<em>被看見了，卻沒被發現</em><b style="font-size:' + (64 + Math.min(72, ovN * 3.2)) + 'px">+' + ovSum + '</b><u>連續 ' + ovN + ' 跳' + (d.add >= 40 ? '　正對著你！' : '') + '</u><i>這一下 +' + d.add + '　累計 ' + d.score + '</i>';
        void els.ovl.offsetWidth; els.ovl.classList.add('tick'); bus.emit('ovltick', { n: ovN, add: d.add });
      });
      bus.on('frame', function () {
        if (ovN && G.simT - ovLast > SG.RULES.overlooked.streakGapSec) { // the hunter looked away: the streak is banked and flies over to your row in the ranking
          var r0 = els.ovl.getBoundingClientRect(), fly = h('div', 'bank', '+' + ovSum, els.hud), r1 = els.rank.getBoundingClientRect(); fly.style.left = (r0.right - 150) + 'px'; fly.style.top = (r0.top + 20) + 'px'; void fly.offsetWidth; fly.style.left = (r1.left + 90) + 'px'; fly.style.top = (r1.top + 30) + 'px'; fly.style.fontSize = '20px'; fly.style.opacity = 0.2;
          setTimeout(function () { fly.remove(); els.rank.classList.add('flash'); setTimeout(function () { els.rank.classList.remove('flash'); }, 450); }, 720); bus.emit('banked', { sum: ovSum, n: ovN });
          ovN = 0; els.ovl.className = 'ovl hide'; rankT = 0; }
        rankT -= 1; if (rankT > 0 || !G.state) return; rankT = 20;
        if (ui.role !== 'cat' && !els.rank.classList.contains('hide') && els.rank.innerHTML && G.simT - (ui.rankAt || -99) < G.settings.boardEvery) return; ui.rankAt = G.simT; // hunters get the ranking only every 30 s (host setting), as in the original
        var on = G.state.phase === 'seek' && (ui.role === 'cat' || G.settings.board); show(els.rank, on); if (!on) return;
        var P = G.state.players, ids = Object.keys(P).filter(function (id) { return P[id].team === 'cat' || P[id].score > 0 || G.state.mode === 'double'; }).sort(function (a, b) { return P[b].score - P[a].score; }).slice(0, 7);
        els.rank.innerHTML = '<h4>眼皮底下排行</h4>' + ids.map(function (id, i) { return '<div class="' + (id === G.me.pid ? 'me' : '') + '"><u>' + (i + 1) + '</u><span>' + nameOf(id) + '</span><b>' + P[id].score + '</b></div>'; }).join('');
      });
      bus.on('blast', function (d) { if (d.me) { els.cross.classList.remove('fire'); void els.cross.offsetWidth; els.cross.classList.add('fire'); } });
      bus.on('tags', function (d) { toast(d.on ? '名牌：顯示' : '名牌：隱藏'); });
      bus.on('viewlock', function (d) { toast(d.on ? '視角鎖定：身體不再跟著鏡頭轉' : '視角鎖定解除'); });
      bus.on('seethrough', function (d) { toast(d.on ? '透視自己：開' : '透視自己：關'); });
      bus.on('follow', function (d) { toast(d.name ? '跟著 ' + d.name : '自由鏡頭'); });
      bus.on('ctrlwarn', function () { toast('提醒：在瀏覽器分頁裡 Ctrl+W 會關掉分頁，壓低可以改用 C，或先按 F11 全螢幕'); });
      bus.on('role', function (d) { setRole(d.team); toast(G.state.mode === 'infection' ? '你被找到了，現在你也是狗！' : '換你當狗去找別人'); });
      bus.on('infected', function (d) { if (d.cat !== 'you') toast(nameOf(d.cat) + ' 變成狗了'); teamIcons(); });
      bus.on('out', function () { teamIcons(); });
      bus.on('found', function (d) { teamIcons(); if (!G.me || G.me.team !== 'dog') return; var me = G.me.pid || G.me.id; banner(d.by === me ? '找到 ' + d.name + ' 了！' : (d.by ? nameOf(d.by) + ' 找到了 ' + d.name : d.name + ' 被找到了')); });
      /* (the 30 s board event is superseded by the live ranking panel on the left) */
      bus.on('heard', function (d) { els.heard.style.transform = 'rotate(' + (-d.angle * 180 / Math.PI) + 'deg)'; show(els.heard, true); ui.heardT = 2.2; });
      bus.on('meow', function (d) { if (d.forced && d.me) toast('強制喵叫！'); });
      bus.on('embed', function (d) { toast(d.state === 'warn' ? '身體嵌進去超過 1/3，這樣不允許！再不出來會被看見' : d.state === 'exposed' ? '你露出來了！狗看得到你' : '好了，出來了'); });
      bus.on('votes', function (d) { if (d.have < d.need) toast('跳過投票 ' + d.have + ' / ' + d.need); });
      bus.on('lineup', lineup);
      bus.on('undo', function () { toast('復原一步'); });
      root.addEventListener('mousemove', function (e) { ui.mx = e.clientX; ui.my = e.clientY; }, true);
      window.addEventListener('mousemove', function (e) { if (G.paint.on) { els.ring.style.left = e.clientX + 'px'; els.ring.style.top = e.clientY + 'px'; } });
    }
  });
  var bubs = [];
  function bubble(en, text, ms) { if (!en) return; bubs = bubs.filter(function (b) { if (b.en === en) { b.el.remove(); return false; } return true; }); var el = h('div', 'bub', text, els.bubbles); bubs.push({ en: en, el: el, t: (ms || 2200) / 1000 }); }
  function pop(text, x, y, cls) { var el = h('div', 'pop ' + (cls || ''), text, els.hud); el.style.left = x + 'px'; el.style.top = y + 'px'; setTimeout(function () { el.remove(); }, 900); }
  function banner(text) { var el = h('div', 'banner', text, els.hud); setTimeout(function () { el.remove(); }, 1900); }
  ui.bubble = bubble;
  function nameOf(id) { var e = G.ent(id); return e ? e.name : id; }
  var toastT;
  function toast(t) { els.toast.textContent = t; els.toast.classList.add('on'); clearTimeout(toastT); toastT = setTimeout(function () { els.toast.classList.remove('on'); }, 2200); }
  ui.toast = toast;

  /* ---------- title ---------- */
  /* Title lettering: the regular-weight glyph is turned into a distance field, thickened evenly by dilation
     (not by stroking), then shaded as a rounded bevel with a rim. */
  function glyph(ch, pal) {
    var N = 256, c = document.createElement('canvas'); c.width = c.height = N; var g = c.getContext('2d', { willReadFrequently: true });
    g.fillStyle = '#000'; g.fillRect(0, 0, N, N); g.fillStyle = '#fff'; g.textAlign = 'center'; g.textBaseline = 'middle'; g.font = '400 176px "SushiTC","Noto Sans TC",sans-serif'; g.fillText(ch, N / 2, N / 2 + 6);
    var src = g.getImageData(0, 0, N, N).data, ins = new Uint8Array(N * N), i, x, y;
    for (i = 0; i < N * N; i++) ins[i] = src[i * 4] > 110 ? 1 : 0;
    function dist(feature) { // two-pass chamfer distance to the nearest pixel where ins === feature
      var d = new Float32Array(N * N), INF = 1e6, a = 1, b = 1.4142, v;
      for (i = 0; i < N * N; i++) d[i] = ins[i] === feature ? 0 : INF;
      for (y = 0; y < N; y++) for (x = 0; x < N; x++) { i = y * N + x; v = d[i]; if (x > 0) v = Math.min(v, d[i - 1] + a); if (y > 0) { v = Math.min(v, d[i - N] + a); if (x > 0) v = Math.min(v, d[i - N - 1] + b); if (x < N - 1) v = Math.min(v, d[i - N + 1] + b); } d[i] = v; }
      for (y = N - 1; y >= 0; y--) for (x = N - 1; x >= 0; x--) { i = y * N + x; v = d[i]; if (x < N - 1) v = Math.min(v, d[i + 1] + a); if (y < N - 1) { v = Math.min(v, d[i + N] + a); if (x < N - 1) v = Math.min(v, d[i + N + 1] + b); if (x > 0) v = Math.min(v, d[i + N - 1] + b); } d[i] = v; }
      return d;
    }
    var dOut = dist(1), dIn = dist(0), W = 6.5, BEV = 9, RIM = 5, sd = new Float32Array(N * N), hgt = new Float32Array(N * N);
    for (i = 0; i < N * N; i++) { sd[i] = (ins[i] ? -dIn[i] : dOut[i]) - W; var k = Math.max(0, Math.min(1, -sd[i] / BEV)); hgt[i] = 1 - (1 - k) * (1 - k); }
    var out = g.createImageData(N, N), o = out.data, T = pal.top, B = pal.bottom, Rm = pal.rim, L = [-0.42, -0.72, 0.55];
    for (y = 1; y < N - 1; y++) for (x = 1; x < N - 1; x++) {
      i = y * N + x; var s = sd[i], q = i * 4; if (s > RIM + 1.5) continue;
      var nx = (hgt[i - 1] - hgt[i + 1]) * 3.2, ny = (hgt[i - N] - hgt[i + N]) * 3.2, nz = 1, nl = Math.hypot(nx, ny, nz); nx /= nl; ny /= nl; nz /= nl;
      var dif = Math.max(0, nx * L[0] + ny * L[1] + nz * L[2]), hx = L[0], hy = L[1], hz = L[2] + 1, hl = Math.hypot(hx, hy, hz), sp = Math.pow(Math.max(0, (nx * hx + ny * hy + nz * hz) / hl), 26) * 0.75;
      var t = y / N, sh = 0.62 + 0.55 * dif, r = (T[0] + (B[0] - T[0]) * t) * sh + 255 * sp, gg = (T[1] + (B[1] - T[1]) * t) * sh + 255 * sp, bb = (T[2] + (B[2] - T[2]) * t) * sh + 255 * sp;
      var face = Math.max(0, Math.min(1, 0.5 - s)); // 1 inside the fattened glyph, 0 in the rim
      o[q] = Math.min(255, r) * face + Rm[0] * (1 - face); o[q + 1] = Math.min(255, gg) * face + Rm[1] * (1 - face); o[q + 2] = Math.min(255, bb) * face + Rm[2] * (1 - face);
      o[q + 3] = 255 * Math.max(0, Math.min(1, RIM + 0.5 - s));
    }
    g.putImageData(out, 0, 0); return c;
  }
  var MODES = { basic: ['基本', '狗找貓。時間到還有貓沒被找到，貓隊贏'], infection: ['感染', '被找到的貓會變成狗，撐到最後的貓最厲害'], double: ['雙重', '大家先躲好塗好，再一起去找別人；先找到全員的人贏'] };
  function cycler(parent, label, key, opts, get, set) {
    var row = h('div', 'cy', '<em>' + label + '</em><i class="pv2 hit">◀</i><span><b></b><small></small></span><i class="nx hit">▶</i>', parent); row.dataset.k = key;
    function draw() { var cur = get(), o = opts.filter(function (x) { return x[0] === cur; })[0] || opts[0]; row.children[2].firstChild.textContent = o[1]; row.children[2].lastChild.textContent = o[2] || ''; }
    function step(d) { var cur = get(), i = 0; opts.forEach(function (x, k) { if (x[0] === cur) i = k; }); set(opts[(i + d + opts.length) % opts.length][0]); draw(); if (SG.audio) SG.audio.play('click'); }
    row.children[1].onclick = function () { step(-1); }; row.children[3].onclick = function () { step(1); }; draw(); return row;
  }
  function buildTitle() {
    var t = els.title = h('div', '', '', root); t.id = 'title';
    var n = h('div', 'noren', '', t); for (var i = 0; i < 9; i++) h('i', '', '', n);
    h('div', 'furin', '<b class="str"></b><b class="bell"></b><b class="tan">涼</b>', t);
    for (i = 0; i < 9; i++) { var l = h('div', 'leaf', '', t); l.style.left = (18 + i * 11) + '%'; l.style.animationDuration = (11 + (i * 37 % 9)) + 's'; l.style.animationDelay = (-i * 2.7) + 's'; l.style.width = l.style.height = (16 + (i * 13 % 12)) + 'px'; }
    var logo = h('div', 'logo', '<div class="tile t1"><i class="ear l"></i><i class="ear r"></i></div><div class="tile t2"></div><div class="tile t3"><i class="ear l"></i><i class="ear r"></i></div><div class="tile t4"></div>', t);
    var cream = { top: [255, 253, 244], bottom: [255, 222, 170], rim: [146, 66, 14] }, ice = { top: [255, 255, 255], bottom: [200, 232, 255], rim: [22, 78, 130] }, ink = { top: [150, 96, 50], bottom: [70, 40, 18], rim: [255, 250, 236] };
    [['貓', cream], ['躲', ink], ['狗', ice], ['找', ink]].forEach(function (gp, k) { logo.children[k].appendChild(glyph(gp[0], gp[1])); logo.children[k].setAttribute('aria-label', gp[0]); });
    h('div', 'tagline', '塗上顏色・藏進日常', t);
    h('div', 'sub', '老家裡的塗裝捉迷藏', t);
    function card(team, title, label, sub, list) {
      var c = h('div', 'card panel ' + team, '<h4>' + IC.paw + title + '</h4>', t), pvw = h('canvas', 'pv', '', c), P0 = G.pick[team], O = SG.CRITTER_OPTIONS[team];
      function upd() { G.setPreview(team, pvw); }
      cycler(c, '體型', 'breed', Object.keys(list).map(function (k) { return [k, list[k].name, list[k].tag]; }), function () { return P0.breed; }, function (v) { P0.breed = v; upd(); });
      cycler(c, '耳朵', 'ear', O.ear, function () { return P0.ear; }, function (v) { P0.ear = v; upd(); });
      cycler(c, '尾巴', 'tail', O.tail, function () { return P0.tail; }, function (v) { P0.tail = v; upd(); });
      if (O.collar) cycler(c, '項圈', 'collar', O.collar, function () { return P0.collar; }, function (v) { P0.collar = v; upd(); });
      var b = h('button', 'btn ' + team, IC.paw + ' ' + label + '<small>' + sub + '</small>', c); b.dataset.act = 'start-' + team; b.onclick = function () { G.start(team); };
      upd();
    }
    card('cat', '貓咪・躲', '當貓咪', '塗色躲起來', SG.CATS); card('dog', '狗狗・找', '當狗狗', '用漆彈槍找出來', SG.DOGS);
    var m = h('div', 'mid', '', t), ms = h('div', 'modes', '', m), md = h('p', 'mdesc', '', m);
    Object.keys(MODES).forEach(function (k) { var b = h('b', 'hit' + (k === G.settings.mode ? ' on' : ''), MODES[k][0], ms); b.dataset.mode = k; b.onclick = function () { G.settings.mode = k; [].forEach.call(ms.children, function (c) { c.classList.toggle('on', c === b); }); md.textContent = MODES[k][1]; if (SG.audio) SG.audio.play('click'); }; });
    md.textContent = MODES[G.settings.mode][1];
    var r2 = h('div', 'row row2', '', m);
    var hb = h('button', 'btn', '房主設定', r2); hb.dataset.act = 'host'; hb.onclick = function () { openModal('host'); };
    h('button', 'btn', '操作說明', r2).onclick = function () { openModal('help'); };
    h('div', 'foot', '1 位玩家 + 機器人<i>・</i>全部美術與音效皆由程式生成<i>・</i>WebGL 垂直切片', t);
  }

  /* ---------- HUD ---------- */
  function buildHud() {
    var H = els.hud = h('div', 'hide', '', root); H.id = 'hud';
    var top = h('div', 'top', '', H);
    els.tCats = h('div', 'team c', '', top);
    var pl = h('div', 'plaque', '<span class="ph"></span><span class="sep"></span><span class="tm"></span>', top); els.ph = pl.children[0]; els.tm = pl.children[2];
    els.tDogs = h('div', 'team d', '', top);
    els.vote = h('button', 'btn vote', '跳過 <span class="key">Enter</span>', top); els.vote.dataset.act = 'vote'; els.vote.onclick = function () { G.skip(); els.vote.blur(); };
    els.night = h('div', 'team nightb hide', '夜晚模式', top);
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
    els.ammo = h('div', 'ammo panel hide', '<em>彈藥</em><span class="n"></span><div class="balls"></div>', H);
    els.tags = h('div', 'tags', '', H);
    els.board = h('div', 'board panel hide', '', H);
    els.vig = h('div', 'vig', '', H); els.bubbles = h('div', 'tags', '', H); els.myScore = h('div', 'myscore hide', '<em>眼皮底下</em><b>0</b>', H); els.modecap = h('div', 'modecap', '', H); els.ovl = h('div', 'ovl hide', '', H); els.rank = h('div', 'rank panel hide', '', H);
    els.chat = h('input', 'chat hide', '', H); els.chat.maxLength = 40; els.chat.placeholder = '說點什麼…（Enter 送出）';
    els.chat.addEventListener('keydown', function (e) { e.stopPropagation(); if (e.key === 'Enter') { if (els.chat.value.trim()) bubble(G.me, els.chat.value.trim(), 3500); els.chat.value = ''; show(els.chat, false); els.chat.blur(); } if (e.key === 'Escape') { show(els.chat, false); els.chat.blur(); } });
    els.heard = h('div', 'heard hide', '<i>' + IC.paw + '喵</i>', H);
    els.cap = h('div', 'cap hide', '', root);
    els.toast = h('div', 'toast', '', root);
    els.wait = h('div', 'wait hide', '<h2>在玄關等一下</h2><p>貓咪們正在屋裡塗色、找地方躲</p><div class="big"></div>', H);
    h('button', 'btn dog', '直接進屋 <span class="key">Enter</span>', els.wait).onclick = function () { G.skip(); };
    els.result = h('div', 'result panel hide', '', H);
    // pose wheel
    els.pw = h('div', 'pw hide', '', H);
    SG.POSE_LIST.forEach(function (p, i) {
      var b = h('button', '', p[1], els.pw); b.dataset.pose = p[0];
      if (i === 0) { b.style.left = '0'; b.style.top = '0'; } else { var a2 = (i - 1) / (SG.POSE_LIST.length - 1) * Math.PI * 2 - Math.PI / 2; b.style.left = Math.cos(a2) * 196 + 'px'; b.style.top = Math.sin(a2) * 168 + 'px'; }
      b.onmouseenter = function () { ui.hoverPose = p[0]; }; b.onclick = function () { G.setPose(p[0]); };
    });
    els.ring = h('div', 'ring hide', '', root);
    els.loupe = h('div', 'loupe hide', '<canvas width="132" height="132"></canvas><b></b>', root);
  }
  function teamIcons() {
    var st = G.state; if (!st) return;
    if (st.mode === 'double') { var me2 = st.players.you; els.tCats.innerHTML = '<em>你找到</em> ' + me2.found.length + ' / ' + (st.order.length - 1); els.tDogs.innerHTML = '<em>你的彈藥</em> ' + (SG.RULES.dog.unlimited ? '∞' : me2.ammo); return; }
    var c = '<em>貓</em>', d = '<em>狗的彈藥</em><div class="balls">';
    SGCore.list(st, 'cat').forEach(function (p) { c += IC.paw.replace('class="ic"', 'class="ic' + (p.out ? ' off' : '') + '"'); });
    var dogs = SGCore.hunters(st), n = 0; d = '<em>獵人</em>'; dogs.forEach(function (p) { n += p.ammo; d += '<i class="hi' + (p.id === 'you' ? ' me' : '') + '"></i>'; }); // white hiders on the left, red hunters on the right
    d += '<span class="num">' + (SG.RULES.dog.unlimited ? '∞' : '彈 ' + n) + '</span>';
    els.tCats.innerHTML = c; els.tDogs.innerHTML = d;
  }
  function balls() {
    teamIcons(); var p = G.state.players.you; if (!p || !p.hunter) return;
    var s = ''; for (var i = 0; i < Math.max(p.ammo, RULES.dog.startAmmo); i++) s += '<i class="ball' + (i < p.ammo ? '' : ' off') + '"></i>';
    els.ammo.children[1].textContent = SG.RULES.dog.unlimited ? '∞' : p.ammo; els.ammo.children[2].innerHTML = s; els.ammo.classList.toggle('low', p.ammo <= RULES.dog.lowAmmoWarn);
  }
  function setGuide(n) {
    var bs = els.guide.firstChild.children; for (var i = 0; i < bs.length; i++) bs[i].className = i < n ? 'done' : i === n ? 'on' : '';
    els.guide.lastChild.innerHTML = GUIDE[Math.min(n, GUIDE.length - 1)];
  }
  function markPose(p) { [].forEach.call(els.poses.querySelectorAll('button'), function (b) { b.classList.toggle('on', b.dataset.pose === p); }); }
  function hints(side, phase) {
    var k = function (a, b) { return '<span><span class="key">' + a + '</span> ' + b + '</span>'; };
    els.hints.innerHTML = phase === 'reveal' || ui.spect ? k('WASD', '飛行') + k('空白／C', '升降') + k('拖曳', '轉頭') + k('Enter', phase === 'reveal' ? '回標題' : '看結果') : side === 'cat'
      ? (G.paint.on ? k('左鍵', '塗') + k('空白+點', '取色') + k('右鍵拖曳', '筆刷大小') + k('中鍵拖曳', '轉鏡頭') + k('滾輪', '遠近') : k('WASD', '移動') + k('空白', '跳') + k('Ctrl', '壓低') + k('R', '姿勢') + k('F', '塗色') + k('右鍵', '鎖定視角') + k('1', '喵') + k('2', '名牌') + k('3', '透視')) + (phase === 'prep' ? k('Enter', '好了') : '')
      : k('WASD', '移動') + k('滑鼠', '看') + k('左鍵', '開火') + k('右鍵', '第三人稱') + k('空白', '跳') + k('Ctrl', '蹲') + k('Esc', '說明');
  }
  function setRole(team) { // HUD layout for the side the player is on right now (changes mid-round in infection / double)
    var cat = team === 'cat', ph = G.state ? G.state.phase : 'prep'; ui.role = team;
    show(els.poses, cat && ph !== 'reveal'); show(els.acts, cat && ph !== 'reveal'); show(els.guide, cat && ph === 'prep'); show(els.sus, cat && ph === 'seek');
    show(els.cross, !cat && ph === 'seek'); show(els.ammo, !cat && ph !== 'reveal'); show(els.wait, !cat && ph === 'prep');
    if (!cat) { els.pp.classList.add('off'); show(els.ring, false); show(els.pw, false); balls(); }
    hints(team, ph); show(els.myScore, cat && ph === 'seek'); if (!cat) els.vig.style.opacity = 0;
    var gm = G.state ? G.state.mode : 'basic'; els.modecap.innerHTML = '<b>' + MODES[gm][0] + '</b>' + MODES[gm][1];
    var aids = !!G.settings.paintAids; show(els.sug, aids); var pb = els.tools.querySelector('[data-tool=pattern]'); if (pb) show(pb, aids); if (!aids) G.paint.pattern = '';
  }
  function onMode(d) {
    show(els.title, d.mode === 'title'); show(els.hud, d.mode === 'play'); show(els.cap, false); ui.spect = false;
    els.pp.classList.add('off'); show(els.ring, false); show(els.result, false); els.tags.innerHTML = ''; show(els.board, false); show(els.heard, false); els.vig.style.opacity = 0; els.myScore.lastChild.textContent = '0'; bubs.forEach(function (b) { b.el.remove(); }); bubs = [];
    if (d.mode === 'play') { markPose('stand'); setGuide(0); teamIcons(); show(els.night, G.settings.night); setRole(d.side); }
  }
  function onPhase(d) {
    if (!G.state || G.mode !== 'play') return;
    var cat = ui.role === 'cat', dbl = G.state.mode === 'double';
    els.ph.textContent = dbl && d.phase === 'seek' ? '大家找大家' : PHASE[d.phase] || ''; teamIcons(); setRole(ui.role);
    show(els.vote, d.phase === 'prep' || d.phase === 'reveal');
    if (d.phase === 'seek') toast(dbl ? '換你去找別人了！你的身體留在原地' : cat ? '狗狗進屋了，別動！' : '開始找！' + (SG.RULES.dog.unlimited ? '彈藥不限' : ' 彈藥只有 ' + RULES.dog.startAmmo + ' 發'));
    if (d.phase === 'reveal') { show(els.poses, false); show(els.acts, false); show(els.pw, false); els.pp.classList.add('off'); show(els.ring, false); show(els.cross, false); show(els.ammo, false); show(els.sus, false); result(); }
  }
  function result() {
    var st = G.state, e = ui.lastEnd || { winner: st.winner, reason: st.reason }, dbl = st.mode === 'double';
    var why = { time: dbl ? '時間到，找到最多的人贏' : '時間到，還有貓沒被找到', 'all-found': '所有貓都被找到了', 'no-ammo': '彈藥用完了', 'double-all': '有人找到了全員' }[e.reason] || '';
    var mine = st.players.you, title, cls, won;
    if (dbl) { won = e.winner === 'you'; title = nameOf(e.winner) + ' 獲勝'; cls = won ? 'cats' : 'dogs'; }
    else { won = (mine.team === 'cat' && !mine.hunter) === (e.winner === 'cats'); if (st.mode === 'infection' && mine.hunter && G.side === 'cat') won = false; title = e.winner === 'cats' ? '貓隊獲勝' : '狗隊獲勝'; cls = e.winner; }
    var rows = st.order.filter(function (id) { return dbl || G.side === 'cat' ? !/^dog/.test(id) : !/^dog|^you$/.test(id); }).map(function (id) {
      var p = st.players[id]; if (dbl) return '<tr><td>' + nameOf(id) + '</td><td>找到 ' + p.found.length + ' 個</td><td class="n">眼皮底下 ' + p.score + ' 分</td></tr>';
      return '<tr><td>' + nameOf(id) + (st.lastCat === id && st.mode === 'infection' ? '（撐最久）' : '') + '</td><td>' + (p.out ? '✕ 被找到' : '○ 沒被找到') + '</td><td class="n">眼皮底下 ' + p.score + ' 分</td></tr>'; }).join('');
    els.result.innerHTML = '<h2 class="' + cls + '">' + title + '</h2><p>' + why + '・' + (dbl ? (won ? '你贏了' : '你沒贏') : (won ? '你這隊贏了' : '你這隊輸了')) + '</p><table>' + rows + '</table><div class="row"></div>';
    var r = els.result.lastChild; h('button', 'btn ' + (G.side === 'cat' ? 'cat' : 'dog'), '再來一局', r).onclick = function () { G.start(G.side); }; h('button', 'btn', '回標題', r).onclick = function () { G.toTitle(); };
    show(els.result, true);
    els.tags.innerHTML = ''; ui.tagEls = [];
    els.result.classList.remove('mini'); if (!els.result.querySelector('.tabhint')) h('div', 'tabhint', '<span class="key">Tab</span> 收合', els.result);
    // name tags: name, 眼皮底下 score, 👍 count; for the hunters also how far away and, off screen, which way
    G.ents.forEach(function (en) { if (!en.c.root.visible) return; var pl = st.players[en.id] || st.players[en.pid] || {}, dogT = en.team === 'dog';
      var t = h('div', 'tag ' + (dogT ? 'dogt' : en.found ? 'found' : 'safe'), '<i class="arr">➤</i><b>' + (dogT ? '狗 ' : en.found ? '✕ ' : '○ ') + en.name + '</b>' + (dogT ? '' : '<small><span class="sc">' + (pl.score || 0) + ' 分</span><span class="lk">👍 ' + ((G.likes || {})[en.id] || 0) + '</span><span class="ds"></span></small>'), els.tags); ui.tagEls.push([en, t]); });
  }
  var lastSec = -1;
  function onFrame(d) {
    var s = Math.max(0, Math.ceil(d.left)); if (s !== lastSec) { lastSec = s; els.tm.textContent = Math.floor(s / 60) + ':' + ('0' + s % 60).slice(-2); els.tm.classList.toggle('warn', s <= 10 && d.phase !== 'reveal'); if (!els.wait.classList.contains('hide')) els.wait.querySelector('.big').textContent = s; }
    if (d.phase === 'reveal' && ui.tagEls) { var hunter = G.side === 'dog' || (G.me && G.me.team === 'dog'), W = G.vw, Hh = G.vh;
      ui.tagEls.forEach(function (p) { var q = G.project(p[0]), el = p[1], on = q.vis && q.x > 40 && q.x < W - 40 && q.y > 70 && q.y < Hh - 30, cat = p[0].team === 'cat';
        if (on || !hunter || !cat) { el.classList.remove('edge'); el.style.left = q.x + 'px'; el.style.top = q.y + 'px'; el.style.display = q.vis ? '' : 'none'; }
        else { var dx = q.vx, dy = -q.vy; if (q.vz > 0 && Math.abs(dx) < 1e-3) dx = 1e-3; var l = Math.hypot(dx, dy) || 1, ux = dx / l, uy = dy / l, k = Math.min((W / 2 - 70) / Math.max(1e-3, Math.abs(ux)), (Hh / 2 - 60) / Math.max(1e-3, Math.abs(uy))); // pinned to the screen edge, arrow pointing at the hider
          el.classList.add('edge'); el.style.display = ''; el.style.left = (W / 2 + ux * k) + 'px'; el.style.top = (Hh / 2 + uy * k + 20) + 'px'; el.firstChild.style.transform = 'rotate(' + Math.atan2(uy, ux) + 'rad)'; }
        if (hunter && cat) { var ds = el.querySelector('.ds'); if (ds) ds.textContent = Math.round(q.dist) + ' m'; } }); }
    if (ui.role === 'cat') { els.bDecoy.lastChild.textContent = G.decoyCd > 0 ? Math.ceil(G.decoyCd) + 's' : ''; if (G.paint.on) { var px = G.paint.size / Math.max(0.5, G.cam.dist * 0.62) / Math.tan(52 * Math.PI / 360) * G.vh; els.ring.style.width = els.ring.style.height = Math.max(6, px) + 'px'; } }
    if (ui.role === 'dog' && d.phase === 'seek') { var p = G.state.players.you; els.cross.classList.toggle('cd', G.simT - p.lastShot < RULES.dog.shotIntervalSec); }
    bubs = bubs.filter(function (b) { b.t -= 0.016; if (b.t <= 0 || !b.en.c.root.visible) { b.el.remove(); return false; } var q = G.project(b.en); b.el.style.left = q.x + 'px'; b.el.style.top = (q.y - 26) + 'px'; b.el.style.display = q.vis ? '' : 'none'; return true; });
    if (G.tags && d.phase !== 'reveal') { if (!ui.liveTags) ui.liveTags = {}; G.ents.forEach(function (en) { if (en === G.me || en.fp) return; var t = ui.liveTags[en.id]; if (!t) t = ui.liveTags[en.id] = h('div', 'tag ' + (en.team === 'dog' ? 'dogt' : 'safe'), en.name, els.bubbles); var q = G.project(en); t.style.left = q.x + 'px'; t.style.top = q.y + 'px'; t.style.display = q.vis && en.c.root.visible ? '' : 'none'; }); } else if (ui.liveTags) { Object.keys(ui.liveTags).forEach(function (k) { ui.liveTags[k].remove(); }); ui.liveTags = null; }
    if (ui.heardT > 0) { ui.heardT -= 0.016; if (ui.heardT <= 0) show(els.heard, false); }
  }
  function lineup(d) {
    var names = { stand: '站立（跑步中）', crouch: '壓低' }; SG.POSE_LIST.forEach(function (p) { names[p[0]] = p[1]; });
    var list = d.kind === 'cat' ? SG.CATS : d.kind === 'dog' ? SG.DOGS : null, s = '', keys = list ? Object.keys(list) : d.kind === 'pose3' ? [[0, names[d.pose] + '・正面'], [0, '側面'], [0, '背面']] : SG.POSE_LIST.slice(d.row * 3, d.row * 3 + 3);
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
    P.setRGB = function (rgb) { G.paint.rgb2 = P.getRGB(); var n = rgb2hsv(rgb[0], rgb[1], rgb[2]); if (n[1] < 0.01) n[0] = hsv[0]; hsv = n; sw.firstChild.style.background = css(rgb); sync(); };
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
    var PATS = [['', '素色'], ['stripe', '條紋'], ['check', '格子'], ['wood', '木紋'], ['tatami', '榻榻米']];
    [['brush', '筆', IC.brush], ['pattern', '素色', IC.pat], ['pick', '取色', IC.drop], ['fill', '填滿', IC.fill], ['hard', '硬邊', IC.soft], ['undo', '復原', IC.undo]].forEach(function (t) {
      var b = h('button', '', t[2] + t[1], tl); b.dataset.tool = t[0];
      b.onclick = function () { if (t[0] === 'pattern') { var ix = 0; PATS.forEach(function (q, k) { if (q[0] === (G.paint.pattern || '')) ix = k; }); var nx = PATS[(ix + 1) % PATS.length]; G.paint.pattern = nx[0]; b.lastChild.textContent = nx[1]; b.dataset.pat = nx[0]; G.paint.tool = 'brush'; } else if (t[0] === 'fill') G.fillAll(); else if (t[0] === 'undo') G.undo(); else if (t[0] === 'hard') { G.paint.hard = !G.paint.hard; b.lastChild.textContent = G.paint.hard ? '硬邊' : '軟邊'; } else G.paint.tool = t[0]; markTool(); b.blur(); };
    });
    els.wl = h('div', 'wl', '<b>白色剩餘</b><i><u></u></i><span>100%</span><em><span class="key">H</span> 按住顯示還沒塗到的地方</em>', pp);
    markTool(); sync();
  }
  function markTool() { [].forEach.call(els.tools.children, function (b) { var t = b.dataset.tool; b.classList.toggle('on', t === G.paint.tool || (t === 'hard' && G.paint.hard) || (t === 'pattern' && !!G.paint.pattern)); }); }
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
      '<tr><td>' + K('R') + '</td><td>按住開姿勢輪，放開選定</td></tr><tr><td>' + K('C') + '</td><td>按住壓低（慢慢走，不算逃跑）</td></tr><tr><td>' + K('F') + '</td><td>開關塗色；左鍵在身上塗，' + K('Alt') + '+點 取畫面上的顏色（加 ' + K('Shift') + ' 取材質本色），滾輪調筆刷，花紋筆跟著筆劃方向</td></tr>' +
      '<tr><td>' + K('Ctrl') + '+' + K('Z') + '</td><td>復原</td></tr><tr><td>' + K('1') + ' ' + K('Q') + ' ' + K('X') + '</td><td>喵叫／放分身／收回分身</td></tr><tr><td>右鍵拖曳</td><td>轉視角</td></tr></table>' +
      '<h5 class="d">' + IC.paw + ' 狗（找）</h5><table><tr><td>' + K('W') + K('A') + K('S') + K('D') + '</td><td>移動</td></tr><tr><td>滑鼠／方向鍵</td><td>看四周</td></tr><tr><td>左鍵</td><td>漆彈槍開火：打空少一發、打中多一發，每 ' + RULES.dog.shotIntervalSec + ' 秒一發</td></tr><tr><td>右鍵</td><td>第一／第三人稱</td></tr><tr><td>' + K('空白') + ' ' + K('Ctrl') + '</td><td>跳／蹲</td></tr></table><div class="row"></div>';
    else {
      p.innerHTML = '<h3>房主設定</h3><div class="set"></div><div class="row"></div>';
      var b = p.querySelector('.set'), S = G.settings, R0 = window.SG_RULES;
      function sl(label, key, min, max, fmt, on) { var x = slider(b, label, { wide: true, min: min, max: max, value: S[key], fmt: fmt || function (v) { return Math.round(v) + ' 秒'; }, on: function (v) { S[key] = Math.round(v); if (on) on(v); } }); x.row.dataset.s = key; return x; }
      function tg(label, key, on) { var r = h('div', 'tgrow', '<span>' + label + '</span><div class="tg hit' + (S[key] ? ' on' : '') + '"><i></i></div>', b), t = r.lastChild; t.dataset.t = key; t.onclick = function () { S[key] = !S[key]; t.classList.toggle('on', S[key]); if (on) on(S[key]); if (SG.audio) SG.audio.play('click'); }; return r; }
      h('h5', '', '回合', b);
      sl('準備時間', 'prep', 30, 300); sl('搜索時間', 'seek', 60, 600); sl('揭曉時間', 'reveal', 10, 60);
      sl('狗的數量', 'dogs', 0, 3, function (v) { return Math.round(v) ? Math.round(v) + ' 隻' : '自動'; }); sl('彈藥數', 'ammo', 1, 30, function (v) { return Math.round(v) + ' 發'; });
      tg('彈藥不限量', 'unlimited'); tg('強制喵叫', 'forcedMeow'); sl('喵叫間隔', 'meowEvery', R0.cat.forcedMeowMinSec, 120);
      tg('狗看得到「眼皮底下」排行', 'board');
      h('h5', '', '自訂規則（我們自己加的，預設全關）', b);
      tg('夜晚模式（關燈，狗有手電筒）', 'night'); tg('犬種有不同的視角高度', 'breedEyes'); tg('塗色輔助：環境色建議＋花紋筆', 'paintAids'); tg('撞倒東西的聲音會引來狗', 'knockNoise');
      h('div', 'note', '聞一聞、嘲諷加分、換位加分：還沒做。', b);
      h('h5', '', '畫面與聲音', b);
      slider(b, '音量', { wide: true, min: 0, max: 100, value: SG.audio ? SG.audio.volume * 100 : 70, on: function (v) { if (SG.audio) SG.audio.setVolume(v / 100); } });
      slider(b, '泛光', { wide: true, min: 0, max: 100, value: SG.post.final.uBloom.value * 100, on: function (v) { SG.post.final.uBloom.value = v / 100; } });
      slider(b, '陰影感', { wide: true, min: 0, max: 100, value: SG.post.final.uAO.value * 100, on: function (v) { SG.post.final.uAO.value = v / 100; } });
    }
    h('button', 'btn cat', '知道了', p.lastChild).onclick = function () { show(els.modal, false); };
    show(els.modal, true);
  }
  ui.openModal = openModal; ui.els = els; ui.h = h; ui.show = show; ui.toast = toast; ui.slider = slider; ui.IC = IC;
})();
