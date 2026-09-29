import { readFileSync } from 'node:fs';
import { ARIA, aria, canvasStrings, readouts, roTitles, legend, ctas, STEPS, heroH1, facts, triad, OS, SEC, CMP, CLOSE } from './content.mjs';
import { t, tf, escAttr, escText, isKept, ORIGIN, SNIPPET } from './i18n.mjs';

const here = new URL('.', import.meta.url);
// Build-time minification, deliberately conservative (no external deps):
// CSS loses comments and the whitespace around { } ; , (never around ':' — `.a :focus` is a
// descendant selector); JS loses comment-only lines and indentation but keeps its line breaks
// (no ASI hazards); markup loses indentation after line breaks (a newline run is still one
// space to the HTML parser, so inline text keeps its spacing).
export const minCSS = c => c.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\s+/g, ' ').replace(/\s*([{};,])\s*/g, '$1').replace(/;}/g, '}').trim();
export const minJS = j => j.split('\n').map(l => l.trim()).filter(l => l && !l.startsWith('//') && !/^\/\*.*\*\/$/.test(l)).join('\n')
  // block comments that span lines (file headers)
  .replace(/^\/\*[\s\S]*?\*\/\n/gm, '');
const minHTML = h => h.replace(/\n\s+/g, '\n');
const read = f => readFileSync(new URL(f, here), 'utf8');
export const css = minCSS(read('page.css'));
// the zoom (the world, its drawing, the support team, the loop) and the copy button
export const ZOOM_JS = ['zoom-world.js', 'zoom-draw.js', 'zoom-support.js'];
const js = minJS([...ZOOM_JS, 'zoom-run.js', 'page.js'].map(read).join('\n'));
export const zoomEngine = () => minJS(ZOOM_JS.map(read).join('\n'));
// only on multilingual builds: the language picker, the footer's language links and the suggestion bar
const i18nCSS = minCSS(read('i18n.css'));
const langbarJS = minJS(read('langbar.js'));

// Where the pinned ("cine") layout fits: wide and tall enough, or a short landscape screen (a phone on its side), which
// gets the same layout with its readouts in the text. The head script, page.css and zoom-run.js share this query.
export const CINE = '(min-width: 960px) and (min-height: 640px), (orientation: landscape) and (min-width: 640px) and (max-height: 639px)';

