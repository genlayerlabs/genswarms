// The system figure. One data model -> the live (pinned) figure + static stills (two layouts).

const f = n => Math.round(n * 10) / 10;
const vis = arr => 'fx ' + arr.map(k => 'v' + k).join(' ');

// ---------- geometry per layout ----------
export const L = {
  id: 'L', w: 800, h: 640,
  s0: [400, 300, 1.9],
  sat: { model: [400, 132], prompt: [630, 300], tools: [170, 300] },
  scatter: [[400, 320], [175, 140], [330, 92], [565, 118], [700, 222], [118, 300], [252, 425], [640, 372], [522, 488], [372, 562], [150, 530], [716, 548]],
  wires: [[1, 2, 250, 60], [2, 0, 300, 230], [0, 3, 520, 250], [3, 4, 680, 120], [5, 6, 120, 420], [6, 0, 360, 420], [7, 8, 640, 470], [8, 9, 420, 470], [10, 9, 260, 600], [4, 7, 760, 300], [5, 1, 80, 200], [0, 7, 520, 380], [6, 10, 200, 470], [1, 8, 250, 330], [3, 6, 470, 300], [2, 11, 640, 300], [9, 4, 600, 560]],
  grid: { xs: [250, 350, 450, 550], ys: [300, 390, 480] },
  org: { y: 110, x1: 120, x2: 680, label: [120, 92] },
  bar: { y: 200, x1: 170, x2: 630, label: [170, 184] },
  gridLabel: [400, 548],
  diamond: [400, 200],
  ann: [
    { x: 212, y: 382, anchor: 'end', lines: ['each agent runs', 'as a process'], lx1: 216, lx2: 226, ly: 390 },
    { x: 588, y: 382, anchor: 'start', lines: ['its boundary: what', 'it can reach'], lx1: 574, lx2: 584, ly: 390 },
  ],
  team: {
    R: [36, 330], a: [[140, 330], [270, 330], [415, 330], [545, 245], [545, 415], [668, 330]], out: [760, 330], H: [668, 150],
    labels: [
      [140, 294, 'middle', ['classifier']], [270, 294, 'middle', ['account lookup']], [415, 286, 'middle', ['investigator']],
      [545, 207, 'middle', ['billing']], [545, 464, 'middle', ['technical support']], [668, 380, 'middle', ['verifier']],
    ],
    Rlabel: [36, 294, 'middle'], outLabel: [760, 294, 'middle'],
    Hlabel: [638, 146, 'end', ['human']], Hsub: [638, 168, 'end', 'attaches to the session'],
    sup: [415, 530], supLabel: [438, 535, 'start'],
    status5: [393, 382, 'end', 'crashed, restarted'],
    status6: [0, 0, 'end', ''],
    log: [40, 58],
  },
  worldTo: [130, 240], // where the team collapses to in stage 7
  bar7: { y: 100, x1: 60, x2: 740, label: [60, 80] },
  clusters: [[130, 240], [310, 240], [490, 240], [670, 240], [220, 405], [400, 405], [580, 405]],
  clusterLabelDy: 62,
  models: { y: 568, x1: 60, x2: 740, label: [60, 548], xs: [170, 250, 330, 410, 490, 570, 650, 730].slice(0, 7).map((x, i) => 175 + i * 80) },
  fs: { t: 20, ts: 16, tb: 26, log: 16 },
  ghostR: 34,
};
export const P = {
  id: 'P', w: 400, h: 660,
  s0: [200, 300, 1.7],
  sat: { model: [200, 168], prompt: [348, 300], tools: [52, 300] },
  scatter: [[200, 300], [70, 92], [190, 58], [322, 112], [352, 250], [48, 250], [108, 392], [312, 380], [252, 492], [130, 560], [40, 480], [352, 574]],
  wires: [[1, 2, 110, 20], [2, 0, 140, 180], [0, 3, 300, 220], [3, 4, 390, 150], [5, 6, 20, 330], [6, 0, 200, 380], [7, 8, 320, 460], [8, 9, 200, 470], [10, 9, 60, 560], [4, 7, 390, 320], [5, 1, 20, 150], [0, 7, 290, 300], [1, 8, 120, 300], [3, 6, 240, 250], [2, 11, 330, 400]],
  grid: { xs: [80, 160, 240, 320], ys: [300, 380, 460] },
  org: { y: 118, x1: 30, x2: 370, label: [30, 100] },
  bar: { y: 200, x1: 40, x2: 360, label: [40, 184] },
  gridLabel: [200, 522],
  diamond: [200, 200],
  ann: [
    { x: 200, y: 568, anchor: 'middle', lines: ['each agent runs as a process', 'inside its own boundary'] },
  ],
  team: {
    R: [200, 40], a: [[200, 115], [200, 190], [200, 265], [100, 350], [300, 350], [200, 435]], out: [200, 515], H: [340, 435],
    labels: [
      [230, 120, 'start', ['classifier']], [230, 195, 'start', ['account lookup']], [230, 270, 'start', ['investigator']],
      [100, 396, 'middle', ['billing']], [300, 396, 'middle', ['technical', 'support']], [168, 440, 'end', ['verifier']],
    ],
    Rlabel: [228, 45, 'start'], outLabel: [228, 520, 'start'],
    Hlabel: [340, 478, 'middle', ['human']], Hsub: null,
    sup: [46, 300], supLabel: [46, 280, 'middle'],
    status5: [180, 236, 'end', 'crashed, restarted'],
    log: [16, 588],
  },
  worldTo: [105, 142],
  bar7: { y: 42, x1: 30, x2: 370, label: [30, 24] },
  clusters: [[105, 142], [295, 142], [105, 262], [295, 262], [105, 382], [295, 382], [200, 508]],
  clusterLabelDy: 50,
  models: { y: 628, x1: 30, x2: 370, label: [30, 610], xs: [130, 180, 230, 280, 330] },
  fs: { t: 16, ts: 14.5, tb: 20, log: 14.5 },
  ghostR: 22,
};
export const LAYOUTS = [L, P];

