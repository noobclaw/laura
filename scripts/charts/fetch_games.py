#!/usr/bin/env python3
"""Fetch App Store game charts (free / paid / grossing) across sub-genres and storefronts,
then enrich every app with lookup data. Output: out/games_raw.json"""
import json, os, sys, time, urllib.request

COUNTRIES = os.environ.get("COUNTRIES", "us,gb,de,jp,ca,au,tw,hk,fr,kr").split(",")
GENRES = os.environ.get("GENRES", "6014,7001,7002,7003,7004,7005,7009,7011,7012,7013,7014,7015,7016,7017,7018,7019").split(",")
CHARTS = ["topfreeapplications", "toppaidapplications", "topgrossingapplications"]
os.makedirs("out", exist_ok=True)


def get(url):
    for i in range(4):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(req, timeout=40) as r:
                return json.load(r)
        except Exception as e:
            print("retry", url, e, file=sys.stderr); time.sleep(4 * (i + 1))
    return None


apps = {}   # id -> {"charts": [...], "info": {country: lookup}}
for c in COUNTRIES:
    for g in GENRES:
        for ch in CHARTS:
            feed = get(f"https://itunes.apple.com/{c}/rss/{ch}/limit=200/genre={g}/json")
            entries = (feed or {}).get("feed", {}).get("entry", []) or []
            if isinstance(entries, dict): entries = [entries]
            for rank, e in enumerate(entries, 1):
                i = e["id"]["attributes"]["im:id"]
                a = apps.setdefault(i, {"charts": [], "info": {}, "name": e["im:name"]["label"]})
                a["charts"].append({"c": c, "g": g, "chart": ch, "rank": rank, "price": e["im:price"]["label"]})
            print(c, g, ch, len(entries), flush=True)
            time.sleep(0.3)
    ids = [i for i, a in apps.items() if any(x["c"] == c for x in a["charts"])]
    for k in range(0, len(ids), 150):
        res = get(f"https://itunes.apple.com/lookup?country={c}&id={','.join(ids[k:k+150])}") or {"results": []}
        for r in res["results"]:
            a = apps.get(str(r.get("trackId")))
            if a is None: continue
            a["info"][c] = {k2: r.get(k2) for k2 in ("trackName", "sellerName", "formattedPrice", "price", "averageUserRating",
                         "userRatingCount", "releaseDate", "currentVersionReleaseDate", "genres", "primaryGenreName",
                         "trackViewUrl", "contentAdvisoryRating", "fileSizeBytes")}
            a["info"][c]["description"] = (r.get("description") or "")[:900]
        time.sleep(1)
json.dump(apps, open("out/games_raw.json", "w"), ensure_ascii=False)
print("apps", len(apps))
