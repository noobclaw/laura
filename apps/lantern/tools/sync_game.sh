#!/usr/bin/env bash
# Copy the web game into this app's assets. Run from anywhere: bash apps/lantern/tools/sync_game.sh
# Changes made on the way: no web-font request (the app makes no network calls; iOS falls back to
# its rounded system font), pinch-zoom and rubber-band scrolling off, loose sound files and docs left out.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"; src="$here/../../game/lantern/prototype3d"; dst="$here/assets/game"
rm -rf "$dst"; mkdir -p "$dst/vendor" "$dst/assets/fx"
cp "$src/core.js" "$src/solver.js" "$src/i18n.js" "$src/game3d.js" "$dst/"
cp "$src/vendor/three.min.js" "$src/vendor/THREE-LICENSE.txt" "$dst/vendor/"
cp "$src"/assets/fx/*.png "$dst/assets/fx/"
cp "$src/assets/sfx.js" "$dst/assets/"   # sounds travel as base64 inside this script
python3 - "$src/index.html" "$dst/index.html" <<'PY'
import re,sys
h=open(sys.argv[1],encoding="utf-8").read()
h,n=re.subn(r'<link[^>]*fonts\.(googleapis|gstatic)\.com[^>]*>\n?','',h);assert n==3,n
a='width=device-width,initial-scale=1,viewport-fit=cover';assert a in h
h=h.replace(a,a+',maximum-scale=1,user-scalable=no')
a='<style>';assert h.count(a)==1
h=h.replace(a,'<style>html,body{overscroll-behavior:none;-webkit-touch-callout:none;-webkit-text-size-adjust:100%}\n')
open(sys.argv[2],"w",encoding="utf-8").write(h)
PY
echo "synced: $(find "$dst" -type f | wc -l) files, $(du -sh "$dst" | cut -f1)"
