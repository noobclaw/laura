// Claude QA round 1b: kernel cases left "not evaluated" in round 1.
import { readFile, writeFile } from 'node:fs/promises';
import { execSync } from 'node:child_process';
import { SortingSession } from '../../src/session.js';
import { applyAmericanArt } from '../../src/art.js';
import { balanceStage, CAMPAIGN_EDITION, isNeighborhood } from '../../src/campaign.js';
import { FestivalBook } from '../../src/festivals.js';
import { Playthrough } from '../../src/playthrough.js';
import { requestLabel } from '../../src/requests.js';
const root = new URL('../../', import.meta.url);
const out = {};
const note = (id, status, detail) => { out[id] = { status, detail }; console.error(id, status, JSON.stringify(detail).slice(0, 300)); };
const raw = async n => JSON.parse(await readFile(new URL(`data/stage-${String(n).padStart(3, '0')}.json`, root), 'utf8'));
const content = async (n, { edition = CAMPAIGN_EDITION } = {}) => applyAmericanArt(isNeighborhood(edition) ? balanceStage(await raw(n), n, edition) : await raw(n));

// RULE-09: a direct hit is never reassigned by the touch radius.
{
  const p = await content(6), r = new SortingSession(p.stage, p.forms, {});
  let checked = 0, moved = [];
  for (const id of r.inspect().board) {
    const at = r.tokenInfo(id).at;
    const exact = r.locate(at);
    if (exact === null) continue;
    checked++;
    const assisted = r.locate(at, 12, 'visible'); // same arguments as the shipped pointer handler
    if (assisted !== exact) moved.push({ point: id, exact, assisted });
  }
  note('TC-RULE-09', moved.length ? 'fail' : 'pass', { preference: 'visible', stage: 6, directHitsChecked: checked, reassigned: moved.slice(0, 5) });
}

// ECO-09: free scan highlights 1 item, a paid scan 3.
{
  const p = await content(3);
  const run = quantity => {
    const r = new SortingSession(p.stage, p.forms, {});
    r.dispatch({ kind: 'scanGrant', quantity });
    let activations = 0;
    for (let i = 0; i < 6; i++) {
      const res = r.dispatch({ kind: 'scanActivate' });
      if (res !== 'activated') break;
      activations++;
      r.dispatch({ kind: 'collect', tokenId: r.inspect().scanTokens[0] });
    }
    return activations;
  };
  const free = run(1), paid = run(3);
  note('TC-ECO-09', free === 1 && paid === 3 ? 'pass' : 'fail', { freeActivations: free, paidActivations: paid });
}

// LVL-09: no stage asks for two different categories with the same name.
{
  const bad = [];
  for (let n = 1; n <= 160; n++) {
    const p = await content(n);
    const byName = new Map();
    for (const s of p.stage.shipments) {
      const name = requestLabel(s.group, 'en');
      if (!byName.has(name)) byName.set(name, new Set());
      byName.get(name).add(s.group);
    }
    for (const [name, groups] of byName) if (groups.size > 1) bad.push({ stage: n, name, groups: [...groups] });
  }
  note('TC-LVL-09', bad.length ? 'fail' : 'pass', { duplicates: bad.slice(0, 10), count: bad.length });
}

// ECO-10 and CHEAT-05: daily sprint and weekly league settle and pay out once.
{
  let now = Date.UTC(2026, 11, 7, 15); // a Monday afternoon UTC
  const clock = () => now;
  const awarded = [];
  const book = new FestivalBook({ clock, zone: 'America/Los_Angeles', award: async (key, q) => { awarded.push([key, q]); return q; } });
  const entered = book.enterSprint(12);
  for (let i = 0; i < 30; i++) { now += 20000; book.addShipment(12); }
  await book.settled();
  now += 3 * 3600 * 1000;
  const status = book.sprintStatus();
  const first = await book.claimSprint(), second = await book.claimSprint();
  const [c1, c2] = await Promise.all([book.claimCheckpoint(0), book.claimCheckpoint(0)]);
  for (let i = 0; i < 160; i++) { now += 1000; book.addShipment(12); }
  const cp = await book.claimCheckpoint(0), cpAgain = await book.claimCheckpoint(0);
  note('TC-ECO-10', entered && status?.final && first ? 'pass' : 'fail', { entered: !!entered, final: status?.final, position: status?.position, reward: status?.reward, claim: first, seasonScore: book.inspect().season?.score, checkpoint150: cp });
  note('TC-CHEAT-05', second === null && cpAgain === null && [c1, c2].filter(Boolean).length <= 1 ? 'pass' : 'fail', { secondSprintClaim: second, secondCheckpointClaim: cpAgain, concurrentEarlyClaims: [c1, c2], awards: awarded });
}

// Time zone of daily boundaries in a fresh save.
{
  const pt = await new Playthrough({ loadStage: content, contentEdition: CAMPAIGN_EDITION }).initialize();
  const snap = pt.inspect();
  note('TC-ZONE-01', snap.zone === 'Asia/Shanghai' ? 'fail' : 'pass', { freshSaveZone: snap.zone, eventsZone: snap.events?.zone, note: 'play.js does not pass zone; Playthrough defaults to Asia/Shanghai' });
}

// SAVE-05: a round started in the classic edition resumes with its own layout.
{
  let saved;
  const a = await new Playthrough({ loadStage: content, contentEdition: 'classic', persist: async s => { saved = s; } }).initialize();
  await a.start(1);
  const classicCount = a.payload.stage.specimens.length;
  const b = await new Playthrough({ record: saved, loadStage: content, contentEdition: CAMPAIGN_EDITION }).initialize();
  const resumed = b.payload?.stage.specimens.length;
  await b.start(1, { restart: true });
  const restarted = b.payload.stage.specimens.length;
  note('TC-SAVE-05', resumed === classicCount && restarted === 18 ? 'pass' : 'fail', { classicRoundItems: classicCount, resumedItems: resumed, afterRestartItems: restarted });
}

// I18N-04: UI text literals outside the string table.
{
  const hits = execSync(`grep -nE "['\\\`][^'\\\`]*[\\u4e00-\\u9fff][^'\\\`]*['\\\`]" examples/play.js examples/feedback.js web/scenes.jsx || true`, { cwd: new URL('../../', import.meta.url).pathname }).toString().split('\n').filter(Boolean);
  const english = execSync(`grep -nE "(textContent|aria-label|setAttribute\\('aria-label'), ?['\\\`][A-Z][a-z]+ [a-z]" examples/play.js web/scenes.jsx || true`, { cwd: new URL('../../', import.meta.url).pathname }).toString().split('\n').filter(Boolean);
  note('TC-I18N-04', hits.length + english.length ? 'partial' : 'pass', { chineseLiterals: hits.slice(0, 8), englishLiterals: english.slice(0, 8) });
}
await writeFile(new URL('../evidence/remaining-kernel.json', import.meta.url), JSON.stringify(out, null, 1));
