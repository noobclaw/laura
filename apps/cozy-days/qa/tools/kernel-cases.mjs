// Claude QA: automated kernel-level test cases for Cozy Days.
// Usage: node qa/tools/kernel-cases.mjs [--seeds N] > qa/evidence/kernel-cases.json
import { readFile } from 'node:fs/promises';
import { SortingSession } from '../../src/session.js';
import { applyAmericanArt } from '../../src/art.js';
import { PlayerJournal } from '../../src/progress.js';
import { ratingFor, ACCOUNT_LIMITS } from '../../src/policies.js';
import { balanceStage, campaignProfile, CAMPAIGN_EDITION, TOOL_UNLOCKS } from '../../src/campaign.js';
import { SHOP_PRODUCTS, productPresentation } from '../../src/shop.js';

const root = new URL('../../', import.meta.url);
const args = process.argv.slice(2);
const SEEDS = Number(args[args.indexOf('--seeds') + 1]) || 5;
const RANDOM_RUNS = Number(args[args.indexOf('--random') + 1]) || 20;

const results = [];
const record = (id, status, detail) => results.push({ id, status, detail });
const check = async (id, fn) => {
  try {
    const out = await fn();
    record(id, out.status, out.detail);
  } catch (error) {
    record(id, 'fail', `uncaught: ${error?.stack?.split('\n').slice(0, 2).join(' | ')}`);
  }
};

async function rawStage(n) {
  return JSON.parse(await readFile(new URL(`data/stage-${String(n).padStart(3, '0')}.json`, root), 'utf8'));
}
async function campaignStage(n) {
  // Same pipeline as the shipped game: campaign balance, then the new art's shapes.
  return applyAmericanArt(balanceStage(await rawStage(n), n, CAMPAIGN_EDITION));
}
function rng(seed) {
  let s = seed >>> 0 || 1;
  return () => ((s = Math.imul(s ^ (s >>> 15), 2246822519) ^ Math.imul(s ^ (s >>> 13), 3266489917)) >>> 0) / 4294967296;
}
function hashState(round) {
  return JSON.stringify(round.inspect());
}

// ---------- bots ----------
function choose(round, payload, policy, random) {
  const state = round.inspect();
  const free = state.board.filter(id => !round.isObstructed(id));
  if (!free.length) return null;
  if (policy === 'random') return free[Math.floor(random() * free.length)];
  const need = new Map();
  for (const bay of state.bays) if (bay.available && bay.group !== -1 && bay.filled < bay.required) need.set(bay.group, bay.required - bay.filled);
  const deliver = free.filter(id => need.has(round.tokenInfo(id).group));
  if (deliver.length) return deliver[Math.floor(random() * Math.min(deliver.length, 3))] ?? deliver[0];
  // Stash the item whose category arrives soonest in the remaining schedule.
  const upcoming = payload.stage.shipments.slice(state.cursor).map(s => s.group);
  const trayGroups = state.tray.filter(c => c.tokenId !== null).map(c => round.tokenInfo(c.tokenId).group);
  const score = id => {
    const g = round.tokenInfo(id).group;
    const at = upcoming.indexOf(g);
    const pending = trayGroups.filter(x => x === g).length;
    return (at < 0 ? 999 : at) - pending * 0.5;
  };
  free.sort((a, b) => score(a) - score(b) || b - a);
  return free[0];
}

function play(payload, policy, seed) {
  const random = rng(seed);
  const round = new SortingSession(payload.stage, payload.forms, {});
  let steps = 0, trayPeak = 0, completions = [];
  while (round.inspect().phase === 'live' && steps < 3000) {
    const id = choose(round, payload, policy, random);
    if (id === null) break;
    round.dispatch({ kind: 'collect', tokenId: id });
    round.dispatch({ kind: 'advance', seconds: 1.2 });
    steps++;
    for (const s of round.takeSignals()) if (s.kind === 'bayCompleted') completions.push(steps);
    trayPeak = Math.max(trayPeak, round.inspect().tray.filter(c => c.tokenId !== null).length);
  }
  const phase = round.inspect().phase;
  return { win: phase === 'done', phase, steps, trayPeak, completions };
}

// ---------- rule cases ----------
const s1 = await campaignStage(1);

