// App Store collector — Apple official marketing RSS (free, no key).
// v2 feed has no genre filter, so we fetch top charts then batch-lookup genres
// via the iTunes Lookup API and tag utility/productivity apps.

const FEEDS = [
  { country: 'us', feed: 'top-free' },
  { country: 'us', feed: 'top-paid' },
  { country: 'cn', feed: 'top-free' },
  { country: 'cn', feed: 'top-paid' },
];

const TOOL_GENRES = new Set([
  'Utilities', 'Productivity', 'Photo & Video', 'Graphics & Design',
  // CN storefront returns localized genre names
  '工具', '效率', '摄影与录像',
]);

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Apple's RSS edge throws transient 5xx (504 on cn/top-paid, 2026-08-07) — retry before giving up.
async function fetchFeed(country, feed) {
  const url = `https://rss.applemarketingtools.com/api/v2/${country}/apps/${feed}/100/apps.json`;
  let res = null;
  let lastErr = 'unknown';
  for (let attempt = 0; attempt < 4; attempt++) {
    if (attempt > 0) await sleep(2000 * attempt);
    try {
      res = await fetch(url);
      if (res.ok) break;
      lastErr = `HTTP ${res.status}`;
      if (res.status < 500 && res.status !== 429) break;
    } catch (e) {
      lastErr = String(e?.message || e);
    }
    res = null;
  }
  if (!res || !res.ok) throw new Error(`appstore rss ${country}/${feed}: ${lastErr}`);
  const json = await res.json();
  return (json.feed?.results || []).map((r, i) => ({
    rank: i + 1,
    id: r.id,
    name: r.name,
    artist: r.artistName,
    url: r.url,
    genres: (r.genres || []).map((g) => g.name),
  }));
}

// Some feed entries lack genres; enrich the ungenred ones via lookup (200 ids/call).
async function enrichGenres(apps, country) {
  const missing = apps.filter((a) => a.genres.length === 0);
  for (let i = 0; i < missing.length; i += 150) {
    const batch = missing.slice(i, i + 150);
    const ids = batch.map((a) => a.id).join(',');
    try {
      const res = await fetch(`https://itunes.apple.com/lookup?id=${ids}&country=${country}`);
      if (!res.ok) continue;
      const json = await res.json();
      const byId = new Map((json.results || []).map((r) => [String(r.trackId), r]));
      for (const app of batch) {
        const info = byId.get(String(app.id));
        if (info) app.genres = info.genres || (info.primaryGenreName ? [info.primaryGenreName] : []);
      }
    } catch {
      // enrichment is best-effort
    }
  }
}

export async function collectAppStore() {
  const charts = {};
  const feedErrors = {};
  for (const { country, feed } of FEEDS) {
    const key = `${country}_${feed.replace('-', '_')}`;
    try {
      const apps = await fetchFeed(country, feed);
      await enrichGenres(apps, country);
      for (const a of apps) a.isToolLike = a.genres.some((g) => TOOL_GENRES.has(g));
      charts[key] = apps;
    } catch (e) {
      // One bad storefront must not sink the whole source — record and continue.
      feedErrors[key] = String(e?.message || e);
    }
  }
  if (Object.keys(charts).length === 0) {
    throw new Error(`appstore rss: all feeds failed — ${JSON.stringify(feedErrors)}`);
  }
  return { source: 'appstore_rss', fetchedAt: new Date().toISOString(), charts, feedErrors };
}
