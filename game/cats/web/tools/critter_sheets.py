"""Evidence sheets for the animals (used by critter_shots.py). Each function drives the studio page and writes PNG / JSON."""
import json, pathlib
from PIL import Image, ImageDraw, ImageFont

POSE_ROW = r"""
var names = SG.POSE_PAGES[__PG__], S = PV.size(), cols = 9, rows = names.length, w = S[0] / cols, h = S[1] / rows, out = {};
var cams = [[1.5, 0.75, 2.0], [3.0, 0.3, 0.0], [0.0, 3.2, 0.3]], amts = [0, 0.5, 1];
names.forEach(function (n, r) { amts.forEach(function (a, ai) { PV.clear(); var b = n === 'drape' ? [6, 0.63, 0.24] : [0, 0, 0], c = PV.spawn('mochi', { pose: n, amount: a, x: b[0], y: b[1], z: b[2] }); out[n + '@' + a] = c.measure().size.map(function (v) { return +v.toFixed(3); });   // drape is shown on the table edge it is meant for
  cams.forEach(function (cm, ci) { PV.look([cm[0] + b[0], cm[1] + b[1], cm[2] + b[2]], [b[0], 0.2 + b[1] * 0.75, b[2]], ci == 2 ? 20 : 19); PV.view((ai * 3 + ci) * w, r * h, w, h); }); }); });
names.forEach(function (n, r) { PV.label(4, r * h + 4, SG.POSE_INFO[n].label + ' ' + n + '  (' + SG.POSE_INFO[n].hint + ')'); });
['amount 0', 'amount 0.5', 'amount 1'].forEach(function (t, i) { PV.label(i * 3 * w + w * 1.2, S[1] - 22, t + ':  3/4 | side | top'); });
return out;
"""

LINEUP = r"""
var keys = Object.keys(SG.CATS), S = PV.size(), w = S[0] / keys.length, h = S[1] / 3, st = [];
var views = [[[0.0, 0.32, 3.3], 'front'], [[3.3, 0.3, 0.0], 'side'], [[0.0, 3.5, 0.01], 'top']];
keys.forEach(function (k, i) { PV.clear(); var c = PV.spawn(k, {}), m = c.measure(), q = SG.critterStats(SG.CATS[k], 1024);
  st.push({ key: k, name: SG.CATS[k].name, scale: c.scale, shoulder_m: +(c.bp.D.shoulder * c.scale).toFixed(3), top_of_head_m: +(c.bp.D.top * c.scale).toFixed(3), width_m: +(SG.CATS[k].hw * 2 * c.scale).toFixed(3), length_m: +((c.bp.D.zF - c.bp.D.zR) * c.scale).toFixed(3), tris: q.tris, verts: q.verts });
  views.forEach(function (v, j) { PV.look(v[0], [0, 0.27, 0.04], 16); PV.view(i * w, j * h, w, h); }); });
keys.forEach(function (k, i) { PV.label(i * w + 6, 6, SG.CATS[k].name + ' ' + SG.CATS[k].tag + ' (' + k + ')'); });
['front', 'side', 'top'].forEach(function (t, j) { PV.label(6, j * h + 30, t); });
return st;
"""

