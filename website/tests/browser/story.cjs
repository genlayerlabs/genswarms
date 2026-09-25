// website/tests/browser/story.cjs
// Run: python3 -m http.server 8766 --directory website & NODE_PATH=$PROTO/node_modules node website/tests/browser/story.cjs
const { chromium } = require('playwright-core');
const BASE = process.env.BASE || 'http://localhost:8766/';
const fail = [];
const ok = (c, m) => { if (!c) fail.push(m); };
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' });
  // deep link: stage matches the step in view on load
  let p = await b.newPage({ viewport: { width: 1440, height: 900 } });
  await p.goto(BASE + '#s6'); await p.waitForTimeout(800);
  ok(await p.getAttribute('.sys.live', 'data-s') === '6', 'deep link #s6 shows stage 6');
  // resize across the breakpoint keeps a visible figure
  await p.setViewportSize({ width: 900, height: 900 }); await p.waitForTimeout(400);
  ok(!(await p.evaluate(() => document.documentElement.classList.contains('cine'))), 'narrow → in-flow mode');
  ok(await p.isVisible('#s6 figure.still'), 'narrow → still of step 6 visible');
  await p.setViewportSize({ width: 1440, height: 900 }); await p.waitForTimeout(600);
  ok(await p.getAttribute('.sys.live', 'data-s') === '6', 'wide again → stage 6 without scrolling');
  // focus is never hidden under the figure or nav
  await p.goto(BASE); await p.waitForTimeout(300);
  for (let i = 0; i < 25; i++) {
    await p.keyboard.press('Tab');
    const r = await p.evaluate(() => { const e = document.activeElement, b = e.getBoundingClientRect(), fig = document.querySelector('.stage-col'), nav = document.querySelector('header nav');
      const hit = x => x && (() => { const c = x.getBoundingClientRect(); return b.left < c.right && c.left < b.right && b.top < c.bottom && c.top < b.bottom; })();
      // header nav (z-index:10) always paints above the pinned figure column, so a nav
      // link's bbox intersecting the (grid-row-tall) .stage-col box is not actually covered.
      return { tag: e.tagName, hidden: (e.closest('.stage-col') || e.closest('nav')) ? false : (hit(fig) || hit(nav)) }; });
    ok(!r.hidden, `focused ${r.tag} #${i} is covered`);
  }
  ok(await p.$('a.skip[href="#os"]') !== null, 'skip link to #os exists');
  await p.close();
  // no JS and reduced motion: all copy and a still per step visible
  for (const opts of [{ javaScriptEnabled: false }, { reducedMotion: 'reduce' }]) {
    const c = await b.newContext({ viewport: { width: 1440, height: 900 }, ...opts }); p = await c.newPage();
    await p.goto(BASE); await p.waitForTimeout(500);
    for (let k = 0; k <= 8; k++) ok(await p.isVisible(`#s${k} figure.still svg.L`), `${JSON.stringify(opts)}: still ${k} visible`);
    ok(await p.isVisible('text=Start with one team'), `${JSON.stringify(opts)}: close visible`);
    await c.close();
  }
  await b.close();
  if (fail.length) { console.log(fail.join('\n')); process.exit(1); }
  console.log('story ok');
})();
