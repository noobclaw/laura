#!/usr/bin/env bash
# Copy the web game into this app's assets. Run from anywhere: bash apps/lantern/tools/sync_game.sh
# Since 1.1.0 the game is the puppy build in game/dog-queens/web (same rules, saves and products as 1.0).
# Changes made on the way: pinch-zoom and rubber-band scrolling off. The page makes no network requests.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"; src="$here/../../game/dog-queens/web"; dst="$here/assets/game"
rm -rf "$dst"; mkdir -p "$dst/assets/art"
cp "$src/core.js" "$src/music.js" "$src/solver.js" "$src/levels.js" "$src/i18n.js" "$src/strings.js" "$src/game.js" "$dst/"
cp "$src"/assets/art/*.png "$dst/assets/art/"
cp "$src/assets/sfx.js" "$dst/assets/"   # sounds travel as base64 inside this script
python3 - "$src/index.html" "$dst/index.html" <<'PY'
import sys
h=open(sys.argv[1],encoding="utf-8").read()
assert "http://" not in h.replace("http://www.w3.org","") and "https://" not in h, "page must not reference the network"
a='width=device-width,initial-scale=1,viewport-fit=cover';assert a in h
h=h.replace(a,a+',maximum-scale=1,user-scalable=no')
a='<style>';assert h.count(a)==1
h=h.replace(a,'<style>html,body{-webkit-touch-callout:none;-webkit-text-size-adjust:100%}\n')
open(sys.argv[2],"w",encoding="utf-8").write(h)
PY
echo "synced: $(find "$dst" -type f | wc -l) files, $(du -sh "$dst" | cut -f1)"