export const TEAMS = ['Customer operations', 'Software engineering', 'Sales', 'Finance', 'Research', 'Security', 'Network operations'];
// cluster constellations in local coords
export const SHAPES = [
  { n: [[-56, 0], [-32, 0], [-8, 0], [18, -18], [18, 18], [44, 0]], e: [[0, 1], [1, 2], [2, 3], [2, 4], [3, 5], [4, 5]], h: [44, -28] },
  { n: [[-56, 0], [-28, 0], [0, 0], [28, 0], [56, 0]], e: [[0, 1], [1, 2], [2, 3], [3, 4]], arc: [28, -28] },
  { n: [[-50, 0], [0, -24], [0, 0], [0, 24], [50, 0]], e: [[0, 1], [0, 2], [0, 3], [1, 4], [2, 4], [3, 4]] },
  { n: [[-52, -16], [-22, -16], [-52, 16], [-22, 16], [14, 0], [50, 0]], e: [[0, 1], [2, 3], [1, 4], [3, 4], [4, 5]] },
  { n: [[-50, 0], [-12, -20], [-12, 20], [30, -30], [30, -8], [30, 12], [30, 30]], e: [[0, 1], [0, 2], [1, 3], [1, 4], [2, 5], [2, 6]] },
  { n: [[0, 0], [0, -28], [27, -9], [17, 23], [-17, 23], [-27, -9]], e: [[0, 1], [0, 2], [0, 3], [0, 4], [0, 5], [1, 2], [2, 3], [3, 4], [4, 5], [5, 1]] },
  { n: [[-44, -15], [0, -15], [44, -15], [-44, 15], [0, 15], [44, 15]], e: [[0, 1], [1, 2], [3, 4], [4, 5], [0, 3], [1, 4], [2, 5], [0, 4], [4, 2]] },
];

// ---------- agent positions per stage ----------
export function agentPos(Lo) {
  const st = [];
  const [cx, cy, cs] = Lo.s0;
  st[0] = Lo.scatter.map((_, i) => (i === 0 ? [cx, cy, cs] : [cx, cy, 0.3]));
  st[1] = Lo.scatter.map(([x, y]) => [x, y, 1]);
  const g = [];
  for (const y of Lo.grid.ys) for (const x of Lo.grid.xs) g.push([x, y, 1]);
  st[2] = g; st[3] = g;
  const t = g.map((p, i) => (i < 6 ? [...Lo.team.a[i], 1] : p));
  st[4] = t; st[5] = t; st[6] = t; st[7] = t; st[8] = t;
  return st;
}
const AGENT_VIS = i => (i === 0 ? [0, 1, 2, 3, 4, 5, 6, 7, 8] : i < 6 ? [1, 2, 3, 4, 5, 6] : [1, 2, 3]);

