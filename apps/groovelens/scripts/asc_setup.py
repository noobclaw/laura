#!/usr/bin/env python3
"""Make sure App Store Connect has what a TestFlight upload of Groovelens needs.

- Checks the app record for the bundle id exists (the API cannot create app records).
- Creates the non-consumable Pro in-app purchase if missing: localizations, USD 9.99 price,
  availability in every territory.

Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH. Exit 2 = app record missing.
"""
import json, os, sys, time, urllib.request, urllib.error
import jwt  # PyJWT

BUNDLE_ID = "com.noobclaw.groovelens"
PRODUCT_ID = "com.noobclaw.groovelens.pro_unlock"
USD_PRICE = "9.99"
LOCALIZATIONS = {
    "en-US": ("Groovelens Pro", "Unlimited songs, Kit mode, exports and all stages."),
    "zh-Hant": ("Groovelens Pro", "無限歌曲、真鼓模式、匯出與所有舞台。"),
    "zh-Hans": ("Groovelens Pro", "无限歌曲、真鼓模式、导出与所有舞台。"),
    "ja": ("Groovelens Pro", "曲数無制限、キットモード、書き出し、全ステージ。"),
    "ko": ("Groovelens Pro", "곡 무제한, 키트 모드, 내보내기, 모든 스테이지."),
    "de-DE": ("Groovelens Pro", "Unbegrenzt Songs, Kit-Modus, Export, alle Bühnen."),
    "fr-FR": ("Groovelens Pro", "Morceaux illimités, mode Batterie, exports, scènes."),
    "es-ES": ("Groovelens Pro", "Canciones ilimitadas, modo Batería y exportación."),
    "pt-BR": ("Groovelens Pro", "Músicas ilimitadas, modo Bateria e exportação."),
    "it": ("Groovelens Pro", "Brani illimitati, modalità Batteria, esportazione."),
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


def main():
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
            "attributes": {"name": "Groovelens Pro", "productId": PRODUCT_ID, "inAppPurchaseType": "NON_CONSUMABLE",
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
