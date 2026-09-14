// Run a single collector and write data/YYYY-MM-DD/<name>.json, updating
// summary.json in place. Used when one source has to be re-run or added after
// run_all.mjs has already finished (e.g. the day reddit_niche was introduced).
//   node collectors/run_one.mjs reddit_niche
import { mkdir, writeFile, readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const name = process.argv[2];
const registry = {
  github: () => import('./github_trending.mjs').then((m) => m.collectGithub),
  github_search: () => import('./github_search.mjs').then((m) => m.collectGithubSearch),
  ezindie: () => import('./ezindie_weekly.mjs').then((m) => m.collectEzindie),
  indie_launches: () => import('./indie_launches.mjs').then((m) => m.collectIndieLaunches),
  appstore: () => import('./appstore_rss.mjs').then((m) => m.collectAppStore),
  googleplay: () => import('./google_play.mjs').then((m) => m.collectGooglePlay),
  hn_showhn: () => import('./hn_showhn.mjs').then((m) => m.collectShowHN),
  reddit_niche: () => import('./reddit_niche.mjs').then((m) => m.collectRedditNiche),
};
if (!registry[name]) {
  console.error(`unknown collector "${name}". known: ${Object.keys(registry).join(', ')}`);
  process.exit(2);
}

const now = new Date();
const today = [now.getFullYear(), String(now.getMonth() + 1).padStart(2, '0'), String(now.getDate()).padStart(2, '0')].join('-');
const outDir = path.join(ROOT, 'data', today);
await mkdir(outDir, { recursive: true });

const fn = await registry[name]();
const data = await fn();
await writeFile(path.join(outDir, `${name}.json`), JSON.stringify(data, null, 2), 'utf8');

const sumPath = path.join(outDir, 'summary.json');
let summary = { date: today, ok: [], failed: {}, silentZero: {} };
try { summary = JSON.parse(await readFile(sumPath, 'utf8')); } catch { /* first writer */ }
if (!summary.ok.includes(name)) summary.ok.push(name);
delete summary.failed?.[name];
if (data?.zeroHitQueries?.length) summary.silentZero[name] = data.zeroHitQueries;
await writeFile(sumPath, JSON.stringify(summary, null, 2), 'utf8');
console.log(`[ok] ${name} -> ${outDir}`);
