#!/usr/bin/env python3
"""Detail-density metrics for game screenshots.

Usage: python3 visual_metrics.py shot1.png [shot2.png ...]

Measures how much visual detail a screenshot carries. It does NOT measure
whether the picture is good-looking: a noisy image scores high too. Use it as a
floor check next to a side-by-side comparison with the reference game.

Reference values, measured 2026-11-22 on three in-match screenshots of
Starfall (vileosbot-bot/starfall-rebuild, docs/shots 05/06/07):
  entropy 7.14-7.35, edge density 22.1-27.1 %, flat blocks 8.9-12.0 %,
  colours 1218-1446.
Pass line used by the casual-game-production skill:
  flat blocks <= 15 %, edge density >= 22 %.
"""
import sys

import numpy as np
from PIL import Image

FLAT_MAX = 15.0
EDGE_MIN = 22.0


def metrics(path):
    im = Image.open(path).convert("RGB")
    w, h = im.size
    s = 640 / max(w, h)  # same scale for every image so numbers compare
    im = im.resize((int(w * s), int(h * s)), Image.LANCZOS)
    a = np.asarray(im).astype(np.float32)
    g = a.mean(2)
    hist = np.histogram(g, bins=256, range=(0, 255))[0] / g.size
    entropy = float(-(hist[hist > 0] * np.log2(hist[hist > 0])).sum())
    gx = np.abs(np.diff(g, axis=1))[:-1, :]
    gy = np.abs(np.diff(g, axis=0))[:, :-1]
    edge = float((np.hypot(gx, gy) > 12).mean() * 100)
    H, W = g.shape
    B = 8
    blocks = g[: H // B * B, : W // B * B].reshape(H // B, B, W // B, B).std(axis=(1, 3))
    flat = float((blocks < 1.5).mean() * 100)
    q = (a // 16).astype(np.int32)
    colours = int(len(np.unique(q[..., 0] * 256 + q[..., 1] * 16 + q[..., 2])))
    return entropy, edge, flat, colours


def main(paths):
    if not paths:
        print(__doc__)
        return 2
    failed = False
    print(f"{'file':40} {'entropy':>8} {'edge %':>8} {'flat %':>8} {'colours':>8}  result")
    for p in paths:
        e, ed, fl, c = metrics(p)
        ok = fl <= FLAT_MAX and ed >= EDGE_MIN
        failed |= not ok
        print(f"{p[-40:]:40} {e:8.2f} {ed:8.1f} {fl:8.1f} {c:8d}  {'pass' if ok else 'BELOW LINE'}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
