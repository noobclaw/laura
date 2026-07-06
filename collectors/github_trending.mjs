// GitHub Trending collector — scrapes https://github.com/trending (no official API).
// Returns daily + weekly trending repos with stars-gained figures.

const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36';

function decodeEntities(s) {
  return s
    .replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&nbsp;/g, ' ');
}

function parseTrendingHtml(html) {
  const repos = [];
  const articles = html.split('<article class="Box-row"');
  for (let i = 1; i < articles.length; i++) {
    const block = articles[i];
    const nameMatch = block.match(/<h2[^>]*>[\s\S]*?href="\/([^"?]+)"/);
    if (!nameMatch) continue;
    const fullName = nameMatch[1].trim();

    const descMatch = block.match(/<p class="col-9[^"]*"[^>]*>([\s\S]*?)<\/p>/);
    const description = descMatch ? decodeEntities(descMatch[1].replace(/<[^>]+>/g, '').trim()) : '';

    const langMatch = block.match(/itemprop="programmingLanguage">([^<]+)</);
    const language = langMatch ? langMatch[1].trim() : null;

    const starsMatch = block.match(/href="\/[^"]+\/stargazers"[^>]*>([\s\S]*?)<\/a>/);
    const stars = starsMatch ? starsMatch[1].replace(/<[^>]+>/g, '').trim() : null;

    const gainedMatch = block.match(/([\d,]+)\s+stars\s+(?:today|this week|this month)/);
    const starsGained = gainedMatch ? parseInt(gainedMatch[1].replace(/,/g, ''), 10) : null;

    repos.push({
      fullName,
      url: `https://github.com/${fullName}`,
      description,
      language,
      stars,
      starsGained,
    });
  }
  return repos;
}

async function fetchTrending(since) {
  const res = await fetch(`https://github.com/trending?since=${since}`, {
    headers: { 'User-Agent': UA, Accept: 'text/html' },
  });
  if (!res.ok) throw new Error(`github trending ${since}: HTTP ${res.status}`);
  const html = await res.text();
  const repos = parseTrendingHtml(html);
  if (repos.length === 0) throw new Error(`github trending ${since}: parsed 0 repos (page structure changed?)`);
  return repos;
}

export async function collectGithub() {
  const [daily, weekly] = await Promise.all([fetchTrending('daily'), fetchTrending('weekly')]);
  return { source: 'github_trending', fetchedAt: new Date().toISOString(), daily, weekly };
}
