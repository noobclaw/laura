# Renders Mochi's tokens and poses to art/out/*.svg. Run: python3 poses.py
import os
from shiba import head, bandana, fur_shape, svg

OUT = os.path.join(os.path.dirname(__file__), '..', 'out')
os.makedirs(OUT, exist_ok=True)


def save(name, text):
    open(os.path.join(OUT, name + '.svg'), 'w').write(text)


def place(inner, x, y, k):
    return f'<g transform="translate({x} {y}) scale({k})">{inner}</g>'


def shadow(cx, cy, rx, op=.18):
    return f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{rx * .12:.0f}" fill="#3A2A20" opacity="{op}" filter="url(#blur6)"/>'


def toe_lines(cx, cy, w):
    return ''.join(f'<path d="M{cx + dx} {cy - 6} L{cx + dx} {cy + 8}" stroke="#D9B99A" stroke-width="2.4" stroke-linecap="round"/>'
                   for dx in (-w * .3, 0, w * .3))


def paw(cx, cy, rx=38, ry=22, seed=0):
    return fur_shape(f'M{cx - rx} {cy} A{rx} {ry} 0 1 0 {cx + rx} {cy} A{rx} {ry} 0 1 0 {cx - rx} {cy}Z',
                     'url(#creamBody)', seed=seed, cream=True) + toe_lines(cx, cy, rx)


def tail(cx, cy, r, seed):
    # curled shiba tail: orange ring with a cream curl inside
    outer = f'M{cx - r} {cy} A{r} {r} 0 1 0 {cx + r} {cy} A{r} {r} 0 1 0 {cx - r} {cy}Z'
    inner_r = r * .55
    inner = f'M{cx - inner_r} {cy + 4} A{inner_r} {inner_r} 0 1 0 {cx + inner_r} {cy + 4} A{inner_r} {inner_r} 0 1 0 {cx - inner_r} {cy + 4}Z'
    return (fur_shape(outer, 'url(#furSide)', seed=seed, box=(cx - r, cy - r, cx + r, cy + r), strokes=40)
            + fur_shape(inner, 'url(#creamBody)', seed=seed + 1, cream=True)
            + f'<path d="M{cx - inner_r * .4} {cy} q{inner_r * .3} -{inner_r * .5} {inner_r * .7} 0" stroke="#E2B48A" stroke-width="3" fill="none" opacity=".7"/>')


def limb(x1, y1, x2, y2, w, seed, cream=False):
    # a soft capsule from (x1,y1) to (x2,y2)
    import math
    a = math.atan2(y2 - y1, x2 - x1); nx, ny = -math.sin(a) * w / 2, math.cos(a) * w / 2
    d = (f'M{x1 + nx:.1f} {y1 + ny:.1f} L{x2 + nx:.1f} {y2 + ny:.1f} A{w / 2} {w / 2} 0 0 0 {x2 - nx:.1f} {y2 - ny:.1f} '
         f'L{x1 - nx:.1f} {y1 - ny:.1f} A{w / 2} {w / 2} 0 0 0 {x1 + nx:.1f} {y1 + ny:.1f}Z')
    return fur_shape(d, 'url(#creamBody)' if cream else 'url(#furSide)', seed=seed, cream=cream,
                     box=(min(x1, x2) - w, min(y1, y2) - w, max(x1, x2) + w, max(y1, y2) + w), strokes=25)


# ---------- tokens (board pieces) ----------
for name, e, m in (('C1_token', 'open', 'smile'), ('C2_token_joy', 'joy', 'open'), ('C3_token_surprise', 'surprise', 'o')):
    save(name, svg(512, 512, shadow(256, 478, 150, .16) + bandana() + head(e, m), px=1024))

# ---------- B1 sitting ----------
HX, HY, HK = 64, 0, .92          # head placement for sitting poses
def sitting_body(seed=10):
    s = shadow(300, 700, 230)
    s += tail(470, 470, 56, seed)
    s += fur_shape('M190 360 C146 420 136 560 166 640 C196 692 404 692 434 640 C464 560 454 420 410 360 Z',
                   seed=seed + 2, box=(150, 360, 450, 690), strokes=120)
    s += fur_shape('M120 620 C110 570 150 540 200 548 C250 556 266 610 250 650 C236 690 140 690 120 620Z', seed=seed + 3, box=(110, 540, 260, 690), strokes=40)
    s += fur_shape('M480 620 C490 570 450 540 400 548 C350 556 334 610 350 650 C364 690 460 690 480 620Z', seed=seed + 4, box=(340, 540, 490, 690), strokes=40)
    s += paw(150, 676, 44, 22, seed + 5) + paw(450, 676, 44, 22, seed + 6)
    s += fur_shape('M234 372 C212 424 216 500 246 544 C266 568 334 568 354 544 C384 500 388 424 366 372 Z',
                   'url(#creamBody)', seed=seed + 7, cream=True, box=(214, 372, 386, 566), strokes=70)
    return s

