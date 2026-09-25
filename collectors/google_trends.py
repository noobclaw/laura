"""Demand check for today's candidate words: Google Trends + Google suggest,
read against competition (rule 5 of kb/选题规矩/立项前挑刺关.md, 2026-09-25).

Not part of run_all.mjs on purpose: it only runs for the handful of words the
day's report is actually scoring, never as a full scan.

Usage:
  python collectors/google_trends.py "embroidery digitizing" "embroidery app" "pes file"
  python collectors/google_trends.py --country cn "数控车床编程"     # CN: Trends skipped, Baidu suggest + iTunes cn only
  python collectors/google_trends.py --date 2026-09-25 ...          # output folder, default = local today

Writes data/<date>/google_trends.json (merged with earlier runs of the same day)
and prints a markdown table for the report.

Reading the numbers (the rule, not a suggestion):
  - heat      = 12-month US mean on Trends (raw, only comparable inside its batch).
  - vsAnchor  = heat / anchorHeat * 100. Every batch carries ANCHOR, so this is
                the number that compares across batches and days (anchor = 100).
  - toolIntent = suggest list contains app/free/calculator/... ; none -> demand
                is doubtful, deduct.
  - topReviews = largest userRatingCount among the top 10 iTunes results for the
                word. It is a proxy: the report must still name the true
                same-kind head app by hand before quoting it.
  - heatPerCompetition = vsAnchor / max(1, topReviews / 1000). High heat with high
                competition is a red ocean (the anchor itself: guitar tuner, crowded).
"""

import argparse
import datetime as dt
import json
import os
import sys
import time
import urllib.parse
import urllib.request

ANCHOR = "guitar tuner"
BATCH = 4  # Trends takes at most 5 words per request; 1 slot is the anchor
TOOL_INTENT = ("app", "free", "calculator", "optimizer", "generator", "software",
               "online", "tool", "converter", "maker", "tracker", "planner", "simulator")
# CN: Google suggest answers an empty list for Chinese words (09-25 probe), so the
# cn path reads Baidu's suggest instead; Chinese has no word boundaries, so its
# intent words match as substrings.
TOOL_INTENT_ZH = ("app", "软件", "计算器", "下载", "免费", "手机版", "宝典", "工具", "助手")
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def http_json(url, timeout=20):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    raw = urllib.request.urlopen(req, timeout=timeout).read()
    return json.loads(raw.decode("utf-8", "ignore"))


def trends(words):
    """Returns {word: 12-month mean} with ANCHOR in every batch; {} if pytrends is unusable."""
    try:
        from pytrends.request import TrendReq
    except ImportError:
        print("[warn] pytrends not installed: pip install pytrends", file=sys.stderr)
        return {}, "pytrends not installed"
    out, err = {}, None
    p = TrendReq(hl="en-US", tz=0, timeout=(10, 25))
    for i in range(0, len(words), BATCH):
        kws = [ANCHOR] + [w for w in words[i:i + BATCH] if w != ANCHOR]
        last = None
        for attempt in range(3):
            try:
                p.build_payload(kws, timeframe="today 12-m", geo="US")
                df = p.interest_over_time()
                a = float(df[ANCHOR].mean()) if ANCHOR in df else 0.0
                for k in kws:
                    m = float(df[k].mean()) if k in df else 0.0
                    # Trends rescales every batch to its own max, so the raw mean
                    # only compares within one batch. vsAnchor (anchor = 100) is
                    # the number that compares across batches and days.
                    out[k] = {"heat": round(m, 1), "anchorHeat": round(a, 1),
                              "vsAnchor": round(m / a * 100, 1) if a else None}
                break
            except Exception as e:  # 429 is the usual one; the rule says wait >= 60s
                last = f"{type(e).__name__}: {e}"
                print(f"[warn] trends batch {kws}: {last}; retry in 70s", file=sys.stderr)
                time.sleep(70)
        else:  # every attempt failed: only then is it an error worth recording
            err = f"batch {kws[1:]}: {last}"
        if i + BATCH < len(words):
            time.sleep(8)
    return out, err


