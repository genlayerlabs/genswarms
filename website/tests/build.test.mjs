import { test } from 'node:test';
import assert from 'node:assert/strict';
import { renderPage, CINE } from '../src/page.mjs';
import { readFileSync } from 'node:fs';
import { catalogue } from '../src/site.mjs';
const css = () => readFileSync(new URL('../src/page.css', import.meta.url), 'utf8');
const src = f => readFileSync(new URL(`../src/${f}`, import.meta.url), 'utf8');

const html = renderPage();
// remove every element <tag class="cls…"> with its content (nesting-aware)
function strip(h, tag, cls) {
  const open = new RegExp(`<${tag} class="${cls}[^"]*"[^>]*>`, 'g');
  let out = '', i = 0, m;
  while ((m = open.exec(h))) {
    out += h.slice(i, m.index);
    let depth = 1, j = open.lastIndex;
    const re = new RegExp(`<${tag}[\\s>]|</${tag}>`, 'g');
    re.lastIndex = j;
    let n;
    while (depth && (n = re.exec(h))) depth += n[0].startsWith('</') ? -1 : 1;
    i = n ? re.lastIndex : h.length; open.lastIndex = i;
  }
  return out + h.slice(i);
}
const zs = JSON.parse(html.match(/<script type="application\/json" id="zoom-strings">([\s\S]*?)<\/script>/)[1]);

test('page has the owner headline and all nine story steps', () => {
  assert.match(html, /<h1>The operating system for AI(&nbsp;| )workforces\.<\/h1>/);
  for (let k = 0; k <= 8; k++) assert.match(html, new RegExp(`id="s${k}" data-step="${k}"`));
});

