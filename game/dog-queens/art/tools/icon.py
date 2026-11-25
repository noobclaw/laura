# App icon: Mochi peeking over a row of glossy colour tiles. Full-bleed 1024 square (iOS rounds the corners itself).
import os
from shiba import head, bandana, svg
OUT = os.path.join(os.path.dirname(__file__), '..', 'out')

def tile(x, y, s, c1, c2, c3, r=54):
    # c1 top face, c2 side, c3 highlight
    return (f'<rect x="{x}" y="{y + 26}" width="{s}" height="{s}" rx="{r}" fill="{c2}"/>'
            f'<rect x="{x}" y="{y}" width="{s}" height="{s}" rx="{r}" fill="{c1}"/>'
            f'<rect x="{x + 18}" y="{y + 14}" width="{s - 36}" height="{s * .34:.0f}" rx="{r * .6:.0f}" fill="{c3}" opacity=".55"/>'
            f'<ellipse cx="{x + s * .26:.0f}" cy="{y + s * .2:.0f}" rx="{s * .09:.0f}" ry="{s * .05:.0f}" fill="#fff" opacity=".85"/>')

def paw(cx, cy, k=1.0, rot=0):
    return (f'<g transform="translate({cx} {cy}) rotate({rot}) scale({k})">'
            '<ellipse cx="0" cy="8" rx="78" ry="58" fill="#E9C8A4"/><ellipse cx="0" cy="0" rx="78" ry="58" fill="url(#creamBody)"/>'
            '<path d="M-28 -34 v34 M0 -40 v38 M28 -34 v34" stroke="#D9B48E" stroke-width="7" stroke-linecap="round"/>'
            '<ellipse cx="-20" cy="-30" rx="26" ry="12" fill="#fff" opacity=".6"/></g>')

def sparkle(cx, cy, r, op=.95):
    return (f'<path d="M{cx} {cy - r} C{cx + r * .12} {cy - r * .12} {cx + r * .12} {cy - r * .12} {cx + r} {cy} '
            f'C{cx + r * .12} {cy + r * .12} {cx + r * .12} {cy + r * .12} {cx} {cy + r} '
            f'C{cx - r * .12} {cy + r * .12} {cx - r * .12} {cy + r * .12} {cx - r} {cy} '
            f'C{cx - r * .12} {cy - r * .12} {cx - r * .12} {cy - r * .12} {cx} {cy - r}Z" fill="#fff" opacity="{op}"/>')

defs = ('<defs><radialGradient id="bgI" cx="50%" cy="34%" r="80%"><stop offset="0" stop-color="#C9F3FF"/><stop offset=".55" stop-color="#7FD3F7"/><stop offset="1" stop-color="#4AA8E8"/></radialGradient>'
        '<radialGradient id="halo" cx="50%" cy="50%" r="50%"><stop offset="0" stop-color="#fff" stop-opacity=".85"/><stop offset=".6" stop-color="#fff" stop-opacity=".25"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></radialGradient>'
        '<linearGradient id="floor" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2E7FC9" stop-opacity="0"/><stop offset="1" stop-color="#1F5FA8" stop-opacity=".45"/></linearGradient></defs>')
rays = ''.join(f'<path d="M512 430 L{512 + 900 * __import__("math").cos(a - .07):.0f} {430 + 900 * __import__("math").sin(a - .07):.0f} L{512 + 900 * __import__("math").cos(a + .07):.0f} {430 + 900 * __import__("math").sin(a + .07):.0f}Z" fill="#fff" opacity=".10"/>'
               for a in [i * 6.283 / 12 for i in range(12)])
T = [('#FF9EBB', '#E36E93', '#FFD3E0'), ('#FFD86B', '#E3A92E', '#FFF0B8'), ('#7FDDB4', '#3FB388', '#C8F5E2'), ('#BFA2F7', '#8E6FD8', '#E4D8FF')]
tiles = ''.join(tile(34 + i * 244, 726, 224, *T[i]) for i in range(4))
K, HX, HY = 1.56, 512 - 256 * 1.56, 96
body = (defs + '<rect width="1024" height="1024" fill="url(#bgI)"/>' + rays
        + '<circle cx="512" cy="440" r="470" fill="url(#halo)"/>'
        + sparkle(150, 190, 46) + sparkle(884, 150, 34, .9) + sparkle(900, 420, 22, .8) + sparkle(120, 470, 20, .75) + sparkle(236, 96, 16, .7)
        + f'<g transform="translate({HX} {HY}) scale({K})">' + bandana() + head('open', 'smile') + '</g>'
        + '<ellipse cx="512" cy="748" rx="360" ry="40" fill="#1F5FA8" opacity=".28" filter="url(#blur12)"/>'
        + tiles + '<rect y="820" width="1024" height="204" fill="url(#floor)"/>'
        + paw(262, 742, 1.0, -8) + paw(762, 742, 1.0, 8))
open(os.path.join(OUT, 'E1_icon.svg'), 'w').write(svg(1024, 1024, body, px=1024))
