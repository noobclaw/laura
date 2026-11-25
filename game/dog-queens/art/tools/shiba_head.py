# Draws the shiba head token as SVG. Fur strands are placed with a fixed seed so the output is stable.
import math, random, sys
R = random.Random(7)
HEAD = 'M256 92 C268 78 286 80 292 96 C380 104 444 176 446 262 C460 286 462 316 444 330 C450 352 436 372 420 380 C388 420 330 436 256 436 C182 436 124 420 92 380 C76 372 62 352 68 330 C50 316 52 286 66 262 C68 176 132 104 220 96 C228 80 246 80 256 92Z'
URA = 'M58 306 C84 284 104 300 116 282 C134 244 170 230 204 248 C226 260 236 282 256 284 C276 282 286 260 308 248 C342 230 378 244 396 282 C408 300 428 284 454 306 L454 446 L58 446 Z'

def strands(n, cx, cy, rx, ry, cols, wmin, wmax, lmin, lmax, op, flow):
    out = []
    for _ in range(n):
        a = R.uniform(0, 2*math.pi); r = math.sqrt(R.random())
        x = cx + math.cos(a)*rx*r; y = cy + math.sin(a)*ry*r
        ang = flow(x, y) + R.uniform(-.25, .25); L = R.uniform(lmin, lmax)
        x2 = x + math.cos(ang)*L; y2 = y + math.sin(ang)*L
        mx = (x+x2)/2 + math.cos(ang+1.57)*L*.18; my = (y+y2)/2 + math.sin(ang+1.57)*L*.18
        out.append(f'<path d="M{x:.1f} {y:.1f} Q{mx:.1f} {my:.1f} {x2:.1f} {y2:.1f}" stroke="{R.choice(cols)}" stroke-width="{R.uniform(wmin,wmax):.1f}" stroke-linecap="round" fill="none" opacity="{op*R.uniform(.5,1):.2f}"/>')
    return '\n'.join(out)

# fur flows outward from the face centre (256,300)
flow_out = lambda x, y: math.atan2(y-300, x-256)
flow_down = lambda x, y: math.atan2(y-300, x-256)*.4 + 1.2

def edge_tufts(path_pts, col, n):
    # small pointed tufts around the head outline for a fluffy silhouette
    out = []
    for i in range(n):
        t = i/n*2*math.pi; jitter = R.uniform(-.03,.03)
        a = t + jitter
        rx, ry = 192 + R.uniform(-4,4), 172
        cx, cy = 256 + math.cos(a)*rx, 264 + math.sin(a)*ry
        if cy < 140 and abs(cx-256) > 60: continue   # ears sit there
        nx, ny = math.cos(a), math.sin(a)
        L = R.uniform(10, 18); w = R.uniform(7, 12)
        tx, ty = cx + nx*L, cy + ny*L
        px, py = -ny*w, nx*w
        out.append(f'<path d="M{cx+px:.1f} {cy+py:.1f} Q{tx:.1f} {ty:.1f} {tx:.1f} {ty:.1f} Q{tx:.1f} {ty:.1f} {cx-px:.1f} {cy-py:.1f} Z" fill="{col(cy)}"/>')
    return '\n'.join(out)

def tuft_col(y):
    return 'url(#fur)' if y < 300 else '#FFF3E4'

svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="1024" height="1024">
<defs>
  <radialGradient id="fur" cx="40%" cy="22%" r="85%">
    <stop offset="0" stop-color="#FFC888"/><stop offset=".4" stop-color="#F7A050"/><stop offset=".8" stop-color="#E27A30"/><stop offset="1" stop-color="#C9621F"/>
  </radialGradient>
  <radialGradient id="ear" cx="40%" cy="25%" r="85%"><stop offset="0" stop-color="#FDB468"/><stop offset="1" stop-color="#CC6322"/></radialGradient>
  <linearGradient id="earIn" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#F8B9A6"/><stop offset=".6" stop-color="#FFE3D3"/><stop offset="1" stop-color="#FFF4EA"/></linearGradient>
  <radialGradient id="cream" cx="50%" cy="25%" r="80%"><stop offset="0" stop-color="#FFFFFC"/><stop offset=".65" stop-color="#FFF2E2"/><stop offset="1" stop-color="#EFD2B3"/></radialGradient>
  <radialGradient id="iris" cx="50%" cy="62%" r="55%"><stop offset="0" stop-color="#9A5A2E"/><stop offset=".55" stop-color="#5A2F17"/><stop offset="1" stop-color="#1C0D06"/></radialGradient>
  <radialGradient id="nose" cx="38%" cy="28%" r="75%"><stop offset="0" stop-color="#6E5148"/><stop offset=".6" stop-color="#2E1D17"/><stop offset="1" stop-color="#140B08"/></radialGradient>
  <radialGradient id="blush" cx="50%" cy="50%" r="50%"><stop offset="0" stop-color="#FF8A98" stop-opacity=".6"/><stop offset="1" stop-color="#FF8A98" stop-opacity="0"/></radialGradient>
  <radialGradient id="ao" cx="50%" cy="58%" r="50%"><stop offset=".72" stop-color="#B4561C" stop-opacity="0"/><stop offset=".9" stop-color="#B4561C" stop-opacity=".18"/><stop offset="1" stop-color="#B4561C" stop-opacity="0"/></radialGradient>
  <pattern id="gingham" width="26" height="26" patternUnits="userSpaceOnUse" patternTransform="rotate(-8)">
    <rect width="26" height="26" fill="#C9F4E4"/><rect width="13" height="26" fill="#5FCBA8" opacity=".55"/><rect width="26" height="13" fill="#5FCBA8" opacity=".55"/>
  </pattern>
  <linearGradient id="bandShade" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0B6B55" stop-opacity=".35"/><stop offset=".4" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#0B6B55" stop-opacity=".25"/></linearGradient>
  <filter id="blur6" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="6"/></filter>
  <filter id="blur3" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="3"/></filter>
  <filter id="blur12" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="12"/></filter>
  <linearGradient id="fluffCol" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#F09040"/><stop offset=".55" stop-color="#F09040"/><stop offset=".62" stop-color="#FBEBD8"/><stop offset="1" stop-color="#F4DCC2"/></linearGradient>
  <filter id="fluff" x="-10%" y="-10%" width="120%" height="120%">
    <feTurbulence type="fractalNoise" baseFrequency="0.09" numOctaves="2" seed="3" result="n"/>
    <feDisplacementMap in="SourceGraphic" in2="n" scale="16" xChannelSelector="R" yChannelSelector="G"/>
  </filter>
  <clipPath id="headClip"><path d="{HEAD}"/></clipPath>
  <clipPath id="eyeL"><ellipse cx="182" cy="268" rx="35" ry="41"/></clipPath>
  <clipPath id="eyeR"><ellipse cx="330" cy="268" rx="35" ry="41"/></clipPath>
</defs>

<ellipse cx="256" cy="478" rx="150" ry="16" fill="#3A2A20" opacity=".16" filter="url(#blur6)"/>

<!-- ears -->
<path d="M116 214 C92 150 96 88 122 54 C134 38 152 40 168 56 C198 86 224 120 240 152 Z" fill="url(#ear)"/>
<path d="M132 182 C120 140 122 102 138 78 C146 68 156 70 166 80 C184 100 202 124 212 148 Z" fill="url(#earIn)"/>
<path d="M396 214 C420 150 416 88 390 54 C378 38 360 40 344 56 C314 86 288 120 272 152 Z" fill="url(#ear)"/>
<path d="M380 182 C392 140 390 102 374 78 C366 68 356 70 346 80 C328 100 310 124 300 148 Z" fill="url(#earIn)"/>
{strands(26,158,150,26,40,['#FFFFFF','#FFF1E6'],1.4,2.4,10,22,.7,lambda x,y:-1.9)}
{strands(26,354,150,26,40,['#FFFFFF','#FFF1E6'],1.4,2.4,10,22,.7,lambda x,y:-1.25)}

<!-- bandana -->
<g>
  <path d="M110 388 C186 432 326 432 402 388 L412 432 C344 478 168 478 100 432 Z" fill="url(#gingham)"/>
  <path d="M110 388 C186 432 326 432 402 388 L412 432 C344 478 168 478 100 432 Z" fill="url(#bandShade)"/>
  <path d="M222 450 L256 506 L290 450 Z" fill="url(#gingham)"/>
  <path d="M222 450 L256 506 L290 450 Z" fill="url(#bandShade)"/>
  <path d="M108 432 C170 474 342 474 404 432" stroke="#fff" stroke-width="3" fill="none" opacity=".45"/>
</g>

<!-- head base and fluffy rim -->
<path d="{HEAD}" fill="url(#fluffCol)" filter="url(#fluff)"/>
<path d="{HEAD}" fill="url(#fur)"/>
<g clip-path="url(#headClip)">
  <path d="{URA}" fill="url(#cream)"/>
  {strands(150,256,180,175,100,['#FFD9A8','#FFC587','#E88A43'],1.0,1.8,7,14,.28,flow_out)}
  {strands(140,256,370,185,80,['#FFFFFF','#F1DCC6'],1.0,1.8,6,12,.35,flow_down)}
  <ellipse cx="206" cy="150" rx="120" ry="48" fill="#FFE6C2" opacity=".45" filter="url(#blur12)"/>
  <path d="M424 184 C448 224 452 274 442 314" stroke="#FFE9CC" stroke-width="12" fill="none" opacity=".5" filter="url(#blur6)"/>
  <ellipse cx="256" cy="452" rx="230" ry="62" fill="#B98454" opacity=".28" filter="url(#blur12)"/>
  <!-- soft occlusion around eyes -->
  <ellipse cx="182" cy="270" rx="44" ry="50" fill="url(#ao)"/>
  <ellipse cx="330" cy="270" rx="44" ry="50" fill="url(#ao)"/>
