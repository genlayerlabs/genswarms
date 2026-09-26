import { readFileSync } from 'node:fs';
import { L, P, system, figureCSS, em } from './figures.mjs';
import { STAGES, CROP, STEPS, OS, SEC, CMP, CLOSE } from './content.mjs';
import { t, tf, escAttr, escText, isKept, ORIGIN, SNIPPET } from './i18n.mjs';

const here = new URL('.', import.meta.url);
// Build-time minification, deliberately conservative (no external deps):
// CSS loses comments and the whitespace around { } ; , (never around ':' — `.a :focus` is a
// descendant selector); JS loses comment-only lines and indentation but keeps its line breaks
// (no ASI hazards); markup loses indentation after line breaks (a newline run is still one
// space to the HTML parser, so inline text keeps its spacing).
const minCSS = c => c.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\s+/g, ' ').replace(/\s*([{};,])\s*/g, '$1').replace(/;}/g, '}').trim();
const minJS = j => j.split('\n').map(l => l.trim()).filter(l => l && !l.startsWith('//')).join('\n');
const minHTML = h => h.replace(/\n\s+/g, '\n');
const css = minCSS(readFileSync(new URL('page.css', here), 'utf8'));
const js = minJS(readFileSync(new URL('story.js', here), 'utf8'));
// only on multilingual builds: the language picker, the footer's language links and the suggestion bar
const i18nCSS = minCSS(readFileSync(new URL('i18n.css', here), 'utf8'));
const langbarJS = minJS(readFileSync(new URL('langbar.js', here), 'utf8'));

// ---------- per writing system (playbook §9) ----------
// Bricolage Grotesque and Instrument Sans have no Cyrillic, Hangul or Han glyphs: those pages set text and titles
// in good system faces and load only what they still use (JetBrains Mono for code and identifiers, and the Latin
// wordmark "GenSwarms" in Bricolage, fetched for those nine letters only). CJK pages do not load Instrument Sans for
// Latin runs: the system CJK faces carry matching Latin glyphs, and mixing faces inside one sentence reads worse.
const FONTS_ALL = 'https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@12..96,400..800&family=Instrument+Sans:ital,wght@0,400;0,500;0,600;1,400&family=JetBrains+Mono:wght@400;500&display=swap';
const FONTS_SYS = ['https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500&display=swap',
  'https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@12..96,700&text=GenSwarms&display=swap'];
const WORDMARK = `.brand,.sys .tb.bandl{font-family:'Bricolage Grotesque',ui-sans-serif,system-ui,sans-serif}`;
const SYS = {
  ru: `-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,'Noto Sans',sans-serif`,
  ko: `'Apple SD Gothic Neo','Noto Sans KR','Malgun Gothic',sans-serif`,
  'zh-Hans': `'PingFang SC','Hiragino Sans GB','Noto Sans SC','Microsoft YaHei',sans-serif`,
};
// titles: every display-type element on the page
const TITLES = 'h1,h2,h3,.triad span,.spec dt,.cmp thead th,.sys .tb:not(.bandl)';
// long words (Russian, Turkish): hyphenate titles and scale the display sizes with the phone's width
const LONG = `${TITLES.replace('.sys .tb:not(.bandl)', '.cmp tbody th')}{hyphens:auto;-webkit-hyphens:auto;overflow-wrap:break-word}
@media (max-width:759px){h1{font-size:clamp(34px,10.6vw,64px)}.step h2{font-size:clamp(28px,8.4vw,52px)}.band-head h2{font-size:clamp(26px,7.4vw,46px)}.close h2{font-size:clamp(32px,9.6vw,104px)}.triad span{font-size:clamp(26px,7vw,54px)}}`;
// CJK: no negative tracking on titles, taller title lines, upright example lines
const CJK_CSS = `${TITLES}{letter-spacing:0}h1{line-height:1.12}.step h2,.close h2,.triad span{line-height:1.16}.band-head h2{line-height:1.2}.copy .ex,.sys .logcap{font-style:normal}`;
// the comparison table: words stay whole (hyphenating split "agen-te", "Lang-Smith", "Gen-Swarms"); at 1000-1279px the
// table takes the band's full width (page.css), so its columns are wide enough. A word longer than its column still breaks
const TABLE = `.cmp th,.cmp td{overflow-wrap:break-word}`;
const TYPE = {
  es: { fonts: [FONTS_ALL], css: TABLE },
  // the desktop hero is ~20% smaller in Russian so «Операционная» stays one word at 1000-1440px
  ru: { fonts: FONTS_SYS, css: `:root{--fd:${SYS.ru};--ft:${SYS.ru}}${WORDMARK}${LONG}${TABLE}@media (min-width:1000px){h1,.cine h1{font-size:4.3vw}}` },
  tr: { fonts: [FONTS_ALL], css: LONG + TABLE },
  ko: { fonts: FONTS_SYS, css: `:root{--fd:${SYS.ko};--ft:${SYS.ko}}${WORDMARK}body{word-break:keep-all;overflow-wrap:break-word}${CJK_CSS}` },
  // Chinese wraps between any two characters: keep paragraphs from ending on one stranded character
  'zh-Hans': { fonts: FONTS_SYS, css: `:root{--fd:${SYS['zh-Hans']};--ft:${SYS['zh-Hans']}}${WORDMARK}${CJK_CSS}.lead,.close p,.sec-col li{text-wrap:pretty}` },
};

