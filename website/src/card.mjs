// The share card (og:image), one per language: 1200x630, drawn from its own HTML by tools/og.cjs (never deployed).
// Left: the wordmark, the page's headline and a footer line (genswarms.com, "Open source, MIT"); right: a still of the
// organization the page's zoom starts from, drawn by the page's own engine (src/zoom-*.js) on a canvas, with the zoom
// caption over it. Every string is the page's own, looked up through the same t() calls, so translating the page
// translates the card. The build hashes this HTML into i18n/build.lock.json (og.<lang>.source); `--check` refuses an
// image rendered from other HTML.
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import { t, CJK, fill, escText } from './i18n.mjs';
import { css, minCSS, typeOf, zoomEngine, WORD } from './page.mjs';
import { heroH1, facts, canvasStrings } from './content.mjs';

export const CARD = { w: 1200, h: 630 };
// headline size (px) per language; the card's script steps it down if the column still overflows
const HEAD = { en: 64, es: 56, ko: 64, 'zh-Hans': 68, ru: 52, tr: 56 };

// the organization's size, as the page's engine builds it (seeded: the same on every page and card)
let WORLD = null;
function world() {
  if (!WORLD) {
    const ctx = { Math };
    vm.createContext(ctx);
    vm.runInContext(readFileSync(new URL('zoom-world.js', import.meta.url), 'utf8').replace(/^var Z = \{\};/m, 'Z = {};'), ctx);
    const W = ctx.Z.build(1.2);
    WORLD = { swarms: W.count, agents: W.total };
  }
  return WORLD;
}

const inner = (html, re) => (html.match(re) || [])[1];

// the card's copy, from the page's own strings
export function cardCopy(code = 'en') {
  // a hyphenated compound (Russian «ИИ-персонала») stays on one line: the card never breaks inside a word
  const head = heroH1(t).replace(/[^\s<>;]+-[^\s<>&]+/g, w => `<span class="nw">${w}</span>`);
  const license = facts(t)[0][1];
  const zs = canvasStrings(t), nf = n => new Intl.NumberFormat(code).format(n), W = world();
  const cap = { lv: zs.lv[0], n: fill(zs.count, { swarms: nf(W.swarms), agents: nf(W.agents) }) };
  const ill = t('illustration', 'small label at the bottom right of the drawing: everything it shows is an illustration');
  return { head, license, cap, ill };
}

// The fit script: once the fonts are in, the world is drawn, then the headline steps down (2px at a time) while the
// copy column overflows the card, a word is wider than the column, or the last line holds one word (or, in Chinese,
// one character) alone. It leaves what is still wrong in <html data-fit> ("ok" when nothing), which tools/og.cjs
// refuses to render.
const FIT = `(function(){
var d=document,h=d.querySelector('.og-h'),c=d.querySelector('.og-copy'),card=d.querySelector('.og').getBoundingClientRect();
function lines(el){var r=d.createRange();r.selectNodeContents(el);var ls=[];[].forEach.call(r.getClientRects(),function(x){if(!x.width)return;var l=ls.find(function(y){return Math.abs(y.top-x.top)<4});if(l){l.left=Math.min(l.left,x.left);l.right=Math.max(l.right,x.right)}else ls.push({top:x.top,left:x.left,right:x.right,bottom:x.bottom})});return ls}
function problems(){var p=[];
if(h.scrollWidth>h.clientWidth+1)p.push('a word of the headline is wider than its column');
if(c.scrollHeight>c.clientHeight+1)p.push('the copy column overflows');
[].forEach.call(d.querySelectorAll('.og-copy *,.og-cap,.og-ill'),function(e){var b=e.getBoundingClientRect();if(b.width&&(b.left<card.left+40||b.right>card.right-40||b.top<card.top+32||b.bottom>card.bottom-28))p.push(e.className+' is outside the margins')});
var ls=lines(h),last=ls[ls.length-1];
if(ls.length>1&&(last.right-last.left)<0.22*Math.max.apply(null,ls.map(function(l){return l.right-l.left})))p.push('the headline ends on a stranded word');
return p}
function draw(){var cv=d.querySelector('.og-fig canvas'),b=cv.getBoundingClientRect(),r=window.devicePixelRatio||1,w=b.width,hh=b.height;
cv.width=Math.round(w*r);cv.height=Math.round(hh*r);var g=cv.getContext('2d');g.setTransform(r,0,0,r,0,0);g.textBaseline='alphabetic';
var cs=getComputedStyle(d.documentElement),C={},m={bg:'--bg',bg1:'--bg-1',bg2:'--bg-2',ink:'--ink',ink2:'--ink-2',ink3:'--ink-3',or:'--or',hl3:'--hl-3'};for(var k in m)C[k]=cs.getPropertyValue(m[k]).trim();
var sf=[56,76,w-56-40,hh-76-56],W=Z.build(sf[2]/sf[3]),ob=W.box,pad=40,s=Math.min(sf[2]/(ob[2]-ob[0]+2*pad),sf[3]/(ob[3]-ob[1]+2*pad));
var st={sup:Z.sup,W:W,C:C,S:{},F:Z.fonts(cs.getPropertyValue('--fc').trim()),dash:Z.dash,tEdges:Z.teamEdges(W),pulses:{n:0,list:[]},crashes:[],cam:{ux:(ob[0]+ob[2])/2,uy:(ob[1]+ob[3])/2,s:s,cx:sf[0]+sf[2]/2,cy:sf[1]+sf[3]/2},q:0,t:0.6,vw:w,vh:hh,rm:false,audit:null};
var rng=Z.rngf(7),i,S;for(i=0;i<W.swarms.length;i++){S=W.swarms[i];if(S.kind!=='pipe'||rng()<0.35)continue;var e=S.edges[rng()*S.edges.length|0];st.pulses.list.push({on:true,sup:false,S:S,j:0,d:e.len*(0.3+rng()*0.5),wait:0,e:e});st.pulses.n++}
for(i=0;i<W.swarms.length;i++)if(W.swarms[i].name==='trading sim')st.crashes.push({on:true,S:W.swarms[i],i:7,t0:0});
Z.draw(g,st)}
function fit(){draw();var s=parseFloat(getComputedStyle(h).fontSize),p;while((p=problems()).length&&s>32){s-=2;h.style.fontSize=s+'px'}d.documentElement.dataset.fit=p.length?p.join('; '):'ok';d.documentElement.dataset.size=s}
d.fonts.ready.then(fit)})();`;

