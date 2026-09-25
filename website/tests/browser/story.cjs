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
  await p.close();
  // isolate the load/resize sync mechanism itself: disable IntersectionObserver before any
  // page script runs, so only the sync-on-load/resize code path (not IO) can update the stage.
  {
    const c0 = await b.newContext({ viewport: { width: 1440, height: 900 } });
    await c0.addInitScript(() => { delete window.IntersectionObserver; });
    let p0 = await c0.newPage();
    await p0.goto(BASE + '#s6'); await p0.waitForTimeout(800);
    ok(!(await p0.evaluate(() => 'IntersectionObserver' in window)), 'no-IO: IntersectionObserver is really gone');
    ok(await p0.getAttribute('.sys.live', 'data-s') === '6', 'no-IO: deep link #s6 shows stage 6');
    // scroll to step 4, then reload with no hash: the restored scroll position (not a hash
    // or IO) must drive the stage on load
    await p0.evaluate(() => document.getElementById('s4').scrollIntoView({ behavior: 'instant', block: 'start' }));
    await p0.waitForTimeout(200);
    await p0.reload(); await p0.waitForTimeout(800);
    ok(await p0.getAttribute('.sys.live', 'data-s') === '4', 'no-IO: reload with restored scroll shows stage 4');
    // resize across the breakpoint and back, still on stage 6
    await p0.goto(BASE + '#s6'); await p0.waitForTimeout(800);
    await p0.setViewportSize({ width: 900, height: 900 }); await p0.waitForTimeout(400);
    await p0.setViewportSize({ width: 1440, height: 900 }); await p0.waitForTimeout(600);
    ok(await p0.getAttribute('.sys.live', 'data-s') === '6', 'no-IO: resize cycle keeps stage 6');
    await c0.close();
  }
  p = await b.newPage({ viewport: { width: 1440, height: 900 } });
  // focus is never hidden under the figure or nav
  await p.goto(BASE); await p.waitForTimeout(300);
  for (let i = 0; i < 25; i++) {
    await p.keyboard.press('Tab');
    const r = await p.evaluate(() => { const e = document.activeElement, b = e.getBoundingClientRect(), fig = document.querySelector('.stage-col'), nav = document.querySelector('header nav');
      const hit = x => x && (() => { const c = x.getBoundingClientRect(); return b.left < c.right && c.left < b.right && b.top < c.bottom && c.top < b.bottom; })();
      // header nav (z-index:10) always paints above the pinned figure column, so a nav
      // link's bbox intersecting the (grid-row-tall) .stage-col box is not actually covered.
      return { tag: e.tagName, hidden: (e.closest('.stage-col') || e.closest('header nav')) ? false : (hit(fig) || hit(nav)) }; });
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