const still = k => `<figure class="still" aria-label="${escAttr(tf('Figure {n}', { n: k + 1 }, 'story figures: accessible name of each drawing ({n} = 1…9)', { kind: 'attr' }))}">
  ${system(L, k, { label: aria(k), crop: CROP.L[k], prune: true })}
  ${system(P, k, { label: aria(k), crop: CROP.P[k], prune: true })}
  ${STAGES[k].note ? `<figcaption class="fig-note">${note()}</figcaption>` : ''}
</figure>`;
const aria = k => escAttr(t(STAGES[k].aria, `figure ${k + 1}: text alternative of the drawing (aria-label; read by screen readers, not shown)`, { kind: 'attr' }));
const note = () => t('illustration', 'small caption under figures 5-8, which show simulated events and placeholder data');

// each rail button is named after its step's visible headline (h1/h2), so the words match the
// page and translate with it
const headline = c => c.match(/<h[12]>([\s\S]*?)<\/h[12]>/)[1].replace(/<[^>]+>/g, '').replace(/&nbsp;/g, ' ').trim();

const mark = (cls = '') => `<svg class="mark ${cls}" viewBox="0 0 26 26" aria-hidden="true"><g stroke="currentColor" stroke-width="1.3"><line x1="6" y1="6" x2="20" y2="9"/><line x1="6" y1="6" x2="9" y2="20"/><line x1="20" y1="9" x2="20" y2="20"/><line x1="9" y1="20" x2="20" y2="20"/><line x1="6" y1="6" x2="20" y2="20"/></g><g fill="currentColor"><circle cx="6" cy="6" r="2.6"/><circle cx="20" cy="9" r="2.6"/><circle cx="9" cy="20" r="2.6"/><circle cx="20" cy="20" r="2.6"/></g></svg>`;

// The header on a multilingual page carries the language picker too. Translated link names differ in length, so the
// breakpoints where the section links, and then "Docs", leave the header are computed from their estimated widths
// (15px text; 4px to spare). English keeps page.css's 719px.
// These numbers mirror page.css, keep them in step with it: 149 = .brand (24px .mark + 10px gap + "GenSwarms" in
// 700 20px Bricolage), 24 = .top's gap, 51 = the .gh link, 44 = the picker's summary (i18n.css), g() = --g and
// gap() = .top nav's gap. i18n-audit.cjs catches drift (header items overlapping or leaving the screen).
function navCSS(labels) {
  const g = W => Math.max(16, Math.min(64, 0.042 * W)), gap = W => Math.max(14, Math.min(30, 0.022 * W));
  const fits = (W, items) => 149 + 24 + items.reduce((n, w) => n + w, 0) + gap(W) * (items.length - 1) + 2 * g(W) + 4 <= W;
  const [how, cmp, sec, docs] = labels.map(s => em(s) * 15), gh = 51, pick = 44;
  const from = items => { for (let W = 320; W < 1400; W++) if (fits(W, items)) return W; return 1400; };
  const all = from([how, cmp, sec, docs, gh, pick]), some = from([docs, gh, pick]);
  return (all > 720 ? `@media (max-width:${all - 1}px){.top nav>a:not(.gh):not([href="/docs/"]){display:none}}` : '') +
    (some > 320 ? `@media (max-width:${some - 1}px){.top nav>a[href="/docs/"]{display:none}}` : '');
}

