#!/usr/bin/env python3
"""Build Localizable.xcstrings and InfoPlist.xcstrings from the exported en.xliff (keys)
plus translation tables keyed by English text.

Usage: build_strings.py en.xliff localization/ui_a.py localization/ui_b.py ... localization/seed.py

Each table is a Python file defining T = {english: [zh-Hant, zh-Hans, ja, ko, de, fr, es, pt-BR, it]};
"=" keeps the English text. Keys that appear only in tables (e.g. starter-library names looked up
at runtime) are added to Localizable as well. Missing translations for exported keys are listed and
the script exits 1.
"""
import json, os, runpy, sys
import xml.etree.ElementTree as ET

LANGS = ["zh-Hant", "zh-Hans", "ja", "ko", "de", "fr", "es", "pt-BR", "it"]
NS = "{urn:oasis:names:tc:xliff:document:1.2}"

xliff, tables = sys.argv[1], sys.argv[2:]
T = {}
for path in tables:
    for k, row in runpy.run_path(path)["T"].items():
        if len(row) != 9:
            sys.exit(f"{path}: {k!r} has {len(row)} translations, expected 9")
        if k in T and T[k] != row:
            print(f"note: {k!r} defined twice; using {path}")
        T[k] = row

import re
POS = re.compile(r"%(\d+)\$")
# Also index tables by key without positional markers ("%1$@ in %2$@" -> "%@ in %@").
for k in list(T):
    T.setdefault(POS.sub("%", k), T[k])

# (file, key, source)
units = []
for f in ET.parse(xliff).getroot().iter(NS + "file"):
    orig = f.get("original", "")
    for u in f.iter(NS + "trans-unit"):
        key = u.get("id")
        src = u.find(NS + "source")
        if key is None or src is None:
            continue
        units.append((orig, key, src.text or ""))

def entry(source, row):
    loc = {"en": {"stringUnit": {"state": "translated", "value": source}}}
    for lang, text in zip(LANGS, row):
        loc[lang] = {"stringUnit": {"state": "translated", "value": source if text == "=" else text}}
    return {"localizations": loc}

loc, plist, missing = {}, {}, []
for orig, key, source in units:
    k, _, variant = key.partition("|==|")
    if variant:  # plural variants are not used in this app
        continue
    row = T.get(k) or T.get(source)
    if row is None:
        missing.append((orig.split("/")[-1], k))
        continue
    target = plist if orig.endswith("InfoPlist.xcstrings") else loc
    e = entry(source, row)
    # English is the source language; spell it out so keys like "tag.base" resolve to their English text.
    e["localizations"]["en"] = {"stringUnit": {"state": "translated", "value": source}}
    target[k] = e

# Runtime-only keys (seed data) go into Localizable too.
for k, row in T.items():
    if k not in loc and not any(k == key for _, key, _ in units):
        loc[k] = entry(k, row)

if missing:
    print(f"MISSING {len(missing)} translations:")
    for m in missing:
        print("  ", m)
    sys.exit(1)

out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Accord", "Resources")
for name, strings in (("Localizable.xcstrings", loc), ("InfoPlist.xcstrings", plist)):
    with open(os.path.join(out, name), "w", encoding="utf-8") as fh:
        json.dump({"sourceLanguage": "en", "strings": dict(sorted(strings.items())), "version": "1.0"},
                  fh, ensure_ascii=False, indent=2)
    print(name, len(strings), "keys ×", len(LANGS), "languages")