// renderOgCard({ lang }): the card in the current t() language (see withLang in src/i18n.mjs)
export function renderOgCard({ lang: code = 'en' } = {}) {
  const type = typeOf(code);
  const { head, license, cap, ill } = cardCopy(code);
  const cjk = CJK.has(code);
  const card = `
html,body{width:${CARD.w}px;height:${CARD.h}px;overflow:hidden;background:var(--bg)}
.og{position:relative;width:${CARD.w}px;height:${CARD.h}px;overflow:hidden;background:var(--bg)}
.og-copy{position:absolute;left:64px;top:56px;bottom:52px;width:500px;display:flex;flex-direction:column;z-index:2}
.og .brand{font-size:30px;min-height:0}
.og-h{margin:auto 0 0;font:600 ${HEAD[code] || HEAD.en}px/1.04 var(--fh);letter-spacing:${cjk ? 0 : '-.05em'};color:var(--ink);text-wrap:balance;hyphens:manual;overflow-wrap:normal}
.og-h .nw{white-space:nowrap}
.og-foot{margin:34px 0 0;display:flex;align-items:center;gap:14px;font:500 17px/1.3 var(--fm);color:var(--ink-2);letter-spacing:-.02em}
.og-foot b{font-weight:500;color:var(--ink)}
.og-foot i{width:1px;height:16px;background:var(--hl-3)}
.og-fig{position:absolute;left:600px;top:0;right:0;bottom:0;border-left:1px solid var(--hl)}
.og-fig canvas{position:absolute;inset:0;width:100%;height:100%;display:block}
.og-cap{position:absolute;left:56px;top:36px;display:flex;gap:14px;font:500 15px/1.3 var(--fm);color:var(--ink);letter-spacing:-.01em;white-space:nowrap}
.og-cap span+span{color:var(--ink-3);font-weight:400}
.og-ill{position:absolute;right:40px;bottom:30px;font:400 14px/1 var(--fm);color:var(--ink-3)}
${cjk ? '.og-h{line-height:1.16}' : ''}`;
  return `<!doctype html>
<html lang="${code}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=${CARD.w}">
${type.fonts.map(h => `<link href="${h}" rel="stylesheet">`).join('\n')}
<style>
${css}${type.css ? '\n' + minCSS(type.css) : ''}
${minCSS(card)}
</style>
</head>
<body>
<div class="og">
<div class="og-copy">
<span class="brand">${WORD}</span>
<p class="og-h">${head}</p>
<p class="og-foot"><b>genswarms.com</b><i></i>${license}</p>
</div>
<div class="og-fig"><canvas></canvas><p class="og-cap"><span>${escText(cap.lv)}</span><span>${escText(cap.n)}</span></p><p class="og-ill">${ill}</p></div>
</div>
<script>
${zoomEngine()}
${FIT}
</script>
</body>
</html>
`;
}
