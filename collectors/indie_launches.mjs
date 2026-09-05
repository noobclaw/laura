// Indie launches collector — "看看别的开发者在做什么" (user, 2026-09-05).
// Sources that expose plain feeds without an API key:
//   - Product Hunt daily feed (Atom)            https://www.producthunt.com/feed
//   - Reddit new posts (RSS) for r/SideProject, r/indiehackers, r/iOSProgramming,
//     r/androidapps — Reddit rate-limits anonymous RSS hard (429), so requests
//     are spaced out and retried once.
// Indie Hackers is client-rendered and its self-reported revenue is junk;
// Show HN is already covered by hn_showhn.mjs.

const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function decode(s) {
  return s
    .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, '$1')
    .replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&#x27;/g, "'").replace(/&nbsp;/g, ' ');
}
const strip = (html) => decode(html).replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();

async function get(url, tries = 2) {
  for (let i = 0; i < tries; i++) {
    const res = await fetch(url, { headers: { 'User-Agent': UA, Accept: 'application/rss+xml, application/atom+xml, text/xml, */*' } });
    if (res.status === 429 && i + 1 < tries) { await sleep(8000); continue; }
    if (!res.ok) throw new Error(`HTTP ${res.status} ${url}`);
    return res.text();
  }
  throw new Error(`gave up ${url}`);
}

/// Atom (Product Hunt) and RSS (Reddit) both have <entry>/<item> with a
/// title, a link and some body text; one loose parser covers both.
function parseFeed(xml, source) {
  const out = [];
  const blocks = xml.split(/<entry>|<item>/).slice(1);
  for (const b of blocks) {
    const title = strip(b.match(/<title[^>]*>([\s\S]*?)<\/title>/)?.[1] || '');
    const link = b.match(/<link[^>]*href="([^"]+)"/)?.[1] || strip(b.match(/<link>([\s\S]*?)<\/link>/)?.[1] || '');
    const body = strip(b.match(/<(?:content|description|summary)[^>]*>([\s\S]*?)<\/(?:content|description|summary)>/)?.[1] || '').slice(0, 400);
    const published = b.match(/<(?:published|pubDate|updated)>([^<]+)</)?.[1] || null;
    if (title) out.push({ source, title, url: link, summary: body, published });
  }
  return out;
}

const FEEDS = [
  ['producthunt', 'https://www.producthunt.com/feed'],
  ['reddit/SideProject', 'https://www.reddit.com/r/SideProject/new/.rss'],
  ['reddit/indiehackers', 'https://www.reddit.com/r/indiehackers/new/.rss'],
  ['reddit/iOSProgramming', 'https://www.reddit.com/r/iOSProgramming/new/.rss'],
  ['reddit/androidapps', 'https://www.reddit.com/r/androidapps/new/.rss'],
];

export async function collectIndieLaunches() {
  const items = [];
  const failed = {};
  for (const [name, url] of FEEDS) {
    try {
      const xml = await get(url);
      const parsed = parseFeed(xml, name);
      if (parsed.length === 0) throw new Error('parsed 0 entries (feed structure changed?)');
      items.push(...parsed);
    } catch (e) {
      failed[name] = String(e?.message || e);
    }
    await sleep(3000);
  }
  if (items.length === 0) throw new Error('indie launches: every feed failed: ' + JSON.stringify(failed));
  return { source: 'indie_launches', fetchedAt: new Date().toISOString(), failed, items };
}