</g>

<!-- maro brows -->
<ellipse cx="186" cy="204" rx="21" ry="13" fill="#FFF6EA"/><ellipse cx="326" cy="204" rx="21" ry="13" fill="#FFF6EA"/>
<ellipse cx="190" cy="200" rx="9" ry="4" fill="#fff" opacity=".8"/><ellipse cx="330" cy="200" rx="9" ry="4" fill="#fff" opacity=".8"/>

<!-- eyes -->
<g>
  <ellipse cx="182" cy="268" rx="35" ry="41" fill="#140904"/>
  <g clip-path="url(#eyeL)">
    <circle cx="182" cy="276" r="31" fill="url(#iris)"/>
    <circle cx="182" cy="276" r="16" fill="#0E0603"/>
    <ellipse cx="182" cy="232" rx="40" ry="16" fill="#000" opacity=".35" filter="url(#blur3)"/>
    <path d="M160 296 C172 306 194 306 204 294" stroke="#C9884F" stroke-width="4" fill="none" opacity=".6"/>
  </g>
  <ellipse cx="330" cy="268" rx="35" ry="41" fill="#140904"/>
  <g clip-path="url(#eyeR)">
    <circle cx="330" cy="276" r="31" fill="url(#iris)"/>
    <circle cx="330" cy="276" r="16" fill="#0E0603"/>
    <ellipse cx="330" cy="232" rx="40" ry="16" fill="#000" opacity=".35" filter="url(#blur3)"/>
    <path d="M308 296 C320 306 342 306 352 294" stroke="#C9884F" stroke-width="4" fill="none" opacity=".6"/>
  </g>
  <ellipse cx="168" cy="252" rx="13" ry="14" fill="#fff"/><ellipse cx="316" cy="252" rx="13" ry="14" fill="#fff"/>
  <circle cx="196" cy="286" r="6" fill="#fff" opacity=".9"/><circle cx="344" cy="286" r="6" fill="#fff" opacity=".9"/>
  <circle cx="186" cy="246" r="3.5" fill="#fff" opacity=".8"/><circle cx="334" cy="246" r="3.5" fill="#fff" opacity=".8"/>
</g>

<!-- blush -->
<ellipse cx="126" cy="324" rx="40" ry="25" fill="url(#blush)"/><ellipse cx="386" cy="324" rx="40" ry="25" fill="url(#blush)"/>
<g fill="#FF8E9C" opacity=".5"><circle cx="114" cy="324" r="2.2"/><circle cx="126" cy="320" r="2.2"/><circle cx="138" cy="326" r="2.2"/><circle cx="374" cy="326" r="2.2"/><circle cx="386" cy="320" r="2.2"/><circle cx="398" cy="324" r="2.2"/></g>

<!-- muzzle -->
<ellipse cx="256" cy="340" rx="72" ry="52" fill="#FFFDF9"/>
<ellipse cx="256" cy="372" rx="62" ry="22" fill="#E8CBAE" opacity=".35" filter="url(#blur6)"/>
<g fill="#C9A486" opacity=".55"><circle cx="222" cy="336" r="2"/><circle cx="214" cy="346" r="2"/><circle cx="226" cy="350" r="2"/><circle cx="290" cy="336" r="2"/><circle cx="298" cy="346" r="2"/><circle cx="286" cy="350" r="2"/></g>

<!-- nose -->
<path d="M230 306 C230 294 282 294 282 306 C282 322 266 332 256 334 C246 332 230 322 230 306Z" fill="url(#nose)"/>
<ellipse cx="246" cy="303" rx="10" ry="4.5" fill="#fff" opacity=".6"/>
<path d="M243 318 C246 316 248 318 247 321" stroke="#000" stroke-width="2" fill="none" opacity=".5"/>
<path d="M269 318 C266 316 264 318 265 321" stroke="#000" stroke-width="2" fill="none" opacity=".5"/>

<!-- mouth -->
<path d="M256 334 L256 348" stroke="#3A2218" stroke-width="4.5" stroke-linecap="round"/>
<path d="M224 346 C236 366 252 364 256 348 C260 364 276 366 288 346" fill="none" stroke="#3A2218" stroke-width="4.5" stroke-linecap="round" stroke-linejoin="round"/>
<path d="M243 359 C244 382 268 382 269 359 C262 364 250 364 243 359Z" fill="#FF7685"/>
<path d="M256 362 L256 374" stroke="#E0506A" stroke-width="2" opacity=".6"/>
<ellipse cx="250" cy="366" rx="4" ry="2.5" fill="#fff" opacity=".5"/>
</svg>'''
open(sys.argv[1], 'w').write(svg)