def front_legs(seed=20):
    s = '<path d="M300 540 L300 676" stroke="#B5642A" stroke-width="14" opacity=".35" filter="url(#blur3)"/>'
    for x0, x1, k in ((258, 254, 0), (342, 346, 1)):
        s += limb(x0, 500, x1, 662, 60, seed + k)                       # orange leg
        s += limb(x0 + (6 if k == 0 else -6), 530, x1 + (4 if k == 0 else -4), 664, 48, seed + 4 + k, cream=True)  # cream front stripe
    return s + paw(250, 678, 40, 22, seed + 2) + paw(350, 678, 40, 22, seed + 3)

body = sitting_body() + front_legs()
body += place(bandana(), HX, HY, HK) + place(head('open', 'smile'), HX, HY, HK)
save('B1_sit', svg(600, 720, body))

# ---------- B3 jumping with joy ----------
import random
R = random.Random(3)
conf = ''
for _ in range(26):
    x, y = R.uniform(40, 560), R.uniform(30, 560); c = R.choice(['#FF7FA6', '#FFD45C', '#6FD3B4', '#7FB6FF', '#B48CFF'])
    if R.random() < .5:
        conf += f'<rect x="{x:.0f}" y="{y:.0f}" width="14" height="8" rx="2" fill="{c}" transform="rotate({R.uniform(0, 180):.0f} {x:.0f} {y:.0f})"/>'
    else:
        conf += f'<circle cx="{x:.0f}" cy="{y:.0f}" r="{R.uniform(4, 7):.1f}" fill="{c}"/>'
JX, JY, JK = 64, 20, .92
body = shadow(300, 706, 150, .12) + conf
body += tail(452, 520, 50, 40)
body += limb(240, 560, 176, 650, 62, 41) + limb(360, 560, 424, 650, 62, 42)          # hind legs spread
body += paw(166, 664, 40, 24, 43) + paw(434, 664, 40, 24, 44)
body += fur_shape('M200 380 C160 440 166 560 210 610 C246 646 354 646 390 610 C434 560 440 440 400 380 Z', seed=45, box=(170, 380, 430, 640), strokes=110)
body += fur_shape('M240 392 C218 450 224 548 260 596 C282 620 318 620 340 596 C376 548 382 450 360 392 Z', 'url(#creamBody)', seed=46, cream=True, box=(220, 392, 380, 620), strokes=70)
body += limb(214, 430, 100, 300, 56, 47) + limb(386, 430, 500, 300, 56, 48)          # front legs up
body += paw(92, 286, 34, 30, 49) + paw(508, 286, 34, 30, 50)
body += place(bandana(), JX, JY, JK) + place(head('joy', 'open', ears='up'), JX, JY, JK)
save('B3_celebrate', svg(600, 720, body))

# ---------- B5 oops: paws over the eyes ----------
body = sitting_body(60)
body += place(bandana(), HX, HY, HK) + place(head('squeeze', 'wobble', ears='down'), HX, HY, HK)
body += limb(160, 470, 214, 296, 56, 70) + limb(440, 470, 386, 296, 56, 71)
body += paw(232, 262, 44, 38, 72) + paw(368, 262, 44, 38, 73)
body += ('<path d="M470 150 C458 176 452 190 462 202 C472 212 488 206 488 190 C488 178 480 166 470 150Z" fill="#9FD8F5"/>'
         '<ellipse cx="466" cy="190" rx="4" ry="7" fill="#fff" opacity=".7"/>')
save('B5_oops', svg(600, 720, body))

