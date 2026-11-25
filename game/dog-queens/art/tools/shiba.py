# Mochi the shiba: shared drawing parts. Every pose reuses the same head so the dog stays on model.
# Output is plain SVG; render with rsvg-convert. Random fur strands use fixed seeds, so output is stable.
import math, random

HEAD = ('M256 92 C268 78 286 80 292 96 C380 104 444 176 446 262 C460 286 462 316 444 330 C450 352 436 372 420 380 '
        'C388 420 330 436 256 436 C182 436 124 420 92 380 C76 372 62 352 68 330 C50 316 52 286 66 262 '
        'C68 176 132 104 220 96 C228 80 246 80 256 92Z')
URA = ('M58 306 C84 284 104 300 116 282 C134 244 170 230 204 248 C226 260 236 282 256 284 C276 282 286 260 308 248 '
       'C342 230 378 244 396 282 C408 300 428 284 454 306 L454 446 L58 446 Z')

DEFS = '''<defs>
  <radialGradient id="fur" cx="40%" cy="22%" r="85%"><stop offset="0" stop-color="#FFC888"/><stop offset=".4" stop-color="#F7A050"/><stop offset=".8" stop-color="#E27A30"/><stop offset="1" stop-color="#C9621F"/></radialGradient>
  <radialGradient id="furSide" cx="30%" cy="25%" r="90%"><stop offset="0" stop-color="#FDB66C"/><stop offset=".6" stop-color="#EE8B3C"/><stop offset="1" stop-color="#C55E1D"/></radialGradient>
  <radialGradient id="ear" cx="40%" cy="25%" r="85%"><stop offset="0" stop-color="#FDB468"/><stop offset="1" stop-color="#CC6322"/></radialGradient>
  <linearGradient id="earIn" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#F8B9A6"/><stop offset=".6" stop-color="#FFE3D3"/><stop offset="1" stop-color="#FFF4EA"/></linearGradient>
  <radialGradient id="cream" cx="50%" cy="25%" r="80%"><stop offset="0" stop-color="#FFFFFC"/><stop offset=".65" stop-color="#FFF2E2"/><stop offset="1" stop-color="#EFD2B3"/></radialGradient>
  <radialGradient id="creamBody" cx="45%" cy="30%" r="80%"><stop offset="0" stop-color="#FFFFFC"/><stop offset=".7" stop-color="#FFF0DE"/><stop offset="1" stop-color="#EBCBA9"/></radialGradient>
  <radialGradient id="iris" cx="50%" cy="62%" r="55%"><stop offset="0" stop-color="#9A5A2E"/><stop offset=".55" stop-color="#5A2F17"/><stop offset="1" stop-color="#1C0D06"/></radialGradient>
  <radialGradient id="nose" cx="38%" cy="28%" r="75%"><stop offset="0" stop-color="#6E5148"/><stop offset=".6" stop-color="#2E1D17"/><stop offset="1" stop-color="#140B08"/></radialGradient>
  <radialGradient id="blush" cx="50%" cy="50%" r="50%"><stop offset="0" stop-color="#FF8A98" stop-opacity=".6"/><stop offset="1" stop-color="#FF8A98" stop-opacity="0"/></radialGradient>
  <radialGradient id="ao" cx="50%" cy="58%" r="50%"><stop offset=".72" stop-color="#B4561C" stop-opacity="0"/><stop offset=".9" stop-color="#B4561C" stop-opacity=".18"/><stop offset="1" stop-color="#B4561C" stop-opacity="0"/></radialGradient>
  <radialGradient id="pad" cx="45%" cy="35%" r="70%"><stop offset="0" stop-color="#FFB3BE"/><stop offset="1" stop-color="#E9818F"/></radialGradient>
  <pattern id="gingham" width="26" height="26" patternUnits="userSpaceOnUse" patternTransform="rotate(-8)"><rect width="26" height="26" fill="#C9F4E4"/><rect width="13" height="26" fill="#5FCBA8" opacity=".55"/><rect width="26" height="13" fill="#5FCBA8" opacity=".55"/></pattern>
  <linearGradient id="bandShade" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0B6B55" stop-opacity=".35"/><stop offset=".4" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#0B6B55" stop-opacity=".25"/></linearGradient>
  <linearGradient id="fluffCol" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#F09040"/><stop offset=".55" stop-color="#F09040"/><stop offset=".62" stop-color="#FBEBD8"/><stop offset="1" stop-color="#F4DCC2"/></linearGradient>
  <filter id="fluff" x="-10%" y="-10%" width="120%" height="120%"><feTurbulence type="fractalNoise" baseFrequency="0.22 0.22" numOctaves="1" seed="3" result="n"/><feDisplacementMap in="SourceGraphic" in2="n" scale="9" xChannelSelector="R" yChannelSelector="G"/></filter>
  <filter id="fluffS" x="-10%" y="-10%" width="120%" height="120%"><feTurbulence type="fractalNoise" baseFrequency="0.25 0.25" numOctaves="1" seed="5" result="n"/><feDisplacementMap in="SourceGraphic" in2="n" scale="7" xChannelSelector="R" yChannelSelector="G"/></filter>
  <filter id="blur3" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="3"/></filter>
  <filter id="blur6" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="6"/></filter>
  <filter id="blur12" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="12"/></filter>
  <clipPath id="headClip"><path d="''' + HEAD + '''"/></clipPath>
  <clipPath id="eyeL"><ellipse cx="182" cy="268" rx="35" ry="41"/></clipPath>
  <clipPath id="eyeR"><ellipse cx="330" cy="268" rx="35" ry="41"/></clipPath>
</defs>'''


