#!/usr/bin/env python3
"""Build Localizable.xcstrings and InfoPlist.xcstrings from localization/*.py tables.

Each table defines T = {english: [zh-Hant, zh-Hans, ja, ko, de, fr, es, pt-BR, it]}; "=" keeps English.
Keys are the English source strings (format specifiers as Swift exports them: %@, %lld).
The CI gate (check_strings.py) then compares the exported en.xliff against these catalogs.
"""
import glob, json, os, runpy, sys

LANGS = ["zh-Hant", "zh-Hans", "ja", "ko", "de", "fr", "es", "pt-BR", "it"]
here = os.path.dirname(os.path.abspath(__file__))
T = {}
for path in sorted(glob.glob(os.path.join(here, "..", "localization", "*.py"))):
    for k, row in runpy.run_path(path)["T"].items():
        if len(row) != 9:
            sys.exit(f"{path}: {k!r} has {len(row)} translations")
        T[k] = row

def entry(source, row):
    loc = {"en": {"stringUnit": {"state": "translated", "value": source}}}
    for lang, text in zip(LANGS, row):
        loc[lang] = {"stringUnit": {"state": "translated", "value": source if text == "=" else text}}
    return {"localizations": loc}

PLIST = {
    "NSLocalNetworkUsageDescription": "Spindle connects to the music server on your home network that you add as a source.",
    "NSPhotoLibraryAddUsageDescription": "Spindle saves the share card you create to your photo library.",
    "CFBundleDisplayName": "Spindle",
    "CFBundleName": "Spindle",
}
plist = {k: entry(src, T[src]) for k, src in PLIST.items()}
loc = {k: entry(k, row) for k, row in T.items() if k not in PLIST.values() or k == "Spindle"}

out = os.path.join(here, "..", "Spindle", "Resources")
for name, strings in (("Localizable.xcstrings", loc), ("InfoPlist.xcstrings", plist)):
    with open(os.path.join(out, name), "w", encoding="utf-8") as fh:
        json.dump({"sourceLanguage": "en", "strings": dict(sorted(strings.items())), "version": "1.0"}, fh, ensure_ascii=False, indent=2)
    print(name, len(strings), "keys ×", len(LANGS) + 1, "languages")
