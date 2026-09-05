// GitHub Search collector — finds mature open-source projects whose core is
// pure local computation and could be ported into a no-server mobile tool app.
//
// Why this exists (user, 2026-09-05): "把调研重心放在 GitHub 上,看看有哪些优秀
// 项目能做成纯 app 工具". Trending only shows what is hot this week; this
// collector asks the Search API a fixed set of *capability* questions
// (OCR, PDF, audio, image, converters, editors, …) and returns the best-
// maintained, permissively licensed answers regardless of hype.
//
// Auth: uses GITHUB_TOKEN, else `gh auth token`. Authenticated search allows
// 30 requests/min; we stay well under with a small delay between queries.

import { execSync } from 'node:child_process';

const API = 'https://api.github.com/search/repositories';

// Each query is one product capability. Keep them concrete: a repo that
// answers "how do I do X locally" is a port candidate; frameworks are not.
export const QUERIES = [
  // Documents / text
  { key: 'ocr', q: 'ocr offline in:description,topics stars:>1500' },
  { key: 'pdf', q: 'topic:pdf tool stars:>1500' },
  { key: 'markdown-editor', q: 'topic:markdown-editor stars:>1500' },
  { key: 'epub', q: 'epub reader OR converter in:description stars:>1000' },
  { key: 'translation-offline', q: 'offline translation in:description stars:>800' },
  { key: 'dictionary', q: 'topic:dictionary offline in:description stars:>500' },
  { key: 'speech-to-text', q: 'speech recognition on-device OR offline in:description stars:>1500' },
  { key: 'text-to-speech', q: 'text-to-speech offline in:description stars:>1000' },
  // Images / camera
  { key: 'image-editor', q: 'topic:image-editor stars:>1500' },
  { key: 'image-compression', q: 'image compression in:description topic:image-processing stars:>1000' },
  { key: 'background-removal', q: 'background removal in:description stars:>1500' },
  { key: 'upscale', q: 'image upscale OR super-resolution in:description stars:>2000' },
  { key: 'qrcode', q: 'topic:qrcode generator OR scanner stars:>1000' },
  { key: 'exif', q: 'exif in:description,topics stars:>500' },
  { key: 'color-picker', q: 'topic:color-picker stars:>500' },
  { key: 'palette', q: 'topic:palette-generator stars:>300' },
  // Audio / video
  { key: 'audio-editor', q: 'topic:audio-editor stars:>800' },
  { key: 'tuner-metronome', q: 'tuner OR metronome in:description,topics stars:>300' },
  { key: 'video-editing', q: 'topic:video-editing stars:>1500' },
  { key: 'video-converter', q: 'topic:video-converter stars:>800' },
  { key: 'subtitles', q: 'topic:subtitles editor OR sync in:description stars:>500' },
  { key: 'music-theory', q: 'chord OR music-theory in:topics stars:>500' },
  // Data / files
  { key: 'file-converter', q: 'file converter in:description offline OR local stars:>1000' },
  { key: 'archive', q: 'topic:compression archive extract in:description stars:>1000' },
  { key: 'json-csv-tools', q: 'json OR csv viewer OR editor in:description topic:tool stars:>800' },
  { key: 'sqlite-viewer', q: 'sqlite browser OR viewer in:description stars:>800' },
  { key: 'encryption', q: 'topic:encryption file in:description stars:>1500' },
  { key: 'password', q: 'topic:password-manager stars:>1500' },
  { key: 'hash-checksum', q: 'checksum in:description,topics stars:>500' },
  // Personal productivity (local-first)
  { key: 'notes-local', q: 'topic:note-taking offline in:description stars:>1500' },
  { key: 'flashcards', q: 'spaced repetition in:description,topics stars:>500' },
  { key: 'habit-tracker', q: 'topic:habit-tracker stars:>500' },
  { key: 'expense-tracker', q: 'topic:expense-tracker stars:>800' },
  { key: 'time-tracking', q: 'topic:time-tracking stars:>800' },
  { key: 'pomodoro', q: 'topic:pomodoro stars:>500' },
  { key: 'calendar-tools', q: 'ical OR icalendar parser generator in:description stars:>500' },
  // Science / measurement / hobby
  { key: 'astronomy', q: 'topic:astronomy calculation OR ephemeris in:description stars:>300' },
  { key: 'gps-tools', q: 'gpx OR geodesy OR coordinate in:description,topics stars:>500' },
  { key: 'unit-convert', q: 'unit conversion in:description library OR tool stars:>500' },
  { key: 'calculator-advanced', q: 'topic:calculator scientific OR graphing OR symbolic stars:>800' },
  { key: 'regex-tools', q: 'topic:regex tester OR visualizer in:description stars:>800' },
  { key: 'diff-tools', q: 'topic:diff text compare in:description stars:>800' },
  { key: 'fonts-typography', q: 'font inspector OR glyph OR typography tool in:description stars:>500' },
  // On-device models (the enabling tech for the above)
  { key: 'on-device-ml', q: 'on-device inference mobile in:description stars:>2000' },
  { key: 'whisper-mobile', q: 'whisper cpp OR mobile in:description stars:>2000' },
  { key: 'llm-mobile', q: 'llm mobile on-device in:description stars:>2000' },
];

