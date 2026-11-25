/* 貓躲狗找 — core round rules. Pure: no DOM, no three.js. apply(state, action, rules) -> { state, events }.
   Runs unchanged in the browser (window.SGCore) and under node (require). Numbers come from data/rules.json. */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory(); else root.SGCore = factory();
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';
  function clone(o) { return JSON.parse(JSON.stringify(o)); }

  function dogCountFor(n, rules) {
    for (var i = 0; i < rules.dogCount.length; i++) if (n <= rules.dogCount[i].maxPlayers) return rules.dogCount[i].dogs;
    return rules.dogCount[rules.dogCount.length - 1].dogs;
  }
  /* players: [{id, team?}] — teams already set are kept (single-player picks a side); the rest are drawn with rnd */
  /* modes: 'basic' (teams fixed), 'infection' (a found cat joins the dogs; the last cat standing is the best hider),
     'double' (everyone hides and paints, then everyone hunts everyone else; first to find all the others wins) */
  function createState(players, rules, rnd, mode) {
    rnd = rnd || Math.random; mode = mode || 'basic';
    var st = { mode: mode, phase: 'lobby', left: 0, elapsed: 0, seekElapsed: 0, winner: null, reason: null, players: {}, order: [], boardAt: 0, lastCat: null, votes: {} };
    if (mode === 'double') players = players.map(function (p) { return { id: p.id, team: 'cat', bot: p.bot }; });
    var free = players.filter(function (p) { return !p.team; }), dogs = dogCountFor(players.length, rules) - players.filter(function (p) { return p.team === 'dog'; }).length;
    free = free.slice();
    for (var i = free.length - 1; i > 0; i--) { var j = Math.floor(rnd() * (i + 1)), t = free[i]; free[i] = free[j]; free[j] = t; }
    players.forEach(function (p) {
      var team = p.team || (free.indexOf(p) < dogs ? 'dog' : 'cat');
      st.players[p.id] = { id: p.id, team: team, bot: !!p.bot, out: false, connected: true, ammo: team === 'dog' ? rules.dog.startAmmo : 0, lastShot: -1e9, score: 0, hits: 0, misses: 0, decoys: 0, found: [], hunter: team === 'dog' };
      st.order.push(p.id);
    });
    return st;
  }
  function list(st, team) { return st.order.map(function (id) { return st.players[id]; }).filter(function (p) { return p.team === team; }); }
  function catsAlive(st) { return list(st, 'cat').filter(function (p) { return !p.out && p.connected; }).length; }
  function hunters(st) { return st.order.map(function (id) { return st.players[id]; }).filter(function (p) { return p.hunter && p.connected; }); }
  function huntersWithAmmo(st) { return hunters(st).filter(function (p) { return p.ammo > 0; }).length; }
  function doubleLeader(st) { var best = null; st.order.forEach(function (id) { var p = st.players[id]; if (!best || p.found.length > best.found.length) best = p; }); return best; }

  function toPhase(st, phase, rules, ev) {
    st.phase = phase; st.elapsed = 0; st.votes = {};
    if (phase === 'seek' && st.mode === 'double') st.order.forEach(function (id) { var p = st.players[id]; p.hunter = true; p.ammo = rules.dog.startAmmo; });
    st.left = phase === 'prep' ? rules.round.prepSec : phase === 'seek' ? rules.round.seekSec : phase === 'reveal' ? rules.round.revealSec : 0;
    ev.push({ type: 'phase', phase: phase, left: st.left });
  }
  function end(st, winner, reason, rules, ev) {
    st.winner = winner; st.reason = reason;
    ev.push({ type: 'end', winner: winner, reason: reason });
    toPhase(st, 'reveal', rules, ev);
  }

  function apply(state, action, rules) {
    var st = clone(state), ev = [], p, c;
    switch (action.type) {
      case 'start':
        if (st.phase !== 'lobby') { ev.push({ type: 'rejected', why: 'not-in-lobby' }); break; }
        if (st.order.length < rules.round.minPlayers) { ev.push({ type: 'rejected', why: 'need-players' }); break; }
        st.winner = null; st.reason = null; st.seekElapsed = 0; st.boardAt = 0;
        toPhase(st, 'prep', rules, ev); break;
      case 'vote': // every connected human has to vote; bots always agree
        if (st.phase !== 'prep' && st.phase !== 'reveal') { ev.push({ type: 'rejected', why: 'cannot-skip' }); break; }
        st.votes[action.id] = true;
        var need = st.order.filter(function (id) { return !st.players[id].bot && st.players[id].connected; }), have = need.filter(function (id) { return st.votes[id]; });
        ev.push({ type: 'votes', have: have.length, need: need.length });
        if (have.length >= need.length) { if (st.phase === 'prep') toPhase(st, 'seek', rules, ev); else toPhase(st, 'lobby', rules, ev); }
        break;
      case 'skip': // unanimous vote to skip prep or reveal
        if (st.phase === 'prep') toPhase(st, 'seek', rules, ev);
        else if (st.phase === 'reveal') toPhase(st, 'lobby', rules, ev);
        else ev.push({ type: 'rejected', why: 'cannot-skip' });
        break;
      case 'tick':
        if (st.phase === 'lobby') break;
        st.left -= action.dt; st.elapsed += action.dt;
        if (st.phase === 'seek') {
          st.seekElapsed += action.dt;
          if (st.seekElapsed - st.boardAt >= rules.overlooked.boardEverySec) {
            st.boardAt = st.seekElapsed;
            ev.push({ type: 'board', rows: list(st, 'cat').map(function (q) { return { id: q.id, score: q.score }; }).sort(function (a, b) { return b.score - a.score; }) });
          }
        }
        if (st.left <= 0) {
          st.left = 0;
          if (st.phase === 'prep') toPhase(st, 'seek', rules, ev);
          else if (st.phase === 'seek') { if (st.mode === 'double') { var ld = doubleLeader(st); st.lastCat = ld.id; end(st, ld.id, 'time', rules, ev); } else end(st, catsAlive(st) > 0 ? 'cats' : 'dogs', 'time', rules, ev); }
          else if (st.phase === 'reveal') toPhase(st, 'lobby', rules, ev);
        }
        break;
      case 'shoot': // { dog, now, hit: catId|null, fleeing: bool (target speed above dog.fleeingSpeed), decoy: bool }
        p = st.players[action.dog];
        if (!p || !p.hunter || st.phase !== 'seek') { ev.push({ type: 'rejected', why: 'cannot-shoot' }); break; }
        if (p.ammo <= 0 && !rules.dog.unlimited) { ev.push({ type: 'rejected', why: 'no-ammo' }); break; }
        if (action.now - p.lastShot < rules.dog.shotIntervalSec - 1e-9) { ev.push({ type: 'rejected', why: 'cooldown' }); break; }
        p.lastShot = action.now;
        c = action.hit != null ? st.players[action.hit] : null;
        ev.push({ type: 'shot', dog: p.id });
        var valid = c && c.id !== p.id && (st.mode === 'double' ? p.found.indexOf(c.id) < 0 : (c.team === 'cat' && !c.out));
        if (valid) {
          if (!rules.dog.unlimited) p.ammo += rules.dog.hitDelta; p.hits++;
          ev.push({ type: 'hit', dog: p.id, cat: c.id, decoy: !!action.decoy, ammo: p.ammo });
          if (st.mode === 'double') {
            p.found.push(c.id); c.out = true; ev.push({ type: 'out', cat: c.id, by: p.id });
            if (p.found.length >= st.order.length - 1) { st.lastCat = p.id; end(st, p.id, 'double-all', rules, ev); }
          } else if (st.mode === 'infection') {
            st.lastCat = c.id; c.out = true; ev.push({ type: 'out', cat: c.id });
            if (catsAlive(st) === 0) end(st, 'dogs', 'all-found', rules, ev);
            else { c.team = 'dog'; c.hunter = true; c.ammo = rules.dog.startAmmo; c.lastShot = action.now; ev.push({ type: 'infected', cat: c.id }); }
          } else {
            c.out = true; ev.push({ type: 'out', cat: c.id });
            if (catsAlive(st) === 0) end(st, 'dogs', 'all-found', rules, ev);
          }
        } else {
          p.misses++;
          if (!action.fleeing && !rules.dog.unlimited) p.ammo += rules.dog.missDelta; // a shot at a running cat that misses costs nothing
          ev.push({ type: 'miss', dog: p.id, ammo: p.ammo, free: !!action.fleeing });
          if (p.ammo === rules.dog.lowAmmoWarn && !rules.dog.unlimited) ev.push({ type: 'lowAmmo', dog: p.id });
          if (!rules.dog.unlimited && huntersWithAmmo(st) === 0) { if (st.mode === 'double') { var l2 = doubleLeader(st); st.lastCat = l2.id; end(st, l2.id, 'no-ammo', rules, ev); } else end(st, 'cats', 'no-ammo', rules, ev); }
        }
        break;
      case 'overlook': // one tick (rules.overlooked.tickEverySec) of a hider being inside a hunter's view without being shot:
        // { cat, by, area (0..1 of the hunter's screen, 0 = occluded), centre (0 = dead centre … 1 = screen edge), dist (m) }
        c = st.players[action.cat];
        if (!c || (c.out && st.mode !== 'double') || st.phase !== 'seek') break;
        if (action.area >= rules.overlooked.minArea && !((action.speed || 0) >= rules.cat.stillSpeed)) { // a hider that is moving does not score
          var o = rules.overlooked, cen = Math.max(0, ((action.centre || 0) - o.deadZone) / (1 - o.deadZone)), cf = 1 - (1 - o.edgeFactor) * Math.min(1, cen);
          var df = (action.dist || 0) <= o.nearM ? 1 : Math.max(o.farFactor, 1 - (1 - o.farFactor) * (action.dist - o.nearM) / (o.farM - o.nearM));
          var pts = Math.max(1, Math.round(o.maxPerTick * cf * df));
          c.score += pts; ev.push({ type: 'score', cat: c.id, by: action.by, add: pts, score: c.score });
        }
        break;
      case 'disconnect':
        p = st.players[action.id]; if (!p) break;
        p.connected = false;
        if (p.team === 'cat' && !p.out) { p.out = true; ev.push({ type: 'out', cat: p.id }); }
        if (st.phase === 'seek') {
          if (catsAlive(st) === 0) end(st, 'dogs', 'all-found', rules, ev);
          else if (huntersWithAmmo(st) === 0) end(st, 'cats', 'no-ammo', rules, ev);
        }
        break;
      default: ev.push({ type: 'rejected', why: 'unknown-action' });
    }
    return { state: st, events: ev };
  }

  return { apply: apply, createState: createState, dogCountFor: dogCountFor, catsAlive: catsAlive, huntersWithAmmo: huntersWithAmmo, list: list, hunters: hunters };
});
