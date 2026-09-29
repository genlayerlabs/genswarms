// website/tests/browser/story.cjs — the story and its zoom (English): the camera follows the reading position, deep
// links and resizes land on the right keyframe, focus is never hidden, no JS and reduced motion keep the whole story,
// and the drawing's labels never overlap, leave the canvas or sit under the caption or the readout.
// Run: python3 -m http.server 8766 --directory website & NODE_PATH=$PROTO/node_modules node website/tests/browser/story.cjs
// (BASE=http://localhost:PORT/ to use another server)
const { chromium } = require('playwright-core');
const BASE = process.env.BASE || 'http://localhost:8766/';
const fail = [];
const ok = (c, m) => { if (!c) fail.push(m); };
const kOf = p => p.evaluate(() => +document.querySelector('.stage').getAttribute('data-k'));

// runs in the page: every keyframe as a composed still; its labels against each other, the drawing's nodes, the
// canvas edge, the zoom caption and the readout shown over the drawing
function canvasProblems(floor) {
  if (!window.Z || !Z.still) return ['no zoom engine'];
  const out = [], cv = document.querySelector('.stage canvas'), R = cv.getBoundingClientRect();
  if (!R.width) return out;
  const rel = e => { const b = e.getBoundingClientRect(); return { x0: b.left - R.left, y0: b.top - R.top, x1: b.right - R.left, y1: b.bottom - R.top }; };
  const hit = (a, b, m = 1) => Math.min(a.x1, b.x1) - Math.max(a.x0, b.x0) > m && Math.min(a.y1, b.y1) - Math.max(a.y0, b.y0) > m;
  const or = getComputedStyle(document.documentElement).getPropertyValue('--or').trim();
  for (let k = 0; k <= 10; k++) {
    const boxes = Z.still(k), labels = boxes.filter(b => b.k !== 'node'), nodes = boxes.filter(b => b.k === 'node');
    const cap = rel(document.querySelector('.zcap'));
    const ro = [...document.querySelectorAll('.ros [data-at]')].find(e => e.classList.contains('on') && e.offsetParent);
    for (const l of labels) {
      const at = `K${k} "${l.s}"`;
      if (l.x0 < 0 || l.x1 > R.width || l.y0 < 0 || l.y1 > R.height) out.push(`${at} leaves the canvas (${Math.round(l.x0)}..${Math.round(l.x1)} of ${Math.round(R.width)}, y ${Math.round(l.y0)})`);
      if (l.px < floor) out.push(`${at} is ${l.px}px`);
      if (hit(l, cap)) out.push(`${at} is under the zoom caption`);
      if (ro && hit(l, rel(ro))) out.push(`${at} is under the readout`);
      if (l.c === or && !/^(dropped|crash)$/.test(l.k)) out.push(`${at} is orange (orange is for failure only)`);
      for (const n of nodes) if (hit(l, n, 1.5)) { out.push(`${at} covers a node of the drawing`); break; }
    }
    for (let i = 0; i < labels.length; i++) for (let j = i + 1; j < labels.length; j++) if (hit(labels[i], labels[j])) out.push(`K${k} "${labels[i].s}" overlaps "${labels[j].s}"`);
  }
  Z.release();
  return out;
}
module.exports = { canvasProblems };

