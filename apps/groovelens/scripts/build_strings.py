#!/usr/bin/env python3
"""Build Localizable.xcstrings and InfoPlist.xcstrings from units.json (exported keys)
and translation tables. Usage: build_strings.py units.json tr_a.py tr_b.py tr_c.py"""
import json, sys, runpy, os
LANGS = ["zh-Hant", "zh-Hans", "ja", "ko", "de", "fr", "es", "pt-BR", "it"]
ONE = {  # plural "one" forms where the language needs them; index -> {lang: text}
    15: {"de": "%lld Tag in Folge", "fr": "%lld jour d’affilée", "es": "%lld día seguido", "pt-BR": "%lld dia seguido", "it": "%lld giorno di fila"},
    16: {"en": "%lld free song left", "de": "Noch %lld Song gratis", "fr": "Encore %lld morceau gratuit", "es": "Te queda %lld canción gratis", "pt-BR": "Resta %lld música grátis", "it": "Ancora %lld brano gratis"},
    18: {"en": "%lld tap", "de": "%lld Tap", "fr": "%lld frappe", "es": "%lld toque", "pt-BR": "%lld toque", "it": "%lld tocco"},
    190: {"en": "Practice for %lld minute", "de": "Übe %lld Minute", "fr": "Pratique %lld minute", "es": "Practica %lld minuto", "pt-BR": "Pratique %lld minuto", "it": "Esercitati per %lld minuto"},
}
units = json.load(open(sys.argv[1]))
T = {}
for f in sys.argv[2:]:
    T.update(runpy.run_path(f)["T"])
loc, plist, missing = {}, {}, []
for i, u in enumerate(units):
    if u["id"] == "":
        continue
    row = T.get(i)
    if row is None or len(row) != 9:
        missing.append((i, u["src"])); continue
    entry = {}
    for lang, text in zip(LANGS, row):
        value = u["src"] if text == "=" else text
        if i in ONE and lang in ONE[i]:
            entry[lang] = {"variations": {"plural": {"one": {"stringUnit": {"state": "translated", "value": ONE[i][lang]}},
                                                     "other": {"stringUnit": {"state": "translated", "value": value}}}}}
        else:
            entry[lang] = {"stringUnit": {"state": "translated", "value": value}}
    if i in ONE and "en" in ONE[i]:
        entry["en"] = {"variations": {"plural": {"one": {"stringUnit": {"state": "translated", "value": ONE[i]["en"]}},
                                                 "other": {"stringUnit": {"state": "translated", "value": u["src"]}}}}}
    target = plist if u["file"].endswith("InfoPlist.xcstrings") else loc
    if target is plist:
        entry["en"] = {"stringUnit": {"state": "translated", "value": u["src"]}}
        if u.get("note"): pass
    target[u["id"]] = {"localizations": entry}
if missing:
    print("MISSING", missing); sys.exit(1)
out = os.path.join(os.path.dirname(__file__), "..", "Groovelens", "Resources")
for name, strings in (("Localizable.xcstrings", loc), ("InfoPlist.xcstrings", plist)):
    with open(os.path.join(out, name), "w", encoding="utf-8") as fh:
        json.dump({"sourceLanguage": "en", "strings": dict(sorted(strings.items())), "version": "1.0"}, fh, ensure_ascii=False, indent=2)
    print(name, len(strings), "keys ×", len(LANGS), "languages")