SIZES = r"""
var S = PV.size(), out = [], xs = [-1.5, -0.75, 0.15, 1.3], sc = [0.7, 1, 1.4, 1.7];
PV.clear();
sc.forEach(function (s, i) { var c = PV.spawn('mochi', { x: xs[i], scale: s, yaw: 0.5, tail: 'up', ears: 'up' }), m = c.measure(); out.push({ scale: s, shoulder_m: +(c.bp.D.shoulder * c.scale).toFixed(3), top_of_head_m: +(c.bp.D.top * c.scale).toFixed(3), body_width_m: +(0.27 * s).toFixed(3), length_nose_to_rump_m: +((c.bp.D.zF - c.bp.D.zR) * s).toFixed(3), game_collision_radius_m: +(Math.max(0.12, c.spec.bellyR * 0.95) * s).toFixed(3) }); });
var k = PV.spawn('azuki', { x: -2.2, yaw: 0.5, tail: 'up', ears: 'up' }); out.push({ build: 'azuki (kitten, spec.scale 0.7)', shoulder_m: +(k.bp.D.shoulder * k.scale).toFixed(3) });
var d = PV.spawn('shiba', { x: 2.6, yaw: 0.5 });
// a 0.45 m bar and a 0.62 m bar (dog eye height) for scale
var mk = function (hh, x, col) { var b = new THREE.Mesh(new THREE.BoxGeometry(0.02, hh, 0.02), new THREE.MeshBasicMaterial({ color: col })); b.position.set(x, hh / 2, 0.5); PV.scene.add(b); return b; };
var b1 = mk(0.45, -0.3, 0xd03030), b2 = mk(0.62, 2.1, 0x3050d0);
PV.look([0.4, 0.7, 7.0], [0.3, 0.45, 0], 22); PV.full();
PV.label(20, 20, 'scale 0.7 / 1.0 / 1.4 / 1.7 (same build), kitten build far left, a dog on the right. Red bar = 0.45 m, blue bar = 0.62 m (dog eye height)');
PV.scene.remove(b1); PV.scene.remove(b2);
return out;
"""

STRIPES = r"""
var S = PV.size(), w = S[0] / 4, h = S[1] / 3, i = 0, LAB = [];
function cell(n, cam, lab, carried, breed) { PV.clear(); var c = PV.spawn(breed || 'mochi', { pose: carried ? 'stand' : n, tail: 'straight', ears: 'up' });
  PV.stripes(c, 5, [200, 40, 40], 0.012, 2); PV.stripes(c, 1, [40, 70, 200], 0.012, 0);
  if (carried) { c.setPose(n); c.settle(); }
  PV.look(cam, [0, 0.2, 0], 22); PV.view((i % 4) * w, Math.floor(i / 4) * h, w, h); LAB.push([(i % 4) * w + 6, Math.floor(i / 4) * h + 6, lab]); i++; }
var A = [1.7, 1.0, 1.7], T = [1.3, 1.6, 1.2];
cell('stand', A, 'stand: 5 stripes across flank + back, 1 along the spine'); cell('loaf', A, 'loaf (painted in this pose)'); cell('pancake', T, 'pancake (painted in this pose)'); cell('ball', A, 'ball (painted in this pose)');
cell('bolster', A, 'bolster (painted in this pose)'); cell('tall', [1.9, 0.9, 1.9], 'tall (painted in this pose)'); cell('arch', [2.3, 0.6, 1.0], 'arch (painted in this pose)'); cell('lsit', [2.3, 0.7, 1.2], 'L-sit (painted in this pose)');
cell('loaf', A, 'painted standing, then loaf', 1); cell('pancake', T, 'painted standing, then pancake', 1); cell('sit', A, 'painted standing, then sit', 1); cell('stand', A, 'cube build, stand', 0, 'tofu');
LAB.forEach(function (l) { PV.label(l[0], l[1], l[2]); });
"""

CHECKER = r"""
PV.clear(); var S = PV.size(), w = S[0] / 4, h = S[1], c = PV.spawn('mochi', { tail: 'up', ears: 'up' }), A = c.A;
for (var y = 0; y < A; y++) for (var x = 0; x < A; x++) { var o = (y * A + x) * 4, k = ((x >> 4) + (y >> 4)) & 1; c.alb[o] = k ? 235 : 60; c.alb[o + 1] = k ? 235 : 90; c.alb[o + 2] = k ? 235 : 160; }
c.texA.needsUpdate = true;
PV.look([1.4, 0.7, 1.9], [0, 0.25, 0.03], 19); PV.view(0, 0, w, h); PV.look([-1.6, 0.6, -1.6], [0, 0.25, 0], 19); PV.view(w, 0, w, h); PV.look([0.01, 2.9, 0.1], [0, 0.2, 0.03], 19); PV.view(2 * w, 0, w, h);
c.setPose('loaf'); c.settle(); PV.look([1.4, 0.8, 1.9], [0, 0.15, 0.03], 19); PV.view(3 * w, 0, w, h);
PV.label(6, 6, 'the atlas filled with a 16-texel checker: squares on the body = undistorted, even texel density');
var st = SG.critterStats(SG.CATS.mochi, 1024); return st;
"""

