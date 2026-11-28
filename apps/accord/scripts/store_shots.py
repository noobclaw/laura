#!/usr/bin/env python3
"""Turn the CI UI-tour screenshots into App Store screenshots (6.7", 1290x2796).

  store_shots.py <ui-shots dir>
"""
import os, sys
from PIL import Image

SRC = sys.argv[1]
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "store", "screenshots")
LANGS = {"en": "en-US", "zh-Hant": "zh-Hant", "ja": "ja", "de": "de-DE"}
PICK = ["01-bench", "03-analysis-more", "07-plan", "08-weigh", "10-shelf", "16-dilution"]
SIZE = (1290, 2796)


def save(src, dst):
    im = Image.open(src).convert("RGB").resize(SIZE, Image.LANCZOS)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    im.save(dst, "JPEG", quality=90)


for lang, folder in LANGS.items():
    n = 0
    for name in PICK:
        p = os.path.join(SRC, lang, name + ".png")
        if os.path.exists(p):
            n += 1
            save(p, os.path.join(OUT, folder, f"{n:02d}.jpg"))
    if lang == "en":   # the Noir look as the closing shot
        for name in ("01-bench", "04-share-card"):
            p = os.path.join(SRC, "noir", name + ".png")
            if os.path.exists(p) and n < 10:
                n += 1
                save(p, os.path.join(OUT, folder, f"{n:02d}.jpg"))
    print(folder, n)

save(os.path.join(SRC, "en", "20-paywall.png"), os.path.join(OUT, "iap-review.jpg"))
print("iap-review.jpg")
