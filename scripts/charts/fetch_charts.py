#!/usr/bin/env python3
"""Fetch App Store top-paid charts for a genre and enrich them with lookup data.

Apple's public chart feed returns at most 200 entries per country/genre.
Writes out/<country>-<genre>.json and out/<country>-<genre>.csv
"""
import csv, json, os, sys, time, urllib.request

GENRE = os.environ.get("GENRE", "6002")          # 6002 = Utilities
COUNTRIES = os.environ.get("COUNTRIES", "us").split(",")
CHART = os.environ.get("CHART", "toppaidapplications")
OUT = "out"
os.makedirs(OUT, exist_ok=True)


def get(url):
    for i in range(4):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(req, timeout=40) as r:
                return json.load(r)
        except Exception as e:
            print("retry", url, e, file=sys.stderr)
            time.sleep(5 * (i + 1))
    raise SystemExit("failed " + url)


for c in COUNTRIES:
    feed = get(f"https://itunes.apple.com/{c}/rss/{CHART}/limit=200/genre={GENRE}/json")
    entries = feed["feed"].get("entry", [])
    ids = [e["id"]["attributes"]["im:id"] for e in entries]
    info = {}
    for i in range(0, len(ids), 150):
        res = get(f"https://itunes.apple.com/lookup?country={c}&id={','.join(ids[i:i+150])}")
        for r in res["results"]:
            info[str(r["trackId"])] = r
        time.sleep(2)
    rows = []
    for rank, (e, i) in enumerate(zip(entries, ids), 1):
        r = info.get(i, {})
        rows.append({
            "rank": rank, "id": i, "name": e["im:name"]["label"],
            "developer": e["im:artist"]["label"],
            "price": r.get("formattedPrice") or e["im:price"]["label"],
            "rating": round(r.get("averageUserRating", 0), 2),
            "ratings": r.get("userRatingCount", 0),
            "released": (r.get("releaseDate") or "")[:10],
            "updated": (r.get("currentVersionReleaseDate") or "")[:10],
            "version": r.get("version", ""),
            "genres": "/".join(r.get("genres", [])),
            "iap": "inAppPurchase" in json.dumps(r.get("features", [])) or None,
            "url": r.get("trackViewUrl", "").split("?")[0],
            "description": (r.get("description") or "")[:600].replace("\n", " "),
        })
    base = f"{OUT}/{c}-{CHART}-{GENRE}"
    json.dump(rows, open(base + ".json", "w"), ensure_ascii=False, indent=1)
    with open(base + ".csv", "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader(); w.writerows(rows)
    print(c, len(rows))
