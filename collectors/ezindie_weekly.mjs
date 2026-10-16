// ezindie.com「独立开发变现周刊」collector — one Chinese weekly, each issue
// profiles ~5 small products with real revenue figures and how they got
// there. Asked for by the user on 2026-09-05 ("独立开发者的网站…给我们一些做
// app 的思路"). Server-rendered HTML, no API; we read the RSS for issue links
// and pull the newest issues' product sections as plain text.

const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36';
const RSS = 'https://www.ezindie.com/feed/rss.xml';
const ISSUES_TO_READ = 4;

function decode(s) {
  return s
    .replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&nbsp;/g, ' ');
}

function textOf(html) {
  const noScript = html.replace(/<script[\s\S]*?<\/script>|<style[\s\S]*?<\/style>/g, '');
  return decode(noScript.replace(/<br\s*\/?>/g, '\n').replace(/<\/(p|div|h\d|li)>/g, '\n').replace(/<[^>]+>/g, ''))
    .split('\n').map((l) => l.trim()).filter(Boolean);
}

async function get(url) {
  const res = await fetch(url, { headers: { 'User-Agent': UA } });
  if (!res.ok) throw new Error(`ezindie ${url}: HTTP ${res.status}`);
  return res.text();
}

// Read article h2 headings, not flattened text: the contents list repeats
// titles, numbered steps inside an article can look like new products, and
// newer issues have ten articles rather than nine.
function parseIssue(html) {
  const headings = [...html.matchAll(/<h2\b[^>]*>([\s\S]*?)<\/h2>/gi)];
  return headings.flatMap((heading, i) => {
    const title = textOf(heading[1]).join(' ').match(/^\d{1,2}[、.．]\s*(.+)$/)?.[1];
    if (!title) return [];
    const start = heading.index + heading[0].length;
    let body = html.slice(start, headings[i + 1]?.index ?? html.length);
    // The final article is followed by the site's promotional/footer headings.
    if (i === headings.length - 1) body = body.split(/<h[1-6]\b/i)[0];
    const text = textOf(body).join(' ').slice(0, 1500);
    return [{
      title: title.trim(),
      summary: text.slice(0, 600),
      revenueHint: (title + ' ' + text).match(/(每月|月入|年收入|月收入|MRR|ARR)[^。,,]{0,30}/)?.[0] || null,
    }];
  });
}

export async function collectEzindie() {
  const rss = await get(RSS);
  const items = [...rss.matchAll(/<item>[\s\S]*?<title><!\[CDATA\[(.*?)\]\]><\/title>[\s\S]*?<link>(.*?)<\/link>[\s\S]*?<\/item>/g)]
    .map((m) => ({ title: m[1].trim(), url: m[2].trim() }))
    .filter((it) => /weekly\/issue-\d+/.test(it.url));
  if (items.length === 0) throw new Error('ezindie: no weekly issues in RSS (feed structure changed?)');
  const issues = [];
  for (const it of items.slice(0, ISSUES_TO_READ)) {
    try {
      const html = await get(it.url);
      const products = parseIssue(html);
      if (!products.length) throw new Error('ezindie: no numbered article headings');
      issues.push({ ...it, products });
    } catch (e) {
      issues.push({ ...it, error: String(e?.message || e) });
    }
  }
  return { source: 'ezindie_weekly', fetchedAt: new Date().toISOString(), issues };
}
