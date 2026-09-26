// The translation catalogue (playbook §6-7, §11). English in the sources is the single source: every string the
// page shows or announces goes through t() at build time. Rendering in English with a recorder attached yields
// the catalogue (website/i18n/en.json); rendering with a language table yields that language's page.
import { createHash } from 'node:crypto';

export const ORIGIN = 'https://genswarms.com/';
// code (html lang, hreflang), folder, translation file, og:locale, native name, picker code
export const LANGS = [
  { code: 'en', dir: '', file: null, og: 'en_US', name: 'English', short: 'EN' },
  { code: 'es', dir: 'es/', file: 'es', og: 'es_ES', name: 'Español', short: 'ES' },
  { code: 'ko', dir: 'ko/', file: 'ko', og: 'ko_KR', name: '한국어', short: 'KO' },
  { code: 'zh-Hans', dir: 'zh/', file: 'zh', og: 'zh_CN', name: '简体中文', short: 'ZH' },
  { code: 'ru', dir: 'ru/', file: 'ru', og: 'ru_RU', name: 'Русский', short: 'RU' },
  { code: 'tr', dir: 'tr/', file: 'tr', og: 'tr_TR', name: 'Türkçe', short: 'TR' },
];
export const CJK = new Set(['ko', 'zh-Hans']);
// search and social snippets: at most 150 characters, 80 in Chinese and Korean
export const SNIPPET = { chars: 150, cjk: 80 };

// Names a translation must carry over verbatim whenever the English has them.
export const PROTECT = ['GenSwarms', 'LangGraph', 'CrewAI', 'AutoGen', 'GitHub', 'OTP', 'bwrap', 'Docker', 'Apple container', 'SSH',
  'Tmux', 'Bwrap', 'Mock', 'Local', 'REST', 'WebSocket', 'CLI', 'gsp', 'swarmidx', 'Telegram', 'WhatsApp', 'skill.md', 'MIT', '0.2.0',
  'Microsoft Agent Framework', 'LangSmith', 'AMP'];
// Keep list: never catalogued, the same on every page. Product and company names, language names, file names, and
// the identifiers drawn in the figures (agent and object names, event kinds, document keys, package refs).
export const KEEP = new Set(['GenSwarms', 'LangGraph', 'CrewAI', 'AutoGen', 'GitHub', 'GenLayer Labs', 'MIT', 'skill.md', 'llms.txt',
  ...LANGS.map(l => l.name), ...LANGS.map(l => l.short),
  'Local', 'Tmux', 'Docker', 'Apple container', 'SSH', 'Bwrap', 'Mock',
  'telegram', 'triage', 'answer', 'research', 'cron', 'budget', 'browser', 'agents', 'objects', 'edges',
  'message_routed', 'invalid_route', 'add_agent', 'scale_agent_group', 'swarm.state', 'swarm.overlay']);

// A text run that is only names, identifiers and numbers (e.g. "telegram → triage", "genlayerlabs/cron@0.2.8") is
// the same in every language.
export function isKept(run) {
  const s = run.replace(/\s+/g, ' ').trim();
  if (!s || !/\p{L}/u.test(s) || KEEP.has(s)) return true;
  const rest = [...KEEP].filter(k => k.includes(' ')).reduce((r, k) => r.split(k).join(' '), s).replace(/sha256:[0-9a-f]+…?/g, ' ');
  return rest.split(/[\s,→…:+·()]+/).every(w => !w || KEEP.has(w) || /[_.@/]|^sha256|^\d/.test(w) || !/\p{L}/u.test(w));
}

// Catalogue ids are a hash of the English: an edited sentence gets a new id, so it shows up as untranslated.
export const sid = s => createHash('sha1').update(s).digest('hex').slice(0, 8);
export const placeholders = s => (s.match(/\{\w+\}/g) || []).sort();
export const tagsOf = s => (s.match(/<[^>]+>/g) || []).sort();

