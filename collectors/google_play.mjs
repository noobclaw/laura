// Google Play collector — uses google-play-scraper (unofficial, free).
// Pulls TOP_FREE charts for tool-adjacent categories.

import gplay from 'google-play-scraper';

const TARGETS = [
  { key: 'us_tools', country: 'us', category: gplay.category.TOOLS },
  { key: 'us_productivity', country: 'us', category: gplay.category.PRODUCTIVITY },
  { key: 'us_photography', country: 'us', category: gplay.category.PHOTOGRAPHY },
];

async function fetchList(country, category) {
  const items = await gplay.list({
    category,
    collection: gplay.collection.TOP_FREE,
    num: 50,
    country,
    throttle: 5,
  });
  return items.map((it, i) => ({
    rank: i + 1,
    appId: it.appId,
    title: it.title,
    developer: it.developer,
    score: it.score,
    installs: it.installs ?? null,
    summary: it.summary,
    url: it.url,
  }));
}

export async function collectGooglePlay() {
  const charts = {};
  const errors = {};
  for (const t of TARGETS) {
    try {
      charts[t.key] = await fetchList(t.country, t.category);
    } catch (e) {
      errors[t.key] = String(e?.message || e);
    }
  }
  if (Object.keys(charts).length === 0) {
    throw new Error(`google play: all targets failed: ${JSON.stringify(errors)}`);
  }
  return { source: 'google_play', fetchedAt: new Date().toISOString(), charts, errors };
}
