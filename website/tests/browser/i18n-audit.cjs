// website/tests/browser/i18n-audit.cjs — every language version × 14 screen sizes (playbook §10), plus the
// suggestion bar and the no-JS language picker.
//
//   NODE_PATH=<dir with playwright-core> node website/tests/browser/i18n-audit.cjs            pseudo-locales
//   NODE_PATH=<dir with playwright-core> node website/tests/browser/i18n-audit.cjs <BASE>     a served site
//
// Without BASE it builds pseudo-locales for all five languages (website/tools/pseudo.mjs) into a temp dir with the
// site's static files and serves that itself, so it passes before any real translation exists. With BASE (e.g.
// http://localhost:8790/) it audits the versions that site lists in its hreflang links.
//
// Per language and size: no sideways overflow; header items inside the bar and not overlapping; the pinned figure
// fits; step text never under the figure; no HTML text under 12px; 44px tap targets on phones; in every figure
// (stills, and the pinned figure at each of its nine stages) no label overlapping another, running outside the
// drawing or rendering under 12px; the picker marks the current language; no console errors or failed requests.
// The larger-font pass stays in audit.cjs (English only): with every language it would take too long.
// Languages run three at a time (AUDIT_JOBS); AUDIT_LANGS=ru,ko limits the run to those versions.
const { chromium } = require('playwright-core');
const http = require('http');
const fs = require('fs');
const os = require('os');
const path = require('path');

const WEB = path.resolve(__dirname, '../..');
const SIZES = [[320,720],[360,780],[375,812],[390,844],[414,896],[480,900],[600,900],[768,1024],[820,1180],[1024,768],[1280,800],[1440,900],[1440,640],[844,390]];
const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';
const TYPES = { '.html': 'text/html; charset=utf-8', '.xml': 'application/xml', '.txt': 'text/plain; charset=utf-8', '.svg': 'image/svg+xml', '.png': 'image/png', '.md': 'text/markdown' };

async function pseudoSite() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'gs-i18n-'));
  const i18n = path.join(tmp, 'i18n'), out = path.join(tmp, 'site');
  fs.mkdirSync(out);
  for (const f of fs.readdirSync(WEB)) {
    const st = fs.statSync(path.join(WEB, f));
    if (st.isFile()) fs.copyFileSync(path.join(WEB, f), path.join(out, f));
  }
  const { writePseudo } = await import(path.join(WEB, 'tools/pseudo.mjs'));
  const { build } = await import(path.join(WEB, 'src/site.mjs'));
  const { pathToFileURL } = require('url');
  writePseudo(i18n);
  const r = build({ i18nDir: pathToFileURL(i18n + '/'), outDir: pathToFileURL(out + '/') });
  if (r.errors.length) throw new Error('pseudo build refused:\n' + r.errors.join('\n'));
  for (const [f, v] of Object.entries(r.outputs)) { if (v === null) continue; fs.mkdirSync(path.dirname(path.join(out, f)), { recursive: true }); fs.writeFileSync(path.join(out, f), v); }
  // a static server that behaves like GitHub Pages: /es -> 301 /es/, a missing path -> 404.html
  const server = http.createServer((req, res) => {
    const u = decodeURIComponent(new URL(req.url, 'http://x').pathname);
    let p = path.join(out, u);
    if (!p.startsWith(out)) { res.writeHead(403); return res.end(); }
    if (fs.existsSync(p) && fs.statSync(p).isDirectory()) {
      if (!u.endsWith('/')) { res.writeHead(301, { Location: u + '/' }); return res.end(); }
      p = path.join(p, 'index.html');
    }
    if (!fs.existsSync(p)) { res.writeHead(404, { 'Content-Type': TYPES['.html'] }); return res.end(fs.readFileSync(path.join(out, '404.html'))); }
    res.writeHead(200, { 'Content-Type': TYPES[path.extname(p)] || 'application/octet-stream' });
    res.end(fs.readFileSync(p));
  });
  await new Promise(r => server.listen(0, '127.0.0.1', r));
  return { base: `http://127.0.0.1:${server.address().port}/`, close: () => { server.close(); fs.rmSync(tmp, { recursive: true, force: true }); } };
}

