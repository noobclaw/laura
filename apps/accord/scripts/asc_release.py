#!/usr/bin/env python3
"""App Store Connect release automation for Accord (same flow as Groovelens).

  asc_release.py meta     -> listing (10 locales), categories, content rights, age rating (copied from an
                              existing app of this account), review contact (copied too), price (free),
                              screenshots, IAP review screenshot, build selection.
  asc_release.py submit   -> review submission (reuses an open draft).

App Privacy ("Data Not Collected") and territory availability are done in the web UI.
Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH, BUILD_NUMBER.
"""
import hashlib, json, os, sys, time, urllib.parse, urllib.request, urllib.error
import jwt

BUNDLE_ID = "com.noobclaw.accord"
PRODUCT_ID = "com.noobclaw.accord.pro_unlock"
HERE = os.path.dirname(os.path.abspath(__file__))
STORE = os.path.join(HERE, "..", "store")
BASE = "https://api.appstoreconnect.apple.com"
PRIVACY_URL = "https://256btc.com/privacy/accord/"
SUPPORT_URL = "https://256btc.com/support/"

sys.path.insert(0, STORE)
from listing import EN_DESC, PRO_LINE, LOCALES, SHOT_DIRS, REVIEW_NOTES  # noqa: E402


def token():
    now = int(time.time())
    return jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"},
                      open(os.environ["ASC_KEY_PATH"]).read(), algorithm="ES256",
                      headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


