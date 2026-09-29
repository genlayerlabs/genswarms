/* ===== zoom-support.js: the support team and the story told around it (keyframes K1-K9) =====
   Every word drawn here comes from st.S (the page's catalogue, in the page's language) or is an identifier. */
(function () {
  'use strict';
  var A = Z.A, OS = Z.OS, TAU = Math.PI * 2, clamp = Z.clamp, sm = Z.sm, vis = Z.vis, lab = Z.lab, node = Z.node;
  function hex(g, x, y, R) { g.beginPath(); for (var i = 0; i < 6; i++) { var a = Math.PI / 6 + i * Math.PI / 3; if (i) g.lineTo(x + R * Math.cos(a), y + R * Math.sin(a)); else g.moveTo(x + R * Math.cos(a), y + R * Math.sin(a)); } g.closePath(); }
  function head(g, px, py, qx, qy, len, w) {
    var dx = qx - px, dy = qy - py, n = Math.hypot(dx, dy) || 1, ux = dx / n, uy = dy / n, bx = qx - ux * len, by = qy - uy * len;
    g.beginPath(); g.moveTo(qx, qy); g.lineTo(bx - uy * w, by + ux * w); g.lineTo(bx + uy * w, by - ux * w); g.closePath(); g.fill();
  }
  var ox = 0, oy = 0;
  function LX(x) { return Z.X(x + ox); }
  function LY(y) { return Z.Y(y + oy); }
  var P = []; for (var i0 = 0; i0 < 12; i0++) P.push([0, 0]);
  var OB = ['tg', 'cron', 'browser', 'budget'];
  var NAMES = ['triage', 'answer', 'research', 'tg', 'cron', 'browser', 'budget'];
  var CO = [[156, 650, 'supervisor', 1], [200, 654, 'process', 0], [320, 668, 'sandbox', 1]]; // y, line start, string, sandbox-only

  Z.drawSupport = function (g, st, s, r) {
    var W = st.W, C = st.C, q = st.q, SUP = st.sup, V = SUP.vis, now = st.t, rm = st.rm, F = st.F, S = st.S;
    var i, x, y, a, p, j;
    ox = W.sx; oy = W.sy;
    // current agent positions
    var i0 = Math.floor(q), f = sm(q - i0), i1 = Math.min(i0 + 1, 10); i0 = Math.min(i0, 10);
    for (i = 0; i < 12; i++) {
      var pa = SUP.AGPOS[i0][i], pb = SUP.AGPOS[i1][i];
      P[i][0] = pa[0] + (pb[0] - pa[0]) * f; P[i][1] = pa[1] + (pb[1] - pa[1]) * f;
    }
    var aExtra = vis(V.extra, q);
    g.lineWidth = 1;

    // K3: many agents, each wired to the others by hand
    var wA = vis(V.wires, q);
    if (wA > 0.01) {
      g.globalAlpha = wA * 0.6; g.strokeStyle = C.ink2; g.setLineDash(st.dash.wire); g.lineCap = 'round';
      g.beginPath();
      for (j = 0; j < SUP.wires.length; j++) {
        var w = SUP.wires[j], pp = P[w[0]], qq = P[w[1]], mx = (pp[0] + qq[0]) / 2, my = (pp[1] + qq[1]) / 2, dx = qq[0] - pp[0], dy = qq[1] - pp[1], n = Math.hypot(dx, dy) || 1;
        var kk = (j % 2 ? 1 : -1) * Math.min(46, n * 0.24), ccx = mx - dy / n * kk, ccy = my + dx / n * kk;
        var d0x = ccx - pp[0], d0y = ccy - pp[1], n0 = Math.hypot(d0x, d0y) || 1, d1x = ccx - qq[0], d1y = ccy - qq[1], n1 = Math.hypot(d1x, d1y) || 1, tr = A + 5;
        g.moveTo(LX(pp[0] + d0x / n0 * tr), LY(pp[1] + d0y / n0 * tr)); g.quadraticCurveTo(LX(ccx), LY(ccy), LX(qq[0] + d1x / n1 * tr), LY(qq[1] + d1y / n1 * tr));
      }
      g.stroke(); g.setLineDash(st.dash.none); g.lineCap = 'butt';
    }

    // K4-K5: the GenSwarms layer and the process tree
    var yA = vis(V.layer, q), B = SUP.bar;
    if (yA > 0.01) {
      var top = B.y + B.h, lastBus = SUP.gy[SUP.gy.length - 1] - SUP.drop;
      // the tree draws down from the layer
      var grow = rm ? 1 : clamp((q - 3) / 0.9, 0, 1);
      if (q > 5.2) grow = 1;
      g.globalAlpha = yA * 0.7; g.strokeStyle = C.ink2; g.beginPath();
      g.moveTo(LX(SUP.spine), LY(top)); g.lineTo(LX(SUP.spine), LY(top + (lastBus - top) * sm(grow * 1.4)));
      for (var row = 0; row < SUP.gy.length; row++) {
        var gy = SUP.gy[row], gr = sm(grow * 1.6 - row * 0.2); if (gr <= 0) continue;
        var xe = SUP.spine + (SUP.gx[SUP.gx.length - 1] - SUP.spine) * gr;
        g.moveTo(LX(SUP.spine), LY(gy - SUP.drop)); g.lineTo(LX(xe), LY(gy - SUP.drop));
        for (j = 0; j < SUP.gx.length; j++) if (SUP.gx[j] <= xe) { g.moveTo(LX(SUP.gx[j]), LY(gy - SUP.drop)); g.lineTo(LX(SUP.gx[j]), LY(gy - A - 3)); }
      }
      g.stroke();
      g.globalAlpha = yA; g.fillStyle = C.bg2; var bx = LX(B.x1), by = LY(B.y), bw = (B.x2 - B.x1) * s, bh = B.h * s;
      g.fillRect(bx, by, bw, bh); g.strokeStyle = C.ink3; g.strokeRect(bx + 0.5, by + 0.5, bw - 1, bh - 1);
      if (bh > 13) Z.barText(g, st, bx, by, bw, bh, bw > 330 ? S.layer : '', false);
    }

    // K5: sandboxes and supervisors
    var bA = vis(V.sbx, q), crashP = -1;
    if (bA > 0.01) {
      var S2 = SUP.sandbox * s;
      if (!rm) crashP = now % 4.8;
      var crashing = crashP > 0.4 && crashP < 2.1;
      g.globalAlpha = bA * 0.75; g.strokeStyle = C.ink3; g.setLineDash(st.dash.box); g.beginPath();
      for (j = 0; j < SUP.grid.length; j++) { if (j === SUP.crash && crashing) continue; p = SUP.grid[j]; g.rect(LX(p[0]) - S2 / 2, LY(p[1]) - S2 / 2, S2, S2); }
      g.stroke();
      if (crashing) { p = SUP.grid[SUP.crash]; g.strokeStyle = C.or; g.globalAlpha = bA; g.beginPath(); g.rect(LX(p[0]) - S2 / 2, LY(p[1]) - S2 / 2, S2, S2); g.stroke(); }
      g.setLineDash(st.dash.none);
      var dd = 5 * s; g.globalAlpha = bA; g.beginPath();
      for (j = 0; j < SUP.grid.length; j++) { p = SUP.grid[j]; x = LX(p[0]); y = LY(p[1] - SUP.drop); g.moveTo(x, y - dd); g.lineTo(x + dd, y); g.lineTo(x, y + dd); g.lineTo(x - dd, y); g.closePath(); }
      g.fillStyle = C.bg; g.fill(); g.strokeStyle = C.ink; g.stroke();
    }
    // callouts (K4: process; K5: supervisor, process, sandbox), where there is room for them
    if (s > 0.55) for (j = 0; j < CO.length; j++) {
      var c = CO[j], ca = c[3] ? bA : Math.max(bA, yA);
      if (ca < 0.01) continue;
      g.globalAlpha = ca; g.strokeStyle = C.ink3; g.beginPath(); g.moveTo(LX(c[1]), LY(c[0])); g.lineTo(LX(684), LY(c[0])); g.stroke();
      lab(g, st, S[c[2]], LX(690), LY(c[0]) + 4, 'left', F.f115, C.ink2, false, 'callout');
    }

    // declared paths of the team
    var EAc = vis(V.core, q), EAm = vis(V.more, q), arrows = s > 0.3;
    for (j = 0; j < st.tEdges.length; j++) {
      var E = st.tEdges[j], ea = E.grp === 'core' ? EAc : EAm; if (ea < 0.01) continue;
      var pts = E.e.pts, m = E.kind === 'm';
      g.globalAlpha = ea * (m ? 0.75 : 0.85); g.strokeStyle = C.ink2;
      if (m) { g.setLineDash(st.dash.call); g.lineCap = 'round'; g.lineWidth = 1.4; }
      g.beginPath(); g.moveTo(Z.X(pts[0][0]), Z.Y(pts[0][1])); for (var k = 1; k < pts.length; k++) g.lineTo(Z.X(pts[k][0]), Z.Y(pts[k][1])); g.stroke();
      if (m) { g.setLineDash(st.dash.none); g.lineCap = 'butt'; g.lineWidth = 1; }
      if (arrows && !m) { var nn = pts.length; g.fillStyle = C.ink2; head(g, Z.X(pts[nn - 2][0]), Z.Y(pts[nn - 2][1]), Z.X(pts[nn - 1][0]), Z.Y(pts[nn - 1][1]), 7, 3.2); }
    }

    // K6: the dropped message (research -> telegram is not on the graph)
    var T = SUP.T, dA = vis(V.drop, q);
    if (dA > 0.01) {
      var D = SUP.dropLine, p0x = LX(D[0]), p0y = LY(D[1]), p1x = LX(D[2]), p1y = LY(D[3]);
      g.globalAlpha = dA; g.strokeStyle = C.or; g.lineWidth = 1.3; g.setLineDash(st.dash.drop);
      g.beginPath(); g.moveTo(p0x, p0y); g.lineTo(p1x, p1y); g.stroke(); g.setLineDash(st.dash.none);
      var hit = 0;
      if (!rm) {
        var dc = now % 4.4;
        if (dc < 1.1) {
          var u = sm(dc / 1.1), px = p0x + (p1x - p0x) * u, py = p0y + (p1y - p0y) * u, ln = Math.hypot(p1x - p0x, p1y - p0y) || 1;
          g.strokeStyle = C.ink; g.lineWidth = 1.6; g.lineCap = 'round';
          g.beginPath(); g.moveTo(px - (p1x - p0x) / ln * 9, py - (p1y - p0y) / ln * 9); g.lineTo(px, py); g.stroke(); g.lineCap = 'butt';
        } else hit = clamp(1 - (dc - 1.1) / 0.9, 0, 1);
      }
      var xs = 6 * Math.max(s, 0.8) * (1 + hit * 0.25), X0 = LX(D[4]), Y0 = LY(D[5]);
      g.strokeStyle = C.or; g.lineWidth = 2; g.lineCap = 'square'; g.beginPath(); g.moveTo(X0 - xs, Y0 - xs); g.lineTo(X0 + xs, Y0 + xs); g.moveTo(X0 + xs, Y0 - xs); g.lineTo(X0 - xs, Y0 + xs); g.stroke();
      g.lineWidth = 1; g.lineCap = 'butt';
      node(st, X0, Y0, 7.5);
      if (s > 0.45) lab(g, st, S.dropped, X0, Y0 + 7.5 * Math.max(s, 0.8) + 16, 'center', F.w12, C.or, true, 'dropped');
    }

    // objects
    var os = OS * s;
    for (j = 0; j < OB.length; j++) {
      a = vis(j === 0 ? V.tg : V.objs, q); if (a < 0.01) continue;
      p = T[OB[j]]; x = LX(p[0]); y = LY(p[1]);
      g.globalAlpha = a;
      if (os < 3.4) { var h = Math.max(os, 1.9) / 2; g.fillStyle = C.ink2; g.fillRect(x - h, y - h, h * 2, h * 2); continue; }
      g.fillStyle = C.bg; g.fillRect(x - os / 2, y - os / 2, os, os); g.strokeStyle = C.ink; g.lineWidth = 1.2; g.strokeRect(x - os / 2, y - os / 2, os, os); g.lineWidth = 1;
      var cs = Math.max(1.4, os * 0.27); g.fillStyle = C.ink; g.fillRect(x - cs / 2, y - cs / 2, cs, cs);
      node(st, x, y, os / 2);
    }
    // K8: each object from a signed, verified package
    var kA = vis(V.seals, q);
    if (kA > 0.01) for (j = 0; j < OB.length; j++) {
      p = T[OB[j]]; x = LX(p[0] + OS / 2 + 4); y = LY(p[1] - OS / 2 - 4); var R = Math.max(6, 7 * s);
      g.globalAlpha = kA; g.fillStyle = C.bg; g.beginPath(); g.arc(x, y, R, 0, TAU); g.fill(); g.strokeStyle = C.ink; g.stroke();
      g.lineWidth = 1.4; g.beginPath(); g.moveTo(x - R * 0.42, y + R * 0.02); g.lineTo(x - R * 0.1, y + R * 0.34); g.lineTo(x + R * 0.46, y - R * 0.3); g.stroke(); g.lineWidth = 1;
      node(st, x, y, R);
    }

    // agents
    var ringT = clamp((r - 2.1) / 1.6, 0, 1), inner = clamp((r - 44) / 70, 0, 1);
    for (i = 0; i < 12; i++) {
      var al = i < 3 ? 1 : aExtra; if (al < 0.01) continue;
      x = LX(P[i][0]); y = LY(P[i][1]);
      if (x < -r - 200 || x > st.vw + r + 200 || y < -r - 200 || y > st.vh + r + 200) continue;
      var hot = i === SUP.crash && crashP > 0.4 && crashP < 1.8 && bA > 0.01;
      g.globalAlpha = al;
      if (ringT < 1 && !hot) { g.fillStyle = C.ink2; g.globalAlpha = al * (1 - ringT); g.beginPath(); g.arc(x, y, Math.max(r, 1), 0, TAU); g.fill(); g.globalAlpha = al * ringT; }
      if (ringT > 0 || hot) {
        g.fillStyle = C.bg; g.beginPath(); g.arc(x, y, r, 0, TAU); g.fill();
        g.strokeStyle = hot ? C.or : C.ink; g.lineWidth = 1.2; g.stroke(); g.lineWidth = 1;
        var core = (r / 3) * (1 - inner) + Math.max(3, r * 0.045) * inner;
        g.fillStyle = hot ? C.or : C.ink; g.beginPath(); g.arc(x, y, hot ? r * 0.62 : core, 0, TAU); g.fill();
        if (inner > 0.01) drawInside(g, st, x, y, r, core, inner * al);
        else if (al > 0.5 && r < 40) node(st, x, y, r);
      }
    }
    // K5: the crash and the restart
    if (bA > 0.01) {
      var cp = SUP.grid[SUP.crash], ccx2 = LX(cp[0]), ccy2 = LY(cp[1]), RR = r + 5;
      var ringU = rm ? 1 : crashP < 1.8 ? 0 : sm((crashP - 1.8) / 0.7), fade = rm ? 1 : 1 - sm((crashP - 4.1) / 0.5);
      if (ringU > 0) { g.globalAlpha = bA * fade; g.strokeStyle = C.ink; g.lineWidth = 1.4; g.beginPath(); g.arc(ccx2, ccy2, RR, -Math.PI / 2, -Math.PI / 2 + TAU * ringU); g.stroke(); g.lineWidth = 1; }
      if (s > 0.3 && (rm || crashP > 0.5)) {
        // "crashed → restarted": two catalogue labels and an arrow, centred as one line under the crashed agent
        g.globalAlpha = bA * fade;
        if (g.font !== F.w12) g.font = F.w12;
        var w1 = g.measureText(S.crashed).width, w2 = g.measureText(S.arrowRestarted).width, lx = ccx2 - (w1 + w2) / 2, ly = ccy2 + SUP.sandbox * s / 2 + 18;
        lx = clamp(lx, 4, st.vw - 4 - w1 - w2);
        lab(g, st, S.crashed, lx, ly, 'left', F.w12, C.or, false, 'crash');
        if (ringU > 0.2) { g.globalAlpha *= rm ? 1 : clamp((ringU - 0.2) / 0.5, 0, 1); lab(g, st, S.arrowRestarted, lx + w1, ly, 'left', F.w12, C.ink2, false, 'crash'); }
      }
    }

    // names, once legible (identifiers)
    var nA = vis(V.names, q) * clamp((r - 2.6) / 1.2, 0, 1) * (1 - clamp((r - 30) / 12, 0, 1));
    if (nA > 0.01) {
      for (j = 0; j < NAMES.length; j++) {
        var key = NAMES[j];
        a = key === 'tg' ? vis(V.tg, q) : j > 3 ? vis(V.objs, q) : 1;
        if (a < 0.01) continue;
        var L = SUP.labels[key]; g.globalAlpha = nA * a;
        // (browser and budget make room for their package seal, top right of the square)
        var shift = kA > 0.01 && (key === 'browser' || key === 'budget') ? kA * 8 : 0;
        lab(g, st, SUP.names[key], LX(L[0]) + shift, LY(L[1]) + 4, L[2] === 'end' ? 'right' : 'left', F.w125, C.ink, true, 'name');
      }
    }
    var mA = vis(V.calls, q);
    if (mA > 0.01 && s > 0.5) { g.globalAlpha = mA; lab(g, st, S.modelCalls, LX(510), LY(470) + 4, 'center', F.f115, C.ink2, true, 'calls'); }

    // K9: the swarm as a document, and the database it restores from
    var docA = vis(V.doc, q);
    if (docA > 0.01) drawDoc(g, st, s, docA);
    g.globalAlpha = 1;
  };

  // an agent, up close: a model, a prompt and some tools
  function drawInside(g, st, x, y, r, core, a) {
    var C = st.C, F = st.F, S = st.S;
    var mhx = x, mhy = y - r * 0.5, tlx = x - r * 0.52, tly = y + r * 0.26, prx = x + r * 0.52, pry = y + r * 0.26;
    var hr = Math.max(7, r * 0.1), ts = Math.max(12, r * 0.15), pw = Math.max(10, r * 0.12), ph = pw * 1.25;
    g.globalAlpha = a * 0.8; g.strokeStyle = C.ink3; g.beginPath();
    seg(g, x, y, core, mhx, mhy, hr + 6); seg(g, x, y, core, tlx, tly, ts * 0.72 + 6); seg(g, x, y, core, prx, pry, ph * 0.62 + 6);
    g.stroke();
    g.globalAlpha = a; g.strokeStyle = C.ink2; g.lineWidth = 1.2;
    hex(g, mhx, mhy, hr); g.fillStyle = C.bg; g.fill(); g.stroke();
    g.fillRect(tlx - ts / 2, tly - ts / 2, ts, ts); g.strokeRect(tlx - ts / 2, tly - ts / 2, ts, ts);
    g.fillStyle = C.ink2; g.fillRect(tlx - ts * 0.14, tly - ts * 0.14, ts * 0.28, ts * 0.28);
    g.fillStyle = C.bg; g.fillRect(prx - pw / 2, pry - ph / 2, pw, ph); g.strokeRect(prx - pw / 2, pry - ph / 2, pw, ph);
    g.lineWidth = 1; g.beginPath();
    for (var k = 0; k < 3; k++) { var yy = pry - ph * 0.22 + k * ph * 0.2; g.moveTo(prx - pw * 0.28, yy); g.lineTo(prx + pw * (k === 2 ? 0.1 : 0.28), yy); }
    g.stroke();
    node(st, mhx, mhy, hr); node(st, tlx, tly, ts / 2); node(st, prx, pry, ph / 2); node(st, x, y, core + 2);
    lab(g, st, S.model, mhx, mhy - hr - 10, 'center', F.f12, C.ink2, false, 'inside');
    lab(g, st, S.tools, tlx, tly + ts / 2 + 20, 'center', F.f12, C.ink2, false, 'inside');
    lab(g, st, S.prompt, prx, pry + ph / 2 + 20, 'center', F.f12, C.ink2, false, 'inside');
    lab(g, st, S.agent, x, y + core + 22, 'center', F.w13, C.ink, false, 'inside');
  }
  function seg(g, x, y, core, px, py, d) {
    var dx = px - x, dy = py - y, n = Math.hypot(dx, dy);
    g.moveTo(x + dx / n * (core + 6), y + dy / n * (core + 6)); g.lineTo(px - dx / n * d, py - dy / n * d);
  }

  // the document: rows prepared in layout (st.doc: wrapped to the box in the page's language), drawn at scale
  function drawDoc(g, st, s, a) {
    var C = st.C, F = st.F, S = st.S, DC = st.doc, D = st.sup.doc;
    var x = LX(D.x), y0 = LY(D.y), w = D.w * s, fs = DC.fs * s, H = DC.h * s, j, R;
    g.globalAlpha = a; g.fillStyle = C.bg1; g.fillRect(x, y0, w, H); g.strokeStyle = C.hl3; g.strokeRect(x + 0.5, y0 + 0.5, w - 1, H - 1);
    g.beginPath(); g.moveTo(x, y0 + DC.h1 * s); g.lineTo(x + w, y0 + DC.h1 * s); g.stroke();
    g.setLineDash(st.dash.box); g.beginPath(); g.moveTo(x, y0 + DC.h2 * s); g.lineTo(x + w, y0 + DC.h2 * s); g.stroke(); g.setLineDash(st.dash.none);
    g.fillStyle = C.or; g.fillRect(x, y0 + DC.ref0 * s, 2, (DC.ref1 - DC.ref0) * s);
    if (fs >= 6) {
      var f4 = DC.font4(fs), f6 = DC.font6(fs), f5 = DC.font5(fs);
      for (j = 0; j < DC.rows.length; j++) {
        R = DC.rows[j];
        var fnt = R.wt === 600 ? f6 : R.wt === 500 ? f5 : f4;
        if (g.font !== fnt) g.font = fnt;
        g.fillStyle = C[R.col]; g.textAlign = R.right ? 'right' : 'left';
        g.fillText(R.t, R.right ? x + w - 18 * s : x + (18 + R.ind) * s, y0 + R.y * s);
      }
      g.textAlign = 'left';
    }
    // the document defines the running swarm
    var axx = LX(545), ay0 = y0 - 6, ay1 = LY(492);
    g.strokeStyle = C.ink3; g.beginPath(); g.moveTo(axx, ay0); g.lineTo(axx, ay1 + 8); g.stroke();
    g.fillStyle = C.ink3; g.beginPath(); g.moveTo(axx, ay1); g.lineTo(axx - 3.5, ay1 + 8); g.lineTo(axx + 3.5, ay1 + 8); g.closePath(); g.fill();
    if (ay0 - ay1 > 24) lab(g, st, S.defines, axx + 10, (ay0 + ay1) / 2 + 4, 'left', F.f115, C.ink2, false, 'defines');
    // the database it comes back from (where there is room left of the document)
    if (!DC.dbLines.length) return;
    var db = st.sup.db, dx = LX(db[0]), dy = LY(db[1]), rw = 20 * s, rh = 6 * s, hh = 30 * s;
    g.strokeStyle = C.ink2; g.fillStyle = C.bg; g.lineWidth = 1.2;
    g.beginPath(); g.ellipse(dx, dy - hh / 2, rw, rh, 0, 0, TAU); g.moveTo(dx - rw, dy - hh / 2); g.lineTo(dx - rw, dy + hh / 2); g.ellipse(dx, dy + hh / 2, rw, rh, 0, Math.PI, 0, true); g.lineTo(dx + rw, dy - hh / 2); g.stroke();
    g.lineWidth = 1;
    node(st, dx, dy, rw);
    for (j = 0; j < DC.dbLines.length; j++) lab(g, st, DC.dbLines[j], dx, dy + hh / 2 + rh + 20 + j * 16, 'center', F.f115, C.ink2, false, 'db');
  }
})();