def suggest(word, country):
    if country == "cn":
        u = "https://suggestion.baidu.com/su?action=opensearch&ie=utf-8&wd=" + urllib.parse.quote(word + " ")
    else:
        u = ("https://suggestqueries.google.com/complete/search?client=firefox"
             "&hl=en&gl=us&q=" + urllib.parse.quote(word + " "))
    try:
        return http_json(u, 15)[1][:10], None
    except Exception as e:
        return [], f"{type(e).__name__}: {e}"


def itunes_head(word, country):
    u = ("https://itunes.apple.com/search?entity=software&limit=10"
         f"&country={country}&term=" + urllib.parse.quote(word))
    try:
        res = http_json(u).get("results", [])
    except Exception as e:
        return None, [], f"{type(e).__name__}: {e}"
    head = sorted(res, key=lambda a: a.get("userRatingCount") or 0, reverse=True)[:3]
    top = [{"name": a.get("trackName"), "price": a.get("formattedPrice"),
            "rating": round(a.get("averageUserRating") or 0, 2),
            "reviews": a.get("userRatingCount") or 0} for a in head]
    return (top[0]["reviews"] if top else 0), top, None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("words", nargs="+")
    ap.add_argument("--country", default="us", choices=["us", "cn"])
    ap.add_argument("--date", default=dt.date.today().isoformat())
    a = ap.parse_args()

    words = list(dict.fromkeys(w.strip() for w in a.words if w.strip()))
    heat, trends_err = ({}, "skipped for cn (use Baidu index or skip, per rule 5)") \
        if a.country == "cn" else trends(words)

    rows = []
    for w in words:
        sug, sug_err = suggest(w, a.country)
        if a.country == "cn":
            intent = sorted({t for s in sug for t in TOOL_INTENT_ZH if t in s.lower()})
        else:
            intent = sorted({t for s in sug for t in TOOL_INTENT if t in s.lower().split()})
        top_reviews, head, it_err = itunes_head(w, a.country)
        t = heat.get(w) or {}
        h = t.get("vsAnchor")
        ratio = round(h / max(1.0, (top_reviews or 0) / 1000), 2) if h is not None and top_reviews is not None else None
        rows.append({"word": w, "country": a.country, "heat": t.get("heat"), "anchor": ANCHOR,
                     "anchorHeat": t.get("anchorHeat"), "vsAnchor": h, "suggest": sug, "toolIntent": intent,
                     "topReviews": top_reviews, "itunesHead": head, "heatPerCompetition": ratio,
                     "errors": {k: v for k, v in (("suggest", sug_err), ("itunes", it_err)) if v}})
        time.sleep(1)

    out_dir = os.path.join(ROOT, "data", a.date)
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "google_trends.json")
    prev = {"rows": []}
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            prev = json.load(f)
    keep = [r for r in prev.get("rows", []) if (r["word"], r["country"]) not in {(w, a.country) for w in words}]
    doc = {"source": "google_trends", "fetchedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
           "anchor": ANCHOR, "trendsError": trends_err, "rows": keep + rows}
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(doc, f, ensure_ascii=False, indent=2)

    print(f"| 词 | 区 | 热度(锚 {ANCHOR}=100) | 工具意图联想 | 头部评价数(iTunes {a.country}) | 热度/竞争 |")
    print("|---|---|---|---|---|---|")
    for r in rows:
        print(f"| {r['word']} | {r['country']} | {r['vsAnchor'] if r['vsAnchor'] is not None else '—'} | "
              f"{' / '.join(r['toolIntent']) or '无 → 扣分'} | {r['topReviews']} | "
              f"{r['heatPerCompetition'] if r['heatPerCompetition'] is not None else '—'} |")
    if trends_err:
        print(f"\n[trends] {trends_err}", file=sys.stderr)
    print(f"\n→ {path}", file=sys.stderr)


if __name__ == "__main__":
    main()