// ---------- per writing system (playbook §9) ----------
// Geist and Geist Mono cover Latin (with Turkish) and Cyrillic, so English, Spanish, Turkish and Russian load both.
// They have no Hangul or Han: Korean and Chinese set titles and text in good system faces and load Geist Mono only,
// for the wordmark, identifiers, readouts and the drawing's labels, with the system face behind it for their own script.
export const FONTS_ALL = 'https://fonts.googleapis.com/css2?family=Geist+Mono:wght@400..600&family=Geist:wght@400..600&display=swap';
const FONTS_MONO = 'https://fonts.googleapis.com/css2?family=Geist+Mono:wght@400..600&display=swap';
const SYS = {
  ko: `'Apple SD Gothic Neo','Noto Sans KR','Malgun Gothic',sans-serif`,
  'zh-Hans': `'PingFang SC','Hiragino Sans GB','Noto Sans SC','Microsoft YaHei',sans-serif`,
};
const cjkVars = sys => `:root{--fs:${sys};--fh:${sys};--fm:'Geist Mono',${sys.replace(/,sans-serif$/, '')},ui-monospace,monospace;--fc:'Geist Mono',${sys.replace(/,sans-serif$/, '')},monospace}`;
// titles: every display-type element on the page
const TITLES = 'h1,h2,h3,.triad span,.spec dt,.cmp tbody th';
// long words (Russian, Turkish): hyphenate titles and set the phone's and the pinned hero's display sizes a step smaller. The comparison's
// heading, row questions and column heads are not hyphenated (brand names broke: "Lang-Graph", "Auto-Gen'den")
const LONG = `h1,h2,h3,.triad span,.spec dt{hyphens:auto;-webkit-hyphens:auto;overflow-wrap:break-word}
#cmp-h{hyphens:manual;-webkit-hyphens:manual}
@media (max-width:759px){h1{font-size:clamp(30px,8.6vw,64px)}.step h2{font-size:clamp(25px,6.6vw,40px)}.sec-head h2{font-size:clamp(26px,6.2vw,40px)}}
@media (min-height:640px){.cine h1{font-size:clamp(34px,min(3.7vw,7.4vh),54px)}}`;
// CJK: no negative tracking on titles, taller title lines
const CJK_CSS = `${TITLES}{letter-spacing:0}h1{line-height:1.14}.step h2,.close h2,.sec-head h2{line-height:1.2}.triad span{line-height:1.4}`;
// the comparison table: words stay whole (hyphenating split "agen-te", "Lang-Smith", "Gen-Swarms"); a word longer
// than its column still breaks
const TABLE = `.cmp th,.cmp td{overflow-wrap:break-word}`;
export const TYPE = {
  es: { fonts: [FONTS_ALL], css: TABLE },
  ru: { fonts: [FONTS_ALL], css: `${LONG}${TABLE}` },
  tr: { fonts: [FONTS_ALL], css: `${LONG}${TABLE}` },
  ko: { fonts: [FONTS_MONO], css: `${cjkVars(SYS.ko)}body{word-break:keep-all;overflow-wrap:break-word}${CJK_CSS}` },
  // Chinese wraps between any two characters: paragraphs never end on one stranded character (text-wrap:pretty) and
  // the two-line lead is balanced
  'zh-Hans': { fonts: [FONTS_MONO], css: `${cjkVars(SYS['zh-Hans'])}${CJK_CSS}.copy .lead{text-wrap:balance}` },
};
export const typeOf = code => TYPE[code] || { fonts: [FONTS_ALL], css: '' };