await check('TC-RULE-01', () => {
  const r = new SortingSession(s1.stage, s1.forms, {});
  const st = r.inspect();
  const need = new Set(st.bays.filter(b => b.group !== -1).map(b => b.group));
  const id = st.board.find(t => !r.isObstructed(t) && need.has(r.tokenInfo(t).group));
  const before = st.board.length;
  r.dispatch({ kind: 'collect', tokenId: id });
  const sig = r.takeSignals().map(s => s.kind);
  const ok = r.inspect().board.length === before - 1 && sig.includes('boardDelivered');
  return { status: ok ? 'pass' : 'fail', detail: `board ${before}→${r.inspect().board.length}; signals ${sig.join(',')}` };
});

await check('TC-RULE-02', () => {
  const r = new SortingSession(s1.stage, s1.forms, {});
  const blocked = r.inspect().board.filter(t => r.isObstructed(t));
  let changed = 0;
  for (const id of blocked) {
    const h = JSON.stringify(r.inspect().board);
    r.dispatch({ kind: 'collect', tokenId: id });
    if (JSON.stringify(r.inspect().board) !== h) changed++;
  }
  return { status: blocked.length && !changed ? 'pass' : blocked.length ? 'fail' : 'n/a', detail: `${blocked.length} obstructed items tried, ${changed} collected anyway` };
});

await check('TC-RULE-03', () => {
  const r = new SortingSession(s1.stage, s1.forms, {});
  let guard = 0;
  while (r.inspect().phase === 'live' && guard++ < 200) {
    const st = r.inspect();
    const need = new Set(st.bays.filter(b => b.group !== -1).map(b => b.group));
    const id = st.board.find(t => !r.isObstructed(t) && !need.has(r.tokenInfo(t).group)) ?? st.board.find(t => !r.isObstructed(t));
    if (id === undefined) break;
    r.dispatch({ kind: 'collect', tokenId: id });
  }
  const st = r.inspect();
  const cap = st.tray.filter(c => c.available).length;
  return { status: cap === 5 ? 'pass' : 'fail', detail: `tray capacity ${cap}, phase ${st.phase}, occupied ${st.tray.filter(c => c.tokenId !== null).length}` };
});

await check('TC-RULE-05', () => {
  const r = new SortingSession(s1.stage, s1.forms, {});
  const h = hashState(r);
  const bad = [{ kind: 'collect', tokenId: 9999 }, { kind: 'collect', tokenId: -1 }, { kind: 'collect', tokenId: NaN }, { kind: 'collect', tokenId: '0' }, { kind: 'nope' }, null, {}];
  const errors = [];
  for (const a of bad) {
    try { r.dispatch(a); } catch (e) { errors.push(`${JSON.stringify(a)} → ${e.message}`); }
  }
  r.takeSignals();
  const same = hashState(r) === h;
  return { status: same && !errors.length ? 'pass' : same ? 'partial' : 'fail', detail: `state unchanged=${same}; thrown: ${errors.join('; ') || 'none'}` };
});

await check('TC-RULE-06', () => {
  const r = new SortingSession(s1.stage, s1.forms, {});
  const out = [];
  for (const v of [-5, NaN, Infinity, 1e12]) {
    try { r.dispatch({ kind: 'advance', seconds: v }); out.push(`${v}: ok seconds=${r.inspect().seconds}`); } catch (e) { out.push(`${v}: throws ${e.message}`); }
  }
  const sec = r.inspect().seconds;
  return { status: Number.isFinite(sec) && sec >= 0 ? 'pass' : 'fail', detail: out.join('; ') };
});

await check('TC-RULE-07', () => {
  let bad = 0;
  for (let seed = 1; seed <= 30; seed++) {
    const random = rng(seed);
    const r = new SortingSession(s1.stage, s1.forms, {});
    for (let i = 0; i < 50 && r.inspect().phase === 'live'; i++) {
      const id = choose(r, s1, 'random', random);
      if (id === null) break;
      r.dispatch({ kind: 'collect', tokenId: id });
      r.dispatch({ kind: 'advance', seconds: 0.7 });
    }
    const resumed = SortingSession.resume(s1.stage, s1.forms, r.save());
    if (hashState(resumed) !== hashState(r)) bad++;
  }
  return { status: bad ? 'fail' : 'pass', detail: `30 random games saved/resumed, ${bad} mismatches` };
});

