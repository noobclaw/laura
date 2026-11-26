#!/usr/bin/env python3
"""App Store Connect release automation for Groovelens.

  asc_release.py meta     -> listing (10 locales), categories, content rights, age rating (copied from an
                              existing app of this account), review contact (copied too), price (free),
                              screenshots, IAP review screenshot, build selection.
  asc_release.py submit   -> IAP submission + app version review submission.

App Privacy ("Data Not Collected") and territory availability are done in the web UI.
Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH, BUILD_NUMBER.
"""
import hashlib, json, os, sys, time, urllib.request, urllib.error
import jwt

BUNDLE_ID = "com.noobclaw.groovelens"
PRODUCT_ID = "com.noobclaw.groovelens.pro_unlock"
HERE = os.path.dirname(os.path.abspath(__file__))
STORE = os.path.join(HERE, "..", "store")
BASE = "https://api.appstoreconnect.apple.com"
PRIVACY_URL = "https://256btc.com/privacy/groovelens/"
SUPPORT_URL = "https://256btc.com/support/"

EN_DESC = """Drop in any song and play its drums.

Groovelens listens to a track, separates the drums from the rest of the mix, finds the beat and writes a readable drum chart. Then it turns that chart into a rhythm game you can play on screen or on your real kit.

• Import an audio file, a rehearsal video from Photos, or record your band
• Analysis runs entirely on this iPhone. Nothing is uploaded, no account
• Drum chart with kick, snare, hi-hat, toms, ride and crash. Tap to fix any hit
• Practice with the full mix, the song without drums, or the drums alone
• Slow it down without changing pitch, add a click, loop any section
• Tap mode: six pads under a neon highway with Perfect, Great and Good timing
• Kit mode (Pro): play your real drums and the microphone scores every hit
• Results with grades, stars, combo and a bar-by-bar early/late timing map
• Fill library: every fill from your songs, ready to drill on a loop
• Levels, daily quests, streaks, achievements and unlockable stage skins
• 10 languages, switchable inside the app

Groovelens Pro is a one-time purchase, not a subscription: unlimited songs, Kit mode, speed trainer, the full fill library, MIDI, MusicXML and PDF export, and every stage skin.

Works with your own audio files, videos and recordings. Songs bought from Apple Music are copy-protected and can't be imported. Automatic transcription can miss or mislabel hits on dense mixes; the chart editor lets you fix them."""

