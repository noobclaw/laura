#!/usr/bin/env bash
# Copy the web game into this app's assets. Run from anywhere: bash apps/lantern/tools/sync_game.sh
# Since 1.1.0 the app holds two complete scenes that share saves and items:
#   assets/game/            Shiba Garden   (game/dog-queens/web), opened at launch
#   assets/game/lantern/    Lantern Garden (game/lantern/prototype3d), the 1.0 game with its own art, unchanged
# A button in the top right corner of each home screen opens the other one (scene_switch.js).
# Changes made on the way: no web-font request, pinch-zoom and rubber-band scrolling off. Neither page uses the network.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"; dog="$here/../../game/dog-queens/web"; lan="$here/../../game/lantern/prototype3d"; dst="$here/assets/game"
rm -rf "$dst"; mkdir -p "$dst/assets/art" "$dst/lantern/vendor" "$dst/lantern/assets/fx"
cp "$dog/core.js" "$dog/music.js" "$dog/solver.js" "$dog/levels.js" "$dog/i18n.js" "$dog/strings.js" "$dog/game.js" "$dog/scene_switch.js" "$dog/lantern_help.js" "$dst/"
cp "$dog"/assets/art/*.png "$dst/assets/art/"
cp "$dog/assets/sfx.js" "$dst/assets/"   # sounds travel as base64 inside this script
cp "$lan/core.js" "$lan/music.js" "$lan/solver.js" "$lan/levels.js" "$lan/i18n.js" "$lan/game3d.js" "$dst/lantern/"
cp "$lan/vendor/three.min.js" "$lan/vendor/THREE-LICENSE.txt" "$dst/lantern/vendor/"
cp "$lan"/assets/fx/*.png "$dst/lantern/assets/fx/"
cp "$lan/assets/sfx.js" "$dst/lantern/assets/"
python3 - "$dog/index.html" "$dst/index.html" "$lan/index.html" "$dst/lantern/index.html" <<'PY'
import re,sys
def common(h):
    a='width=device-width,initial-scale=1,viewport-fit=cover';assert a in h
    h=h.replace(a,a+',maximum-scale=1,user-scalable=no')
    a='<style>';assert h.count(a)==1
    return h.replace(a,'<style>html,body{overscroll-behavior:none;-webkit-touch-callout:none;-webkit-text-size-adjust:100%}\n')
h=common(open(sys.argv[1],encoding="utf-8").read())
assert "https://" not in h and "http://" not in h.replace("http://www.w3.org",""), "page must not reference the network"
open(sys.argv[2],"w",encoding="utf-8").write(h)
h=open(sys.argv[3],encoding="utf-8").read()
h,n=re.subn(r'<link[^>]*fonts\.(googleapis|gstatic)\.com[^>]*>\n?','',h);assert n==3,n
h=common(h)
a='<script src="game3d.js"></script>';assert h.count(a)==1
h=h.replace(a,a+'\n<script src="../scene_switch.js"></script>\n<script src="../lantern_help.js"></script>')
assert "https://" not in h and "http://" not in h.replace("http://www.w3.org","")
open(sys.argv[4],"w",encoding="utf-8").write(h)
PY
echo "synced: $(find "$dst" -type f | wc -l) files, $(du -sh "$dst" | cut -f1)"