await check('TC-RULE-08', async () => {
  const s2 = await campaignStage(2);
  const r = new SortingSession(s1.stage, s1.forms, {});
  try { SortingSession.resume(s2.stage, s2.forms, r.save()); return { status: 'fail', detail: 'resume accepted foreign stage' }; } catch (e) { return { status: 'pass', detail: `rejected: ${e.message}` }; }
});

await check('TC-RULE-10', () => {
  const r = new SortingSession(s1.stage, s1.forms, {});
  const snap = r.inspect();
  snap.board.length = 0; snap.phase = 'done';
  return { status: r.inspect().board.length > 0 && r.inspect().phase === 'live' ? 'pass' : 'fail', detail: 'mutating inspect() copy' };
});

// ---------- level cases + bots ----------
const levels = [];
for (let n = 1; n <= 160; n++) {
  const p = await campaignStage(n);
  const counts = new Map();
  for (const t of p.stage.specimens) counts.set(t.group, (counts.get(t.group) ?? 0) + 1);
  const needs = new Map();
  for (const s of p.stage.shipments) needs.set(s.group, (needs.get(s.group) ?? 0) + s.quantity);
  const satisfiable = [...needs].every(([g, q]) => (counts.get(g) ?? 0) >= q);
  const exact = [...needs].every(([g, q]) => (counts.get(g) ?? 0) === q) && [...counts.keys()].every(g => needs.has(g));
  const greedy = [];
  for (let seed = 1; seed <= SEEDS; seed++) greedy.push(play(p, 'greedy', seed * 7919 + n));
  const randomRuns = [];
  for (let seed = 1; seed <= RANDOM_RUNS; seed++) randomRuns.push(play(p, 'random', seed * 104729 + n));
  const gw = greedy.filter(x => x.win).length, rw = randomRuns.filter(x => x.win).length;
  const winSteps = greedy.filter(x => x.win).map(x => x.steps);
  const gaps = greedy.filter(x => x.win).flatMap(x => x.completions.map((c, i, a) => (c - (a[i - 1] ?? 0)) * 1.2));
  levels.push({
    n, pace: campaignProfile(n).pace, items: p.stage.specimens.length, categories: needs.size, requests: p.stage.shipments.length,
    satisfiable, exact, rating: p.stage.rating ?? null,
    greedyWin: gw / SEEDS, randomWin: rw / RANDOM_RUNS,
    medianSteps: winSteps.sort((a, b) => a - b)[Math.floor(winSteps.length / 2)] ?? null,
    maxRewardGapSec: gaps.length ? Math.max(...gaps) : null,
    trayPeak: Math.max(...greedy.map(x => x.trayPeak))
  });
}

record('TC-LVL-01', levels.every(l => l.items > 0 && l.satisfiable) ? 'pass' : 'fail',
  `${levels.filter(l => l.satisfiable).length}/160 satisfiable; unsatisfiable: ${levels.filter(l => !l.satisfiable).map(l => l.n).join(',') || 'none'}`);