test('one stage: a canvas with a text alternative, the zoom caption, the readouts and the illustration label', () => {
  assert.equal((html.match(/<canvas /g) || []).length, 1);
  assert.match(html, /<canvas role="img" aria-label="Illustration: an organization of 36 swarms, several thousand agents\./);
  assert.match(html, /<div class="zcap" aria-hidden="true"><span class="lv">organization<\/span>/);
  assert.match(html, /<div class="ros" aria-hidden="true">/);
  assert.match(html, /<div class="ill" aria-hidden="true">illustration<\/div>/);
  // one text alternative per keyframe (K0-K10), in the page's JSON block, the first one also on the canvas
  assert.equal(zs.aria.length, 11);
  for (const a of zs.aria) assert.match(a, /^Illustration: /);
  // the same media query decides the pinned layout in the head script and in the drawing's script
  assert.equal(zs.cine, CINE);
  assert.ok(html.includes(`matchMedia('${CINE}')`));
});

test('readouts: in the stage for the pinned layout (hidden from screen readers), and in each step for everyone else', () => {
  const stage = html.match(/<div class="ros" aria-hidden="true">([\s\S]*?)<div class="ill"/)[1];
  assert.deepEqual([...stage.matchAll(/<div class="ro[^"]*" data-at="(\d+)"/g)].map(m => +m[1]), [0, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
  // the legend (data-at 0) is in the stage only: the canvas's text alternative describes the marks
  const inStep = k => [...html.match(new RegExp(`id="s${k}" data-step="${k}"[\\s\\S]*?</article>`))[0].matchAll(/<div class="ro-in" data-at="(\d+)"/g)].map(m => +m[1]);
  assert.deepEqual([0, 1, 2, 3, 4, 5, 6, 7, 8].map(inStep), [[], [2, 3], [4], [5], [6], [7], [8], [9], [10]]);
  // the readouts are real text: event kinds, package refs and shortened digests
  assert.match(html, /<span class="k">invalid_route<\/span><span>research <span class="ar">→<\/span> telegram<\/span><span class="tag">dropped<\/span>/);
  for (const pkg of ['genlayerlabs/genswarms-telegram@0.6.6', 'genlayerlabs/cron@0.2.8', 'genlayerlabs/genswarms-llm-proxy@0.4.2', 'genlayerlabs/browser@0.2.4']) assert.ok(html.includes(pkg), pkg);
  assert.doesNotMatch(html, /sha256:[0-9a-f]{5,}/, 'digests are visibly shortened placeholders');
});

test('without JavaScript the stage is not shown and nothing is blank', () => {
  assert.match(css(), /html:not\(\.js\) \.stage-col\{display:none\}/);
  assert.match(html, /<script>\(function\(\)\{var d=document\.documentElement;d\.classList\.add\('js'\)/);
  // the zoom's script gives up cleanly without a canvas: the page falls back to the no-JS layout
  assert.match(src('zoom-run.js'), /if \(!g\) \{ root\.classList\.remove\('js', 'cine'\); return; \}/);
});

test('built page is under 150 KB', () => {
  assert.ok(Buffer.byteLength(html) < 153600, `${Buffer.byteLength(html)} bytes`);
});

test('no copy lives in the script: the drawing takes its words from the catalogue', () => {
  const script = html.match(/<script>\n([\s\S]*?)<\/script>\n?<\/body>/)[1];
  assert.doesNotMatch(script, /\bARIA\b/);
  for (const e of catalogue()) {
    // (a one-word string can also be a document key or identifier the drawing spells out, e.g. "agents")
    if (!/\s/.test(e.en)) continue;
    assert.ok(!script.includes(`'${e.en}'`) && !script.includes(`"${e.en}"`), `hard-coded in the script: ${e.en}`);
  }
  for (const phrase of ['operating system', 'Every agent is a process', 'Not everything needs a model', 'model calls', 'never logged', 'log of changes', 'Copied', 'Selected']) assert.ok(!script.includes(phrase), phrase);
  // every word the canvas draws is in the JSON block
  for (const k of ['lv', 'count', 'layer', 'supervisor', 'process', 'sandbox', 'dropped', 'crashed', 'restarted', 'modelCalls', 'model', 'tools', 'prompt', 'agent', 'seed', 'log', 'declared', 'refused', 'never', 'defines', 'restores', 'aria']) assert.ok(zs[k], k);
  assert.equal(zs.count, '{swarms} swarms · {agents} agents');
  assert.equal(zs.refused, 'refused: over the {cap}-agent cap');
  // numbers are formatted for the page's language
  assert.match(src('zoom-run.js'), /new Intl\.NumberFormat\(lang, opts\)/);
});

const text = html.replace(/<script[\s\S]*?<\/script>|<style[\s\S]*?<\/style>/g, '').replace(/<[^>]+>/g, ' ').replace(/&nbsp;/g, ' ').replace(/\s+/g, ' ');

test('banned claims are absent', () => {
  // (the package scope genlayerlabs/ in the readouts is a real swarmidx identifier)
  const all = text + ' ' + JSON.stringify(zs);
  assert.doesNotMatch(all, /GenLayer(?! Labs|labs\/)|unhardcoded|blockchain/i);
  assert.doesNotMatch(all, /\bRBAC\b|per-user permission|approval workflow|sandboxed packages/i);
  assert.doesNotMatch(all, /(?<!not )exactly once/i);
  assert.doesNotMatch(all, /\bmemory\b/i);
});

test('approved copy deck v2 is applied (design/2026-09-25-copy-deck-v2.md)', () => {
  assert.match(text, /Deploy, coordinate and control thousands of AI agents across your organization\./);
  const heads = [...html.matchAll(/<article class="step[^"]*" id="s\d"[\s\S]*?<h[12]>([\s\S]*?)<\/h[12]>/g)].map(m => m[1].replace(/&nbsp;/g, ' '));
  assert.deepEqual(heads, ['The operating system for AI workforces.', 'Your agents need more than models and prompts.', 'Think of it as an operating system.',
    'Every agent is a process.', 'Agents talk only along declared paths.', 'Not everything needs a model.', 'Install what your agents need.',
    'A swarm is a document.', 'One control layer for your AI organization.']);
  assert.match(text, /One agent is easy\. Many agents working together need somewhere to run, rules for who talks to whom, and a way back when one fails\./);
  assert.match(text, /An operating system runs programs it didn’t write\. GenSwarms does that for agents: it starts them, isolates them, routes their messages and restarts them when they fail\./);
  assert.match(text, /You draw the graph\. Every message is checked against it, and anything off the graph is dropped\./);
  assert.match(text, /signed packages from the swarmidx index, verified before they load\./);
  assert.match(text, /A bad change is refused before it runs; a stopped swarm comes back from its database\./);
  assert.match(text, /Models provide intelligence\. Agents perform work\. GenSwarms runs the organization\./);
  assert.match(text, /How is it different from LangGraph, CrewAI or AutoGen\?/);
  assert.match(text, /In use today for chat assistants, coding agents, trading simulations and swarms that watch other swarms\./);
  assert.match(text, /Read https:\/\/genswarms\.com\/skill\.md and set up a swarm\./);
  // the v4 design's additions: the hero facts row, the section sub-lines, the sources note
  assert.match(html, /<dl class="facts"><div><dt>license<\/dt><dd>Open source, MIT<\/dd><\/div><div><dt>version<\/dt><dd>0\.2\.0<\/dd><\/div><div><dt>runtime<\/dt><dd>Elixir \/ OTP<\/dd><\/div><\/dl>/);
  assert.equal((html.match(/<div class="sec-head"><h2 [^>]+>[^<]+<\/h2><p>[^<]+<\/p><\/div>/g) || []).length, 3);
  assert.match(text, /From each project’s own documentation, September 2026\./);
  // removed: v1's turn block and determines list, explanatory paragraphs, the Control surface row
  assert.doesNotMatch(html, /class="(turn|turn-k|turn-q|determines|strike)\b/);
  assert.doesNotMatch(text, /It becomes|share context|A runtime, not a library|Control surface|production-ready|build an AI workforce/);
  // one example line, on step 5 (#s4)
  assert.equal((html.match(/class="ex"/g) || []).length, 1);
  assert.match(html, /id="s4" data-step="4"[^>]*>\s*<div class="copy">[\s\S]*?<p class="ex">From here the drawings follow one swarm: a support team that answers customers on Telegram\.<\/p>/);
  // "How it works." has the deck's ten rows, in order
  assert.deepEqual([...html.matchAll(/<div class="row"><dt>([^<]+)<\/dt>/g)].map(m => m[1]), ['Processes', 'Isolation', 'Network', 'Messages', 'Services', 'Drivers', 'Packages', 'State', 'Control', 'Events']);
  assert.equal((html.match(/<div class="gu-col yes"><h3>[^<]+<\/h3><ul>([\s\S]*?)<\/ul>/)[1].match(/<li>/g) || []).length, 4);
  assert.equal((html.match(/<div class="gu-col not"><h3>[^<]+<\/h3><ul>([\s\S]*?)<\/ul>/)[1].match(/<li>/g) || []).length, 5);
});

test('none of the removed v1 story remains (page, llms.txt)', () => {
  const llms = readFileSync(new URL('../llms.txt', import.meta.url), 'utf8');
  for (const [name, t] of [['index.html', html], ['llms.txt', llms]]) {
    for (const re of [/charged/i, /classifier/i, /verifier/i, /escalat/i, /human/i, /agent_blocked/i, /attaches/i, /team shapes/i, /Customer operations/i, /coordination layer/i])
      assert.doesNotMatch(t, re, `${name}: ${re}`);
  }
});

test('visible copy stays short', () => {
  const words = h => h.replace(/<svg[\s\S]*?<\/svg>|<script[\s\S]*?<\/script>|<style[\s\S]*?<\/style>/g, ' ')
    .replace(/<[^>]+>/g, ' ').replace(/&nbsp;/g, ' ').split(/\s+/).filter(w => /[\p{L}\p{N}]/u.test(w)).length;
  // the page's prose: <main> outside svg/script/style, without screen-reader-only text, the readouts (what the drawing
  // shows, as text) and the comparison table (sourced data, fixed by design/comparison-sources.md)
  const main = strip(strip(html.match(/<main[\s\S]*<\/main>/)[0], 'div', 'ros'), 'div', 'ro-in');
  const prose = words(main.replace(/<(span|caption) class="sr"[\s\S]*?<\/\1>/g, ' ').replace(/<table[\s\S]*?<\/table>/, ' '));
  // pinned at the v4 design's applied counts, so copy can't grow silently
  assert.ok(prose <= 580, `${prose} words of prose`);
  const all = words(html.match(/<body>[\s\S]*<\/body>/)[0]);
  assert.ok(all <= 1180, `${all} words on the whole page`);
});

test('facts match v0.2.0', () => {
  assert.match(text, /0\.2\.0/);
  for (const b of ['Local', 'Tmux', 'Docker', 'Apple container', 'SSH', 'Bwrap', 'Mock']) assert.ok(text.includes(b), b);
  assert.match(text, /100 agents/);
  assert.match(text, /illustration/i);
});

test('every simulated readout and the drawing are labelled illustration', () => {
  // the drawing always carries "illustration" (bottom right); its text alternatives start with "Illustration:"
  assert.match(html, /<div class="ill" aria-hidden="true">illustration<\/div>/);
  // the simulated events and packages (keyframes 5, 6, 8, 10) carry it in their headings
  for (const k of [5, 6, 8, 10]) assert.match(html, new RegExp(`<div class="ro(-in)?" data-at="${k}"><p class="ro-t">[^<]*\\(illustration\\)</p>`), `readout ${k}`);
  // the event log uses the real telemetry event names
  assert.match(html, /<span class="k">message_routed<\/span><span>telegram <span class="ar">→<\/span> triage<\/span>/);
});

test('the drawing tells the v2 story from real parts', () => {
  const js = ['zoom-world.js', 'zoom-draw.js', 'zoom-support.js', 'zoom-run.js'].map(src).join('\n');
  // the support team, its objects and its declared paths
  for (const n of ["tg: 'telegram'", "cron: 'cron'", "browser: 'browser'", "budget: 'budget'", "triage: 'triage'", "answer: 'answer'", "research: 'research'"]) assert.ok(js.includes(n), n);
  assert.match(js, /\['research', 'budget', \[\[700, 210\]\], 'm', 'more'\]/, 'budget is called for model calls, not a message route');
  // the document: a seed and a log of changes; the refused change gets no number and is never logged
  for (const s of ["'swarm.state'", "'swarm.overlay'", "'1  add_agent research'", "'×  scale_agent_group answer 150'"]) assert.ok(js.includes(s), s);
  assert.match(js, /fill\(ZS\.refused, \{ cap: nf0\(100\) \}\)/);
  // 36 swarms: 35 generated and the support team; the named ones are real uses
  assert.match(js, /N = 35/);
  assert.match(js, /var NAMED = \['chat', 'coding', 'trading sim', 'observer'\];/);
  // orange only for failure: the crash, the dropped message, the refused change (and the wordmark's cursor)
  const orUses = (js.match(/C\.or\b/g) || []).length;
  assert.ok(orUses >= 5 && orUses <= 12, `${orUses} uses of orange in the drawing`);
});

test('comparison has no Draft stamp once sourced', () => {
  assert.doesNotMatch(text, /Draft/);
});

test('no pill badges or tracked uppercase eyebrows', () => {
  assert.doesNotMatch(html, /class="[^"]*\b(pill|badge|eyebrow)\b/);
  assert.doesNotMatch(css(), /text-transform:\s*uppercase[^}]*letter-spacing|letter-spacing[^}]*text-transform:\s*uppercase/);
});

test('the wordmark replaces the old logo, and keeps an accessible name', () => {
  assert.doesNotMatch(html, /class="mark|<svg class="mark/);
  const brands = [...html.matchAll(/<a class="brand" href="#s0" aria-label="([^"]+)">genswarms<span class="cur" aria-hidden="true"><\/span><\/a>/g)];
  assert.equal(brands.length, 2, 'header and footer');
  for (const b of brands) assert.equal(b[1], 'GenSwarms home');
  assert.match(css(), /\.cur\{[^}]*background:var\(--or\)/);
  // the icons: a graphite square, a Geist Mono "g" drawn as a path (no font needed) and the orange cursor
  const fav = readFileSync(new URL('../favicon.svg', import.meta.url), 'utf8');
  assert.match(fav, /fill="#0D0E10"/); assert.match(fav, /fill="#FF6A2B"/); assert.match(fav, /<path fill="#ECEDEF" d="M/);
  assert.doesNotMatch(fav, /<text/);
  for (const f of ['favicon-32.png', 'apple-touch-icon.png']) {
    const png = readFileSync(new URL(`../${f}`, import.meta.url));
    const [w, h] = [png.readUInt32BE(16), png.readUInt32BE(20)];
    assert.deepEqual([w, h], f === 'favicon-32.png' ? [32, 32] : [180, 180], f);
  }
});

test('the dimmest text passes WCAG AA', () => {
  const v = n => css().match(new RegExp(`--${n}:(#[0-9A-Fa-f]{6})`))[1];
  const lum = hex => { const c = [1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16) / 255).map(x => (x <= 0.03928 ? x / 12.92 : ((x + 0.055) / 1.055) ** 2.4)); return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]; };
  const ratio = (a, b) => { const [x, y] = [lum(a), lum(b)].sort((p, q) => q - p); return (x + 0.05) / (y + 0.05); };
  for (const bg of ['bg', 'bg-0', 'bg-1', 'bg-2']) for (const fg of ['ink', 'ink-2', 'ink-3', 'or']) assert.ok(ratio(v(fg), v(bg)) >= 4.5, `${fg} on ${bg}: ${ratio(v(fg), v(bg)).toFixed(2)}`);
});

test('inlined CSS and JS are minified', () => {
  const style = html.match(/<style>([\s\S]*?)<\/style>/)[1];
  assert.doesNotMatch(style, /\/\*/, 'no CSS comments');
  assert.doesNotMatch(style, /\n[ \t]/, 'no indentation in CSS');
  const script = html.match(/<script>\n([\s\S]*?)<\/script>\n?<\/body>/)[1];
  assert.doesNotMatch(script, /^\s*\/\//m, 'no comment lines in JS');
  assert.doesNotMatch(script, /^\/\*/m, 'no block comments in JS');
  assert.doesNotMatch(script, /\n[ \t]/, 'no indentation in JS');
  assert.doesNotMatch(html.replace(/<script[\s\S]*?<\/script>|<style[\s\S]*?<\/style>/g, ''), /\n[ \t]+</, 'no indentation between tags');
});

test('the canvas stays light: DPR capped at 2, paused off screen and in hidden tabs, pooled messages', () => {
  const run = src('zoom-run.js');
  assert.match(run, /maxDpr = 2/);
  assert.match(run, /Math\.min\(window\.devicePixelRatio \|\| 1, maxDpr\)/);
  assert.match(run, /new IntersectionObserver/);
  assert.match(run, /visibilitychange/);
  assert.match(run, /if \(!rm && onScreen && !D\.hidden\) raf = requestAnimationFrame\(frame\)/);
  // resizes are debounced; a slow device drops resolution and messages
  assert.match(run, /setTimeout\(function \(\) \{ layout\(\); kick\(\); \}, 120\)/);
  assert.match(run, /pulseCap = 24/);
  // nothing Chrome-only on the canvas
  assert.doesNotMatch(src('zoom-draw.js') + src('zoom-support.js'), /roundRect|\.filter\s*=|letterSpacing|fontKerning/);
});

test('head metadata', () => {
  const desc = html.match(/<meta name="description" content="([^"]+)"/)[1];
  assert.ok(desc.length <= 150, `description ${desc.length} chars`);
  assert.match(html, /<title>GenSwarms: the operating system for AI workforces<\/title>/);
  assert.match(html, /<link rel="canonical" href="https:\/\/genswarms\.com\/"/);
  assert.match(html, /<meta http-equiv="content-language" content="en"/);
  for (const i of ['/favicon.svg', '/favicon-32.png', '/apple-touch-icon.png']) assert.ok(html.includes(`href="${i}"`), i);
  const ld = JSON.parse(html.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/)[1]);
  assert.equal(ld['@type'], 'SoftwareApplication');
  assert.equal(ld.softwareVersion, '0.2.0');
  assert.doesNotMatch(html, /FAQPage/);
  // Geist and Geist Mono only, swapped in, with preconnect
  const F = 'https://fonts.googleapis.com/css2?family=Geist+Mono:wght@400..600&family=Geist:wght@400..600&display=swap';
  assert.deepEqual([...html.matchAll(/<link href="(https:\/\/fonts\.googleapis\.com[^"]+)"/g)].map(m => m[1]), [F, F]);
  // loaded without blocking the first paint, and the usual way without JavaScript
  assert.ok(html.includes(`<link href="${F}" rel="stylesheet" media="print" onload="this.media='all'">\n<noscript><link href="${F}" rel="stylesheet"></noscript>`));
  assert.match(src('zoom-run.js'), /D\.fonts\.addEventListener\('loadingdone', onResize\)/);
  assert.match(html, /<link rel="preconnect" href="https:\/\/fonts\.gstatic\.com" crossorigin>/);
  // landmarks and the skip link
  for (const re of [/<a class="skip" href="#main">Skip to content<\/a>/, /<header class="top">/, /<nav aria-label="Primary">/, /<main id="main">/, /<footer class="foot">/, /<nav aria-label="Footer">/]) assert.match(html, re);
});
test('llms.txt matches the new positioning', () => {
  const t = readFileSync(new URL('../llms.txt', import.meta.url), 'utf8');
  assert.match(t, /operating system for AI workforces/);
  assert.match(t, /0\.2\.0/);
  assert.match(t, /Apple container/);
  assert.doesNotMatch(t, /~380|54 ?KB/);
});
