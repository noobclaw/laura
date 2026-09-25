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

// Keep the Accept header: without it the same search URL answered 403 on 09-25.
// Comment feeds pass backoffMs=30000 — a 15s retry after 429 failed in the
// 09-25 probe, 60s later it answered 200.
async function get(url, tries = 3, backoffMs = 15000) {
  for (let i = 0; i < tries; i++) {
    const res = await fetch(url, { headers: { 'User-Agent': UA, Accept: 'application/atom+xml, application/rss+xml, text/xml, */*' } });
    if (res.status === 429 && i + 1 < tries) { await sleep(backoffMs * (i + 1)); continue; }
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
    const id = b.match(/<id>([^<]+)<\/id>/)?.[1] || '';
    if (title) out.push({ sub, id, title, url, author, published, body });
  }
  return out;
}

// Complaint templates — rule 4 of kb/选题规矩/立项前挑刺关.md (2026-09-25),
// borrowed from gapscout's query list. The sub restriction plus the `app`
// search is the "圈子关键词" half of each template; the phrase half is matched
// here, locally.
//
// Why locally and not as a Reddit query: probed 09-25 on r/woodworking —
// `"looking for" OR "is there an app" OR ... OR subscription` (restrict_sr,
// top/year) came back 200 with 100 entries that were simply the sub's top posts
// ("Made my first box", "I made a 7'6 Bigfoot"). Reddit loosens a long OR list
// into near-match-all, so the filter has to happen on our side. Separate
// per-phrase queries would cost 10x the anonymous quota that already 429s.
//
// Kept deliberately narrow: a wide regex makes every post match and destroys
// the signal the filter exists to find. The last four tags are the 09-13 list
// (spreadsheet / paper = the strongest "nobody built it" signal) and stay.
const PAIN = [
  ['looking_for', /\blooking for (an? |any )?(good |decent |simple )?(app|software|program|tool)\b/i],
  ['is_there_app', /\b(is there (an?|any) (app|software|program)|isn'?t there an app)\b/i],
  ['wish', /\b(wish there (was|were)|wish someone would|someone should (make|build))\b/i],
  ['overpriced', /\boverpriced\b/i],
  ['too_expensive', /\btoo (expensive|pricey)\b/i],
  ['alternative', /\balternatives? to\b/i],
  ['switched_from', /\bswitched (away )?from\b/i],
  ['gave_up', /\b(gave up on|giving up on)\b/i],
  ['hate_that', /\bhate (that|how|the app)\b/i],
  ['subscription', /\bsubscriptions?\b/i],
  ['no_good_app', /\b(no good app|there('| i)?s no app|no decent app|never found an app)\b/i],
  ['app_bad', /\b(app sucks|app is (terrible|awful|garbage|useless|broken)|worst app)\b/i],
  ['spreadsheet', /\b(spreadsheet|excel|google sheets)\b/i],
  ['paper', /\b(paper and pen|pen and paper|pencil and paper|paper logbook|paper log|notebook and pen|by hand)\b/i],
];

// Signal labels, read off the comment thread of each matched post (rule 4):
//   agree        — how many other people said "+1 / same / me too / I'd use this"
//   payMentions  — explicit willingness to pay, or a price named (prices kept)
//   failed       — solutions already tried and dropped ("tried X", "switched from X")
//   freeAlt      — someone answered with a free app that already does it
// The report sorts by rankScore = (1 + agree) × (1 + payMentions).
const AGREE = /^\s*(\+1|same( here)?|me too|this[.!]*$|seconded|seconding|following|commenting to follow|also looking|i'?d (also )?(love|use|buy|pay)|would (also )?(love|use|buy|pay)|interested|subscribing|yes please)\b/i;
const AGREE_ANY = /(\+1\b|\bsame problem\b|\bsame issue\b|\bi'?m in the same boat\b|\bi need this too\b)/i;
const PAY = /\b((would|i'?d|happily|gladly|willing to|i'?ll) (pay|buy)|take my money|worth (paying|the money)|one[- ]time (purchase|payment|fee)|pay (for (it|this|that|an app)|a few bucks))\b/i;
const PRICE = /\$\s?\d{1,4}(?:\.\d{2})?(?:\s?(?:\/|per|a)\s?(?:mo|month|yr|year))?/gi;
const PRICE_CONTEXT = /\b(pay|paid|app|apps|software|program|subscription|subscribe|license|licence|one[- ]time|per month|a month|\/mo|per year|a year|\/yr|worth it|in-app|pro version|lifetime)\b/i;
const FAILED = /\b(tried|used to use|switched (?:away )?from|gave up on|stopped using|uninstalled|ditched|moved away from)\s+([A-Z][\w'+&-]*(?:\s+[A-Z][\w'+&-]*){0,2})/g;
const FREE_ALT = /\b(just use|i use|we use|try|check out)\s+([A-Z][\w'+&-]*(?:\s+[A-Z][\w'+&-]*){0,2})[^.!?]{0,80}\bfree\b|\bfree (app|alternative|version|option) (called|named|is)\b|\bit'?s (completely |totally )?free\b/i;

// Comment threads cost one request each on the same anonymous bucket, so only
// the strongest matches per run get one (ranked by how many templates hit).
const COMMENT_FETCHES = 6;

function signalsOf(post, comments) {
  const others = comments.filter((c) => c.author && c.author !== post.author);
  const allText = [post.title, post.body, ...comments.map((c) => c.body)].join('\n');
  let agree = 0;
  for (const c of others) if (AGREE.test(c.body) || AGREE_ANY.test(c.body)) agree++;
  let payMentions = 0;
  const prices = new Set();
  for (const t of [`${post.title} ${post.body}`, ...comments.map((c) => c.body)]) {
    // A bare price is usually hardware ("$1900 Makera", 09-25 test on r/CNC);
    // it only counts when said next to a software/payment word.
    const p = [...t.matchAll(PRICE)]
      .filter((m) => PRICE_CONTEXT.test(t.slice(Math.max(0, m.index - 60), m.index + m[0].length + 60)))
      .map((m) => m[0]);
    if (PAY.test(t) || p.length) payMentions++;
    for (const x of p) prices.add(x.replace(/\s+/g, ''));
  }
  const failed = new Set();
  for (const m of allText.matchAll(FAILED)) failed.add(m[2].trim());
  const freeAlt = [];
  for (const c of others) {
    const m = c.body.match(FREE_ALT);
    if (m) freeAlt.push(c.body.slice(Math.max(0, m.index - 40), m.index + 140));
  }
  return {
    commentCount: others.length, agree, payMentions, prices: [...prices].slice(0, 8),
    failed: [...failed].slice(0, 10), freeAlt: freeAlt.slice(0, 3),
    rankScore: (1 + agree) * (1 + payMentions),
  };
}

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
  // 2026-09-16: the pool/spa dosing candidate (report §三 1) rests entirely on
  // App Store review quotes — a single source. These three cover the trade and
  // the owners so the complaint can be cross-checked off-store. Appended, never
  // reordered, so the rotation slices stay reproducible.
  'pools', 'swimmingpools', 'poolcleaning',
];
const ROSTER = SUBS;

// 2026-09-19: 10 -> 5. Frequency only — the query string, the pain regex and
// the roster order are untouched, so each sub's hit set must stay identical.
//
// Why: the daily re-run's marginal output is exactly zero. `sort=top&t=year`
// returns a year-long ranking that does not move day to day; every same-slice
// comparison so far (09-14 vs 09-18, 09-14 vs 09-19, ...) came back at 100%
// URL overlap — five times now. What the run does cost is the entire anonymous
// Reddit quota: on 09-18 and again on 09-19 the targeted in-sub pain searches
// that the 09-13 brief calls the PRIMARY discovery channel (r/EngineeringStudents,
// r/AskElectronics) were 429'd because this collector had already spent the
// budget re-fetching a list it last saw four days earlier.
//
// 10 -> 5 halves both wall clock (~15min -> ~7.5min) and request count, and
// stretches the roster cycle from ceil(32/10)=4 days to ceil(32/5)=7. A 7-day
// revisit of a year-ranking loses nothing.
//
// NOTE: rotationFor() is `doy % slices`, so slices 4 -> 7 changes which subs
// land on which day. Cross-day comparisons must match on sub name, never on
// the slice index.
//
// Rollback condition (report 2026-09-19 §六 0): if the targeted searches are
// still 429 tomorrow, the bottleneck is not this collector — restore PER_RUN.
const PER_RUN = 5;

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
  // REDDIT_NICHE_SUBS=MachineEmbroidery,Machinists targets named subs — for
  // re-checking a candidate's own circle (rule 4), outside the rotation.
  const subs = process.env.REDDIT_NICHE_SUBS
    ? process.env.REDDIT_NICHE_SUBS.split(',').map((s) => s.trim()).filter(Boolean)
    : process.env.REDDIT_NICHE_ALL === '1' ? ROSTER.slice() : rotationFor(new Date());
  const failed = {};
  const counts = {};
  const items = [];
  const scanSub = async (sub) => {
    const url = `https://www.reddit.com/r/${sub}/search.rss?q=app&restrict_sr=1&sort=top&t=year&limit=100`;
    const posts = parseFeed(await get(url), sub);
    if (posts.length === 0) throw new Error('parsed 0 entries (429 page or feed structure changed?)');
    let kept = 0;
    for (const p of posts) {
      const matches = painOf(`${p.title} ${p.body}`);
      if (matches.length === 0) continue;
      kept++;
      items.push({
        sub: p.sub, title: p.title, url: p.url, author: p.author,
        published: p.published, matches, excerpt: p.body.slice(0, 500), body: p.body,
      });
    }
    counts[sub] = { total: posts.length, kept };
  };
  for (const sub of subs) {
    try { await scanSub(sub); } catch (e) { failed[sub] = String(e?.message || e); }
    await sleep(9000);
  }
  for (const sub of Object.keys(failed)) {
    await sleep(20000);
    try { await scanSub(sub); delete failed[sub]; } catch (e) { failed[sub] = String(e?.message || e); }
  }
  if (Object.keys(counts).length === 0) {
    throw new Error('reddit_niche: every sub failed: ' + JSON.stringify(failed));
  }

  // Comment threads for the strongest matches (most templates hit, newest first
  // on ties). Everything else is still labelled from its own title/body, with
  // commentsFetched=false so the report never reads a 0 as "nobody agreed".
  const order = items.slice().sort((a, b) => b.matches.length - a.matches.length
    || String(b.published).localeCompare(String(a.published)));
  const toFetch = new Set(order.slice(0, COMMENT_FETCHES));
  const commentErrors = {};
  for (const it of items) {
    let comments = [];
    it.commentsFetched = false;
    if (toFetch.has(it) && it.url) {
      await sleep(9000);
      try {
        comments = parseFeed(await get(it.url.replace(/\/?$/, '/') + '.rss', 3, 30000), it.sub)
          .filter((c) => c.id.startsWith('t1_'));
        it.commentsFetched = true;
      } catch (e) {
        commentErrors[it.url] = String(e?.message || e);
      }
    }
    Object.assign(it, signalsOf(it, comments));
    delete it.body;
  }
  items.sort((a, b) => b.rankScore - a.rankScore || b.matches.length - a.matches.length);
  return {
    source: 'reddit_niche', fetchedAt: new Date().toISOString(),
    rosterSize: ROSTER.length, perRun: PER_RUN, subs, counts, failed,
    commentFetches: COMMENT_FETCHES, commentErrors,
    sortedBy: 'rankScore = (1 + agree) × (1 + payMentions)', items,
  };
}