// ---------- text widths (for the header's breakpoints) ----------
const HAN = /[⺀-⿿　-ヿ㐀-鿿豈-﫿＀-￯]/;
const HANGUL = /[ᄀ-ᇿ㄰-㆏가-힯]/;
// estimated advance of s in em, rounded up from measurements of Geist, Geist Mono and the Korean and Chinese system faces
export function em(s, { mono = false } = {}) {
  let w = 0;
  for (const ch of s) {
    if (HAN.test(ch)) w += 1.02;
    else if (HANGUL.test(ch)) w += mono ? 0.86 : 0.9;
    else if (mono) w += 0.6;
    else if (/\s/.test(ch)) w += 0.26;
    else if (/[A-ZЀ-Я]/.test(ch)) w += 0.68;
    else if (/[0-9]/.test(ch)) w += 0.6;
    else if (/[а-џ]/.test(ch)) w += 0.58;
    else if (/[.,:;'’()!|/-]/.test(ch)) w += 0.3;
    else w += 0.56;
  }
  return w;
}

// The wordmark: lowercase Geist Mono and an orange block cursor. Its accessible name comes from the link around it.
export const WORD = `genswarms<span class="cur" aria-hidden="true"></span>`;

// The header on a multilingual page carries the language picker too. Translated link names differ in length, so the
// breakpoints where the section links, and then "Docs", leave the header are computed from their estimated widths.
// English keeps page.css's 719px. These numbers mirror page.css (measured in Chrome), keep them in step with it:
// 112 = .brand (the wordmark at 600 19px Geist Mono and its cursor), 20 = .top-in's gap, 76 = the .gh link
// ("GitHub", 500 13px Geist Mono, 12px padding, 1px border), 44 = the picker's summary (i18n.css), 14px = the links'
// size, g() = --g and gap() = .top nav's gap. i18n-audit.cjs catches drift (header items overlapping or leaving the screen).
function navCSS(labels) {
  const g = W => Math.max(16, Math.min(48, 0.034 * W)), gap = W => Math.max(12, Math.min(30, 0.022 * W));
  const fits = (W, items) => 112 + 20 + items.reduce((n, w) => n + w, 0) + gap(W) * (items.length - 1) + 2 * g(W) + 8 <= W;
  const [how, cmp, sec, docs] = labels.map(s => em(s) * 14), gh = 76, pick = 44;
  const from = items => { for (let W = 320; W < 1400; W++) if (fits(W, items)) return W; return 1400; };
  const all = from([how, cmp, sec, docs, gh, pick]), some = from([docs, gh, pick]);
  return `@media (max-width:${Math.max(all, 720) - 1}px){.top nav>a:not(.gh):not([href="/docs/"]){display:none}}` +
    (some > 320 ? `@media (max-width:${some - 1}px){.top nav>a[href="/docs/"]{display:none}}` : '');
}

// The fonts load without blocking the first paint (display=swap: the fallback face shows until they arrive; the
// drawing measures its labels again once they have); without JavaScript, <noscript> loads them the usual way.
const langLinks = (langs, code) => langs.map(l => `<a href="/${l.dir}" hreflang="${l.code}" lang="${l.code}"${l.code === code ? ' aria-current="page"' : ''}>${l.name}</a>`);
const json = o => JSON.stringify(o).replace(/</g, '\\u003c');

// the story's steps
const step = (s, i, RO, TT) => {
  const ro = (k, cls) => `<div class="${cls}" data-at="${k}">${TT[k] ? `<p class="ro-t">${TT[k]}</p>` : ''}${RO[k]}</div>`;
  const inl = s.k.filter(k => RO[k]).map(k => ro(k, 'ro-in')).join('');
  const n = i + 1;
  let copy;
  if (s.hero) copy = `<div class="copy hero-copy">
<h1>${heroH1(t)}</h1>
<p class="lead">${t('Deploy, coordinate and control thousands of AI agents across your organization.', 'story step 1: lead paragraph under the headline')}</p>
${ctas(t, 'story step 1')}
<dl class="facts">${facts(t).map(([k, v]) => `<div><dt>${k}</dt><dd>${v}</dd></div>`).join('')}</dl>
</div>`;
  else if (s.last) copy = `<div class="copy">
<h2>${t('One control layer for your AI organization.', 'story step 9: headline (h2, display size)')}</h2>
<p>${t('Watch every message, crash and restart as it happens. Drive it by API or CLI, or hand it to your coding agent.', 'story step 9: paragraph 1')}</p>
<p class="triad">${triad(t).map(x => `<span>${x}</span>`).join(' ')}</p>
${inl}
</div>`;
  else copy = `<div class="copy">
<h2>${t(s.h, `story step ${n}: headline (h2, display size)`)}</h2>
${s.p.map((p, j) => `<p>${t(p, `story step ${n}: paragraph ${j + 1}`)}</p>`).join('\n')}${s.ex ? `\n<p class="ex">${t(s.ex, `story step ${n}: small example line under the paragraph`)}</p>` : ''}
${inl}
</div>`;
  return `<article class="step${s.hero ? ' hero' : ''}" id="s${i}" data-step="${i}" data-k="${s.k.join(' ')}">
${copy}
</article>`;
};

// renderPage({ lang, langs }): the page in the current t() language (see withLang in src/i18n.mjs). `langs` lists
// every version being built; with more than English it adds hreflang, the picker, the footer's language links and
// the suggestion bar. An English-only build is exactly the English page.
export function renderPage({ lang: code = 'en', langs = null, bar = null, ogImage = 'og-image.png' } = {}) {
  const multi = langs && langs.length > 1;
  const cur = multi ? langs.find(l => l.code === code) : { code: 'en', dir: '', og: 'en_US', short: 'EN' };
  const url = ORIGIN + cur.dir;
  const type = typeOf(code);
  const nf = n => new Intl.NumberFormat(code).format(n);
  const title = t('GenSwarms: the operating system for AI workforces', 'page title (browser tab, search result title, share title)', { kind: 'meta' });
  const desc = t('GenSwarms runs AI agents as separate, supervised processes on declared message paths, with an API and a live event stream. Open source, MIT.', 'meta description (search result snippet)', { kind: 'meta', limit: SNIPPET });
  const ogDesc = t('Deploy, coordinate and control AI agents as separate, supervised processes.', 'og:description (share preview text)', { kind: 'meta', limit: SNIPPET });
  const ld = { '@context': 'https://schema.org', '@type': 'SoftwareApplication', name: 'GenSwarms', applicationCategory: 'DeveloperApplication', operatingSystem: 'Linux, macOS', softwareVersion: '0.2.0', license: 'https://opensource.org/licenses/MIT', url, codeRepository: 'https://github.com/genlayerlabs/genswarms',
    description: t('The operating system for AI workforces: runs AI agents as separate, supervised processes on declared message paths, with a REST + WebSocket API and a live event stream.', 'structured data (JSON-LD) description, read by search engines', { kind: 'meta' }),
    ...(multi ? { inLanguage: code } : {}),
    offers: { '@type': 'Offer', price: '0', priceCurrency: 'USD' }, author: { '@type': 'Organization', name: 'GenLayer Labs' } };
  const hreflang = multi ? '\n' + [...langs.map(l => `<link rel="alternate" hreflang="${l.code}" href="${ORIGIN}${l.dir}">`), `<link rel="alternate" hreflang="x-default" href="${ORIGIN}">`].join('\n') : '';
  const langName = t('Language', 'header language picker and footer language links: accessible name (read by screen readers)', { kind: 'attr' });
  const picker = multi ? `\n<details class="lang"><summary><span class="sr">${langName} </span>${cur.short}</summary><ul>${langLinks(langs, code).map(a => `<li>${a}</li>`).join('')}</ul></details>` : '';
  const footLangs = multi ? `\n<nav class="foot-langs" aria-label="${escAttr(langName)}">${langLinks(langs, code).join('')}</nav>` : '';
  const barData = multi && bar ? `\n<script type="application/json" id="langbar">${json(bar)}</script>\n<script>\n${langbarJS}\n</script>` : '';
  const docs = t('Docs', 'header navigation link (keep it short: on phones it shares the header with the logo, GitHub and the language picker); footer link');
  const navHow = t('How it works', 'header navigation link to the “How it works.” section (tablet and desktop; keep it short)');
  const navCmp = t('Compare', 'header navigation link to the comparison table (tablet and desktop; keep it short)');
  const navSec = t('Security', 'header navigation link to the guarantees section (tablet and desktop; keep it short)');
  const home = escAttr(t('GenSwarms home', 'header and footer logo link: accessible name (the logo is the lowercase wordmark “genswarms”)', { kind: 'attr' }));
  const RO = readouts(t, nf), TT = roTitles(t);
  // the drawing's words and its text alternatives, in this language
  const zs = { cine: CINE, ...canvasStrings(t), aria: ARIA.map((_, k) => aria(t, k)) };
  const html = `<!doctype html>
<html lang="${code}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escText(title)}</title>
<meta name="description" content="${escAttr(desc)}">
<link rel="canonical" href="${url}">${hreflang}
<meta http-equiv="content-language" content="${code}">
<meta name="theme-color" content="#0D0E10">
<meta property="og:type" content="website"><meta property="og:locale" content="${cur.og}">
<meta property="og:title" content="${escAttr(title)}">
<meta property="og:description" content="${escAttr(ogDesc)}">
<meta property="og:url" content="${url}"><meta property="og:image" content="${ORIGIN}${ogImage}">
<meta property="og:image:width" content="1200"><meta property="og:image:height" content="630"><meta property="og:image:alt" content="${escAttr(title)}">
<meta name="twitter:card" content="summary_large_image">
<link rel="icon" href="/favicon.svg" type="image/svg+xml"><link rel="icon" href="/favicon-32.png" sizes="32x32"><link rel="apple-touch-icon" href="/apple-touch-icon.png">
<script type="application/ld+json">${json(ld)}</script>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
${type.fonts.map(h => `<link href="${h}" rel="stylesheet" media="print" onload="this.media='all'">`).join('\n')}
<noscript>${type.fonts.map(h => `<link href="${h}" rel="stylesheet">`).join('')}</noscript>
<script>(function(){var d=document.documentElement;d.classList.add('js');if(matchMedia('${CINE}').matches)d.classList.add('cine')})()</script>
<style>
${css}${multi ? '\n' + i18nCSS + navCSS([navHow, navCmp, navSec, docs]) : ''}${type.css ? '\n' + minCSS(type.css) : ''}
</style>
</head>
<body>
<a class="skip" href="#main">${t('Skip to content', 'skip link (first thing keyboard users reach; jumps past the header to the page’s content)')}</a>
<header class="top"><div class="wrap top-in">
<a class="brand" href="#s0" aria-label="${home}">${WORD}</a>
<nav aria-label="${escAttr(t('Primary', 'header navigation: accessible name (landmark label read by screen readers)', { kind: 'attr' }))}">
<a href="#how">${navHow}</a>
<a href="#compare">${navCmp}</a>
<a href="#security">${navSec}</a>
<a href="/docs/">${docs}</a>
<a class="gh" href="https://github.com/genlayerlabs/genswarms">GitHub</a>${picker}
</nav>
</div></header>
<main id="main">
<section class="story" aria-label="${escAttr(t('What GenSwarms is', 'the story section: accessible name', { kind: 'attr' }))}">
<div class="story-in">
<div class="stage-col"><div class="stage" data-k="0">
<canvas role="img" aria-label="${escAttr(zs.aria[0])}"></canvas>
<div class="zcap" aria-hidden="true"><span class="lv">${escText(zs.lv[0])}</span><span class="zf"></span><span class="n"></span></div>
<div class="ros" aria-hidden="true">${legend(t)}${[2, 3, 4, 5, 6, 7, 8, 9, 10].map(k => `<div class="ro" data-at="${k}">${TT[k] ? `<p class="ro-t">${TT[k]}</p>` : ''}${RO[k]}</div>`).join('')}</div>
<div class="ill" aria-hidden="true">${t('illustration', 'small label at the bottom right of the drawing: everything it shows is an illustration')}</div>
</div></div>
<div class="steps">
${STEPS.map((s, i) => step(s, i, RO, TT)).join('\n')}
</div>
</div>
</section>

<section class="sec" id="how" aria-labelledby="how-h">
<div class="wrap">
<div class="sec-head"><h2 id="how-h">${t('How it works.', 'section heading (h2) over the spec sheet')}</h2><p>${t('The parts of an operating system, and what GenSwarms puts in each place.', 'sub-line beside the “How it works.” heading')}</p></div>
<dl class="spec">${OS.map(([k, v]) => `<div class="row"><dt>${t(k, 'spec sheet: row label (one word or two)')}</dt><dd>${isKept(v) ? v : t(v, `spec sheet: the “${k}” row (a short line, not a full sentence)`)}</dd></div>`).join('')}</dl>
</div>
</section>

<section class="sec" id="compare" aria-labelledby="cmp-h">
<div class="wrap">
<div class="sec-head"><h2 id="cmp-h">${t('How is it different from LangGraph, CrewAI or AutoGen?', 'section heading (h2) over the comparison table')}</h2><p>${t('Frameworks organize agents in your code. GenSwarms runs each agent as its own supervised process.', 'sub-line beside the comparison heading')}</p></div>
<div class="cmp-wrap"><table class="cmp">
<caption class="sr">${t('GenSwarms compared with LangGraph, CrewAI and AutoGen', 'comparison table caption (screen readers only)')}</caption>
<thead><tr><th scope="col"><span class="sr">${t('Question', 'comparison table: header of the question column (screen readers only)')}</span></th><th scope="col" class="gs"><span class="gs-name">${WORD}</span></th><th scope="col">LangGraph</th><th scope="col">CrewAI</th><th scope="col">AutoGen</th></tr></thead>
<tbody>
${CMP.map(r => `<tr><th scope="row">${t(r[0], 'comparison table: row question')}</th><td class="gs" data-l="GenSwarms">${t(r[1], `comparison table, “${r[0]}”: GenSwarms`)}</td><td data-l="LangGraph">${t(r[2], `comparison table, “${r[0]}”: LangGraph (sourced; keep the facts exact)`)}</td><td data-l="CrewAI">${t(r[3], `comparison table, “${r[0]}”: CrewAI (sourced; keep the facts exact)`)}</td><td data-l="AutoGen">${t(r[4], `comparison table, “${r[0]}”: AutoGen (sourced; keep the facts exact)`)}</td></tr>`).join('\n')}
</tbody></table></div>
<p class="src">${t('From each project’s own documentation, September 2026.', 'small note under the comparison table: where the competitors’ cells come from')}</p>
</div>
</section>

<section class="sec" id="security" aria-labelledby="sec-h">
<div class="wrap">
<div class="sec-head"><h2 id="sec-h">${t('What it guarantees, and what it doesn’t yet.', 'section heading (h2) over the guarantees and limits')}</h2><p>${t('What ships in 0.2.0 today, and the limits we know about.', 'sub-line beside the guarantees heading')}</p></div>
<div class="gu">
<div class="gu-col yes"><h3>${t('Guarantees', 'guarantees section: heading of the list of guarantees (h3)')}</h3><ul>${SEC.yes.map(s => `<li>${t(s, 'guarantees section: an item under “Guarantees” (one short line)')}</li>`).join('')}</ul></div>
<div class="gu-col not"><h3>${t('Not yet', 'guarantees section: heading of the list of limits (h3)')}</h3><ul>${SEC.not.map(s => `<li>${t(s, 'guarantees section: an item under “Not yet” (one short line)')}</li>`).join('')}</ul></div>
</div>
</div>
</section>

<section class="sec close" id="start" aria-labelledby="close-h">
<div class="wrap">
<h2 id="close-h">${t('<span>Start with one team.</span> <span>Scale to thousands of agents.</span>', 'closing section headline (h2, large type): two sentences, each set on its own line (keep the two <span> elements)')}</h2>
<p class="close-p">${t(CLOSE, 'closing section: paragraph under the headline')}</p>
${ctas(t, 'closing section')}
<div class="handoff">
<p id="handoff-l">${t('Or hand it to your agent:', 'closing section: label above the copyable prompt')}</p>
<div class="cmd"><code id="prompt">${t('Read https://genswarms.com/skill.md and set up a swarm.', 'closing section: a prompt the reader copies into their coding agent (keep the URL exactly)')}</code><button type="button" id="copy" aria-describedby="handoff-l" data-idle="${escAttr(copyIdle())}" data-copied="${escAttr(t('Copied', 'copy button: text shown for 2 seconds after the prompt was copied', { kind: 'attr' }))}" data-fallback="${escAttr(t('Selected', 'copy button: text shown when the browser cannot copy (the prompt is selected, for the reader to copy)', { kind: 'attr' }))}">${copyIdle()}</button></div>
</div>
</div>
</section>
</main>
<footer class="foot"><div class="wrap foot-in">
<a class="brand" href="#s0" aria-label="${home}">${WORD}</a>
<p>${t('The operating system for AI workforces.', 'footer: tagline next to the logo')}</p>
<nav aria-label="${escAttr(t('Footer', 'footer navigation: accessible name', { kind: 'attr' }))}"><a href="/docs/">${docs}</a><a href="https://github.com/genlayerlabs/genswarms">GitHub</a><a href="https://github.com/genlayerlabs/genswarms/blob/main/LICENSE">${t('License (MIT)', 'footer link to the license file')}</a><a href="/skill.md">skill.md</a><a href="/llms.txt">llms.txt</a></nav>${footLangs}
<p class="legal">${t('© 2026 GenLayer Labs · MIT License', 'footer: copyright line')}</p>
</div></footer>
<script type="application/json" id="zoom-strings">${json(zs)}</script>
<script>
${js}
</script>${barData}
</body>
</html>
`;
  // minify markup outside the inlined style and script (already minified above)
  return html.split(/(<style>[\s\S]*?<\/style>|<script>[\s\S]*?<\/script>)/).map((part, i) => (i % 2 ? part : minHTML(part))).join('');
}
const copyIdle = () => t('Copy', 'copy button next to the prompt (short: the button is about 80px wide)');
