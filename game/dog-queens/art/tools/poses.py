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
print('ok')