if (require.main === module) (async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' });
  // deep link: the stage shows the keyframe of the step in view (step 7, #s6, is the packages: K8)
  let p = await b.newPage({ viewport: { width: 1440, height: 900 } });
  await p.goto(BASE + '#s6'); await p.waitForTimeout(1200);
  ok(await kOf(p) === 8, `deep link #s6 shows keyframe 8 (got ${await kOf(p)})`);
  ok(await p.evaluate(() => document.querySelector('.stage canvas').getAttribute('aria-label').startsWith('Illustration: each object comes from a signed package')), 'the canvas is named after keyframe 8');
  // resize across the breakpoint and back keeps the reader's place
  await p.setViewportSize({ width: 900, height: 900 }); await p.waitForTimeout(800);
  ok(!(await p.evaluate(() => document.documentElement.classList.contains('cine'))), 'narrow → stage above the text');
  ok(await p.isVisible('#s6 .ro-in'), 'narrow → the readout of step 7 is in its text');
  await p.evaluate(() => document.getElementById('s6').scrollIntoView({ behavior: 'instant', block: 'start' }));
  await p.setViewportSize({ width: 1440, height: 900 }); await p.waitForTimeout(1000);
  await p.evaluate(() => document.getElementById('s6').scrollIntoView({ behavior: 'instant', block: 'start' })); await p.waitForTimeout(1200);
  ok(await kOf(p) === 8, `wide again → keyframe 8 (got ${await kOf(p)})`);
  await p.close();
  // without IntersectionObserver the drawing still follows the scroll
  {
    const c0 = await b.newContext({ viewport: { width: 1440, height: 900 } });
    await c0.addInitScript(() => { delete window.IntersectionObserver; });
    const p0 = await c0.newPage();
    await p0.goto(BASE + '#s6'); await p0.waitForTimeout(1200);
    ok(!(await p0.evaluate(() => 'IntersectionObserver' in window)), 'no-IO: IntersectionObserver is really gone');
    ok(await kOf(p0) === 8, 'no-IO: deep link #s6 shows keyframe 8');
    await p0.evaluate(() => document.getElementById('s4').scrollIntoView({ behavior: 'instant', block: 'start' }));
    await p0.waitForTimeout(300);
    await p0.reload(); await p0.waitForTimeout(1200);
    ok(await kOf(p0) === 6, `no-IO: reload with restored scroll shows keyframe 6 (got ${await kOf(p0)})`);
    await c0.close();
  }
  // every keyframe is reached by scrolling, in order, at the scroll position the drawing reports for it
  for (const [w, h, mobile] of [[1440, 900], [390, 844, true]]) {
    const c = await b.newContext({ viewport: { width: w, height: h }, isMobile: !!mobile, hasTouch: !!mobile });
    p = await c.newPage();
    await p.goto(BASE); await p.waitForTimeout(600);
    for (let k = 0; k <= 10; k++) {
      await p.evaluate(k => scrollTo(0, Z.scrollFor(k)), k); await p.waitForTimeout(900);
      ok(await kOf(p) === k, `${w}x${h}: keyframe ${k} at its scroll position (got ${await kOf(p)})`);
      const n = await p.evaluate(k => [...document.querySelectorAll('.ros [data-at]')].filter(e => e.classList.contains('on')).map(e => +e.getAttribute('data-at')), k);
      ok(n.length === 1 && n[0] === (k === 1 ? 0 : k), `${w}x${h}: keyframe ${k} shows readout ${n}`);
    }
    await c.close();
  }
  // focus is never hidden under the stage or the header
  for (const [w, h] of [[1440, 900], [390, 844]]) {
    p = await b.newPage({ viewport: { width: w, height: h } });
    await p.goto(BASE); await p.waitForTimeout(400);
    for (let i = 0; i < 40; i++) {
      await p.keyboard.press('Tab'); await p.waitForTimeout(40);
      const r = await p.evaluate(() => {
        const e = document.activeElement; if (!e || e === document.body) return null;
        const b = e.getBoundingClientRect(), hit = x => { const c = x.getBoundingClientRect(); return c.height && b.left < c.right && c.left < b.right && b.top < c.bottom - 1 && c.top < b.bottom - 1; };
        const stage = document.querySelector('.stage-col'), top = document.querySelector('.top');
        const inTop = e.closest('.top') || e.classList.contains('skip'), cine = document.documentElement.classList.contains('cine');
        return { what: `${e.tagName} ${e.textContent.trim().slice(0, 20)}`, hidden: !inTop && (hit(top) || (!cine && getComputedStyle(stage).position === 'sticky' && hit(stage))) };
      });
      if (r) ok(!r.hidden, `${w}x${h}: focused ${r.what} is covered`);
    }
    ok(await p.$('a.skip[href="#main"]') !== null, 'skip link to #main exists');
    await p.close();
  }
  // no JS and reduced motion: all the copy and every readout readable; no empty box where the drawing would be
  for (const opts of [{ javaScriptEnabled: false }, { reducedMotion: 'reduce' }]) for (const [w, h] of [[1440, 900], [390, 844]]) {
    const c = await b.newContext({ viewport: { width: w, height: h }, ...opts }); p = await c.newPage();
    await p.goto(BASE); await p.waitForTimeout(600);
    const tag = `${JSON.stringify(opts)} ${w}`;
    for (let k = 0; k <= 8; k++) ok(await p.isVisible(`#s${k} .copy`), `${tag}: step ${k} visible`);
    ok(await p.isVisible('text=Start with one team'), `${tag}: close visible`);
    if (opts.javaScriptEnabled === false) {
      ok(!(await p.isVisible('.stage-col')), `${tag}: no stage without JS`);
      for (const k of [2, 4, 6, 8, 10]) ok(await p.isVisible(`.ro-in[data-at="${k}"]`), `${tag}: readout ${k} in the text`);
    } else {
      // reduced motion: a composed still per keyframe, drawn (not blank)
      const drawn = await p.evaluate(() => { const c = document.querySelector('.stage canvas'), g = c.getContext('2d'), d = g.getImageData(0, 0, c.width, c.height).data; let n = 0; for (let i = 3; i < d.length; i += 64) if (d[i]) n++; return n; });
      ok(drawn > 100, `${tag}: the canvas is drawn (${drawn})`);
    }
    await c.close();
  }
  // the drawing's labels, at every keyframe, on the sizes the story is read at (short laptops included)
  for (const [w, h] of [[1440, 900], [1280, 720], [1024, 768], [1366, 657], [1920, 1080], [2560, 1440], [1280, 600], [844, 390], [768, 1024], [390, 844], [360, 740], [320, 720]]) {
    const mobile = w < 800 && h > w;
    const c = await b.newContext({ viewport: { width: w, height: h }, isMobile: mobile, hasTouch: mobile });
    p = await c.newPage();
    await p.goto(BASE); await p.waitForTimeout(500);
    await p.evaluate(() => document.fonts.ready);
    const cine = await p.evaluate(() => document.documentElement.classList.contains('cine'));
    ok(cine === (w >= 960 && h >= 640) || (h < 640 && w > h && w >= 640 && cine), `${w}x${h}: ${cine ? 'pinned' : 'stacked'} layout`);
    if (cine && h < 640) ok(!(await p.isVisible('.ros')) && await p.isVisible('#s3 .ro-in'), `${w}x${h}: short screen → readouts in the text`);
    const probs = await p.evaluate(canvasProblems, w < 360 ? 11 : 12);
    probs.forEach(m => fail.push(`${w}x${h}: ${m}`));
    // the canvas is sharp: its backing store follows the device pixel ratio (capped at 2)
    const px = await p.evaluate(() => { const c = document.querySelector('.stage canvas'); return c.width / c.getBoundingClientRect().width; });
    ok(Math.abs(px - Math.min(2, await p.evaluate(() => devicePixelRatio))) < 0.02, `${w}x${h}: canvas at ${px.toFixed(2)}x`);
    await c.close();
  }
  // step headings never meet the previous step's text
  for (const [w, h] of [[1440, 900], [1024, 768], [390, 844], [360, 740]]) {
    p = await b.newPage({ viewport: { width: w, height: h } });
    await p.goto(BASE); await p.waitForTimeout(500);
    const hits = await p.evaluate(() => {
      const out = [], steps = [...document.querySelectorAll('.step')];
      const vis = e => { if (!e.getClientRects().length || getComputedStyle(e).visibility === 'hidden') return false; for (let x = e; x; x = x.parentElement) if (x.getBoundingClientRect().width <= 1) return false; return true; };
      for (let k = 1; k < steps.length; k++) {
        let bottom = -1e9;
        steps[k - 1].querySelectorAll('.copy *').forEach(e => { if (!vis(e)) return; const r = e.getBoundingClientRect(); if (r.height) bottom = Math.max(bottom, r.bottom); });
        const first = steps[k].querySelector('.copy > *').getBoundingClientRect().top;
        if (first - bottom < 48) out.push(`step ${k} starts ${Math.round(first - bottom)}px after step ${k - 1}`);
      }
      return out;
    });
    ok(!hits.length, `${w}x${h}: ${hits.join('; ')}`);
    await p.close();
  }
  // pinned: the story text never runs under the drawing
  for (const w of [960, 1024, 1280, 1440, 1920, 2560]) {
    p = await b.newPage({ viewport: { width: w, height: 900 } });
    await p.goto(BASE); await p.waitForTimeout(500);
    const over = await p.evaluate(() => {
      const edge = document.querySelector('.stage').getBoundingClientRect().left, out = [];
      document.querySelectorAll('.step .copy > *:not(.ro-in)').forEach(e => {
        const r = document.createRange(); r.selectNodeContents(e);
        const right = Math.max(...[...r.getClientRects()].map(x => x.right));
        if (right > edge - 8) out.push(`${e.tagName}.${e.className} ends at ${Math.round(right)} (stage at ${Math.round(edge)})`);
      });
      return out;
    });
    ok(!over.length, `${w}: ${over.join('; ')}`);
    await p.close();
  }
  await b.close();
  if (fail.length) { console.log(fail.join('\n')); console.log(`${fail.length} problem(s)`); process.exit(1); }
  console.log('story ok');
})();
