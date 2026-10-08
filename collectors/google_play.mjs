// Google Play collector — uses google-play-scraper (unofficial, free).
// Pulls TOP_FREE charts for tool-adjacent categories.

import gplay from 'google-play-scraper';
import { HttpsProxyAgent } from 'https-proxy-agent';

// got (used by google-play-scraper) does not inherit fetch's proxy handling.
const proxy = process.env.HTTPS_PROXY || process.env.https_proxy
  || process.env.HTTP_PROXY || process.env.http_proxy;
const requestOptions = {
  timeout: { request: 20000 },
  retry: { limit: 0 },
  ...(proxy ? { agent: { https: new HttpsProxyAgent(proxy, { timeout: 20000 }) } } : {}),
};

const TARGETS = [
  { key: 'us_tools', country: 'us', category: gplay.category.TOOLS },
  { key: 'us_productivity', country: 'us', category: gplay.category.PRODUCTIVITY },
  { key: 'us_photography', country: 'us', category: gplay.category.PHOTOGRAPHY },
];

async function fetchList(country, category) {
  // A proxy CONNECT can stall before got starts its request timer. Bound the
  // entire category, including agent setup, and cancel the outstanding request.
  const controller = new AbortController();
  let deadline;
  let items;
  try {
    items = await Promise.race([
      gplay.list({
        category,
        collection: gplay.collection.TOP_FREE,
        num: 50,
        country,
        throttle: 5,
        requestOptions: { ...requestOptions, signal: controller.signal },
      }),
      new Promise((_, reject) => {
        deadline = setTimeout(() => {
          controller.abort();
          reject(new Error('Google Play category deadline exceeded (30s)'));
        }, 30000);
      }),
    ]);
  } finally {
    clearTimeout(deadline);
  }
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