// ---------- helpers ----------
function shorten(x1, y1, x2, y2, r1, r2) {
  const dx = x2 - x1, dy = y2 - y1, d = Math.hypot(dx, dy);
  const ux = dx / d, uy = dy / d;
  return [x1 + ux * r1, y1 + uy * r1, x2 - ux * r2, y2 - uy * r2, ux, uy];
}
function edge(a, b, r1, r2, cls = 'e', head = true) {
  const [x1, y1, x2, y2, ux, uy] = shorten(a[0], a[1], b[0], b[1], r1, r2);
  let s = `<line class="${cls}" x1="${f(x1)}" y1="${f(y1)}" x2="${f(x2)}" y2="${f(y2)}"/>`;
  if (head) {
    const hl = 9, hw = 4.5;
    const bx = x2 - ux * hl, by = y2 - uy * hl;
    s += `<path class="${cls}-h" d="M${f(x2)} ${f(y2)}L${f(bx - uy * hw)} ${f(by + ux * hw)}L${f(bx + uy * hw)} ${f(by - ux * hw)}Z"/>`;
  }
  return s;
}
const hex = (x, y, r) => {
  let d = '';
  for (let i = 0; i < 6; i++) { const a = Math.PI / 6 + i * Math.PI / 3; d += (i ? 'L' : 'M') + f(x + r * Math.cos(a)) + ' ' + f(y + r * Math.sin(a)); }
  return `<path class="hex" d="${d}Z"/>`;
};
const text = (x, y, s, cls = 't', anchor = 'start') => `<text class="${cls}" x="${f(x)}" y="${f(y)}" text-anchor="${anchor}">${s}</text>`;
const diamond = (x, y, r = 11) => `<path class="dia" d="M${x} ${y - r}L${x + r} ${y}L${x} ${y + r}L${x - r} ${y}Z"/>`;
const person = (x, y, cls = 'hum') => `<g class="${cls}" transform="translate(${x} ${y})"><circle class="hum-o" r="19"/><circle class="hum-g" cy="-5" r="5"/><path class="hum-g" d="M-9 11a9 8 0 0 1 18 0Z"/></g>`;

