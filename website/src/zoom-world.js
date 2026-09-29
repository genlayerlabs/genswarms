/* ===== zoom-world.js: the organization, its swarms, and the support team's story states =====
   The world is data made once per layout (seeded, so every visitor sees the same organization). */
var Z = {};
(function () {
  'use strict';
  var A = 12, OS = 22, U = 56; // agent radius, object side, agent pitch (world units)
  Z.A = A; Z.OS = OS; Z.U = U; Z.NK = 11;

  function rngf(seed) {
    return function () {
      seed |= 0; seed = seed + 0x6D2B79F5 | 0;
      var t = Math.imul(seed ^ seed >>> 15, 1 | seed);
      t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
      return ((t ^ t >>> 14) >>> 0) / 4294967296;
    };
  }
  Z.rngf = rngf;
  function oddRows(n, max) { var r = Math.round((Math.sqrt(n * 0.8) - 1) / 2) * 2 + 1; return Math.max(1, Math.min(max || 9, r)); }

  // a block of agents under one supervisor: a bus above, one line down each column (a comb)
  function block(S, x0, yc, cnt, rows) {
    var cols = Math.ceil(cnt / rows), h = (rows - 1) * U, t = yc - h / 2, bus = t - 40;
    var si = S.sup.length; S.sup.push([x0 - 34, bus]);
    S.comb.push(x0 - 28, bus, x0 + (cols - 1) * U, bus);
    var first = S.ag.length, left = -1, right = -1, rightX = -1e9, leftX = 1e9, mid = 0, bot = [];
    for (var c = 0; c < cols; c++) {
      var k = Math.min(rows, cnt - c * rows), x = x0 + c * U;
      if (k <= 0) break;
      S.comb.push(x, bus, x, t + (k - 1) * U);
      for (var r = 0; r < k; r++) {
        var y = t + r * U, i = S.ag.length;
        S.ag.push([x, y]); S.agSup.push(si); S.agCol.push([x, bus]);
        if (Math.abs(y - yc) < 1) { if (x < leftX) { leftX = x; left = i; } if (x > rightX) { rightX = x; right = i; } }
      }
      bot.push(S.ag.length - 1);
    }
    return { l: x0, r: x0 + (cols - 1) * U, t: t, b: t + h, bus: bus, left: left, right: right, first: first, last: bot[bot.length - 1] };
  }

  function pipe(S, rng, n) {
    var ng = n < 36 ? 2 : n < 70 ? 3 : 3 + (rng() < 0.5 ? 1 : 0);
    var first = Math.max(2, Math.round(n * (0.05 + rng() * 0.07)));
    var sizes = [first], rest = n - first, w = [];
    for (var g = 1; g < ng; g++) w.push(0.6 + rng());
    var ws = w.reduce(function (a, b) { return a + b; }, 0), acc = 0;
    for (g = 1; g < ng; g++) { var s = g === ng - 1 ? rest - acc : Math.max(3, Math.round(rest * w[g - 1] / ws)); sizes.push(s); acc += s; }
    var maxRows = n > 70 ? 9 : 7;
    S.ob.push([0, 0]);
    var x = 120, blocks = [];
    for (g = 0; g < ng; g++) {
      var rows = g === 0 ? (sizes[0] <= 3 ? 1 : 3) : oddRows(sizes[g], maxRows);
      var b = block(S, x, 0, sizes[g], rows);
      blocks.push(b); x = b.r + 150;
    }
    var bl = blocks[blocks.length - 1], yB = -1e9;
    blocks.forEach(function (b) { yB = Math.max(yB, b.b); });
    yB += 64;
    // declared paths: gateway -> first group -> ... -> last group -> (right object) -> back to the gateway
    var a0 = S.ag[blocks[0].left];
    S.edges.push([[OS / 2 + 3, 0], [a0[0] - A - 3, 0]]);
    for (g = 0; g < ng - 1; g++) {
      var p = S.ag[blocks[g].right], q = S.ag[blocks[g + 1].left];
      S.edges.push([[p[0] + A + 3, 0], [q[0] - A - 3, 0]]);
    }
    var pr = S.ag[bl.right];
    if (rng() < 0.55) {
      var ox = bl.r + 130; S.ob.push([ox, 0]);
      S.edges.push([[pr[0] + A + 3, 0], [ox - OS / 2 - 3, 0]]);
      S.edges.push([[ox, OS / 2 + 3], [ox, yB], [0, yB], [0, OS / 2 + 3]]);
    } else if (rng() < 0.4) {
      var lb = S.ag[bl.last];
      S.edges.push([[lb[0], lb[1] + A + 3], [lb[0], yB], [0, yB], [0, OS / 2 + 3]]);
    }
  }

  function tree(S, rng, n) {
    var k = n < 40 ? 3 : n < 75 ? 4 : 5, sizes = [], w = [], ws = 0, acc = 0;
    for (var i = 0; i < k; i++) { w.push(0.7 + rng()); ws += w[i]; }
    for (i = 0; i < k; i++) { var s = i === k - 1 ? n - acc : Math.max(3, Math.round(n * w[i] / ws)); sizes.push(s); acc += s; }
    var x = 0, blocks = [], busY = 70, t0 = 170;
    var objAt = rng() < 0.6 ? (rng() * (k + 1) | 0) : -1, objs = [];
    for (i = 0; i <= k; i++) {
      if (i === objAt) { objs.push([x + 6, busY + 70]); x += 110; }
      if (i === k) break;
      var rows = Math.min(9, Math.max(3, Math.ceil(sizes[i] / 3)));
      if (rows % 2 === 0) rows++;
      var b = block(S, x + 34, t0 + (rows - 1) * U / 2, sizes[i], rows);
      blocks.push(b); x = b.r + 110;
    }
    var xs = blocks.map(function (b) { return b.l - 34; }).concat(objs.map(function (o) { return o[0]; }));
    var xl = Math.min.apply(null, xs), xr = Math.max.apply(null, xs), rx = Math.round((xl + xr) / 2);
    S.sup.push([rx, 0]);
    S.comb.push(rx, 6, rx, busY, xl, busY, xr, busY);
    blocks.forEach(function (b) { S.comb.push(b.l - 34, busY, b.l - 34, b.bus - 6); });
    objs.forEach(function (o) { S.ob.push(o); S.comb.push(o[0], busY, o[0], o[1] - OS / 2); });
    S.root = S.sup.length - 1;
  }

  function mkSwarm(rng, n, kind) {
    var S = { kind: kind, n: n, ag: [], agSup: [], agCol: [], ob: [], sup: [], comb: [], edges: [] };
    if (kind === 'pipe') pipe(S, rng, n); else tree(S, rng, n);
    var x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9;
    function ext(x, y, r) { x0 = Math.min(x0, x - r); y0 = Math.min(y0, y - r); x1 = Math.max(x1, x + r); y1 = Math.max(y1, y + r); }
    S.ag.forEach(function (p) { ext(p[0], p[1], A); });
    S.ob.forEach(function (p) { ext(p[0], p[1], OS / 2); });
    S.sup.forEach(function (p) { ext(p[0], p[1], 6); });
    S.edges.forEach(function (e) { e.forEach(function (p) { ext(p[0], p[1], 0); }); });
    S.bx = [x0, y0, x1, y1]; S.w = x1 - x0; S.h = y1 - y0;
    return S;
  }
  Z.mkSwarm = mkSwarm;

  // ---------- the support team, in its own local frame (800 x 540), and its states per keyframe ----------
  var T = {
    tg: [140, 290], cron: [320, 90], browser: [700, 90], triage: [320, 210], research: [520, 210], answer: [320, 370], budget: [700, 370],
  };
  var sc = [[330, 205], [300, 385], [560, 150], [440, 290], [180, 140], [120, 300], [250, 460], [650, 350], [520, 450], [700, 210], [420, 110], [720, 470]];
  var gx = [250, 380, 510, 640], gy = [200, 320, 440], grid = [];
  gy.forEach(function (y) { gx.forEach(function (x) { grid.push([x, y]); }); });
  // triage, answer, research take these grid slots (slot 9 is the one that crashes)
  var slot = [1, 5, 2, 0, 3, 4, 6, 7, 8, 9, 10, 11];
  var team = [T.triage, T.answer, T.research];
  function agentsAt(k) {
    var out = [];
    for (var i = 0; i < 12; i++) {
      var p;
      if (k === 3) p = sc[i];
      else if (k === 4 || k === 5) p = grid[slot[i]];
      else p = i < 3 ? team[i] : grid[slot[i]];
      out.push(p);
    }
    return out;
  }
  var AGPOS = []; for (var k = 0; k < 11; k++) AGPOS.push(agentsAt(k));
  function on(list) { var a = []; for (var k = 0; k < 11; k++) a.push(list.indexOf(k) >= 0 ? 1 : 0); return a; }
  var TEAM = [0, 1, 2, 6, 7, 8, 9, 10];
  Z.sup = {
    T: T, sc: sc, grid: grid, gx: gx, gy: gy, AGPOS: AGPOS, slot: slot,
    bx: [100, 60, 740, 480], // footprint in the organization
    vis: {
      extra: on([3, 4, 5]),
      tg: on([0, 1, 2, 6, 7, 8, 9, 10]),
      objs: on([0, 1, 2, 7, 8, 9, 10]),
      core: on(TEAM),
      more: on([0, 1, 2, 7, 8, 9, 10]),
      names: on([0, 1, 2, 6, 7, 8, 9]),
      wires: on([3]),
      layer: on([4, 5]),
      sbx: on([5]),
      drop: on([6]),
      calls: on([7, 8]),
      seals: on([8]),
      doc: on([9]),
      ctl: on([10]),
      dim: [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1], // 1 = the whole organization at full strength
    },
    // declared paths of the team: [from, to, via, kind]  (kind: e = message path, m = model call)
    edges: [
      ['tg', 'triage', [[140, 210]], 'e', 'core'],
      ['triage', 'answer', null, 'e', 'core'],
      ['triage', 'research', null, 'e', 'core'],
      ['research', 'answer', [[520, 370]], 'e', 'core'],
      ['answer', 'tg', [[140, 370]], 'e', 'core'],
      ['cron', 'triage', null, 'e', 'more'],
      ['research', 'browser', [[520, 90]], 'e', 'more'],
      ['research', 'budget', [[700, 210]], 'm', 'more'],
      ['answer', 'budget', [[320, 450], [700, 450]], 'm', 'more'],
    ],
    labels: { triage: [304, 197, 'end'], answer: [304, 357, 'end'], research: [536, 197, 'start'], tg: [118, 295, 'end'], cron: [304, 95, 'end'], browser: [722, 95, 'start'], budget: [722, 375, 'start'] },
    names: { tg: 'telegram', cron: 'cron', browser: 'browser', budget: 'budget', triage: 'triage', answer: 'answer', research: 'research' },
    wires: [[4, 10], [10, 0], [0, 2], [2, 9], [5, 6], [6, 3], [7, 8], [8, 6], [11, 8], [9, 7], [5, 4], [3, 7], [1, 6], [4, 0], [2, 3], [10, 9], [1, 5], [11, 7], [3, 1]],
    bar: { x1: 60, x2: 740, y: 44, h: 44 },
    spine: 130, drop: 44, sandbox: 52,
    crash: 9, // grid slot that crashes (local 380, 440)
    // K6: the message research -> telegram, off the graph: [from x, y, to x, y, cross x, y]
    dropLine: (function () { var ra = T.research, tg = T.tg, dx = tg[0] - ra[0], dy = tg[1] - ra[1], n = Math.hypot(dx, dy), xm = [ra[0] + dx * 0.44, ra[1] + dy * 0.44];
      return [ra[0] + dx / n * (A + 5), ra[1] + dy / n * (A + 5), xm[0] - dx / n * 9, xm[1] - dy / n * 9, xm[0], xm[1]]; })(),
    doc: { x: 300, y: 566, w: 480, lh: 28, fs: 17 },
    db: [170, 700],
    // camera frames (local) per keyframe; K0 and K10 frame the organization
    // tight horizontal extent of the drawing at K6-K9 (its labels are fitted on top of it)
    camX: { 6: [120, 545], 7: [120, 730], 8: [120, 730], 9: [120, 790] },
    cam: [null, [-260, -120, 1100, 680], 'agent', [90, 70, 770, 500], [40, 30, 780, 480], [40, 30, 790, 480], [40, 150, 580, 420], [30, 56, 790, 480], [30, 56, 790, 480], [40, 60, 800, 990], null],
  };

  // the support team's declared paths, in world coordinates of a built organization W
  Z.teamEdges = function (W) {
    var T = Z.sup.T, rad = function (k) { return /^(tg|cron|browser|budget)$/.test(k) ? OS / 2 + 3 : A + 3; };
    function trim(p, q, d) { var dx = q[0] - p[0], dy = q[1] - p[1], n = Math.hypot(dx, dy) || 1; return [p[0] + dx / n * d, p[1] + dy / n * d]; }
    return Z.sup.edges.map(function (E) {
      var pts = [T[E[0]]].concat(E[2] || [], [T[E[1]]]);
      pts[0] = trim(pts[0], pts[1], rad(E[0])); var n = pts.length; pts[n - 1] = trim(pts[n - 1], pts[n - 2], rad(E[1]) + 1);
      pts = pts.map(function (p) { return [p[0] + W.sx, p[1] + W.sy]; });
      var cum = [0];
      for (var j = 1; j < pts.length; j++) cum.push(cum[j - 1] + Math.hypot(pts[j][0] - pts[j - 1][0], pts[j][1] - pts[j - 1][1]));
      return { from: E[0], to: E[1], kind: E[3], grp: E[4], e: { pts: pts, cum: cum, len: cum[cum.length - 1] } };
    });
  };

  // ---------- the organization ----------
  var NAMED = ['chat', 'coding', 'trading sim', 'observer'];
  Z.build = function (aspect) {
    var rng = rngf(20260929), N = 35, list = [], total = 3;
    for (var i = 0; i < N; i++) {
      var r = rng(), n = Math.round(42 + Math.pow(r, 0.5) * 58);
      var kind = rng() < 0.62 ? 'pipe' : 'tree';
      var S = mkSwarm(rng, n, kind); S.id = i; total += n;
      list.push(S);
    }
    for (i = 0; i < NAMED.length; i++) list[[3, 11, 19, 27][i]].name = NAMED[i];
    var sup = { support: true, name: 'support', bx: Z.sup.bx, w: Z.sup.bx[2] - Z.sup.bx[0], h: Z.sup.bx[3] - Z.sup.bx[1], n: 3 };
    var GX = 250, GY = 280;
    function pack(order, Wt) {
      var rows = [], row = [], rw = 0;
      order.forEach(function (S) {
        if (row.length && rw + GX + S.w > Wt) { rows.push({ it: row, w: rw }); row = []; rw = 0; }
        rw += (row.length ? GX : 0) + S.w; row.push(S);
      });
      if (row.length) rows.push({ it: row, w: rw });
      var W = Math.max.apply(null, rows.map(function (r) { return r.w; })), y = 0, pl = [];
      rows.forEach(function (r) {
        var h = Math.max.apply(null, r.it.map(function (S) { return S.h; })), x = (W - r.w) / 2;
        r.y = y; r.h = h;
        r.it.forEach(function (S) { pl.push({ S: S, x: x, y: y + (h - S.h) / 2, row: r }); x += S.w + GX; });
        y += h + GY;
      });
      return { pl: pl, W: W, H: y - GY, rows: rows };
    }
    var area = 0; list.forEach(function (S) { area += (S.w + GX) * (S.h + GY); });
    var best = null;
    for (var at = 12; at <= 24; at++) {
      var order = list.slice(0, at).concat([sup], list.slice(at));
      for (var f = 0.7; f <= 1.9; f += 0.05) {
        var P = pack(order, Math.sqrt(area * aspect) * f), ps = P.pl.filter(function (p) { return p.S.support; })[0];
        var dc = Math.hypot((ps.x + sup.w / 2) / P.W - 0.5, (ps.y + sup.h / 2) / P.H - 0.47);
        var lr = P.rows[P.rows.length - 1], fill = lr.w / P.W;
        var score = Math.abs(Math.log((P.W / P.H) / aspect)) * 1.4 + dc + (fill < 0.7 ? (0.7 - fill) * 1.5 : 0);
        if (!best || score < best.score) { best = P; best.score = score; }
      }
    }
    var W = { swarms: [], total: total, count: N + 1, rows: best.rows, w: best.W, h: best.H };
    best.pl.forEach(function (p) {
      var S = p.S, ox = p.x - S.bx[0], oy = p.y - S.bx[1];
      if (S.support) { W.sx = ox; W.sy = oy; W.supBox = [p.x, p.y, p.x + S.w, p.y + S.h]; W.supRow = p.row; return; }
      // bake world coordinates
      var o = { id: S.id, kind: S.kind, name: S.name, n: S.n, bx: [p.x, p.y, p.x + S.w, p.y + S.h], row: p.row };
      o.ag = new Float32Array(S.ag.length * 2); S.ag.forEach(function (a, i) { o.ag[2 * i] = a[0] + ox; o.ag[2 * i + 1] = a[1] + oy; });
      o.agCol = S.agCol.map(function (c) { return [c[0] + ox, c[1] + oy]; });
      o.ob = S.ob.map(function (a) { return [a[0] + ox, a[1] + oy]; });
      o.sup = S.sup.map(function (a) { return [a[0] + ox, a[1] + oy]; });
      o.comb = []; for (var i = 0; i < S.comb.length; i += 4) o.comb.push(S.comb[i] + ox, S.comb[i + 1] + oy, S.comb[i + 2] + ox, S.comb[i + 3] + oy);
      o.edges = S.edges.map(function (e) {
        var pts = e.map(function (q) { return [q[0] + ox, q[1] + oy]; }), cum = [0];
        for (var j = 1; j < pts.length; j++) cum.push(cum[j - 1] + Math.hypot(pts[j][0] - pts[j - 1][0], pts[j][1] - pts[j - 1][1]));
        return { pts: pts, cum: cum, len: cum[cum.length - 1] };
      });
      W.swarms.push(o);
    });
    W.box = [0, 0, best.W, best.H];
    return W;
  };
})();