FROZEN = r"""
PV.clear(); var S = PV.size(), W = S[0], H = S[1], gl = PV.R.getContext(), out = {};
function run(frozen, pose) {
  PV.clear(); var c = PV.spawn('mochi', { pose: pose, live: 1, yaw: 0.6, ears: 'up', tail: 'curl' }), d = PV.spawn('soba', { pose: 'sit', live: 1, x: 0.9, yaw: -0.4, ears: 'up', tail: 'straight' });
  PV.stripes(c, 5, [200, 40, 40], 0.012, 2);
  for (var i = 0; i < 240; i++) PV.step(1, 1 / 60);            // let the pose arrive
  c.frozen = d.frozen = frozen; for (i = 0; i < 120; i++) PV.step(1, 1 / 60);
  PV.look([1.6, 0.8, 2.4], [0.4, 0.25, 0], 22); var ref = null, maxDiff = 0, changed = 0, buf = new Uint8Array(W * H * 4);
  for (var f = 0; f < 30; f++) { PV.step(1, 1 / 60); PV.full(); gl.readPixels(0, 0, W, H, gl.RGBA, gl.UNSIGNED_BYTE, buf); if (!ref) ref = buf.slice(); else { var n = 0; for (var q = 0; q < buf.length; q += 4) if (buf[q] !== ref[q] || buf[q + 1] !== ref[q + 1] || buf[q + 2] !== ref[q + 2]) n++; changed += n; if (n > maxDiff) maxDiff = n; } }
  return { frames: 30, pixels_changed_total: changed, max_changed_in_one_frame: maxDiff };
}
out.frozen_loaf_and_sit = run(true, 'loaf'); out.frozen_stand_pose = run(true, 'stand'); out.not_frozen_control = run(false, 'loaf');
PV.label(6, 6, 'frozen test: 30 frames rendered, pixels compared with frame 0 -> ' + JSON.stringify(out));
return out;
"""

GAIT = r"""
var S = PV.size(), w = S[0] / 8, h = S[1] / ROWS.length, LAB = [];
ROWS.forEach(function (R, ri) { PV.clear(); var c = PV.spawn(R.k, { live: 1, yaw: 0, tail: R.tail }); c.speed = R.sp; if (R.pose) c.setPose(R.pose);
  for (var q = 0; q < 90; q++) c.update(1 / 60);
  for (var f = 0; f < 8; f++) { for (q = 0; q < 6; q++) c.update(R.per / 8 / 6); c.root.updateMatrixWorld(true); PV.look(R.cam || [3.4, 0.35, 0.0], [0, R.ty || 0.27, 0], R.fov || 13); PV.view(f * w, ri * h, w, h); }
  LAB.push([6, ri * h + 6, R.lab]); });
LAB.forEach(function (l) { PV.label(l[0], l[1], l[2]); });
"""

