// The 404 page: one file for every language (GitHub Pages serves it for any missing path). The English is in the
// markup; on a multilingual build a small script swaps in the strings of the language whose folder the missing path
// is in (/es/…, /ko/…), and the fonts that language needs. Strings come from the catalogue.
import { t, escText } from './i18n.mjs';

export const strings404 = () => ({
  title: t('404 — page not found · GenSwarms', '404 page: browser tab title', { kind: '404' }),
  code: t('Error 404', '404 page: small line above the headline', { kind: '404' }),
  h1: t('This page ran off the swarm.', '404 page: headline', { kind: '404' }),
  p: t("The page you're looking for doesn't exist — or it wandered off the topology.", '404 page: text under the headline', { kind: '404' }),
  back: t('Back to home', '404 page: button back to the home page', { kind: '404' }),
  docs: t('Read the docs', '404 page: link to the documentation', { kind: '404' }),
});

// same system faces as the translated pages (src/page.mjs): the 404's brand fonts have no Cyrillic, Hangul or Han
const FONTS = `:lang(ru) body,:lang(ru) h1{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"Noto Sans",sans-serif}
:lang(ko) body,:lang(ko) h1{font-family:"Apple SD Gothic Neo","Noto Sans KR","Malgun Gothic",sans-serif;word-break:keep-all}
:lang(zh-Hans) body,:lang(zh-Hans) h1{font-family:"PingFang SC","Hiragino Sans GB","Noto Sans SC","Microsoft YaHei",sans-serif}
:lang(ko) h1,:lang(zh-Hans) h1{letter-spacing:0;line-height:1.15}`;

// byLang: { es: { lang: 'es', home: '/es/', ...strings404() in Spanish }, ... } (English stays in the markup)
export function render404(byLang = null) {
  const { title, code, h1, p, back, docs } = Object.fromEntries(Object.entries(strings404()).map(([k, v]) => [k, escText(v)]));
  const multi = byLang && Object.keys(byLang).length;
  const head = multi ? `\n<style>\n${FONTS}\n</style>` : '';
  const body = multi ? `<script id="i18n-404">
(function(){
  var L=${JSON.stringify(byLang).replace(/</g, '\\u003c')};
  var s=L[location.pathname.split('/')[1]]; if(!s) return;
  document.documentElement.lang=s.lang; document.title=s.title;
  document.querySelector('.code').textContent=s.code;
  document.querySelector('h1').textContent=s.h1;
  document.querySelector('p').textContent=s.p;
  var a=document.querySelector('.btn-primary'); a.firstChild.textContent=s.back+' '; a.setAttribute('href', s.home);
  document.querySelector('.btn-ghost').textContent=s.docs;
})();
</script>
` : '';
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<title>${title}</title>
<meta name="robots" content="noindex" />
<link rel="icon" href="/favicon.svg" type="image/svg+xml" />
<link rel="icon" type="image/png" sizes="32x32" href="/favicon-32.png" />
<link rel="apple-touch-icon" sizes="180x180" href="/apple-touch-icon.png" />
<link rel="preconnect" href="https://fonts.googleapis.com" />
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
<link href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@12..96,700;12..96,800&family=Instrument+Sans:wght@400;500;600&family=JetBrains+Mono:wght@500&display=swap" rel="stylesheet" />
<style>
:root{--sand:#E9E0D2;--ink:#33301f;--ink-2:#5f5946;--clay:#A84E36;--r-spring:cubic-bezier(.2,.9,.25,1)}
*{margin:0;padding:0;box-sizing:border-box}
::selection{background:var(--clay);color:#fff}
body{min-height:100vh;display:flex;align-items:center;justify-content:center;background:var(--sand);color:var(--ink);font-family:"Instrument Sans",sans-serif;-webkit-font-smoothing:antialiased;padding:32px;text-align:center}
.wrap{max-width:540px}
.mark{width:46px;height:46px;margin:0 auto 30px;display:block}
.mark line{stroke:var(--ink);stroke-opacity:.35;stroke-width:1.1}
.mark circle{fill:var(--clay)}
.code{font-family:"JetBrains Mono",monospace;font-size:13px;letter-spacing:.18em;text-transform:uppercase;color:var(--ink-2);margin-bottom:14px}
h1{font-family:"Bricolage Grotesque",sans-serif;font-weight:800;font-size:clamp(40px,9vw,72px);line-height:1;letter-spacing:-.03em;margin-bottom:16px;text-wrap:balance}
p{font-size:16.5px;color:var(--ink-2);max-width:34ch;margin:0 auto 30px;text-wrap:pretty}
.row{display:flex;gap:14px;justify-content:center;flex-wrap:wrap}
.btn{display:inline-flex;align-items:center;gap:8px;font-size:15px;font-weight:600;padding:12px 20px;min-height:44px;border-radius:11px;text-decoration:none;transition:transform .3s var(--r-spring),background .3s ease}
.btn-primary{background:var(--ink);color:var(--sand)}
.btn-primary:hover{background:var(--clay)}
.btn-ghost{color:var(--ink);border:0;text-decoration:underline;text-decoration-thickness:1px;text-underline-offset:5px}
.btn-ghost:hover{text-decoration-thickness:2px}
.btn svg{transition:transform .35s var(--r-spring)}
.btn:hover svg{transform:translateX(3px)}
</style>${head}
</head>
<body>
  <div class="wrap">
    <svg class="mark" viewBox="0 0 26 26" aria-hidden="true">
      <line x1="6" y1="6" x2="20" y2="9"/><line x1="6" y1="6" x2="9" y2="20"/>
      <line x1="20" y1="9" x2="20" y2="20"/><line x1="9" y1="20" x2="20" y2="20"/>
      <line x1="6" y1="6" x2="20" y2="20"/>
      <circle cx="6" cy="6" r="2.6"/><circle cx="20" cy="9" r="2.6"/>
      <circle cx="9" cy="20" r="2.6"/><circle cx="20" cy="20" r="2.6"/>
    </svg>
    <div class="code">${code}</div>
    <h1>${h1}</h1>
    <p>${p}</p>
    <div class="row">
      <a class="btn btn-primary" href="/">${back} <svg width="13" height="13" viewBox="0 0 13 13" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M3 10L10 3M10 3H4M10 3V9"/></svg></a>
      <a class="btn btn-ghost" href="/docs/">${docs}</a>
    </div>
  </div>
${body}</body>
</html>
`;
}