record('TC-LVL-02', [18, 28, 36].every((c, i) => levels[i].items === c) ? 'pass' : 'fail', `first three: ${levels.slice(0, 3).map(l => l.items).join('/')}`);
{
  const teach = levels.filter(l => l.n <= 7 || l.n % 20 === 0 || l.n % 20 === 1);
  const teachFail = teach.filter(l => l.greedyWin === 0).map(l => l.n);
  const unsolved = levels.filter(l => l.greedyWin === 0).map(l => l.n);
  record('TC-LVL-03', teachFail.length ? 'fail' : unsolved.length ? 'partial' : 'pass',
    `greedy bot (no tools, ${SEEDS} seeds): solved ${160 - unsolved.length}/160; unsolved: ${unsolved.join(',') || 'none'}; tutorial/chapter-edge unsolved: ${teachFail.join(',') || 'none'}`);
}
{
  const g = levels.reduce((a, l) => a + l.greedyWin, 0) / 160, r = levels.reduce((a, l) => a + l.randomWin, 0) / 160;
  record('TC-LVL-04', g - r >= 0.2 ? 'pass' : 'fail', `mean win: greedy ${(g * 100).toFixed(1)}%, random ${(r * 100).toFixed(1)}%, gap ${((g - r) * 100).toFixed(1)} pts`);
}
{
  const wrong = levels.slice(0, 20).filter(l => !l.rating || l.rating.fast !== Math.max(60, Math.ceil(l.items * 3.5)) || l.rating.medium !== Math.max(100, Math.ceil(l.items * 5.5)));
  record('TC-LVL-05', wrong.length ? 'fail' : 'pass', `levels 1–20 rating mismatches: ${wrong.map(l => l.n).join(',') || 'none'}`);
}
{
  const l = levels[40];
  const r3 = ratingFor(l.items * 3, l.items), r2 = ratingFor(l.items * 5, l.items), r1 = ratingFor(l.items * 5 + 1, l.items);
  record('TC-LVL-06', r3 === 3 && r2 === 2 && r1 === 1 && levels.slice(20).every(x => x.rating === null) ? 'pass' : 'fail', `stage 41 (${l.items} items): ${r3}/${r2}/${r1}; levels 21–160 carry no fixed rating: ${levels.slice(20).every(x => x.rating === null)}`);
}
{
  const out = levels.filter(l => l.medianSteps && (l.medianSteps * 1.2 < 60 || l.medianSteps * 1.2 > 300)).map(l => `${l.n}(${Math.round(l.medianSteps * 1.2)}s)`);
  record('TC-LVL-07', out.length ? 'partial' : 'pass', `estimated at 1.2 s/pick; outside 1–5 min: ${out.join(', ') || 'none'}`);
}
{
  const cliffs = [];
  for (let i = 1; i < 160; i++) if (levels[i].items > levels[i - 1].items * 2 || levels[i].items * 2 < levels[i - 1].items) cliffs.push(`${levels[i - 1].n}→${levels[i].n} (${levels[i - 1].items}→${levels[i].items})`);
  const breathers = levels.filter(l => l.pace === 'breather').map(l => `${l.n}:${l.items} vs ${levels[l.n - 2].items}`);
  record('TC-LVL-08', cliffs.length ? 'partial' : 'pass', `item-count cliffs (>2×): ${cliffs.join('; ') || 'none'}; breathers vs previous: ${breathers.join(', ')}`);
}
{
  const gaps = levels.filter(l => l.maxRewardGapSec !== null).map(l => l.maxRewardGapSec);
  const over = levels.filter(l => l.maxRewardGapSec > 30).map(l => `${l.n}(${Math.round(l.maxRewardGapSec)}s)`);
  record('TC-FUN-01', over.length > 16 ? 'fail' : over.length ? 'partial' : 'pass', `longest gap between completed boxes (1.2 s/pick): median of levels ${Math.round(gaps.sort((a, b) => a - b)[Math.floor(gaps.length / 2)])}s; levels over 30 s: ${over.length} → ${over.slice(0, 25).join(', ')}${over.length > 25 ? ' …' : ''}`);
}

// ---------- economy / journal ----------
const mkClock = start => { let t = start; const c = () => t; c.set = v => { t = v; }; c.add = ms => { t += ms; }; return c; };