const bandH = Lo => (Lo.id === 'L' ? 19 : 16);
function band(Lo, b, right) {
  const h = bandH(Lo);
  let o = `<rect class="layer" x="${b.x1}" y="${b.y - h}" width="${b.x2 - b.x1}" height="${2 * h}" rx="${h}"/>`;
  o += text(b.x1 + 20, b.y + (Lo.id === 'L' ? 9 : 7), 'GenSwarms', 'tb bandl');
  if (right) o += text(b.x2 - 18, b.y + (Lo.id === 'L' ? 5.5 : 5), right, 'ts bandr', 'end');
  return o;
}
// ---------- the system SVG ----------
export function system(Lo, stage, { extraClass = '', label = '', crop = null, prune = false } = {}) {
  const T = Lo.team, A = T.a, live = /\blive\b/.test(extraClass);
  const grp = (stages, inner, extra = '') =>
    prune && !stages.includes(stage) ? '' : `<g class="${vis(stages)}${extra ? ' ' + extra : ''}">${inner}</g>`;
  let s = '';
  // --- stage 7/8: organisation (outside the world group)
  s += `<g class="org">`;
  const b7 = Lo.bar7;
  // connectors from control layer to clusters
  let con = '';
  if (Lo.id === 'L') {
    Lo.clusters.forEach(([x, y]) => { con += `<line class="drop" x1="${x}" y1="${b7.y + bandH(Lo)}" x2="${x}" y2="${y - 38}"/>`; });
  } else {
    const last = Lo.clusters[6];
    con += `<line class="drop" x1="200" y1="${b7.y + bandH(Lo)}" x2="200" y2="${last[1] - 30}"/>`;
    Lo.clusters.slice(0, 6).forEach(([x, y]) => { con += `<line class="drop" x1="200" y1="${y}" x2="${x < 200 ? x + 68 : x - 68}" y2="${y}"/>`; });
  }
  s += grp([7, 8], con + band(Lo, b7, 'control layer'));
  Lo.clusters.forEach(([cx, cy], k) => {
    if (prune && !([7, 8].includes(stage))) return;
    const sh = SHAPES[k];
    let c = '';
    sh.e.forEach(([i, j]) => { const a = sh.n[i], b = sh.n[j]; c += `<line class="ce" x1="${cx + a[0]}" y1="${cy + a[1]}" x2="${cx + b[0]}" y2="${cy + b[1]}"/>`; });
    if (sh.arc) c += `<path class="ce" d="M${cx + sh.arc[0]} ${cy - 6}Q${cx} ${cy - 34} ${cx + sh.arc[1]} ${cy - 6}"/>`;
    sh.n.forEach(([x, y]) => { c += `<circle class="cn" cx="${cx + x}" cy="${cy + y}" r="5"/>`; });
    if (sh.h) c += `<line class="ce esc" x1="${cx + 44}" y1="${cy - 6}" x2="${cx + sh.h[0]}" y2="${cy + sh.h[1] + 5}"/><circle class="ch" cx="${cx + sh.h[0]}" cy="${cy + sh.h[1]}" r="5"/>`;
    const cls = 'ts cl' + (k === 0 ? ' first' : ''), ly = cy + Lo.clusterLabelDy, two = live && TEAMS[k].includes(' ');
    c += text(cx, ly, TEAMS[k], cls + (two ? ' clw' : ''), 'middle');
    // two-line variant, shown where the live figure renders small and its labels step up
    if (two) c += text(cx, ly, TEAMS[k].split(' ').map((w, i) => `<tspan x="${cx}" dy="${i ? '1.15em' : 0}">${w}</tspan>`).join(''), cls + ' cln', 'middle');
    s += grp([7, 8], c, `cl${k}`);
  });
  // models row
  const m = Lo.models;
  let mr = `<line class="mline" x1="${m.x1}" y1="${m.y}" x2="${m.x2}" y2="${m.y}"/>`;
  m.xs.forEach(x => { mr += hex(x, m.y, 9); });
  mr += text(m.label[0], m.label[1], 'Models', 'tb tm');
  s += grp([8], mr);
  s += `</g>`;

  // --- the world group
  s += `<g class="world">`;
  const pos = agentPos(Lo);
  // stage 1: hand-made wires between scattered agents
  let w = '';
  Lo.wires.forEach(([i, j, qx, qy]) => { const a = Lo.scatter[i], b = Lo.scatter[j]; w += `<path class="wire" d="M${a[0]} ${a[1]}Q${qx} ${qy} ${b[0]} ${b[1]}"/>`; });
  const stubs = [[-24, -22], [26, -18], [-28, 12], [22, 24], [-20, 26], [28, -4]];
  Lo.scatter.forEach(([x, y], i) => { const [dx, dy] = stubs[i % stubs.length]; w += `<line class="sat" x1="${x}" y1="${y}" x2="${x + dx * .72}" y2="${y + dy * .72}"/>` + hex(x + dx, y + dy, 6); });
  s += grp([1], w);

  // stage 2/3: organisation line, coordination bar, column connectors
  const o = Lo.org, br = Lo.bar;
  let g2 = `<line class="orgline" x1="${o.x1}" y1="${o.y}" x2="${o.x2}" y2="${o.y}"/>`;
  const sq = Lo.id === 'L' ? [175, 262, 350, 450, 538, 625] : [60, 116, 172, 228, 284, 340];
  const bh = bandH(Lo);
  sq.forEach(x => { g2 += `<rect class="dept" x="${x - 6}" y="${o.y - 6}" width="12" height="12" rx="2"/><line class="drop" x1="${x}" y1="${o.y + 6}" x2="${x}" y2="${br.y - bh}"/>`; });
  g2 += text(o.label[0], o.label[1], 'the organization', 'ts');
  Lo.grid.xs.forEach(x => { g2 += `<line class="col" x1="${x}" y1="${br.y + bh}" x2="${x}" y2="${Lo.grid.ys[2]}"/>`; });
  s += grp([2, 3], g2 + band(Lo, br, null));
  const bandR = (s, c = 'ts bandr') => text(br.x2 - 18, br.y + (Lo.id === 'L' ? 5.5 : 5), s, c, 'end');
  s += grp([2], text(Lo.gridLabel[0], Lo.gridLabel[1], 'individual agents', 'ts', 'middle') + bandR('coordination layer'));
  // stage 3: supervisor + annotations
  // the diamond sits after the word, so it never depends on the label's rendered width
  let g3 = `<path class="dia-in" d="${(() => { const x = br.x2 - 22, y = br.y, r = 6; return `M${x} ${y - r}L${x + r} ${y}L${x} ${y + r}L${x - r} ${y}Z`; })()}"/>` + text(br.x2 - 36, br.y + (Lo.id === 'L' ? 5.5 : 5), 'supervisor', 'ts bandr', 'end');
  Lo.ann.forEach(a => {
    a.lines.forEach((ln, i) => { g3 += text(a.x, a.y + i * (Lo.fs.ts + 5), ln, 'ts ann', a.anchor); });
    if (a.lx1) g3 += `<line class="lead" x1="${a.lx1}" y1="${a.ly - 8}" x2="${a.lx2}" y2="${a.ly - 8}"/>`;
  });
  s += grp([3], g3);

  // stage 0: satellites
  const [cx, cy] = Lo.s0;
  const gd = Lo.ghostR * 0.42;
  let g0 = Lo.clusters.map(([x, y]) => `<circle class="org-ghost" cx="${x}" cy="${y}" r="${Lo.ghostR}"/><path class="org-ghost-m" d="M${f(x - gd)} ${f(y + gd * .6)}h0M${x} ${f(y - gd * .8)}h0M${f(x + gd)} ${f(y + gd * .6)}h0"/>`).join('');
  g0 += `<circle class="halo" cx="${cx}" cy="${cy}" r="${Lo.id === 'L' ? 62 : 52}"/>`;
  const glyph = {
    model: (x, y) => hex(x, y, 12),
    prompt: (x, y) => `<rect class="glyph" x="${x - 13}" y="${y - 10}" width="26" height="20" rx="3"/><line class="glyph" x1="${x - 7}" y1="${y - 3}" x2="${x + 7}" y2="${y - 3}"/><line class="glyph" x1="${x - 7}" y1="${y + 3}" x2="${x + 3}" y2="${y + 3}"/>`,
    tools: (x, y) => `<rect class="glyph" x="${x - 11}" y="${y - 11}" width="22" height="22" rx="3"/><rect class="glyph" x="${x - 4}" y="${y - 4}" width="8" height="8" rx="1"/>`,
  };
  for (const [k, [x, y]] of Object.entries(Lo.sat)) {
    const [x1, y1, x2, y2] = shorten(cx, cy, x, y, Lo.id === 'L' ? 66 : 56, 20);
    g0 += `<line class="sat" x1="${f(x1)}" y1="${f(y1)}" x2="${f(x2)}" y2="${f(y2)}"/>` + glyph[k](x, y);
    g0 += text(x, y < cy ? y - 24 : y + 38, k, 't', 'middle');
  }
  s += grp([0], g0);

  // stages 4-6: the team topology
  const R = T.R, O = T.out, H = T.H;
  let e = '';
  e += edge(R, A[0], 20, 22) + edge(A[0], A[1], 22, 22) + edge(A[1], A[2], 22, 22) + edge(A[2], A[3], 22, 22) + edge(A[2], A[4], 22, 22) + edge(A[3], A[5], 22, 22) + edge(A[4], A[5], 22, 22) + edge(A[5], O, 22, 20);
  e += edge(A[5], H, 22, 24, 'e esc');
  e += `<rect class="io" x="${R[0] - 17}" y="${R[1] - 12}" width="34" height="24" rx="4"/><path class="io-g" d="M${R[0] - 17} ${R[1] - 10}L${R[0]} ${R[1] + 2}L${R[0] + 17} ${R[1] - 10}"/>`;
  e += `<rect class="io" x="${O[0] - 17}" y="${O[1] - 12}" width="34" height="24" rx="4"/><path class="io-g" d="M${O[0] - 7} ${O[1]}L${O[0] - 2} ${O[1] + 5}L${O[0] + 8} ${O[1] - 6}"/>`;
  e += text(T.Rlabel[0], T.Rlabel[1], 'request', 't', T.Rlabel[2]) + text(T.outLabel[0], T.outLabel[1], 'reply', 't', T.outLabel[2]);
  e += person(H[0], H[1]);
  e += text(T.Hlabel[0], T.Hlabel[1], 'human', 't', T.Hlabel[2]);
  if (T.Hsub) e += grp([6], text(T.Hsub[0], T.Hsub[1], T.Hsub[3], 'ts', T.Hsub[2]));
  s += grp([4, 5, 6], e);
  // stage 6: escalation highlight
  s += grp([6], edge(A[5], H, 22, 24, 'eh') + `<circle class="block" cx="${A[5][0]}" cy="${A[5][1]}" r="24"/>`, 'escal');
  // stage 5: supervisor, crash marks
  const [sx, sy] = T.sup;
  const [lx1, ly1, lx2, ly2] = shorten(sx, sy, A[2][0], A[2][1], 12, 26);
  let g5 = `<line class="supline" pathLength="1" x1="${f(lx1)}" y1="${f(ly1)}" x2="${f(lx2)}" y2="${f(ly2)}"/>` + diamond(sx, sy) + text(T.supLabel[0], T.supLabel[1], 'supervisor', 'ts', T.supLabel[2]);
  g5 += `<g transform="translate(${A[2][0]} ${A[2][1]})"><circle class="burst" r="30"/><circle class="restart" r="23"/></g>`;
  g5 += text(T.status5[0], T.status5[1], T.status5[3], 'ts st', T.status5[2]);
  s += grp([5], g5);
  // event log (illustration)
  const [gx, gy] = T.log, lh = Math.round(Lo.fs.log * 1.5);
  const log5 = [['message', 'account_lookup → investigator'], ['crash', 'investigator'], ['restart', 'investigator'], ['message', 'investigator → technical_support']];
  const log6 = [['message', 'billing → verifier'], ['agent_blocked', 'verifier, waiting on human input'], ['output', 'verifier → reply']];
  const logBlock = (rows, k) => {
    let b = text(gx, gy, 'event stream (illustration)', 'ts logcap');
    // wrap a row's text at the figure edge (phones), continuing under the text column
    const cols = Math.floor((Lo.w - 2 * gx) / (Lo.fs.log * 0.6)) - k;
    let y = gy + lh;
    rows.forEach(([kind, rest]) => {
      // too long for one line: break at the space nearest the middle (two balanced lines)
      const mid = rest.length / 2, sp = [...rest.matchAll(/ /g)].map(m => m.index).sort((a, b) => Math.abs(a - mid) - Math.abs(b - mid))[0];
      const parts = rest.length > cols && sp ? [rest.slice(0, sp), rest.slice(sp + 1)] : [rest];
      parts.forEach((ln, j) => {
        b += `<text class="log" x="${gx}" y="${y}">${j ? ' '.repeat(k) : `<tspan class="k-${kind}">${kind.padEnd(k)}</tspan>`}${ln}</text>`;
        y += lh;
      });
    });
    return b;
  };
  s += grp([5], logBlock(log5, 9)) + grp([6], logBlock(log6.slice(0, Lo.id === 'L' ? 3 : 2), 14));

  // agents
  pos[0].forEach((_, i) => {
    if (prune && !AGENT_VIS(i).includes(stage)) return;
    const lab = i < 6 ? T.labels[i] : null;
    let a = `<g class="ag a${i} ${vis(AGENT_VIS(i))}" style="--i:${i}">`;
    a += (prune && !([3, 4, 5, 6].includes(stage))) ? '' : `<rect class="bnd ${vis([3, 4, 5, 6])}" x="-25" y="-25" width="50" height="50" rx="12"/>`;
    a += `<circle class="ring" r="16"/><circle class="core" r="10"/>`;
    if (lab) {
      const [x, y, anc, lines] = lab;
      const rel = lines.map((ln, k) => text(x - A[i][0], y - A[i][1] + k * (Lo.fs.t + 2), ln, 't', anc)).join('');
      a += grp([4, 5, 6], rel);
    }
    a += `</g>`;
    s += a;
  });
  // token
  s += (prune && !([4, 5, 6].includes(stage))) ? '' : `<g class="tok ${vis([4, 5, 6])}"><circle r="7.5"/></g>`;
  s += `</g>`; // world

  // the live figure keeps one viewBox for every stage; a camera group recentres each drawing (figureCSS)
  if (live) s = `<g class="cam">${s}</g>`;
  return `<svg class="sys ${Lo.id}${extraClass ? ' ' + extraClass : ''}" data-s="${stage}" viewBox="${crop || `0 0 ${Lo.w} ${Lo.h}`}" role="img" aria-label="${label}">${s}</svg>`;
}

