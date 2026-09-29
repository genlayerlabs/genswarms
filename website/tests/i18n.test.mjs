// The translation pipeline (website/src/i18n.mjs, site.mjs), exercised with pseudo-locales written to a temp dir.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, readFileSync, mkdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { createHash } from 'node:crypto';
import { LANGS, ORIGIN, PROTECT, sid, textRuns, validate } from '../src/i18n.mjs';
import { catalogue, catalogueFile, build, check, verify, ogSource, ogFile, ogKey } from '../src/site.mjs';
import { CARD } from '../src/card.mjs';
import { createServer } from 'node:http';
import { renderPage } from '../src/page.mjs';
import { pseudo, writePseudo } from '../tools/pseudo.mjs';

const WEB = new URL('../', import.meta.url);
const tmp = () => mkdtempSync(join(tmpdir(), 'gs-i18n-test-'));
const url = d => pathToFileURL(d + '/');
const entries = catalogue();
const byEn = en => entries.find(e => e.en === en);

// a pseudo-locale set for `codes`, optionally edited, built in memory
function pseudoBuild(codes, edit = () => {}, opts = {}) {
  const d = tmp();
  writePseudo(d, codes);
  for (const l of LANGS.filter(l => codes.includes(l.code))) {
    const f = join(d, `${l.file}.json`), tx = JSON.parse(readFileSync(f, 'utf8'));
    edit(l.code, tx);
    writeFileSync(f, JSON.stringify(tx));
  }
  const r = build({ i18nDir: url(d), outDir: WEB, ...opts });
  rmSync(d, { recursive: true, force: true });
  return r;
}
const refused = (r, re) => { assert.ok(r.errors.length, 'the build should refuse'); assert.ok(r.errors.some(e => re.test(e)), r.errors.join('\n')); assert.equal(r.outputs, undefined, 'nothing to write'); };

test('extraction is deterministic and matches the committed catalogue', () => {
  assert.deepEqual(catalogue(), entries);
  assert.equal(catalogueFile(entries), readFileSync(new URL('i18n/en.json', WEB), 'utf8'), 'run `node website/build.mjs --extract`');
});

test('ids are a hash of the English, so an edited sentence gets a new id', () => {
  for (const e of entries) assert.equal(e.id, sid(e.en));
  assert.equal(new Set(entries.map(e => e.id)).size, entries.length, 'no two entries share an id');
  assert.notEqual(sid('Every agent is a process.'), sid('Every agent is a process'));
  // and the build notices: a catalogue made from other English is stale
  const d = tmp();
  const edited = entries.map(e => (e.en === 'Every agent is a process.' ? { ...e, en: 'Each agent is a process.', id: sid('Each agent is a process.') } : e));
  writeFileSync(join(d, 'en.json'), catalogueFile(edited));
  refused(build({ i18nDir: url(d), outDir: WEB }), new RegExp(`en\\.json is stale.*${sid('Every agent is a process.')}`));
  rmSync(d, { recursive: true, force: true });
});

test('the catalogue holds every kind of string, and keeps names and identifiers out', () => {
  const en = new Set(entries.map(e => e.en));
  for (const s of ['GenSwarms: the operating system for AI workforces', 'Skip to content', 'Illustration: the camera zooms into one swarm, a support team.',
    'illustration', 'Copy', 'Copied', 'Selected', 'Language', 'This page is also available in English.', 'Dismiss', 'This page ran off the swarm.',
    'organization', 'team', 'agent', '{swarms} swarms · {agents} agents', 'start · isolate · route · restart', 'supervisor', 'process', 'sandbox',
    'crashed', 'restarted', 'dropped', 'model calls', 'verified', 'events (illustration)', 'seed', 'log of changes', '{n} declared',
    'refused: over the {cap}-agent cap', 'never logged', 'defines', 'restores from its database', 'model', 'prompt', 'tools', 'agent {n}',
    'message on a declared path', 'license', 'runtime', 'Open source, MIT', 'From each project’s own documentation, September 2026.'])
    assert.ok(en.has(s), s);
  // units are whole elements with their inline markup
  assert.ok(en.has('The operating system for AI&nbsp;workforces.'));
  for (const kept of ['GenSwarms', 'genswarms', 'GitHub', 'LangGraph', 'telegram', 'triage', 'message_routed', 'swarm.state', 'genlayerlabs/cron@0.2.8', 'Local, Tmux, Docker, Apple container, SSH, Bwrap, Mock.', 'Elixir / OTP', 'trading sim', 'English', 'Español'])
    assert.ok(!en.has(kept), kept);
  assert.ok(entries.every(e => !/sha256:|@\d|message_routed/.test(e.en)), 'no identifiers in the catalogue');
  // every entry says where it appears; svg labels carry their width budget; snippets their limit
  for (const e of entries) assert.ok(e.where.length && e.where.every(Boolean), e.id);
  for (const e of entries.filter(e => e.kind === 'svg')) assert.ok(e.max > 0, `${e.en}: max`);
  // sentences in the drawing are templates with placeholders, never concatenations
  assert.deepEqual(byEn('{swarms} swarms · {agents} agents').placeholders, ['{agents}', '{swarms}']);
  assert.deepEqual(byEn('{n} declared').placeholders, ['{n}']);
  assert.deepEqual(byEn('Deploy, coordinate and control AI agents as separate, supervised processes.').limit, { chars: 150, cjk: 80 });
  assert.deepEqual(byEn('refused: over the {cap}-agent cap').placeholders, ['{cap}']);
});