// runs in the page: label problems inside every visible system figure
function figureProblems() {
  const out = [];
  const hidden = (e, svg) => { for (let x = e; x && x !== svg.parentNode; x = x.parentElement) { const cs = getComputedStyle(x); if (cs.opacity === '0' || cs.display === 'none' || cs.visibility === 'hidden') return true; } return false; };
  document.querySelectorAll('svg.sys').forEach(svg => {
    const sr = svg.getBoundingClientRect();
    if (!sr.width || hidden(svg, svg)) return;
    const name = `${svg.classList.contains('live') ? 'pinned figure' : 'figure ' + (+svg.getAttribute('data-s') + 1)} (${svg.classList.contains('P') ? 'phone' : 'desktop'} drawing, stage ${svg.getAttribute('data-s')})`;
    const sc = svg.getScreenCTM().a;
    const texts = [...svg.querySelectorAll('text')].filter(t => t.getClientRects().length && !hidden(t, svg)).map(t => ({ t, r: t.getBoundingClientRect(), s: t.textContent.trim() }));
    for (const { t, r, s } of texts) {
      // (the English design renders its phone figures at 11.5px on a 320px screen: the floor there is 11px, and 12px
      // from 360px, where story.cjs holds English to 13px)
      const px = parseFloat(getComputedStyle(t).fontSize) * sc;
      if (px < (innerWidth < 360 ? 11 : 12)) out.push(`${name}: "${s}" renders at ${px.toFixed(1)}px`);
      if (r.left < sr.left - 1 || r.right > sr.right + 1) out.push(`${name}: "${s}" runs outside the drawing`);
      // a label's box includes the font's full ascent and descent: compare roughly where its glyphs are
      if (!svg.classList.contains('live') && (r.top + r.height * 0.15 < sr.top - 1 || r.bottom - r.height * 0.25 > sr.bottom + 1)) out.push(`${name}: "${s}" is cut off by the crop`);
    }
    for (let i = 0; i < texts.length; i++) for (let j = i + 1; j < texts.length; j++) {
      const a = texts[i].r, b = texts[j].r;
      const ox = Math.min(a.right, b.right) - Math.max(a.left, b.left), oy = Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top);
      if (ox > 1 && oy > 2) out.push(`${name}: "${texts[i].s}" overlaps "${texts[j].s}"`);
    }
  });
  return out;
}

