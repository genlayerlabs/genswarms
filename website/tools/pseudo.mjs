// Pseudo-translations of the catalogue, for testing the pipeline without real translations (never committed).
// Every string changes, in the writing system of the language it stands in for (accented Latin for es and tr,
// Cyrillic for ru, Hangul for ko, Han for zh-Hans), while tags, entities, placeholders, URLs, protected names and
// keep-list names stay verbatim. Spanish prose runs ~20% longer, like real Spanish; the others keep their length.
//
//   node website/tools/pseudo.mjs <dir>    writes <dir>/en.json and <dir>/{es,ko,zh,ru,tr}.json
import { writeFileSync, mkdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { LANGS, PROTECT, KEEP } from '../src/i18n.mjs';
import { catalogue, catalogueFile } from '../src/site.mjs';

// (lowercase identifiers such as `agents` are only kept where they are drawn, not inside prose)
const names = [...new Set([...PROTECT, ...[...KEEP].filter(n => !/^[a-z]+$/.test(n))])].filter(n => /\p{L}/u.test(n)).sort((a, b) => b.length - a.length).map(n => n.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'));
const KEEP_RE = new RegExp(`(<[^>]+>|&[a-z#0-9]+;|\\{\\w+\\}|https?://[^\\s<]+[^\\s<.,]|(?<![\\p{L}\\w])(?:${names.join('|')})(?![\\p{L}\\w]))`, 'u');

const ACC = { a: 'á', b: 'ƀ', c: 'ç', d: 'ð', e: 'é', f: 'ƒ', g: 'ĝ', h: 'ĥ', i: 'í', j: 'ĵ', k: 'ķ', l: 'ĺ', m: 'ɱ', n: 'ñ', o: 'ó', p: 'þ', q: 'ǫ', r: 'ŕ', s: 'š', t: 'ţ', u: 'ú', v: 'ṽ', w: 'ŵ', x: 'ẋ', y: 'ý', z: 'ž' };
const TR = { a: 'â', c: 'ç', g: 'ğ', i: 'ı', o: 'ö', s: 'ş', u: 'ü', e: 'ê' };
const CYR = { a: 'а', b: 'б', c: 'ц', d: 'д', e: 'е', f: 'ф', g: 'г', h: 'х', i: 'и', j: 'й', k: 'к', l: 'л', m: 'м', n: 'н', o: 'о', p: 'п', q: 'к', r: 'р', s: 'с', t: 'т', u: 'у', v: 'в', w: 'ш', x: 'ж', y: 'ы', z: 'з' };
const HAN = '的一是在不了有和人这中大为上个国我以要他时来用们生到作地于出就分对成会可主发年动同工也能下过子说产种面而方后多定行学法所民得经十三之进着等部度家电力里如水化高自二理起小物现实加量都两体制机当使点从业本去把性好应开它合还因由其些然前外天政四日那社义事平形相全表间样与关各重新线内数正心反你明看原又么利比或但质气第向道命此变条只没结解问意建月公无系军很情者最立代想已通并提直题党程展五果料象员革位入常文总次品式活设及管特件长求老头基资边流路级少图山统接知较将组见计别她手角期根论运农指几九区强放决西被干做必战先回则任取据处府';
const HANGUL = '가나다라마바사아자차카타파하고노도로모보소오조초코토포호구누두루무부수우주추쿠투푸후그느드르므브스으즈츠크트프흐기니디리미비시이지치키티피히개내대래매배새애재채';
const PUNCT_ZH = { '.': '。', ',': '，', ':': '：', ';': '；', '?': '？', '(': '（', ')': '）', '!': '！' };

const hash = s => [...s].reduce((h, c) => (h * 31 + c.codePointAt(0)) >>> 0, 7);
const pick = (pool, s, n) => Array.from({ length: n }, (_, i) => pool[(hash(s) + i * 7) % pool.length]).join('');
const mapLetters = (s, m) => s.replace(/[A-Za-z]/g, ch => { const v = m[ch.toLowerCase()]; return v ? (ch === ch.toLowerCase() ? v : v.toUpperCase()) : ch; });

function plain(code, s, grow) {
  if (code === 'es') {
    let words = mapLetters(s, ACC).split(' ');
    if (grow) words = words.flatMap((w, i) => (i % 5 === 4 && /\p{L}{3}/u.test(w) ? [w, w.replace(/[.,:;?!]+$/, '')] : [w]));
    return words.join(' ');
  }
  if (code === 'tr') return mapLetters(s, TR);
  if (code === 'ru') return mapLetters(s, CYR);
  if (code === 'ko') return s.replace(/[A-Za-z’'-]+/g, w => pick(HANGUL, w, Math.max(1, Math.round(w.length / 3))));
  // zh-Hans: no spaces between Han characters, fullwidth punctuation
  return s.replace(/[A-Za-z’'-]+/g, w => pick(HAN, w, Math.max(1, Math.round(w.length / 2.4))))
    .replace(/(?<=[㐀-鿿]) (?=[㐀-鿿])/g, '').replace(/[.,:;?!()](?=\s|$)/g, p => PUNCT_ZH[p] || p);
}

export function pseudo(code, entries) {
  const out = { _same_as_english: [] };
  for (const e of entries) {
    const grow = e.kind === 'html' && e.en.split(' ').length >= 4;
    out[e.id] = e.en.split(KEEP_RE).map((part, i) => (i % 2 ? part : plain(code, part, grow))).join('');
  }
  return out;
}

// write a pseudo-locale set: the catalogue plus one file per language
export function writePseudo(dir, codes = LANGS.slice(1).map(l => l.code)) {
  mkdirSync(dir, { recursive: true });
  const entries = catalogue();
  writeFileSync(resolve(dir, 'en.json'), catalogueFile(entries));
  for (const l of LANGS.filter(l => codes.includes(l.code))) writeFileSync(resolve(dir, `${l.file}.json`), JSON.stringify(pseudo(l.code, entries), null, 1) + '\n');
  return entries;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const dir = process.argv[2];
  if (!dir) { console.error('usage: node website/tools/pseudo.mjs <dir>'); process.exit(1); }
  writePseudo(dir);
  console.log(`pseudo-locales written to ${dir}`);
}
