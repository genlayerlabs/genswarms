// The share card (og:image), one per language: 1200x630, drawn from its own HTML by tools/og.cjs (never deployed).
// Left: the lockup, the page's headline, the closing triad of step 9 (one beat per line) and a footer line; right:
// step 9's drawing (the control layer over the swarms and the models). Every string is the page's own, looked up
// through the same t() calls (so the card follows the catalogue and needs no strings of its own). The build hashes
// this HTML into i18n/build.lock.json (og.<lang>.source); `--check` refuses an image rendered from other HTML.
import { STEPS } from './content.mjs';
import { L, system, figureCSS } from './figures.mjs';
import { t, CJK } from './i18n.mjs';
import { css, minCSS, mark, TYPE, FONTS_ALL } from './page.mjs';

export const CARD = { w: 1200, h: 630 };
// the step 9 drawing, cropped to what it draws (the band, the swarms, the models)
export const CARD_CROP = '48 70 704 518';
// headline size (px) per language; the card's script steps it down if the column still overflows
const HEAD = { en: 80, es: 68, ko: 86, 'zh-Hans': 92, ru: 62, tr: 68 };

const inner = (html, re) => (html.match(re) || [])[1];

// the card's copy, from the page's own markup (story steps 1 and 9)
export function cardCopy() {
  const hero = STEPS[0](t), close = STEPS[8](t);
  // a hyphenated compound (Russian «ИИ-персонала») stays on one line: the card never breaks inside a word
  const head = inner(hero, /<h1>([\s\S]*?)<\/h1>/).replace(/[^\s<>;]+-[^\s<>&]+/g, w => `<span class="nw">${w}</span>`);
  const meta = inner(hero, /<p class="meta">([\s\S]*?)<\/p>/);
  const triad = [...inner(close, /<p class="triad">([\s\S]*?)<\/p>/).matchAll(/<span>([\s\S]*?)<\/span>/g)].map(m => m[1]);
  // "Open source, MIT." without the version: the meta line's first sentence (the whole line if it has no break)
  const license = (meta.match(/^[^.。]*MIT[^.。]*[.。]/) || [meta])[0];
  return { head, triad, license };
}

// The fit script: once the fonts are in, the headline steps down (2px at a time) while the copy column overflows the
// card, a word is wider than the column, or the last line holds one word (or, in Chinese, one character) alone.
// It leaves what is still wrong in <html data-fit> ("ok" when nothing), which tools/og.cjs refuses to render.
const FIT = `(function(){
var d=document,h=d.querySelector('.og-h'),c=d.querySelector('.og-copy'),card=d.querySelector('.og').getBoundingClientRect();
function lines(el){var r=d.createRange();r.selectNodeContents(el);var ls=[];[].forEach.call(r.getClientRects(),function(x){if(!x.width)return;var l=ls.find(function(y){return Math.abs(y.top-x.top)<4});if(l){l.left=Math.min(l.left,x.left);l.right=Math.max(l.right,x.right)}else ls.push({top:x.top,left:x.left,right:x.right,bottom:x.bottom})});return ls}
function problems(){var p=[];
if(h.scrollWidth>h.clientWidth+1)p.push('a word of the headline is wider than its column');
if(c.scrollHeight>c.clientHeight+1)p.push('the copy column overflows');
[].forEach.call(d.querySelectorAll('.og-copy *,.og-fig svg,.og-fig text'),function(e){var b=e.getBoundingClientRect();if(b.width&&(b.left<card.left+40||b.right>card.right-40||b.top<card.top+32||b.bottom>card.bottom-32))p.push((e.className.baseVal!=null?e.className.baseVal:e.className)+' is outside the margins')});
var ls=lines(h),last=ls[ls.length-1];
if(ls.length>1&&(last.right-last.left)<0.22*Math.max.apply(null,ls.map(function(l){return l.right-l.left})))p.push('the headline ends on a stranded word');
return p}
function fit(){var s=parseFloat(getComputedStyle(h).fontSize),p;while((p=problems()).length&&s>40){s-=2;h.style.fontSize=s+'px'}d.documentElement.dataset.fit=p.length?p.join('; '):'ok';d.documentElement.dataset.size=s}
d.fonts.ready.then(fit)})();`;

// renderOgCard({ lang }): the card in the current t() language (see withLang in src/i18n.mjs)
export function renderOgCard({ lang: code = 'en' } = {}) {
  const type = TYPE[code] || { fonts: [FONTS_ALL], css: '' };
  const { head, triad, license } = cardCopy();
  const cjk = CJK.has(code);
  const card = `
.og{position:relative;display:grid;grid-template-columns:552px minmax(0,1fr);gap:40px;width:${CARD.w}px;height:${CARD.h}px;padding:52px 64px 48px;box-sizing:border-box;overflow:hidden}
.og-copy{display:flex;flex-direction:column;min-width:0;min-height:0}
.og .brand{font-size:26px;gap:12px;min-height:0}
.og .brand .mark{width:30px;height:30px}
.og-h{margin:auto 0 0;font:780 ${HEAD[code] || HEAD.en}px/.94 var(--fd);letter-spacing:${cjk ? 0 : '-.042em'};font-variation-settings:"opsz" 96;color:var(--ink);text-wrap:balance;hyphens:manual;overflow-wrap:normal}
.og-h .nw{white-space:nowrap}
.og-k{margin:30px 0 auto;padding:0;list-style:none;font:700 25px/1.2 var(--fd);letter-spacing:${cjk ? 0 : '-.02em'};color:var(--ink-2);text-wrap:balance}
.og-k li+li{margin-top:5px}
.og-k li:last-child{color:var(--clay)}
.og-foot{margin:0;font:500 17px/1.3 var(--ft);color:var(--ink-2)}
.og-foot b{font-weight:600;color:var(--ink)}
.og-fig{display:flex;align-items:center;min-width:0}
.og-fig .sys{width:100%;height:auto}
.og-fig .ts{font-size:21px}.og-fig .tb{font-size:30px}
.og-fig .ce{stroke-width:1.8;stroke-opacity:.7}.og-fig .cn{r:6.4px}
.og-fig .drop,.og-fig .mline{stroke-width:1.3}.og-fig .hex{stroke-width:2}
.og-foot b::after{content:"";display:inline-block;width:4px;height:4px;margin:0 .75em;border-radius:50%;background:var(--ink-2);vertical-align:middle}
${cjk ? '.og-h{line-height:1.12}.og-k{line-height:1.3}' : ''}`;
  return `<!doctype html>
<html lang="${code}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=${CARD.w}">
${type.fonts.map(h => `<link href="${h}" rel="stylesheet">`).join('\n')}
<style>
${css}
${minCSS(figureCSS())}${type.css ? '\n' + minCSS(type.css) : ''}
html,body{width:${CARD.w}px;height:${CARD.h}px;overflow:hidden}
${minCSS(card)}
</style>
</head>
<body>
<div class="og">
<div class="og-copy">
<span class="brand">${mark()}GenSwarms</span>
<p class="og-h">${head}</p>
<ul class="og-k">${triad.map(s => `<li>${s}</li>`).join('')}</ul>
<p class="og-foot"><b>genswarms.com</b>${license}</p>
</div>
<div class="og-fig">${system(L, 8, { crop: CARD_CROP, prune: true })}</div>
</div>
<script>
${FIT}
</script>
</body>
</html>
`;
}
