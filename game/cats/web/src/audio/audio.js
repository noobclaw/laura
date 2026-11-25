/* 貓躲狗找 — every sound is synthesised with WebAudio (oscillators, noise, filters). No audio files.
   Each sound is a function (ctx, out, t, opt) so the same code can be rendered in an OfflineAudioContext for checking. */
(function () {
  'use strict';
  var SG = (window.SG = window.SG || {});
  var noiseBuf = new WeakMap();
  function noise(ctx) { var b = noiseBuf.get(ctx); if (!b) { b = ctx.createBuffer(1, ctx.sampleRate, ctx.sampleRate); var d = b.getChannelData(0), s = 12345; for (var i = 0; i < d.length; i++) { s = (s * 1103515245 + 12345) & 0x7fffffff; d[i] = s / 0x3fffffff - 1; } noiseBuf.set(ctx, b); } var n = ctx.createBufferSource(); n.buffer = b; n.loop = true; return n; }
  function env(ctx, out, t, a, d, peak) { var g = ctx.createGain(); g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(peak, t + a); g.gain.exponentialRampToValueAtTime(0.0001, t + a + d); g.connect(out); return g; }
  function osc(ctx, type, f0, f1, t, dur, out, peak, a) { var o = ctx.createOscillator(); o.type = type; o.frequency.setValueAtTime(f0, t); if (f1) o.frequency.exponentialRampToValueAtTime(f1, t + dur); o.connect(env(ctx, out, t, a || 0.005, dur, peak)); o.start(t); o.stop(t + dur + 0.05); return o; }
  function nz(ctx, type, f, q, t, dur, out, peak, f1) { var n = noise(ctx), fl = ctx.createBiquadFilter(); fl.type = type; fl.frequency.setValueAtTime(f, t); if (f1) fl.frequency.exponentialRampToValueAtTime(f1, t + dur); fl.Q.value = q; n.connect(fl); fl.connect(env(ctx, out, t, 0.004, dur, peak)); n.start(t); n.stop(t + dur + 0.05); }
  function pluck(ctx, out, t, f, peak, dur) { osc(ctx, 'triangle', f, f * 0.995, t, dur || 0.7, out, peak, 0.003); osc(ctx, 'sine', f * 2, f * 2, t, (dur || 0.7) * 0.4, out, peak * 0.35, 0.002); nz(ctx, 'bandpass', f * 3, 2, t, 0.03, out, peak * 0.5); }
  function voice(ctx, out, t, pts, dur, peak, formant) { // vowel-ish: saw + two band-passes, pitch follows pts [[time 0..1, Hz]...]
    var o = ctx.createOscillator(); o.type = 'sawtooth'; pts.forEach(function (p, i) { if (i === 0) o.frequency.setValueAtTime(p[1], t); else o.frequency.linearRampToValueAtTime(p[1], t + p[0] * dur); });
    var lfo = ctx.createOscillator(), lg = ctx.createGain(); lfo.frequency.value = 7; lg.gain.value = 9; lfo.connect(lg); lg.connect(o.frequency); lfo.start(t); lfo.stop(t + dur + 0.1);
    var g = ctx.createGain(); g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(peak, t + dur * 0.18); g.gain.setValueAtTime(peak, t + dur * 0.55); g.gain.exponentialRampToValueAtTime(0.0001, t + dur); g.connect(out);
    (formant || [[900, 5, 1], [2300, 7, 0.6]]).forEach(function (f) { var b = ctx.createBiquadFilter(); b.type = 'bandpass'; b.frequency.setValueAtTime(f[0], t); b.frequency.linearRampToValueAtTime(f[0] * 1.35, t + dur * 0.5); b.frequency.linearRampToValueAtTime(f[0] * 0.8, t + dur); b.Q.value = f[1]; var gg = ctx.createGain(); gg.gain.value = f[2]; o.connect(b); b.connect(gg); gg.connect(g); });
    o.start(t); o.stop(t + dur + 0.05);
  }
  var YO = [293.66, 329.63, 392.0, 440.0, 493.88, 587.33, 659.25, 783.99];
  var S = {
    click: function (c, o, t) { osc(c, 'sine', 980, 720, t, 0.07, o, 0.25); },
    meow: function (c, o, t, p) { var k = (p && p.pitch) || 1; voice(c, o, t, [[0, 420 * k], [0.3, 760 * k], [0.7, 690 * k], [1, 430 * k]], 0.55, 0.5); },
    meowHit: function (c, o, t) { voice(c, o, t, [[0, 700], [0.15, 1150], [0.5, 900], [1, 520]], 0.5, 0.55, [[1200, 5, 1], [2900, 7, 0.7]]); pluck(c, o, t + 0.05, 1318, 0.2, 0.5); pluck(c, o, t + 0.14, 1760, 0.18, 0.6); },
    bark: function (c, o, t) { [0, 0.17].forEach(function (d) { voice(c, o, t + d, [[0, 330], [0.3, 250], [1, 170]], 0.13, 0.6, [[520, 3, 1], [1400, 4, 0.5]]); nz(c, 'lowpass', 1500, 1, t + d, 0.08, o, 0.3); }); },
    thwop: function (c, o, t) { osc(c, 'sine', 210, 55, t, 0.16, o, 0.7); nz(c, 'lowpass', 2600, 0.7, t, 0.12, o, 0.4, 300); osc(c, 'triangle', 900, 300, t, 0.05, o, 0.15); },
    bounce: function (c, o, t) { osc(c, 'sine', 420, 230, t, 0.08, o, 0.4); nz(c, 'bandpass', 1900, 2, t, 0.035, o, 0.3); },
    miss: function (c, o, t) { pluck(c, o, t, 392, 0.3, 0.35); pluck(c, o, t + 0.13, 293.66, 0.3, 0.5); },
    dryfire: function (c, o, t) { nz(c, 'bandpass', 2400, 6, t, 0.03, o, 0.25); },
    brush: function (c, o, t, p) { var f = 2600 - Math.min(1, ((p && p.size) || 0.06) / 0.2) * 1800; nz(c, 'bandpass', f, 1.2, t, 0.09, o, 0.13, f * 0.7); },
    pick: function (c, o, t) { osc(c, 'sine', 1500, 2100, t, 0.06, o, 0.3); osc(c, 'sine', 2800, 2800, t + 0.05, 0.08, o, 0.14); },
    fill: function (c, o, t) { nz(c, 'bandpass', 500, 1.5, t, 0.4, o, 0.25, 4200); osc(c, 'sine', 400, 1300, t, 0.35, o, 0.14); },
    undo: function (c, o, t) { osc(c, 'triangle', 640, 420, t, 0.1, o, 0.25); },
    pose: function (c, o, t) { osc(c, 'sine', 190, 110, t, 0.1, o, 0.35); nz(c, 'lowpass', 900, 0.7, t, 0.06, o, 0.15); },
    jump: function (c, o, t) { nz(c, 'bandpass', 700, 1, t, 0.14, o, 0.16, 2400); },
    land: function (c, o, t) { osc(c, 'sine', 130, 70, t, 0.1, o, 0.4); nz(c, 'lowpass', 600, 0.7, t, 0.05, o, 0.2); },
    bump: function (c, o, t, p) { var k = (p && p.type) || ''; if (/茶杯|空罐|小盆栽/.test(k)) { osc(c, 'triangle', 1900, 1500, t, 0.09, o, 0.3); osc(c, 'sine', 3100, 2900, t, 0.12, o, 0.14); } else if (/積木/.test(k)) { osc(c, 'square', 520, 380, t, 0.04, o, 0.16); nz(c, 'bandpass', 1500, 3, t, 0.03, o, 0.2); } else { osc(c, 'sine', 240, 150, t, 0.08, o, 0.3); nz(c, 'lowpass', 1200, 0.7, t, 0.05, o, 0.12); } },
    paintmode: function (c, o, t) { pluck(c, o, t, 587.33, 0.22, 0.4); pluck(c, o, t + 0.07, 783.99, 0.2, 0.5); },
    phase: function (c, o, t) { [0, 2, 4, 5].forEach(function (n, i) { pluck(c, o, t + i * 0.11, YO[n], 0.3, 0.9); }); },
    seek: function (c, o, t) { [5, 4, 2, 0].forEach(function (n, i) { pluck(c, o, t + i * 0.09, YO[n] * 0.5, 0.34, 0.8); }); osc(c, 'sine', 73, 73, t, 0.9, o, 0.35, 0.02); },
    alert: function (c, o, t) { osc(c, 'square', 880, 880, t, 0.07, o, 0.14); osc(c, 'square', 1175, 1175, t + 0.1, 0.12, o, 0.14); },
    lowBalls: function (c, o, t) { [0, 0.42].forEach(function (d) { osc(c, 'sine', 62, 48, t + d, 0.16, o, 0.6); osc(c, 'sine', 58, 44, t + d + 0.14, 0.14, o, 0.4); }); },
    win: function (c, o, t) { [0, 2, 4, 5, 7].forEach(function (n, i) { pluck(c, o, t + i * 0.12, YO[n], 0.32, 1.1); }); pluck(c, o, t + 0.72, YO[5] * 2, 0.22, 1.4); },
    lose: function (c, o, t) { [4, 3, 1, 0].forEach(function (n, i) { pluck(c, o, t + i * 0.2, YO[n] * 0.5, 0.32, 1.0); }); },
    decoy: function (c, o, t) { osc(c, 'sine', 500, 1000, t, 0.12, o, 0.2); osc(c, 'sine', 750, 1500, t + 0.06, 0.12, o, 0.16); },
    blast: function (c, o, t) { osc(c, 'sine', 120, 30, t, 0.32, o, 0.5); osc(c, 'sine', 62, 34, t + 0.02, 0.4, o, 0.3); nz(c, 'lowpass', 4200, 0.8, t, 0.12, o, 0.4, 420); nz(c, 'bandpass', 1500, 1.2, t + 0.015, 0.2, o, 0.16, 280); nz(c, 'highpass', 5200, 0.7, t, 0.03, o, 0.12); osc(c, 'square', 300, 90, t, 0.04, o, 0.09); nz(c, 'lowpass', 900, 0.7, t + 0.09, 0.35, o, 0.07, 200); }, // thump + body + crack + splatter tail
    pump: function (c, o, t) { nz(c, 'bandpass', 1700, 3, t, 0.04, o, 0.55); osc(c, 'triangle', 400, 280, t, 0.04, o, 0.3); osc(c, 'sine', 150, 110, t, 0.05, o, 0.2); nz(c, 'bandpass', 2400, 3, t + 0.17, 0.035, o, 0.6); osc(c, 'triangle', 620, 470, t + 0.17, 0.035, o, 0.3); osc(c, 'sine', 190, 140, t + 0.17, 0.05, o, 0.2); },
    heart: function (c, o, t, p) { var k = (p && p.v) || 0.5; osc(c, 'sine', 64, 44, t, 0.11, o, 0.35 + k * 0.4); osc(c, 'sine', 58, 40, t + 0.15, 0.1, o, 0.22 + k * 0.3); },
    sneeze: function (c, o, t, p) { var k = (p && p.vol) || 0.5; nz(c, 'bandpass', 2600, 1.5, t, 0.05, o, 0.25 * k, 5200); nz(c, 'highpass', 3000, 0.7, t + 0.06, 0.12, o, 0.4 * k); osc(c, 'sine', 900, 500, t + 0.06, 0.08, o, 0.12 * k); },
    giggle: function (c, o, t) { [0, 0.09, 0.18, 0.27].forEach(function (d, i) { osc(c, 'sine', 980 + i * 60, 760 + i * 40, t + d, 0.06, o, 0.1); }); },
    like: function (c, o, t) { pluck(c, o, t, 880, 0.2, 0.3); pluck(c, o, t + 0.08, 1175, 0.2, 0.4); },
    splat: function (c, o, t) { nz(c, 'lowpass', 900, 1, t, 0.07, o, 0.3, 200); osc(c, 'sine', 240, 120, t, 0.06, o, 0.18); },
    chime: function (c, o, t, p) { var f = 2100 * ((p && p.k) || 1); osc(c, 'sine', f, f, t, 1.6, o, 0.1, 0.002); osc(c, 'sine', f * 2.76, f * 2.76, t, 0.8, o, 0.04, 0.002); osc(c, 'sine', f * 5.4, f * 5.4, t, 0.3, o, 0.02, 0.002); },
    score: function (c, o, t, p) { var f = 520 * Math.pow(1.059, Math.min(26, (p && p.n) || 1)); osc(c, 'triangle', f, f * 1.5, t, 0.09, o, 0.22); osc(c, 'sine', f * 2, f * 2.02, t + 0.03, 0.09, o, 0.1); }, // 見落とし counter: one semitone higher each tick
    tick: function (c, o, t) { nz(c, 'bandpass', 3200, 3, t, 0.018, o, 0.5); osc(c, 'sine', 1800, 1500, t, 0.012, o, 0.05); },
    kettle: function (c, o, t) { nz(c, 'bandpass', 5200, 3, t, 1.4, o, 0.035, 6200); osc(c, 'sine', 2350, 2500, t + 0.2, 1.1, o, 0.018, 0.3); },
    vacuum: function (c, o, t) { nz(c, 'bandpass', 420, 1.2, t, 1.5, o, 0.03); osc(c, 'sawtooth', 96, 98, t, 1.5, o, 0.012, 0.3); }
  };
  var AMB = { tick: 1, chime: 1, kettle: 1, vacuum: 1 };
  var A = (SG.audio = {
    volume: 0.7, ctx: null, sounds: S,
    init: function () {
      var bus = SG.bus, map = { meow: 'meow', blast: 'blast', pump: 'pump', giggle: 'giggle', like: 'like', bounce: 'splat', ovltick: 'score', miss: 'miss', dryfire: 'dryfire', picked: 'pick', fill: 'fill', undo: 'undo', pose: 'pose', jump: 'jump', land: 'land', paintmode: 'paintmode', alert: 'alert', lowBalls: 'lowBalls', decoy: 'decoy', bump: 'bump' };
      Object.keys(map).forEach(function (ev) { bus.on(ev, function (d) { A.play(map[ev], d); }); });
      bus.on('hit', function () { A.play('meowHit'); });
      bus.on('fidget', function (d) { if (d.sneeze && SG.game.me && SG.game.me.team === 'dog' && d.d < 6) A.play('sneeze', { vol: 1 - d.d / 7 }); });
      var hb = 0; bus.on('danger', function (d) { A.danger = d.v; }); setInterval(function () { if (!A.ctx || !(A.danger > 0.25) || !SG.game.state || SG.game.state.phase !== 'seek') return; var n = performance.now(); if (n - hb > 1150 - 760 * A.danger) { hb = n; A.play('heart', { v: A.danger }); } }, 60);
      bus.on('stroke', function (d) { var n = performance.now(); if (n - (A.lastBrush || 0) > 70) { A.lastBrush = n; A.play('brush', d); } });
      bus.on('phase', function (d) { if (d.phase === 'seek') { A.play('seek'); if (SG.game.side === 'cat') setTimeout(function () { A.play('bark'); }, 700); } else if (d.phase === 'prep') A.play('phase'); });
      bus.on('end', function (d) { var won = (SG.game.side === 'cat') === (d.winner === 'cats'); setTimeout(function () { A.play(won ? 'win' : 'lose'); }, 400); });
      document.addEventListener('click', function (e) { A.unlock(); if (e.target.closest && e.target.closest('button')) A.play('click'); }, true);
      // ambience: a quiet clock tick, and one soft wind-chime note about every 80-110 s. The kettle whistle and the vacuum hum are gone (owner: too noisy).
      var nextChime = 40; setInterval(function () { if (!A.ctx || A.ctx.state !== 'running') return; var t = Math.floor(performance.now() / 1000); if (t % 2 === 0) A.play('tick'); if (t >= nextChime) { nextChime = t + 80 + Math.floor(Math.random() * 30); A.play('chime', { k: 1 }); } }, 1000);
      // music follows the phase; in the search phase it is off unless the player turns it on (it would mask footsteps and taunts)
      function mus() { var G = SG.game, M = SG.music; if (!M) return; A.buses(); var st = G.state, ph = G.mode === 'title' ? 'lobby' : !st ? null : st.phase === 'lobby' ? 'lobby' : st.phase === 'prep' ? 'hide' : st.phase === 'seek' ? (G.opts.searchMusic ? 'search' : null) : 'answer'; if (ph) M.play(ph); else M.stop(); }
      bus.on('mode', mus); bus.on('phase', function (d) { if (d.phase === 'reveal' && SG.music) SG.music.sting(); mus(); }); bus.on('frame', function (d) { if (SG.music) SG.music.level = d.phase === 'seek' ? (d.left < 10 ? 2 : d.left < 60 ? 1 : 0) : 0; });
    },
    unlock: function () { if (!A.ctx) { var C = window.AudioContext || window.webkitAudioContext; if (!C) return; A.ctx = new C(); A.master = A.ctx.createGain(); A.master.gain.value = A.volume; var comp = A.ctx.createDynamicsCompressor(); comp.threshold.value = -12; comp.ratio.value = 6; A.master.connect(comp); comp.connect(A.ctx.destination); } if (A.ctx.state === 'suspended') A.ctx.resume(); },
    setVolume: function (v) { A.volume = v; if (A.master) A.master.gain.value = v; },
    levels: { sfx: 1, amb: 0.3, mus: 0.125 }, // music sits about 18 dB under the effects
    setLevel: function (k, v) { A.levels[k] = v; if (A[k]) A[k].gain.value = v; },
    buses: function () { if (A.sfx || !A.ctx) return; ['sfx', 'amb', 'mus'].forEach(function (k) { A[k] = A.ctx.createGain(); A[k].gain.value = A.levels[k]; A[k].connect(A.master); });
      var dl = A.ctx.createDelay(0.5), fb = A.ctx.createGain(), wet = A.ctx.createGain(); dl.delayTime.value = 0.27; fb.gain.value = 0.22; wet.gain.value = 0.18; A.musIn = A.ctx.createGain(); A.musIn.connect(A.mus); A.musIn.connect(dl); dl.connect(fb); fb.connect(dl); dl.connect(wet); wet.connect(A.mus); A.mus = Object.assign(A.musIn, { gainNode: A.mus }); },
    play: function (name, opt) { if (!A.ctx || A.ctx.state !== 'running' || !S[name]) return; A.buses(); try { S[name](A.ctx, AMB[name] ? A.amb : A.sfx, A.ctx.currentTime + 0.01, opt); } catch (e) { } },
    /* render every sound offline and measure it. Nobody has listened to these: this only proves they are audible and do not clip. */
    selfTest: function () {
      var names = Object.keys(S), out = [];
      return names.reduce(function (p, n) {
        return p.then(function () {
          var c = new OfflineAudioContext(1, 44100 * 2, 44100); S[n](c, c.destination, 0.02, {});
          return c.startRendering().then(function (b) { var d = b.getChannelData(0), peak = 0, sq = 0, clip = 0, last = 0; for (var i = 0; i < d.length; i++) { var a = Math.abs(d[i]); if (a > peak) peak = a; sq += a * a; if (a >= 0.999) clip++; if (a > 0.002) last = i; } out.push({ name: n, peak: +peak.toFixed(3), rms: +Math.sqrt(sq / d.length).toFixed(4), clipped: clip, lengthSec: +(last / 44100).toFixed(2), silent: peak < 0.01 }); });
        });
      }, Promise.resolve()).then(function () { return out; });
    }
  });
})();
