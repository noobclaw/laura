"""iTunes keyword search + competitor low-star reviews. Runs in GitHub Actions.

Env: KEYWORDS (| separated), COUNTRIES (comma), REVIEW_IDS (comma app ids), REVIEW_COUNTRIES.
Writes out/keywords.json and out/reviews.json.
"""
import json, os, time, urllib.parse, urllib.request

UA = {"User-Agent": "Mozilla/5.0"}


def get(url, tries=3):
    for i in range(tries):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=30) as r:
                return json.loads(r.read().decode("utf-8"))
        except Exception as e:  # noqa: BLE001
            last = e
            time.sleep(3 * (i + 1))
    print("FAIL", url, last)
    return None


def main():
    kws = [k.strip() for k in os.environ["KEYWORDS"].split("|") if k.strip()]
    countries = os.environ.get("COUNTRIES", "us").split(",")
    out = {}
    for c in countries:
        for kw in kws:
            q = urllib.parse.urlencode({"term": kw, "country": c, "entity": "software", "limit": 25})
            d = get(f"https://itunes.apple.com/search?{q}") or {"results": []}
            out[f"{c}|{kw}"] = [
                {
                    "rank": i + 1, "id": a.get("trackId"), "name": a.get("trackName"),
                    "seller": a.get("sellerName"), "price": a.get("formattedPrice"),
                    "ratings": a.get("userRatingCount"), "rating": a.get("averageUserRating"),
                    "genre": a.get("primaryGenreName"), "updated": a.get("currentVersionReleaseDate"),
                    "released": a.get("releaseDate"), "size": a.get("fileSizeBytes"),
                }
                for i, a in enumerate(d.get("results", []))
            ]
            time.sleep(1.5)
    os.makedirs("out", exist_ok=True)
    json.dump(out, open("out/keywords.json", "w"), ensure_ascii=False, indent=1)

    reviews = {}
    ids = [x for x in os.environ.get("REVIEW_IDS", "").split(",") if x]
    for c in os.environ.get("REVIEW_COUNTRIES", "us").split(","):
        for app in ids:
            rows = []
            for page in range(1, 11):
                d = get(f"https://itunes.apple.com/{c}/rss/customerreviews/page={page}/id={app}/sortby=mostrecent/json")
                entries = (d or {}).get("feed", {}).get("entry", [])
                if isinstance(entries, dict):
                    entries = [entries]
                ents = [e for e in entries if "im:rating" in e]
                if not ents:
                    break
                for e in ents:
                    rows.append({
                        "rating": int(e["im:rating"]["label"]), "title": e["title"]["label"],
                        "text": e["content"]["label"][:600], "version": e.get("im:version", {}).get("label"),
                        "date": e.get("updated", {}).get("label"),
                    })
                time.sleep(1.5)
            reviews[f"{c}|{app}"] = rows
    json.dump(reviews, open("out/reviews.json", "w"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