PRO_LINE = {
    "zh-Hant": "Groovelens Pro 一次買斷，不是訂閱：無限歌曲、真鼓模式、速度訓練、全部過門、MIDI／MusicXML／PDF 匯出與所有舞台造型。\n\n可使用你自己的音訊檔、影片和錄音；從 Apple Music 購買的歌曲有版權保護，無法匯入。自動扒譜在編曲很滿的歌上可能認錯，可以用鼓譜編輯器修正。",
    "zh-Hans": "Groovelens Pro 一次买断，不是订阅：无限歌曲、真鼓模式、速度训练、全部过门、MIDI／MusicXML／PDF 导出与所有舞台造型。\n\n可使用你自己的音频文件、视频和录音；从 Apple Music 购买的歌曲有版权保护，无法导入。自动扒谱在编曲很满的歌上可能认错，可以用鼓谱编辑器修正。",
    "ja": "Groovelens Pro は買い切りでサブスクではありません：曲数無制限、キットモード、スピードトレーナー、全フィル、MIDI／MusicXML／PDF 書き出し、全ステージスキン。\n\n自分の音声ファイル、動画、録音が使えます。Apple Music で購入した曲はコピー保護のため読み込めません。音数の多い曲では誤認識することがあり、譜面エディタで修正できます。",
    "ko": "Groovelens Pro는 한 번 구매로 끝, 구독이 아닙니다: 곡 무제한, 키트 모드, 속도 트레이너, 모든 필인, MIDI/MusicXML/PDF 내보내기, 모든 스테이지 스킨.\n\n직접 가진 오디오 파일, 동영상, 녹음을 쓸 수 있습니다. Apple Music에서 구입한 곡은 복제 방지되어 가져올 수 없습니다. 복잡한 곡에서는 일부 타격을 잘못 인식할 수 있으며 악보 편집기로 고칠 수 있습니다.",
    "de-DE": "Groovelens Pro ist ein Einmalkauf, kein Abo: unbegrenzt Songs, Kit-Modus, Tempo-Trainer, alle Fills, MIDI-, MusicXML- und PDF-Export und alle Bühnen-Skins.\n\nFunktioniert mit eigenen Audiodateien, Videos und Aufnahmen. Bei Apple Music gekaufte Songs sind kopiergeschützt und können nicht importiert werden. Bei dichten Mixes können Schläge falsch erkannt werden; korrigiere sie im Noteneditor.",
    "fr-FR": "Groovelens Pro s’achète une fois, sans abonnement : morceaux illimités, mode Batterie, entraîneur de tempo, tous les breaks, export MIDI, MusicXML et PDF, et tous les thèmes de scène.\n\nFonctionne avec tes propres fichiers audio, vidéos et enregistrements. Les morceaux achetés sur Apple Music sont protégés et ne peuvent pas être importés. Sur les mix chargés, certaines frappes peuvent être mal reconnues ; corrige-les dans l’éditeur.",
    "es-ES": "Groovelens Pro es un pago único, sin suscripción: canciones ilimitadas, modo Batería, entrenador de velocidad, todos los fills, exportación MIDI, MusicXML y PDF, y todos los escenarios.\n\nFunciona con tus propios archivos de audio, vídeos y grabaciones. Las canciones compradas en Apple Music tienen protección anticopia y no se pueden importar. En mezclas densas algunos golpes pueden confundirse; corrígelos en el editor.",
    "pt-BR": "O Groovelens Pro é compra única, sem assinatura: músicas ilimitadas, modo Bateria, treino de velocidade, todas as viradas, exportação MIDI, MusicXML e PDF, e todos os palcos.\n\nFunciona com seus próprios arquivos de áudio, vídeos e gravações. Músicas compradas no Apple Music são protegidas e não podem ser importadas. Em mixagens densas algumas batidas podem ser confundidas; corrija no editor.",
    "it": "Groovelens Pro è un acquisto unico, senza abbonamento: brani illimitati, modalità Batteria, allenatore di velocità, tutti i fill, esportazione MIDI, MusicXML e PDF e tutti i palchi.\n\nFunziona con i tuoi file audio, video e registrazioni. I brani acquistati su Apple Music sono protetti e non possono essere importati. Nei mix densi alcuni colpi possono essere confusi; correggili nell’editor.",
}

