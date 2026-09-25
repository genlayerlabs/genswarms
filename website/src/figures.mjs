// The system figure. One data model -> the live (pinned) figure + static stills (two layouts).
import { t, tf, fill, escText } from './i18n.mjs';

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
  ann: [
    { x: 212, y: 382, anchor: 'end', lines: ['each agent runs', 'as a process'], lx1: 216, lx2: 226, ly: 390, room: [8, 212] },
    { x: 588, y: 382, anchor: 'start', lines: ['its boundary: what', 'it can reach'], lx1: 574, lx2: 584, ly: 390, room: [588, 792] },
  ],
  // stage 3: the agent that crashes and restarts (index into the grid) and its status line
  crash: { i: 10, st: [450, 534, 'middle'] },
  // stages 4-7: one support swarm. Agents a0-a2; objects are squares.
  team: {
    a: [[330, 235], [330, 425], [560, 330]], // triage, answer, research
    tg: [140, 330], cron: [330, 105], budget: [730, 470], browser: [730, 330],
    labels: [[362, 228, 'start'], [330, 478, 'middle'], [560, 290, 'middle']],
    olabels: { tg: [112, 337, 'end'], cron: [298, 111, 'end'], budget: [730, 516, 'middle'], browser: [730, 290, 'middle'] },
    callsLabel: [600, 437, 'middle'], // "model calls", on the dotted lines to budget (L only)
    drop: [445, 330], dropLabel: [430, 336, 'end'],
    log: [40, 518], legend: [40, 530], index: [40, 522],
    doc: { x: 100, y: 118, w: 600, cols: 58 },
  },
  worldTo: [400, 330], worldC: [435, 290], // stages 7-8: the swarm folds away into the document
  bar7: { y: 100, x1: 60, x2: 740, label: [60, 80] },
  clusters: [[130, 240], [310, 240], [490, 240], [670, 240], [220, 405], [400, 405], [580, 405]],
  swarmsLabel: [60, 498],
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
  ann: [
    { x: 200, y: 568, anchor: 'middle', lines: ['each agent runs as a process', 'inside its own boundary'], room: [16, 384] },
  ],
  crash: { i: 10, st: [240, 512, 'middle'] },
  team: {
    a: [[80, 175], [320, 175], [200, 370]],
    tg: [200, 50], cron: [80, 55], budget: [200, 270], browser: [330, 370],
    labels: [[100, 234, 'end'], [300, 234, 'start'], [200, 422, 'middle']],
    olabels: { tg: [200, 100, 'middle'], cron: [104, 61, 'start'], budget: [200, 240, 'middle'], browser: [330, 422, 'middle'] },
    drop: [200, 296], dropLabel: [200, 268, 'middle'],
    log: [16, 474], legend: [24, 476], index: [16, 470],
    doc: { x: 16, y: 24, w: 368, cols: 37 },
  },
  worldTo: [200, 300], worldC: [200, 200],
  bar7: { y: 42, x1: 30, x2: 370, label: [30, 24] },
  clusters: [[105, 142], [295, 142], [105, 262], [295, 262], [105, 382], [295, 382], [200, 508]],
  swarms: [[105, 150], [295, 150], [105, 250], [295, 250], [105, 350], [295, 350], [200, 450]], swarmsLabel: [30, 100],
  models: { y: 548, x1: 30, x2: 370, label: [30, 530], xs: [130, 180, 230, 280, 330] },
  fs: { t: 16, ts: 15.5, tb: 20, log: 15 },
  ghostR: 22,
};
export const LAYOUTS = [L, P];

// stage 8: swarm constellations in local coords (shapes only, unnamed)
export const SHAPES = [
  { n: [[-56, 0], [-32, 0], [-8, 0], [18, -18], [18, 18], [44, 0]], e: [[0, 1], [1, 2], [2, 3], [2, 4], [3, 5], [4, 5]] },
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
  const t = g.map((p, i) => (i < 3 ? [...Lo.team.a[i], 1] : p));
  st[4] = t; st[5] = t; st[6] = t; st[7] = t; st[8] = t;
  return st;
}
// the three swarm agents stay from stage 1 to 7; the rest of the grid leaves after stage 3
const AGENT_VIS = i => (i === 0 ? [0, 1, 2, 3, 4, 5, 6, 7, 8] : i < 3 ? [1, 2, 3, 4, 5, 6, 7] : [1, 2, 3]);
const AGENT_NAMES = ['triage', 'answer', 'research'];
// objects of the swarm: name, first stage, its swarmidx package (stage 6; digests are shortened
// placeholders, drawn as an illustration)
const OBJECTS = [
  ['tg', 'telegram', 4, 'genlayerlabs/genswarms-telegram@0.6.6', 'sha256:9f2c…'],
  ['cron', 'cron', 5, 'genlayerlabs/cron@0.2.8', 'sha256:4be1…'],
  ['budget', 'budget', 5, 'genlayerlabs/genswarms-llm-proxy@0.4.2', 'sha256:c07a…'],
  ['browser', 'browser', 5, 'genlayerlabs/browser@0.2.4', 'sha256:51d3…'],
];
const range = (a, b) => Array.from({ length: b - a + 1 }, (_, i) => a + i);

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

