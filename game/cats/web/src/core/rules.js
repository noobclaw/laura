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
  function createState(players, rules, rnd) {
    rnd = rnd || Math.random;
    var st = { phase: 'lobby', left: 0, elapsed: 0, seekElapsed: 0, winner: null, reason: null, players: {}, order: [], boardAt: 0 };
    var free = players.filter(function (p) { return !p.team; }), dogs = dogCountFor(players.length, rules) - players.filter(function (p) { return p.team === 'dog'; }).length;
    free = free.slice();
    for (var i = free.length - 1; i > 0; i--) { var j = Math.floor(rnd() * (i + 1)), t = free[i]; free[i] = free[j]; free[j] = t; }
    players.forEach(function (p) {
      var team = p.team || (free.indexOf(p) < dogs ? 'dog' : 'cat');
      st.players[p.id] = { id: p.id, team: team, out: false, connected: true, balls: team === 'dog' ? rules.dog.startBalls : 0, lastShot: -1e9, score: 0, hits: 0, misses: 0, decoys: 0 };
      st.order.push(p.id);
    });
    return st;
  }
  function list(st, team) { return st.order.map(function (id) { return st.players[id]; }).filter(function (p) { return p.team === team; }); }
  function catsAlive(st) { return list(st, 'cat').filter(function (p) { return !p.out && p.connected; }).length; }
  function dogsWithBalls(st) { return list(st, 'dog').filter(function (p) { return p.connected && p.balls > 0; }).length; }

  function toPhase(st, phase, rules, ev) {
    st.phase = phase; st.elapsed = 0;
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
          else if (st.phase === 'seek') end(st, catsAlive(st) > 0 ? 'cats' : 'dogs', 'time', rules, ev);
          else if (st.phase === 'reveal') toPhase(st, 'lobby', rules, ev);
        }
        break;
      case 'shoot': // { dog, now, hit: catId|null, fleeing: bool (target speed above dog.fleeingSpeed), decoy: bool }
        p = st.players[action.dog];
        if (!p || p.team !== 'dog' || st.phase !== 'seek') { ev.push({ type: 'rejected', why: 'cannot-shoot' }); break; }
        if (p.balls <= 0) { ev.push({ type: 'rejected', why: 'no-balls' }); break; }
        if (action.now - p.lastShot < rules.dog.shotIntervalSec - 1e-9) { ev.push({ type: 'rejected', why: 'cooldown' }); break; }
        p.lastShot = action.now;
        c = action.hit != null ? st.players[action.hit] : null;
        ev.push({ type: 'shot', dog: p.id });
        if (c && c.team === 'cat' && !c.out) {
          c.out = true; p.balls += rules.dog.hitDelta; p.hits++;
          ev.push({ type: 'hit', dog: p.id, cat: c.id, decoy: !!action.decoy, balls: p.balls });
          ev.push({ type: 'out', cat: c.id });
          if (catsAlive(st) === 0) end(st, 'dogs', 'all-found', rules, ev);
        } else {
          p.misses++;
          if (!action.fleeing) p.balls += rules.dog.missDelta; // a shot at a running cat that misses costs nothing
          ev.push({ type: 'miss', dog: p.id, balls: p.balls, free: !!action.fleeing });
          if (p.balls === rules.dog.lowBallWarn) ev.push({ type: 'lowBalls', dog: p.id });
          if (dogsWithBalls(st) === 0) end(st, 'cats', 'no-balls', rules, ev);
        }
        break;
      case 'overlook': // sampled every rules.overlooked.checkEverySec: { cat, area (0..1 of the dog's screen), speed }
        c = st.players[action.cat];
        if (!c || c.out || st.phase !== 'seek') break;
        if (action.speed < rules.cat.stillSpeed && action.area >= rules.overlooked.minArea) {
          var pts = Math.round(rules.overlooked.coef * Math.sqrt(action.area * 100));
          c.score += pts; ev.push({ type: 'score', cat: c.id, add: pts, score: c.score });
        }
        break;
      case 'disconnect':
        p = st.players[action.id]; if (!p) break;
        p.connected = false;
        if (p.team === 'cat' && !p.out) { p.out = true; ev.push({ type: 'out', cat: p.id }); }
        if (st.phase === 'seek') {
          if (catsAlive(st) === 0) end(st, 'dogs', 'all-found', rules, ev);
          else if (dogsWithBalls(st) === 0) end(st, 'cats', 'no-balls', rules, ev);
        }
        break;
      default: ev.push({ type: 'rejected', why: 'unknown-action' });
    }
    return { state: st, events: ev };
  }

  return { apply: apply, createState: createState, dogCountFor: dogCountFor, catsAlive: catsAlive, dogsWithBalls: dogsWithBalls, list: list };
});