// ---------- CSS generated from the model ----------
// liveCrops: the per-stage content boxes of the L layout ('x y w h'); the live camera centres each one
export function figureCSS(liveCrops = []) {
  let c = '';
  liveCrops.forEach((box, k) => {
    const [, y, , h] = box.split(' ').map(Number);
    c += `.live[data-s="${k}"] .cam{transform:translateY(${f(L.h / 2 - (y + h / 2))}px)}`;
  });
  for (let k = 0; k <= 8; k++) c += `.sys[data-s="${k}"] .v${k}{opacity:1;visibility:visible}`;
  // live morphs: arrivals wait for the agents to move; departures fade at once
  c += [...Array(9).keys()].map(k => `.live[data-s="${k}"] .v${k}:not(.ag)`).join(',') + '{transition-delay:.35s}';
  c += '\n';
  for (const Lo of LAYOUTS) {
    // one rule per distinct agent position, listing every stage that uses it. The live figure (L)
    // needs every stage, so agents keep moving while they fade; phone stills only their own stages.
    const pos = agentPos(Lo), rules = new Map();
    for (let k = 0; k <= 8; k++) {
      pos[k].forEach(([x, y, s], i) => {
        if (Lo.id === 'P' && !AGENT_VIS(i).includes(k)) return;
        const d = `transform:translate(${x}px,${y}px)${s !== 1 ? ` scale(${s})` : ''}`;
        rules.set(d, [...(rules.get(d) || []), `.${Lo.id}[data-s="${k}"] .a${i}`]);
      });
    }
    for (const [d, sel] of rules) c += `${sel.join(',')}{${d}}`;
    const [tx, ty] = Lo.worldTo, sc = 0.2;
    const wc = Lo.id === 'L' ? [415, 330] : [200, 290];
    c += `.${Lo.id}[data-s="7"] .world,.${Lo.id}[data-s="8"] .world{transform:translate(${f(tx - wc[0] * sc)}px,${f(ty - wc[1] * sc)}px) scale(${sc});opacity:0}`;
    c += `.${Lo.id} .t{font-size:${Lo.fs.t}px}.${Lo.id} .ts{font-size:${Lo.fs.ts}px}.${Lo.id} .tb{font-size:${Lo.fs.tb}px}.${Lo.id} .log{font-size:${Lo.fs.log}px}`;
    // token: static positions, then animated routes
    const T = Lo.team, A = T.a, R = T.R, O = T.out, H = T.H;
    const mid = (p, q, t = 0.5) => [p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t];
    const tp = p => `transform:translate(${f(p[0])}px,${f(p[1])}px)`;
    c += `.${Lo.id}[data-s="4"] .tok{${tp(mid(A[1], A[2]))}}.${Lo.id}[data-s="5"] .tok{${tp(mid(A[2], A[4], 0.55))}}.${Lo.id}[data-s="6"] .tok{${tp(mid(A[5], H, 0.5))}}`;
    c += `.${Lo.id}[data-s="7"] .tok,.${Lo.id}[data-s="8"] .tok,.${Lo.id}[data-s="3"] .tok{${tp(A[2])}}`;
    c += '\n@media (prefers-reduced-motion:no-preference){';
    // route helper: list of [point, pct, opacity]
    const kf = (name, frames) => `@keyframes ${name}{` + frames.map(([p, pct, op]) => `${pct}%{${tp(p)};opacity:${op}}`).join('') + '}';
    c += kf(`t4${Lo.id}`, [[R, 0, 0], [R, 4, 1], [A[0], 16, 1], [A[1], 30, 1], [A[2], 44, 1], [A[3], 58, 1], [A[5], 72, 1], [O, 86, 1], [O, 94, 0], [O, 100, 0]]);
    c += kf(`t5${Lo.id}`, [[R, 0, 0], [R, 3, 1], [A[0], 12, 1], [A[1], 22, 1], [A[2], 32, 1], [A[2], 34, 0], [A[2], 66, 0], [A[2], 68, 1], [A[4], 78, 1], [A[5], 88, 1], [O, 95, 1], [O, 100, 0]]);
    c += kf(`t6${Lo.id}`, [[A[2], 0, 0], [A[2], 4, 1], [A[3], 18, 1], [A[5], 32, 1], [A[5], 46, 1], [H, 64, 1], [H, 96, 1], [H, 100, 0]]);
    c += `.${Lo.id}[data-s="4"] .tok{animation:t4${Lo.id} 6.4s linear infinite}.${Lo.id}[data-s="5"] .tok{animation:t5${Lo.id} 7.2s linear infinite}.${Lo.id}[data-s="6"] .tok{animation:t6${Lo.id} 6.4s linear infinite}`;
    c += '}\n';
  }
  return c;
}