# locale: (name ≤30, subtitle ≤30, keywords ≤100, description intro)
LOCALES = {
    "en-US": ("Groovelens: Drum Sheet & Tabs", "Turn any song into a drum game",
              "drum transcription,drum notation,drumming,practice,metronome,rhythm game,midi,musicxml,beat,fill", None),
    "zh-Hant": ("Groovelens：鼓譜扒譜練習", "任何歌曲，變成鼓的節奏遊戲", "鼓譜,扒譜,爵士鼓,打鼓,練鼓,節拍器,節奏遊戲,MIDI,過門",
                "放進任何一首歌，就能打它的鼓。Groovelens 在 iPhone 上把鼓聲分離出來、找到節拍、寫出鼓譜，再變成可以在螢幕上或真鼓上玩的節奏遊戲。全部本機處理，不上傳、不需要帳號。"),
    "zh-Hans": ("Groovelens：鼓谱扒谱练习", "任何歌曲，变成鼓的节奏游戏", "鼓谱,扒谱,架子鼓,打鼓,练鼓,节拍器,节奏游戏,MIDI,过门",
                "放进任何一首歌，就能打它的鼓。Groovelens 在 iPhone 上把鼓声分离出来、找到节拍、写出鼓谱，再变成可以在屏幕上或真鼓上玩的节奏游戏。全部本机处理，不上传、不需要账号。"),
    "ja": ("Groovelens：ドラム譜・耳コピ練習", "どんな曲もドラムのリズムゲームに", "ドラム,耳コピ,ドラム譜,採譜,練習,メトロノーム,リズムゲーム,MIDI,フィル",
           "好きな曲を入れるだけで、そのドラムを叩けます。Groovelens は iPhone の中でドラムを分離し、ビートを見つけて譜面を作り、画面でも本物のドラムでも遊べるリズムゲームにします。すべて端末内で処理、アップロードもアカウントも不要です。"),
    "ko": ("Groovelens: 드럼 악보 채보 연습", "어떤 곡이든 드럼 리듬 게임으로", "드럼,채보,드럼악보,연습,메트로놈,리듬게임,MIDI,필인,비트",
           "원하는 곡을 넣으면 그 곡의 드럼을 칠 수 있습니다. Groovelens는 iPhone에서 드럼을 분리하고 비트를 찾아 악보를 만든 뒤, 화면이나 실제 드럼으로 즐기는 리듬 게임으로 바꿉니다. 모든 처리는 기기에서, 업로드와 계정 없이."),
    "de-DE": ("Groovelens: Drum-Noten üben", "Jeder Song wird zum Drum-Game", "Schlagzeug,Drums,Noten,Transkription,Metronom,Rhythmusspiel,MIDI,Fill,Üben",
              "Wirf einen Song rein und spiel seine Drums. Groovelens trennt auf dem iPhone die Drums vom Mix, findet den Beat, schreibt lesbare Noten und macht daraus ein Rhythmusspiel, auf dem Bildschirm oder an deinem echten Kit. Alles läuft auf dem Gerät, kein Upload, kein Konto."),
    "fr-FR": ("Groovelens: partition batterie", "Tes morceaux en jeu de rythme", "batterie,partition,transcription,métronome,jeu de rythme,MIDI,break,pratique,groove",
              "Choisis un morceau et joue sa batterie. Groovelens isole la batterie sur ton iPhone, trouve la pulsation, écrit une partition lisible et la transforme en jeu de rythme, à l’écran ou sur ta vraie batterie. Tout reste sur l’appareil, sans envoi ni compte."),
    "es-ES": ("Groovelens: partituras batería", "Tu música, un juego de ritmo", "batería,partitura,transcripción,metrónomo,juego de ritmo,MIDI,fill,práctica,groove",
              "Elige cualquier canción y toca su batería. Groovelens separa la batería en tu iPhone, encuentra el pulso, escribe una partitura legible y la convierte en un juego de ritmo, en pantalla o en tu batería real. Todo ocurre en el dispositivo, sin subidas ni cuentas."),
    "pt-BR": ("Groovelens: partitura bateria", "Cada música vira jogo de ritmo", "bateria,partitura,transcrição,metrônomo,jogo de ritmo,MIDI,virada,prática,groove",
              "Escolha qualquer música e toque a bateria dela. O Groovelens separa a bateria no seu iPhone, encontra o pulso, escreve uma partitura legível e transforma tudo em um jogo de ritmo, na tela ou na sua bateria de verdade. Tudo fica no aparelho, sem envio e sem conta."),
    "it": ("Groovelens: spartiti batteria", "Ogni brano, un gioco di ritmo", "batteria,spartito,trascrizione,metronomo,gioco ritmico,MIDI,fill,studio,groove",
           "Scegli un brano e suonane la batteria. Groovelens separa la batteria sul tuo iPhone, trova il beat, scrive uno spartito leggibile e lo trasforma in un gioco di ritmo, sullo schermo o sulla tua vera batteria. Tutto resta sul dispositivo, senza caricamenti né account."),
}
SHOT_DIRS = {"en-US": "en-US", "zh-Hant": "zh-Hant", "de-DE": "de-DE", "ja": "ja"}
REVIEW_NOTES = ("No account or login is needed. To try the app without your own audio, tap \"Try the demo song\" on the home "
                "screen: a built-in groove is analyzed on the device and opens as a playable chart. Pro is a one-time "
                "non-consumable purchase; tapping Kit mode on a song page (or any PRO badge) opens the paywall with "
                "Restore Purchases. The microphone is used only for recording and Kit mode. Analysis is fully on-device.")


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
        "primaryCategory": {"data": {"type": "appCategories", "id": "MUSIC"}},
        "secondaryCategory": {"data": {"type": "appCategories", "id": "EDUCATION"}}}}})
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


if __name__ == "__main__":
    app = call("GET", f"/v1/apps?filter[bundleId]={BUNDLE_ID}")["data"][0]
    print("app", app["id"], app["attributes"]["name"])
    {"meta": meta, "submit": submit}[sys.argv[1]](app["id"])
