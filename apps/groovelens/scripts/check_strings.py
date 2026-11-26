#!/usr/bin/env python3
"""CI gate: every key in en.xliff must be translated in every target language."""
import json, sys, re, xml.etree.ElementTree as ET
LANGS = ["zh-Hant", "zh-Hans", "ja", "ko", "de", "fr", "es", "pt-BR", "it"]
ns = "{urn:oasis:names:tc:xliff:document:1.2}"
keys = {}
for f in ET.parse(sys.argv[1]).getroot().iter(ns + "file"):
    for u in f.iter(ns + "trans-unit"):
        if u.get("id"): keys.setdefault(f.get("original"), set()).add(u.get("id"))
bad = []
spec = re.compile(r"%(\d+\$)?(lld|@|lf|d|f|%)")
for orig, ids in keys.items():
    cat = json.load(open(sys.argv[2] + "/" + orig.split("/")[-1]))["strings"]
    for k in ids:
        locs = cat.get(k, {}).get("localizations", {})
        for lang in LANGS:
            l = locs.get(lang)
            if not l: bad.append((lang, k)); continue
            unit = l.get("stringUnit") or l["variations"]["plural"]["other"]["stringUnit"]
            if unit.get("state") != "translated" or not unit.get("value"): bad.append((lang, k)); continue
            if sorted(t for _, t in spec.findall(k)) != sorted(t for _, t in spec.findall(unit["value"])): bad.append((lang, k, "format"))
print(f"{sum(len(v) for v in keys.values())} keys checked × {len(LANGS)} languages, {len(bad)} problems")
for b in bad[:60]: print("  ", b)
sys.exit(1 if bad else 0)
