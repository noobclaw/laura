#!/usr/bin/env python3
"""Collision containment check (owner bug reports: into a box, through the ceiling, inside a bush).
A cat starts at many random floor spots and pushes forward (sometimes jumping, which sticks it to walls and climbs them) for a few
seconds each. After every step: the body must not be inside a solid, not above the ceiling without a ceiling over it, not outside
the house bounds. Also reports how often the safety net had to pull a body back (G.contained): each of those is a hole somewhere else.
usage: containcheck.py [TRIALS]"""
import sys, pathlib, json
from playwright.sync_api import sync_playwright
ARGS = ["--no-sandbox", "--disable-gpu-sandbox", "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist", "--allow-file-access-from-files"]
ROOT = pathlib.Path(__file__).resolve().parent.parent / "index.html"
N = int(sys.argv[1]) if len(sys.argv) > 1 else 60
JS = """(n) => { const G = SG.game, R = SG.room, P = R.platforms, b = R.bounds, H = SG.ROOM.H * SG.WS; G.noRender = true; G.noContain = !!window.NOCONTAIN; let travel = 0; G.settings.dogs = 1; G.start('cat'); G.skip && 0;
  let me = G.me; let rs = 12345; const rnd = () => (rs = (rs * 16807) % 2147483647) / 2147483647;
  function solid(x, y, z) { for (const p of P) if (x > p.x0 && x < p.x1 && z > p.z0 && z < p.z1 && y > p.y0 && y < p.y1) return p; return null; }
  function bad(e) { const h = e.h || 0.3; if (!(e.x > b.x0 - 0.2 && e.x < b.x1 + 0.2 && e.z > b.z0 - 0.2 && e.z < b.z1 + 0.2)) return 'outside';
    let ceil = false; for (const p of P) if (e.x > p.x0 && e.x < p.x1 && e.z > p.z0 && e.z < p.z1 && p.y0 >= e.y + (e.cling ? -0.05 : 0.05)) { ceil = true; break; }
    if (!ceil && e.y > H - 0.3) return 'above ceiling'; if (!e.cling && solid(e.x, e.y + Math.max(0.08, h * 0.5), e.z)) return 'inside solid'; return null; }
  const out = { trials: 0, steps: 0, bad: {}, contained0: G.contained || 0, maxY: 0 };
  for (let t = 0; t < n; t++) {
    let x, z, y, k = 0; do { x = b.x0 + rnd() * (b.x1 - b.x0); z = b.z0 + rnd() * (b.z1 - b.z0); y = R.groundAt(x, z, 8, 0); k++; } while ((solid(x, y + 0.3, z) || y > H - 0.5) && k < 200);
    if (G.state) G.state.left = 999; G.place('you', x, y, z, rnd() * 6.28); me.c.setPose('stand'); G.cam.yaw = me.yaw + Math.PI; G.keys.w = true; out.trials++;
    for (let s = 0; s < 240; s++) { G.keys[' '] = (s % 50) < 3 || (s > 120 && rnd() < 0.1); { const px = me.x, pz = me.z; G.step(1 / 60); travel += Math.hypot(me.x - px, me.z - pz); } out.steps++; out.maxY = Math.max(out.maxY, me.y); const r = bad(me); if (r) out.bad[r] = (out.bad[r] || 0) + 1; if (s % 60 === 0) G.cam.yaw += (rnd() - 0.5) * 2; }
    G.keys.w = false; G.keys[' '] = false;
  }
  // climbing: stand in front of every tall wall face, jump onto it and keep climbing (W + space) for 6 s
  out.climbs = 0; out.clung = 0; out.reachedTop = 0;
  const walls = P.filter(p => p.wall && p.y1 > 2.5 && p.y0 < 0.1);
  for (const w of walls) for (const side of [-1, 1]) {
    const alongX = (w.x1 - w.x0) > (w.z1 - w.z0), cx = (w.x0 + w.x1) / 2, cz = (w.z0 + w.z1) / 2;
    let x = alongX ? cx + (rnd() - 0.5) * (w.x1 - w.x0) * 0.6 : (side < 0 ? w.x0 : w.x1) + side * 0.4, z = alongX ? (side < 0 ? w.z0 : w.z1) + side * 0.4 : cz + (rnd() - 0.5) * (w.z1 - w.z0) * 0.6;
    if (!(x > b.x0 && x < b.x1 && z > b.z0 && z < b.z1)) continue; const y = R.groundAt(x, z, 1.5, 0); if (solid(x, y + 0.3, z) || y > 1) continue;
    const yaw = alongX ? (side < 0 ? 0 : Math.PI) : (side < 0 ? Math.PI / 2 : -Math.PI / 2);
    if (G.state) G.state.left = 999; G.place('you', x, y + 1.0, z, yaw); me.c.setPose('stand'); G.cam.yaw = yaw + Math.PI; out.climbs++; let clung = !!G.tryAttach(me, 0, 0, [[alongX ? 2 : 0, -side]]);
    G.keys.w = true; for (let s = 0; s < 420; s++) { G.keys[' '] = s < 4 || (s > 30 && s < 34) || (me.cling && true); G.step(1 / 60); out.steps++; if (me.cling) clung = true; out.maxY = Math.max(out.maxY, me.y); const r = bad(me); if (r) { out.bad[r] = (out.bad[r] || 0) + 1; if (!out.sample) out.sample = [me.x, me.y, me.z, b.x0, b.x1, b.z0, b.z1, !!me.cling, G.mode, me.out, G.contained || 0]; } }
    G.keys.w = false; G.keys[' '] = false; if (clung) out.clung++; if (me.y > 2.5) out.reachedTop++;
  }
  out.contained = (G.contained || 0) - out.contained0; out.H = H; out.why = G.containWhy; out.travel = +travel.toFixed(1); out.at = G.containAt; return out; }"""
with sync_playwright() as p:
    b = p.chromium.launch(executable_path="/usr/bin/google-chrome", headless=True, args=ARGS)
    pg = b.new_page(viewport={"width": 640, "height": 360}); errs = []
    pg.on("pageerror", lambda e: errs.append(str(e)))
    pg.goto(ROOT.as_uri() + "?q=low&nolock=1"); pg.wait_for_function("window.__ready===true||window.__error", timeout=180000)
    pg.wait_for_timeout(3000)
    pg.evaluate("window.NOCONTAIN=%s" % ("true" if len(sys.argv) > 2 else "false")); r = pg.evaluate(JS, N); r["pageErrors"] = errs[:3]; r["frameErrors"] = pg.evaluate("SG.game.errors||0")
    print(json.dumps(r)); ok = not r["bad"] and not errs and r["frameErrors"] == 0 and r["maxY"] > 2.2 and r["clung"] > 0
    print("RESULT", "PASS" if ok else "FAIL")
    b.close()
