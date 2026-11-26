#!/usr/bin/env python3
"""Make sure App Store Connect has what a TestFlight upload of Accord needs.

- Checks the app record for the bundle id exists (the API cannot create app records).
- Creates the non-consumable Pro in-app purchase if missing: localizations, USD 9.99 price,
  availability in every territory.

Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH. Exit 2 = app record missing.
"""
import json, os, sys, time, urllib.request, urllib.error
import jwt  # PyJWT

BUNDLE_ID = "com.noobclaw.accord"
PRODUCT_ID = "com.noobclaw.accord.pro_unlock"
USD_PRICE = "9.99"
LOCALIZATIONS = {
    "en-US": ("Accord Pro", "Unlimited formulas, bases, batches, cost and export."),
    "zh-Hant": ("Accord Pro", "無限配方、基底、批次熟成、成本、版本比較、匯出。"),
    "zh-Hans": ("Accord Pro", "无限配方、基底、批次熟成、成本、版本比较、导出。"),
    "ja": ("Accord Pro", "処方無制限、ベース、バッチ、コスト、比較、書き出し。"),
    "ko": ("Accord Pro", "무제한 처방, 베이스, 배치, 원가, 비교, 내보내기."),
    "de-DE": ("Accord Pro", "Unbegrenzt Rezepte, Basen, Chargen, Kosten, Export."),
    "fr-FR": ("Accord Pro", "Formules illimitées, bases, lots, coût, export."),
    "es-ES": ("Accord Pro", "Fórmulas ilimitadas, bases, lotes, coste, exportar."),
    "pt-BR": ("Accord Pro", "Fórmulas ilimitadas, bases, lotes, custo, exportar."),
    "it": ("Accord Pro", "Formule illimitate, basi, lotti, costi, esporta."),
}
BASE = "https://api.appstoreconnect.apple.com"


def token():
    key = open(os.environ["ASC_KEY_PATH"]).read()
    now = int(time.time())
    return jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"},
                      key, algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


def call(method, path, body=None):
    req = urllib.request.Request(BASE + path, method=method, data=json.dumps(body).encode() if body else None,
                                 headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode()
        raise SystemExit(f"{method} {path} -> HTTP {e.code}\n{detail}")


def ensure_bundle_id():
    ids = call("GET", f"/v1/bundleIds?filter[identifier]={BUNDLE_ID}")["data"]
    if any(i["attributes"]["identifier"] == BUNDLE_ID for i in ids):
        return
    call("POST", "/v1/bundleIds", {"data": {"type": "bundleIds", "attributes": {
        "identifier": BUNDLE_ID, "name": "Accord", "platform": "IOS"}}})
    print("registered bundle id", BUNDLE_ID)


def main():
    ensure_bundle_id()
    apps = call("GET", f"/v1/apps?filter[bundleId]={BUNDLE_ID}")["data"]
    if not apps:
        print(f"APP_RECORD_MISSING: no App Store Connect app for {BUNDLE_ID}. Create it in the web UI "
              "(My Apps → + → New App, iOS, English (U.S.), this bundle id).")
        sys.exit(2)
    app_id = apps[0]["id"]
    print("app record:", app_id, apps[0]["attributes"].get("name"))

    found = call("GET", f"/v1/apps/{app_id}/inAppPurchasesV2?filter[productId]={PRODUCT_ID}")["data"]
    if found:
        iap_id = found[0]["id"]
        print("in-app purchase exists:", iap_id, found[0]["attributes"].get("state"))
    else:
        iap = call("POST", "/v2/inAppPurchases", {"data": {
            "type": "inAppPurchases",
            "attributes": {"name": "Accord Pro", "productId": PRODUCT_ID, "inAppPurchaseType": "NON_CONSUMABLE",
                           "familySharable": True,
                           "reviewNote": "One-time unlock. Tap any Pro badge (for example Kit mode on a song page) to open the paywall."},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})
        iap_id = iap["data"]["id"]
        print("created in-app purchase:", iap_id)

    have = {l["attributes"]["locale"] for l in call("GET", f"/v2/inAppPurchases/{iap_id}/inAppPurchaseLocalizations")["data"]}
    for locale, (name, desc) in LOCALIZATIONS.items():
        if locale in have:
            continue
        call("POST", "/v1/inAppPurchaseLocalizations", {"data": {
            "type": "inAppPurchaseLocalizations", "attributes": {"locale": locale, "name": name, "description": desc},
            "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iap_id}}}}})
        print("added localization", locale)

    try:
        schedule = call("GET", f"/v2/inAppPurchases/{iap_id}/iapPriceSchedule")
        has_price = bool(schedule.get("data"))
    except SystemExit:
        has_price = False
    if not has_price:
        point = None
        path = f"/v2/inAppPurchases/{iap_id}/pricePoints?filter[territory]=USA&limit=200"
        while path and not point:
            page = call("GET", path)
            point = next((p["id"] for p in page["data"] if p["attributes"]["customerPrice"] == USD_PRICE), None)
            nxt = page.get("links", {}).get("next")
            path = nxt.replace(BASE, "") if nxt else None
        if not point:
            raise SystemExit(f"no USD {USD_PRICE} price point found")
        call("POST", "/v1/inAppPurchasePriceSchedules", {
            "data": {"type": "inAppPurchasePriceSchedules", "relationships": {
                "inAppPurchase": {"data": {"type": "inAppPurchases", "id": iap_id}},
                "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
                "manualPrices": {"data": [{"type": "inAppPurchasePrices", "id": "${price0}"}]}}},
            "included": [{"type": "inAppPurchasePrices", "id": "${price0}", "attributes": {"startDate": None},
                          "relationships": {"inAppPurchasePricePoint": {"data": {"type": "inAppPurchasePricePoints", "id": point}}}}]})
        print("set price USD", USD_PRICE)
    else:
        print("price schedule exists")

    try:
        avail = call("GET", f"/v2/inAppPurchases/{iap_id}/inAppPurchaseAvailability")
        has_avail = bool(avail.get("data"))
    except SystemExit:
        has_avail = False
    if not has_avail:
        territories, path = [], "/v1/territories?limit=200"
        while path:
            page = call("GET", path)
            territories += [{"type": "territories", "id": t["id"]} for t in page["data"]]
            nxt = page.get("links", {}).get("next")
            path = nxt.replace(BASE, "") if nxt else None
        call("POST", "/v1/inAppPurchaseAvailabilities", {"data": {
            "type": "inAppPurchaseAvailabilities", "attributes": {"availableInNewTerritories": True},
            "relationships": {"inAppPurchase": {"data": {"type": "inAppPurchases", "id": iap_id}},
                              "availableTerritories": {"data": territories}}}})
        print("available in", len(territories), "territories")
    else:
        print("availability exists")


if __name__ == "__main__":
    main()