def strands(R, n, cx, cy, rx, ry, cols, wmin, wmax, lmin, lmax, op, flow):
    out = []
    for _ in range(n):
        a = R.uniform(0, 2 * math.pi); r = math.sqrt(R.random())
        x = cx + math.cos(a) * rx * r; y = cy + math.sin(a) * ry * r
        ang = flow(x, y) + R.uniform(-.25, .25); L = R.uniform(lmin, lmax)
        x2 = x + math.cos(ang) * L; y2 = y + math.sin(ang) * L
        mx = (x + x2) / 2 + math.cos(ang + 1.57) * L * .18; my = (y + y2) / 2 + math.sin(ang + 1.57) * L * .18
        out.append(f'<path d="M{x:.1f} {y:.1f} Q{mx:.1f} {my:.1f} {x2:.1f} {y2:.1f}" stroke="{R.choice(cols)}" '
                   f'stroke-width="{R.uniform(wmin, wmax):.1f}" stroke-linecap="round" fill="none" opacity="{op * R.uniform(.5, 1):.2f}"/>')
    return '\n'.join(out)


def eyes(kind):
    if kind in ('open', 'surprise'):
        k = 1.12 if kind == 'surprise' else 1.0
        out = []
        for cx, clip in ((182, 'eyeL'), (330, 'eyeR')):
            rx, ry = 35 * k, 41 * k
            out.append(f'<ellipse cx="{cx}" cy="268" rx="{rx}" ry="{ry}" fill="#140904"/>')
            out.append(f'<g clip-path="url(#{clip})" transform="translate({cx} 268) scale({k}) translate({-cx} -268)">'
                       f'<circle cx="{cx}" cy="276" r="31" fill="url(#iris)"/>'
                       f'<circle cx="{cx}" cy="276" r="{12 if kind == "surprise" else 16}" fill="#0E0603"/>'
                       f'<ellipse cx="{cx}" cy="232" rx="40" ry="16" fill="#000" opacity=".35" filter="url(#blur3)"/>'
                       f'<path d="M{cx-22} 296 C{cx-10} 306 {cx+12} 306 {cx+22} 294" stroke="#C9884F" stroke-width="4" fill="none" opacity=".6"/></g>')
            out.append(f'<ellipse cx="{cx-14}" cy="252" rx="13" ry="14" fill="#fff"/>'
                       f'<circle cx="{cx+14}" cy="286" r="6" fill="#fff" opacity=".9"/><circle cx="{cx+4}" cy="246" r="3.5" fill="#fff" opacity=".8"/>')
        return '\n'.join(out)
    if kind == 'joy':      # happy closed eyes, arched up
        return ''.join(f'<path d="M{cx-30} 280 Q{cx} 236 {cx+30} 280" stroke="#2A170E" stroke-width="11" fill="none" stroke-linecap="round"/>'
                       for cx in (182, 330))
    if kind == 'sleep':    # relaxed closed eyes, curved down
        return ''.join(f'<path d="M{cx-28} 266 Q{cx} 292 {cx+28} 266" stroke="#2A170E" stroke-width="9" fill="none" stroke-linecap="round"/>'
                       f'<path d="M{cx-24} 262 Q{cx-30} 258 {cx-36} 262" stroke="#2A170E" stroke-width="5" fill="none" stroke-linecap="round" opacity=".7"/>'
                       for cx in (182, 330))
    if kind == 'squeeze':  # embarrassed > <
        return ('<path d="M156 250 L204 270 L156 288" stroke="#2A170E" stroke-width="11" fill="none" stroke-linecap="round" stroke-linejoin="round"/>'
                '<path d="M356 250 L308 270 L356 288" stroke="#2A170E" stroke-width="11" fill="none" stroke-linecap="round" stroke-linejoin="round"/>')
    return ''