// ---------- the lookup ----------
let ctx = { lang: 'en', table: null, rec: null };
// run fn with a language table (null = English) and optionally a recorder (a Map, filled in first-use order)
export function withLang({ lang = 'en', table = null, rec = null } = {}, fn) {
  const prev = ctx;
  ctx = { lang, table, rec };
  try { return fn(); } finally { ctx = prev; }
}
// t(english, where, { kind, max, lines, limit }) -> the text for the current language.
//   kind   meta | html | attr | svg | js | 404 (html is an element's inner HTML, inline tags included)
//   max    svg labels: characters that fit on one line (the English width budget); lines: how many it may wrap to
//   limit  a hard character limit: { chars, cjk } (search snippets: 150, and 80 in Chinese and Korean)
export function t(en, where, o = {}) {
  if (ctx.rec) record(en, where, o);
  if (!ctx.table) return en;
  const v = ctx.table[sid(en)];
  if (typeof v !== 'string' || !v.trim()) return en;
  // inner HTML: a translator's bare & becomes &amp; (a stray < or > is refused by validate())
  return (o.kind || 'html') === 'html' ? v.trim().replace(/&(?![a-z]+;|#\d+;)/gi, '&amp;') : v.trim();
}
export const fill = (s, vars) => s.replace(/\{(\w+)\}/g, (m, k) => (k in vars ? String(vars[k]) : m));
// sentence templates, never concatenation (§7): tf('Step {n}: {title}', { n, title }, where)
export const tf = (en, vars, where, o) => fill(t(en, where, o), vars);
export const escAttr = s => s.replace(/&(?![a-z]+;|#\d+;)/g, '&amp;').replace(/"/g, '&quot;');
export const escText = s => s.replace(/&(?![a-z]+;|#\d+;)/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

function record(en, where, o) {
  let e = ctx.rec.get(en);
  if (!e) {
    e = { id: sid(en), kind: o.kind || 'html', en, where: [] };
    const ph = placeholders(en);
    if (ph.length) e.placeholders = [...new Set(ph)];
    ctx.rec.set(en, e);
  }
  if (where && !e.where.includes(where)) e.where.push(where);
  if (o.max != null) e.max = Math.min(e.max ?? Infinity, o.max);
  if (o.lines != null) e.lines = Math.min(e.lines ?? Infinity, o.lines);
  if (o.limit != null) e.limit = o.limit;
}

// ---------- validation of one translation file ----------
// tags must nest the way HTML needs them to (the multiset check alone would pass `</code>…<code>`)
const VOID = new Set(['br', 'wbr', 'img', 'hr']);
function nests(s) {
  const open = [];
  for (const [, close, name, self] of s.matchAll(/<(\/?)([a-z][\w-]*)[^>]*?(\/?)>/gi)) {
    if (self || VOID.has(name.toLowerCase())) continue;
    if (!close) open.push(name.toLowerCase());
    else if (open.pop() !== name.toLowerCase()) return false;
  }
  return !open.length;
}
// Words a translation could have copied from the English. Tags, entities, placeholders, URLs, protected and keep-list
// names and identifiers (anything with a digit, _, @ or /) are cut out, each leaving a break ('|'), so a run of words
// never joins across a name such as "LangSmith Deployment".
// (the figures' lowercase identifiers, such as `browser` or `answer`, are ordinary words in prose: they stay)
const NAME_RES = [...new Set([...PROTECT, ...[...KEEP].filter(n => !/^[a-z]+$/.test(n))])].filter(n => /\p{L}/u.test(n)).sort((a, b) => b.length - a.length)
  .map(n => new RegExp(`(?<![\\p{L}\\w])${n.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}(?![\\p{L}\\w])`, 'gu'));
function stripNames(s) {
  let x = decode(s.replace(/<[^>]+>/g, ' ')).replace(/\{\w+\}|https?:\/\/\S+/g, ' | ');
  for (const re of NAME_RES) x = x.replace(re, ' | ');
  return x.replace(/\S*[\d_@/]\S*/g, ' | ');
}
// ASCII-Latin words, with every other script and every cut-out name as a break
const latinTokens = s => (stripNames(s).match(/[A-Za-z]+(?:['’-][A-Za-z]+)*|[^\P{L}A-Za-z]+|\|/gu) || []).map(w => w.toLowerCase());
function latinTrigrams(s) {
  const out = new Set();
  let run = [];
  for (const w of latinTokens(s)) {
    if (/^[a-z]/.test(w)) run.push(w); else run = [];
    if (run.length >= 3) out.add(run.slice(-3).join(' '));
  }
  return out;
}
// (names and identifiers don't count: a string of product names alone has no words to translate)
const words = s => (stripNames(s).match(/\p{L}+(?:['’-]\p{L}+)*/gu) || []).map(w => w.toLowerCase());
// scripts that are not Latin: any run of three English words left in them is English left behind
const NON_LATIN = new Set(['ko', 'zh-Hans', 'ru']);
// Every id present, markup and placeholders kept, protected names untouched, snippets short enough, nothing left in
// English unless the file says so.
export function validate(code, entries, tx) {
  const errs = [];
  const same = new Set(tx._same_as_english || []);
  for (const e of entries) {
    const v = tx[e.id];
    const tr = typeof v === 'string' ? v.trim() : '';
    if (!tr) { errs.push(`${e.id} missing (${e.where[0]}): ${e.en.slice(0, 70)}`); continue; }
    if (tagsOf(tr).join('') !== tagsOf(e.en).join(''))
      errs.push(`${e.id} markup differs: ${JSON.stringify(tagsOf(e.en))} vs ${JSON.stringify(tagsOf(tr))}`);
    else if (nests(e.en) && !nests(tr)) errs.push(`${e.id} tags are out of order: ${JSON.stringify(tr.match(/<[^>]+>/g))}`);
    if (e.kind === 'html' && /[<>]/.test(tr.replace(/<[^>]+>/g, ''))) errs.push(`${e.id} has a bare < or > (write &lt; or &gt;)`);
    if (placeholders(tr).join() !== placeholders(e.en).join())
      errs.push(`${e.id} placeholders differ: ${placeholders(e.en).join(' ') || 'none'} vs ${placeholders(tr).join(' ') || 'none'}`);
    for (const name of PROTECT)
      if (new RegExp(`(^|[^\\w])${name.replace(/[.]/g, '\\.')}($|[^\\w])`).test(e.en) && !tr.includes(name))
        errs.push(`${e.id} lost the protected name "${name}"`);
    if (tr === e.en && !same.has(e.id))
      errs.push(`${e.id} is still English (list it under _same_as_english if that is deliberate): ${tr.slice(0, 60)}`);
    // _same_as_english is for short labels and names, never for whole sentences
    if (same.has(e.id) && e.kind !== 'svg' && e.kind !== 'attr' && words(e.en).length > 3)
      errs.push(`${e.id} cannot be listed under _same_as_english (only figure labels, accessible names and strings of up to 3 words can): ${e.en.slice(0, 60)}`);
    // near-English: three English words in a row in a non-Latin script, or a Latin-script text that is mostly English words
    if (!same.has(e.id) && NON_LATIN.has(code)) {
      const en3 = latinTrigrams(e.en), hit = [...latinTrigrams(tr)].find(g => en3.has(g));
      if (hit) errs.push(`${e.id} still has English in it ("${hit}"): ${tr.slice(0, 60)}`);
    }
    if (!same.has(e.id) && !NON_LATIN.has(code)) {
      const enW = new Set(words(e.en)), trW = words(tr), same80 = trW.filter(w => enW.has(w)).length;
      if (trW.length && same80 / trW.length >= 0.8)
        errs.push(`${e.id} is mostly English (${same80} of ${trW.length} words are the English ones): ${tr.slice(0, 60)}`);
    }
    const lim = e.limit && (CJK.has(code) ? e.limit.cjk : e.limit.chars);
    if (lim && [...tr].length > lim) errs.push(`${e.id} is ${[...tr].length} characters, over the ${lim}-character limit (${e.where[0]})`);
  }
  return errs;
}
// ids in a translation file that the catalogue no longer has (safe to delete)
export const staleIds = (entries, tx) => Object.keys(tx).filter(k => !k.startsWith('_') && !entries.some(e => e.id === k));

// ---------- text runs, for the "no English left behind" check (§10) ----------
const ENT = { nbsp: ' ', amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", '#39': "'" };
export const decode = s => s.replace(/&(#?\w+);/g, (m, k) => ENT[k] ?? (k[0] === '#' ? String.fromCodePoint(+k.slice(1)) : m));
const RUN_ATTRS = ['aria-label', 'alt', 'title', 'data-idle', 'data-copied', 'data-fallback'];
export function textRuns(html) {
  const runs = new Set();
  const add = s => { s = decode(s).replace(/\s+/g, ' ').trim(); if (s && !isKept(s)) runs.add(s); };
  const ld = html.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/);
  if (ld) add(JSON.parse(ld[1]).description);
  const body = html.replace(/<script[\s\S]*?<\/script>|<style[\s\S]*?<\/style>/g, '');
  for (const m of body.matchAll(/<(title)>([\s\S]*?)<\/title>/g)) add(m[2]);
  for (const m of body.matchAll(/<meta (?:name|property)="(description|og:title|og:description|og:image:alt|twitter:title|twitter:description)" content="([^"]*)"/g)) add(m[2]);
  const inBody = body.slice(body.indexOf('<body'));
  for (const m of inBody.matchAll(/>([^<]+)</g)) add(m[1]);
  for (const m of inBody.matchAll(new RegExp(`\\s(?:${RUN_ATTRS.join('|')})="([^"]*)"`, 'g'))) add(m[1]);
  return runs;
}
