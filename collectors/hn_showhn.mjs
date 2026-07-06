// Hacker News "Show HN" collector — Algolia public API (free, no key).
// Good early signal for indie tools before they hit app-store charts.

export async function collectShowHN() {
  const since = Math.floor(Date.now() / 1000) - 7 * 24 * 3600;
  // The HN Algolia index no longer allows numeric filtering on `points`,
  // so filter by time via the API and by score locally.
  const filters = encodeURIComponent(`created_at_i>${since}`);
  const url = `https://hn.algolia.com/api/v1/search?tags=show_hn&numericFilters=${filters}&hitsPerPage=100`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`hn showhn: HTTP ${res.status}`);
  const json = await res.json();
  const items = (json.hits || []).filter((h) => (h.points || 0) >= 50).map((h) => ({
    title: h.title,
    url: h.url || `https://news.ycombinator.com/item?id=${h.objectID}`,
    hnUrl: `https://news.ycombinator.com/item?id=${h.objectID}`,
    points: h.points,
    comments: h.num_comments,
    createdAt: h.created_at,
  }));
  return { source: 'hn_showhn', fetchedAt: new Date().toISOString(), items };
}