def mouth(kind):
    base = '<path d="M256 334 L256 348" stroke="#3A2218" stroke-width="4.5" stroke-linecap="round"/>'
    if kind == 'smile':
        return (base + '<path d="M224 346 C236 366 252 364 256 348 C260 364 276 366 288 346" fill="none" stroke="#3A2218" stroke-width="4.5" stroke-linecap="round" stroke-linejoin="round"/>'
                '<path d="M243 359 C244 382 268 382 269 359 C262 364 250 364 243 359Z" fill="#FF7685"/>'
                '<path d="M256 362 L256 374" stroke="#E0506A" stroke-width="2" opacity=".6"/><ellipse cx="250" cy="366" rx="4" ry="2.5" fill="#fff" opacity=".5"/>')
    if kind == 'open':    # big happy open mouth with tongue
        return (base + '<path d="M218 346 C226 348 246 352 256 348 C266 352 286 348 294 346 C292 382 274 400 256 400 C238 400 220 382 218 346Z" fill="#5A1E22"/>'
                '<path d="M232 378 C236 410 276 410 280 378 C270 370 242 370 232 378Z" fill="#FF7685"/>'
                '<path d="M256 380 L256 398" stroke="#E0506A" stroke-width="2.5" opacity=".6"/>'
                '<path d="M218 346 C226 348 246 352 256 348 C266 352 286 348 294 346" fill="none" stroke="#3A2218" stroke-width="4.5" stroke-linecap="round"/>')
    if kind == 'o':
        return base.replace('L256 348', 'L256 344') + '<ellipse cx="256" cy="360" rx="13" ry="15" fill="#5A1E22"/><ellipse cx="256" cy="368" rx="8" ry="5" fill="#FF7685"/>'
    if kind == 'wobble':  # embarrassed wavy mouth
        return base + '<path d="M228 356 Q236 348 244 356 Q252 364 260 356 Q268 348 276 356 Q284 364 290 356" fill="none" stroke="#3A2218" stroke-width="4.5" stroke-linecap="round"/>'
    if kind == 'sleep':
        return base + '<path d="M240 350 C248 358 264 358 272 350" fill="none" stroke="#3A2218" stroke-width="4.5" stroke-linecap="round"/>'
    return base


