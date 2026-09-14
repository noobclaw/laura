// Reddit vertical-community collector — discipline AY④ (user, 2026-09-13).
//
// The steering change of 2026-09-13 moved the primary discovery channel off the
// generalist developer feeds (r/SideProject / r/indiehackers / Product Hunt /
// HN: 69 tracked days, 0 candidates) and onto vertical profession/hobby subs,
// where the four required words can actually co-occur: 垂直细分 + 巨头注意不到 +
// 抱怨最多 + 还没人做或做得不够好.
//
// Method fixed by the user's brief:
//   in-sub search for `app`, sort=top, t=year, then filter by a pain regex.
//   "圈里还在用 Excel/纸笔" is the strongest positive signal — it proves the
//   need is real AND that nobody has built the thing.
//
// Two hard constraints learned from indie_launches.mjs (same host):
//   - Reddit rate-limits anonymous RSS hard (429). Requests are spaced >=9s and
//     retried with a growing backoff; anything still missing gets a second pass.
//   - old.reddit.com is NOT a fallback: it answers /.rss with 200 and an HTML
//     page, turning a loud 429 into a silent "0 entries". Never add it.
//
// Roster rotation: 30 subs is ~5 minutes of wall clock at the required spacing,
// and a sub's top-of-year list barely moves day to day. So each run takes a
// deterministic slice of the roster (by day-of-year), which covers the whole
// roster every ROTATION_DAYS days and keeps one run bounded. The slice is
// recorded in the output so a report can say which subs were and were not seen.

const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function decode(s) {
  return s
    .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, '$1')
    .replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&#x27;/g, "'").replace(/&nbsp;/g, ' ');
}
const strip = (html) => decode(html).replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();

async function get(url, tries = 3) {
  for (let i = 0; i < tries; i++) {
    const res = await fetch(url, { headers: { 'User-Agent': UA, Accept: 'application/atom+xml, application/rss+xml, text/xml, */*' } });
    if (res.status === 429 && i + 1 < tries) { await sleep(15000 * (i + 1)); continue; }
    if (!res.ok) throw new Error(`HTTP ${res.status} ${url}`);
    return res.text();
  }
  throw new Error(`gave up ${url}`);
}

function parseFeed(xml, sub) {
  const out = [];
  const blocks = xml.split(/<entry>/).slice(1);
  for (const b of blocks) {
    const title = strip(b.match(/<title[^>]*>([\s\S]*?)<\/title>/)?.[1] || '');
    const url = b.match(/<link[^>]*href="([^"]+)"/)?.[1] || '';
    const body = strip(b.match(/<content[^>]*>([\s\S]*?)<\/content>/)?.[1] || '');
    const published = b.match(/<(?:published|updated)>([^<]+)</)?.[1] || null;
    const author = strip(b.match(/<author>[\s\S]*?<name>([^<]+)<\/name>/)?.[1] || '');
    if (title) out.push({ sub, title, url, author, published, body });
  }
  return out;
}

// The user's phrase list, plus the obvious spelling variants of the same
// complaint. Kept deliberately small: a wide regex makes every post match and
// destroys the signal the filter exists to find.
const PAIN = [
  ['no_good_app', /\b(no good app|there('| i)?s no app|isn'?t an app|is there an app|no decent app|never found an app)\b/i],
  ['wish', /\b(wish there was|wish there were|wish someone would|someone should (make|build))\b/i],
  ['app_bad', /\b(app sucks|hate the app|app is (terrible|awful|garbage|useless|broken)|worst app)\b/i],
  ['alternative', /\balternative to\b/i],
  ['spreadsheet', /\b(spreadsheet|excel|google sheets)\b/i],
  ['paper', /\b(paper and pen|pen and paper|pencil and paper|paper logbook|paper log|notebook and pen|by hand)\b/i],
];

function painOf(text) {
  const hits = [];
  for (const [tag, re] of PAIN) if (re.test(text)) hits.push(tag);
  return hits;
}

// Vertical profession/hobby subs. Roster is the user's own list (2026-09-13)
// plus close neighbours of the same shape. Order is stable so the rotation is
// reproducible; append new subs at the end, never reorder.
export const SUBS = [
  'Beekeeping', 'woodworking', 'HVAC', 'electricians', 'sailing', 'scuba',
  'flying', 'Truckers', 'Genealogy', 'knitting', 'Aquariums', 'Bonsai',
  'Equestrian', 'KitchenConfidential', 'Dogtraining', 'amateurradio',
  'quilting', 'Firefighting', 'Welding', 'reptiles', 'Blacksmith',
  'Machinists', 'Plumbing', 'Farming', 'Chickens', 'Cheesemaking',
  'Homebrewing', 'Luthier', 'Gunsmithing',
];
const ROSTER = SUBS;

const PER_RUN = 10;

export function rotationFor(date = new Date()) {
  const start = Date.UTC(date.getUTCFullYear(), 0, 0);
  const doy = Math.floor((Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()) - start) / 86400000);
  const slices = Math.ceil(ROSTER.length / PER_RUN);
  const idx = doy % slices;
  return ROSTER.slice(idx * PER_RUN, idx * PER_RUN + PER_RUN);
}

export async function collectRedditNiche() {
  // REDDIT_NICHE_ALL=1 walks the whole roster in one run (~5 min). Used for the
  // first baseline pass; the daily run takes the rotation slice.
  const subs = process.env.REDDIT_NICHE_ALL === '1' ? ROSTER.slice() : rotationFor(new Date());
  const failed = {};
  const counts = {};
  const items = [];
  for (const sub of subs) {
    const url = `https://www.reddit.com/r/${sub}/search.rss?q=app&restrict_sr=1&sort=top&t=year&limit=100`;
    try {
      const posts = parseFeed(await get(url), sub);
      if (posts.length === 0) throw new Error('parsed 0 entries (429 page or feed structure changed?)');
      let kept = 0;
      for (const p of posts) {
        const matches = painOf(`${p.title} ${p.body}`);
        if (matches.length === 0) continue;
        kept++;
        items.push({
          sub: p.sub, title: p.title, url: p.url, author: p.author,
          published: p.published, matches, excerpt: p.body.slice(0, 500),
        });
      }
      counts[sub] = { total: posts.length, kept };
    } catch (e) {
      failed[sub] = String(e?.message || e);
    }
    await sleep(9000);
  }
  for (const sub of Object.keys(failed)) {
    await sleep(20000);
    const url = `https://www.reddit.com/r/${sub}/search.rss?q=app&restrict_sr=1&sort=top&t=year&limit=100`;
    try {
      const posts = parseFeed(await get(url), sub);
      if (posts.length === 0) throw new Error('parsed 0 entries (429 page or feed structure changed?)');
      let kept = 0;
      for (const p of posts) {
        const matches = painOf(`${p.title} ${p.body}`);
        if (matches.length === 0) continue;
        kept++;
        items.push({
          sub: p.sub, title: p.title, url: p.url, author: p.author,
          published: p.published, matches, excerpt: p.body.slice(0, 500),
        });
      }
      counts[sub] = { total: posts.length, kept };
      delete failed[sub];
    } catch (e) {
      failed[sub] = String(e?.message || e);
    }
  }
  if (Object.keys(counts).length === 0) {
    throw new Error('reddit_niche: every sub failed: ' + JSON.stringify(failed));
  }
  return {
    source: 'reddit_niche', fetchedAt: new Date().toISOString(),
    rosterSize: ROSTER.length, perRun: PER_RUN, subs, counts, failed, items,
  };
}