MOVES = r"""
// jump (take-off pop, rise, fall, landing squash), stop from a run (skid), a hard turn while running, turning on the spot
var S = PV.size(), w = S[0] / 8, h = S[1] / 4, LAB = [];
function row(ri, lab, drive, cam, tgt, fov) { PV.clear(); var c = PV.spawn('mochi', { live: 1 }), t = 0, dt = 1 / 120; c.speed = 0;
  for (var f = 0; f < 8; f++) { for (var q = 0; q < drive.step; q++) { drive.fn(c, t, dt); c.update(dt); t += dt; } c.root.updateMatrixWorld(true); PV.look(cam || [3.6, 0.5, 0.0], tgt || [0, 0.35, 0], fov || 15); PV.view(f * w, ri * h, w, h); }
  LAB.push([6, ri * h + 6, lab]); }
row(0, 'jump 1.1 m: stand -> take-off pop -> stretch up -> apex -> reach down -> land (squash) -> settle   (frames 0.14 s apart)', { step: 17, fn: function (c, t, dt) { var T0 = 0.1, vy0 = 4.6, tt = t - T0, y = tt > 0 ? Math.max(0, vy0 * tt - 4.9 * tt * tt) : 0, was = c.air; c.air = y > 0 ? 1 : 0; if (was && !c.air) c.squash = 1; c.root.position.y = y; } }, [7.5, 0.8, 0.0], [0, 0.8, 0], 17);
row(1, 'running at 5 m/s, then stop (decel 10 m/s2 from frame 2): skid on braced front legs, sit back, spring up   (frames 0.1 s apart)', { step: 12, fn: function (c, t, dt) { if (t === 0) { c.speed = 5; for (var i = 0; i < 60; i++) c.update(1 / 60); } c.speed = t < 0.15 ? 5 : Math.max(0, 5 - (t - 0.15) * 10); } });
row(2, 'running, hard turn (4 rad/s between frames 2 and 6): leans into the turn, spine bends, tail lags', { step: 9, fn: function (c, t, dt) { c.speed = 5; c.turn = t > 0.1 && t < 0.5 ? 4 : 0; if (t === 0) for (var i = 0; i < 60; i++) c.update(1 / 60); } }, [0.5, 0.6, 3.6]);
row(3, 'turning on the spot (3 rad/s): quick shuffle', { step: 5, fn: function (c, t, dt) { c.speed = 0; c.turn = 3; } }, [2.4, 0.9, 2.6]);
LAB.forEach(function (l) { PV.label(l[0], l[1], l[2]); });
"""

ICONS = r"""
PV.clear(); var S = PV.size(); document.getElementById('gl').style.display = 'none'; document.body.style.background = '#3b2f2a';
var box = document.createElement('div'); box.style.cssText = 'position:absolute;left:0;top:0;right:0;bottom:0;display:grid;grid-template-columns:repeat(8,1fr);gap:8px;padding:14px;color:#f3e9d8;font:14px sans-serif;text-align:center';
var t0 = performance.now();
SG.POSE_PAGES.forEach(function (pg) { pg.forEach(function (n) { var d = document.createElement('div'); d.style.cssText = 'background:#4d3d35;border-radius:14px;padding:8px 4px'; var c = SG.poseIcon(n, { size: 128 }); d.appendChild(c); var l = document.createElement('div'); l.textContent = SG.POSE_INFO[n].label + '  ' + n; d.appendChild(l); box.appendChild(d); }); });
['mochi', 'soba', 'dango', 'tofu'].forEach(function (b) { ['stand', 'loaf', 'sit', 'pancake'].forEach(function (n, i) { var d = document.createElement('div'); d.style.cssText = 'background:#2f4b7c;border-radius:14px;padding:8px 4px'; d.appendChild(SG.poseIcon(n, { size: 96, spec: SG.CATS[b], ears: i ? 'flat' : 'up', tail: i ? 'tuck' : 'curl' })); var l = document.createElement('div'); l.textContent = b + ' ' + n; d.appendChild(l); box.appendChild(d); }); });
document.body.appendChild(box);
return { icons: 32, ms_total: Math.round(performance.now() - t0), dataURL_bytes_one_icon: SG.poseIconURL('loaf', { size: 96 }).length };
"""