def head(eye='open', mouth_kind='smile', seed=7, ears='up'):
    """The head in its own 512 box. Place it with a transform."""
    R = random.Random(seed)
    flow_out = lambda x, y: math.atan2(y - 300, x - 256)
    flow_down = lambda x, y: math.atan2(y - 300, x - 256) * .4 + 1.2
    if ears == 'up':
        ear = ('<path d="M116 214 C92 150 96 88 122 54 C134 38 152 40 168 56 C198 86 224 120 240 152 Z" fill="url(#ear)"/>'
               '<path d="M132 182 C120 140 122 102 138 78 C146 68 156 70 166 80 C184 100 202 124 212 148 Z" fill="url(#earIn)"/>'
               '<path d="M396 214 C420 150 416 88 390 54 C378 38 360 40 344 56 C314 86 288 120 272 152 Z" fill="url(#ear)"/>'
               '<path d="M380 182 C392 140 390 102 374 78 C366 68 356 70 346 80 C328 100 310 124 300 148 Z" fill="url(#earIn)"/>')
        ear += strands(R, 26, 158, 150, 26, 40, ['#FFFFFF', '#FFF1E6'], 1.4, 2.4, 10, 22, .7, lambda x, y: -1.9)
        ear += strands(R, 26, 354, 150, 26, 40, ['#FFFFFF', '#FFF1E6'], 1.4, 2.4, 10, 22, .7, lambda x, y: -1.25)
    else:  # ears folded back and down (sad / embarrassed)
        ear = ('<path d="M104 196 C70 170 46 130 54 96 C58 80 74 76 92 84 C130 102 176 128 214 160 Z" fill="url(#ear)"/>'
               '<path d="M116 174 C90 154 74 128 78 106 C82 96 92 94 104 100 C132 114 162 134 188 156 Z" fill="url(#earIn)"/>'
               '<path d="M408 196 C442 170 466 130 458 96 C454 80 438 76 420 84 C382 102 336 128 298 160 Z" fill="url(#ear)"/>'
               '<path d="M396 174 C422 154 438 128 434 106 C430 96 420 94 408 100 C380 114 350 134 324 156 Z" fill="url(#earIn)"/>')
    blushes = ('<ellipse cx="126" cy="324" rx="40" ry="25" fill="url(#blush)"/><ellipse cx="386" cy="324" rx="40" ry="25" fill="url(#blush)"/>'
               '<g fill="#FF8E9C" opacity=".5"><circle cx="114" cy="324" r="2.2"/><circle cx="126" cy="320" r="2.2"/><circle cx="138" cy="326" r="2.2"/>'
               '<circle cx="374" cy="326" r="2.2"/><circle cx="386" cy="320" r="2.2"/><circle cx="398" cy="324" r="2.2"/></g>')
    ao = ('<ellipse cx="182" cy="270" rx="44" ry="50" fill="url(#ao)"/><ellipse cx="330" cy="270" rx="44" ry="50" fill="url(#ao)"/>'
          if eye in ('open', 'surprise') else '')
    return f'''<g>
{ear}
<path d="{HEAD}" fill="url(#fluffCol)" filter="url(#fluff)"/>
<path d="{HEAD}" fill="url(#fur)"/>
<g clip-path="url(#headClip)">
  <path d="{URA}" fill="url(#cream)"/>
  {strands(R, 150, 256, 180, 175, 100, ['#FFD9A8', '#FFC587', '#E88A43'], 1.0, 1.8, 7, 14, .28, flow_out)}
  {strands(R, 140, 256, 370, 185, 80, ['#FFFFFF', '#F1DCC6'], 1.0, 1.8, 6, 12, .35, flow_down)}
  <ellipse cx="206" cy="150" rx="120" ry="48" fill="#FFE6C2" opacity=".45" filter="url(#blur12)"/>
  <path d="M424 184 C448 224 452 274 442 314" stroke="#FFE9CC" stroke-width="12" fill="none" opacity=".5" filter="url(#blur6)"/>
  <ellipse cx="256" cy="452" rx="230" ry="62" fill="#B98454" opacity=".28" filter="url(#blur12)"/>
  {ao}
</g>
<ellipse cx="186" cy="204" rx="21" ry="13" fill="#FFF6EA"/><ellipse cx="326" cy="204" rx="21" ry="13" fill="#FFF6EA"/>
<ellipse cx="190" cy="200" rx="9" ry="4" fill="#fff" opacity=".8"/><ellipse cx="330" cy="200" rx="9" ry="4" fill="#fff" opacity=".8"/>
{eyes(eye)}
{blushes}
<ellipse cx="256" cy="340" rx="72" ry="52" fill="#FFFDF9"/>
<ellipse cx="256" cy="372" rx="62" ry="22" fill="#E8CBAE" opacity=".35" filter="url(#blur6)"/>
<g fill="#C9A486" opacity=".55"><circle cx="222" cy="336" r="2"/><circle cx="214" cy="346" r="2"/><circle cx="226" cy="350" r="2"/><circle cx="290" cy="336" r="2"/><circle cx="298" cy="346" r="2"/><circle cx="286" cy="350" r="2"/></g>
<path d="M230 306 C230 294 282 294 282 306 C282 322 266 332 256 334 C246 332 230 322 230 306Z" fill="url(#nose)"/>
<ellipse cx="246" cy="303" rx="10" ry="4.5" fill="#fff" opacity=".6"/>
<path d="M243 318 C246 316 248 318 247 321" stroke="#000" stroke-width="2" fill="none" opacity=".5"/><path d="M269 318 C266 316 264 318 265 321" stroke="#000" stroke-width="2" fill="none" opacity=".5"/>
{mouth(mouth_kind)}
</g>'''


def bandana(scale=1.0):
    return '''<g>
<path d="M110 388 C186 432 326 432 402 388 L412 432 C344 478 168 478 100 432 Z" fill="url(#gingham)"/>
<path d="M110 388 C186 432 326 432 402 388 L412 432 C344 478 168 478 100 432 Z" fill="url(#bandShade)"/>
<path d="M222 450 L256 506 L290 450 Z" fill="url(#gingham)"/><path d="M222 450 L256 506 L290 450 Z" fill="url(#bandShade)"/>
<path d="M108 432 C170 474 342 474 404 432" stroke="#fff" stroke-width="3" fill="none" opacity=".45"/></g>'''


def fur_shape(d, fill='url(#furSide)', seed=1, cream=False, strokes=60, box=None):
    """A fluffy body part: fuzzy rim, gradient fill, fur strands clipped inside."""
    R = random.Random(seed)
    cid = f'clip{seed}'
    rim = '#FBEBD8' if cream else '#EE8B3C'
    s = f'<clipPath id="{cid}"><path d="{d}"/></clipPath>'
    s += f'<path d="{d}" fill="{rim}" filter="url(#fluffS)"/><path d="{d}" fill="{fill}"/>'
    if box:
        x0, y0, x1, y1 = box
        cols = ['#FFFFFF', '#F1DCC6'] if cream else ['#FFD9A8', '#FFC587', '#E88A43']
        s += f'<g clip-path="url(#{cid})">' + strands(R, strokes, (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2, (y1 - y0) / 2,
                                                      cols, 1.0, 1.8, 6, 12, .3, lambda x, y: 1.4) + '</g>'
    return s


def svg(w, h, body, px=None):
    px = px or w * 2
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{px}" height="{int(px * h / w)}">'
            + DEFS + body + '</svg>')
