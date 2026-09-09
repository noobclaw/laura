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
  // 09-09: was 'background removal in:description stars:>1500' — one repo for
  // the whole tracking period. The topic form returns 13 on-target repos
  // (rembg MIT, T8RIN/ImageToolbox Apache-2.0, BiRefNet MIT), verified 09-09.
  { key: 'background-removal', q: 'topic:background-removal stars:>300' },
  { key: 'upscale', q: 'topic:super-resolution stars:>1500' },
  { key: 'upscaler', q: 'image upscaler in:name,description stars:>1500' },
  { key: 'qrcode', q: 'topic:qrcode generator OR scanner stars:>1000' },
  { key: 'exif', q: 'exif in:description,topics stars:>500' },
  { key: 'color-picker', q: 'topic:color-picker stars:>500' },
  { key: 'palette', q: 'topic:palette-generator stars:>300' },
  // Audio / video
  // 09-09: 'topic:audio-editor stars:>800' matched 1 repo; the free-text form
  // returns 24 (lossless-cut, audacity, motionity), verified 09-09.
  { key: 'audio-editor', q: 'audio editor OR waveform editor in:description,topics stars:>500' },
  { key: 'tuner-metronome', q: 'tuner OR metronome in:description,topics stars:>300' },
  { key: 'video-editing', q: 'topic:video-editing stars:>1500' },
  { key: 'video-converter', q: 'topic:video-converter stars:>800' },
  // 09-09: dropping the free-text tail ('editor OR sync in:description') takes
  // this group from 1 repo to 68, verified 09-09.
  { key: 'subtitles', q: 'topic:subtitles stars:>300' },
  { key: 'music-theory', q: 'chord OR music-theory in:topics stars:>500' },
  // Data / files
  { key: 'file-converter', q: 'file converter in:description offline OR local stars:>1000' },
  { key: 'archive', q: 'topic:compression archive extract in:description stars:>1000' },
  { key: 'json-viewer', q: 'topic:json-viewer stars:>500' },
  { key: 'csv-tools', q: 'topic:csv editor OR viewer in:description stars:>500' },
  { key: 'sqlite-viewer', q: 'topic:sqlite browser OR viewer in:name,description stars:>500' },
  { key: 'encryption', q: 'topic:encryption file encryption in:description stars:>1500' },
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
  { key: 'gpx', q: 'topic:gpx stars:>300' },
  { key: 'geodesy', q: 'topic:geodesy stars:>200' },
  { key: 'unit-convert', q: 'unit conversion in:description library OR tool stars:>500' },
  { key: 'calculator-advanced', q: 'topic:calculator scientific OR graphing OR symbolic stars:>800' },
  // 09-09: `regex-tools` and `diff-tools` dropped. Both contributed exactly one
  // repo across the whole tracking period, and the rewrites make it worse, not
  // better: `topic:regex stars:>500` returns 73 repos that are all ripgrep/fd
  // class developer tooling. A regex tester or a diff viewer as a phone app has
  // no paid face on either store — they never belonged in a consumer-tool pipe.
  { key: 'fonts-typography', q: 'font inspector OR glyph OR typography tool in:description stars:>500' },
  // On-device models (the enabling tech for the above)
  // 09-09: both rewritten. The old forms ('on-device inference mobile
  // in:description stars:>2000' / 'llm mobile on-device in:description
  // stars:>2000') returned total_count = 0 on every run from 09-05 to 09-08 —
  // three free words ANDed inside in:description plus stars:>2000 has no
  // solution. They failed silently (a successful HTTP 200 with zero items is
  // not a failedQuery), so the whole on-device-model leg of this project was
  // uncovered for at least four days without any health check noticing.
  // New forms verified against the API on 09-09 before wiring in:
  //   'on-device inference in:description stars:>500' -> total 8
  //     (alibaba/MNN, react-native-executorch, TinyChatEngine, …)
  //   'llm on-device in:description stars:>500'       -> total 7
  //     (MNN, MiniCPM, CoreML-Models, callstackincubator/ai, …)
  { key: 'on-device-ml', q: 'on-device inference in:description stars:>500' },
  { key: 'whisper-mobile', q: 'whisper in:name,description mobile OR cpp OR ios OR android in:description stars:>1500' },
  { key: 'llm-mobile', q: 'llm on-device in:description stars:>500' },
  // 2026-09-06 batch. The 09-05 pool went static overnight (345 repos, 2 new),
  // so five directions the old list could not reach. astro-stacking and
  // image-registration were added because the store side showed a live paid
  // entry with no counterpart in the pool: AstroShader $1.99 / 4.19 / 102 and
  // Star Stacker $3.99 / 4.32 / 96, both maintained, free side one 1-rating app.
  { key: 'astro-stacking', q: 'astrophotography stacking OR alignment in:description,topics stars:>200' },
  // 09-07: rewritten. The free-form `OR alignment` matched every sense of the
  // word (webpack, stable-diffusion, PaddleOCR, ultralytics); the topic form is
  // the only one that means image registration.
  { key: 'image-registration', q: 'topic:image-registration stars:>100' },
  { key: 'omr-sheetmusic', q: 'optical music recognition OR sheet music in:description stars:>300' },
  // 09-09: topic form, 2 -> 4 repos and all four are actual HTR (CTCDecoder,
  // WordDetector, handwritten-text-recognition), verified 09-09.
  { key: 'handwriting-recognition', q: 'topic:handwriting-recognition stars:>200' },
  // 09-07 batch. The 09-06 pool was completely static overnight (363 -> 363,
  // zero new repos), so five more directions. Every one of them was picked
  // because the *store* side already showed paid entries during the tracking
  // period — the 09-06 lesson was that store-first beats query-first.
  // `engineering-calc` was dropped here (0 hits on two runs) and moved to the
  // store-driven route; `trade-calc` is its narrower successor.
  // 09-09: `ballistics`, `nautical-tide` and `trade-calc` removed.
  //   ballistics    — query was broken (total_count 0 on both runs). The
  //                   working form is `topic:ballistics stars:>20` (14 repos,
  //                   verified 09-09), but the direction itself was rejected on
  //                   09-08: the free-side leader is an ammunition maker's
  //                   marketing app (Hornady, 4.76 / 42,865). Recorded here so
  //                   the next audit does not re-derive the fix.
  //   nautical-tide — same shape: working form is `topic:tides stars:>20`
  //                   (19 repos incl. pyTMD MIT), direction rejected 09-08
  //                   (9 paid incumbents, zero effective dispersion).
  //   trade-calc    — genuinely empty on GitHub: two independent formulations
  //                   both returned total_count 0. Moved to the store-driven
  //                   route, same handling as `engineering-calc` on 09-06.
  { key: 'document-scan', q: 'topic:document-scanner stars:>100' }, // 1 -> 14, verified 09-09
  { key: 'photo-dedupe', q: 'duplicate OR similar image finder in:description,topics stars:>300' },
  // 09-09 batch. The pool was byte-identical for four straight days (372 repos,
  // zero in, zero out) — the old list is exhausted, not the field. Five new
  // capability directions, each verified against the API before wiring in, and
  // each chosen because it is a technical leg under an app we already have or
  // one already in the queue rather than a fresh guess at a category.
  { key: 'speech-enhancement', q: 'topic:speech-enhancement stars:>300' },   // 28; echo-jot / AutoSnore leg
  { key: 'image-denoise', q: 'topic:noise-reduction stars:>100' },           // 26; AstroPile / photolift leg
  { key: 'photogrammetry', q: 'topic:photogrammetry stars:>500' },           // 25; camera-measurement leg
  { key: 'ephemeris', q: 'topic:ephemeris stars:>50' },                      // 18; Orbit / GoldenScout leg
  { key: 'audio-analysis', q: 'snoring OR sleep audio analysis in:description,topics stars:>50' }, // 84; AutoSnore leg
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
const NOISE = /\b(awesome|curated|cheat ?sheet|roadmap|interview|tutorials?|courses?|handbook|collection of|list of|learning path)\b/i;
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
  // 09-09: per-query hit counts. A query that returns zero items is an HTTP 200
  // — it never shows up in failedQueries — so four broken queries sat in this
  // list for days while every health check stayed green (see report 09-08 §六 5).
  // hits = items the API returned; kept = what survived the noise filter.
  const hits = {};
  for (const { key, q } of QUERIES) {
    try {
      const items = await search(q, tok);
      let kept = 0;
      for (const it of items) {
        if (isNoise(it)) continue;
        kept += 1;
        const cur = byName.get(it.full_name);
        if (cur) cur.queries.push(key);
        else byName.set(it.full_name, shape(it, key));
      }
      hits[key] = { hits: items.length, kept };
    } catch (e) {
      failed[key] = String(e?.message || e);
    }
    await sleep(tok ? 2200 : 6500); // 30/min authenticated, 10/min anonymous
  }
  const repos = [...byName.values()].sort((a, b) => b.stars - a.stars);
  if (repos.length === 0) throw new Error('github search: 0 repos across all queries');
  const zeroHitQueries = Object.keys(hits).filter((k) => hits[k].hits === 0);
  const lowHitQueries = Object.keys(hits).filter((k) => hits[k].hits > 0 && hits[k].hits <= 3);
  return {
    source: 'github_search',
    fetchedAt: new Date().toISOString(),
    authenticated: Boolean(tok),
    queryCount: QUERIES.length,
    failedQueries: failed,
    queryHits: hits,
    zeroHitQueries,
    lowHitQueries,
    repos,
  };
}
