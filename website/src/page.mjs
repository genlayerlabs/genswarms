import { readFileSync } from 'node:fs';
import { L, P, system, figureCSS } from './figures.mjs';
import { STAGES, CROP, STEPS, OS, SEC, CMP } from './content.mjs';

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

const still = k => `<figure class="still" aria-label="Figure ${k + 1}">
  ${system(L, k, { label: STAGES[k].aria, crop: CROP.L[k], prune: true })}
  ${system(P, k, { label: STAGES[k].aria, crop: CROP.P[k], prune: true })}
  ${STAGES[k].note ? `<figcaption class="fig-note">${STAGES[k].note}</figcaption>` : ''}
</figure>`;

const stepsHTML = STEPS.map((c, k) => `<article class="step${k === 0 ? ' step-hero' : ''}" id="s${k}" data-step="${k}">
  ${c}
  ${still(k)}
</article>`).join('\n');

const mark = (cls = '') => `<svg class="mark ${cls}" viewBox="0 0 26 26" aria-hidden="true"><g stroke="currentColor" stroke-width="1.3"><line x1="6" y1="6" x2="20" y2="9"/><line x1="6" y1="6" x2="9" y2="20"/><line x1="20" y1="9" x2="20" y2="20"/><line x1="9" y1="20" x2="20" y2="20"/><line x1="6" y1="6" x2="20" y2="20"/></g><g fill="currentColor"><circle cx="6" cy="6" r="2.6"/><circle cx="20" cy="9" r="2.6"/><circle cx="9" cy="20" r="2.6"/><circle cx="20" cy="20" r="2.6"/></g></svg>`;