(async () => {
  const arg = process.argv[2];
  const site = arg ? { base: arg.replace(/\/?$/, '/'), close: () => {} } : await pseudoSite();
  const BASE = site.base;
  const b = await chromium.launch({ executablePath: process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' });
  const problems = [];
  // the versions: whatever the English page lists
  let p0 = await b.newPage();
  await p0.goto(BASE);
  const langs = await p0.evaluate(() => [...document.querySelectorAll('link[rel=alternate][hreflang]')].filter(l => l.hreflang !== 'x-default').map(l => [l.hreflang, new URL(l.href).pathname]));
  await p0.close();
  if (!langs.length) langs.push(['en', '/']);
  // AUDIT_LANGS=ru,ko audits only those versions (the suggestion bar needs at least two)
  if (process.env.AUDIT_LANGS) langs.splice(0, langs.length, ...langs.filter(l => process.env.AUDIT_LANGS.split(',').includes(l[0])));
  console.log(`auditing ${langs.map(l => l[0]).join(', ')} at ${BASE}`);

  // languages run side by side (AUDIT_JOBS, default 3), sizes one after another within a language
  const auditLang = async ([lang, dir]) => {
    for (const [w, h] of SIZES) {
      const phone = w <= 820 && h > w;
      const c = await b.newContext({ viewport: { width: w, height: h }, isMobile: phone, hasTouch: phone });
      const p = await c.newPage(); const errs = [];
      p.on('pageerror', e => errs.push(e.message)); p.on('console', m => m.type() === 'error' && errs.push(m.text()));
      p.on('requestfailed', r => errs.push('failed ' + r.url()));
      p.on('response', r => r.status() >= 400 && errs.push(r.status() + ' ' + r.url()));
      await p.goto(BASE + dir.slice(1), { waitUntil: 'networkidle' });
      await p.evaluate(() => document.fonts.ready);
      const at = `${lang} ${w}x${h}`;
      // header: every item inside the bar, none overlapping, link text on one line; the picker marks this page
      (await p.evaluate(() => {
        const o = [], hit = (a, b) => a.left < b.right - 1 && b.left < a.right - 1 && a.top < b.bottom - 1 && b.top < a.bottom - 1;
        const items = [document.querySelector('.top .brand'), ...document.querySelectorAll('.top nav > a, .top nav > .lang')].filter(e => e && e.offsetParent).map(e => [e, e.getBoundingClientRect()]);
        for (let i = 0; i < items.length; i++) {
          if (items[i][1].right > innerWidth || items[i][1].left < 0) o.push(`header: ${items[i][0].textContent.trim().slice(0, 16)} outside the screen`);
          for (let j = i + 1; j < items.length; j++) if (hit(items[i][1], items[j][1])) o.push(`header: ${items[i][0].textContent.trim().slice(0, 16)} overlaps ${items[j][0].textContent.trim().slice(0, 16)}`);
          if (items[i][1].height > 50) o.push(`header: ${items[i][0].textContent.trim().slice(0, 16)} wraps`);
        }
        const cur = document.querySelector('.lang a[aria-current="page"]'), foot = document.querySelector('.foot-langs a[aria-current="page"]');
        if (document.querySelector('.lang') && (!cur || cur.lang !== document.documentElement.lang)) o.push('picker does not mark this language');
        if (document.querySelector('.foot-langs') && (!foot || foot.lang !== document.documentElement.lang)) o.push('footer links do not mark this language');
        return o;
      })).forEach(m => problems.push(`${at}: ${m}`));
      // the picker's list opens inside the screen
      if (await p.$('details.lang')) {
        await p.click('details.lang summary');
        const r = await p.evaluate(() => { const u = document.querySelector('details.lang ul').getBoundingClientRect(); return u.width && u.left >= 0 && u.right <= innerWidth && document.querySelector('details.lang').open; });
        if (!r) problems.push(`${at}: the picker's list does not open inside the screen`);
        await p.keyboard.press('Escape');
      }
      // what doesn't depend on the scroll position, once: text sizes, tap targets, the stills; then scroll through the
      // page like audit.cjs for what does
      (await p.evaluate(({ phone }) => {
        const o = [];
        const tw = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
        for (let n; (n = tw.nextNode());) { const e = n.parentElement; if (!n.textContent.trim() || !e.offsetParent || e.closest('svg,.skip,.sr')) continue;
          if (parseFloat(getComputedStyle(e).fontSize) < 12) o.push('text < 12px: ' + n.textContent.trim().slice(0, 20)); }
        // (inline links inside running text or prose lists are exempt, as in audit.cjs; the picker's links are not)
        if (phone) for (const a of document.querySelectorAll('a,button,summary')) { if (!a.offsetParent || a.classList.contains('skip')) continue;
          if (a.tagName === 'A' && a.closest('p,li') && !a.closest('.lang')) continue;
          const r = a.getBoundingClientRect(); if (r.height < 44) o.push('tap target ' + Math.round(r.height) + 'px: ' + a.textContent.trim().slice(0, 20)); }
        return o;
      }, { phone })).forEach(m => problems.push(`${at}: ${m}`));
      (await p.evaluate(figureProblems)).forEach(m => problems.push(`${at}: ${m}`));
      const H = await p.evaluate(() => document.documentElement.scrollHeight);
      for (let y = 0; y < H; y += h) {
        await p.evaluate(y => scrollTo(0, y), y); await p.waitForTimeout(80);
        const r = await p.evaluate(({ phone }) => {
          const o = [], de = document.documentElement;
          if (de.scrollWidth > innerWidth) o.push(`overflow ${de.scrollWidth}`);
          const fig = document.querySelector('.cine .stage');
          if (fig) {
            const f = fig.getBoundingClientRect(), liveSvg = document.querySelector('.cine .sys.live');
            if (Math.abs(f.top) < 2 && liveSvg) {
              const s = liveSvg.getBoundingClientRect(), cap = document.querySelector('.cine .stage-cap');
              const capBottom = cap && cap.offsetParent ? cap.getBoundingClientRect().bottom : s.bottom;
              if (s.top < -1 || Math.max(s.bottom, capBottom) > innerHeight + 1) o.push('pinned figure taller than viewport');
            }
            for (const t of document.querySelectorAll('.step .copy')) { const b = t.getBoundingClientRect();
              if (b.bottom > 0 && b.top < innerHeight && b.left < f.right && f.left < b.right && b.top < f.bottom && f.top < b.bottom) o.push('step text under figure'); }
          }
          return o;
        }, { phone });
        r.forEach(m => problems.push(`${at}: ${m}`));
      }
      // the pinned figure at every stage (transitions off, so each drawing is measured as it settles)
      if (await p.$('.cine .sys.live')) {
        await p.addStyleTag({ content: '*,*::before,*::after{transition:none!important;animation:none!important}' });
        await p.evaluate(() => scrollTo(0, document.querySelector('.story').offsetTop + 50));
        for (let k = 0; k <= 8; k++) {
          await p.evaluate(k => document.querySelector('.sys.live').setAttribute('data-s', k), k);
          (await p.evaluate(figureProblems)).forEach(m => problems.push(`${at}: ${m}`));
        }
      }
      errs.forEach(m => problems.push(`${at}: ${m}`));
      await c.close();
    }
    process.stdout.write(`${lang} `);
  };
  const queue = [...langs];
  await Promise.all(Array.from({ length: Math.min(+process.env.AUDIT_JOBS || 3, queue.length) }, async () => { while (queue.length) await auditLang(queue.shift()); }));
  console.log('');

  // the suggestion bar: offer, never redirect; remembered once dismissed or chosen; never Simplified for zh-TW
  const codes = langs.map(l => l[0]), dirOf = Object.fromEntries(langs);
  const bar = async (locales, dir, expect, { ua = UA, then } = {}) => {
    const c = await b.newContext({ locale: locales[0], userAgent: ua, extraHTTPHeaders: { 'Accept-Language': locales.join(',') } });
    await c.addInitScript(l => Object.defineProperty(navigator, 'languages', { get: () => l }), locales);
    const p = await c.newPage();
    await p.goto(BASE + dir.slice(1), { waitUntil: 'networkidle' });
    const got = await p.evaluate(() => { const b = document.querySelector('.langbar'); return b && { lang: b.lang, text: b.innerText.replace(/\s+/g, ' '), href: b.querySelector('a').getAttribute('href') }; });
    const tag = `bar ${locales.join(',')} on ${dir}${ua === UA ? '' : /bot/i.test(ua) ? ' (crawler UA)' : ' (headless UA)'}`;
    if (!p.url().endsWith(dir)) problems.push(`${tag}: moved to ${p.url()}`);
    if ((got && got.lang) !== expect) problems.push(`${tag}: expected ${expect}, got ${JSON.stringify(got)}`);
    else console.log(`${tag}: ${got ? `${got.lang} | ${got.text} | ${got.href}` : 'none'}`);
    if (got && got.href !== dirOf[expect]) problems.push(`${tag}: links to ${got.href}, not ${dirOf[expect]}`);
    if (got) {
      const top = await p.evaluate(() => { const b = document.querySelector('.langbar').getBoundingClientRect(), t = document.querySelector('.top').getBoundingClientRect(); return t.top >= b.bottom - 1; });
      if (!top) problems.push(`${tag}: the header overlaps the bar`);
    }
    if (then) await then(p, got, tag);
    await c.close();
  };
  const dismissed = async (p, got, tag) => {
    if (!got) return;
    await p.click('.langbar button');
    if (await p.$('.langbar')) problems.push(`${tag}: × did not close it`);
    await p.reload({ waitUntil: 'networkidle' });
    if (await p.$('.langbar')) problems.push(`${tag}: came back after dismissal`);
  };
  const chose = async (p, got, tag) => {
    // an explicit choice in the footer (here: staying in English) keeps the bar away everywhere
    await p.click(`.foot-langs a[hreflang="en"]`);
    await p.waitForLoadState('networkidle');
    await p.goto(BASE, { waitUntil: 'networkidle' });
    if (await p.$('.langbar')) problems.push(`${tag}: came back after an explicit choice`);
  };
  if (codes.length > 1) {
    const other = codes.find(c => c !== 'en');
    if (codes.includes('es')) await bar(['es-MX', 'en'], '/', 'es', { then: dismissed });
    if (codes.includes('ko')) await bar(['ko-KR', 'ko'], dirOf.es || '/', 'ko');
    if (codes.includes('zh-Hans')) { await bar(['zh-CN'], '/', 'zh-Hans'); await bar(['zh-TW', 'zh'], '/', null); await bar(['zh', 'zh-TW'], '/', null); await bar(['zh-HK'], '/', null); }
    await bar(['en-US'], dirOf[other], 'en', { then: dismissed });
    await bar([other === 'zh-Hans' ? 'zh-CN' : other], dirOf[other], null);
    await bar(['de-DE'], '/', null);
    await bar([other === 'zh-Hans' ? 'zh-CN' : other], '/', other, { then: chose });
    await bar([other === 'zh-Hans' ? 'zh-CN' : other], '/', null, { ua: 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) HeadlessChrome/140.0.0.0 Safari/537.36' });
    await bar([other === 'zh-Hans' ? 'zh-CN' : other], '/', null, { ua: 'Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)' });
    // the picker works without JavaScript: a native disclosure of links
    const c = await b.newContext({ javaScriptEnabled: false, viewport: { width: 320, height: 720 } });
    const p = await c.newPage();
    await p.goto(BASE, { waitUntil: 'networkidle' });
    await p.click('details.lang summary');
    await p.click(`details.lang a[hreflang="${other}"]`);
    await p.waitForLoadState('networkidle');
    const lang = await p.evaluate(() => document.documentElement.lang);
    if (lang !== other || !p.url().endsWith(dirOf[other])) problems.push(`no-JS picker: landed on ${p.url()} (${lang})`);
    else console.log(`no-JS picker at 320px: / -> ${dirOf[other]}`);
    // and the 404 page speaks the language of the folder it is in
    await p.goto(BASE + dirOf[other].slice(1) + 'no-such-page');
    const nf = await p.evaluate(() => document.documentElement.lang);
    if (nf !== 'en') problems.push(`404 without JS should stay English, got ${nf}`);
    await c.close();
    const c2 = await b.newContext();
    const p2 = await c2.newPage();
    await p2.goto(BASE + dirOf[other].slice(1) + 'no-such-page');
    const nf2 = await p2.evaluate(() => [document.documentElement.lang, document.querySelector('.btn-primary').getAttribute('href')]);
    if (nf2[0] !== other || nf2[1] !== dirOf[other]) problems.push(`404 in ${dirOf[other]}: lang ${nf2[0]}, home ${nf2[1]}`);
    else console.log(`404 in ${dirOf[other]}: ${nf2[0]}, home link ${nf2[1]}`);
    await c2.close();
  }
  await b.close();
  site.close();
  const uniq = [...new Set(problems)];
  if (uniq.length) { console.log(uniq.join('\n')); console.log(`${uniq.length} problem(s)`); process.exit(1); }
  console.log(`i18n audit ok: ${langs.length} language(s) × ${SIZES.length} sizes${codes.length > 1 ? ', suggestion bar, no-JS picker and 404 ok' : ''}`);
})().catch(e => { console.error(e); process.exit(1); });