// ---------- translated labels ----------
// Han, kana and fullwidth forms break anywhere and are ~1em wide; Hangul is ~0.8em and breaks at spaces.
const HAN = /[\u2e80-\u2fff\u3000-\u30ff\u3400-\u9fff\uf900-\ufaff\uff00-\uffef]/;
const HANGUL = /[\u1100-\u11ff\u3130-\u318f\uac00-\ud7af]/;
// estimated advance of s in em, rounded up from measurements of Instrument Sans, Bricolage Grotesque, JetBrains Mono
// and the Russian, Korean and Chinese system faces the translated pages use
export function em(s, { mono = false, bold = false } = {}) {
  let w = 0;
  for (const ch of s) {
    if (HAN.test(ch)) w += 1.02;
    else if (HANGUL.test(ch)) w += mono ? 0.86 : 0.8;
    else if (mono) w += 0.6;
    else if (/\s/.test(ch)) w += 0.25;
    else if (/[A-Z\u0400-\u042f]/.test(ch)) w += 0.76;
    else if (/[0-9]/.test(ch)) w += 0.6;
    else if (/[\u0430-\u045f]/.test(ch)) w += 0.58;
    else if (/[.,:;'’()!|/-]/.test(ch)) w += 0.34;
    else w += 0.55;
  }
  return bold ? w * 1.09 : w;
}
// monospaced columns: CJK characters take two
const cols = s => [...s].reduce((n, ch) => n + (HAN.test(ch) || HANGUL.test(ch) ? 2 : 1), 0);
// greedy line breaking at spaces and between Han characters (closing punctuation stays with its character)
export function breakLines(s, maxW, width) {
  const toks = [];
  s.split(' ').forEach((w, i) => {
    const parts = w.match(/[\u2e80-\u2fff\u3400-\u9fff\uf900-\ufaff][\u3001\u3002\uff0c\uff1a\uff1b\uff01\uff1f\u300d\u300f\uff09]*|[^\u2e80-\u2fff\u3400-\u9fff\uf900-\ufaff]+/g) || [''];
    parts.forEach((p, j) => toks.push([p, j ? '' : i ? ' ' : '']));
  });
  const lines = [];
  let cur = '';
  for (const [p, glue] of toks) {
    const next = cur ? cur + glue + p : p;
    if (cur && width(next) > maxW) { lines.push(cur); cur = p; } else cur = next;
  }
  lines.push(cur);
  return lines;
}
const SIZE = cls => cls.split(' ').find(c => c === 't' || c === 'ts' || c === 'tb' || c === 'log');
// the live figure (L) steps .ts and .log labels up to 18.5px on narrow and short screens (page.css): fit to that
const fsOf = (Lo, cls) => { const k = SIZE(cls), v = Lo.fs[k]; return Lo.id === 'L' && (k === 'ts' || k === 'log') ? Math.max(v, 18.5) : v; };
const BOUNDS = { L: [8, 792], P: [16, 384] };
// where a translated label grew below its drawing (per stage), so a still's crop can grow with it
let grown = [];
// A label drawn in a figure. English renders exactly as designed. A translation gets the room [lo, hi] (SVG units):
// it slides inward to fit, then wraps (up to `lines`, downward, or upward with up: true), and only then steps its
// font down (to 82%). The catalogue's `max` is that room in Latin characters (CJK characters count about double).
function tlabel(Lo, x, y, en, where, { cls = 't', anchor = 'start', room = BOUNDS[Lo.id], lines = 1, up = false, vars = null, st = [], english = null, max = null } = {}) {
  const fs = fsOf(Lo, cls), [lo, hi] = room, bold = SIZE(cls) === 'tb', mono = SIZE(cls) === 'log';
  const tr = t(en, where, { kind: 'svg', max: max ?? Math.floor((hi - lo) / (fs * (mono ? 0.6 : 0.55))), lines });
  const s = vars ? fill(tr, vars) : tr;
  if (tr === en) return english ? english() : text(x, y, vars ? fill(en, vars) : en, cls, anchor);
  let k = 1, ls;
  for (k of [1, 0.94, 0.88, 0.82]) {
    const width = u => em(u, { mono, bold }) * fs * k;
    ls = breakLines(s, hi - lo, width);
    if (ls.length <= lines && Math.max(...ls.map(width)) <= hi - lo) break;
  }
  // still too long at the smallest step: keep to the lines allowed and let it overflow (the audit reports it)
  if (ls.length > lines) ls = [...ls.slice(0, lines - 1), ls.slice(lines - 1).reduce((a, b) => (HAN.test(a.slice(-1)) && HAN.test(b[0]) ? a + b : a + ' ' + b))];
  const w = Math.max(...ls.map(u => em(u, { mono, bold }) * fs * k));
  const clamp = (v, a, b) => Math.min(Math.max(v, a), Math.max(a, b));
  const ax = anchor === 'middle' ? clamp(x, lo + w / 2, hi - w / 2) : anchor === 'end' ? clamp(x, lo + w, hi) : clamp(x, lo, hi - w);
  const lh = Math.round(fs * k * 1.3), y0 = up ? y - (ls.length - 1) * lh : y;
  const style = k < 1 ? ` style="font-size:${f(fs * k)}px"` : '';
  if (!up && ls.length > 1) grown.push([y0 + (ls.length - 1) * lh + fs * 0.35, st]);
  return ls.map((u, i) => `<text class="${cls}" x="${f(ax)}" y="${f(y0 + i * lh)}" text-anchor="${anchor}"${style}>${escText(u)}</text>`).join('');
}
// an object: a square with a square core (agents are circles)
const obj = (x, y, r = 15) => `<rect class="ob" x="${x - r}" y="${y - r}" width="${2 * r}" height="${2 * r}" rx="3"/><rect class="ob-c" x="${x - 5}" y="${y - 5}" width="10" height="10" rx="1"/>`;
const agentGlyph = (x, y) => `<circle class="lg-r" cx="${x}" cy="${y}" r="11"/><circle class="lg-c" cx="${x}" cy="${y}" r="6.5"/>`;
// verified: a sage disc with a check
const okBadge = (x, y) => `<circle class="okb" cx="${x}" cy="${y}" r="8.5"/><path class="okc" d="M${x - 4} ${y}l2.8 2.8l5-5.2"/>`;
const noBadge = (x, y) => `<circle class="nob" cx="${x}" cy="${y}" r="8.5"/><path class="okc" d="M${x - 3.2} ${y - 3.2}l6.4 6.4m0 -6.4l-6.4 6.4"/>`;
const cyl = (x, y, w = 26, h = 26) => { const ry = 5; return `<path class="db" d="M${x} ${y + ry}v${h - 2 * ry}a${w / 2} ${ry} 0 0 0 ${w} 0v${-(h - 2 * ry)}"/><ellipse class="db" cx="${x + w / 2}" cy="${y + ry}" rx="${w / 2}" ry="${ry}"/><path class="db" fill="none" d="M${x} ${y + h / 2}a${w / 2} ${ry} 0 0 0 ${w} 0"/>`; };
// monospaced rows: [kind, rest, kindClass, restClass, [tail, tailClass]]. The kind is padded to `pad` columns; a
// rest too long for `width` columns wraps (at spaces, or between Han characters) and continues under the rest column.
function monoRows(x, y, lh, rows, pad, width) {
  let b = '';
  rows.forEach(([kind, rest, kc, rc, tail]) => {
    const lines = breakLines(rest, width - pad, cols);
    lines.forEach((ln, j) => {
      const k = j ? ' '.repeat(pad) : kind ? `<tspan class="${kc || 'k-' + kind}">${kind.padEnd(pad)}</tspan>` : ' '.repeat(pad);
      const end = tail && j === lines.length - 1 ? `<tspan class="${tail[1]}">${tail[0]}</tspan>` : '';
      b += `<text class="log" x="${x}" y="${f(y)}">${k}${ln ? `<tspan${rc ? ` class="${rc}"` : ''}>${escText(ln)}</tspan>` : ''}${end}</text>`;
      y += lh;
    });
  });
  return [b, y];
}

const bandH = Lo => (Lo.id === 'L' ? 19 : 16);
// the room right of the "GenSwarms" wordmark in a band, for a label that ends at x
const bandRoom = (Lo, b, x) => [b.x1 + 20 + em('GenSwarms', { bold: true }) * Lo.fs.tb + 14, x];
function band(Lo, b, right) {
  const h = bandH(Lo);
  let o = `<rect class="layer" x="${b.x1}" y="${b.y - h}" width="${b.x2 - b.x1}" height="${2 * h}" rx="${h}"/>`;
  o += text(b.x1 + 20, b.y + (Lo.id === 'L' ? 9 : 7), 'GenSwarms', 'tb bandl');
  if (right) o += tlabel(Lo, b.x2 - 18, b.y + (Lo.id === 'L' ? 5.5 : 5), right[0], right[1], { cls: 'ts bandr', anchor: 'end', room: bandRoom(Lo, b, b.x2 - 18) });
  return o;
}
// ---------- the system SVG ----------
export function system(Lo, stage, { extraClass = '', label = '', crop = null, prune = false } = {}) {
  const T = Lo.team, A = T.a, live = /\blive\b/.test(extraClass);
  const grp = (stages, inner, extra = '') =>
    prune && !stages.includes(stage) ? '' : `<g class="${vis(stages)}${extra ? ' ' + extra : ''}">${inner}</g>`;
  const lh = Math.round(Lo.fs.log * 1.5);
  grown = [];
  const fig = k => `figure ${k + 1} (${['one agent', 'hand-wired agents', 'the OS layer', 'processes', 'declared paths', 'objects', 'packages', 'the swarm as a document', 'the control layer'][k]})`;
  let s = '';
  // --- stage 8: the organisation (outside the world group)
  s += `<g class="org">`;
  const b7 = Lo.bar7, SW = Lo.swarms || Lo.clusters;
  // connectors from control layer to the swarms
  let con = '';
  if (Lo.id === 'L') {
    SW.forEach(([x, y]) => { con += `<line class="drop" x1="${x}" y1="${b7.y + bandH(Lo)}" x2="${x}" y2="${y - 38}"/>`; });
  } else {
    const last = SW[6];
    con += `<line class="drop" x1="200" y1="${b7.y + bandH(Lo)}" x2="200" y2="${last[1] - 30}"/>`;
    // horizontal stubs from the spine end where each shape begins
    SW.slice(0, 6).forEach(([x, y], k) => {
      const xs = SHAPES[k].n.map(n => n[0]), end = x < 200 ? x + Math.max(...xs) + 5 : x + Math.min(...xs) - 5;
      con += `<line class="drop" x1="200" y1="${y}" x2="${end}" y2="${y}"/>`;
    });
  }
  s += grp([8], con + band(Lo, b7, ['control layer', `${fig(8)}, SVG label: inside the dark “GenSwarms” band above the swarms (one line)`]));
  let cls = '';
  SW.forEach(([cx, cy], k) => {
    const sh = SHAPES[k];
    sh.e.forEach(([i, j]) => { const a = sh.n[i], b = sh.n[j]; cls += `<line class="ce" x1="${cx + a[0]}" y1="${cy + a[1]}" x2="${cx + b[0]}" y2="${cy + b[1]}"/>`; });
    if (sh.arc) cls += `<path class="ce" d="M${cx + sh.arc[0]} ${cy - 6}Q${cx} ${cy - 34} ${cx + sh.arc[1]} ${cy - 6}"/>`;
    sh.n.forEach(([x, y]) => { cls += `<circle class="cn" cx="${cx + x}" cy="${cy + y}" r="5"/>`; });
  });
  s += grp([8], cls + tlabel(Lo, Lo.swarmsLabel[0], Lo.swarmsLabel[1], 'Swarms', `${fig(8)}, SVG label: bold heading over the row of swarms`, { cls: 'tb tm', room: [Lo.swarmsLabel[0], Lo.w - Lo.swarmsLabel[0]] }));
  // models row
  const m = Lo.models;
  let mr = `<line class="mline" x1="${m.x1}" y1="${m.y}" x2="${m.x2}" y2="${m.y}"/>`;
  m.xs.forEach(x => { mr += hex(x, m.y, 9); });
  mr += tlabel(Lo, m.label[0], m.label[1], 'Models', `${fig(8)}, SVG label: bold heading over the row of models (hexagons)`, { cls: 'tb tm', room: [m.label[0], Lo.w - m.label[0]] });
  s += grp([8], mr);
  s += `</g>`;

  // --- stage 7: the swarm as a document (outside the world group, which folds into it)
  {
    const D = T.doc, pad = 20, x = D.x + pad;
    let y = D.y + pad + Lo.fs.log;
    let d = '';
    const head = (name, note, where) => {
      const end = D.x + D.w - pad;
      d += `<text class="log k-hd" x="${x}" y="${f(y)}">${name}</text>` + tlabel(Lo, end, y, note, where, { cls: 'ts', anchor: 'end', room: [x + name.length * 0.6 * fsOf(Lo, 'log') + 16, end] });
      y += lh;
    };
    head('swarm.state', 'seed', `${fig(7)}, SVG label: note at the right of “swarm.state”, the swarm’s starting definition (one line)`);
    let r;
    [r, y] = monoRows(x + 18, y, lh, [
      ['agents', 'triage, answer'],
      ['objects', 'telegram, cron, budget, browser'],
      ['edges', 'telegram → triage, triage → answer, …'.replace(/ → /g, '\u00a0→\u00a0')],
    ], 9, D.cols - 2);
    d += r;
    y += lh * 0.45;
    head('swarm.overlay', 'change log', `${fig(7)}, SVG label: note at the right of “swarm.overlay”, the numbered log of changes (one line)`);
    // logged changes get a seq; a change the gate refuses (OpPolicy, before any seq) is never logged
    for (const [ok, op] of [[1, '1 add_agent research'], [1, '2 scale_agent_group answer 3'], [0, 'scale_agent_group answer 150']]) {
      if (!ok) y += lh * 0.3;
      d += (ok ? okBadge : noBadge)(x + 26, y - Lo.fs.log * 0.33);
      [r, y] = monoRows(x + 42, y, lh, [['', op]], 0, D.cols - 4);
      d += r;
    }
    const refusedEn = 'refused: over the {cap}-agent cap';
    const refused = tf(refusedEn, { cap: 100 }, `${fig(7)}, SVG label (monospace, red): why the last change was refused; {cap} is the agent limit (100). Wraps at ${D.cols - 4} columns in the phone drawing; CJK characters take two`, { kind: 'svg', max: D.cols - 4 });
    const translated = refused !== fill(refusedEn, { cap: 100 });
    [r, y] = monoRows(x + 42, y, lh, [['', refused, '', 'k-no']], 0, D.cols - 4);
    d += r;
    y += lh * 0.45;
    const restoreEn = 'restore: seed + {n} changes';
    const restore = tf(restoreEn, { n: 2 }, `${fig(7)}, SVG label (monospace): a stopped swarm is rebuilt from its seed plus the logged changes; {n} is how many (2). Wraps at ${D.cols - 4} columns in the phone drawing`, { kind: 'svg', max: D.cols - 4 });
    if (restore === fill(restoreEn, { n: 2 })) {
      d += cyl(x, y - Lo.fs.log - 4) + `<text class="log" x="${x + 38}" y="${f(y)}">${restore}</text>`;
    } else {
      d += cyl(x, y - Lo.fs.log - 4);
      breakLines(restore, D.cols - 4, cols).forEach((ln, i) => { if (i) y += lh; d += `<text class="log" x="${x + 38}" y="${f(y)}">${escText(ln)}</text>`; });
    }
    y += lh * 0.5;
    const h = y - D.y + 4, fold = 22;
    if (translated || restore !== fill(restoreEn, { n: 2 })) grown.push([D.y + h + 8, [7]]);
    d = `<path class="doc" d="M${D.x} ${D.y + 10}q0 -10 10 -10H${D.x + D.w - fold}L${D.x + D.w} ${D.y + fold}V${f(D.y + h - 10)}q0 10 -10 10H${D.x + 10}q-10 0 -10 -10Z"/><path class="doc-f" d="M${D.x + D.w - fold} ${D.y}V${D.y + fold}H${D.x + D.w}"/>` + d;
    s += grp([7], d);
  }

  // --- the world group
  s += `<g class="world">`;
  const pos = agentPos(Lo);
  // stage 1: hand-made wires between scattered agents
  let w = '';
  Lo.wires.forEach(([i, j, qx, qy]) => { const a = Lo.scatter[i], b = Lo.scatter[j]; w += `<path class="wire" d="M${a[0]} ${a[1]}Q${qx} ${qy} ${b[0]} ${b[1]}"/>`; });
  const stubs = [[-24, -22], [26, -18], [-28, 12], [22, 24], [-20, 26], [28, -4]];
  Lo.scatter.forEach(([x, y], i) => { const [dx, dy] = stubs[i % stubs.length]; w += `<line class="sat" x1="${x}" y1="${y}" x2="${x + dx * .72}" y2="${y + dy * .72}"/>` + hex(x + dx, y + dy, 6); });
  s += grp([1], w);

  // stage 2/3: organisation line, the GenSwarms band, column connectors
  const o = Lo.org, br = Lo.bar;
  let g2 = `<line class="orgline" x1="${o.x1}" y1="${o.y}" x2="${o.x2}" y2="${o.y}"/>`;
  const sq = Lo.id === 'L' ? [175, 262, 350, 450, 538, 625] : [60, 116, 172, 228, 284, 340];
  const bh = bandH(Lo);
  sq.forEach(x => { g2 += `<rect class="dept" x="${x - 6}" y="${o.y - 6}" width="12" height="12" rx="2"/><line class="drop" x1="${x}" y1="${o.y + 6}" x2="${x}" y2="${br.y - bh}"/>`; });
  g2 += tlabel(Lo, o.label[0], o.label[1], 'the organization', `${fig(2)}, SVG label: the line of departments at the top (one line)`, { cls: 'ts', room: [o.label[0], o.x2] });
  Lo.grid.xs.forEach(x => { g2 += `<line class="col" x1="${x}" y1="${br.y + bh}" x2="${x}" y2="${Lo.grid.ys[2]}"/>`; });
  s += grp([2, 3], g2 + band(Lo, br, null));
  const bandR = (s, where) => tlabel(Lo, br.x2 - 18, br.y + (Lo.id === 'L' ? 5.5 : 5), s, where, { cls: 'ts bandr', anchor: 'end', room: bandRoom(Lo, br, br.x2 - 18) });
  s += grp([2], tlabel(Lo, Lo.gridLabel[0], Lo.gridLabel[1], 'individual agents', `${fig(2)}, SVG label: under the grid of agents`, { cls: 'ts', anchor: 'middle', room: Lo.id === 'L' ? [150, 650] : [20, 380], lines: 2, st: [2] }) +
    bandR('operating system', `${fig(2)}, SVG label: inside the dark “GenSwarms” band, what the layer is (one line)`));
  // stage 3: supervisor + annotations + one agent crashes and restarts
  // the diamond sits after the word, so it never depends on the label's rendered width
  let g3 = `<path class="dia-in" d="${(() => { const x = br.x2 - 22, y = br.y, r = 6; return `M${x} ${y - r}L${x + r} ${y}L${x} ${y + r}L${x - r} ${y}Z`; })()}"/>` +
    tlabel(Lo, br.x2 - 36, br.y + (Lo.id === 'L' ? 5.5 : 5), 'supervisor', `${fig(3)}, SVG label: inside the dark “GenSwarms” band, before a small diamond; the software that restarts a crashed process, not a person (one line)`, { cls: 'ts bandr', anchor: 'end', room: bandRoom(Lo, br, br.x2 - 36) });
  Lo.ann.forEach(a => {
    // English keeps its hand-set line breaks; a translation wraps to the room it has
    g3 += tlabel(Lo, a.x, a.y, a.lines.join(' '), `${fig(3)}, SVG annotation beside the agents (${Lo.id === 'L' ? 'desktop drawing' : 'phone drawing'}; wraps)`, { cls: 'ts ann', anchor: a.anchor, room: a.room, lines: 3, st: [3],
      english: () => a.lines.map((ln, i) => text(a.x, a.y + i * (Lo.fs.ts + 5), ln, 'ts ann', a.anchor)).join('') });
    if (a.lx1) g3 += `<line class="lead" x1="${a.lx1}" y1="${a.ly - 8}" x2="${a.lx2}" y2="${a.ly - 8}"/>`;
  });
  const C = Lo.crash, [kx, ky] = pos[3][C.i];
  g3 += `<g transform="translate(${kx} ${ky})"><circle class="burst" r="30"/><circle class="restart" r="23"/></g>`;
  g3 += tlabel(Lo, C.st[0], C.st[1], 'crashed, restarted', `${fig(3)}, SVG label: status under the one agent that crashes and comes back`, { cls: 'ts st', anchor: C.st[2], room: Lo.id === 'L' ? [240, 660] : [20, 380], lines: 2, st: [3] });
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
  const satRoom = Lo.id === 'L' ? { model: [300, 500], prompt: [500, 792], tools: [8, 300] } : { model: [120, 280], prompt: [256, 384], tools: [16, 146] };
  for (const [k, [x, y]] of Object.entries(Lo.sat)) {
    const [x1, y1, x2, y2] = shorten(cx, cy, x, y, Lo.id === 'L' ? 66 : 56, 20);
    g0 += `<line class="sat" x1="${f(x1)}" y1="${f(y1)}" x2="${f(x2)}" y2="${f(y2)}"/>` + glyph[k](x, y);
    g0 += tlabel(Lo, x, y < cy ? y - 24 : y + 38, k, `${fig(0)}, SVG label: one of the three things an agent is made of (its model / its prompt / its tools); one line`, { anchor: 'middle', room: satRoom[k] });
  }
  s += grp([0], g0);

  // stages 4-6: the support swarm. Declared edges (agent radius 22, object radius 19)
  const [TR, AN, RE] = A, OB = { tg: T.tg, cron: T.cron, budget: T.budget, browser: T.browser };
  s += grp([4, 5, 6], edge(OB.tg, TR, 19, 22) + edge(TR, AN, 22, 22) + edge(TR, RE, 22, 22) + edge(RE, AN, 22, 22) + edge(AN, OB.tg, 22, 19));
  s += grp([5, 6], edge(TR, OB.cron, 22, 19) + edge(RE, OB.browser, 22, 19));
  // budget (llm-proxy) is the endpoint agents call their model through, not a message route:
  // dotted, arrowless lines, never the edge style
  s += grp([5, 6], edge(AN, OB.budget, 22, 19, 'mc', false) + edge(RE, OB.budget, 22, 19, 'mc', false) +
    (T.callsLabel ? tlabel(Lo, T.callsLabel[0], T.callsLabel[1], 'model calls', `${fig(5)}, SVG label (desktop drawing): on the dotted lines from two agents to “budget”, the proxy they call their model through`, { cls: 'ts', anchor: T.callsLabel[2], room: [480, 700], lines: 2, st: [5, 6] }) : ''));
  // stage 4: research tries telegram, which is off the graph: the message is dropped
  {
    const [dx, dy] = T.drop, [x1, y1] = shorten(RE[0], RE[1], dx, dy, 22, 0);
    const u = 7;
    let g = `<line class="edrop" x1="${f(x1)}" y1="${f(y1)}" x2="${dx}" y2="${dy}"/>`;
    g += `<path class="xm" d="M${dx - u} ${dy - u}L${dx + u} ${dy + u}M${dx + u} ${dy - u}L${dx - u} ${dy + u}"/>`;
    g += tlabel(Lo, T.dropLabel[0], T.dropLabel[1], 'dropped', `${fig(4)}, SVG label (red): next to the crossed-out message that was off the graph`, { cls: 'ts xl', anchor: T.dropLabel[2], room: Lo.id === 'L' ? [345, 436] : [110, 290], lines: 2, up: Lo.id === 'P', st: [4] });
    s += grp([4], g);
  }
  // objects (squares), their labels, and at stage 6 the verified package mark
  OBJECTS.forEach(([key, name, from]) => {
    const [x, y] = OB[key], [lx, ly, la] = T.olabels[key];
    s += grp(range(from, 6), obj(x, y) + text(lx, ly, name, 't', la));
    s += grp([6], okBadge(x + 15, y - 15));
  });
  // stage 4: events (illustration)
  {
    const [gx, gy] = T.log;
    let b = tlabel(Lo, gx, gy, 'events (illustration)', `${fig(4)}, SVG label (italic): heading over the simulated event log`, { cls: 'ts logcap', room: [gx, BOUNDS[Lo.id][1]] });
    b += monoRows(gx, gy + lh, lh, [
      ['message_routed', 'telegram → triage'],
      ['message_routed', 'triage → research'],
      ['invalid_route', 'research → telegram'],
      ['message_routed', 'research → answer'],
      ['message_routed', 'answer → telegram'],
    ], 16, 99)[0];
    s += grp([4], b);
  }
  // stage 5: legend
  {
    const [gx, gy] = T.legend, gap = Lo.id === 'L' ? 34 : 30, tx = gx + 28;
    const room = [tx, Lo.id === 'L' ? 640 : BOUNDS.P[1]];
    let b = `<rect class="lg-b" x="${gx - 3}" y="${gy - 19}" width="28" height="28" rx="7"/>` + agentGlyph(gx + 11, gy - 5) + tlabel(Lo, tx, gy, 'agent, uses a model', `${fig(5)}, SVG legend: next to the circle symbol (one line)`, { cls: 'ts', room });
    b += `<rect class="ob" x="${gx}" y="${gy + gap - 16}" width="22" height="22" rx="3"/><rect class="ob-c" x="${gx + 7}" y="${gy + gap - 9}" width="8" height="8" rx="1"/>` + tlabel(Lo, tx, gy + gap, 'object, plain code', `${fig(5)}, SVG legend: next to the square symbol (one line)`, { cls: 'ts', room });
    s += grp([5], b);
  }
  // stage 6: the swarmidx index, each package verified on this machine
  {
    const [gx, gy] = T.index;
    // header: the index, and what the mark means
    // (the legend starts at a fixed x, so labels that step up in size grow away from the mark)
    // (a translated "verified" too long for the phone drawing moves the mark left, never past the heading)
    const idxEn = 'swarmidx index', okEn = 'verified';
    const idxT = t(idxEn, `${fig(6)}, SVG label: heading over the list of packages (swarmidx is the package index; keep the name)`, { kind: 'svg' });
    const okT = t(okEn, `${fig(6)}, SVG legend: next to the green check mark; each package was checked on this machine (one short word)`, { kind: 'svg' });
    const fs = fsOf(Lo, 'ts'), BR = BOUNDS[Lo.id][1];
    let kx = Lo.id === 'L' ? gx + 24 + 40 * Lo.fs.log * 0.6 : 300;
    if (okT !== okEn) kx = Math.max(Math.min(kx, BR - 22 - em(okT) * fs), gx + em(idxT) * fs + 12);
    let b = tlabel(Lo, gx, gy, idxEn, '', { cls: 'ts', room: [gx, kx - 4] }) + okBadge(kx + 8, gy - 5) + tlabel(Lo, kx + 22, gy, okEn, '', { cls: 'ts', room: [kx + 22, BR], max: 16 });
    let y = gy + lh + 4;
    OBJECTS.forEach(o => {
      b += okBadge(gx + 8, y - Lo.fs.log * 0.33);
      const rows = Lo.id === 'L' ? [[o[3], o[4], 'k-pkg', 'k-dg']] : [[o[3], '', 'k-pkg'], ['', o[4], '', 'k-dg']];
      let r;
      [r, y] = monoRows(gx + 24, y, lh, rows, Lo.id === 'L' ? 40 : 2, 99);
      b += r;
    });
    s += grp([6], b);
  }

  // agents
  pos[0].forEach((_, i) => {
    if (prune && !AGENT_VIS(i).includes(stage)) return;
    let a = `<g class="ag a${i} ${vis(AGENT_VIS(i))}" style="--i:${i}">`;
    a += (prune && !([3, 4, 5, 6].includes(stage))) ? '' : `<rect class="bnd ${vis([3, 4, 5, 6])}" x="-25" y="-25" width="50" height="50" rx="12"/>`;
    a += `<circle class="ring" r="16"/><circle class="core" r="10"/>`;
    if (i < 3) {
      const [x, y, anc] = T.labels[i];
      a += grp([4, 5, 6], text(x - A[i][0], y - A[i][1], AGENT_NAMES[i], 't', anc));
    }
    a += `</g>`;
    s += a;
  });
  // work in motion: the routed message, and (stage 4) the one that is dropped
  s += (prune && !([4, 5].includes(stage))) ? '' : `<g class="tok ${vis([4, 5])}"><circle r="7.5"/></g>`;
  s += (prune && stage !== 4) ? '' : `<g class="tok tok2 ${vis([4])}"><circle r="7.5"/></g>`;
  s += `</g>`; // world

  // the live figure keeps one viewBox for every stage; a camera group recentres each drawing (figureCSS)
  if (live) s = `<g class="cam">${s}</g>`;
  // a still whose translated labels wrapped below its crop grows to show them
  let vb = crop || `0 0 ${Lo.w} ${Lo.h}`;
  if (crop) {
    const [x0, y0, w0, h0] = crop.split(' ').map(Number);
    const need = Math.max(0, ...grown.filter(([, st]) => st.includes(stage)).map(([y]) => y + 6 - (y0 + h0)));
    if (need > 0) vb = `${x0} ${y0} ${w0} ${f(h0 + need)}`;
  }
  return `<svg class="sys ${Lo.id}${extraClass ? ' ' + extraClass : ''}" data-s="${stage}" viewBox="${vb}" role="img" aria-label="${label}">${s}</svg>`;
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
    const [tx, ty] = Lo.worldTo, sc = 0.2, wc = Lo.worldC;
    c += `.${Lo.id}[data-s="7"] .world,.${Lo.id}[data-s="8"] .world{transform:translate(${f(tx - wc[0] * sc)}px,${f(ty - wc[1] * sc)}px) scale(${sc});opacity:0}`;
    c += `.${Lo.id} .t{font-size:${Lo.fs.t}px}.${Lo.id} .ts{font-size:${Lo.fs.ts}px}.${Lo.id} .tb{font-size:${Lo.fs.tb}px}.${Lo.id} .log{font-size:${Lo.fs.log}px}`;
    // tokens: static positions, then animated routes
    const T = Lo.team, [TR, AN, RE] = T.a, TG = T.tg;
    const mid = (p, q, t = 0.5) => [p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t];
    const tp = p => `transform:translate(${f(p[0])}px,${f(p[1])}px)`;
    // the dropped message stops just short of the cross
    const [dx, dy] = T.drop, [, , ex, ey] = shorten(RE[0], RE[1], dx, dy, 0, 16), X = [ex, ey];
    c += `.${Lo.id}[data-s="4"] .tok{${tp(mid(TR, RE))}}.${Lo.id}[data-s="5"] .tok{${tp(mid(TR, AN))}}.${Lo.id}[data-s="4"] .tok2{${tp(X)}}`;
    c += [0, 1, 2, 3, 6, 7, 8].map(k => `.${Lo.id}[data-s="${k}"] .tok`).join(',') + `{${tp(TR)}}.${Lo.id} .tok2{${tp(RE)}}`;
    c += '\n@media (prefers-reduced-motion:no-preference){';
    // route helper: list of [point, pct, opacity]
    const kf = (name, frames) => `@keyframes ${name}{` + frames.map(([p, pct, op]) => `${pct}%{${tp(p)};opacity:${op}}`).join('') + '}';
    c += kf(`t4${Lo.id}`, [[TG, 0, 0], [TG, 4, 1], [TR, 18, 1], [RE, 34, 1], [RE, 36, 1], [AN, 54, 1], [TG, 72, 1], [TG, 78, 0], [TG, 100, 0]]);
    c += kf(`x4${Lo.id}`, [[RE, 0, 0], [RE, 38, 0], [RE, 40, 1], [X, 50, 1], [X, 64, 1], [X, 70, 0], [X, 100, 0]]);
    c += kf(`t5${Lo.id}`, [[TG, 0, 0], [TG, 4, 1], [TR, 24, 1], [AN, 46, 1], [TG, 68, 1], [TG, 74, 0], [TG, 100, 0]]);
    c += `.${Lo.id}[data-s="4"] .tok{animation:t4${Lo.id} 6.4s linear infinite}.${Lo.id}[data-s="4"] .tok2{animation:x4${Lo.id} 6.4s linear infinite}.${Lo.id}[data-s="5"] .tok{animation:t5${Lo.id} 5.6s linear infinite}`;
    c += '}\n';
  }
  return c;
}