export function renderPage() {
  const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>GenSwarms: the operating system for AI workforces</title>
<meta name="description" content="GenSwarms runs AI agents as separate, supervised processes on declared message paths, with an API and a live event stream. Open source, MIT.">
<link rel="canonical" href="https://genswarms.com/">
<meta http-equiv="content-language" content="en">
<meta property="og:type" content="website"><meta property="og:locale" content="en_US">
<meta property="og:title" content="GenSwarms: the operating system for AI workforces">
<meta property="og:description" content="Deploy, coordinate and control AI agents as separate, supervised processes.">
<meta property="og:url" content="https://genswarms.com/"><meta property="og:image" content="https://genswarms.com/og-image.png">
<meta name="twitter:card" content="summary_large_image">
<link rel="icon" href="/favicon.svg" type="image/svg+xml"><link rel="icon" href="/favicon-32.png" sizes="32x32"><link rel="apple-touch-icon" href="/apple-touch-icon.png">
<script type="application/ld+json">{"@context":"https://schema.org","@type":"SoftwareApplication","name":"GenSwarms","applicationCategory":"DeveloperApplication","operatingSystem":"Linux, macOS","softwareVersion":"0.2.0","license":"https://opensource.org/licenses/MIT","url":"https://genswarms.com/","codeRepository":"https://github.com/genlayerlabs/genswarms","description":"The operating system for AI workforces: runs AI agents as separate, supervised processes on declared message paths, with a REST + WebSocket API and a live event stream.","offers":{"@type":"Offer","price":"0","priceCurrency":"USD"},"author":{"@type":"Organization","name":"GenLayer Labs"}}</script>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@12..96,400..800&family=Instrument+Sans:ital,wght@0,400;0,500;0,600;1,400&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
<script>if(matchMedia('(min-width: 1000px) and (min-height: 600px)').matches&&!matchMedia('(prefers-reduced-motion: reduce)').matches)document.documentElement.classList.add('cine')</script>
<style>
${css}
${minCSS(figureCSS(CROP.L))}
</style>
</head>
<body>
<a class="skip" href="#os">Skip to how it works</a>
<header class="top">
  <a class="brand" href="#s0" aria-label="GenSwarms home">${mark()}GenSwarms</a>
  <nav aria-label="Primary">
    <a href="#os">How it works</a>
    <a href="#compare">Compare</a>
    <a href="#security">Security</a>
    <a href="/docs/">Docs</a>
    <a class="gh" href="https://github.com/genlayerlabs/genswarms">GitHub</a>
  </nav>
</header>

<main id="main">
<section class="story" aria-label="What GenSwarms is">
  <div class="steps">
${stepsHTML}
  </div>
  <div class="stage-col">
    <div class="stage">
      <figure class="stage-fig">
        ${system(L, 0, { extraClass: 'live', label: STAGES[0].aria })}
        <figcaption class="stage-cap fig-note">${STAGES.map((s, k) => s.note ? `<span data-at="${k}">${s.note}</span>` : '').join('')}</figcaption>
      </figure>
      <ol class="rail" aria-label="Story chapters">
        ${STAGES.map((s, k) => `<li><button type="button" data-go="${k}" aria-label="Go to figure ${k + 1}"${k === 0 ? ' aria-current="step"' : ''}></button></li>`).join('')}
      </ol>
    </div>
  </div>
</section>

<div class="proof">
<section class="band" id="os" aria-labelledby="os-h">
  <div class="band-head">
    <h2 id="os-h">How it works.</h2>
  </div>
  <dl class="spec">
    ${OS.map(([k, v]) => `<div><dt>${k}</dt><dd>${v}</dd></div>`).join('\n    ')}
  </dl>
</section>

<section class="band" id="compare" aria-labelledby="cmp-h">
  <div class="band-head">
    <h2 id="cmp-h">How is it different from LangGraph, CrewAI or AutoGen?</h2>
  </div>
  <div class="cmp-wrap">
    <table class="cmp">
      <caption class="sr">GenSwarms compared with LangGraph, CrewAI and AutoGen</caption>
      <thead><tr><th scope="col"><span class="sr">Question</span></th><th scope="col" class="gs">GenSwarms</th><th scope="col">LangGraph</th><th scope="col">CrewAI</th><th scope="col">AutoGen</th></tr></thead>
      <tbody>
      ${CMP.map(r => `<tr><th scope="row">${r[0]}</th><td class="gs" data-l="GenSwarms">${r[1]}</td><td data-l="LangGraph">${r[2]}</td><td data-l="CrewAI">${r[3]}</td><td data-l="AutoGen">${r[4]}</td></tr>`).join('\n      ')}
      </tbody>
    </table>
  </div>
</section>

<section class="band" id="security" aria-labelledby="sec-h">
  <div class="band-head">
    <h2 id="sec-h">What it guarantees, and what it doesn’t yet.</h2>
  </div>
  <div class="sec-cols">
    <div class="sec-col">
      <h3>Guarantees</h3>
      <ul class="yes">${SEC.yes.map(t => `<li>${t}</li>`).join('')}</ul>
    </div>
    <div class="sec-col">
      <h3>Not yet</h3>
      <ul class="not">${SEC.not.map(t => `<li>${t}</li>`).join('')}</ul>
    </div>
  </div>
</section>
</div>

<section class="close" id="start" aria-labelledby="close-h">
  <div class="close-in">
    <h2 id="close-h">Start with one team. Scale to thousands of agents.</h2>
    <p>Instead of building isolated agents, build an AI&nbsp;workforce.</p>
    <div class="ctas"><a class="btn btn-primary" href="/docs/">Read the docs</a><a class="btn btn-ghost" href="https://github.com/genlayerlabs/genswarms">View on GitHub</a></div>
    <div class="handoff">
      <p id="handoff-l">Or hand it to your agent:</p>
      <div class="prompt"><code id="prompt">Read https://genswarms.com/skill.md and set up a swarm.</code><button type="button" id="copy" aria-describedby="handoff-l" data-idle="Copy" data-copied="Copied" data-fallback="Select and copy">Copy</button></div>
    </div>
  </div>
</section>
</main>

<footer class="foot">
  <div class="foot-in">
    <a class="brand" href="#s0">${mark()}GenSwarms</a>
    <p>The operating system for AI workforces.</p>
    <nav aria-label="Footer"><a href="/docs/">Docs</a><a href="https://github.com/genlayerlabs/genswarms">GitHub</a><a href="https://github.com/genlayerlabs/genswarms/blob/main/LICENSE">License</a><a href="/skill.md">skill.md</a><a href="/llms.txt">llms.txt</a></nav>
    <p class="legal">© 2026 GenLayer Labs · MIT License</p>
  </div>
</footer>

<script>
${js}
</script>
</body>
</html>
`;
  // minify markup outside the inlined style and script (already minified above)
  return html.split(/(<style>[\s\S]*?<\/style>|<script>[\s\S]*?<\/script>)/).map((part, i) => (i % 2 ? part : minHTML(part))).join('');
}
