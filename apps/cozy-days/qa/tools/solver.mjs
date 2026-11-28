// Claude QA: beam-search solver to test whether a stage is clearable without tools.
// Usage: node qa/tools/solver.mjs 21 30 60 ... [--beam 6] [--branch 10]
import { readFile } from 'node:fs/promises';
import { SortingSession } from '../../src/session.js';
import { applyAmericanArt } from '../../src/art.js';
import { balanceStage, CAMPAIGN_EDITION } from '../../src/campaign.js';

const argv = process.argv.slice(2);
const opt = (name, fallback) => (argv.includes(name) ? Number(argv[argv.indexOf(name) + 1]) : fallback);
const BEAM = opt('--beam', 6), BRANCH = opt('--branch', 10);
const EXPAND = argv.includes('--expand');
const stages = argv.filter((a, i) => /^\d+$/.test(a) && !['--beam', '--branch'].includes(argv[i - 1])).map(Number);
const root = new URL('../../', import.meta.url);

async function load(n) {
  const raw = JSON.parse(await readFile(new URL(`data/stage-${String(n).padStart(3, '0')}.json`, root), 'utf8'));
  return applyAmericanArt(balanceStage(raw, n, CAMPAIGN_EDITION));
}
const needOf = r => {
  const m = new Map();
  for (const b of r.inspect().bays) if (b.available && b.group !== -1 && b.filled < b.required) m.set(b.group, b.required - b.filled);
  return m;
};
// Deliver every reachable needed item until none is left; returns picks made.
function drain(r) {
  let picks = 0;
  for (;;) {
    if (r.inspect().phase !== 'live') return picks;
    const need = needOf(r);
    const id = r.inspect().board.find(t => !r.isObstructed(t) && need.has(r.tokenInfo(t).group));
    if (id === undefined) return picks;
    r.dispatch({ kind: 'collect', tokenId: id });
    picks++;
  }
}
const score = r => {
  const s = r.inspect();
  if (s.phase === 'done') return 1e9;
  if (s.phase === 'lost') return -1e9;
  const tray = s.tray.filter(c => c.tokenId !== null).length;
  const delivered = s.bays.reduce((a, b) => a + b.filled, 0) + s.cursor * 100;
  const free = s.board.filter(t => !r.isObstructed(t)).length;
  return delivered - tray * 40 + free;
};

async function solve(n) {
  const p = await load(n);
  const clone = r => SortingSession.resume(p.stage, p.forms, r.save());
  let start = new SortingSession(p.stage, p.forms, {});
  if (EXPAND) { start.dispatch({ kind: 'expandBay' }); start.dispatch({ kind: 'expandTray' }); start.dispatch({ kind: 'expandTray' }); }
  let picks = drain(start);
  let beam = [{ r: start, picks, stashes: 0 }];
  let expansions = 0;
  const t0 = performance.now();
  while (beam.length) {
    const done = beam.find(b => b.r.inspect().phase === 'done');
    if (done) return { n, items: p.stage.specimens.length, solved: true, picks: done.picks, stashes: done.stashes, expansions, ms: Math.round(performance.now() - t0) };
    const next = [];
    for (const node of beam) {
      const s = node.r.inspect();
      if (s.phase !== 'live') continue;
      const upcoming = p.stage.shipments.slice(s.cursor).map(x => x.group);
      const free = s.board.filter(t => !node.r.isObstructed(t));
      free.sort((a, b) => {
        const ga = upcoming.indexOf(node.r.tokenInfo(a).group), gb = upcoming.indexOf(node.r.tokenInfo(b).group);
        return (ga < 0 ? 999 : ga) - (gb < 0 ? 999 : gb) || b - a;
      });
      for (const id of free.slice(0, BRANCH)) {
        const c = clone(node.r);
        c.dispatch({ kind: 'collect', tokenId: id });
        const more = drain(c);
        expansions++;
        next.push({ r: c, picks: node.picks + 1 + more, stashes: node.stashes + 1, s: score(c) });
      }
    }
    const seen = new Set();
    beam = next.filter(x => x.s > -1e9).sort((a, b) => b.s - a.s).filter(x => {
      const k = JSON.stringify(x.r.inspect().board.length) + JSON.stringify(x.r.inspect().tray);
      if (seen.has(k)) return false;
      seen.add(k);
      return true;
    }).slice(0, BEAM);
    if (performance.now() - t0 > 240000) return { n, items: p.stage.specimens.length, solved: false, reason: 'timeout', expansions };
  }
  return { n, items: p.stage.specimens.length, solved: false, reason: 'every branch lost', expansions, ms: Math.round(performance.now() - t0) };
}

const out = [];
for (const n of stages) {
  const r = await solve(n);
  out.push(r);
  console.error(JSON.stringify(r));
}
console.log(JSON.stringify({ beam: BEAM, branch: BRANCH, expand: EXPAND, results: out }, null, 1));