def call(method, path, body=None, ok404=False):
    url = path if path.startswith("http") else BASE + path
    req = urllib.request.Request(url, method=method, data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode()
        if ok404 and e.code == 404:
            return None
        print(f"!! {method} {path} -> HTTP {e.code}\n{detail[:2000]}")
        raise


def all_pages(path):
    out = []
    while path:
        page = call("GET", path)
        out += page.get("data", [])
        path = page.get("links", {}).get("next")
    return out


def upload(reserve_path, rel_key, rel_type, rel_id, file_path, res_type):
    data = open(file_path, "rb").read()
    res = call("POST", reserve_path, {"data": {"type": res_type,
        "attributes": {"fileName": os.path.basename(file_path), "fileSize": len(data)},
        "relationships": {rel_key: {"data": {"type": rel_type, "id": rel_id}}}}})["data"]
    for op in res["attributes"]["uploadOperations"]:
        chunk = data[op["offset"]:op["offset"] + op["length"]]
        req = urllib.request.Request(op["url"], method=op["method"], data=chunk,
                                     headers={h["name"]: h["value"] for h in op.get("requestHeaders", [])})
        urllib.request.urlopen(req).read()
    call("PATCH", f"{reserve_path}/{res['id']}", {"data": {"type": res_type, "id": res["id"],
         "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
    return res["id"]


def editable(items, key="appStoreState"):
    for it in items:
        st = it["attributes"].get(key) or it["attributes"].get("state")
        if st in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "WAITING_FOR_REVIEW", None):
            return it
    return items[0]


def meta(app_id):
    # Reference app of the same account (for age rating + review contact).
    ref = None
    for a in all_pages("/v1/apps?limit=50"):
        if a["id"] != app_id:
            vers = call("GET", f"/v1/apps/{a['id']}/appStoreVersions?filter[platform]=IOS&limit=5")["data"]
            live = [v for v in vers if v["attributes"].get("appStoreState") in ("READY_FOR_SALE", "READY_FOR_DISTRIBUTION")]
            if live:
                ref = (a, live[0]); break
    print("reference app:", ref[0]["attributes"]["name"] if ref else None)

    call("PATCH", f"/v1/apps/{app_id}", {"data": {"type": "apps", "id": app_id,
         "attributes": {"contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT"}}})
    print("content rights set")

    info = editable(call("GET", f"/v1/apps/{app_id}/appInfos")["data"], "appStoreState")
    call("PATCH", f"/v1/appInfos/{info['id']}", {"data": {"type": "appInfos", "id": info["id"], "relationships": {
        "primaryCategory": {"data": {"type": "appCategories", "id": "PRODUCTIVITY"}},
        "secondaryCategory": {"data": {"type": "appCategories", "id": "LIFESTYLE"}}}}})
    print("categories set")

    have = {l["attributes"]["locale"]: l["id"] for l in call("GET", f"/v1/appInfos/{info['id']}/appInfoLocalizations?limit=50")["data"]}
    for loc, (name, sub, _, _) in LOCALES.items():
        attrs = {"name": name, "subtitle": sub, "privacyPolicyUrl": PRIVACY_URL}
        if loc in have:
            call("PATCH", f"/v1/appInfoLocalizations/{have[loc]}", {"data": {"type": "appInfoLocalizations", "id": have[loc], "attributes": attrs}})
        else:
            call("POST", "/v1/appInfoLocalizations", {"data": {"type": "appInfoLocalizations", "attributes": {"locale": loc, **attrs},
                 "relationships": {"appInfo": {"data": {"type": "appInfos", "id": info["id"]}}}}})
        print("app info", loc)

    # Age rating: copy the reference app's answers (both are 4+ utility/music apps with no objectionable content).
    decl = call("GET", f"/v1/appInfos/{info['id']}/ageRatingDeclaration")["data"]
    if ref:
        rinfo = call("GET", f"/v1/apps/{ref[0]['id']}/appInfos")["data"][0]
        rdecl = call("GET", f"/v1/appInfos/{rinfo['id']}/ageRatingDeclaration")["data"]
        attrs = {k: v for k, v in rdecl["attributes"].items() if v is not None}
        if "ageRatingOverrideV2" in attrs:
            attrs.pop("ageRatingOverride", None)   # v1 and v2 overrides cannot both be sent
        call("PATCH", f"/v1/ageRatingDeclarations/{decl['id']}", {"data": {"type": "ageRatingDeclarations", "id": decl["id"], "attributes": attrs}})
        print("age rating copied:", len(attrs), "answers")

    ver = editable(call("GET", f"/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS")["data"])
    vid = ver["id"]
    print("version", ver["attributes"]["versionString"], ver["attributes"].get("appStoreState"))
    builds = call("GET", f"/v1/builds?filter[app]={app_id}&filter[version]={os.environ['BUILD_NUMBER']}")["data"]
    if not builds:
        raise SystemExit("build not found")
    print("build", builds[0]["attributes"]["version"], builds[0]["attributes"]["processingState"])
    call("PATCH", f"/v1/appStoreVersions/{vid}", {"data": {"type": "appStoreVersions", "id": vid,
         "attributes": {"copyright": "2026 noobclaw", "releaseType": "AFTER_APPROVAL"},
         "relationships": {"build": {"data": {"type": "builds", "id": builds[0]["id"]}}}}})
    print("build attached, copyright set")

    vhave = {l["attributes"]["locale"]: l["id"] for l in call("GET", f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations?limit=50")["data"]}
    for loc, (name, sub, kw, intro) in LOCALES.items():
        desc = EN_DESC if intro is None else intro + "\n\n" + PRO_LINE[loc]
        attrs = {"description": desc, "keywords": kw, "supportUrl": SUPPORT_URL,
                 "promotionalText": sub}
        if loc in vhave:
            call("PATCH", f"/v1/appStoreVersionLocalizations/{vhave[loc]}", {"data": {"type": "appStoreVersionLocalizations", "id": vhave[loc], "attributes": attrs}})
        else:
            r = call("POST", "/v1/appStoreVersionLocalizations", {"data": {"type": "appStoreVersionLocalizations", "attributes": {"locale": loc, **attrs},
                     "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
            vhave[loc] = r["data"]["id"]
        print("version text", loc)

    for loc, folder in SHOT_DIRS.items():
        lid = vhave[loc]
        sets = call("GET", f"/v1/appStoreVersionLocalizations/{lid}/appScreenshotSets")["data"]
        s = next((x for x in sets if x["attributes"]["screenshotDisplayType"] == "APP_IPHONE_67"), None)
        if s:
            for shot in call("GET", f"/v1/appScreenshotSets/{s['id']}/appScreenshots")["data"]:
                call("DELETE", f"/v1/appScreenshots/{shot['id']}")
            sid = s["id"]
        else:
            sid = call("POST", "/v1/appScreenshotSets", {"data": {"type": "appScreenshotSets",
                       "attributes": {"screenshotDisplayType": "APP_IPHONE_67"},
                       "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": lid}}}}})["data"]["id"]
        d = os.path.join(STORE, "screenshots", folder)
        for f in sorted(os.listdir(d)):
            upload("/v1/appScreenshots", "appScreenshotSet", "appScreenshotSets", sid, os.path.join(d, f), "appScreenshots")
        print("screenshots", loc, len(os.listdir(d)))

    # Review contact copied from the reference app.
    if ref:
        rd = call("GET", f"/v1/appStoreVersions/{ref[1]['id']}/appStoreReviewDetail", ok404=True)
        contact = {k: rd["data"]["attributes"].get(k) for k in ("contactFirstName", "contactLastName", "contactPhone", "contactEmail")} if rd and rd.get("data") else {}
    else:
        contact = {}
    attrs = {**{k: v for k, v in contact.items() if v}, "demoAccountRequired": False, "notes": REVIEW_NOTES}
    mine = call("GET", f"/v1/appStoreVersions/{vid}/appStoreReviewDetail", ok404=True)
    if mine and mine.get("data"):
        call("PATCH", f"/v1/appStoreReviewDetails/{mine['data']['id']}", {"data": {"type": "appStoreReviewDetails", "id": mine["data"]["id"], "attributes": attrs}})
    else:
        call("POST", "/v1/appStoreReviewDetails", {"data": {"type": "appStoreReviewDetails", "attributes": attrs,
             "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
    print("review detail set; contact fields:", sorted(k for k, v in contact.items() if v))

    # Free app.
    sched = call("GET", f"/v1/apps/{app_id}/appPriceSchedule", ok404=True)
    if not sched or not sched.get("data"):
        pts = call("GET", f"/v1/apps/{app_id}/appPricePoints?filter[territory]=USA&limit=10")["data"]
        free = next(p["id"] for p in pts if float(p["attributes"]["customerPrice"]) == 0)
        call("POST", "/v1/appPriceSchedules", {"data": {"type": "appPriceSchedules", "relationships": {
            "app": {"data": {"type": "apps", "id": app_id}},
            "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
            "manualPrices": {"data": [{"type": "appPrices", "id": "${p0}"}]}}},
            "included": [{"type": "appPrices", "id": "${p0}", "attributes": {"startDate": None},
                          "relationships": {"appPricePoint": {"data": {"type": "appPricePoints", "id": free}}}}]})
        print("price: free")
    else:
        print("price schedule exists")

    iap = call("GET", f"/v1/apps/{app_id}/inAppPurchasesV2?filter[productId]={PRODUCT_ID}")["data"][0]
    shot = call("GET", f"/v2/inAppPurchases/{iap['id']}/appStoreReviewScreenshot", ok404=True)
    if not shot or not shot.get("data"):
        upload("/v1/inAppPurchaseAppStoreReviewScreenshots", "inAppPurchaseV2", "inAppPurchases", iap["id"],
               os.path.join(STORE, "screenshots", "iap-review.jpg"), "inAppPurchaseAppStoreReviewScreenshots")
        print("IAP review screenshot uploaded")
    call("PATCH", f"/v2/inAppPurchases/{iap['id']}", {"data": {"type": "inAppPurchases", "id": iap["id"],
         "attributes": {"reviewNote": "Non-consumable one-time unlock. Open any song, tap Kit mode (PRO) to see the paywall. Restore Purchases is on the paywall and in Settings."}}})
    print("IAP state:", iap["attributes"].get("state"))


def submit(app_id):
    ver = editable(call("GET", f"/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS")["data"])
    # Reuse the open draft (the first non-consumable IAP was added there in the web UI).
    subs = call("GET", f"/v1/reviewSubmissions?filter[app]={app_id}&filter[platform]=IOS&filter[state]=READY_FOR_REVIEW")["data"]
    if subs:
        sub = subs[0]
        print("reusing draft", sub["id"])
    else:
        sub = call("POST", "/v1/reviewSubmissions", {"data": {"type": "reviewSubmissions", "attributes": {"platform": "IOS"},
                   "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})["data"]
        print("new draft", sub["id"])
    items = call("GET", f"/v1/reviewSubmissions/{sub['id']}/items?include=appStoreVersion")["data"]
    has_ver = any((it.get("relationships", {}).get("appStoreVersion") or {}).get("data") for it in items)
    kinds = (["appStoreVersion"] if has_ver else []) + (["inAppPurchaseV2"] if len(items) > int(has_ver) else [])
    print("draft items:", len(items), kinds)
    if "appStoreVersion" not in kinds:
        call("POST", "/v1/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems", "relationships": {
            "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub["id"]}},
            "appStoreVersion": {"data": {"type": "appStoreVersions", "id": ver["id"]}}}}})
        print("version added")
    if "inAppPurchaseV2" not in kinds:
        iap = call("GET", f"/v1/apps/{app_id}/inAppPurchasesV2?filter[productId]={PRODUCT_ID}")["data"][0]
        try:
            call("POST", "/v1/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems", "relationships": {
                "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub["id"]}},
                "inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iap["id"]}}}}})
            print("IAP added")
        except urllib.error.HTTPError:
            print("!! IAP could not be added to the draft")
    r = call("PATCH", f"/v1/reviewSubmissions/{sub['id']}", {"data": {"type": "reviewSubmissions", "id": sub["id"], "attributes": {"submitted": True}}})
    print("SUBMITTED:", r["data"]["attributes"].get("state"))


TESTER_EMAILS = ["284726777@qq.com", "zitaa233@163.com"]


def testers(app_id):
    """Internal TestFlight group with every build, plus the team's testers."""
    groups = call("GET", f"/v1/apps/{app_id}/betaGroups")["data"]
    group = next((g for g in groups if g["attributes"].get("isInternalGroup")), None)
    if group is None:
        group = call("POST", "/v1/betaGroups", {"data": {"type": "betaGroups", "attributes": {
            "name": "Internal", "isInternalGroup": True, "hasAccessToAllBuilds": True},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})["data"]
        print("created internal group", group["id"])
    else:
        print("internal group", group["id"], group["attributes"]["name"])
    ids = []
    for email in TESTER_EMAILS:
        found = call("GET", f"/v1/betaTesters?filter[email]={urllib.parse.quote(email)}")["data"]
        if found:
            ids.append(found[0]["id"])
            print("tester", email, found[0]["id"])
        else:
            print("!! no tester record for", email)
    if ids:
        try:
            call("POST", f"/v1/betaGroups/{group['id']}/relationships/betaTesters",
                 {"data": [{"type": "betaTesters", "id": i} for i in ids]})
            print("testers added")
        except urllib.error.HTTPError as e:
            print("!! add testers:", e.code)


if __name__ == "__main__":
    app = call("GET", f"/v1/apps?filter[bundleId]={BUNDLE_ID}")["data"][0]
    print("app", app["id"], app["attributes"]["name"])
    {"meta": meta, "submit": submit, "testers": testers}[sys.argv[1]](app["id"])