test('the guard refuses a missing id and lists it', () => {
  const miss = byEn('Every agent is a process.').id;
  refused(pseudoBuild(['es'], (c, tx) => { delete tx[miss]; }), new RegExp(`es: ${miss} missing \\(story step 4`));
});
test('the guard refuses changed markup', () => {
  const id = byEn('Models provide intelligence.').id;
  refused(pseudoBuild(['ru'], (c, tx) => { tx[id] = `<em>${tx[id]}</em>`; }), new RegExp(`ru: ${id} markup differs`));
  const h1 = byEn('The operating system for AI&nbsp;workforces.').id;
  refused(pseudoBuild(['es'], (c, tx) => { tx[h1] = tx[h1] + '<br>'; }), new RegExp(`es: ${h1} markup differs`));
});
test('the guard refuses changed placeholders', () => {
  const id = byEn('{swarms} swarms · {agents} agents').id;
  refused(pseudoBuild(['ko'], (c, tx) => { tx[id] = tx[id].replace('{agents}', '{workers}'); }), new RegExp(`ko: ${id} placeholders differ`));
  const cap = byEn('refused: over the {cap}-agent cap').id;
  refused(pseudoBuild(['tr'], (c, tx) => { tx[cap] = tx[cap].replace('{cap}', '100'); }), new RegExp(`tr: ${cap} placeholders differ`));
});
test('the guard refuses a dropped protected name', () => {
  const id = byEn('How is it different from LangGraph, CrewAI or AutoGen?').id;
  refused(pseudoBuild(['ru'], (c, tx) => { tx[id] = tx[id].replace('LangGraph', 'ЛангГраф'); }), new RegExp(`ru: ${id} lost the protected name "LangGraph"`));
  const pkg = byEn('gsp and swarmidx: signed, content-addressed, checked on your machine.').id;
  refused(pseudoBuild(['zh-Hans'], (c, tx) => { tx[pkg] = tx[pkg].replace('gsp', 'GSP'); }), new RegExp(`${pkg} lost the protected name "gsp"`));
});
test('the guard refuses descriptions over 150 characters (80 in Chinese and Korean)', () => {
  const desc = byEn('GenSwarms runs AI agents as separate, supervised processes on declared message paths, with an API and a live event stream. Open source, MIT.').id;
  const og = byEn('Deploy, coordinate and control AI agents as separate, supervised processes.').id;
  refused(pseudoBuild(['es'], (c, tx) => { tx[desc] = tx[desc] + ' Ábíéŕţó.'.repeat(2); }), new RegExp(`es: ${desc} is 1[5-9]\\d characters, over the 150-character limit`));
  refused(pseudoBuild(['zh-Hans'], (c, tx) => { tx[og] = tx[og] + '的'.repeat(80); }), new RegExp(`zh-Hans: ${og} is \\d+ characters, over the 80-character limit`));
  // a ko description of 81 characters fails, 80 passes
  refused(pseudoBuild(['ko'], (c, tx) => { tx[desc] = 'GenSwarms MIT ' + '가'.repeat(67); }), /ko: .* 81 characters, over the 80-character limit/);
  assert.deepEqual(pseudoBuild(['ko'], (c, tx) => { tx[desc] = 'GenSwarms MIT ' + '가'.repeat(66); }).errors, []);
});
test('the guard refuses English left on a translated page', () => {
  // a string kept in English without saying so
  const id = byEn('Not everything needs a model.').id;
  refused(pseudoBuild(['tr'], (c, tx) => { tx[id] = 'Not everything needs a model.'; }), new RegExp(`tr: ${id} is still English`));
  // a translation near its own English is caught by validate() (see the fix-round tests); one that shows another
  // string's English (here the nav link "Security" as the "Guarantees" heading) only by the page check
  const h3 = byEn('Guarantees').id;
  refused(pseudoBuild(['es'], (c, tx) => { tx[h3] = 'Security'; }), /es: the built page still shows English: "Security"/);
  // and the words the drawing draws on its canvas count too (they travel in a JSON block, not in the markup)
  const cap = byEn('log of changes').id;
  refused(pseudoBuild(['ko'], (c, tx) => { tx[cap] = 'events (illustration)'; }), /ko: the built page still shows English: "events \(illustration\)"/);
  // listed under _same_as_english, it passes
  const docs = byEn('Docs').id;
  assert.deepEqual(pseudoBuild(['es'], (c, tx) => { tx[docs] = 'Docs'; tx._same_as_english = [docs]; }).errors, []);
});
test('the guard refuses an over-budget page', () => {
  const id = byEn('One agent is easy. Many agents working together need somewhere to run, rules for who talks to whom, and a way back when one fails.').id;
  refused(pseudoBuild(['es'], (c, tx) => { tx[id] = tx[id] + ' ñ'.repeat(30000); }), /es: es\/index\.html is \d+ bytes, over the 153600-byte budget/);
});