// Permissive licences let us ship the code inside a paid closed app with
// attribution. Copyleft (GPL/AGPL) means: reimplement the algorithm or
// open-source the app — flagged, not dropped, because the *idea* still counts.
const PERMISSIVE = new Set(['mit', 'apache-2.0', 'bsd-2-clause', 'bsd-3-clause', 'isc', 'unlicense', 'mpl-2.0', '0bsd', 'zlib', 'cc0-1.0', 'bsl-1.0']);
const COPYLEFT = new Set(['gpl-2.0', 'gpl-3.0', 'agpl-3.0', 'lgpl-2.1', 'lgpl-3.0']);

function token() {
  if (process.env.GITHUB_TOKEN) return process.env.GITHUB_TOKEN;
  try {
    return execSync('gh auth token', { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  } catch {
    return '';
  }
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Curated lists, courses and interview prep dominate any broad search and
// are never something to port. Filtered by name/description/topics.
const NOISE = /(awesome|curated|cheat ?sheet|roadmap|interview|tutorial|course|handbook|collection of|list of|learning path)/i;
function isNoise(item) {
  if (NOISE.test(item.name) || NOISE.test(item.description || '')) return true;
  const t = item.topics || [];
  return t.includes('awesome-list') || t.includes('awesome') || t.includes('list') || t.includes('interview');
}

function shape(item, queryKey) {
  const lic = item.license?.spdx_id?.toLowerCase() || item.license?.key || null;
  return {
    fullName: item.full_name,
    url: item.html_url,
    description: item.description || '',
    stars: item.stargazers_count,
    forks: item.forks_count,
    openIssues: item.open_issues_count,
    language: item.language,
    license: item.license?.spdx_id || null,
    licenseClass: lic ? (PERMISSIVE.has(lic) ? 'permissive' : COPYLEFT.has(lic) ? 'copyleft' : 'other') : 'none',
    topics: item.topics || [],
    createdAt: item.created_at,
    pushedAt: item.pushed_at,
    archived: item.archived,
    queries: [queryKey],
  };
}

async function search(q, tok) {
  const url = `${API}?q=${encodeURIComponent(q + ' archived:false')}&sort=stars&order=desc&per_page=15`;
  const headers = { Accept: 'application/vnd.github+json', 'User-Agent': 'laura-intel', 'X-GitHub-Api-Version': '2022-11-28' };
  if (tok) headers.Authorization = `Bearer ${tok}`;
  const res = await fetch(url, { headers });
  if (res.status === 403 || res.status === 429) {
    const reset = Number(res.headers.get('x-ratelimit-reset') || 0) * 1000;
    const wait = Math.max(5000, Math.min(65000, reset - Date.now() + 1000));
    await sleep(wait);
    return search(q, tok);
  }
  if (!res.ok) throw new Error(`github search HTTP ${res.status} for "${q}"`);
  const body = await res.json();
  return body.items || [];
}

export async function collectGithubSearch() {
  const tok = token();
  const byName = new Map();
  const failed = {};
  for (const { key, q } of QUERIES) {
    try {
      const items = await search(q, tok);
      for (const it of items) {
        if (isNoise(it)) continue;
        const cur = byName.get(it.full_name);
        if (cur) cur.queries.push(key);
        else byName.set(it.full_name, shape(it, key));
      }
    } catch (e) {
      failed[key] = String(e?.message || e);
    }
    await sleep(tok ? 2200 : 6500); // 30/min authenticated, 10/min anonymous
  }
  const repos = [...byName.values()].sort((a, b) => b.stars - a.stars);
  if (repos.length === 0) throw new Error('github search: 0 repos across all queries');
  return {
    source: 'github_search',
    fetchedAt: new Date().toISOString(),
    authenticated: Boolean(tok),
    queryCount: QUERIES.length,
    failedQueries: failed,
    repos,
  };
}
