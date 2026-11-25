/* 貓躲狗找 — music: four small composed loops played by a tiny step sequencer (marimba, plucked bass, brushes, pad).
   No samples. NOBODY HAS LISTENED TO THIS: SG.music.selfTest() only measures level, harshness, DC and loop seams offline. */
(function () {
  'use strict';
  var SG = (window.SG = window.SG || {});
  function hz(m) { return 440 * Math.pow(2, (m - 69) / 12); }
  function env(ctx, out, t, a, dur, peak) { var g = ctx.createGain(); g.gain.setValueAtTime(0.0001, t); g.gain.linearRampToValueAtTime(peak, t + a); g.gain.exponentialRampToValueAtTime(0.0001, t + dur); g.connect(out); return g; }
  function tone(ctx, out, type, f, t, a, dur, peak) { var o = ctx.createOscillator(); o.type = type; o.frequency.value = f; o.connect(env(ctx, out, t, a, dur, peak)); o.start(t); o.stop(t + dur + 0.05); }
  var nbuf = null;
  function brush(ctx, out, t, v) { if (!nbuf || nbuf.sampleRate !== ctx.sampleRate) { nbuf = ctx.createBuffer(1, ctx.sampleRate * 0.2, ctx.sampleRate); var d = nbuf.getChannelData(0), s = 7; for (var i = 0; i < d.length; i++) { s = (s * 16807) % 2147483647; d[i] = s / 1073741823.5 - 1; } }
    var n = ctx.createBufferSource(), f = ctx.createBiquadFilter(); n.buffer = nbuf; f.type = 'bandpass'; f.frequency.value = 2600; f.Q.value = 0.7; n.connect(f); f.connect(env(ctx, out, t, 0.004, 0.07, 0.05 * v)); n.start(t); n.stop(t + 0.1); }
  function marimba(ctx, out, t, m, len, v) { var f = hz(m); tone(ctx, out, 'sine', f, t, 0.004, Math.max(0.35, len * 0.9), 0.2 * v); tone(ctx, out, 'sine', f * 4, t, 0.002, 0.07, 0.05 * v); tone(ctx, out, 'sine', f * 2, t, 0.004, 0.18, 0.03 * v); }
  function bass(ctx, out, t, m, len) { var f = hz(m); tone(ctx, out, 'triangle', f, t, 0.006, Math.max(0.25, len * 0.8), 0.2); tone(ctx, out, 'sine', f, t, 0.006, Math.max(0.3, len), 0.14); }
  function pad(ctx, out, t, ms, dur) { ms.forEach(function (m) { tone(ctx, out, 'sine', hz(m), t, 0.5, dur, 0.022); tone(ctx, out, 'sine', hz(m) * 1.004, t, 0.6, dur, 0.016); }); }
  // chords: [bass root (midi), pad notes]
  var CH = { C: [36, [60, 64, 67]], Am: [33, [57, 60, 64]], F: [29, [57, 60, 65]], G: [31, [59, 62, 67]], Em: [28, [59, 64, 67]], D: [26, [57, 62, 66]], Dm: [26, [57, 62, 65]], E: [28, [56, 59, 64]], Bb: [34, [58, 62, 65]] };
  var m1 = [[0, 76, 1], [1, 79, 0.5], [1.5, 76, 0.5], [2, 72, 1], [3, 74, 1]], m9 = [[0, 81, 1], [1, 77, 1], [2, 72, 1], [3, 77, 1]], s1 = [[0.5, 76, 0.5], [1, 69, 0.5], [3, 72, 0.5]];
  var T = {
    lobby: { name: '大廳', key: 'C major', bpm: 104, style: 'bounce', chords: ['C', 'Am', 'F', 'G', 'C', 'Am', 'F', 'G', 'F', 'G', 'Em', 'Am', 'F', 'G', 'C', 'C'],
      mel: [m1, [[0, 76, 1], [1, 72, 0.5], [1.5, 69, 0.5], [2, 69, 2]], [[0, 77, 1], [1, 81, 0.5], [1.5, 77, 0.5], [2, 72, 1], [3, 74, 1]], [[0, 74, 1.5], [1.5, 71, 0.5], [2, 67, 2]], m1, [[0, 76, 1], [1, 79, 0.5], [1.5, 81, 0.5], [2, 81, 2]], [[0, 77, 1], [1, 76, 0.5], [1.5, 74, 0.5], [2, 72, 1], [3, 74, 1]], [[0, 72, 3]],
        m9, [[0, 79, 1], [1, 74, 1], [2, 71, 1], [3, 74, 1]], [[0, 79, 1.5], [1.5, 76, 0.5], [2, 71, 2]], [[0, 69, 1], [1, 72, 1], [2, 76, 2]], m9, [[0, 79, 1], [1, 83, 1], [2, 74, 1], [3, 79, 1]], [[0, 76, 1], [1, 72, 1], [2, 67, 1], [3, 72, 1]], [[0, 72, 3]]] },
    hide: { name: '躲藏', key: 'G major', bpm: 84, style: 'sparse', chords: ['G', 'Em', 'C', 'D', 'G', 'Em', 'C', 'D'],
      mel: [[[0, 71, 1], [2, 74, 1]], [[0, 76, 1.5], [2.5, 74, 0.5], [3, 71, 1]], [[0, 72, 1], [2, 76, 1]], [[0, 74, 2], [3, 69, 1]], [[0, 71, 1], [1, 74, 1], [2, 79, 2]], [[0, 76, 1], [2, 79, 1], [3, 76, 1]], [[0, 72, 1], [1, 76, 1], [2, 74, 1], [3, 71, 1]], [[0, 67, 3]]] },
    search: { name: '搜索', key: 'A minor', bpm: 96, style: 'sneak', chords: ['Am', 'Am', 'Dm', 'E', 'Am', 'F', 'Dm', 'E'],
      mel: [s1, [[2.5, 71, 0.5], [3, 72, 0.5], [3.5, 76, 0.5]], [[0.5, 77, 0.5], [1, 74, 0.5], [3, 69, 0.5]], [[0, 68, 1], [2, 71, 1], [3, 76, 0.5]], s1, [[0.5, 72, 0.5], [1, 77, 0.5], [2.5, 81, 0.5], [3, 77, 0.5]], [[0, 74, 1], [1.5, 77, 0.5], [2, 69, 1]], [[0, 76, 1], [1, 68, 1], [2, 64, 2]]] },
    answer: { name: '對答案', key: 'F major', bpm: 112, style: 'bounce', chords: ['F', 'Dm', 'Bb', 'C'],
      mel: [[[0, 72, 0.5], [0.5, 77, 0.5], [1, 81, 1], [2, 77, 1], [3, 72, 1]], [[0, 74, 1], [1, 77, 1], [2, 81, 2]], [[0, 70, 0.5], [0.5, 74, 0.5], [1, 77, 1], [2, 79, 1], [3, 77, 1]], [[0, 76, 1], [1, 79, 1], [2, 72, 2]]] }
  };
  /* one bar of a track at time t; level 0..2 = how urgent the search is */
  function bar(ctx, out, tr, i, t, level) {
    var b = 60 / tr.bpm, ch = CH[tr.chords[i % tr.chords.length]], k, st = tr.style;
    pad(ctx, out, t, ch[1], b * 4.2);
    if (st === 'bounce') { bass(ctx, out, t, ch[0] + 12, b); bass(ctx, out, t + b * 2, ch[0] + 12, b); bass(ctx, out, t + b * 3, ch[0] + 19, b * 0.5); for (k = 0; k < 4; k++) brush(ctx, out, t + b * (k + 0.5), k % 2 ? 1 : 0.6); }
    else if (st === 'sparse') { bass(ctx, out, t, ch[0] + 12, b * 2); bass(ctx, out, t + b * 2.5, ch[0] + 19, b); }
    else { [0, 1.5, 2, 3].forEach(function (x, q) { bass(ctx, out, t + b * x, ch[0] + (q === 2 ? 19 : q === 3 ? 24 : 12), b * 0.4); }); if (level > 0) for (k = 0; k < (level > 1 ? 16 : 8); k++) brush(ctx, out, t + b * k * (level > 1 ? 0.25 : 0.5), k % 2 ? 0.5 : 0.9); if (level > 1) for (k = 0; k < 4; k++) bass(ctx, out, t + b * (k + 0.5), ch[0] + 12, b * 0.3); }
    tr.mel[i % tr.mel.length].forEach(function (n) { marimba(ctx, out, t + b * n[0], n[1], b * n[2], 1); });
  }
  var M = (SG.music = { tracks: T, cur: null, level: 0,
    play: function (name) { var A = SG.audio; if (M.cur === name) return; M.cur = name; M.i = 0; if (A && A.ctx) M.next = A.ctx.currentTime + 0.15; },
    stop: function () { M.cur = null; },
    sting: function () { var A = SG.audio; if (!A || !A.ctx || !A.mus) return; var t = A.ctx.currentTime + 0.05; [65, 69, 72, 77, 81, 84].forEach(function (m, i) { marimba(A.ctx, A.mus, t + i * 0.09, m, 0.8, 1.2); }); pad(A.ctx, A.mus, t, [65, 69, 72], 2.2); },
    tick: function () { var A = SG.audio; if (!A || !A.ctx || A.ctx.state !== 'running' || !A.mus || !M.cur) return; var tr = T[M.cur], bd = 240 / tr.bpm; if (M.next == null || M.next < A.ctx.currentTime) M.next = A.ctx.currentTime + 0.1; while (M.next < A.ctx.currentTime + 0.7) { bar(A.ctx, A.mus, tr, M.i, M.next, M.level); M.next += bd; M.i++; } },
    /* offline measurements of every loop (two passes, so the seam between them is inside the render) */
    selfTest: function () {
      var names = Object.keys(T), out = [], C = window.OfflineAudioContext || window.webkitOfflineAudioContext;
      return names.reduce(function (p, name) { return p.then(function () {
        var tr = T[name], bd = 240 / tr.bpm, bars = tr.chords.length, sr = 44100, ctx = new C(1, Math.ceil(sr * (bd * bars * 2 + 1)), sr), i;
        for (i = 0; i < bars * 2; i++) bar(ctx, ctx.destination, tr, i, i * bd, name === 'search' ? 1 : 0);
        return ctx.startRendering().then(function (buf) {
          var d = buf.getChannelData(0), n = d.length, sum = 0, dc = 0, pk = 0, hf = 0, y = 0, a = 1 / (1 + 2 * Math.PI * 4000 / sr), diffs = [], seam = Math.round(sr * bd * bars), k;
          for (k = 1; k < n; k++) { var x = d[k]; sum += x * x; dc += x; if (Math.abs(x) > pk) pk = Math.abs(x); y = a * (y + x - d[k - 1]); hf += y * y; if (k % 37 === 0) diffs.push(Math.abs(x - d[k - 1])); }
          diffs.sort(function (p1, p2) { return p1 - p2; }); var p99 = diffs[Math.floor(diffs.length * 0.99)], sj = 0; for (k = seam - 2; k <= seam + 2; k++) sj = Math.max(sj, Math.abs(d[k] - d[k - 1]));
          out.push({ name: name, title: tr.name, key: tr.key, bpm: tr.bpm, bars: bars, loopSec: +(bd * bars).toFixed(2), rmsDb: +(10 * Math.log10(sum / n)).toFixed(1), peak: +pk.toFixed(3), dc: +(dc / n).toFixed(5), above4kHz: +(hf / sum).toFixed(4), seamJump: +sj.toFixed(4), typicalJumpP99: +p99.toFixed(4), chords: tr.chords.join(' '), melody: tr.mel.map(function (b2) { return b2.map(function (nn) { return ['C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'G#', 'A', 'Bb', 'B'][nn[1] % 12] + (Math.floor(nn[1] / 12) - 1); }).join(' '); }).join(' | ') });
        }); }); }, Promise.resolve()).then(function () { return out; });
    }
  });
  setInterval(function () { M.tick(); }, 200);
})();