// the full pseudo build: all five languages
const full = pseudoBuild(LANGS.slice(1).map(l => l.code));
test('a full pseudo-locale build writes every version', () => {
  assert.deepEqual(full.errors, []);
  assert.deepEqual(Object.keys(full.outputs).sort(), ['404.html', 'es/index.html', 'index.html', 'ko/index.html', 'llms.txt', 'ru/index.html', 'sitemap.xml', 'tr/index.html', 'zh/index.html']);
  for (const [f, v] of Object.entries(full.outputs)) if (f.endsWith('.html')) assert.ok(Buffer.byteLength(v) < 153600, `${f} ${Buffer.byteLength(v)} bytes`);
});
test('every version has its own head: lang, canonical, reciprocal hreflang, og, content-language, JSON-LD', () => {
  const alts = [...LANGS.map(l => `<link rel="alternate" hreflang="${l.code}" href="${ORIGIN}${l.dir}">`), `<link rel="alternate" hreflang="x-default" href="${ORIGIN}">`];
  for (const l of LANGS) {
    const h = full.outputs[`${l.dir}index.html`], u = ORIGIN + l.dir;
    assert.match(h, new RegExp(`^<!doctype html>\\n<html lang="${l.code}">`));
    assert.ok(h.includes(`<link rel="canonical" href="${u}">`), `${l.code} canonical`);
    for (const a of alts) assert.ok(h.includes(a), `${l.code}: ${a}`);
    assert.equal((h.match(/rel="alternate" hreflang/g) || []).length, alts.length);
    assert.ok(h.includes(`<meta http-equiv="content-language" content="${l.code}">`));
    assert.ok(h.includes(`<meta property="og:locale" content="${l.og}">`));
    assert.ok(h.includes(`<meta property="og:url" content="${u}">`));
    assert.ok(h.includes(`<meta property="og:image" content="${ORIGIN}${ogFile(l)}">`));
    assert.ok(h.includes('<meta property="og:image:width" content="1200"><meta property="og:image:height" content="630">'), `${l.code} og:image size`);
    const ld = JSON.parse(h.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/)[1]);
    assert.equal(ld.inLanguage, l.code); assert.equal(ld.url, u); assert.equal(ld.name, 'GenSwarms');
    const title = h.match(/<title>([^<]+)<\/title>/)[1], desc = h.match(/<meta name="description" content="([^"]+)"/)[1];
    assert.ok(h.includes(`<meta property="og:title" content="${title}">`));
    assert.ok(h.includes(`<meta property="og:image:alt" content="${title}">`), `${l.code} og:image:alt is the page title`);
    if (l.code !== 'en') {
      assert.notEqual(title, 'GenSwarms: the operating system for AI workforces');
      assert.notEqual(ld.description, JSON.parse(full.outputs['index.html'].match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/)[1]).description);
    }
    assert.ok([...desc].length <= (l.code === 'ko' || l.code === 'zh-Hans' ? 80 : 150), `${l.code} description`);
    // switching: the picker and the footer mark this version; links carry hreflang and lang
    assert.match(h, new RegExp(`<details class="lang"><summary><span class="sr">[^<]+ </span>${l.short}</summary>`));
    assert.ok(h.includes(`<li><a href="/${l.dir}" hreflang="${l.code}" lang="${l.code}" aria-current="page">${l.name}</a></li>`), `${l.code} picker`);
    const foot = h.match(/<nav class="foot-langs"[^>]*>([\s\S]*?)<\/nav>/)[1];
    assert.equal((foot.match(/<a /g) || []).length, LANGS.length);
    assert.equal((foot.match(/aria-current="page"/g) || []).length, 1);
    assert.ok(foot.includes(`<a href="/${l.dir}" hreflang="${l.code}" lang="${l.code}" aria-current="page">`));
    // the suggestion bar's strings for every language, in each language
    const bar = JSON.parse(h.match(/<script type="application\/json" id="langbar">([\s\S]*?)<\/script>/)[1]);
    assert.deepEqual(Object.keys(bar), LANGS.map(x => x.code));
    for (const x of LANGS) assert.equal(bar[x.code].href, '/' + x.dir);
    assert.equal(bar.en.msg, 'This page is also available in English.');
    assert.notEqual(bar.es.msg, bar.en.msg);
    // one folder deeper, every path still works: only absolute paths, full URLs and in-page anchors
    for (const m of h.matchAll(/\s(?:href|src)="([^"]*)"/g)) assert.match(m[1], /^(\/|#|https:\/\/)/, `${l.code}: ${m[1]}`);
    // anchors point at ids on the page
    for (const m of h.matchAll(/href="#([^"]+)"/g)) assert.ok(h.includes(`id="${m[1]}"`), `${l.code}: #${m[1]}`);
  }
});
const plain = s => s.replace(/<[^>]+>/g, '').replace(/&nbsp;/g, ' ');
test('each version has its own share card: the translated headline, the organization drawn by the page’s engine, no buttons', () => {
  const tables = Object.fromEntries(LANGS.slice(1).map(l => [l.code, pseudo(l.code, entries)]));
  for (const l of LANGS) {
    const c = full.cards[ogKey(l)];
    const tr = en => (l.code === 'en' ? en : tables[l.code][sid(en)] || en);
    assert.match(c, new RegExp(`^<!doctype html>\\n<html lang="${l.code}">`));
    assert.equal(plain(c.match(/<p class="og-h">([\s\S]*?)<\/p>/)[1]), plain(tr('The operating system for AI&nbsp;workforces.')), `${l.code} headline`);
    assert.equal(c.match(/<p class="og-foot"><b>genswarms\.com<\/b><i><\/i>([^<]+)<\/p>/)[1], tr('Open source, MIT'), `${l.code} footer`);
    // the zoom caption over the drawing, with the organization's numbers formatted for the language
    const cap = [...c.match(/<p class="og-cap">([\s\S]*?)<\/p>/)[1].matchAll(/<span>([^<]*)<\/span>/g)].map(m => m[1]);
    assert.equal(cap[0], tr('organization'), `${l.code} caption`);
    assert.equal(cap[1], tr('{swarms} swarms · {agents} agents').replace('{swarms}', '36').replace('{agents}', new Intl.NumberFormat(l.code).format(2861)), `${l.code} counts`);
    assert.match(c, /<div class="og-fig"><canvas><\/canvas>/);
    assert.ok(c.includes('Z.build(') && c.includes('Z.draw(g,st)'), `${l.code}: drawn by the page's engine`);
    // a card, not a page: no buttons, links or page chrome
    assert.doesNotMatch(c, /<a[\s>]|<button|class="btn|class="ctas|<nav|<header|<footer/, `${l.code} card has page chrome`);
    // the page's type for that writing system
    assert.ok(c.includes(`<link href="${full.pages[l.code].match(/<link href="(https:\/\/fonts[^"]+)"/)[1]}" rel="stylesheet">`), `${l.code} fonts`);
    assert.ok(c.includes(`width:${CARD.w}px;height:${CARD.h}px`));
  }
  // a hyphenated compound (Russian «ИИ-персонала») stays whole on the card (a break after its hyphen reads as hyphenation)
  const ru = pseudoBuild(['ru'], (c, tx) => { tx[sid('The operating system for AI&nbsp;workforces.')] = 'Операционная система для ИИ-персонала.'; });
  assert.match(ru.cards.ru, /<span class="nw">ИИ-персонала\.<\/span>/);
});

