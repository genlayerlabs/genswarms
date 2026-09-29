/* ===== zoom-run.js: layout, the camera path, scroll, and the life of the world =====
   Words come from the page's own catalogue (the JSON block #zoom-strings, in the page's language); numbers are
   formatted for that language. The loop pauses while the stage is off screen or the tab is hidden. */
(function () {
  'use strict';
  var D = document, root = D.documentElement, stage = D.querySelector('.stage'), data = D.getElementById('zoom-strings');
  if (!stage || !window.Z || !data) return;
  var cv = stage.querySelector('canvas'), g = cv && cv.getContext ? cv.getContext('2d') : null;
  // no canvas: the page reads as it does without JavaScript (the readouts stay in the text)
  if (!g) { root.classList.remove('js', 'cine'); return; }
  var ZS = JSON.parse(data.textContent), lang = root.lang || 'en';
  var capLv = stage.querySelector('.zcap .lv'), capZf = stage.querySelector('.zcap .zf'), capN = stage.querySelector('.zcap .n'), capEl = stage.querySelector('.zcap');
  var ros = [].slice.call(stage.querySelectorAll('.ros > [data-at]'));
  var steps = [].slice.call(D.querySelectorAll('.step'));
  var col = stage.parentNode, top = D.querySelector('.top');
  var mqC = matchMedia(ZS.cine), mqR = matchMedia('(prefers-reduced-motion: reduce)');
  var SUP = Z.sup, A = Z.A, OS = Z.OS, clamp = Z.clamp, sm = Z.sm;

  function nfmt(opts) {
    try { var f = new Intl.NumberFormat(lang, opts); return function (n) { return f.format(n); }; }
    catch (e) { return function (n) { return opts ? n.toFixed(1) : String(Math.round(n)); }; }
  }
  var nf0 = nfmt(), nf1 = nfmt({ minimumFractionDigits: 1, maximumFractionDigits: 1 });
  function fill(s, v) { return s.replace(/\{(\w+)\}/g, function (m, k) { return k in v ? v[k] : m; }); }
  var S = {
    supervisor: ZS.supervisor, process: ZS.process, sandbox: ZS.sandbox, dropped: ZS.dropped, crashed: ZS.crashed,
    arrowRestarted: ' → ' + ZS.restarted, modelCalls: ZS.modelCalls, model: ZS.model, tools: ZS.tools, prompt: ZS.prompt,
    agent: ZS.agent, layer: ZS.layer, ctlR: 'REST · WebSocket · CLI', defines: ZS.defines
  };

  var st = { sup: SUP, C: {}, S: S, F: {}, tEdges: [], cam: { ux: 0, uy: 0, s: 1, cx: 0, cy: 0 }, audit: null,
    dash: Z.dash };
  // messages and crashes live in fixed pools: nothing is allocated while the world runs
  var PULSES = 72, pulseCap = 60;
  st.pulses = { n: 0, list: [] };
  for (var pi = 0; pi < PULSES; pi++) st.pulses.list.push({ on: false, sup: false, S: null, j: 0, d: 0, wait: 0, e: null, route: null });
  st.crashes = [];
  for (pi = 0; pi < 4; pi++) st.crashes.push({ on: false, S: null, i: 0, t0: 0 });
  var ROUTES = [[0, 2, 3, 4], [0, 1, 4], [5, 2, 3, 4], [5, 1, 4], [8], [7]];

  var W = null, Wasp = 0, cams = [], paths = [], anchors = [], s0 = 1, vw = 0, vh = 0, dpr = 1, maxDpr = 2, rm = mqR.matches;
  var q = 0, last = 0, raf = 0, onScreen = true, kShown = -1, nextCrash = 2.2, nextChain = 0.6, acc = 0, hold = -1;
  var lastW = 0, capKey = -1, capLvShown = '', cine = false, navH = 56, colTop = 0, colH = 0, vhStable = 0, ema = 16.7, slow = 0;

  function colors() {
    var cs = getComputedStyle(root), m = { bg: '--bg', bg1: '--bg-1', bg2: '--bg-2', ink: '--ink', ink2: '--ink-2', ink3: '--ink-3', or: '--or', hl3: '--hl-3' };
    for (var k in m) st.C[k] = cs.getPropertyValue(m[k]).trim();
    return cs.getPropertyValue('--fc').trim() || 'monospace';
  }
  function width(font, s) { if (g.font !== font) g.font = font; return g.measureText(s).width; }

  // greedy line breaking at spaces, and anywhere between Han, kana or Hangul syllables in a word that has no spaces
  var WIDE = /[⺀-鿿가-힯豈-﫿＀-￯]/;
  function wrap(s, maxW, font) {
    var toks = [], words = s.split(' '), i, j;
    for (i = 0; i < words.length; i++) {
      var w = words[i];
      if (WIDE.test(w) && width(font, w) > maxW) { for (j = 0; j < w.length; j++) toks.push([w[j], j === 0 && i ? ' ' : '']); }
      else toks.push([w, i ? ' ' : '']);
    }
    var lines = [], cur = '';
    for (i = 0; i < toks.length; i++) {
      var next = cur ? cur + toks[i][1] + toks[i][0] : toks[i][0];
      if (cur && width(font, next) > maxW) { lines.push(cur); cur = toks[i][0]; } else cur = next;
    }
    lines.push(cur);
    return lines;
  }

  // the document (K9), laid out once per language and font: rows wrap to the box, right-hand notes drop to their own
  // line when they don't fit beside the heading
  function docLayout(fam) {
    var Dd = SUP.doc, fs = Dd.fs, lh = Dd.lh, inner = Dd.w - 36, rows = [], y = 6, f4 = '400 ' + fs + 'px ' + fam, f6 = '600 ' + fs + 'px ' + fam, f5 = '500 ' + fs + 'px ' + fam;
    var sp = width(f4, '   ');
    function add(t, colr, wt, ind) {
      var font = wt === 600 ? f6 : wt === 500 ? f5 : f4, ls = wrap(t, inner - ind, font);
      for (var i = 0; i < ls.length; i++) { y += lh; rows.push({ t: ls[i], col: colr, wt: wt, y: y, ind: ind, right: false }); }
    }
    function headRow(t, note) {
      y += lh; rows.push({ t: t, col: 'ink', wt: 600, y: y, ind: 0, right: false });
      var nw = width(f4, note), hw = width(f6, t);
      if (hw + 24 + nw <= inner) rows.push({ t: note, col: 'ink3', wt: 400, y: y, ind: 0, right: true });
      else { y += lh * 0.8; rows.push({ t: note, col: 'ink3', wt: 400, y: y, ind: 0, right: true }); }
    }
    headRow('swarm.state', ZS.seed);
    add('agents   triage answer', 'ink', 400, 0); add('objects  telegram cron budget browser', 'ink', 400, 0);
    add('paths    ' + fill(ZS.declared, { n: nf0(4) }), 'ink', 400, 0);
    y += 12; var h1 = y; y += 2;
    headRow('swarm.overlay', ZS.log);
    add('1  add_agent research', 'ink', 400, 0); add('2  add_topology_edges +3', 'ink', 400, 0); add('3  bump_package telegram 0.6.6', 'ink', 400, 0);
    y += 12; var h2 = y; y += 2; var ref0 = y + 8;
    add('×  scale_agent_group answer 150', 'or', 500, 0);
    add(fill(ZS.refused, { cap: nf0(100) }), 'ink2', 400, sp);
    add(ZS.never, 'ink3', 400, sp);
    var ref1 = y + 8;
    y += 14;
    st.doc = { rows: rows, fs: fs, h: y, h1: h1, h2: h2, ref0: ref0, ref1: ref1, dbLines: [], font4: st.F.doc(400), font5: st.F.doc(500), font6: st.F.doc(600) };
  }

  // van Wijk & Nuij smooth zoom between two views [ux, uy, w]
  function zpath(p0, p1) {
    var rho = Math.SQRT2, r2 = 2, r4 = 4, ux0 = p0[0], uy0 = p0[1], w0 = p0[2], ux1 = p1[0], uy1 = p1[1], w1 = p1[2];
    var dx = ux1 - ux0, dy = uy1 - uy0, d2 = dx * dx + dy * dy, Sx;
    if (d2 < 1e-9) { Sx = Math.log(w1 / w0) / rho; return function (t, o) { o[0] = ux0 + t * dx; o[1] = uy0 + t * dy; o[2] = w0 * Math.exp(rho * t * Sx); }; }
    var d1 = Math.sqrt(d2), b0 = (w1 * w1 - w0 * w0 + r4 * d2) / (2 * w0 * r2 * d1), b1 = (w1 * w1 - w0 * w0 - r4 * d2) / (2 * w1 * r2 * d1);
    var R0 = Math.log(Math.sqrt(b0 * b0 + 1) - b0), R1 = Math.log(Math.sqrt(b1 * b1 + 1) - b1); Sx = (R1 - R0) / rho;
    var c0 = Math.cosh(R0), sh0 = Math.sinh(R0);
    return function (t, o) {
      var s = t * Sx, u = w0 / (r2 * d1) * (c0 * Math.tanh(rho * s + R0) - sh0);
      o[0] = ux0 + u * dx; o[1] = uy0 + u * dy; o[2] = w0 * c0 / Math.cosh(rho * s + R0);
    };
  }

  // fit a world rect into a safe screen rect, with room for labels that stick out of it by a fixed number of pixels:
  // items are [x, y, left, right, up, down] (a world anchor and its label's extent in px)
  // (on phones, labels may use the stage's side padding: the width is the whole stage less 6px a side)
  function fitL(rect, sf, items, pad) {
    pad = pad || 0;
    var Wd = items.length && vw < 600 ? vw - 12 : sf[2] - pad * 2, Hd = sf[3];
    function span(s, ax) {
      var lo = rect[ax] * s, hi = rect[ax + 2] * s;
      for (var i = 0; i < items.length; i++) {
        var it = items[i], v = it[ax] * s;
        lo = Math.min(lo, v - it[ax ? 4 : 2]); hi = Math.max(hi, v + it[ax ? 5 : 3]);
      }
      return [lo, hi];
    }
    var sHi = Math.min(Wd / (rect[2] - rect[0]), Hd / (rect[3] - rect[1])), sLo = 0, s = sHi;
    function ok(s) { var a = span(s, 0), b = span(s, 1); return a[1] - a[0] <= Wd && b[1] - b[0] <= Hd; }
    if (!ok(sHi)) { for (var it = 0; it < 30; it++) { var m = (sLo + sHi) / 2; if (ok(m)) sLo = m; else sHi = m; } s = sLo; }
    var sx = span(s, 0), sy = span(s, 1);
    return { ux: (sx[0] + sx[1]) / 2 / s, uy: (sy[0] + sy[1]) / 2 / s, s: s, sf: sf };
  }
  // the labels of the support team that stick out of its camera frames, per keyframe (local coordinates)
  function labelItems(k, narrow) {
    var F = st.F, out = [], L = SUP.labels, T = SUP.T, key, w;
    function nm(key) { var a = L[key]; w = width(F.w125, SUP.names[key]) + 6 + (k === 8 && (key === 'browser' || key === 'budget') ? 8 : 0); out.push(a[2] === 'end' ? [a[0], a[1], w, 0, 14, 6] : [a[0], a[1], 0, w, 14, 6]); }
    if (k >= 6 && k <= 9) { nm('triage'); nm('answer'); nm('research'); nm('tg'); }
    if (k >= 7 && k <= 9) { nm('cron'); nm('browser'); nm('budget'); }
    if (k === 6) { w = width(F.w12, S.dropped) / 2 + 4; out.push([SUP.dropLine[4], SUP.dropLine[5], w, w, 10, 32]); }
    if (k === 7 || k === 8) { w = width(F.f115, S.modelCalls) / 2 + 4; out.push([510, 470, w, w, 14, 8]); }
    if ((k === 4 || k === 5) && !narrow) { w = width(F.f115, S.supervisor) + 6; out.push([690, 200, 0, Math.max(w, width(F.f115, S.process) + 6, width(F.f115, S.sandbox) + 6), 0, 0]); }
    if (k === 5) { w = (width(F.w12, S.crashed) + width(F.w12, S.arrowRestarted)) / 2 + 4; out.push([SUP.grid[SUP.crash][0], SUP.grid[SUP.crash][1] + SUP.sandbox / 2, w, w, 0, 26]); }
    return out;
  }

  function roFor(k) { return k === 1 ? 0 : k; }
  function layout() {
    cine = mqC.matches; root.classList.toggle('cine', cine);
    rm = mqR.matches;
    var nvw = stage.clientWidth, nvh = stage.clientHeight;
    if (!nvw || !nvh) return;
    var ndpr = Math.min(window.devicePixelRatio || 1, maxDpr);
    if (nvw !== vw || nvh !== vh || ndpr !== dpr) { vw = nvw; vh = nvh; dpr = ndpr; cv.width = Math.round(vw * dpr); cv.height = Math.round(vh * dpr); }
    var fam = colors();
    st.F = Z.fonts(fam); docLayout(fam);
    navH = top ? top.offsetHeight : 56;
    // a phone's URL bar showing or hiding changes the height a little and nothing else: the reading line stays put
    if (innerWidth !== lastW || Math.abs(innerHeight - vhStable) > 150) vhStable = innerHeight;
    lastW = innerWidth;
    colTop = col.getBoundingClientRect().top + scrollY; colH = col.offsetHeight;
    // the part of the stage the drawing may use, per keyframe (room for the caption and the readout)
    var padT = capEl.offsetTop + capEl.offsetHeight + (cine ? 22 : 12), padS = cine ? 36 : 16;
    var safe = [], k;
    for (k = 0; k < 11; k++) {
      var ro = null;
      if (cine) for (var i = 0; i < ros.length; i++) if (+ros[i].getAttribute('data-at') === roFor(k)) ro = ros[i];
      var padB = ro ? ro.offsetHeight + 44 : cine ? 36 : 30;
      safe.push([padS, padT, vw - padS * 2, Math.max(80, vh - padT - padB)]);
    }
    var asp = safe[0][2] / safe[0][3];
    if (!W || Math.abs(Math.log(asp / Wasp)) > 0.12) { W = Z.build(asp); Wasp = asp; clearLife(); }
    st.W = W;
    st.tEdges = Z.teamEdges(W);
    var T = SUP.T;
    // camera for each keyframe
    var ob = W.box, padO = 60, ox = W.sx, oy = W.sy, narrow = vw < 600;
    // the document (K9) fills the frame on narrow or short stages, where the whole team would set it too small to read
    var docFocus = narrow || safe[9][3] < 520;
    cams[0] = fitL([ob[0] - padO, ob[1] - padO, ob[2] + padO, ob[3] + padO], safe[0], []);
    s0 = cams[0].s;
    // the control layer over the whole organization (drawn at K10)
    var GYb = 0.8 * 280, sp = ob[0] - 170, rowsC = W.rows.map(function (R) {
      var xs = []; R.it.forEach(function (S) { if (S.support) xs.push([W.supBox[0] + (W.supBox[2] - W.supBox[0]) / 2, W.supBox[1]]); else { var o = W.swarms.filter(function (w) { return w.id === S.id; })[0]; xs.push([(o.bx[0] + o.bx[2]) / 2, o.bx[1]]); } });
      return { y: R.y - GYb, xs: xs, x1: Math.max.apply(null, xs.map(function (d) { return d[0]; })) };
    });
    var bh = 30 / s0, by = rowsC[0].y - 30 / s0 - bh;
    W.ctl = { x1: sp - 20, x2: ob[2], y: by, h: bh, spine: sp, rows: rowsC };
    for (k = 1; k < 10; k++) {
      var c = SUP.cam[k];
      if (c === 'agent') {
        var ap = T.answer, sf = safe[k], s = Math.min(sf[2], sf[3]) * (narrow ? 0.37 : 0.31) / A;
        cams[k] = { ux: ap[0] + ox, uy: ap[1] + oy + 1.2, s: s, sf: sf };
      } else {
        if (k === 9 && docFocus) c = [SUP.doc.x - 8, SUP.doc.y - 26, SUP.doc.x + SUP.doc.w + 8, SUP.doc.y + st.doc.h + 18];
        // phones: the team's frames are horizontally just the drawing (its labels are fitted as items)
        else if (narrow && SUP.camX[k]) c = [SUP.camX[k][0], c[1], SUP.camX[k][1], c[3]];
        var items = (k === 9 && docFocus ? [] : labelItems(k, narrow)).map(function (it) { return [it[0] + ox, it[1] + oy, it[2], it[3], it[4], it[5]]; });
        cams[k] = fitL([c[0] + ox, c[1] + oy, c[2] + ox, c[3] + oy], safe[k], items, narrow && k !== 9 ? 30 : 0);
      }
    }
    cams[10] = fitL([W.ctl.x1 - 40, W.ctl.y - 40, ob[2] + padO, ob[3] + padO], safe[10], []);
    // the database note under the cylinder, wrapped to the room left of the document (wide stages only)
    var s9 = cams[9].s, room = Math.min(220, (SUP.doc.x - SUP.db[0] - 26) * 2 * s9);
    st.doc.dbLines = !docFocus && room > 60 ? wrap(ZS.restores, room, st.F.f115) : [];
    paths = [];
    for (k = 0; k < 10; k++) paths.push(zpath([cams[k].ux, cams[k].uy, 1000 / cams[k].s], [cams[k + 1].ux, cams[k + 1].uy, 1000 / cams[k + 1].s]));
    // scroll anchors: where the reading line must be for each keyframe
    var y0 = scrollY, rl = readLine(0), copy = function (i) { var c = steps[i].querySelector('.copy'), b = c.getBoundingClientRect(); return [b.top + y0, b.height]; };
    anchors = [rl];
    var c1 = copy(1), vhh = vhStable;
    if (cine) { anchors[2] = c1[0] + c1[1] * 0.5 - vhh * 0.2; anchors[3] = c1[0] + c1[1] * 0.5 + vhh * 0.24; }
    else { anchors[2] = c1[0] + 24; anchors[3] = c1[0] + c1[1] * 0.55; }
    anchors[1] = anchors[0] + (anchors[2] - anchors[0]) * 0.52;
    for (i = 2; i < steps.length; i++) { var ci = copy(i); anchors[i + 2] = cine ? ci[0] + ci[1] * 0.5 : ci[0] + 24; }
    for (k = 1; k < 11; k++) if (anchors[k] <= anchors[k - 1] + 20) anchors[k] = anchors[k - 1] + 20;
    kShown = -1; capKey = -1;
    render(performance.now() / 1000);
  }
  // the reading line (at scroll position y): the middle of the screen beside the pinned stage; on phones, just under
  // the stage
  function readLine(y) {
    if (y == null) y = scrollY;
    if (cine) return y + navH + (vhStable - navH) * 0.5;
    var sb = Math.max(colTop - y, navH) + colH;
    return y + sb + (vhStable - sb) * 0.2;
  }
  var HOLD = [0.05, 0.08, 0.2, 0.2, 0.2, 0.2, 0.2, 0.2, 0.2, 0.2];
  function target() {
    if (hold >= 0) return hold;
    var m = readLine();
    if (m <= anchors[0]) return 0;
    for (var k = 0; k < 10; k++) {
      if (m < anchors[k + 1]) {
        var f = (m - anchors[k]) / (anchors[k + 1] - anchors[k]), h = HOLD[k];
        return k + sm((f - h) / (1 - 2 * h));
      }
    }
    return 10;
  }

  var zv = [0, 0, 0];
  function camAt(qq, o) {
    var i = Math.min(Math.floor(qq), 9), f = qq - i;
    if (qq >= 10) { i = 9; f = 1; }
    paths[i](f, zv);
    var a = cams[i].sf, b = cams[i + 1].sf, e = sm(f);
    o.cx = a[0] + a[2] / 2 + ((b[0] + b[2] / 2) - (a[0] + a[2] / 2)) * e;
    o.cy = a[1] + a[3] / 2 + ((b[1] + b[3] / 2) - (a[1] + a[3] / 2)) * e;
    o.ux = zv[0]; o.uy = zv[1]; o.s = 1000 / zv[2];
    return o;
  }

  // ---------- life: messages and crashes ----------
  var rnd = Math.random, pipes = [], cand = [];
  function clearLife() { var i; for (i = 0; i < st.pulses.list.length; i++) st.pulses.list[i].on = false; st.pulses.n = 0; for (i = 0; i < st.crashes.length; i++) st.crashes[i].on = false; }
  function spawn() { var L = st.pulses.list; for (var i = 0; i < L.length; i++) if (!L[i].on) { st.pulses.n++; L[i].on = true; L[i].e = null; L[i].j = 0; L[i].d = 0; L[i].wait = 0; return L[i]; } return null; }
  function step(t, dt) {
    var cam = st.cam, s = cam.s, r = A * s, i, P;
    var vpx = 55 + 95 * clamp(r / 6, 0, 1), spd = clamp(vpx / s, 30, 2200);
    // messages on the organization's paths
    pipes.length = 0;
    var vis = st.visible || pipes;
    for (i = 0; i < vis.length; i++) if (vis[i].kind === 'pipe') pipes.push(vis[i]);
    acc += dt * Math.min(26, pipes.length * 0.7);
    while (acc >= 1) {
      acc -= 1;
      if (!pipes.length || st.pulses.n >= pulseCap) break;
      P = spawn(); if (!P) break;
      P.sup = false; P.S = pipes[rnd() * pipes.length | 0]; P.j = rnd() * P.S.edges.length | 0;
    }
    // the support team's messages follow its paths
    var core = Z.vis(SUP.vis.core, q), more = Z.vis(SUP.vis.more, q);
    nextChain -= dt;
    if (core > 0.5 && nextChain <= 0) {
      nextChain = 2.4 + rnd() * 0.8;
      P = spawn();
      if (P) { P.sup = true; P.route = ROUTES[(rnd() < 0.6 ? 0 : 1) + (more > 0.5 && rnd() < 0.3 ? 2 : 0)]; }
    }
    var L = st.pulses.list;
    for (i = 0; i < L.length; i++) {
      P = L[i]; if (!P.on) continue;
      if (P.wait > 0) { P.wait -= dt; P.e = null; continue; }
      var e = P.sup ? st.tEdges[P.route[P.j]].e : P.S.edges[P.j];
      P.e = e; P.d += dt * spd;
      if (P.d < e.len + 9 / s) continue;
      if (P.sup) {
        var arrived = st.tEdges[P.route[P.j]].to;
        if (more > 0.5 && (arrived === 'answer' || arrived === 'research') && rnd() < 0.8) { var M = spawn(); if (M) { M.sup = true; M.route = ROUTES[arrived === 'answer' ? 4 : 5]; M.wait = 0.15; } }
        if (P.j + 1 < P.route.length) { P.j++; P.d = 0; P.wait = 0.3 + rnd() * 0.4; P.e = null; continue; }
      } else if (P.j + 1 < P.S.edges.length && rnd() < 0.85) { P.j++; P.d = 0; P.wait = 0.2 + rnd() * 0.5; P.e = null; continue; }
      P.on = false; st.pulses.n--;
    }
    // crashes, now and then, while the whole organization is in view
    for (i = 0; i < st.crashes.length; i++) if (st.crashes[i].on && t - st.crashes[i].t0 >= 3.4) st.crashes[i].on = false;
    nextCrash -= dt;
    if (nextCrash <= 0) {
      nextCrash = 4.2 + rnd() * 3.2;
      if (q < 1.15 || q > 9.7) {
        var sf = cams[0].sf; cand.length = 0;
        for (i = 0; i < vis.length; i++) {
          var Sw = vis[i], x0 = cam.cx + (Sw.bx[0] - cam.ux) * s, x1 = cam.cx + (Sw.bx[2] - cam.ux) * s, y0 = cam.cy + (Sw.bx[1] - cam.uy) * s, y1 = cam.cy + (Sw.bx[3] - cam.uy) * s;
          if (x0 > sf[0] && x1 < sf[0] + sf[2] && y0 > sf[1] - 10 && y1 < sf[1] + sf[3] + 10) cand.push(Sw);
        }
        if (q > 9.7 && rnd() < 0.6) for (i = 0; i < cand.length; i++) if (cand[i].name === 'trading sim') { cand[0] = cand[i]; cand.length = 1; break; }
        if (cand.length) for (i = 0; i < st.crashes.length; i++) if (!st.crashes[i].on) { var K = st.crashes[i], S2 = cand[rnd() * cand.length | 0]; K.on = true; K.S = S2; K.i = rnd() * (S2.ag.length / 2) | 0; K.t0 = t; break; }
      }
    }
  }

  function render(t) {
    if (!W || !vw) return;
    st.q = q; st.t = t; st.vw = vw; st.vh = vh; st.rm = rm;
    if (!st.stepping) camAt(q, st.cam);
    g.setTransform(dpr, 0, 0, dpr, 0, 0);
    g.clearRect(0, 0, vw, vh);
    g.textBaseline = 'alphabetic';
    if (rm) clearLife();
    Z.draw(g, st);
    // caption: what scale we are at (strings change only when the rounded value does)
    var z = st.cam.s / s0, lv = z < 2.4 ? 0 : z < 26 ? 1 : 2, zk = lv * 1e6 + (z < 9.95 ? Math.round(z * 10) : 1000 + Math.round(z));
    if (zk !== capKey) {
      capKey = zk;
      capZf.textContent = '×' + (z < 9.95 ? nf1(Math.round(z * 10) / 10) : nf0(Math.round(z)));
      var lvS = ZS.lv[lv];
      if (lvS !== capLvShown) { capLvShown = lvS; capLv.textContent = lvS; capN.textContent = lv ? '' : fill(ZS.count, { swarms: nf0(W.count), agents: nf0(W.total) }); }
    }
    var k = Math.round(q);
    if (k !== kShown) {
      kShown = k; stage.setAttribute('data-k', k);
      for (var i = 0; i < ros.length; i++) { var e = ros[i], on = +e.getAttribute('data-at') === roFor(k); e.classList.toggle('on', on); if (on && cine) stage.style.setProperty('--rb', (e.offsetHeight + 30) + 'px'); }
      cv.setAttribute('aria-label', ZS.aria[k]);
    }
  }

  function frame(ts) {
    raf = 0;
    var t = ts / 1000, dt = last ? t - last : 0.016; last = t;
    // slow device: after a sustained run of long frames, draw at a lower resolution and with fewer messages
    if (dt < 0.1) { ema += (dt * 1000 - ema) * 0.05; if (ema > 24) slow++; else slow = 0; }
    if (slow > 90 && maxDpr > 1) { slow = 0; ema = 16.7; maxDpr = Math.max(1, Math.min(maxDpr, dpr) - 0.5); pulseCap = 24; layout(); }
    dt = Math.min(0.05, dt);
    var p = target();
    if (rm) q = Math.round(p);
    else { q += (p - q) * (1 - Math.exp(-dt / 0.1)); if (Math.abs(p - q) < 1e-4) q = p; }
    if (!rm) { camAt(q, st.cam); step(t, dt); }
    st.stepping = !rm; render(t); st.stepping = false;
    if (!rm && onScreen && !D.hidden) raf = requestAnimationFrame(frame);
  }
  function kick() { if (!raf && onScreen && !D.hidden) { raf = requestAnimationFrame(frame); } }

  // the scroll position that puts the reading line on camera position qq
  function scrollForQ(qq) {
    var k = Math.min(Math.floor(qq), 9), f = Math.min(1, qq - k), a = anchors[k] + (anchors[k + 1] - anchors[k]) * f;
    return a - (readLine() - scrollY);
  }
  var rt = 0, placeQ = -1, placeW = innerWidth;
  // a new width (a phone turned, a window resized) reflows the story: keep the reader on the same part of it
  function onResize() {
    if (innerWidth !== placeW && placeQ < 0 && q > 0.05 && q < 9.95) placeQ = q;
    clearTimeout(rt);
    rt = setTimeout(function () {
      layout();
      if (placeQ >= 0) { scrollTo(0, Math.max(0, scrollForQ(placeQ))); q = placeQ; }
      placeQ = -1; placeW = innerWidth;
      kick();
    }, 120);
  }
  addEventListener('resize', onResize, { passive: true });
  addEventListener('orientationchange', onResize, { passive: true });
  addEventListener('scroll', function () { if (rm || !raf) kick(); }, { passive: true });
  D.addEventListener('visibilitychange', function () { if (D.hidden) { if (raf) cancelAnimationFrame(raf); raf = 0; } else { last = 0; kick(); } });
  var onMq = function () { rm = mqR.matches; layout(); kick(); };
  [mqC, mqR].forEach(function (m) { if (m.addEventListener) m.addEventListener('change', onMq); else if (m.addListener) m.addListener(onMq); });
  if ('IntersectionObserver' in window) {
    new IntersectionObserver(function (es) { onScreen = es[es.length - 1].isIntersecting; if (onScreen) { last = 0; kick(); } }).observe(stage);
  }
  layout();
  q = target(); if (rm) q = Math.round(q);
  kick();
  if (D.fonts && D.fonts.ready) D.fonts.ready.then(function () { layout(); kick(); });
  // the fonts arrive after the first paint: measure and draw the labels again in them
  if (D.fonts && D.fonts.addEventListener) D.fonts.addEventListener('loadingdone', onResize);
  addEventListener('load', function () { layout(); kick(); });

  // for the browser checks (tests/browser): the scroll position of a keyframe, and a composed still of any keyframe
  // with the boxes of its labels and nodes
  Z.scrollFor = function (k) { return anchors[k] - (readLine() - scrollY); };
  Z.debug = function () { return { q: q, anchors: anchors, W: W, cams: cams, st: st, dpr: dpr, vw: vw, vh: vh }; };
  Z.still = function (k) {
    var rm0 = rm; hold = k; q = k; rm = true; st.audit = [];
    render(performance.now() / 1000);
    var out = st.audit; st.audit = null; rm = rm0;
    return out;
  };
  Z.release = function () { hold = -1; last = 0; kick(); };
})();
