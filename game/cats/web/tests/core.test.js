// node tests/core.test.js — exercises the pure rules module against data/rules.json
const assert = require('assert');
const core = require('../src/core/rules.js');
const R = require('../data/rules.json');
let n = 0; const t = (name, fn) => { fn(); n++; console.log('ok  ' + name); };
const mk = (cats = 2, dogs = 1) => {
  const ps = []; for (let i = 0; i < cats; i++) ps.push({ id: 'c' + i, team: 'cat' }); for (let i = 0; i < dogs; i++) ps.push({ id: 'd' + i, team: 'dog' });
  let s = core.createState(ps, R); s = core.apply(s, { type: 'start' }, R).state; return s;
};
const run = (s, a) => core.apply(s, a, R);
const toSeek = s => run(s, { type: 'skip' }).state;
const types = r => r.events.map(e => e.type);

t('dog count table: <=5 -> 1, 6-9 -> 2, 10-14 -> 3', () => { assert.equal(core.dogCountFor(4, R), 1); assert.equal(core.dogCountFor(6, R), 2); assert.equal(core.dogCountFor(9, R), 2); assert.equal(core.dogCountFor(14, R), 3); });
t('roles are drawn when not preset', () => { const s = core.createState([1, 2, 3, 4, 5, 6, 7].map(i => ({ id: 'p' + i })), R, () => 0.3); assert.equal(core.list(s, 'dog').length, 2); assert.equal(core.list(s, 'cat').length, 5); });
t('start needs 2 players', () => { const s = core.createState([{ id: 'a', team: 'cat' }], R); assert.deepEqual(types(run(s, { type: 'start' })), ['rejected']); });
t('prep -> seek -> reveal by timers (end 1: time up, cats win)', () => {
  let s = mk(); assert.equal(s.phase, 'prep'); assert.equal(s.left, R.round.prepSec);
  let r = run(s, { type: 'tick', dt: R.round.prepSec }); assert.equal(r.state.phase, 'seek'); assert.equal(r.state.left, R.round.seekSec);
  r = run(r.state, { type: 'tick', dt: R.round.seekSec }); assert.equal(r.state.phase, 'reveal'); assert.equal(r.state.winner, 'cats'); assert.equal(r.state.reason, 'time');
  r = run(r.state, { type: 'tick', dt: R.round.revealSec }); assert.equal(r.state.phase, 'lobby');
});
t('apply is pure (input state untouched)', () => { const s = mk(); const j = JSON.stringify(s); run(s, { type: 'tick', dt: 5 }); assert.equal(JSON.stringify(s), j); });
t('vote skip works in prep and reveal only', () => { let s = mk(); s = toSeek(s); assert.equal(s.phase, 'seek'); assert.deepEqual(types(run(s, { type: 'skip' })), ['rejected']); });
t('miss costs one ball, hit gives one back', () => {
  let s = toSeek(mk()); let r = run(s, { type: 'shoot', dog: 'd0', now: 10, hit: null });
  assert.equal(r.state.players.d0.ammo, R.dog.startAmmo - 1);
  r = run(r.state, { type: 'shoot', dog: 'd0', now: 12, hit: 'c0' });
  assert.equal(r.state.players.d0.ammo, R.dog.startAmmo); assert.equal(r.state.players.c0.out, true); assert.ok(types(r).includes('hit'));
});
t('only one shot per 1.5 s', () => {
  let s = toSeek(mk()); let r = run(s, { type: 'shoot', dog: 'd0', now: 10, hit: null });
  const r2 = run(r.state, { type: 'shoot', dog: 'd0', now: 10 + R.dog.shotIntervalSec - 0.1, hit: null });
  assert.deepEqual(types(r2), ['rejected']); assert.equal(r2.state.players.d0.ammo, R.dog.startAmmo - 1);
  const r3 = run(r.state, { type: 'shoot', dog: 'd0', now: 10 + R.dog.shotIntervalSec, hit: null }); assert.equal(r3.state.players.d0.ammo, R.dog.startAmmo - 2);
});
t('missing a fleeing cat is free', () => { let s = toSeek(mk()); const r = run(s, { type: 'shoot', dog: 'd0', now: 5, hit: null, fleeing: true }); assert.equal(r.state.players.d0.ammo, R.dog.startAmmo); });
t('end 2: all dogs out of balls -> reveal, cats win at once', () => {
  let s = toSeek(mk(2, 2)), r;
  ['d0', 'd1'].forEach(d => { for (let i = 0; i < R.dog.startAmmo; i++) { r = run(s, { type: 'shoot', dog: d, now: 10 + i * 2, hit: null }); s = r.state; } });
  assert.equal(s.phase, 'reveal'); assert.equal(s.winner, 'cats'); assert.equal(s.reason, 'no-ammo');
});
t('low-ball warning fires at 1', () => { let s = toSeek(mk()), r; for (let i = 0; i < R.dog.startAmmo - 1; i++) { r = run(s, { type: 'shoot', dog: 'd0', now: i * 2, hit: null }); s = r.state; } assert.ok(types(r).includes('lowAmmo')); });
t('end 3: all cats found -> reveal, dogs win', () => {
  let s = toSeek(mk()); let r = run(s, { type: 'shoot', dog: 'd0', now: 1, hit: 'c0' }); assert.equal(r.state.phase, 'seek');
  r = run(r.state, { type: 'shoot', dog: 'd0', now: 3, hit: 'c1' }); assert.equal(r.state.phase, 'reveal'); assert.equal(r.state.winner, 'dogs'); assert.equal(r.state.reason, 'all-found');
});
t('last ball hitting the last cat: hit settles first, dogs win', () => {
  let s = toSeek(mk(1, 1)); for (let i = 0; i < R.dog.startAmmo - 1; i++) s = run(s, { type: 'shoot', dog: 'd0', now: i * 2, hit: null }).state;
  assert.equal(s.players.d0.ammo, 1); const r = run(s, { type: 'shoot', dog: 'd0', now: 100, hit: 'c0' });
  assert.equal(r.state.winner, 'dogs'); assert.equal(r.state.players.d0.ammo, 2);
});
t('hitting a decoy takes the real cat out', () => { let s = toSeek(mk()); const r = run(s, { type: 'shoot', dog: 'd0', now: 1, hit: 'c0', decoy: true }); assert.equal(r.state.players.c0.out, true); assert.equal(r.events.find(e => e.type === 'hit').decoy, true); });
t('overlooked score: 45 per tick dead centre and close, less toward the edge and with distance, 0 when occluded', () => {
  let s = toSeek(mk()); const one = (a) => { const r = run(s, Object.assign({ type: 'overlook', cat: 'c0', by: 'd0' }, a)); const e = r.events.find(e => e.type === 'score'); return e ? e.add : 0; };
  assert.equal(one({ area: 0.01, centre: 0, dist: 3 }), 45); assert.equal(one({ area: 0.01, centre: 0.08, dist: 3 }), 45);
  const edge = one({ area: 0.01, centre: 1, dist: 3 }), mid = one({ area: 0.01, centre: 0.5, dist: 3 }), far = one({ area: 0.01, centre: 0, dist: 30 });
  assert.ok(edge > 0 && edge <= 8, 'edge ' + edge); assert.ok(mid > edge && mid < 45); assert.ok(far < 45 && far >= 10, 'far ' + far);
  assert.equal(one({ area: 0, centre: 0, dist: 3 }), 0); assert.equal(one({ area: 0.01, centre: 0, dist: 3, speed: 1.2 }), 0, 'moving hiders do not score');
  let t = toSeek(mk()); for (let i = 0; i < 20; i++) t = run(t, { type: 'overlook', cat: 'c0', by: 'd0', area: 0.01, centre: 0, dist: 2 }).state; assert.equal(t.players.c0.score, 900);
});
t('scoreboard event every 30 s of seek', () => { let s = toSeek(mk()); const r = run(s, { type: 'tick', dt: R.overlooked.boardEverySec }); assert.ok(types(r).includes('board')); });
t('disconnect: cat counts as out; dog balls stop counting', () => {
  let s = toSeek(mk(2, 2)); s = run(s, { type: 'disconnect', id: 'c0' }).state; assert.equal(s.players.c0.out, true);
  for (let i = 0; i < R.dog.startAmmo; i++) s = run(s, { type: 'shoot', dog: 'd0', now: i * 2, hit: null }).state;
  assert.equal(s.phase, 'seek'); const r = run(s, { type: 'disconnect', id: 'd1' }); assert.equal(r.state.winner, 'cats');
});
t('numbers come from the json (changing it changes behaviour)', () => { const R2 = JSON.parse(JSON.stringify(R)); R2.dog.startAmmo = 2; R2.round.prepSec = 7; let s = core.createState([{ id: 'c', team: 'cat' }, { id: 'd', team: 'dog' }], R2); s = core.apply(s, { type: 'start' }, R2).state; assert.equal(s.left, 7); assert.equal(s.players.d.ammo, 2); });
t('vote to skip: bots always agree, every connected human must vote', () => {
  let s = core.createState([{ id: 'a', team: 'cat' }, { id: 'b', team: 'cat' }, { id: 'bot', team: 'dog', bot: true }], R); s = run(s, { type: 'start' }).state;
  let r = run(s, { type: 'vote', id: 'a' }); assert.equal(r.state.phase, 'prep'); assert.deepEqual(r.events[0], { type: 'votes', have: 1, need: 2 });
  r = run(r.state, { type: 'vote', id: 'b' }); assert.equal(r.state.phase, 'seek'); assert.deepEqual(types(run(r.state, { type: 'vote', id: 'a' })), ['rejected']);
});
t('unlimited ammo: misses cost nothing and the round cannot end on balls', () => {
  const R2 = JSON.parse(JSON.stringify(R)); R2.dog.unlimited = true; let s = core.createState([{ id: 'c', team: 'cat' }, { id: 'd', team: 'dog' }], R2); s = core.apply(s, { type: 'start' }, R2).state; s = core.apply(s, { type: 'skip' }, R2).state;
  for (let i = 0; i < 12; i++) s = core.apply(s, { type: 'shoot', dog: 'd', now: i * 2, hit: null }, R2).state; assert.equal(s.phase, 'seek'); assert.equal(s.players.d.ammo, R.dog.startAmmo);
});
t('infection: a found cat joins the dogs with fresh balls; last cat found ends it', () => {
  let s = core.createState([{ id: 'c0', team: 'cat' }, { id: 'c1', team: 'cat' }, { id: 'c2', team: 'cat' }, { id: 'd0', team: 'dog' }], R, null, 'infection'); s = run(s, { type: 'start' }).state; s = toSeek(s);
  let r = run(s, { type: 'shoot', dog: 'd0', now: 1, hit: 'c0' }); assert.ok(types(r).includes('infected')); assert.equal(r.state.players.c0.team, 'dog'); assert.equal(r.state.players.c0.ammo, R.dog.startAmmo); assert.equal(r.state.phase, 'seek');
  r = run(r.state, { type: 'shoot', dog: 'c0', now: 5, hit: 'c1' }); assert.equal(r.state.players.c1.team, 'dog'); assert.equal(core.catsAlive(r.state), 1);
  r = run(r.state, { type: 'shoot', dog: 'c1', now: 9, hit: 'c2' }); assert.equal(r.state.phase, 'reveal'); assert.equal(r.state.winner, 'dogs'); assert.equal(r.state.lastCat, 'c2');
});
t('infection: time up with a cat left -> cats win', () => {
  let s = core.createState([{ id: 'c0', team: 'cat' }, { id: 'c1', team: 'cat' }, { id: 'd0', team: 'dog' }], R, null, 'infection'); s = toSeek(run(s, { type: 'start' }).state);
  s = run(s, { type: 'shoot', dog: 'd0', now: 1, hit: 'c0' }).state; const r = run(s, { type: 'tick', dt: R.round.seekSec }); assert.equal(r.state.winner, 'cats');
});
t('double: everyone hides, then everyone hunts; first to find all the others wins', () => {
  let s = core.createState([{ id: 'a' }, { id: 'b' }, { id: 'c' }], R, null, 'double'); assert.equal(core.list(s, 'dog').length, 0); s = run(s, { type: 'start' }).state;
  assert.deepEqual(types(run(s, { type: 'shoot', dog: 'a', now: 0, hit: 'b' })), ['rejected']); s = toSeek(s);
  assert.equal(core.hunters(s).length, 3); assert.equal(s.players.a.ammo, R.dog.startAmmo);
  let r = run(s, { type: 'shoot', dog: 'a', now: 1, hit: 'a' }); assert.ok(types(r).includes('miss')); // own body does not count
  r = run(r.state, { type: 'shoot', dog: 'a', now: 3, hit: 'b' }); assert.equal(r.state.phase, 'seek'); assert.deepEqual(r.state.players.a.found, ['b']);
  let r2 = run(r.state, { type: 'shoot', dog: 'a', now: 5, hit: 'b' }); assert.ok(types(r2).includes('miss')); // already found by this hunter
  r2 = run(r.state, { type: 'shoot', dog: 'b', now: 5, hit: 'a' }); assert.deepEqual(r2.state.players.b.found, ['a']); // a found body can still be found by others
  r = run(r2.state, { type: 'shoot', dog: 'a', now: 7, hit: 'c' }); assert.equal(r.state.phase, 'reveal'); assert.equal(r.state.winner, 'a'); assert.equal(r.state.reason, 'double-all');
});
t('double: time up -> most finds wins', () => {
  let s = core.createState([{ id: 'a' }, { id: 'b' }, { id: 'c' }], R, null, 'double'); s = toSeek(run(s, { type: 'start' }).state);
  s = run(s, { type: 'shoot', dog: 'b', now: 1, hit: 'c' }).state; const r = run(s, { type: 'tick', dt: R.round.seekSec }); assert.equal(r.state.winner, 'b'); assert.equal(r.state.reason, 'time');
});
console.log(n + ' tests passed');
