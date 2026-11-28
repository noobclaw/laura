#!/usr/bin/env python3
"""Report, for every app in the account, which EU storefronts it is (not) available in."""
import json, os, time, urllib.request, urllib.error
import jwt

BASE = "https://api.appstoreconnect.apple.com"
EU = {"AUT","BEL","BGR","HRV","CYP","CZE","DNK","EST","FIN","FRA","DEU","GRC","HUN","IRL","ITA","LVA","LTU",
      "LUX","MLT","NLD","POL","PRT","ROU","SVK","SVN","ESP","SWE"}


def token():
    now = int(time.time())
    return jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"},
                      open(os.environ["ASC_KEY_PATH"]).read(), algorithm="ES256",
                      headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


def call(path):
    url = path if path.startswith("http") else BASE + path
    req = urllib.request.Request(url, headers={"Authorization": "Bearer " + token()})
    try:
        with urllib.request.urlopen(req) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        return {"error": e.code, "detail": e.read().decode()[:300]}


def pages(path):
    out = []
    while path:
        p = call(path)
        if "error" in p:
            return p
        out += p.get("data", []); out_inc = p.get("included", [])
        pages.included = getattr(pages, "included", []) + out_inc
        path = p.get("links", {}).get("next")
    return out


apps = pages("/v1/apps?limit=200&fields[apps]=name,bundleId")
for a in apps:
    name = a["attributes"]["name"]
    av = call(f"/v1/apps/{a['id']}/appAvailabilityV2")
    if "error" in av:
        print(f"{name}: no availability set ({av['error']})"); continue
    pages.included = []
    terr = pages(f"/v2/appAvailabilities/{av['data']['id']}/territoryAvailabilities?limit=200&include=territory")
    if isinstance(terr, dict):
        print(f"{name}: error {terr}"); continue
    eu = [t for t in terr if t["relationships"]["territory"]["data"]["id"] in EU]
    avail = sum(1 for t in terr if t["attributes"].get("available"))
    eu_on = [t for t in eu if t["attributes"].get("available")]
    statuses = sorted({s for t in eu for s in (t["attributes"].get("contentStatuses") or [])})
    print(f"{name}: territories available {avail}/{len(terr)}; EU available {len(eu_on)}/{len(eu)}; EU statuses {statuses}")
