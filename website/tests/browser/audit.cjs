// website/tests/browser/audit.cjs
// Layout audit across widths, landscape and large font.
// Run: node website/build.mjs && NODE_PATH=$PROTO/node_modules node website/tests/browser/audit.cjs
const { chromium } = require('playwright-core');
const BASE = process.env.BASE || 'http://localhost:8766/';
const SIZES = [[320,720],[360,780],[375,812],[390,844],[414,896],[480,900],[600,900],[768,1024],[820,1180],[1024,768],[1280,800],[1440,900],[1440,640],[844,390]];
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' });
  const out = [];
  for (const [w, h] of SIZES) for (const big of [false, true]) {
    const phone = w <= 820 && h > w;
    const c = await b.newContext({ viewport: { width: w, height: h }, isMobile: phone, hasTouch: phone });
    const p = await c.newPage(); const errs = [];
    p.on('pageerror', e => errs.push(e.message)); p.on('console', m => m.type() === 'error' && errs.push(m.text()));
    p.on('response', r => r.status() >= 400 && errs.push(r.status() + ' ' + r.url()));
    await p.goto(BASE, { waitUntil: 'networkidle' });
    if (big) await p.addStyleTag({ content: 'html{font-size:24px}' });
    const H = await p.evaluate(() => document.documentElement.scrollHeight);
    for (let y = 0; y < H; y += h) {
      await p.evaluate(y => scrollTo(0, y), y); await p.waitForTimeout(120);
      const r = await p.evaluate(({ phone }) => {
        const o = [], de = document.documentElement;
        if (de.scrollWidth > innerWidth) o.push(`overflow ${de.scrollWidth}`);
        const fig = document.querySelector('.cine .stage');
        if (fig) { const f = fig.getBoundingClientRect();
          if (f.height > innerHeight + 1) o.push('pinned figure taller than viewport');
          for (const t of document.querySelectorAll('.step .copy')) { const b = t.getBoundingClientRect();
            if (b.bottom > 0 && b.top < innerHeight && b.left < f.right && f.left < b.right && b.top < f.bottom && f.top < b.bottom) o.push('step text under figure'); } }
        const tw = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
        for (let n; (n = tw.nextNode());) { const e = n.parentElement; if (!n.textContent.trim() || !e.offsetParent || e.closest('svg,.skip')) continue;
          if (parseFloat(getComputedStyle(e).fontSize) < 12) o.push('text < 12px: ' + n.textContent.trim().slice(0, 20)); }
        if (phone) for (const a of document.querySelectorAll('a,button')) { if (!a.offsetParent || a.closest('p,li') || a.classList.contains('skip')) continue;
          const r = a.getBoundingClientRect(); if (r.height < 44) o.push('tap target ' + Math.round(r.height) + 'px: ' + a.textContent.trim().slice(0, 20)); }
        return o;
      }, { phone });
      r.forEach(m => out.push(`${w}x${h}${big ? ' 24px' : ''}: ${m}`));
    }
    errs.forEach(m => out.push(`${w}x${h}: ${m}`));
    await c.close();
  }
  await b.close();
  const uniq = [...new Set(out)];
  if (uniq.length) { console.log(uniq.join('\n')); process.exit(1); }
  console.log(`audit ok: ${SIZES.length} sizes × 2 font sizes`);
})();
