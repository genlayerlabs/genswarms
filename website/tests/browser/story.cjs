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
  // figure text is >= 13px where it renders; clay only for moving work, active state and failure
  const CLAY = 'rgb(168, 78, 54)';
  const smallText = sel => p.evaluate(sel => {
    const out = [];
    document.querySelectorAll(sel).forEach(svg => {
      if (!svg.getClientRects().length) return;
      const sc = svg.getScreenCTM().a;
      svg.querySelectorAll('text').forEach(t => {
        if (!t.getClientRects().length) return; // display:none twin label
        for (let e = t; e && e !== svg; e = e.parentElement) if (getComputedStyle(e).opacity === '0') return;
        const px = parseFloat(getComputedStyle(t).fontSize) * sc;
        if (px < 13) out.push(`${t.textContent.trim()} ${px.toFixed(1)}px`);
      });
    });
    return out;
  }, sel);
  // includes short laptop windows (1366x768 and 1280x720 screens minus browser chrome)
  for (const [w, h] of [[1440, 900], [1280, 720], [1024, 768], [1366, 657], [1280, 600]]) {
    p = await b.newPage({ viewport: { width: w, height: h } });
    await p.goto(BASE); await p.waitForTimeout(300);
    ok(await p.evaluate(() => document.documentElement.classList.contains('cine')), `${w}x${h}: pinned mode`);
    for (let k = 0; k <= 8; k++) {
      await p.evaluate(k => document.getElementById('s' + k).scrollIntoView({ behavior: 'instant', block: 'start' }), k);
      await p.waitForTimeout(1500);
      ok(await p.getAttribute('.sys.live', 'data-s') === String(k), `${w}: stage ${k} shown`);
      const small = await smallText('.sys.live');
      ok(!small.length, `${w}x${h} stage ${k}: figure text under 13px: ${small.join(', ')}`);
      const clay = await p.evaluate(CLAY => {
        const svg = document.querySelector('.sys.live'), out = [];
        svg.querySelectorAll('*').forEach(el => {
          if (el.closest('.tok') || el.tagName === 'g') return;
          for (let e = el; e && e !== svg; e = e.parentElement) if (getComputedStyle(e).opacity === '0') return;
          const cs = getComputedStyle(el);
          if (cs.fill === CLAY || cs.stroke === CLAY) out.push(el.getAttribute('class') || el.tagName);
        });
        return out;
      }, CLAY);
      // stage 6 is the escalation (active); the event stream names agent_blocked in clay there
      if (k !== 6) ok(!clay.length, `${w}: stage ${k}: clay outside moving work: ${clay.join(', ')}`);
    }
    await p.close();
  }
  // below 600px tall the story runs in flow (stills), still >= 13px
  for (const [w, h] of [[1280, 560], [1024, 560]]) {
    p = await b.newPage({ viewport: { width: w, height: h } });
    await p.goto(BASE); await p.waitForTimeout(300);
    ok(!(await p.evaluate(() => document.documentElement.classList.contains('cine'))), `${w}x${h}: in-flow mode`);
    const small = await smallText('.still svg.L');
    ok(!small.length, `${w}x${h}: still text under 13px: ${small.join(', ')}`);
    await p.close();
  }
  for (const w of [390, 360]) {
    p = await b.newPage({ viewport: { width: w, height: 844 } });
    await p.goto(BASE); await p.waitForTimeout(300);
    const small = await smallText('.still svg.P');
    ok(!small.length, `${w}: phone still text under 13px: ${small.join(', ')}`);
    // phone figures keep the 16px side gutter (the svg box and everything painted in it)
    const out = await p.evaluate(() => {
      const bad = [];
      document.querySelectorAll('.still svg.P').forEach((svg, k) => {
        [svg, ...svg.querySelectorAll('*')].forEach(e => {
          const r = e.getBoundingClientRect();
          if (!r.width || getComputedStyle(e).display === 'none') return;
          if (r.left < 15.5 || r.right > innerWidth - 15.5) bad.push(`fig ${k + 1} ${e.getAttribute('class') || e.tagName} ${Math.round(r.left)}..${Math.round(r.right)}`);
        });
      });
      return bad;
    });
    ok(!out.length, `${w}: phone figure outside the 16px gutter: ${out.slice(0, 6).join(', ')}`);
    await p.close();
  }
  // step headings never meet the previous step's text or figure
  for (const [w, h] of [[1440, 900], [1024, 768], [390, 844], [360, 740]]) {
    p = await b.newPage({ viewport: { width: w, height: h } });
    await p.goto(BASE); await p.waitForTimeout(500);
    const hits = await p.evaluate(() => {
      const out = [], steps = [...document.querySelectorAll('.step')];
      const vis = e => e.getClientRects().length && getComputedStyle(e).visibility !== 'hidden';
      for (let k = 1; k < steps.length; k++) {
        let bottom = -1e9;
        steps[k - 1].querySelectorAll('.copy *, figure.still svg *, figcaption').forEach(e => {
          if (!vis(e)) return;
          const r = e.getBoundingClientRect(); if (r.height) bottom = Math.max(bottom, r.bottom);
        });
        const first = steps[k].querySelector('.copy > *').getBoundingClientRect().top;
        // and a still's drawing never runs into its own caption
        const fig = steps[k - 1].querySelector('figure.still'), cap = fig && fig.querySelector('figcaption');
        if (cap && vis(cap)) {
          let fb = -1e9;
          fig.querySelectorAll('svg *').forEach(e => { if (vis(e)) { const r = e.getBoundingClientRect(); if (r.height) fb = Math.max(fb, r.bottom); } });
          if (cap.getBoundingClientRect().top - fb < 4) out.push(`figure ${k} runs into its caption`);
        }
        if (first - bottom < 48) out.push(`step ${k} starts ${Math.round(first - bottom)}px after step ${k - 1}`);
      }
      return out;
    });
    ok(!hits.length, `${w}x${h}: ${hits.join('; ')}`);
    await p.close();
  }
  // the story text never runs under the pinned figure (h1 has an unbreakable "AI workforces.")
  for (const w of [1000, 1024, 1280, 1440, 1920]) {
    p = await b.newPage({ viewport: { width: w, height: 900 } });
    await p.goto(BASE); await p.waitForTimeout(500);
    const over = await p.evaluate(() => {
      const edge = document.querySelector('.stage .sys').getBoundingClientRect().left, out = [];
      document.querySelectorAll('.step .copy > *').forEach(e => {
        const r = document.createRange(); r.selectNodeContents(e);
        const right = Math.max(...[...r.getClientRects()].map(x => x.right));
        if (right > edge - 16) out.push(`${e.tagName}.${e.className} ends at ${Math.round(right)} (figure at ${Math.round(edge)})`);
      });
      return out;
    });
    ok(!over.length, `${w}: ${over.join('; ')}`);
    await p.close();
  }
  await b.close();
  if (fail.length) { console.log(fail.join('\n')); process.exit(1); }
  console.log('story ok');
})();