# ---------- B7 sleeping, lying down ----------
SX, SY, SK = 70, 196, .86
body = shadow(300, 690, 270)
body += fur_shape('M70 600 C60 500 160 440 300 440 C440 440 540 500 530 600 C524 670 76 670 70 600Z', seed=80, box=(70, 440, 530, 670), strokes=140)
body += tail(470, 600, 62, 81)
body += fur_shape('M150 610 C150 560 210 540 300 540 C390 540 450 560 450 610 C450 650 150 650 150 610Z', 'url(#creamBody)', seed=83, cream=True, box=(150, 540, 450, 650), strokes=60)
body += place(bandana(), SX, SY, SK) + place(head('sleep', 'sleep'), SX, SY, SK)
body += paw(226, 646, 50, 24, 85) + paw(374, 646, 50, 24, 86)
save('B7_sleep', svg(600, 720, body))

# ---------- B8 sad (out of bones) ----------
body = sitting_body(100) + front_legs(110)
body += place(bandana(), HX, HY + 14, HK) + place(head('open', 'frown', ears='down'), HX, HY + 14, HK)
body += ('<path d="M212 226 L262 240" stroke="#B4561C" stroke-width="7" stroke-linecap="round" opacity=".55"/>'
         '<path d="M388 226 L338 240" stroke="#B4561C" stroke-width="7" stroke-linecap="round" opacity=".55"/>'
         '<path d="M204 318 C196 338 192 350 200 358 C208 364 218 358 218 348 C218 338 212 330 204 318Z" fill="#9FD8F5"/>')
save('B8_sad', svg(600, 720, body))

# ---------- B2 wave hello ----------
body = sitting_body(120)
body += limb(256, 500, 254, 662, 60, 130) + limb(260, 530, 258, 664, 48, 131, cream=True) + paw(250, 678, 40, 22, 132)
body += place(bandana(), HX, HY, HK) + place(head('joy', 'open'), HX, HY, HK)
body += limb(400, 470, 500, 330, 56, 133) + paw(508, 314, 38, 34, 134)
body += ('<path d="M548 262 q14 10 10 28" stroke="#F7A050" stroke-width="6" fill="none" stroke-linecap="round"/>'
         '<path d="M566 246 q22 16 16 46" stroke="#F7A050" stroke-width="6" fill="none" stroke-linecap="round" opacity=".6"/>')
save('B2_wave', svg(600, 720, body))

# ---------- item icons ----------
ICON_DEFS = ('<radialGradient id="boneG" cx="35%" cy="25%" r="85%"><stop offset="0" stop-color="#FFFFFF"/><stop offset=".6" stop-color="#FFF1DC"/><stop offset="1" stop-color="#E5C59E"/></radialGradient>'
             '<radialGradient id="cookieG" cx="35%" cy="25%" r="85%"><stop offset="0" stop-color="#FFD98A"/><stop offset=".6" stop-color="#F0A84A"/><stop offset="1" stop-color="#C87A28"/></radialGradient>'
             '<radialGradient id="ballG" cx="35%" cy="25%" r="85%"><stop offset="0" stop-color="#FF9AA6"/><stop offset=".55" stop-color="#F0566B"/><stop offset="1" stop-color="#B92F46"/></radialGradient>'
             '<linearGradient id="boxG" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#FFE27A"/><stop offset="1" stop-color="#F3B32E"/></linearGradient>'
             '<linearGradient id="lidG" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFEFA6"/><stop offset="1" stop-color="#F8C645"/></linearGradient>'
             '<linearGradient id="ribG" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#8FE3C6"/><stop offset=".5" stop-color="#4FC49E"/><stop offset="1" stop-color="#2FA380"/></linearGradient>')


def icon(name, inner):
    save(name, svg(256, 256, f'<defs>{ICON_DEFS}</defs>' + inner, px=512))


BONE = 'M70 96 C46 72 78 40 102 62 C118 38 150 66 132 92 L176 136 C202 118 232 150 208 166 C232 190 200 222 176 200 C160 224 126 196 146 170 L102 126 C76 144 46 112 70 96Z'
icon('D1_bone', '<ellipse cx="132" cy="236" rx="78" ry="9" fill="#3A2A20" opacity=".15" filter="url(#blur3)"/>'
     f'<path d="{BONE}" fill="#D9B58C" transform="translate(0 7)"/><path d="{BONE}" fill="url(#boneG)"/>'
     '<path d="M84 74 C92 64 104 66 108 76" stroke="#fff" stroke-width="7" fill="none" stroke-linecap="round" opacity=".9"/>'
     '<path d="M112 110 L160 158" stroke="#fff" stroke-width="8" stroke-linecap="round" opacity=".7"/>')