PANCAKE = r"""
// a pancake cat on the floor and one pressed on the wall, both 3 m from a camera at a dog's eye height (0.6 m)
var S = PV.size(), out = {}, AMT = %s, PAINT = %s;
PV.clear(); PV.bg(0x8d939b);
var wallZ = -2.2, camZ = 0.8, q = new THREE.Quaternion().setFromRotationMatrix(new THREE.Matrix4().makeBasis(new THREE.Vector3(1, 0, 0), new THREE.Vector3(0, 0, 1), new THREE.Vector3(0, -1, 0)));  // body up = out of the wall, head up
var f = PV.spawn('mochi', { pose: 'pancake', amount: AMT, x: -0.75, z: -2.0, yaw: 0.5 }), wl = PV.spawn('mochi', { pose: 'pancake', amount: AMT, x: 0.75, y: 0.55, z: wallZ, quat: q.toArray() }), st = PV.spawn('mochi', { x: 0.0, z: -1.7, yaw: 2.2, tail: 'up', ears: 'up' });
if (PAINT) { f.fill([156, 138, 116], 0.85, 0); wl.fill([183, 178, 168], 0.85, 0); }
var mf = f.measure(), mw = wl.measure();
out.floor = { amount: AMT, thickness_m: +mf.size[1].toFixed(4), footprint_m: [+mf.size[0].toFixed(3), +mf.size[2].toFixed(3)] };
out.wall = { amount: AMT, sticks_out_m: +mw.size[1].toFixed(4) };
// what a camera sees: silhouette height of the floor pancake from 3 m at 0.6 m (its thickness plus the sliver of its top), as an angle and as pixels on a 1080-line screen at the game's 52 degree view
var d = Math.hypot(0.75, camZ + 2.0), look = Math.atan2(0.6, d), app = mf.size[1] * Math.cos(look) + mf.size[2] * Math.sin(look) * 0.9, ang = 2 * Math.atan(app / 2 / Math.hypot(d, 0.6));
out.floor.apparent_height_m = +app.toFixed(3); out.floor.apparent_deg = +(ang * 180 / Math.PI).toFixed(2); out.floor.pixels_at_1080p_fov52 = Math.round(ang / (52 * Math.PI / 180) * 1080);
var st0 = st.measure(); out.standing_cat_pixels_at_1080p_fov52 = Math.round(2 * Math.atan(st0.size[1] / 2 / 2.5) / (52 * Math.PI / 180) * 1080);
var h2 = S[1] / 2, w3 = S[0] / 3;
PV.look([0.0, 0.6, camZ], [0.0, 0.42, wallZ], 52); PV.view(0, 0, S[0], h2);
PV.look([0.0, 0.6, camZ], [-0.75, 0.03, -2.0], 9); PV.view(0, h2, w3, h2);
PV.look([0.75 + 3.0, 0.6, wallZ + 0.35], [0.75, 0.55, wallZ + 0.02], 9); PV.view(w3, h2, w3, h2);
PV.look([0.0, 0.6, camZ], [0.75, 0.55, wallZ], 12); PV.view(2 * w3, h2, w3, h2);
PV.label(6, 6, 'camera at dog eye height 0.6 m, field of view 52: pancake on the floor (left, 3 m away), pancake on the wall (right, 3 m), a standing cat for scale' + (PAINT ? ' - both filled with the base colour of what they are on' : ' - plain white'));
PV.label(6, h2 + 6, 'floor, zoomed from the same spot: ' + (out.floor.thickness_m * 100).toFixed(1) + ' cm thick, about ' + out.floor.pixels_at_1080p_fov52 + ' px tall at 1080p'); PV.label(w3 + 6, h2 + 6, 'wall, seen along the wall from 3 m: sticks out ' + (out.wall.sticks_out_m * 100).toFixed(1) + ' cm'); PV.label(2 * w3 + 6, h2 + 6, 'wall, zoomed from the same spot');
return out;
"""


def label(im, xy, text):
    d = ImageDraw.Draw(im)
    try: f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 16)
    except Exception: f = ImageFont.load_default()
    x, y = xy; tw = d.textlength(text, font=f)
    d.rectangle([x, y, x + tw + 10, y + 22], fill=(0, 0, 0)); d.text((x + 5, y + 2), text, fill=(255, 255, 255), font=f)


