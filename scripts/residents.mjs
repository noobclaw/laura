// "Incumbent scan": the daily chart read only ever looks at NEW / GONE / |Δ|>=15,
// so an app that sits on the chart for months without moving is structurally
// invisible to it — which is exactly the shape discipline AY③ asks for
// (stable demand + low rating + abandoned = someone is paying, nobody is
// maintaining). This lists the long-term residents of a paid chart, then
// looks each one up so they can be sorted by rating.
//
//   node scripts/residents.mjs <us_top_paid|cn_top_paid> [minDays]
//
// Weekly job (discipline AZ, 2026-09-14): run both paid charts every Sunday and
// look up every row flagged "<== GAP" (rating < 4.2 with >= 20 ratings).
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const DATA = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', 'data');
const [chart = 'cn_top_paid', minDaysArg = '30'] = process.argv.slice(2);
const minDays = Number(minDaysArg);
const days = fs.readdirSync(DATA).filter((d) => /^\d{4}-\d{2}-\d{2}$/.test(d)).sort();
const seen = new Map(); // id -> {name, days, ranks}
for (const d of days) {
  let o;
  try { o = JSON.parse(fs.readFileSync(path.join(DATA, d, 'appstore.json'), 'utf8')); } catch { continue; }
  for (const e of o.charts[chart] || []) {
    if (!seen.has(e.id)) seen.set(e.id, { name: e.name, days: 0, ranks: [] });
    const s = seen.get(e.id);
    s.days++; s.ranks.push(e.rank);
  }
}
const residents = [...seen.entries()].filter(([, s]) => s.days >= minDays);
console.log(`chart=${chart} tracked days=${days.length} residents(>=${minDays}d)=${residents.length} of ${seen.size}`);
const country = chart.startsWith('cn') ? 'cn' : 'us';
const ids = residents.map(([id]) => id);
const rows = [];
for (let i = 0; i < ids.length; i += 20) {
  const j = await (await fetch(`https://itunes.apple.com/lookup?id=${ids.slice(i, i + 20).join(',')}&country=${country}`)).json();
  rows.push(...(j.results || []));
  await new Promise((r) => setTimeout(r, 1200));
}
const byId = new Map(rows.map((r) => [String(r.trackId), r]));
const out = residents.map(([id, s]) => {
  const r = byId.get(id);
  const med = [...s.ranks].sort((a, b) => a - b)[Math.floor(s.ranks.length / 2)];
  return {
    id, name: s.name, days: s.days, med,
    price: r?.formattedPrice ?? '?', star: r?.averageUserRating ?? 0,
    n: r?.userRatingCount ?? 0, ver: (r?.currentVersionReleaseDate || '').slice(0, 10),
    genre: (r?.genres || [])[0] || '',
  };
}).sort((a, b) => a.star - b.star);
for (const o of out) {
  const flag = (o.star > 0 && o.star < 4.2 && o.n >= 20) ? ' <== GAP' : '';
  console.log(`★${o.star.toFixed(2)} ${String(o.n).padStart(6)}条 ${o.price.padStart(8)} ${String(o.days).padStart(3)}d med#${String(o.med).padStart(3)} ver ${o.ver} ${o.genre.slice(0, 12).padEnd(12)} ${o.name}${flag}`);
}