const langLinks = (langs, code) => langs.map(l => `<a href="/${l.dir}" hreflang="${l.code}" lang="${l.code}"${l.code === code ? ' aria-current="page"' : ''}>${l.name}</a>`);

// renderPage({ lang, langs }): the page in the current t() language (see withLang in src/i18n.mjs). `langs` lists
// every version being built; with more than English it adds hreflang, the picker, the footer's language links and
// the suggestion bar. An English-only build is exactly the English page.
export function renderPage({ lang: code = 'en', langs = null, bar = null, ogImage = 'og-image.png' } = {}) {
  const multi = langs && langs.length > 1;
  const cur = multi ? langs.find(l => l.code === code) : { code: 'en', dir: '', og: 'en_US', short: 'EN' };
  const url = ORIGIN + cur.dir;
  const type = TYPE[code] || { fonts: [FONTS_ALL], css: '' };
  const title = t('GenSwarms: the operating system for AI workforces', 'page title (browser tab, search result title, share title)', { kind: 'meta' });
  const desc = t('GenSwarms runs AI agents as separate, supervised processes on declared message paths, with an API and a live event stream. Open source, MIT.', 'meta description (search result snippet)', { kind: 'meta', limit: SNIPPET });
  const ogDesc = t('Deploy, coordinate and control AI agents as separate, supervised processes.', 'og:description (share preview text)', { kind: 'meta', limit: SNIPPET });
  const ld = { '@context': 'https://schema.org', '@type': 'SoftwareApplication', name: 'GenSwarms', applicationCategory: 'DeveloperApplication', operatingSystem: 'Linux, macOS', softwareVersion: '0.2.0', license: 'https://opensource.org/licenses/MIT', url, codeRepository: 'https://github.com/genlayerlabs/genswarms',
    description: t('The operating system for AI workforces: runs AI agents as separate, supervised processes on declared message paths, with a REST + WebSocket API and a live event stream.', 'structured data (JSON-LD) description, read by search engines', { kind: 'meta' }),
    ...(multi ? { inLanguage: code } : {}),
    offers: { '@type': 'Offer', price: '0', priceCurrency: 'USD' }, author: { '@type': 'Organization', name: 'GenLayer Labs' } };
  const hreflang = multi ? '\n' + [...langs.map(l => `<link rel="alternate" hreflang="${l.code}" href="${ORIGIN}${l.dir}">`), `<link rel="alternate" hreflang="x-default" href="${ORIGIN}">`].join('\n') : '';
  const langName = t('Language', 'header language picker and footer language links: accessible name (read by screen readers)', { kind: 'attr' });
  const picker = multi ? `\n    <details class="lang"><summary><span class="sr">${langName} </span>${cur.short}</summary><ul>${langLinks(langs, code).map(a => `<li>${a}</li>`).join('')}</ul></details>` : '';
  const footLangs = multi ? `\n    <nav class="foot-langs" aria-label="${escAttr(langName)}">${langLinks(langs, code).join('')}</nav>` : '';
  const barData = multi && bar ? `\n<script type="application/json" id="langbar">${JSON.stringify(bar).replace(/</g, '\\u003c')}</script>\n<script>\n${langbarJS}\n</script>` : '';
  const stepsHTML = STEPS.map((c, k) => `<article class="step${k === 0 ? ' step-hero' : ''}" id="s${k}" data-step="${k}">
  ${c(t)}
  ${still(k)}
</article>`).join('\n');
  const railName = k => escAttr(tf('Step {n}: {title}', { n: k + 1, title: headline(STEPS[k](t)) }, 'story rail (desktop): accessible name of each chapter button; {title} is that step’s headline', { kind: 'attr' }));
  const docs = t('Docs', 'header navigation link (keep it short: on phones it shares the header with the logo, GitHub and the language picker); footer link');
  const navHow = t('How it works', 'header navigation link to the “How it works.” section (tablet and desktop; keep it short)');
  const navCmp = t('Compare', 'header navigation link to the comparison table (tablet and desktop; keep it short)');
  const navSec = t('Security', 'header navigation link to the guarantees section (tablet and desktop; keep it short)');
  const html = `<!doctype html>
<html lang="${code}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escText(title)}</title>
<meta name="description" content="${escAttr(desc)}">
<link rel="canonical" href="${url}">${hreflang}
<meta http-equiv="content-language" content="${code}">
<meta property="og:type" content="website"><meta property="og:locale" content="${cur.og}">
<meta property="og:title" content="${escAttr(title)}">
<meta property="og:description" content="${escAttr(ogDesc)}">
<meta property="og:url" content="${url}"><meta property="og:image" content="${ORIGIN}${ogImage}">
<meta name="twitter:card" content="summary_large_image">
<link rel="icon" href="/favicon.svg" type="image/svg+xml"><link rel="icon" href="/favicon-32.png" sizes="32x32"><link rel="apple-touch-icon" href="/apple-touch-icon.png">
<script type="application/ld+json">${JSON.stringify(ld).replace(/</g, '\\u003c')}</script>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
${type.fonts.map(h => `<link href="${h}" rel="stylesheet">`).join('\n')}
<script>if(matchMedia('(min-width: 1000px) and (min-height: 600px) and (orientation: landscape)').matches&&!matchMedia('(prefers-reduced-motion: reduce)').matches)document.documentElement.classList.add('cine')</script>
<style>
${css}
${minCSS(figureCSS(CROP.L))}${multi ? '\n' + i18nCSS + navCSS([navHow, navCmp, navSec, docs]) : ''}${type.css ? '\n' + minCSS(type.css) : ''}
</style>
</head>
<body>
<a class="skip" href="#os">${t('Skip to how it works', 'skip link (first thing keyboard users reach; jumps to the “How it works.” section)')}</a>
<header class="top">
  <a class="brand" href="#s0" aria-label="${escAttr(t('GenSwarms home', 'header logo link: accessible name', { kind: 'attr' }))}">${mark()}GenSwarms</a>
  <nav aria-label="${escAttr(t('Primary', 'header navigation: accessible name (landmark label read by screen readers)', { kind: 'attr' }))}">
    <a href="#os">${navHow}</a>
    <a href="#compare">${navCmp}</a>
    <a href="#security">${navSec}</a>
    <a href="/docs/">${docs}</a>
    <a class="gh" href="https://github.com/genlayerlabs/genswarms">GitHub</a>${picker}
  </nav>
</header>

<main id="main">
<section class="story" aria-label="${escAttr(t('What GenSwarms is', 'the story section: accessible name', { kind: 'attr' }))}">
  <div class="steps">
${stepsHTML}
  </div>
  <div class="stage-col">
    <div class="stage">
      <figure class="stage-fig">
        ${system(L, 0, { extraClass: 'live', label: aria(0) })}
        <figcaption class="stage-cap fig-note">${STAGES.map((s, k) => s.note ? `<span data-at="${k}">${note()}</span>` : '').join('')}</figcaption>
      </figure>
      <ol class="rail" aria-label="${escAttr(t('Story chapters', 'story rail (desktop): accessible name of the list of chapter buttons', { kind: 'attr' }))}">
        ${STAGES.map((s, k) => `<li><button type="button" data-go="${k}" aria-label="${railName(k)}"${k === 0 ? ' aria-current="step"' : ''}></button></li>`).join('')}
      </ol>
    </div>
  </div>
</section>

<div class="proof">
<section class="band" id="os" aria-labelledby="os-h">
  <div class="band-head">
    <h2 id="os-h">${t('How it works.', 'section heading (h2) over the spec sheet')}</h2>
  </div>
  <dl class="spec">
    ${OS.map(([k, v]) => `<div><dt>${t(k, 'spec sheet: row label (one word or two, bold)')}</dt><dd>${isKept(v) ? v : t(v, `spec sheet: the “${k}” row (a short fragment, not a sentence)`)}</dd></div>`).join('\n    ')}
  </dl>
</section>

<section class="band" id="compare" aria-labelledby="cmp-h">
  <div class="band-head">
    <h2 id="cmp-h">${t('How is it different from LangGraph, CrewAI or AutoGen?', 'section heading (h2) over the comparison table')}</h2>
  </div>
  <div class="cmp-wrap">
    <table class="cmp">
      <caption class="sr">${t('GenSwarms compared with LangGraph, CrewAI and AutoGen', 'comparison table caption (screen readers only)')}</caption>
      <thead><tr><th scope="col"><span class="sr">${t('Question', 'comparison table: header of the question column (screen readers only)')}</span></th><th scope="col" class="gs">GenSwarms</th><th scope="col">LangGraph</th><th scope="col">CrewAI</th><th scope="col">AutoGen</th></tr></thead>
      <tbody>
      ${CMP.map(r => `<tr><th scope="row">${t(r[0], 'comparison table: row question')}</th><td class="gs" data-l="GenSwarms">${t(r[1], `comparison table, “${r[0]}”: GenSwarms`)}</td><td data-l="LangGraph">${t(r[2], `comparison table, “${r[0]}”: LangGraph (sourced; keep the facts exact)`)}</td><td data-l="CrewAI">${t(r[3], `comparison table, “${r[0]}”: CrewAI (sourced; keep the facts exact)`)}</td><td data-l="AutoGen">${t(r[4], `comparison table, “${r[0]}”: AutoGen (sourced; keep the facts exact)`)}</td></tr>`).join('\n      ')}
      </tbody>
    </table>
  </div>
</section>

<section class="band" id="security" aria-labelledby="sec-h">
  <div class="band-head">
    <h2 id="sec-h">${t('What it guarantees, and what it doesn’t yet.', 'section heading (h2) over the guarantees and limits')}</h2>
  </div>
  <div class="sec-cols">
    <div class="sec-col">
      <h3>${t('Guarantees', 'guarantees section: heading of the list of guarantees (h3)')}</h3>
      <ul class="yes">${SEC.yes.map(s => `<li>${t(s, 'guarantees section: an item under “Guarantees” (a fragment, lower case)')}</li>`).join('')}</ul>
    </div>
    <div class="sec-col">
      <h3>${t('Not yet', 'guarantees section: heading of the list of limits (h3)')}</h3>
      <ul class="not">${SEC.not.map(s => `<li>${t(s, 'guarantees section: an item under “Not yet” (a fragment, lower case)')}</li>`).join('')}</ul>
    </div>
  </div>
</section>
</div>

<section class="close" id="start" aria-labelledby="close-h">
  <div class="close-in">
    <h2 id="close-h">${t('Start with one team. Scale to thousands of agents.', 'closing section headline (h2, very large type)')}</h2>
    <p>${t(CLOSE, 'closing section: paragraph under the headline')}</p>
    <div class="ctas"><a class="btn btn-primary" href="/docs/">${t('Read the docs', 'closing section: primary button')}</a><a class="btn btn-ghost" href="https://github.com/genlayerlabs/genswarms">${t('View on GitHub', 'closing section: secondary link')}</a></div>
    <div class="handoff">
      <p id="handoff-l">${t('Or hand it to your agent:', 'closing section: label above the copyable prompt')}</p>
      <div class="prompt"><code id="prompt">${t('Read https://genswarms.com/skill.md and set up a swarm.', 'closing section: a prompt the reader copies into their coding agent (keep the URL exactly)')}</code><button type="button" id="copy" aria-describedby="handoff-l" data-idle="${escAttr(copyIdle())}" data-copied="${escAttr(t('Copied', 'copy button: text shown for 2 seconds after the prompt was copied', { kind: 'attr' }))}" data-fallback="${escAttr(t('Select and copy', 'copy button: text shown when the browser cannot copy (the prompt is selected for the reader)', { kind: 'attr' }))}">${copyIdle()}</button></div>
    </div>
  </div>
</section>
</main>

<footer class="foot">
  <div class="foot-in">
    <a class="brand" href="#s0">${mark()}GenSwarms</a>
    <p>${t('The operating system for AI workforces.', 'footer: tagline next to the logo')}</p>
    <nav aria-label="${escAttr(t('Footer', 'footer navigation: accessible name', { kind: 'attr' }))}"><a href="/docs/">${docs}</a><a href="https://github.com/genlayerlabs/genswarms">GitHub</a><a href="https://github.com/genlayerlabs/genswarms/blob/main/LICENSE">${t('License', 'footer link to the license file')}</a><a href="/skill.md">skill.md</a><a href="/llms.txt">llms.txt</a></nav>${footLangs}
    <p class="legal">${t('© 2026 GenLayer Labs · MIT License', 'footer: copyright line')}</p>
  </div>
</footer>

<script>
${js}
</script>${barData}
</body>
</html>
`;
  // minify markup outside the inlined style and script (already minified above)
  return html.split(/(<style>[\s\S]*?<\/style>|<script>[\s\S]*?<\/script>)/).map((part, i) => (i % 2 ? part : minHTML(part))).join('');
}
const copyIdle = () => t('Copy', 'copy button next to the prompt (short: the button is 84px wide)');
