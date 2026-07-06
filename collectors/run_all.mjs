// Runs all collectors and writes data/YYYY-MM-DD/*.json.
// Each source fails independently — a summary.json records what succeeded.

import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { collectGithub } from './github_trending.mjs';
import { collectAppStore } from './appstore_rss.mjs';
import { collectGooglePlay } from './google_play.mjs';
import { collectShowHN } from './hn_showhn.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const today = new Date().toISOString().slice(0, 10);
const outDir = path.join(ROOT, 'data', today);
await mkdir(outDir, { recursive: true });

const collectors = [
  ['github', collectGithub],
  ['appstore', collectAppStore],
  ['googleplay', collectGooglePlay],
  ['hn_showhn', collectShowHN],
];

const summary = { date: today, ok: [], failed: {} };

for (const [name, fn] of collectors) {
  try {
    const data = await fn();
    await writeFile(path.join(outDir, `${name}.json`), JSON.stringify(data, null, 2), 'utf8');
    summary.ok.push(name);
    console.log(`[ok] ${name}`);
  } catch (e) {
    summary.failed[name] = String(e?.message || e);
    console.error(`[FAIL] ${name}: ${summary.failed[name]}`);
  }
}

await writeFile(path.join(outDir, 'summary.json'), JSON.stringify(summary, null, 2), 'utf8');
console.log(`\nDone. ${summary.ok.length}/${collectors.length} sources ok → ${outDir}`);
if (summary.ok.length === 0) process.exit(1);