await check('TC-ECO-01', async () => {
  const clock = mkClock(Date.UTC(2026, 10, 28, 12));
  const j = new PlayerJournal({ clock });
  const a = j.powerStatus();
  await j.openRound(1, 'a1', 'bonus1');
  clock.add(1800 * 1000);
  const b = j.powerStatus();
  clock.add(10 * 3600 * 1000);
  const c = j.powerStatus();
  return { status: a.amount === 5 && b.amount === 5 && c.amount === 5 ? 'pass' : 'fail', detail: `start ${a.amount}; after entry+30min ${b.amount}; +10h ${c.amount}/${c.capacity}` };
});
await check('TC-ECO-02', async () => {
  const j = new PlayerJournal({ clock: mkClock(0) });
  await j.openRound(1, 'a', 'bonus1');
  return { status: j.powerStatus().amount === 4 ? 'pass' : 'fail', detail: `after entry: ${j.powerStatus().amount}` };
});
await check('TC-ECO-03', async () => {
  const j = new PlayerJournal({ clock: mkClock(0) });
  await j.openRound(1, 'a', 'bonus1');
  const first = await j.completeRound(1, 30, 18, { fast: 60, medium: 100 });
  const afterFirst = j.powerStatus().amount;
  await j.openRound(1, 'b', 'bonus1');
  const mid = j.powerStatus().amount;
  const second = await j.completeRound(1, 30, 18, { fast: 60, medium: 100 });
  const afterSecond = j.powerStatus().amount;
  return {
    status: afterSecond === mid + 1 ? 'pass' : 'fail',
    detail: `first clear refund ${first.energy ?? 0} (power ${afterFirst}); replay same 3★: before win ${mid}, after win ${afterSecond}, refund ${second.energy ?? 0}. README says a win refunds the entry point (fixed in C-07; before the fix the kernel only refunded when stars improved).`
  };
});
await check('TC-ECO-05', async () => {
  const j = new PlayerJournal({ clock: mkClock(0) });
  for (let i = 0; i < 5; i++) { await j.openRound(1, `x${i}`, 'bonus1'); }
  const r = await j.openRound(1, 'x6', 'bonus1');
  return { status: r === 'energy' ? 'pass' : 'fail', detail: `6th entry result: ${r}; refillIn ${j.powerStatus().refillIn}s` };
});
await check('TC-ECO-08', () => {
  const ok = TOOL_UNLOCKS.scan === 3 && TOOL_UNLOCKS.return === 4 && TOOL_UNLOCKS.sweep === 5 && TOOL_UNLOCKS.rub === 7;
  return { status: ok ? 'pass' : 'fail', detail: JSON.stringify(TOOL_UNLOCKS) };
});

await check('TC-SAVE-02', () => {
  const base = new PlayerJournal({ clock: mkClock(0) }).inspect();
  const variants = { missingPower: { ...base, power: undefined }, nanPower: { ...base, power: NaN }, negFrontier: { ...base, frontier: -1 }, badCapacity: { ...base, capacity: 7 }, ratingsString: { ...base, ratings: 'x' }, creditsNegative: { ...base, credits: { scan: -3 } } };
  const out = [];
  let accepted = [];
  for (const [k, rec] of Object.entries(variants)) {
    try { new PlayerJournal({ clock: mkClock(0), record: rec }); out.push(`${k}: accepted`); accepted.push(k); } catch { out.push(`${k}: rejected`); }
  }
  return { status: accepted.length ? 'partial' : 'pass', detail: out.join('; ') };
});
await check('TC-SAVE-03', async () => {
  let fail = true;
  const j = new PlayerJournal({ clock: mkClock(0), persist: async () => { if (fail) throw new Error('disk full'); } });
  let threw = false;
  try { await j.openRound(1, 'a', 'bonus1'); } catch { threw = true; }
  const unchanged = j.powerStatus().amount === 5 && j.inspect().attempt === null;
  return { status: threw && unchanged ? 'pass' : 'fail', detail: `write rejected=${threw}; state unchanged=${unchanged}` };
});
await check('TC-CHEAT-01', async () => {
  const clock = mkClock(Date.UTC(2026, 0, 1));
  const j = new PlayerJournal({ clock });
  for (let i = 0; i < 5; i++) await j.openRound(1, `c${i}`, 'bonus1');
  clock.add(10 * 3600 * 1000);
  const fwd = j.powerStatus().amount;
  await j.openRound(1, 'd', 'bonus1');
  clock.add(-10 * 3600 * 1000);
  const back = j.powerStatus();
  return { status: fwd === 5 && back.amount >= 0 && back.refillIn <= 1800 ? 'pass' : 'fail', detail: `+10h → ${fwd}; after entry and −10h → amount ${back.amount}, refillIn ${back.refillIn}s` };
});
await check('TC-CHEAT-02', async () => {
  const clock = mkClock(Date.UTC(2026, 0, 2));
  const j = new PlayerJournal({ clock });
  for (let i = 0; i < 3; i++) await j.openRound(1, `c${i}`, 'bonus1');
  clock.add(-86400 * 1000);
  const p = j.powerStatus();
  return { status: p.amount === 2 && p.refillIn <= 1800 && p.refillIn > 0 ? 'pass' : 'fail', detail: `clock −1 day: amount ${p.amount}, refillIn ${p.refillIn}s (should stay ≤1800)` };
});
await check('TC-CHEAT-03', async () => {
  const j = new PlayerJournal({ clock: mkClock(0) });
  const a = await j.grantReceipt('r-1', 'scan'), b = await j.grantReceipt('r-1', 'scan');
  return { status: a === 'granted' && b === 'duplicate' && j.inspect().credits.scan === 1 ? 'pass' : 'fail', detail: `${a}/${b}, scan credits ${j.inspect().credits.scan}` };
});
await check('TC-MON-04', () => {
  const store = new Map([['cozy.toolbox.welcome', { displayPrice: 'NT$30', available: true }]]);
  const p = productPresentation(SHOP_PRODUCTS[0], store), q = productPresentation(SHOP_PRODUCTS[1], null);
  return { status: p.displayPrice === 'NT$30' && p.purchasable && q.displayPrice === null && !q.purchasable ? 'pass' : 'fail', detail: `with storefront: ${p.displayPrice}/${p.purchasable}; without: ${q.displayPrice}/${q.purchasable}` };
});
// 2026-11-28 user decision: first edition has no ads, so there must be no remove-ads product (no-ads-scan.mjs covers the code).
record('TC-MON-05', !SHOP_PRODUCTS.some(p => /noads|no-ads|remove.?ads/i.test(p.id) || /ads?$/i.test(p.kind)) ? 'pass' : 'fail', `products: ${SHOP_PRODUCTS.map(p => p.id).join(', ')} — no remove-ads product (none expected: no ads in this edition)`);
record('TC-MON-07', 'n/a', 'no random loot boxes in SHOP_PRODUCTS; album photos are deterministic (see AUDIT)');

