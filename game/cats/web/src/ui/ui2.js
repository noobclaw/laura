/* 貓躲狗找 — menus and HUD pieces that follow the layout logic of the original (functions and placement, not artwork):
   main menu, room (host) settings in three columns, options, lobby with the hunter lottery, body picker,
   radial pose wheel (8 + cancel), right-edge key column, bottom-centre clone slots and context keys. */
(function () {
  'use strict';
  var SG = (window.SG = window.SG || {}), G, bus, ui, E, h, show, root, hud, els = {};
  var T = {
    zh: { create: '建立房間', find: '尋找房間', options: '設定', quit: '結束遊戲', maps: '地圖', mode: '遊戲模式', prep: '繪畫時間（秒）', seek: '搜索時間（秒）', reveal: '對答案時間（秒）', meow: '強制挑釁間隔（秒）', board: '向獵人顯示遺漏排行榜', on: '開啟', off: '關閉', start: '開始遊戲', back: '返回', filters: '篩選', mono: '單色', horror: '恐怖', mosaic: '像素（馬賽克）', map: '地圖', random: '隨機', soon: '準備中',
      basic: '基本', infection: '感染', double: '雙重', basicD: '獵人數量固定，被找到的貓出局。<br>時間到還有貓沒被找到，貓隊獲勝。', infectionD: '被抓到就會變成獵人。<br>躲到最後即可勝利。', doubleD: '一開始所有人一起躲藏。<br>之後所有人一起找，最先找到所有人的獲勝。',
      custom: '自訂規則（我們自己加的，預設全關）', night: '夜晚模式（關燈，獵人有手電筒）', breedEyes: '犬種有不同的視角高度', paintAids: '塗色輔助：環境色建議＋花紋筆', knockNoise: '撞倒東西的聲音會引來獵人', unlimited: '彈藥不限量', ammo: '彈藥數', dogs: '獵人數量（0＝自動）',
      lottery: '獵人抽選', stand: '請站在這裡', ready: '人在大廳', body: '身體類型', lobbyTip: '站到墊子上＝報名當獵人（狗）。倒數結束時抽選。', users: '玩家管理', friends: '好友列表', audio: '聲音', video: '圖像', general: '遊戲全般', faq: '常見問題', master: '主音量', sfx: '音效', amb: '環境音', quality: '畫質', low: '低', high: '高', res: '解析度縮放', shadows: '陰影', post: '後製（泛光、陰影感）', lang: '語言', sens: '滑鼠靈敏度', invert: '反轉 Y 軸', fov: '獵人視野（FOV）',
      noNet: '多人連線還沒做完。現在只能自己開房，其他位置由機器人補上。', quitWeb: '在瀏覽器裡請直接關閉分頁。', nofriends: '好友列表需要連線功能，尚未完成。', k_chat: '聊天', k_taunt: '挑釁', k_pose: '姿勢', k_paint: '繪畫模式', k_lock: '按住＝鎖定朝向', k_tags: '切換名牌顯示', k_thru: '切換穿透描繪', k_mic: '麥克風（未做）', k_ear: '耳機（未做）', k_fire: '開火', k_third: '第三人稱', k_jump: '跳', k_crouch: '蹲', k_run: '跑', climb: '攀爬', free: '切換到自由鏡頭', watch: '看其他玩家', next: '換人', rel: '解除', down: '下', up: '上', cancel: '取消', more: '更多姿勢', eyedrop: '3D 滴管（長按）', brush: '筆刷大小', shade: '陰影', camrot: '鏡頭旋轉', zoom: '縮放', skip: '好了／跳過' },
    ja: { create: 'サーバーを立てる', find: 'サーバーを探す', options: '設定', quit: 'ゲーム終了', maps: 'マップ', mode: 'ゲームモード', prep: 'ペイント時間（秒）', seek: '探索時間（秒）', reveal: '答え合わせ時間（秒）', meow: '強制挑発の間隔（秒）', board: '見落としランキングをハンターに表示', on: 'オン', off: 'オフ', start: 'ゲーム開始', back: '戻る', filters: 'フィルター', mono: 'モノクロ', horror: 'ホラー', mosaic: 'モザイク', map: 'マップ', random: 'ランダム', soon: '準備中',
      basic: 'ベーシック', infection: '増え鬼', double: 'ダブル', basicD: 'ハンターの数は固定。見つかった猫は脱落。<br>時間切れまで隠れきれば猫チームの勝ち。', infectionD: '捕まるとハンターになる。<br>最後まで隠れきれば勝ち。', doubleD: '最初は全員で隠れる。<br>その後は全員で探し、最初に全員を見つけた人の勝ち。',
      custom: 'カスタムルール（独自追加・初期設定はすべてオフ）', lottery: 'ハンター抽選', stand: 'ここに立ってください', ready: '人がロビーにいます', body: 'ボディタイプ', users: 'ユーザー管理', friends: 'フレンド', audio: 'サウンド', video: 'グラフィック', general: 'ゲーム全般', faq: 'よくある質問', master: 'マスター音量', sfx: '効果音', amb: '環境音', lang: '言語', sens: 'マウス感度', invert: 'Y軸反転', fov: 'ハンターの視野（FOV）', k_chat: 'チャット', k_taunt: '挑発', k_pose: 'ポーズ', k_paint: 'ペイントモード', k_lock: '回転ロック', k_tags: '名札の切り替え', k_thru: '貫通描画の切り替え', climb: 'よじ登る', free: 'フリーカメラに切り替え', rel: '解除', down: '下', up: '上', cancel: 'キャンセル' },
    en: { create: 'Create room', find: 'Find room', options: 'Settings', quit: 'Quit', maps: 'Maps', mode: 'Game mode', prep: 'Painting time (s)', seek: 'Search time (s)', reveal: 'Answer-check time (s)', meow: 'Forced taunt interval (s)', board: 'Show overlooked ranking to hunters', on: 'On', off: 'Off', start: 'Start game', back: 'Back', filters: 'Filters', mono: 'Monochrome', horror: 'Horror', mosaic: 'Mosaic', map: 'Map', random: 'Random', soon: 'coming',
      basic: 'Basic', infection: 'Infection', double: 'Double', basicD: 'Fixed number of hunters; a found cat is out.<br>If any cat is still hidden when time runs out, the cats win.', infectionD: 'If you are caught you become a hunter.<br>Stay hidden to the end to win.', doubleD: 'Everyone hides together first.<br>Then everyone searches; the first to find all the others wins.',
      custom: 'Custom rules (our own additions, all off by default)', lottery: 'Hunter lottery', stand: 'Stand here', ready: 'in the lobby', body: 'Body type', users: 'Players', friends: 'Friends', audio: 'Audio', video: 'Graphics', general: 'General', faq: 'FAQ', master: 'Master volume', sfx: 'Effects', amb: 'Ambience', lang: 'Language', sens: 'Mouse sensitivity', invert: 'Invert Y', fov: 'Hunter field of view', k_chat: 'Chat', k_taunt: 'Taunt', k_pose: 'Pose', k_paint: 'Paint mode', k_lock: 'Rotation lock', k_tags: 'Name tags', k_thru: 'See-through painting', climb: 'Climb', free: 'Free camera', rel: 'Release', down: 'Down', up: 'Up', cancel: 'Cancel' }
  };
  function t(k) { var L = T[G.opts.lang] || T.zh; return L[k] || T.zh[k] || k; }
  var MODES = ['basic', 'infection', 'double'], MAPS = [['random', 'random'], ['home', '老家'], ['soon1', '澡堂街'], ['soon2', '夜市'], ['soon3', '小學校']];
  var WHEEL = [['sit', '坐下'], ['belly', '仰躺'], ['arch', '拱背'], ['hind', '站起來'], ['pawsup', '搭牆'], ['stretch', '伸懶腰'], ['curl', '蜷成團'], ['sphinx', '趴臥'], ['loaf', '母雞蹲'], ['side', '側躺'], ['box', '箱坐'], ['hang', '掛在邊上'], ['roll', '打滾'], ['crouch', '壓低'], ['stand', '站立'], ['stand', '站立']];
  function key(k) { return '<span class="key">' + k + '</span>'; }
  function cyc(parent, label, vals, get, set, fmt) { // ‹ value › selector, as in the original's settings
    var r = h('div', 'cyc', (label ? '<label>' + label + '</label>' : '') + '<div><b class="pv hit">‹</b><span></span><b class="nx hit">›</b></div>', parent), sp = r.querySelector('span');
    function draw() { sp.textContent = fmt ? fmt(get()) : get(); } function step(d) { var i = vals.indexOf(get()); set(vals[(i + d + vals.length) % vals.length]); draw(); if (SG.audio) SG.audio.play('click'); }
    r.querySelector('.pv').onclick = function () { step(-1); }; r.querySelector('.nx').onclick = function () { step(1); }; draw(); r.draw = draw; return r;
  }
  function num(parent, label, k, min, max) { var S = G.settings, r = h('div', 'numf', '<label>' + label + '</label><input type="number" min="' + min + '" max="' + max + '">', parent), i = r.lastChild; i.dataset.f = k; i.value = S[k]; i.onchange = function () { S[k] = Math.max(min, Math.min(max, Math.round(+i.value || 0))); i.value = S[k]; if (k === 'meowEvery') S.forcedMeow = S[k] > 0; }; i.addEventListener('keydown', function (e) { e.stopPropagation(); }); return r; }
  function tog(parent, label, k, obj, on) { obj = obj || G.settings; return cyc(parent, label, [false, true], function () { return !!obj[k]; }, function (v) { obj[k] = v; if (on) on(v); }, function (v) { return v ? t('on') : t('off'); }); }

  /* ------------------------------------------------------------------ main menu (on the title) */
  function buildMenu() {
    var ti = E.title, old = ti.querySelector('button[data-act=host]'); if (old) old.style.display = 'none';
    if (els.mm) els.mm.remove(); if (els.langs) els.langs.remove();
    var m = els.mm = h('div', 'mm', '', ti);
    [['create', function () { openHost(); }], ['find', function () { info(t('find'), t('noNet')); }], ['options', function () { openOptions('audio'); }], ['quit', function () { if (G.electron) window.close(); else ui.toast(t('quitWeb')); }]].forEach(function (b) { var x = h('button', 'btn', t(b[0]), m); x.dataset.act = 'mm-' + b[0]; x.onclick = b[1]; });
    var mp = h('button', 'btn maps', t('maps'), m); mp.onclick = function () { openHost(); };
    var l = els.langs = h('div', 'langs', '', ti);
    [['zh', '繁體中文'], ['ja', '日本語'], ['en', 'English']].forEach(function (x) { var b = h('button', 'lg' + (G.opts.lang === x[0] ? ' on' : ''), x[1], l); b.dataset.lang = x[0]; b.onclick = function () { G.opts.lang = x[0]; buildMenu(); keycol(); cbar(); }; });
  }
  function info(title, text) { var m = h('div', 'ov2', '<div class="panel box"><h3>' + title + '</h3><p>' + text + '</p></div>', root); h('button', 'btn', t('back'), m.firstChild).onclick = function () { m.remove(); }; }

  /* ------------------------------------------------------------------ room settings: three columns */
  function openHost() {
    if (els.hs) els.hs.remove();
    var S = G.settings, o = els.hs = h('div', 'ov2 hs', '', root), L = h('div', 'col panel', '', o), M = h('div', 'col panel', '', o), R = h('div', 'col panel', '', o), cap;
    h('h3', '', t('mode'), L);
    cyc(L, '', MODES, function () { return S.mode; }, function (v) { S.mode = v; drawCap(); }, function (v) { return t(v); }).dataset.k = 'mode';
    num(L, t('prep'), 'prep', 5, 999999); num(L, t('seek'), 'seek', 10, 999999); num(L, t('reveal'), 'reveal', 5, 999999);
    if (!S.forcedMeow) S.meowEvery0 = 0; var mi = num(L, t('meow'), 'meowEvery', 0, 600); if (!S.forcedMeow) mi.lastChild.value = 0; mi.lastChild.onchange = function () { var v = Math.max(0, Math.min(600, Math.round(+mi.lastChild.value || 0))); if (v > 0 && v < SG.RULES.cat.forcedMeowMinSec) v = SG.RULES.cat.forcedMeowMinSec; S.forcedMeow = v > 0; if (v > 0) S.meowEvery = v; mi.lastChild.value = v; };
    tog(L, t('board'), 'board').dataset.k = 'board'; num(L, '排行榜更新間隔（秒，給獵人看的）', 'boardEvery', 1, 600);
    var d = h('details', 'custom', '<summary>' + t('custom') + '</summary>', L);
    ['night', 'breedEyes', 'paintAids', 'knockNoise'].forEach(function (k) { tog(d, t(k), k).dataset.k = k; });
    num(L, '獵人數量', 'dogs', 1, 3);
    cyc(L, '彈數限制', [false, true], function () { return !S.unlimited; }, function (v) { S.unlimited = !v; am.style.display = v ? '' : 'none'; }, function (v) { return v ? t('on') : t('off'); }).dataset.k = 'ammoLimit'; var am = num(L, '彈數（1–99）', 'ammo', 1, 99); am.style.display = S.unlimited ? 'none' : ''; // the original's optional rule since 2.3.0, at the bottom of the list
    var st = h('button', 'btn cat big', t('start'), L); st.dataset.act = 'hs-start'; st.onclick = function () { o.remove(); els.hs = null; G.enterLobby(); };
    var bk = h('button', 'btn', key('Esc') + ' ' + t('back'), L); bk.dataset.act = 'hs-back'; bk.onclick = function () { o.remove(); els.hs = null; };
    h('h3', '', t('filters'), M); h('p', 'note', '只影響獵人的畫面，用來提高難度。', M);
    tog(M, t('mono'), 'fMono').dataset.k = 'fMono'; var LV = ['關閉', '弱', '中', '強'];
    [['fHorror', 'horror'], ['fMosaic', 'mosaic']].forEach(function (f) { cyc(M, t(f[1]), [0, 1, 2, 3], function () { return +S[f[0]] || 0; }, function (v) { S[f[0]] = v; }, function (v) { return LV[v]; }).dataset.k = f[0]; });
    h('h3', '', t('map'), R); var im = h('img', 'mapimg', '', R); im.src = G.mapImage();
    var ls = h('div', 'maplist', '', R); MAPS.forEach(function (m) { var soon = /^soon/.test(m[0]), b = h('button', (S.map === m[0] ? 'on' : '') + (soon ? ' soon' : ''), (m[0] === 'random' ? t('random') : m[1]) + (soon ? '（' + t('soon') + '）' : ''), ls); b.dataset.map = m[0]; if (!soon) b.onclick = function () { S.map = m[0]; ls.querySelectorAll('button').forEach(function (x) { x.classList.toggle('on', x === b); }); }; });
    cap = h('div', 'modecap2', '', R); function drawCap() { cap.innerHTML = '<b>' + t(S.mode) + '</b>' + t(S.mode + 'D'); } drawCap();
  }
  /* ------------------------------------------------------------------ options */
  function openOptions(tab) {
    if (els.op) els.op.remove();
    var O = G.opts, o = els.op = h('div', 'ov2 op', '', root), L = h('div', 'side', '', o), P = h('div', 'pane panel', '', o), A = SG.audio;
    ['users', 'friends', 'audio', 'video', 'general', 'faq'].forEach(function (k) { var b = h('button', 'btn' + (k === tab ? ' on' : ''), t(k), L); b.dataset.tab = k; b.onclick = function () { openOptions(k); }; });
    var bk = h('button', 'btn', key('Esc') + ' ' + t('back'), L); bk.dataset.act = 'op-back'; bk.onclick = function () { o.remove(); els.op = null; buildMenu(); };
    h('h3', '', t(tab), P);
    var sl = function (label, min, max, val, fmt, on) { return ui.slider(P, label, { wide: true, min: min, max: max, value: val, fmt: fmt, on: on }); }, pc = function (v) { return Math.round(v) + '%'; };
    if (tab === 'users') { var st = G.state; h('p', '', st ? Object.keys(st.players).map(function (id) { var e = G.ent(id); return (e ? e.name : id) + (st.players[id].bot ? '（機器人）' : '（你，房主）'); }).join('<br>') : '還沒有建立房間。建立房間後這裡會列出所有玩家。', P); h('p', 'note', '踢人與封鎖需要連線功能，尚未完成。', P); }
    if (tab === 'friends') h('p', '', t('nofriends'), P);
    if (tab === 'audio') { sl(t('master'), 0, 100, A ? A.volume * 100 : 70, pc, function (v) { if (A) A.setVolume(v / 100); }).row.dataset.s = 'master'; sl(t('sfx'), 0, 100, O.sfx * 100, pc, function (v) { O.sfx = v / 100; if (A) A.setLevel('sfx', O.sfx); }).row.dataset.s = 'sfx'; sl(t('amb'), 0, 100, O.amb * 100, pc, function (v) { O.amb = v / 100; if (A) A.setLevel('amb', O.amb); }).row.dataset.s = 'amb'; sl('音樂', 0, 100, O.music * 100, pc, function (v) { O.music = v / 100; if (A) { A.levels.mus = O.music; if (A.mus && A.mus.gainNode) A.mus.gainNode.gain.value = O.music; } }).row.dataset.s = 'music'; tog(P, '搜索階段也播放音樂（會蓋過腳步聲）', 'searchMusic', O).dataset.k = 'searchMusic'; h('p', 'note', '音樂與音效全部是程式合成的，還沒有人實際聽過。', P); }
    if (tab === 'video') { cyc(P, t('quality'), ['low', 'high'], function () { return O.quality; }, function (v) { O.quality = v; ui.toast('畫質在重新載入後生效（網址加 ?q=' + v + '）'); }, function (v) { return t(v); }); sl(t('res'), 50, 100, O.res * 100, pc, function (v) { O.res = v / 100; G.applyOpts(); }).row.dataset.s = 'res'; tog(P, t('shadows'), 'shadows', O, G.applyOpts).dataset.k = 'shadows'; tog(P, t('post'), 'post', O, G.applyOpts).dataset.k = 'post'; cyc(P, '幀率上限', [0, 60, 120, 144], function () { return O.fpsCap; }, function (v) { O.fpsCap = v; }, function (v) { return v ? v + ' fps' : '不限'; }).dataset.k = 'fpsCap'; tog(P, '顯示 FPS（F3）', 'showFps', O).dataset.k = 'showFps'; h('p', 'note', '動態模糊：沒有（0）。', P); }
    if (tab === 'general') { cyc(P, t('lang'), ['zh', 'ja', 'en'], function () { return O.lang; }, function (v) { O.lang = v; openOptions('general'); keycol(); cbar(); }, function (v) { return { zh: '繁體中文', ja: '日本語', en: 'English' }[v]; }).dataset.k = 'lang'; sl(t('sens'), 30, 300, O.sens * 100, pc, function (v) { O.sens = v / 100; }).row.dataset.s = 'sens'; tog(P, t('invert'), 'invertY', O).dataset.k = 'invertY'; sl(t('fov'), 80, 110, O.fov, function (v) { return Math.round(v) + '°'; }, function (v) { O.fov = Math.round(v); }).row.dataset.s = 'fov'; h('p', 'note', '日本語と English は新しいメニューと操作ヒントだけ対応しています。其餘文字目前只有繁體中文。', P); }
    if (tab === 'faq') h('div', 'faq', '<p><b>Q. 怎麼玩？</b><br>貓：在繪畫時間裡找地方、擺姿勢（按住 ' + key('R') + '）、把自己塗成背景的顏色（' + key('F') + '）。獵人（狗）：搜索時間裡用漆彈槍找出貓，打空會少一發，打中補一發。</p><p><b>Q. 分數是什麼？</b><br>獵人的畫面裡有你、卻沒發現你，你的分數就一直漲；獵人正對著你時每一跳 45 分。移動中不算分。</p><p><b>Q. 可以爬牆嗎？</b><br>可以。靠近任何東西按 ' + key('空白') + ' 就黏上去，' + key('空白') + ' 上、' + key('Ctrl') + ' 下、' + key('Shift') + ' 放開。黏著不動也不會滑下來。</p><p><b>Q. 被東西擋住畫不到？</b><br>按 ' + key('3') + ' 開啟穿透描繪。</p><p><b>Q. 可以連線嗎？</b><br>還不行。目前其他玩家都是機器人。</p>', P);
  }

  /* ------------------------------------------------------------------ HUD: right-edge key column, bottom-centre clone slots + context keys */
  function keycol() {
    var c = els.keycol; if (!c) return; var me = G.me, st = G.state; if (!me || !st || G.mode !== 'play') { c.innerHTML = ''; return; }
    var row = function (k, label, on, dim) { return '<div class="kc' + (on ? ' on' : '') + (dim ? ' dim' : '') + '">' + key(k) + '<span>' + label + '</span></div>'; }, s = row('T', t('k_chat'));
    if (G.fly) s += G.fly.hide ? row('5', '回到身體') + row('WASD', '飛行') : row('4', t('watch')) + row('5', t('free')) + row('左鍵', t('next'));
    else if (me.team === 'cat') s += row('1', t('k_taunt')) + row('R', t('k_pose')) + row('F', t('k_paint'), G.paint.on) + row('右鍵', t('k_lock'), G.viewLock) + row('2', t('k_tags'), G.tags) + row('3', t('k_thru'), G.seeThrough !== false) + row('5', t('free')) + row('Y', '夠了（跳過）');
    else s += row('左鍵', t('k_fire')) + row('右鍵', t('k_third'), G.third) + row('空白', t('k_jump')) + row('Ctrl', t('k_crouch')) + row('Shift', t('k_run')) + row('2', t('k_tags'), G.tags);
    s += row('V', t('k_mic'), false, true) + row('B', t('k_ear'), false, true); c.innerHTML = s;
  }
  function cbar() {
    var c = els.cbar; if (!c) return; var me = G.me, st = G.state; if (!me || !st || G.mode !== 'play' || st.phase === 'reveal') { c.innerHTML = ''; return; }
    var kb = function (k, label) { return '<div class="cb">' + key(k) + '<span>' + label + '</span></div>'; }, s = '';
    if (me.team === 'cat' && !G.fly) {
      var n = G.decoys.filter(function (d) { return d.c.root.visible; }).length, mx = SG.RULES.cat.maxDecoys;
      s += '<div class="slots">' + key('Q'); G.decoySlots.forEach(function (sl, i) { s += '<i class="dia' + (sl.e ? ' used' : sl.cd > 0 ? ' cd' : '') + '" data-slot="' + i + '" title="' + (sl.cd > 0 ? Math.ceil(sl.cd) + ' s' : '') + '">' + (!sl.e && sl.cd > 0 ? '<u>' + Math.ceil(sl.cd) + '</u>' : '') + '</i>'; }); s += '<span class="key x">X</span></div><div class="ctx">';
      if (G.paint.on) s += kb('空白', t('eyedrop')) + kb('右鍵拖', t('brush')) + kb('V', t('shade')) + kb('中鍵拖', t('camrot')) + kb('滾輪', t('zoom'));
      else if (me.cling) s += kb('Shift', t('rel')) + kb('Ctrl', t('down')) + kb('空白', t('up'));
      else s += kb('空白', '跳／跳向牆面黏住') + kb('Shift', t('k_run')) + kb('左鍵+A/D', '原地轉身');
      s += '</div>';
    } else if (G.fly && G.fly.hide) s += '<div class="ctx">' + kb('4', G.fly.move ? '自由移動：開（WASD 飛）' : '自由移動') + kb('5', '回到身體') + '</div>';
    else if (G.fly) s += '<div class="ctx">' + kb('4', t('watch')) + kb('5', t('free')) + '</div>';
    c.innerHTML = s;
  }
  /* ------------------------------------------------------------------ radial pose wheel: 8 + cancel, mouse selected; second page with the rest */
  var page = 0, hover = null, amtPose = null;
  function poseIcon(pose) { try { return SG.poseIconURL ? SG.poseIconURL(pose, { size: 64 }) : ''; } catch (e) { return ''; } }
  function drawWheel() {
    var w = els.pw2, PG = SG.POSE_PAGES || [WHEEL.slice(0, 8).map(function (p) { return p[0]; }), WHEEL.slice(8).map(function (p) { return p[0]; })], INFO = SG.POSE_INFO || {}, cur = G.me && G.me.c;
    w.innerHTML = '<div class="hub"><b>' + t('k_pose') + '</b><small>' + (page + 1) + ' / ' + PG.length + '　點一下換頁</small><div class="amt"><i></i></div><small class="amtl"></small></div>';
    var mk = function (pose, label, ang, cls) { var ic = pose === 'stand' ? '' : poseIcon(pose), b = h('button', 'seg ' + (cls || '') + (cur && cur.pose === pose ? ' cur' : ''), (ic ? '<img src="' + ic + '" alt="">' : '') + '<span>' + label + '</span>', w); b.dataset.pose = pose; b.style.left = Math.cos(ang) * 158 + 'px'; b.style.top = Math.sin(ang) * 158 + 'px'; b.onmouseenter = function () { setHover(b); }; b.onclick = function () { pick(pose); }; return b; };
    mk('stand', '✕ ' + t('cancel'), Math.PI / 2, 'cancel');
    for (var i = 0; i < 8; i++) { var p = PG[page][i]; if (p) mk(p, (INFO[p] && INFO[p].label) || p, Math.PI / 2 + (i + 1) * (Math.PI * 2 / 9)); }
    var c = G.me && G.me.c, TM = ['tuck', 'straight', 'curl'], TN = { tuck: '收起', straight: '伸直', curl: '捲起' };
    var tb = h('button', 'more tailb', '尾巴：' + TN[(c && c.tailMode) || 'tuck'], w); tb.dataset.act = 'tail'; tb.onclick = function (e) { e.stopPropagation(); G.setTail(TM[(TM.indexOf(G.me.c.tailMode || 'tuck') + 1) % 3]); drawWheel(); };
    var eb = h('button', 'more earb', '耳朵：' + (c && c.earFlat ? '貼平' : '立'), w); eb.dataset.act = 'ears'; eb.onclick = function (e) { e.stopPropagation(); G.setEars(!G.me.c.earFlat); drawWheel(); };
    amount();
  }
  function setHover(b) { hover = b ? b.dataset.pose : null; els.pw2.querySelectorAll('.seg').forEach(function (x) { x.classList.toggle('hov', x === b); }); amount(); }
  /* the bar in the hub: how far the hovered (or current) pose goes; the mouse wheel changes it while R is held */
  function amount() { var c = G.me && G.me.c, hub = els.pw2.querySelector('.amt'); if (!hub || !c) return; var pose = hover && hover !== 'stand' ? hover : c.pose, INFO = (SG.POSE_INFO || {})[pose], a = pose === c.pose ? c.poseAmount : (amtPose && amtPose[0] === pose ? amtPose[1] : INFO ? INFO.amount : 0.5);
    hub.firstChild.style.width = Math.round((a == null ? 0.5 : a) * 100) + '%'; hub.style.visibility = pose === 'stand' || pose === 'crouch' ? 'hidden' : ''; els.pw2.querySelector('.amtl').textContent = pose === 'stand' || pose === 'crouch' ? '' : '滾輪：' + ((INFO && INFO.hint) || '程度') + '　' + Math.round((a == null ? 0.5 : a) * 100) + '%'; }
  function scrollAmount(dir) { var c = G.me && G.me.c; if (!c) return; var pose = hover && hover !== 'stand' ? hover : c.pose; if (pose === 'stand' || pose === 'crouch') return; var INFO = (SG.POSE_INFO || {})[pose];
    if (pose === c.pose) G.setPoseAmount(c.poseAmount + dir * 0.1); // the pose you are in changes live
    else { var a0 = amtPose && amtPose[0] === pose ? amtPose[1] : INFO ? INFO.amount : 0.5; amtPose = [pose, Math.max(0, Math.min(1, a0 + dir * 0.1))]; }
    amount(); }
  function pick(pose) { G.setPose(pose); if (amtPose && amtPose[0] === pose) G.setPoseAmount(amtPose[1]); amtPose = null; show(els.pw2, false); hover = null; }

  /* ------------------------------------------------------------------ lobby HUD + body picker */
  function lobbyHud() {
    var L = G.lobby, el = els.lobby; hud.classList.toggle('inlobby', !!L); show(el, !!L); if (!L) { if (els.bp) show(els.bp, false); return; }
    if (!el.dataset.built) { el.dataset.built = 1; el.innerHTML = '<div class="mapcard panel"><img><b>老家</b></div><div class="cnt"><b></b><small></small></div><div class="lot"><b></b><small></small><p></p></div>'; el.querySelector('img').src = G.mapImage(); var bb = h('button', 'btn bodyb', key('B') + ' ' + t('body'), el); bb.dataset.act = 'body'; bb.onclick = function () { bodyPicker(); bb.blur(); }; }
    el.querySelector('.cnt b').textContent = L.n + ' / ' + L.n; el.querySelector('.cnt small').textContent = t('ready');
    if (!el.querySelector('.ehint')) h('div', 'ehint', key('E') + ' 房主設定', el);
    el.querySelector('.lot b').textContent = Math.max(0, Math.ceil(L.t)); el.querySelector('.lot small').textContent = t('lottery'); el.querySelector('.lot p').textContent = L.on ? '✔ 你站在墊子上：這一局你當獵人' : t('lobbyTip'); el.querySelector('.lot').classList.toggle('on', !!L.on);
  }
  function bodyPicker() {
    if (!els.bp) { var p = els.bp = h('div', 'bp panel hide', '<h3>' + t('body') + '</h3><div class="grid"></div>', hud), g = p.lastChild; Object.keys(SG.CATS).forEach(function (k) { SG.RULES.cat.sizes.forEach(function (s) { var b = h('button', '', '<b>' + SG.CATS[k].name + '</b><small>x' + s.toFixed(1) + '</small>', g); b.dataset.body = k + ':' + s; b.onclick = function () { G.setBody(k, s); mark(); }; }); }); h('button', 'btn', t('back'), p).onclick = function () { show(p, false); }; }
    function mark() { els.bp.querySelectorAll('.grid button').forEach(function (b) { b.classList.toggle('on', b.dataset.body === G.pick.cat.breed + ':' + (G.pick.cat.size || 1)); }); }
    mark(); show(els.bp, els.bp.classList.contains('hide'));
  }

  SG.ui2 = {
    t: t, openHost: openHost, openOptions: openOptions,
    init: function () {
      G = SG.game; bus = SG.bus; ui = SG.ui; E = ui.els; h = ui.h; show = ui.show; hud = E.hud; root = hud.parentNode;
      els.keycol = h('div', 'keycol', '', hud); els.cbar = h('div', 'cbar', '', hud); els.pw2 = h('div', 'pw2 hide', '', hud); els.lobby = h('div', 'lobbyhud hide', '', hud);
      buildMenu(); drawWheel();
      ['mode', 'phase', 'viewlock', 'tags', 'seethrough', 'paintmode', 'cling', 'spectate', 'follow', 'decoy', 'infected', 'pose'].forEach(function (ev) { bus.on(ev, function () { setTimeout(function () { keycol(); cbar(); }, 0); }); });
      bus.on('mode', function (d) { if (d.mode === 'title') buildMenu(); show(els.pw2, false); lobbyHud(); });
      var n = 0; bus.on('frame', function () { if (G.lobby || !els.lobby.classList.contains('hide')) lobbyHud(); if (++n % 30 === 0) cbar(); });
      bus.on('wheel', function (d) { var ok = G.me && G.me.team === 'cat' && !G.me.out && G.state && G.state.phase !== 'reveal'; if (d.open && ok) { hover = null; drawWheel(); show(els.pw2, true); } else if (!d.open && !els.pw2.classList.contains('hide')) { if (hover) pick(hover); else show(els.pw2, false); } });
      var vx = 0, vy = 0; window.addEventListener('mousemove', function (e) { if (els.pw2.classList.contains('hide') || !(e.movementX || e.movementY)) return; if (document.pointerLockElement == null && !e.buttons && e.target && e.target.closest && e.target.closest('.pw2')) return; vx = Math.max(-160, Math.min(160, vx + e.movementX)); vy = Math.max(-160, Math.min(160, vy + e.movementY)); if (Math.hypot(vx, vy) < 45) return; var a = Math.atan2(vy, vx), best = null, bd = 9; els.pw2.querySelectorAll('.seg').forEach(function (b) { var ba = Math.atan2(parseFloat(b.style.top), parseFloat(b.style.left)), dd = Math.abs(Math.atan2(Math.sin(a - ba), Math.cos(a - ba))); if (dd < bd) { bd = dd; best = b; } }); if (best && best.dataset.pose !== hover) setHover(best); });
      bus.on('wheel', function (d) { if (d.open) { vx = vy = 0; } });
      window.addEventListener('mousedown', function (e) { if (els.pw2.classList.contains('hide') || (e.target.closest && e.target.closest('.pw2 button'))) return; page = (page + 1) % (SG.POSE_PAGES ? SG.POSE_PAGES.length : 2); hover = null; drawWheel(); e.stopPropagation(); }, true);
      window.addEventListener('wheel', function (e) { if (els.pw2.classList.contains('hide')) return; e.preventDefault(); e.stopPropagation(); scrollAmount(e.deltaY < 0 ? 1 : -1); }, { passive: false, capture: true }); // hold R + scroll: how far the pose goes
      window.addEventListener('keydown', function (e) { if (e.target && /INPUT|TEXTAREA/.test(e.target.tagName)) return; if (e.key === 'Escape') { if (els.hs) { els.hs.remove(); els.hs = null; e.stopImmediatePropagation(); } else if (els.op) { els.op.remove(); els.op = null; e.stopImmediatePropagation(); } } if ((e.key === 'b' || e.key === 'B') && G.lobby) bodyPicker(); if ((e.key === 'e' || e.key === 'E') && G.lobby && !els.hs) openHost(); if (e.key === 'F3') { e.preventDefault(); G.opts.showFps = !G.opts.showFps; } }, true);
      els.fps = h('div', 'fps hide', '', root); setInterval(function () { show(els.fps, !!G.opts.showFps); if (G.opts.showFps && G.ft) els.fps.textContent = Math.round(1 / G.ft) + ' fps　' + (G.ft * 1000).toFixed(1) + ' ms（最慢 ' + ((G.ftMax || 0) * 1000).toFixed(0) + ' ms）　' + (SG.post.sceneCalls || 0) + ' draw'; }, 250);
    }
  };
})();
