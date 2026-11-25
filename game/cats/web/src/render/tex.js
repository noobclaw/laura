/* 貓躲狗找 — procedural textures. Everything is drawn to canvases at start-up. */
(function () {
  'use strict';
  var SG = (window.SG = window.SG || {});
  var FONT = '"SushiTC","Noto Sans TC","Noto Sans CJK TC",sans-serif';

  var PAL = (SG.PAL = {
    vermilion: '#d5432c', vermilionDeep: '#a82c1c',
    indigo: '#24395c', indigoDeep: '#152540', indigoSoft: '#3d5a86',
    matcha: '#93a95c', matchaDeep: '#5f7a3a', matchaPale: '#c9d39a',
    gold: '#d8a444', goldLight: '#f4d892', goldDeep: '#9c6f22',
    washi: '#f4ead6', cream: '#ece0c4', sumi: '#2a2320',
    woodDark: '#3f2718', woodMid: '#8a5a36', hinoki: '#e3c08c', woodRed: '#6d3a24'
  });

  function rng(seed) {
    var a = seed >>> 0;
    return function () {
      a |= 0; a = (a + 0x6d2b79f5) | 0;
      var t = Math.imul(a ^ (a >>> 15), 1 | a);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }
  SG.rng = rng;

  function mk(w, h, draw) {
    var c = document.createElement('canvas');
    c.width = w; c.height = h;
    var g = c.getContext('2d', { willReadFrequently: true });
    draw(g, w, h);
    return c;
  }

  function hex2rgb(h) {
    var n = parseInt(h.slice(1), 16);
    return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
  }
  function shade(h, k) { // k>0 lighten, k<0 darken
    var c = hex2rgb(h), o = [];
    for (var i = 0; i < 3; i++) o.push(Math.round(k >= 0 ? c[i] + (255 - c[i]) * k : c[i] * (1 + k)));
    return 'rgb(' + o.join(',') + ')';
  }
  function rgba(h, a) { var c = hex2rgb(h); return 'rgba(' + c[0] + ',' + c[1] + ',' + c[2] + ',' + a + ')'; }
  SG.shade = shade; SG.rgba = rgba;

  /* fine paper / cloth fibre noise laid over a pattern so it never looks like flat vector art */
  function fibres(g, w, h, seed, amt, weave) {
    var r = rng(seed), i;
    amt = amt == null ? 1 : amt;
    for (i = 0; i < w * h / 260 * amt; i++) {
      var x = r() * w, y = r() * h, l = 4 + r() * 16, a = r() * Math.PI;
      g.strokeStyle = r() < 0.5 ? 'rgba(255,250,235,' + (0.05 + r() * 0.08) + ')' : 'rgba(60,40,20,' + (0.03 + r() * 0.06) + ')';
      g.lineWidth = 0.6 + r() * 0.7;
      g.beginPath(); g.moveTo(x, y); g.lineTo(x + Math.cos(a) * l, y + Math.sin(a) * l); g.stroke();
    }
    if (weave) {
      g.globalAlpha = 0.07;
      for (i = 0; i < h; i += 3) { g.fillStyle = i % 6 ? '#000' : '#fff'; g.fillRect(0, i, w, 1); }
      for (i = 0; i < w; i += 3) { g.fillStyle = i % 6 ? '#fff' : '#000'; g.fillRect(i, 0, 1, h); }
      g.globalAlpha = 1;
    }
  }

  var P = {};

  P.washi = function (base, seed) {
    return mk(256, 256, function (g, w, h) {
      g.fillStyle = base || PAL.washi; g.fillRect(0, 0, w, h);
      var r = rng(seed || 7), i;
      for (i = 0; i < 500; i++) {
        g.fillStyle = 'rgba(' + (r() < 0.5 ? '255,255,250' : '150,120,80') + ',' + (r() * 0.07) + ')';
        var s = 2 + r() * 12; g.beginPath(); g.ellipse(r() * w, r() * h, s, s * (0.3 + r() * 0.6), r() * 3, 0, 7); g.fill();
      }
      fibres(g, w, h, (seed || 7) + 1, 1.6);
    });
  };

  P.seigaiha = function (bg, line, R) {
    R = R || 64;
    return mk(R * 4, R * 2, function (g, w, h) {
      g.fillStyle = bg; g.fillRect(0, 0, w, h);
      var step = R / 2, row, x;
      for (row = -1; row * step < h + R; row++) {
        var off = (row & 1) ? R : 0, cy = row * step;
        for (x = -R * 2; x < w + R * 2; x += R * 2) {
          var cx = x + off;
          g.fillStyle = bg; g.beginPath(); g.arc(cx, cy + R, R, 0, 7); g.fill();
          for (var k = 0; k < 4; k++) {
            g.strokeStyle = line; g.lineWidth = R * (k === 0 ? 0.085 : 0.06);
            g.beginPath(); g.arc(cx, cy + R, R * (1 - k * 0.235) - g.lineWidth / 2, Math.PI, Math.PI * 2); g.stroke();
          }
          g.fillStyle = line; g.beginPath(); g.arc(cx, cy + R, R * 0.09, 0, 7); g.fill();
        }
      }
      fibres(g, w, h, 11, 0.8, true);
    });
  };

  P.asanoha = function (bg, line, s) {
    s = s || 64;
    var H = Math.round(s * Math.sqrt(3));
    return mk(s * 2, H * 2, function (g, w, h) {
      g.fillStyle = bg; g.fillRect(0, 0, w, h);
      g.save(); g.scale(1, H / (s * Math.sqrt(3)));
      g.strokeStyle = line; g.lineWidth = s * 0.045; g.lineCap = 'round';
      var th = s * Math.sqrt(3) / 2, i, j;
      function tri(ax, ay, bx, by, cx, cy) {
        var mx = (ax + bx + cx) / 3, my = (ay + by + cy) / 3;
        g.beginPath();
        g.moveTo(ax, ay); g.lineTo(bx, by); g.lineTo(cx, cy); g.closePath();
        g.moveTo(ax, ay); g.lineTo(mx, my); g.moveTo(bx, by); g.lineTo(mx, my); g.moveTo(cx, cy); g.lineTo(mx, my);
        g.stroke();
      }
      for (j = -1; j < 6; j++) for (i = -1; i < 4; i++) {
        var x0 = i * s + ((j & 1) ? s / 2 : 0), y0 = j * th;
        tri(x0, y0, x0 + s, y0, x0 + s / 2, y0 + th);
        tri(x0 + s, y0, x0 + s / 2, y0 + th, x0 + s * 1.5, y0 + th);
      }
      g.restore();
      fibres(g, w, h, 12, 0.8, true);
    });
  };

  P.yagasuri = function (a, b, cw) {
    cw = cw || 48;
    return mk(cw * 4, cw * 4, function (g, w, h) {
      g.fillStyle = a; g.fillRect(0, 0, w, h);
      var band = cw, col, y;
      for (col = 0; col < 4; col++) {
        var x0 = col * cw, flip = col & 1;
        for (y = -3; y < h / band + 3; y++) {
          g.fillStyle = (y & 1) ? b : a;
          var yy = y * band + (flip ? band / 2 : 0);
          g.beginPath();
          if (!flip) {
            g.moveTo(x0, yy); g.lineTo(x0 + cw / 2, yy + cw / 2); g.lineTo(x0 + cw, yy);
            g.lineTo(x0 + cw, yy + band); g.lineTo(x0 + cw / 2, yy + band + cw / 2); g.lineTo(x0, yy + band);
          } else {
            g.moveTo(x0, yy + cw / 2); g.lineTo(x0 + cw / 2, yy); g.lineTo(x0 + cw, yy + cw / 2);
            g.lineTo(x0 + cw, yy + band + cw / 2); g.lineTo(x0 + cw / 2, yy + band); g.lineTo(x0, yy + band + cw / 2);
          }
          g.closePath(); g.fill();
        }
        g.fillStyle = 'rgba(255,255,255,0.5)'; g.fillRect(x0 + cw / 2 - 1, 0, 2, h);
        g.fillStyle = 'rgba(0,0,0,0.18)'; g.fillRect(x0 - 1, 0, 2, h);
      }
      fibres(g, w, h, 13, 0.8, true);
    });
  };

  P.shippo = function (bg, line, d, dot) {
    d = d || 64;
    return mk(d * 2, d * 2, function (g, w, h) {
      g.fillStyle = bg; g.fillRect(0, 0, w, h);
      g.strokeStyle = line; g.lineWidth = d * 0.07;
      var i, j;
      for (j = -1; j <= 3; j++) for (i = -1; i <= 3; i++) {
        g.beginPath(); g.arc(i * d, j * d, d / Math.SQRT2 - g.lineWidth * 0.2, 0, 7); g.stroke();
      }
      g.fillStyle = dot || line;
      for (j = 0; j <= 4; j++) for (i = 0; i <= 4; i++) {
        var x = i * d / 2, y = j * d / 2;
        if ((i + j) & 1) continue;
        var s = (i & 1) ? d * 0.05 : d * 0.085;
        g.beginPath(); g.moveTo(x, y - s); g.lineTo(x + s, y); g.lineTo(x, y + s); g.lineTo(x - s, y); g.closePath(); g.fill();
      }
      fibres(g, w, h, 14, 0.8, true);
    });
  };

  P.ichimatsu = function (a, b, s) {
    s = s || 64;
    return mk(s * 2, s * 2, function (g, w, h) {
      g.fillStyle = a; g.fillRect(0, 0, w, h);
      g.fillStyle = b; g.fillRect(0, 0, s, s); g.fillRect(s, s, s, s);
      fibres(g, w, h, 15, 1, true);
    });
  };

  P.kikko = function (bg, line, s) {
    s = s || 40;
    var hx = Math.round(s * Math.sqrt(3));
    return mk(hx * 2, s * 6, function (g, w, h) {
      g.fillStyle = bg; g.fillRect(0, 0, w, h);
      g.strokeStyle = line; g.lineWidth = s * 0.09; g.lineJoin = 'round';
      for (var j = -1; j < 6; j++) for (var i = -1; i < 4; i++) {
        var cx = i * hx + ((j & 1) ? hx / 2 : 0), cy = j * s * 1.5;
        g.beginPath();
        for (var k = 0; k < 6; k++) { var a = Math.PI / 6 + k * Math.PI / 3; g.lineTo(cx + Math.cos(a) * s, cy + Math.sin(a) * s); }
        g.closePath(); g.stroke();
        g.beginPath();
        for (k = 0; k < 6; k++) { a = Math.PI / 6 + k * Math.PI / 3; g.lineTo(cx + Math.cos(a) * s * 0.45, cy + Math.sin(a) * s * 0.45); }
        g.closePath(); g.stroke();
      }
      fibres(g, w, h, 16, 0.8, true);
    });
  };

  function sakura(g, x, y, r, rot, fill, core) {
    g.save(); g.translate(x, y); g.rotate(rot);
    g.fillStyle = fill;
    for (var i = 0; i < 5; i++) {
      g.rotate(Math.PI * 2 / 5);
      g.beginPath(); g.moveTo(0, 0);
      g.bezierCurveTo(r * 0.55, -r * 0.25, r * 0.6, -r * 0.95, r * 0.12, -r);
      g.lineTo(0, -r * 0.82); g.lineTo(-r * 0.12, -r);
      g.bezierCurveTo(-r * 0.6, -r * 0.95, -r * 0.55, -r * 0.25, 0, 0); g.fill();
    }
    g.fillStyle = core; g.beginPath(); g.arc(0, 0, r * 0.16, 0, 7); g.fill();
    g.restore();
  }
  SG.drawSakura = sakura;

  P.sakura = function (bg, petal, core) {
    return mk(256, 256, function (g, w, h) {
      g.fillStyle = bg; g.fillRect(0, 0, w, h);
      var pts = [[40, 50, 30, 0.2], [170, 30, 22, 1], [110, 130, 34, 2], [220, 150, 26, 0.7], [40, 200, 24, 1.6], [170, 220, 30, 2.6]];
      pts.forEach(function (p) {
        for (var dx = -1; dx <= 1; dx++) for (var dy = -1; dy <= 1; dy++) sakura(g, p[0] + dx * w, p[1] + dy * h, p[2], p[3], petal, core);
      });
      fibres(g, w, h, 17, 0.8, true);
    });
  };

  P.stripes = function (cols, widths) {
    var tot = widths.reduce(function (a, b) { return a + b; }, 0);
    return mk(tot, 64, function (g, w, h) {
      var x = 0;
      for (var i = 0; i < cols.length; i++) { g.fillStyle = cols[i]; g.fillRect(x, 0, widths[i], h); x += widths[i]; }
      fibres(g, w, h, 18, 0.6, true);
    });
  };

  /* ---- wood ---- */
  P.wood = function (o) {
    o = o || {};
    var W = o.w || 512, H = o.h || 512;
    return mk(W, H, function (g, w, h) {
      var r = rng(o.seed || 3), base = o.base || PAL.woodMid, planks = o.planks || 1, i;
      g.fillStyle = base; g.fillRect(0, 0, w, h);
      var pw = w / planks;
      for (var p = 0; p < planks; p++) {
        g.save(); g.beginPath(); g.rect(p * pw, 0, pw, h); g.clip();
        var tint = (r() - 0.5) * (o.vary == null ? 0.22 : o.vary);
        g.fillStyle = tint > 0 ? 'rgba(255,235,200,' + tint + ')' : 'rgba(30,12,0,' + (-tint) + ')';
        g.fillRect(p * pw, 0, pw, h);
        // grain runs along Y; periodic in Y so the texture tiles
        var f1 = 1 + Math.floor(r() * 2), f2 = 2 + Math.floor(r() * 3), ph1 = r() * 7, ph2 = r() * 7, amp = pw * (0.02 + r() * 0.05);
        var n = Math.floor(pw / 2.2);
        for (i = 0; i < n; i++) {
          var x0 = p * pw + (i + r()) / n * pw, a = 0.04 + r() * (o.contrast || 0.14);
          g.strokeStyle = r() < 0.75 ? 'rgba(40,18,4,' + a + ')' : 'rgba(255,230,190,' + a * 0.8 + ')';
          g.lineWidth = 0.5 + r() * 1.6;
          g.beginPath();
          var k = (i / n - 0.5) * 2;
          for (var y = 0; y <= h; y += 8) {
            var t = y / h * Math.PI * 2;
            var x = x0 + Math.sin(t * f1 + ph1) * amp * (0.4 + k * k) + Math.sin(t * f2 + ph2 + i * 0.05) * amp * 0.35;
            if (y === 0) g.moveTo(x, y); else g.lineTo(x, y);
          }
          g.stroke();
        }
        if (o.knots !== 0 && r() < (o.knots || 0.5)) {
          var kx = p * pw + pw * (0.25 + r() * 0.5), ky = h * (0.15 + r() * 0.7), kr = pw * (0.05 + r() * 0.05);
          for (i = 6; i > 0; i--) {
            g.strokeStyle = 'rgba(40,18,4,' + (0.07 + (6 - i) * 0.04) + ')'; g.lineWidth = 1.2;
            g.beginPath(); g.ellipse(kx, ky, kr * i * 0.5, kr * i * 0.9, 0, 0, 7); g.stroke();
          }
          g.fillStyle = 'rgba(40,18,4,0.45)'; g.beginPath(); g.ellipse(kx, ky, kr * 0.4, kr * 0.6, 0, 0, 7); g.fill();
        }
        g.restore();
        if (planks > 1) {
          g.fillStyle = 'rgba(15,6,0,0.55)'; g.fillRect(p * pw - 1, 0, 2.2, h);
          g.fillStyle = 'rgba(255,240,210,0.16)'; g.fillRect(p * pw + 1.5, 0, 1.2, h);
          if (o.joints !== false) {
            var jy = Math.floor(r() * h);
            g.fillStyle = 'rgba(15,6,0,0.5)'; g.fillRect(p * pw, jy, pw, 2);
            g.fillStyle = 'rgba(255,240,210,0.14)'; g.fillRect(p * pw, jy + 2, pw, 1);
          }
        }
      }
      // overall soft mottling
      for (i = 0; i < 40; i++) {
        g.fillStyle = r() < 0.5 ? 'rgba(255,230,190,0.03)' : 'rgba(30,10,0,0.035)';
        g.beginPath(); g.ellipse(r() * w, r() * h, 20 + r() * 60, 60 + r() * 140, 0, 0, 7); g.fill();
      }
    });
  };

  P.tatami = function () {
    return mk(256, 256, function (g, w, h) {
      g.fillStyle = '#bdb878'; g.fillRect(0, 0, w, h);
      var r = rng(21), y, x;
      for (y = 0; y < h; y += 2) {
        g.fillStyle = 'rgba(' + (r() < 0.5 ? '90,95,40' : '235,230,170') + ',' + (0.1 + r() * 0.22) + ')';
        g.fillRect(0, y, w, 1);
      }
      for (x = 0; x < w; x += 16) {
        g.fillStyle = 'rgba(70,75,30,0.16)'; g.fillRect(x, 0, 1, h);
        g.fillStyle = 'rgba(250,245,200,0.14)'; g.fillRect(x + 1, 0, 1, h);
      }
      for (var i = 0; i < 300; i++) {
        g.fillStyle = 'rgba(' + (r() < 0.5 ? '120,125,60' : '225,215,150') + ',0.25)';
        g.fillRect(r() * w, Math.floor(r() * h / 2) * 2, 6 + r() * 30, 1);
      }
    });
  };

  P.plaster = function (base, seed) {
    return mk(256, 256, function (g, w, h) {
      g.fillStyle = base; g.fillRect(0, 0, w, h);
      var r = rng(seed || 31);
      for (var i = 0; i < 1400; i++) {
        g.fillStyle = 'rgba(' + (r() < 0.5 ? '255,255,245' : '120,95,60') + ',' + (r() * 0.05) + ')';
        var s = 1 + r() * 5; g.fillRect(r() * w, r() * h, s, s);
      }
      fibres(g, w, h, 32, 0.7);
    });
  };

  /* ---- text helpers ---- */
  function vtext(g, str, x, y, size, color, weight, gap) {
    g.fillStyle = color; g.textAlign = 'center'; g.textBaseline = 'middle';
    g.font = (weight || 400) + ' ' + size + 'px ' + FONT;
    gap = gap || size * 1.08;
    for (var i = 0; i < str.length; i++) {
      var ch = str[i], cy = y + i * gap + size / 2;
      if (ch === 'ー') { g.save(); g.translate(x, cy); g.rotate(Math.PI / 2); g.fillText(ch, 0, 0); g.restore(); }
      else g.fillText(ch, x, cy);
    }
  }
  function inkText(g, str, x, y, size, color, vertical, strokeW) {
    // brush-like: stroke the glyph outline to fatten the regular-weight font
    g.lineJoin = 'round'; g.strokeStyle = color; g.lineWidth = strokeW == null ? size * 0.07 : strokeW;
    g.fillStyle = color; g.textAlign = 'center'; g.textBaseline = 'middle';
    g.font = '400 ' + size + 'px ' + FONT;
    for (var i = 0; i < str.length; i++) {
      var ch = str[i], cx = vertical ? x : x + (i - (str.length - 1) / 2) * size * 1.08, cy = vertical ? y + i * size * 1.1 + size / 2 : y;
      g.save(); g.translate(cx, cy);
      if (ch === 'ー' && vertical) g.rotate(Math.PI / 2);
      g.strokeText(ch, 0, 0); g.fillText(ch, 0, 0); g.restore();
    }
  }
  SG.inkText = inkText;

  P.noren = function (ch, crest) { // one indigo noren flap
    return mk(256, 512, function (g, w, h) {
      var gr = g.createLinearGradient(0, 0, w, 0);
      gr.addColorStop(0, '#1b2d4c'); gr.addColorStop(0.3, '#2b446e'); gr.addColorStop(0.55, '#223a60'); gr.addColorStop(0.8, '#2d4772'); gr.addColorStop(1, '#192a47');
      g.fillStyle = gr; g.fillRect(0, 0, w, h);
      fibres(g, w, h, 51 + (ch ? ch.charCodeAt(0) : 0), 1.2, true);
      g.fillStyle = 'rgba(255,255,255,0.75)'; g.fillRect(0, 22, w, 3);
      if (crest) {
        g.strokeStyle = '#f6efdf'; g.lineWidth = 12; g.beginPath(); g.arc(w / 2, h * 0.5, 84, 0, 7); g.stroke();
        // simple fish-and-wave crest
        g.lineWidth = 9; g.lineCap = 'round';
        for (var k = 0; k < 3; k++) { g.beginPath(); g.arc(w / 2 - 40 + k * 40, h * 0.5 + 36, 26, Math.PI, Math.PI * 1.85); g.stroke(); }
        g.fillStyle = '#f6efdf'; g.beginPath(); g.ellipse(w / 2 - 6, h * 0.5 - 16, 46, 22, -0.15, 0, 7); g.fill();
        g.beginPath(); g.moveTo(w / 2 + 30, h * 0.5 - 22); g.lineTo(w / 2 + 66, h * 0.5 - 48); g.lineTo(w / 2 + 62, h * 0.5 + 2); g.closePath(); g.fill();
        g.fillStyle = '#223a60'; g.beginPath(); g.arc(w / 2 - 32, h * 0.5 - 20, 5, 0, 7); g.fill();
      } else if (ch) {
        inkText(g, ch, w / 2, h * 0.5, 170, '#f6efdf', false, 12);
      }
      var sh = g.createLinearGradient(0, 0, 0, h);
      sh.addColorStop(0, 'rgba(0,0,0,0.35)'); sh.addColorStop(0.12, 'rgba(0,0,0,0)'); sh.addColorStop(1, 'rgba(0,0,0,0.12)');
      g.fillStyle = sh; g.fillRect(0, 0, w, h);
    });
  };

  P.lantern = function (text, body, ink, ribs) {
    return mk(512, 512, function (g, w, h) {
      var gr = g.createLinearGradient(0, 0, 0, h);
      gr.addColorStop(0, shade(body, -0.25)); gr.addColorStop(0.5, shade(body, 0.12)); gr.addColorStop(1, shade(body, -0.3));
      g.fillStyle = gr; g.fillRect(0, 0, w, h);
      for (var y = 6; y < h; y += ribs || 22) {
        g.fillStyle = 'rgba(0,0,0,0.16)'; g.fillRect(0, y, w, 2);
        g.fillStyle = 'rgba(255,255,255,0.14)'; g.fillRect(0, y + 2, w, 2);
      }
      // the text appears twice around the lantern
      for (var k = 0; k < 2; k++) inkText(g, text, w * (0.25 + k * 0.5), h * 0.5 - text.length * 62, 112, ink, true, 9);
    });
  };

  P.gyotaku = function () { // fish print scroll
    return mk(512, 1024, function (g, w, h) {
      g.fillStyle = '#6b4a2c'; g.fillRect(0, 0, w, h);
      g.drawImage(P.seigaiha('#27406a', '#4a6aa0', 32), 0, 0, 128, 64, 0, 0, w, h);
      g.fillStyle = 'rgba(20,30,50,0.25)'; g.fillRect(0, 0, w, h);
      g.fillStyle = PAL.gold; g.fillRect(44, 120, w - 88, h - 260);
      g.drawImage(P.washi('#f3e8d0', 61), 0, 0, 256, 256, 52, 128, w - 104, h - 276);
      // fish (sea bream), drawn head-down like a real gyotaku hanging
      g.save(); g.translate(w / 2 + 6, h * 0.47); g.rotate(Math.PI / 2 + 0.08); g.scale(1.15, 1.15);
      var r = rng(77);
      function body() {
        g.beginPath(); g.moveTo(-190, 0);
        g.bezierCurveTo(-150, -95, -10, -120, 110, -40);
        g.lineTo(150, -10); g.lineTo(150, 10); g.lineTo(110, 40);
        g.bezierCurveTo(-10, 110, -150, 85, -190, 0); g.closePath();
      }
      g.fillStyle = '#1d1a1a'; body(); g.fill();
      // tail
      g.beginPath(); g.moveTo(140, 0); g.bezierCurveTo(175, -20, 205, -75, 235, -88); g.bezierCurveTo(215, -30, 215, 30, 235, 88); g.bezierCurveTo(205, 75, 175, 20, 140, 0); g.fill();
      // dorsal + belly fins
      g.beginPath(); g.moveTo(-110, -88); g.bezierCurveTo(-60, -150, 30, -150, 90, -55); g.bezierCurveTo(20, -108, -50, -112, -110, -88); g.fill();
      g.beginPath(); g.moveTo(-30, 92); g.bezierCurveTo(0, 135, 40, 120, 60, 68); g.closePath(); g.fill();
      g.beginPath(); g.moveTo(-90, 20); g.bezierCurveTo(-60, 70, -20, 70, -10, 35); g.closePath(); g.fillStyle = '#3a3636'; g.fill();
      // scales (paper showing through)
      g.save(); body(); g.clip();
      g.strokeStyle = 'rgba(243,232,208,0.55)'; g.lineWidth = 2.2;
      for (var sx = -100; sx < 130; sx += 22) for (var sy = -110; sy < 110; sy += 20) {
        g.beginPath(); g.arc(sx + ((Math.round(sy / 20) & 1) ? 11 : 0), sy, 13, -1.2, 1.2); g.stroke();
      }
      // dry-brush flecks
      for (var i = 0; i < 900; i++) { g.fillStyle = 'rgba(243,232,208,' + (0.1 + r() * 0.35) + ')'; g.fillRect(-200 + r() * 450, -130 + r() * 260, 1 + r() * 5, 1 + r() * 2); }
      g.restore();
      // gill + eye
      g.strokeStyle = 'rgba(243,232,208,0.8)'; g.lineWidth = 4; g.beginPath(); g.arc(-150, 0, 62, -0.9, 0.9); g.stroke();
      g.fillStyle = '#f3e8d0'; g.beginPath(); g.arc(-150, -22, 15, 0, 7); g.fill();
      g.fillStyle = '#1d1a1a'; g.beginPath(); g.arc(-150, -22, 7, 0, 7); g.fill();
      g.restore();
      inkText(g, '大漁', w - 110, 170, 60, '#1d1a1a', true, 5);
      g.fillStyle = PAL.vermilion; g.fillRect(w - 138, 330, 56, 56);
      inkText(g, '魚', w - 110, 358, 40, '#f6ead2', false, 2);
      // roller ends
      g.fillStyle = '#2a1a10'; g.fillRect(0, 0, w, 26); g.fillRect(0, h - 40, w, 40);
    });
  };

  P.byobu = function (panel) { // gold-leaf folding screen panel, 0..3
    return mk(384, 768, function (g, w, h) {
      var gr = g.createLinearGradient(0, 0, w, h);
      gr.addColorStop(0, '#e6bf62'); gr.addColorStop(0.5, '#d2a244'); gr.addColorStop(1, '#c08f36');
      g.fillStyle = gr; g.fillRect(0, 0, w, h);
      var r = rng(90 + panel), i, j;
      for (j = 0; j < 8; j++) for (i = 0; i < 4; i++) {
        g.fillStyle = 'rgba(' + (r() < 0.5 ? '255,240,180' : '120,80,10') + ',' + (0.04 + r() * 0.1) + ')';
        g.fillRect(i * 96 + 1, j * 96 + 1, 94, 94);
      }
      // clouds
      g.fillStyle = 'rgba(250,236,190,0.75)';
      for (i = 0; i < 3; i++) {
        var cy = 90 + r() * 240, cx = r() * w;
        for (j = 0; j < 5; j++) { g.beginPath(); g.ellipse(cx + (j - 2) * 46, cy + Math.sin(j * 1.7) * 10, 50, 17, 0, 0, 7); g.fill(); }
      }
      // red sun on panel 2
      if (panel === 2) { g.fillStyle = '#5d7f8a'; g.beginPath(); g.moveTo(40, 300); g.lineTo(150, 150); g.lineTo(210, 215); g.lineTo(270, 120); g.lineTo(350, 300); g.closePath(); g.fill(); g.fillStyle = '#f3ead2'; g.beginPath(); g.moveTo(250, 150); g.lineTo(270, 120); g.lineTo(292, 152); g.lineTo(272, 144); g.closePath(); g.fill(); } // distant mountains on panel 2
      // pine on panels 0-1
      if (panel < 2) {
        g.strokeStyle = '#3a2416'; g.lineWidth = 20; g.lineCap = 'round';
        g.beginPath(); g.moveTo(panel === 0 ? 60 : -40, 620); g.bezierCurveTo(140, 520, 80, 420, 240 - panel * 120, 330); g.stroke();
        for (i = 0; i < 6; i++) {
          var px = 80 + r() * 240 - panel * 60, py = 250 + r() * 200;
          g.fillStyle = i & 1 ? '#3f6b3a' : '#56824a';
          g.beginPath(); g.ellipse(px, py, 82, 30, 0, Math.PI, 0); g.fill();
          g.strokeStyle = 'rgba(20,50,20,0.5)'; g.lineWidth = 2;
          for (j = -70; j <= 70; j += 10) { g.beginPath(); g.moveTo(px, py); g.lineTo(px + j, py - 28 * Math.sqrt(Math.max(0, 1 - j * j / 6400))); g.stroke(); }
        }
      }
      // waves along the bottom
      var wav = P.seigaiha('#24467a', '#eef0ea', 32);
      g.save(); g.beginPath(); g.moveTo(0, h);
      for (i = 0; i <= w; i += 8) g.lineTo(i, h - 170 - Math.sin((i + panel * 384) / 90) * 26 - Math.sin((i + panel * 384) / 37) * 8);
      g.lineTo(w, h); g.closePath(); g.clip();
      g.fillStyle = g.createPattern(wav, 'repeat'); g.fillRect(0, 0, w, h); g.restore();
      // black lacquer frame with brocade inner border
      g.strokeStyle = '#1b1412'; g.lineWidth = 22; g.strokeRect(0, 0, w, h);
      g.strokeStyle = PAL.vermilionDeep; g.lineWidth = 6; g.strokeRect(16, 16, w - 32, h - 32);
    });
  };

  P.rug = function () {
    return mk(1024, 768, function (g, w, h) {
      g.fillStyle = PAL.vermilionDeep; g.fillRect(0, 0, w, h);
      g.fillStyle = g.createPattern(P.shippo('#a02a1b', '#e1b455', 32, '#f4d892'), 'repeat'); g.fillRect(0, 0, w, h);
      g.fillStyle = '#1e3152'; g.fillRect(64, 64, w - 128, h - 128);
      g.fillStyle = g.createPattern(P.asanoha('#213659', '#d9dfe6', 48), 'repeat'); g.fillRect(80, 80, w - 160, h - 160);
      g.strokeStyle = PAL.goldLight; g.lineWidth = 8; g.strokeRect(64, 64, w - 128, h - 128);
      g.strokeStyle = PAL.gold; g.lineWidth = 6; g.strokeRect(8, 8, w - 16, h - 16);
      // centre medallion
      function dia(r0) { g.beginPath(); g.moveTo(w / 2, h / 2 - r0); g.lineTo(w / 2 + r0 * 1.25, h / 2); g.lineTo(w / 2, h / 2 + r0); g.lineTo(w / 2 - r0 * 1.25, h / 2); g.closePath(); } // a diamond of waves, not a disc
      g.fillStyle = '#2f6f6a'; dia(150); g.fill();
      g.save(); dia(138); g.clip();
      g.fillStyle = g.createPattern(P.seigaiha('#3f8f8a', '#f6dfb0', 28), 'repeat'); g.fillRect(0, 0, w, h); g.restore();
      g.strokeStyle = PAL.goldLight; g.lineWidth = 8; dia(150); g.stroke();
      fibres(g, w, h, 71, 1.5, true);
    });
  };

  P.shoji = function () {
    return mk(256, 512, function (g, w, h) {
      var gr = g.createRadialGradient(w / 2, h * 0.45, 10, w / 2, h * 0.45, h * 0.7);
      gr.addColorStop(0, '#fffaf0'); gr.addColorStop(1, '#f0dfc0');
      g.fillStyle = gr; g.fillRect(0, 0, w, h);
      fibres(g, w, h, 81, 1.2);
      // faint bamboo shadow behind the paper
      g.strokeStyle = 'rgba(110,125,90,0.16)'; g.lineWidth = 9; g.lineCap = 'round';
      g.beginPath(); g.moveTo(60, h); g.quadraticCurveTo(80, 250, 130, 40); g.stroke();
      g.lineWidth = 3;
      for (var i = 0; i < 9; i++) { var y = 80 + i * 44, x = 126 - i * 6.5; g.beginPath(); g.moveTo(x, y); g.quadraticCurveTo(x + 40, y - 30, x + 78, y - 22); g.stroke(); g.beginPath(); g.moveTo(x, y); g.quadraticCurveTo(x - 30, y - 34, x - 62, y - 30); g.stroke(); }
    });
  };

  P.label = function (text, bg, ink) { // bottle / barrel label
    return mk(256, 256, function (g, w, h) {
      g.fillStyle = bg; g.fillRect(0, 0, w, h);
      fibres(g, w, h, 91, 1);
      g.strokeStyle = ink; g.lineWidth = 8; g.strokeRect(14, 14, w - 28, h - 28);
      var sz = text.length > 1 ? Math.min(86, Math.floor(196 / text.length / 1.1)) : 150;
      inkText(g, text, w / 2, text.length > 1 ? (h - text.length * sz * 1.1) / 2 : h / 2 - 80, sz, ink, true, sz * 0.09);
    });
  };

  P.shadowBlob = function () {
    return mk(128, 128, function (g, w, h) {
      var gr = g.createRadialGradient(64, 64, 4, 64, 64, 64);
      gr.addColorStop(0, 'rgba(0,0,0,0.75)'); gr.addColorStop(0.55, 'rgba(0,0,0,0.32)'); gr.addColorStop(1, 'rgba(0,0,0,0)');
      g.fillStyle = gr; g.fillRect(0, 0, w, h);
    });
  };
  P.aoStrip = function () { // vertical gradient: opaque dark at v=0 fading up
    return mk(8, 128, function (g, w, h) {
      var gr = g.createLinearGradient(0, h, 0, 0);
      gr.addColorStop(0, 'rgba(10,4,0,0.62)'); gr.addColorStop(0.3, 'rgba(10,4,0,0.22)'); gr.addColorStop(1, 'rgba(10,4,0,0)');
      g.fillStyle = gr; g.fillRect(0, 0, w, h);
    });
  };
  P.glow = function () {
    return mk(128, 128, function (g, w, h) {
      var gr = g.createRadialGradient(64, 64, 0, 64, 64, 64);
      gr.addColorStop(0, 'rgba(255,220,160,1)'); gr.addColorStop(0.25, 'rgba(255,190,110,0.5)'); gr.addColorStop(1, 'rgba(255,170,80,0)');
      g.fillStyle = gr; g.fillRect(0, 0, w, h);
    });
  };

  P.gingham = function (a, b, s) {
    s = s || 24;
    return mk(s * 2, s * 2, function (g, w, h) {
      g.fillStyle = '#fbf6ec'; g.fillRect(0, 0, w, h); g.fillStyle = rgba(a, 0.55); g.fillRect(0, 0, s, h); g.fillRect(0, 0, w, s); g.fillStyle = b || a; g.fillRect(0, 0, s, s);
      fibres(g, w, h, 23, 0.8, true);
    });
  };
  P.dots = function (bg, dot, s) {
    s = s || 32;
    return mk(s * 2, s * 2, function (g, w, h) {
      g.fillStyle = bg; g.fillRect(0, 0, w, h); g.fillStyle = dot;
      [[s / 2, s / 2], [s * 1.5, s * 1.5]].forEach(function (p) { g.beginPath(); g.arc(p[0], p[1], s * 0.24, 0, 7); g.fill(); });
      fibres(g, w, h, 24, 0.8, true);
    });
  };
  P.tartan = function (bg, a, b) {
    return mk(128, 128, function (g, w, h) {
      g.fillStyle = bg; g.fillRect(0, 0, w, h);
      [[0, 34, a, 0.55], [50, 10, b, 0.8], [76, 22, a, 0.55], [110, 6, '#f6efdc', 0.8]].forEach(function (t) { g.fillStyle = rgba(t[2], t[3]); g.fillRect(t[0], 0, t[1], h); g.fillRect(0, t[0], w, t[1]); });
      fibres(g, w, h, 25, 1, true);
    });
  };
  P.uroko = function (a, b, s) {
    s = s || 32;
    return mk(s * 2, s * 2, function (g, w, h) {
      g.fillStyle = a; g.fillRect(0, 0, w, h); g.fillStyle = b;
      for (var j = 0; j < 2; j++) for (var i = -1; i < 3; i++) { var x = i * s + (j ? s / 2 : 0), y = j * s; g.beginPath(); g.moveTo(x, y + s); g.lineTo(x + s / 2, y); g.lineTo(x + s, y + s); g.closePath(); g.fill(); }
      fibres(g, w, h, 26, 0.8, true);
    });
  };
  P.patchwork = function (cols) {
    return mk(192, 192, function (g, w, h) {
      var r = rng(27);
      for (var j = 0; j < 4; j++) for (var i = 0; i < 4; i++) { g.fillStyle = cols[Math.floor(r() * cols.length)]; g.fillRect(i * 48, j * 48, 48, 48); g.strokeStyle = 'rgba(255,255,255,0.7)'; g.setLineDash([4, 4]); g.lineWidth = 1.5; g.strokeRect(i * 48 + 3, j * 48 + 3, 42, 42); }
      fibres(g, w, h, 28, 1, true);
    });
  };

  SG.P = P;

  /* wrap a canvas as a THREE texture. size = metres per tile (for repeating textures with UVs in metres) */
  var cache = {};
  SG.tex = function (key, canvasFn, opt) {
    if (cache[key]) return cache[key];
    opt = opt || {};
    var c = canvasFn();
    var t = new THREE.CanvasTexture(c);
    t.colorSpace = THREE.SRGBColorSpace;
    t.anisotropy = 8;
    if (opt.size) {
      t.wrapS = t.wrapT = THREE.RepeatWrapping;
      var sx = Array.isArray(opt.size) ? opt.size[0] : opt.size, sy = Array.isArray(opt.size) ? opt.size[1] : opt.size * c.height / c.width;
      t.repeat.set(1 / sx, 1 / sy);
    } else if (opt.wrap) { t.wrapS = t.wrapT = THREE.RepeatWrapping; }
    cache[key] = t;
    return t;
  };
})();