// ---------- 30-day economy simulation (non-paying, no ads) ----------
{
  const clock = mkClock(Date.UTC(2026, 11, 1, 8));
  const j = new PlayerJournal({ clock });
  const sessions = [8, 13, 20];
  const days = [];
  let seed = 1, chapterDay = null;
  for (let day = 1; day <= 30; day++) {
    let attempts = 0, wins = 0, blocked = 0;
    for (const hour of sessions) {
      clock.set(Date.UTC(2026, 11, day, hour));
      for (let k = 0; k < 12; k++) {
        const frontier = j.inspect().frontier;
        if (frontier > 160) break;
        const n = Math.min(frontier, 160);
        const r = await j.openRound(n, `d${day}h${hour}k${k}`, 'bonus1');
        if (r !== 'ok') { blocked++; break; }
        attempts++;
        const lv = levels[n - 1];
        const winP = Math.max(0.15, lv.greedyWin * 0.85);
        if (rng(seed++)() < winP) {
          const secs = (lv.medianSteps ?? lv.items) * 1.2;
          await j.completeRound(n, secs, lv.items, lv.rating ?? 'scaled');
          wins++;
        } else {
          await j.checkpointRound(`d${day}h${hour}k${k}`, { model: { phase: 'lost' } });
          await j.closeLostRound(`d${day}h${hour}k${k}`);
        }
        clock.add(Math.round((lv.medianSteps ?? lv.items) * 1.2 * 1000));
      }
    }
    const st = j.inspect();
    if (chapterDay === null && st.frontier > 20) chapterDay = day;
    days.push({ day, frontier: st.frontier, attempts, wins, power: j.powerStatus().amount, sessionsBlocked: blocked });
  }
  const stuck = days.filter(d => d.attempts === 0).map(d => d.day);
  record('TC-ECO-06', stuck.length ? 'fail' : 'pass', `model: 3 sessions/day, win chance = max(15%, 0.85×greedy bot rate); no tools, no ads, no events. Day 30 frontier ${days.at(-1).frontier}; chapter 1 (stage 20) cleared on day ${chapterDay ?? '>30'}; days with zero attempts: ${stuck.join(',') || 'none'}; avg attempts/day ${(days.reduce((a, d) => a + d.attempts, 0) / 30).toFixed(1)}`);
  results.push({ id: 'ECO-SIM-TABLE', status: 'info', detail: days });
}
record('TC-ECO-07', 'not-evaluated', 'rewarded ads are not integrated');

console.log(JSON.stringify({ seeds: SEEDS, randomRuns: RANDOM_RUNS, results, levels }, null, 1));
