/* ===== zoom-draw.js: one frame of the organization, at any scale. Line weights stay constant on screen. =====
   Hot path: no closures, arrays or strings are created per frame (fonts and strings are prepared in layout). */
(function () {
  'use strict';
  var A = Z.A, OS = Z.OS, TAU = Math.PI * 2;
  function clamp(v, a, b) { return v < a ? a : v > b ? b : v; }
  function sm(t) { t = clamp(t, 0, 1); return t * t * (3 - 2 * t); }
  Z.sm = sm; Z.clamp = clamp;

  // visibility of a keyframe-indexed on/off list at camera position q: fade out in the first half, in in the second
  function vis(arr, q) {
    var i = Math.floor(q), f = q - i, a = arr[i < 10 ? i : 10], b = arr[i + 1 < 10 ? i + 1 : 10];
    if (a === b) return a;
    return a > b ? 1 - sm(f * 2) : sm(f * 2 - 1);
  }
  function mix(arr, q) { var i = Math.floor(q), f = q - i, a = arr[i < 10 ? i : 10], b = arr[i + 1 < 10 ? i + 1 : 10]; return a + (b - a) * sm(f); }
  Z.vis = vis; Z.mix = mix;

  // point along a polyline edge at distance d, written into out: [x, y, segment]
  function at(e, d, out) {
    var p = e.pts, c = e.cum, j = 1, n = c.length - 1;
    while (j < n && c[j] < d) j++;
    var a = p[j - 1], b = p[j], L = c[j] - c[j - 1] || 1, t = clamp((d - c[j - 1]) / L, 0, 1);
    out[0] = a[0] + (b[0] - a[0]) * t; out[1] = a[1] + (b[1] - a[1]) * t; out[2] = j;
    return out;
  }
  Z.at = at;
  Z.mkEdge = function (pts) {
    var cum = [0];
    for (var j = 1; j < pts.length; j++) cum.push(cum[j - 1] + Math.hypot(pts[j][0] - pts[j - 1][0], pts[j][1] - pts[j - 1][1]));
    return { pts: pts, cum: cum, len: cum[cum.length - 1] };
  };
  Z.trim = function (p, q, d) { var dx = q[0] - p[0], dy = q[1] - p[1], n = Math.hypot(dx, dy) || 1; return [p[0] + dx / n * d, p[1] + dy / n * d]; };

  // the canvas fonts, made once per layout: F.f11 = '400 11px <family>' … and F.px[font] = its size
  Z.fonts = function (fam) {
    var F = { px: {} };
    function mk(key, w, px) { F[key] = w + ' ' + px + 'px ' + fam; F.px[F[key]] = px; }
    mk('f11', 400, 11); mk('f115', 400, 11.5); mk('f12', 400, 12); mk('w115', 600, 11.5); mk('w12', 500, 12); mk('w125', 500, 12.5); mk('w13', 600, 13);
    // the document's text is set at the camera's scale: font strings are made once per size step and reused
    var memo = {};
    F.doc = function (wt) { return function (px) { var k = wt + ':' + Math.round(px * 4); return memo[k] || (memo[k] = wt + ' ' + (Math.round(px * 4) / 4) + 'px ' + fam); }; };
    return F;
  };
  Z.dash = { wire: [2.5, 3.5], box: [3, 3], call: [1, 4], drop: [5, 4], none: [] };

  // ---------- labels: measured (any script), kept inside the canvas, recorded for the layout audit ----------
  // lab(g, st, text, x, y, align, font, colour, bg): draws one line; bg paints the page colour behind it so it reads
  // over lines. Returns the drawn width. x is clamped so the box never leaves the canvas.
  var PAD = 4;
  function lab(g, st, s, x, y, align, font, col, bg, kind) {
    if (g.font !== font) g.font = font;
    var w = g.measureText(s).width, x0 = align === 'right' ? x - w : align === 'center' ? x - w / 2 : x;
    if (x0 < PAD) x0 = PAD; else if (x0 + w > st.vw - PAD) x0 = st.vw - PAD - w;
    var fs = st.F.px[font] || 12, top = y - fs * 0.8, bot = y + fs * 0.25;
    if (bg) { var a = g.globalAlpha; g.fillStyle = st.C.bg; g.fillRect(x0 - 3, top - 2, w + 6, bot - top + 4); g.globalAlpha = a; }
    g.fillStyle = col; g.textAlign = 'left'; g.fillText(s, x0, y);
    if (st.audit && g.globalAlpha > 0.5) st.audit.push({ k: kind || 'label', s: s, x0: x0, y0: top, x1: x0 + w, y1: bot });
    return w;
  }
  Z.lab = lab;
  // a node of the drawing (for the audit: labels must not cover nodes)
  function node(st, x, y, r) { if (st.audit) st.audit.push({ k: 'node', s: '', x0: x - r, y0: y - r, x1: x + r, y1: y + r }); }
  Z.node = node;

  var vis0 = [], ptA = [0, 0, 0], ptB = [0, 0, 0];
  var st_, cx_, cy_, s_;
  function X(x) { return cx_ + x * s_; }
  function Y(y) { return cy_ + y * s_; }
  Z.X = X; Z.Y = Y;

  Z.draw = function (g, st) {
    var W = st.W, C = st.C, cam = st.cam, s = cam.s, q = st.q, now = st.t;
    st_ = st; s_ = s; cx_ = cam.cx - cam.ux * s; cy_ = cam.cy - cam.uy * s;
    var cx = cx_, cy = cy_, vw = st.vw, vh = st.vh, i, j, S, a, c, p, x, y;
    var wx0 = -cx / s, wy0 = -cy / s, wx1 = (vw - cx) / s, wy1 = (vh - cy) / s;
    var V = st.sup.vis;
    var dim = 0.2 + 0.8 * mix(V.dim, q);
    var r = A * s; // agent radius on screen
    g.lineCap = 'butt'; g.lineJoin = 'miter';

    // ---------- the organization ----------
    vis0.length = 0;
    for (i = 0; i < W.swarms.length; i++) {
      var b = W.swarms[i].bx;
      if (b[2] < wx0 - 40 || b[0] > wx1 + 40 || b[3] < wy0 - 40 || b[1] > wy1 + 40) continue;
      vis0.push(W.swarms[i]);
    }
    st.visible = vis0;
    var nv = vis0.length;
    var la = clamp((r - 0.6) / 2.4, 0, 1); // lines get a bit stronger as agents become legible
    g.lineWidth = 1;
    // supervision: buses and combs
    g.strokeStyle = C.ink2; g.globalAlpha = (0.2 + 0.14 * la) * dim;
    g.beginPath();
    for (i = 0; i < nv; i++) { c = vis0[i].comb; for (j = 0; j < c.length; j += 4) { g.moveTo(cx + c[j] * s, cy + c[j + 1] * s); g.lineTo(cx + c[j + 2] * s, cy + c[j + 3] * s); } }
    g.stroke();
    // declared paths
    g.globalAlpha = (0.42 + 0.2 * la) * dim;
    g.beginPath();
    for (i = 0; i < nv; i++) {
      var E = vis0[i].edges;
      for (var k = 0; k < E.length; k++) { p = E[k].pts; g.moveTo(cx + p[0][0] * s, cy + p[0][1] * s); for (j = 1; j < p.length; j++) g.lineTo(cx + p[j][0] * s, cy + p[j][1] * s); }
    }
    g.stroke();
    // supervisors (diamonds) once they have a size
    var dd = 5.5 * s;
    if (dd > 1.2) {
      g.globalAlpha = dim * clamp((dd - 1.2) / 1.5, 0, 1) * 0.9;
      g.beginPath();
      for (i = 0; i < nv; i++) { a = vis0[i].sup; for (j = 0; j < a.length; j++) { x = cx + a[j][0] * s; y = cy + a[j][1] * s; g.moveTo(x, y - dd); g.lineTo(x + dd, y); g.lineTo(x, y + dd); g.lineTo(x - dd, y); g.closePath(); } }
      g.fillStyle = C.bg; g.fill(); g.strokeStyle = C.ink2; g.stroke();
    }
    // objects
    var os = OS * s, h;
    g.globalAlpha = dim;
    if (os < 3.4) {
      h = Math.max(os, 1.9) / 2; g.fillStyle = C.ink2; g.beginPath();
      for (i = 0; i < nv; i++) { a = vis0[i].ob; for (j = 0; j < a.length; j++) g.rect(cx + a[j][0] * s - h, cy + a[j][1] * s - h, h * 2, h * 2); }
      g.fill();
    } else {
      g.beginPath();
      for (i = 0; i < nv; i++) { a = vis0[i].ob; for (j = 0; j < a.length; j++) g.rect(cx + a[j][0] * s - os / 2, cy + a[j][1] * s - os / 2, os, os); }
      g.fillStyle = C.bg; g.fill(); g.strokeStyle = C.ink; g.lineWidth = 1.2; g.stroke(); g.lineWidth = 1;
      var cs = Math.max(1.4, os * 0.27); g.fillStyle = C.ink; g.beginPath();
      for (i = 0; i < nv; i++) { a = vis0[i].ob; for (j = 0; j < a.length; j++) g.rect(cx + a[j][0] * s - cs / 2, cy + a[j][1] * s - cs / 2, cs, cs); }
      g.fill();
    }
    // agents: squares when tiny (cheaper than arcs, and identical at that size), dots, then ring + core once legible
    var ringT = clamp((r - 2.1) / 1.6, 0, 1);
    if (ringT < 1) {
      var rd = Math.max(r, 0.95);
      g.globalAlpha = dim * (1 - ringT) * 0.92; g.fillStyle = C.ink2; g.beginPath();
      var tiny = rd < 1.35, e2 = rd * 0.886;
      for (i = 0; i < nv; i++) {
        a = vis0[i].ag;
        for (j = 0; j < a.length; j += 2) {
          x = cx + a[j] * s; y = cy + a[j + 1] * s;
          if (x < -4 || x > vw + 4 || y < -4 || y > vh + 4) continue;
          if (tiny) g.rect(x - e2, y - e2, e2 * 2, e2 * 2); else { g.moveTo(x + rd, y); g.arc(x, y, rd, 0, TAU); }
        }
      }
      g.fill();
    }
    if (ringT > 0) {
      g.globalAlpha = dim * ringT; g.beginPath();
      for (i = 0; i < nv; i++) { a = vis0[i].ag; for (j = 0; j < a.length; j += 2) { x = cx + a[j] * s; y = cy + a[j + 1] * s; if (x < -r || x > vw + r || y < -r || y > vh + r) continue; g.moveTo(x + r, y); g.arc(x, y, r, 0, TAU); } }
      g.fillStyle = C.bg; g.fill(); g.strokeStyle = C.ink; g.lineWidth = 1.2; g.stroke(); g.lineWidth = 1;
      var ri = r / 3; g.fillStyle = C.ink; g.beginPath();
      for (i = 0; i < nv; i++) { a = vis0[i].ag; for (j = 0; j < a.length; j += 2) { x = cx + a[j] * s; y = cy + a[j + 1] * s; if (x < -r || x > vw + r || y < -r || y > vh + r) continue; g.moveTo(x + ri, y); g.arc(x, y, ri, 0, TAU); } }
      g.fill();
    }
    g.globalAlpha = 1;

    // ---------- messages on declared paths ----------
    var PL = st.pulses;
    if (PL.n) {
      g.strokeStyle = C.ink; g.lineWidth = 1.6; g.lineCap = 'round';
      var segL = 9 / s;
      for (i = 0; i < PL.list.length; i++) {
        var P = PL.list[i];
        if (!P.on || !P.e) continue;
        var e = P.e, d1 = Math.min(P.d, e.len), d0 = Math.max(0, P.d - segL);
        if (d1 <= d0) continue;
        var env = clamp(P.d / (segL * 1.5), 0, 1) * clamp((e.len + segL - P.d) / (segL * 1.5), 0, 1);
        g.globalAlpha = 0.95 * env * (P.sup ? vis(V[st.tEdges[P.route[P.j]].grp], q) : dim);
        at(e, d0, ptA); at(e, d1, ptB);
        g.beginPath(); g.moveTo(cx + ptA[0] * s, cy + ptA[1] * s);
        for (j = ptA[2]; j < ptB[2]; j++) g.lineTo(cx + e.pts[j][0] * s, cy + e.pts[j][1] * s);
        g.lineTo(cx + ptB[0] * s, cy + ptB[1] * s); g.stroke();
      }
      g.lineCap = 'butt'; g.lineWidth = 1; g.globalAlpha = 1;
    }

    // ---------- crashes: an agent turns orange and stops; its supervisor restarts it ----------
    var CR = st.crashes;
    for (i = 0; i < CR.length; i++) {
      var K = CR[i];
      if (!K.on) continue;
      S = K.S; x = cx + S.ag[2 * K.i] * s; y = cy + S.ag[2 * K.i + 1] * s;
      var t = now - K.t0, cr = Math.max(r, 2.4), R = Math.max(r + 5, 7.5);
      if (t < 1.9) { // crashed: orange, still
        var fi = clamp(t / 0.15, 0, 1);
        g.globalAlpha = fi; g.fillStyle = C.bg; g.beginPath(); g.arc(x, y, cr + 1.5, 0, TAU); g.fill();
        g.fillStyle = C.or; g.beginPath(); g.arc(x, y, cr, 0, TAU); g.fill();
        g.strokeStyle = C.or; g.lineWidth = 1; g.globalAlpha = fi * 0.7; g.beginPath(); g.arc(x, y, R, 0, TAU); g.stroke();
      }
      if (t > 1.3 && t < 1.9) { // the supervisor's restart travels down its line
        c = S.agCol[K.i]; var u = sm((t - 1.3) / 0.6), ty = c[1] + (S.ag[2 * K.i + 1] - c[1]) * u;
        g.globalAlpha = 0.9; g.strokeStyle = C.ink; g.lineWidth = 1.6; g.lineCap = 'round';
        g.beginPath(); g.moveTo(cx + c[0] * s, Math.max(cy + c[1] * s, cy + ty * s - 9)); g.lineTo(cx + c[0] * s, cy + ty * s); g.stroke(); g.lineCap = 'butt';
      }
      if (t >= 1.9) { // restarted: a ring draws around it, then fades
        var u2 = sm((t - 1.9) / 0.7), fo = 1 - sm((t - 2.7) / 0.6);
        g.globalAlpha = fo; g.strokeStyle = C.ink; g.lineWidth = 1.2;
        g.beginPath(); g.arc(x, y, R, -Math.PI / 2, -Math.PI / 2 + TAU * u2); g.stroke();
      }
      g.lineWidth = 1; g.globalAlpha = 1;
    }

    // ---------- the control layer over the organization (K10) ----------
    var cA = vis(V.ctl, q);
    if (cA > 0.01 && W.ctl) {
      var L = W.ctl, rows = L.rows;
      g.globalAlpha = cA * 0.55; g.strokeStyle = C.ink2; g.beginPath();
      g.moveTo(X(L.spine), Y(L.y + L.h)); g.lineTo(X(L.spine), Y(rows[rows.length - 1].y));
      for (i = 0; i < rows.length; i++) {
        var RW = rows[i];
        g.moveTo(X(L.spine), Y(RW.y)); g.lineTo(X(RW.x1), Y(RW.y));
        for (j = 0; j < RW.xs.length; j++) { g.moveTo(X(RW.xs[j][0]), Y(RW.y)); g.lineTo(X(RW.xs[j][0]), Y(RW.xs[j][1])); }
      }
      g.stroke();
      g.globalAlpha = cA; g.fillStyle = C.bg2; var bx = X(L.x1), by = Y(L.y), bw = (L.x2 - L.x1) * s, bh = L.h * s;
      g.fillRect(bx, by, bw, bh);
      g.strokeStyle = C.ink3; g.strokeRect(bx + 0.5, by + 0.5, bw - 1, bh - 1);
      if (bh > 18) Z.barText(g, st, bx, by, bw, bh, st.S.ctlR, true);
      g.globalAlpha = 1;
    }

    // ---------- the support team (its own states per keyframe) ----------
    Z.drawSupport(g, st, s, r);

    // ---------- swarm names, once legible (identifiers: the same in every language) ----------
    var nA = mix(V.dim, q);
    if (nA > 0.02) {
      g.textBaseline = 'alphabetic';
      for (i = 0; i < W.swarms.length; i++) if (W.swarms[i].name) swarmName(g, st, W.swarms[i].name, W.swarms[i].bx, nA, false);
      if (W.supBox) swarmName(g, st, 'support', W.supBox, nA, true);
      g.globalAlpha = 1;
    }
  };
  function swarmName(g, st, name, bx, nA, strong) {
    var w = (bx[2] - bx[0]) * s_; if (w < 40) return;
    var x = X(bx[0]), y = Y(bx[1]) - 7;
    if (x > st.vw || y < 0 || y > st.vh + 12) return;
    g.globalAlpha = nA * clamp((w - 40) / 30, 0, 1) * (strong ? 1 : 0.9);
    lab(g, st, name, x, y, 'left', st.F.f11, strong ? st.C.ink : st.C.ink2, true, 'name');
  }
  // the text inside the genswarms layer bar: the wordmark left; the right-hand text only where it fits whole
  Z.barText = function (g, st, bx, by, bw, bh, right, big) {
    var F = st.F, C = st.C, ym = by + bh / 2 + (big ? 4.3 : 4);
    var wf = bh > 20 ? F.w13 : F.w115;
    var ww = lab(g, st, 'genswarms', bx + (bh > 20 ? 14 : 8), ym, 'left', wf, C.ink, false, 'bar');
    if (!right) return;
    if (g.font !== F.f115) g.font = F.f115;
    var rw = g.measureText(right).width;
    if (rw + ww + 56 <= bw && bx + bw - 14 <= st.vw - PAD) lab(g, st, right, bx + bw - 14, ym, 'right', F.f115, C.ink2, false, 'bar');
  };
})();