def run(p, Studio, which, out):
    out = pathlib.Path(out); res = {}
    want = lambda n: which in ("all", n)
    def studio(w, h, old=False): return Studio(p, w, h, old)

    if want("lineup"):
        st = studio(1890, 1000); res["builds"] = st.js(LINEUP); st.shot(out / "lineup-builds.png"); st.close()
    if want("sizes"):
        st = studio(1600, 620); res["sizes"] = st.js(SIZES); st.shot(out / "sizes.png"); st.close()
    if want("poses1") or want("poses"):
        st = studio(1800, 1760); res["poses_page1_size_xyz_m"] = st.js(POSE_ROW.replace("__PG__", "0")); st.shot(out / "poses-page1.png"); st.close()
    if want("poses2") or want("poses"):
        st = studio(1800, 1760); res["poses_page2_size_xyz_m"] = st.js(POSE_ROW.replace("__PG__", "1")); st.shot(out / "poses-page2.png"); st.close()
    if want("pancake"):
        st = studio(1600, 1000)
        res["pancake_default"] = st.js(PANCAKE % ("0.75", "false")); st.shot(out / "pancake-3m-white.png")
        res["pancake_thinnest"] = st.js(PANCAKE % ("1", "false")); st.shot(out / "pancake-3m-white-thinnest.png")
        st.js(PANCAKE % ("1", "true")); st.shot(out / "pancake-3m-painted.png"); st.close()
    if want("stripes"):
        st = studio(1600, 1350); st.js(STRIPES); st.shot(out / "stripes.png"); st.close()
    if want("density"):
        st = studio(1600, 700); d = st.js(CHECKER); st.shot(out / "uv-checker.png"); res["density_mochi_1024"] = d
        res["density_all"] = st.js("return Object.keys(SG.CATS).map(function(k){ var s=SG.critterStats(SG.CATS[k],1024); return {key:k, tris:s.tris, verts:s.verts, atlas_used:s.used, texels_per_m:Math.round(s.ppu), torso_mean_texels_per_cm: +(s.parts.filter(function(p){return ['hips','belly','chest'].indexOf(p.name)>=0;}).reduce(function(a,p){return a+p.mean*p.areaCm2;},0)/s.parts.filter(function(p){return ['hips','belly','chest'].indexOf(p.name)>=0;}).reduce(function(a,p){return a+p.areaCm2;},0)).toFixed(2), worst_part_p5: Math.min.apply(null, s.parts.map(function(p){return p.p5;}))}; });")
        res["dog_tris"] = st.js("return Object.keys(SG.DOGS).map(function(k){ var s=SG.critterStats(SG.DOGS[k],1024); return {key:k, tris:s.tris, verts:s.verts}; });")
        st.close()
    if want("frozen"):
        st = studio(800, 500); res["frozen"] = st.js(FROZEN); st.shot(out / "frozen.png"); st.close()
    if want("gait"):
        rows = "var ROWS=[{k:'mochi',sp:2.4,per:0.207,lab:'NEW cat, walk 2.4 m/s: quick trot, 8 frames of one cycle'},{k:'mochi',sp:5,per:0.267,lab:'NEW cat, run 5 m/s: bounding gallop, 8 frames of one cycle'},{k:'mochi',sp:2.4,per:0.207,lab:'walk, 3/4',cam:[2.0,0.8,2.6],fov:14},{k:'mochi',sp:5,per:0.267,lab:'run, 3/4',cam:[2.0,0.8,2.6],fov:14}];"
        st = studio(1600, 1000); st.js(rows + GAIT); st.shot(out / "gait-new.png"); st.close()
        rows_old = "var ROWS=[{k:'mochi',sp:2.4,per:0.2,lab:'OLD cat, walk 2.4 m/s (was already the run gait)'},{k:'mochi',sp:5,per:0.22,lab:'OLD cat, run 5 m/s'}];"
        st = studio(1600, 500, True); st.js(rows_old + GAIT); st.shot(out / "gait-old.png"); st.close()
        a = Image.open(out / "gait-new.png").crop((0, 0, 1600, 500)); b = Image.open(out / "gait-old.png")
        im = Image.new("RGB", (1600, 1000)); im.paste(b, (0, 0)); im.paste(a, (0, 500)); im.save(out / "gait-old-vs-new.png")
        rows_dog = "var ROWS=[{k:'shiba',sp:2.6,per:0.25,lab:'dog walk 2.6 m/s',cam:[4.2,0.45,0],ty:0.35,fov:14},{k:'shiba',sp:5.4,per:0.27,lab:'dog run 5.4 m/s: ears back',cam:[4.2,0.45,0],ty:0.35,fov:14},{k:'dachs',sp:5.4,per:0.25,lab:'dachshund run: ears and tongue fly',cam:[2.6,0.8,3.0],ty:0.3,fov:15},{k:'poodle',sp:5.4,per:0.28,lab:'poodle run',cam:[2.6,0.8,3.0],ty:0.4,fov:17}];"
        st = studio(1600, 1000); st.js(rows_dog + GAIT); st.shot(out / "gait-dogs.png"); st.close()
    if want("moves"):
        st = studio(1600, 1000); st.js(MOVES); st.shot(out / "moves-jump-skid-turn.png"); st.close()
    if want("icons"):
        st = studio(1200, 720); res["icons"] = st.js(ICONS); st.shot(out / "pose-icons.png"); st.close()
    if want("oldnew"):
        js = "PV.clear(); ['mochi','soba','wata','dango','azuki','chikuwa'].forEach(function(k,i){ PV.spawn(k,{x:-2.0+i*0.8,yaw:0.5,tail:'up',ears:'up',face:1}); }); PV.look([0.2,0.75,6.2],[0,0.3,0],17); PV.full();"
        st = studio(1600, 420, True); st.js(js); st.shot(out / "_old.png"); st.close()
        st = studio(1600, 420); st.js(js); st.shot(out / "_new.png"); st.close()
        im = Image.new("RGB", (1600, 840)); im.paste(Image.open(out / "_old.png"), (0, 0)); im.paste(Image.open(out / "_new.png"), (0, 420))
        label(im, (8, 8), "OLD: ball-jointed parts, dark eyes, pink nose and ears, whiskers, fur sheen"); label(im, (8, 428), "NEW: one continuous white skin, nothing dark, everything paintable"); im.save(out / "cats-old-vs-new.png")
        js = "PV.clear(); Object.keys(SG.DOGS).forEach(function(k,i){ PV.spawn(k,{x:-2.3+i*0.92,yaw:0.6}); }); PV.look([0.2,0.85,7.0],[0,0.4,0],17); PV.full();"
        st = studio(1600, 420, True); st.js(js); st.shot(out / "_old.png"); st.close()
        st = studio(1600, 420); st.js(js); st.shot(out / "_new.png"); st.close()
        im = Image.new("RGB", (1600, 840)); im.paste(Image.open(out / "_old.png"), (0, 0)); im.paste(Image.open(out / "_new.png"), (0, 420))
        label(im, (8, 8), "dogs, OLD critter.js"); label(im, (8, 428), "dogs, NEW critter.js (same look, new pipeline and gaits)"); im.save(out / "dogs-old-vs-new.png")
        (out / "_old.png").unlink(); (out / "_new.png").unlink()
    if want("compare"):
        ref = pathlib.Path("/mnt/user-data/uploads/325a7dc6-image.png")
        st = studio(1230, 520)
        st.js("PV.clear(); PV.bg(0x30343a); PV.spawn('mochi',{x:-1.5,yaw:0.6,tail:'up',ears:'up'}); PV.spawn('mochi',{x:-0.6,pose:'sit',yaw:0.6}); PV.spawn('mochi',{x:0.25,pose:'loaf',yaw:0.6}); PV.spawn('mochi',{x:1.05,pose:'tall',yaw:0.6}); PV.spawn('mochi',{x:1.9,pose:'pancake',yaw:0.6}); PV.look([0.3,0.9,6.0],[0.2,0.3,0],17); PV.full();")
        st.shot(out / "_new.png"); st.close()
        new = Image.open(out / "_new.png").convert("RGB")
        if ref.exists():
            r = Image.open(ref).convert("RGB"); r = r.crop((210, 170, 850, 800)); r = r.resize((int(r.width * 520 / r.height), 520))
            im = Image.new("RGB", (r.width + new.width, 520)); im.paste(r, (0, 0)); im.paste(new, (r.width, 0))
            label(im, (8, 8), "the original game's figure (owner's screenshot, for reference only)"); label(im, (r.width + 8, 8), "our cat: stand, sit, loaf, tall, pancake - plain, smooth, flat faces")
        else: im = new
        im.save(out / "canvas-vs-original.png"); (out / "_new.png").unlink()
    if res:
        f = out / "numbers.json"; old = json.loads(f.read_text()) if f.exists() else {}
        old.update(res); f.write_text(json.dumps(old, ensure_ascii=False, indent=1))
        print(json.dumps(res, ensure_ascii=False)[:3000])