test('each writing system gets its fonts, and loads only the Google fonts it uses', () => {
  const o = full.outputs;
  const ALL = /<link href="https:\/\/fonts\.googleapis\.com\/css2\?family=Geist\+Mono:wght@400\.\.600&family=Geist:wght@400\.\.600&display=swap" rel="stylesheet" media="print"/;
  // Geist and Geist Mono cover Latin (Turkish too) and Cyrillic
  for (const f of ['index.html', 'es/index.html', 'tr/index.html', 'ru/index.html']) assert.match(o[f], ALL, f);
  // Korean and Chinese: Geist Mono only (the wordmark, identifiers, readouts, the drawing), the rest in system faces
  for (const f of ['ko/index.html', 'zh/index.html']) {
    assert.doesNotMatch(o[f], /family=Geist:/, f);
    assert.match(o[f], /<link href="https:\/\/fonts\.googleapis\.com\/css2\?family=Geist\+Mono:wght@400\.\.600&display=swap" rel="stylesheet" media="print"/, f);
  }
  assert.match(o['ko/index.html'], /--fh:'Apple SD Gothic Neo','Noto Sans KR','Malgun Gothic',sans-serif/);
  assert.match(o['ko/index.html'], /--fc:'Geist Mono','Apple SD Gothic Neo','Noto Sans KR','Malgun Gothic',monospace/);
  assert.match(o['ko/index.html'], /word-break:keep-all/);
  assert.match(o['zh/index.html'], /--fs:'PingFang SC','Hiragino Sans GB','Noto Sans SC','Microsoft YaHei',sans-serif/);
  for (const f of ['ko/index.html', 'zh/index.html']) assert.match(o[f], /h1,h2,h3,\.triad span,\.spec dt,\.cmp tbody th\{letter-spacing:0\}/, f);
  for (const f of ['ru/index.html', 'tr/index.html']) assert.match(o[f], /hyphens:auto/, f);
  // Spanish: no Korean line breaking and no title hyphenation. The comparison table's cells never hyphenate (brand names
  // broke as "Gen-Swarms"): their long words only break when a column is narrower than the word
  assert.doesNotMatch(o['es/index.html'], /keep-all|\.cmp tbody th\{hyphens:auto/);
  for (const f of ['es/index.html', 'ru/index.html', 'tr/index.html']) {
    assert.match(o[f], /\.cmp th,\.cmp td\{overflow-wrap:break-word\}/, f);
    // nor do its heads, its row questions or its heading in Russian and Turkish ("Lang-Graph", "Auto-Gen'den")
    assert.doesNotMatch(o[f], /(\.cmp|#cmp-h)[^{}]*\{[^}]*hyphens:auto/, f);
  }
});
test('the sitemap lists every version with the full set of alternates', () => {
  const s = full.outputs['sitemap.xml'];
  assert.match(s, /xmlns:xhtml="http:\/\/www\.w3\.org\/1999\/xhtml"/);
  const urls = [...s.matchAll(/<url>([\s\S]*?)<\/url>/g)].map(m => m[1]);
  assert.deepEqual(urls.map(u => u.match(/<loc>([^<]+)<\/loc>/)[1]), LANGS.map(l => ORIGIN + l.dir));
  for (const u of urls) {
    for (const l of LANGS) assert.ok(u.includes(`<xhtml:link rel="alternate" hreflang="${l.code}" href="${ORIGIN}${l.dir}"/>`));
    assert.ok(u.includes(`<xhtml:link rel="alternate" hreflang="x-default" href="${ORIGIN}"/>`));
  }
});
test('404 and llms.txt: one 404 for every language, llms.txt stays English with one line of versions', () => {
  const nf = full.outputs['404.html'];
  const L404 = JSON.parse(nf.match(/var L=(\{[\s\S]*?\});/)[1]);
  assert.deepEqual(Object.keys(L404).sort(), ['es', 'ko', 'ru', 'tr', 'zh']);
  assert.equal(L404.zh.lang, 'zh-Hans'); assert.equal(L404.es.home, '/es/');
  for (const k of ['title', 'code', 'h1', 'p', 'back', 'docs']) assert.ok(L404.ko[k] && L404.ko[k] !== L404.es[k], k);
  assert.ok(nf.includes('<h1>This page ran off the swarm.</h1>'), 'English stays in the markup');
  // the committed llms.txt carries the versions line once; without it, it is the English original
  const llms = full.outputs['llms.txt'], base = readFileSync(new URL('llms.txt', WEB), 'utf8').replace(/^Language versions of this page:.*\n/m, '');
  assert.equal(llms.split('\n').length, base.split('\n').length + 1);
  assert.match(llms, /^Language versions of this page: English https:\/\/genswarms\.com\/, Español https:\/\/genswarms\.com\/es\/, .*Türkçe https:\/\/genswarms\.com\/tr\/\.$/m);
});
test('the English page does not change: only the language additions', () => {
  const alone = renderPage();
  // strip the intended additions from a multilingual English page: it is the English-only page again
  const strip = html => html
    .replace(/\n<link rel="alternate" hreflang="[^"]+" href="[^"]+">/g, '')
    .replace(/,"inLanguage":"en"/, '')
    .replace(/\n<details class="lang">[\s\S]*?<\/details>/, '')
    .replace(/\n<nav class="foot-langs"[\s\S]*?<\/nav>/, '')
    .replace(/\n<script type="application\/json" id="langbar">[\s\S]*?<\/script>\n<script>[\s\S]*?<\/script>/, '')
    .replace(/(<style>[\s\S]*?)\n\/\* ---------- languages[\s\S]*?(<\/style>)/, '$1$2')
    .replace(/\n\.lang\{[\s\S]*?(\n<\/style>)/, '$1');
  const pages = [['pseudo build', full.outputs['index.html']]];
  // and the committed page
  pages.push(['committed page', readFileSync(new URL('index.html', WEB), 'utf8')]);
  for (const [name, html] of pages) {
    assert.equal(strip(html), alone.replace(/\n<\/style>/, '\n</style>'), name);
    // and every English text run is unchanged
    assert.deepEqual([...textRuns(html)].filter(r => r !== 'Language').sort(), [...textRuns(alone)].sort(), name);
  }
});
test('the drawing’s words travel with the page: a JSON block in the page’s language, numbers formatted there', () => {
  const zs = h => JSON.parse(h.match(/<script type="application\/json" id="zoom-strings">([\s\S]*?)<\/script>/)[1]);
  const en = zs(full.outputs['index.html']);
  for (const l of LANGS.slice(1)) {
    const z = zs(full.outputs[`${l.dir}index.html`]), tx = pseudo(l.code, entries);
    assert.equal(z.cine, en.cine);
    for (const k of Object.keys(en).filter(k => k !== 'cine')) {
      const a = [].concat(en[k]), b = [].concat(z[k]);
      assert.equal(b.length, a.length, `${l.code} ${k}`);
      a.forEach((s, i) => assert.equal(b[i], tx[sid(s)], `${l.code} ${k}[${i}]`));
    }
    // the canvas's first text alternative is on the canvas itself
    assert.ok(full.outputs[`${l.dir}index.html`].includes(`<canvas role="img" aria-label="${z.aria[0].replace(/"/g, '&quot;')}">`), l.code);
  }
  // long labels: the catalogue gives each a width budget, and the drawing measures, wraps and fits them in any script
  for (const s of ['refused: over the {cap}-agent cap', 'restores from its database']) assert.equal(byEn(s).lines, 2, s);
  for (const s of ['supervisor', 'process', 'sandbox', 'dropped', 'model calls']) assert.equal(byEn(s).lines, 1, s);
  const run = readFileSync(new URL('src/zoom-run.js', WEB), 'utf8');
  assert.match(run, /function wrap\(s, maxW, font\)/);
  assert.match(run, /function fitL\(rect, sf, items, pad\)/);
});
test('--check verifies the outputs, the lock and the share images', () => {
  const d = tmp(), out = join(d, 'site'), i18n = join(d, 'i18n');
  mkdirSync(out);
  writePseudo(i18n, ['es', 'ko']);
  const r = build({ i18nDir: url(i18n), outDir: url(out) });
  assert.deepEqual(r.errors, []);
  for (const [f, v] of Object.entries(r.outputs)) { mkdirSync(join(out, f, '..'), { recursive: true }); writeFileSync(join(out, f), v); }
  writeFileSync(join(i18n, 'build.lock.json'), JSON.stringify(r.lock));
  const sha = b => createHash('sha256').update(b).digest('hex');
  const og = {};
  for (const l of r.langs) { const png = Buffer.from('png ' + l.code); writeFileSync(join(out, ogFile(l)), png); og[ogKey(l)] = { source: ogSource(r.cards[ogKey(l)]), png: sha(png) }; }
  writeFileSync(join(i18n, 'og.lock.json'), JSON.stringify(og));
  const ck = () => check({ i18nDir: url(i18n), outDir: url(out) });
  assert.deepEqual(ck(), []);
  // a hand-edited page
  writeFileSync(join(out, 'es/index.html'), r.outputs['es/index.html'].replace('</body>', '<!-- edit --></body>'));
  assert.match(ck().join('\n'), /website\/es\/index\.html is stale/);
  writeFileSync(join(out, 'es/index.html'), r.outputs['es/index.html']);
  // a translation changed after the build
  const tx = JSON.parse(readFileSync(join(i18n, 'ko.json'), 'utf8'));
  tx[entries[0].id] = 'GenSwarms 다른 제목';
  writeFileSync(join(i18n, 'ko.json'), JSON.stringify(tx));
  assert.match(ck().join('\n'), /ko\/index\.html is stale[\s\S]*build\.lock\.json does not match i18n\/ko\.json/);
  writePseudo(i18n, ['ko']);
  assert.deepEqual(ck(), []);
  // a lock from another build
  writeFileSync(join(i18n, 'build.lock.json'), JSON.stringify({ ...r.lock, source: 'x' }));
  assert.match(ck().join('\n'), /build\.lock\.json does not match the English source/);
  writeFileSync(join(i18n, 'build.lock.json'), JSON.stringify(r.lock));
  // a share image edited, or rendered from another card
  writeFileSync(join(out, 'og-es.png'), 'other');
  assert.match(ck().join('\n'), /og-es\.png changed since tools\/og\.cjs rendered it/);
  writeFileSync(join(out, 'og-es.png'), 'png es');
  writeFileSync(join(i18n, 'og.lock.json'), JSON.stringify({ ...og, ko: { ...og.ko, source: 'old' } }));
  assert.match(ck().join('\n'), /og-ko\.png shows an old card/);
  writeFileSync(join(i18n, 'og.lock.json'), JSON.stringify(og));
  assert.deepEqual(ck(), []);
  // a new triad line: the pages are rebuilt (build.lock.json too) but the image was not re-rendered, so only the
  // share image of that language is stale
  const kicker = byEn('The operating system for AI&nbsp;workforces.').id, es = JSON.parse(readFileSync(join(i18n, 'es.json'), 'utf8'));
  es[kicker] = 'El sistema operativo para equipos de&nbsp;IA.';
  writeFileSync(join(i18n, 'es.json'), JSON.stringify(es));
  const r2 = build({ i18nDir: url(i18n), outDir: url(out) });
  assert.deepEqual(r2.errors, []);
  for (const [f, v] of Object.entries(r2.outputs)) writeFileSync(join(out, f), v);
  writeFileSync(join(i18n, 'build.lock.json'), JSON.stringify(r2.lock));
  assert.ok(r2.cards.es.includes('<p class="og-h">El sistema operativo para equipos de&nbsp;IA.</p>'));
  assert.deepEqual(ck(), ['website/og-es.png shows an old card (or was never rendered): run `node website/tools/og.cjs`']);
  // and so does a change to the card template alone (here: its CSS), with every page unchanged
  assert.ok(r2.cards.en.includes('.og-foot b{font-weight:500;color:var(--ink)}'));
  assert.notEqual(ogSource(r2.cards.en.replace('.og-foot b{font-weight:500;color:var(--ink)}', '.og-foot b{font-weight:600;color:var(--ink)}')), r2.lock.og.en.source);
  rmSync(d, { recursive: true, force: true });
});
test('the committed site passes --check', () => {
  assert.deepEqual(check({ i18nDir: new URL('i18n/', WEB), outDir: WEB }), []);
});
test('pseudo-locales keep what must not change', () => {
  for (const l of LANGS.slice(1)) {
    const tx = pseudo(l.code, entries);
    for (const e of entries) {
      assert.notEqual(tx[e.id], e.en, `${l.code} ${e.en}`);
      for (const n of PROTECT) if (e.en.includes(n) && new RegExp(`(^|[^\\w])${n.replace('.', '\\.')}($|[^\\w])`).test(e.en)) assert.ok(tx[e.id].includes(n), `${l.code} ${n}`);
    }
  }
});

test('--verify checks a served site: 200s, slash redirects, lang, title, canonical, hreflang', async () => {
  const pages = full.outputs;
  const serve = (redirect, patch = h => h) => new Promise(res => {
    const srv = createServer((req, r) => {
      const u = req.url;
      const l = LANGS.find(x => x.dir && u === '/' + x.dir.replace(/\/$/, ''));
      if (l) { if (redirect) { r.writeHead(301, { Location: u + '/' }); return r.end(); } r.writeHead(200); return r.end(patch(pages[`${l.dir}index.html`])); }
      const f = u === '/' ? 'index.html' : u.slice(1).replace(/\/$/, '/index.html');
      if (pages[f] != null) { r.writeHead(200); return r.end(f.endsWith('.html') ? patch(pages[f]) : pages[f]); }
      if (/^\/(robots\.txt|og-[\w-]+\.png)$/.test(u)) { r.writeHead(200); return r.end('x'); }
      r.writeHead(404); r.end();
    }).listen(0, '127.0.0.1', () => res(srv));
  });
  let srv = await serve(true);
  let r = await verify(`http://127.0.0.1:${srv.address().port}/`, LANGS);
  assert.deepEqual(r.bad, []);
  assert.equal(r.log.length, LANGS.length);
  srv.close();
  // /es serving the page instead of redirecting (relative paths would break), and a wrong canonical
  srv = await serve(false, h => h.replace('<link rel="canonical" href="https://genswarms.com/ko/">', '<link rel="canonical" href="https://genswarms.com/">'));
  r = await verify(`http://127.0.0.1:${srv.address().port}/`, LANGS);
  srv.close();
  assert.ok(r.bad.some(b => /^\/es does not redirect to \/es\/ \(200, /.test(b)), r.bad.join('\n'));
  assert.ok(r.bad.some(b => /^ko\/ canonical is https:\/\/genswarms\.com\/$/.test(b)), r.bad.join('\n'));
});

// ---------- fix round 1: near-English, _same_as_english, tag order, escaping, lastmod ----------
const idOf = en => byEn(en).id;
test('_same_as_english is only for figure labels, accessible names and strings of up to 3 words', () => {
  const sentence = idOf('Every agent is a process.');
  refused(pseudoBuild(['es'], (c, tx) => { tx[sentence] = 'Every agent is a process.'; tx._same_as_english = [sentence]; }), new RegExp(`es: ${sentence} cannot be listed under _same_as_english`));
  const ld = idOf('The operating system for AI workforces: runs AI agents as separate, supervised processes on declared message paths, with a REST + WebSocket API and a live event stream.');
  refused(pseudoBuild(['tr'], (c, tx) => { tx[ld] = byEn('The operating system for AI workforces: runs AI agents as separate, supervised processes on declared message paths, with a REST + WebSocket API and a live event stream.').en; tx._same_as_english = [ld]; }), new RegExp(`${ld} cannot be listed`));
  // a short string, a figure label and an accessible name may be
  const ok = ['Docs', 'model calls', 'Primary'].map(idOf);
  assert.deepEqual(pseudoBuild(['es'], (c, tx) => { for (const i of ok) tx[i] = entries.find(e => e.id === i).en; tx._same_as_english = ok; }).errors, []);
  // the drawing's short labels may be kept in English too (they are checked in its JSON block)
  const ann = ['supervisor', 'process', 'sandbox'].map(idOf);
  assert.deepEqual(pseudoBuild(['ru'], (c, tx) => { for (const i of ann) tx[i] = entries.find(e => e.id === i).en; tx._same_as_english = ann; }).errors, []);
});
test('non-Latin scripts: three English words in a row are English left behind', () => {
  const id = idOf('Not everything needs a model.');
  refused(pseudoBuild(['ru'], (c, tx) => { tx[id] = 'Не всё needs a model.'; }), new RegExp(`ru: ${id} still has English in it \\("needs a model"\\)`));
  refused(pseudoBuild(['zh-Hans'], (c, tx) => { tx[id] = '并非everything needs a模型。'; }), new RegExp(`zh-Hans: ${id} still has English in it \\("everything needs a"\\)`));
  refused(pseudoBuild(['ko'], (c, tx) => { tx[id] = 'Not everything needs 모델이.'; }), new RegExp(`ko: ${id} still has English`));
  // false-positive guard: product names, protected names and a couple of English terms between Cyrillic or Han words
  const cells = {
    'In your Python or JS process, or on LangSmith Deployment servers': ['В вашем процессе Python или JS либо на серверах LangSmith Deployment', '在你的 Python 或 JS 进程中，或在 LangSmith Deployment 服务器上'],
    'Multi-agent framework, now in maintenance mode; Microsoft Agent Framework succeeds it': ['Мультиагентный фреймворк, сейчас в режиме поддержки; на смену ему пришёл Microsoft Agent Framework', '多智能体框架，现处于维护模式；Microsoft Agent Framework 接替了它'],
    'In your Python process, or on CrewAI AMP managed infrastructure': ['В вашем процессе Python или в управляемой инфраструктуре CrewAI AMP', '在你的 Python 进程中，或在 CrewAI AMP 托管基础设施上'],
    'Telegram, WhatsApp and email connectors, a browser, a scheduler: signed packages from the swarmidx index, verified before they load.': ['Коннекторы Telegram, WhatsApp и email, браузер, планировщик: подписанные пакеты из индекса swarmidx, проверенные перед загрузкой.', 'Telegram、WhatsApp 和 email 连接器、浏览器、调度器：来自 swarmidx 索引的签名包，加载前经过验证。'],
  };
  const [ru, zh] = [0, 1].map(k => pseudoBuild([k ? 'zh-Hans' : 'ru'], (c, tx) => { for (const [en, v] of Object.entries(cells)) tx[idOf(en)] = v[k]; }));
  assert.deepEqual(ru.errors, []); assert.deepEqual(zh.errors, []);
});
test('Latin scripts: a translation made mostly of the English words is refused', () => {
  const id = idOf('Every agent is a process.');
  refused(pseudoBuild(['es'], (c, tx) => { tx[id] = 'Every agent es a process.'; }), new RegExp(`es: ${id} is mostly English \\(4 of 5 words`));
  refused(pseudoBuild(['tr'], (c, tx) => { tx[id] = 'Every agent is a process!'; }), new RegExp(`tr: ${id} is mostly English`));
  // false-positive guard: names, identifiers and a few shared words (local, sandbox, skill, Python) stay well under 80%
  const cells = {
    'Each in its own supervised process: local, sandbox, container or SSH': 'Cada uno en su propio proceso supervisado: local, sandbox, contenedor o SSH',
    'In your Python or JS process, or on LangSmith Deployment servers': 'En tu proceso de Python o JS, o en servidores de LangSmith Deployment',
    'REST, WebSocket, CLI, and a skill file for your coding agent.': 'REST, WebSocket, CLI y un archivo de skill para tu agente de programación.',
    'bwrap, Docker or Apple container, per agent.': 'bwrap, Docker o Apple container, por agente.',
    'GenSwarms compared with LangGraph, CrewAI and AutoGen': 'GenSwarms frente a LangGraph, CrewAI y AutoGen',
  };
  assert.deepEqual(pseudoBuild(['es'], (c, tx) => { for (const [en, v] of Object.entries(cells)) tx[idOf(en)] = v; }).errors, []);
  // a string of names only has no words to compare, and may be listed as it is
  const names = { id: 'n0', kind: 'html', en: 'Local, Tmux, Docker, Apple container, SSH, Bwrap, Mock', where: ['x'] };
  assert.deepEqual(validate('es', [names], { n0: names.en, _same_as_english: ['n0'] }), []);
  assert.deepEqual(validate('ru', [names], { n0: names.en, _same_as_english: ['n0'] }), []);
});
test('tags must keep their nesting, and html text escapes & and refuses a bare <', () => {
  const e = { id: 'c1', kind: 'html', en: 'Use <code>gsp</code> to <em>publish</em>.', where: ['x'] };
  assert.deepEqual(validate('es', [e], { c1: 'Usa <code>gsp</code> para <em>publicar</em>.' }), []);
  assert.deepEqual(validate('es', [e], { c1: 'Para <em>publicar</em>, usa <code>gsp</code>.' }), [], 'reordering whole elements is fine');
  assert.match(validate('es', [e], { c1: 'Usa </code>gsp<code> para <em>publicar</em>.' }).join(), /c1 tags are out of order/);
  assert.match(validate('es', [e], { c1: 'Usa <code>gsp</code> para <em>publicar</em> si a < b.' }).join(), /c1 has a bare < or >/);
  const id = idOf('Not everything needs a model.');
  const r = pseudoBuild(['es'], (c, tx) => { tx[id] = 'No todo necesita un modelo de I&D.'; });
  assert.deepEqual(r.errors, []);
  assert.ok(r.outputs['es/index.html'].includes('No todo necesita un modelo de I&amp;D.'));
});
test('sitemap lastmod: a page keeps its date until its output changes', () => {
  const d = tmp(), out = join(d, 'site'), i18n = join(d, 'i18n');
  mkdirSync(out);
  writePseudo(i18n, ['es', 'ko']);
  const run = today => {
    const r = build({ i18nDir: url(i18n), outDir: url(out), today });
    assert.deepEqual(r.errors, []);
    for (const [f, v] of Object.entries(r.outputs)) { mkdirSync(join(out, f, '..'), { recursive: true }); writeFileSync(join(out, f), v); }
    writeFileSync(join(i18n, 'build.lock.json'), JSON.stringify(r.lock));
    return r;
  };
  const dates = r => Object.fromEntries([...r.outputs['sitemap.xml'].matchAll(/<loc>([^<]+)<\/loc>\s*<lastmod>([^<]+)</g)].map(m => [m[1], m[2]]));
  const a = run('2026-10-01');
  assert.deepEqual(Object.values(dates(a)), ['2026-10-01', '2026-10-01', '2026-10-01']);
  assert.deepEqual(a.lock.lastmod, { 'index.html': '2026-10-01', 'es/index.html': '2026-10-01', 'ko/index.html': '2026-10-01' });
  // nothing changed: the same dates on a later day, so --check on another day still passes
  assert.deepEqual(dates(run('2026-10-05')), dates(a));
  // a changed Korean string moves only the Korean page
  const tx = JSON.parse(readFileSync(join(i18n, 'ko.json'), 'utf8'));
  tx[idOf('Not everything needs a model.')] = '모든 것에 모델이 필요한 것은 아닙니다.';
  writeFileSync(join(i18n, 'ko.json'), JSON.stringify(tx));
  assert.deepEqual(dates(run('2026-10-09')), { [ORIGIN]: '2026-10-01', [ORIGIN + 'es/']: '2026-10-01', [ORIGIN + 'ko/']: '2026-10-09' });
  rmSync(d, { recursive: true, force: true });
});