def pawprint(cx, cy, k, fill):
    return (f'<g transform="translate({cx} {cy}) scale({k})" fill="{fill}"><ellipse cx="0" cy="18" rx="30" ry="24"/>'
            '<ellipse cx="-34" cy="-10" rx="12" ry="16" transform="rotate(-24 -34 -10)"/><ellipse cx="-13" cy="-28" rx="12" ry="17" transform="rotate(-8 -13 -28)"/>'
            '<ellipse cx="13" cy="-28" rx="12" ry="17" transform="rotate(8 13 -28)"/><ellipse cx="34" cy="-10" rx="12" ry="16" transform="rotate(24 34 -10)"/></g>')


icon('D2_treat', '<ellipse cx="128" cy="236" rx="74" ry="9" fill="#3A2A20" opacity=".15" filter="url(#blur3)"/>'
     '<circle cx="128" cy="132" r="92" fill="#B56A1E"/><circle cx="128" cy="122" r="92" fill="url(#cookieG)"/>'
     + pawprint(128, 129, 1.25, '#A9601C') + pawprint(128, 124, 1.25, '#FFE9B8') +
     '<path d="M62 86 C78 58 110 44 140 44" stroke="#fff" stroke-width="9" fill="none" stroke-linecap="round" opacity=".55"/>')
icon('D3_ball', '<ellipse cx="128" cy="236" rx="70" ry="9" fill="#3A2A20" opacity=".15" filter="url(#blur3)"/>'
     '<circle cx="128" cy="128" r="94" fill="url(#ballG)"/>'
     '<path d="M40 156 C90 118 170 118 218 156" stroke="#fff" stroke-width="14" fill="none" stroke-linecap="round" opacity=".92"/>'
     '<path d="M128 46 l11 24 26 3 -19 18 5 26 -23 -13 -23 13 5 -26 -19 -18 26 -3z" fill="#FFE27A"/>'
     '<ellipse cx="80" cy="84" rx="24" ry="12" fill="#fff" opacity=".45" transform="rotate(-38 80 84)"/>')
icon('D4_gift', '<ellipse cx="128" cy="238" rx="80" ry="9" fill="#3A2A20" opacity=".15" filter="url(#blur3)"/>'
     '<rect x="48" y="112" width="160" height="116" rx="16" fill="url(#boxG)"/><rect x="48" y="112" width="160" height="22" fill="#C98A14" opacity=".28"/>'
     '<rect x="36" y="80" width="184" height="46" rx="14" fill="url(#lidG)"/><rect x="110" y="80" width="36" height="148" fill="url(#ribG)"/>'
     '<path d="M128 80 C96 30 52 44 70 70 C80 84 110 82 128 80Z" fill="url(#ribG)"/><path d="M128 80 C160 30 204 44 186 70 C176 84 146 82 128 80Z" fill="url(#ribG)"/>'
     '<circle cx="128" cy="78" r="12" fill="#3DB38F"/>' + pawprint(80, 184, .42, '#E09A1A') + pawprint(178, 184, .42, '#E09A1A') +
     '<path d="M48 92 C70 88 92 86 104 86" stroke="#fff" stroke-width="5" fill="none" stroke-linecap="round" opacity=".6"/>')

# ---------- E1 app icon (square, full bleed) ----------
tiles = ''
cols = ['#FFB3CC', '#A8E6CF', '#A9D3FF', '#FFE08A', '#CDB8FF', '#FFC9A3']
k = 0
for yy in range(2):
    for xx in range(4):
        tiles += f'<rect x="{40 + xx * 240}" y="{560 + yy * 240}" width="224" height="224" rx="44" fill="{cols[(k * 5 + yy) % 6]}"/>'
        tiles += f'<rect x="{40 + xx * 240}" y="{560 + yy * 240}" width="224" height="100" rx="44" fill="#fff" opacity=".22"/>'
        k += 1
body = ('<defs><linearGradient id="sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#BDEBFF"/><stop offset="1" stop-color="#E9F9FF"/></linearGradient></defs>'
        '<rect width="1024" height="1024" fill="url(#sky)"/>' + tiles
        + place(bandana(), 132, 150, 1.48) + place(head('open', 'smile'), 132, 150, 1.48))
save('E1_icon', svg(1024, 1024, body, px=1024))
print('ok')
