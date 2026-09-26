// website/tools/og.cjs — the share images, rendered from each version's share card (src/card.mjs).
//
//   NODE_PATH=<dir with playwright-core> node website/tools/og.cjs [--force]
//
// No server needed: it builds in memory (the same build as website/build.mjs, so it refuses on the same errors) and,
// for every version, draws that version's card HTML in Chrome at 1200x630 and deviceScaleFactor 2, then scales it
// down to 1200x630 (crisper text than a 1x render): og-image.png for English, og-<lang>.png for the others. A card
// whose headline still overflows at the smallest size, or ends on a stranded word, stops the run (the card's own fit
// script reports it). It writes i18n/og.lock.json: per version, the hash of the card HTML it drew (the hash
// `build.mjs --check` computes) and of the image, so a changed headline, triad, drawing or card template, or an
// edited image, stops the deploy. Images already up to date are left alone unless --force.
// I18N_DIR and OUT_DIR as for build.mjs: images go next to the pages that were built.
const { chromium } = require('playwright-core');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { fileURLToPath } = require('url');

const WEB = path.resolve(__dirname, '..');
const sha = b => crypto.createHash('sha256').update(b).digest('hex');
const args = process.argv.slice(2);

(async () => {
  const { build, defaults, ogFile, ogKey } = await import(path.join(WEB, 'src/site.mjs'));
  const { CARD } = await import(path.join(WEB, 'src/card.mjs'));
  const { i18nDir, outDir } = defaults();
  const I18N = fileURLToPath(i18nDir), OUT = fileURLToPath(outDir);
  const r = build({ i18nDir, outDir });
  if (r.errors.length) throw new Error('the build refuses, so no share images:\n  ' + r.errors.join('\n  '));
  const ogPath = path.join(I18N, 'og.lock.json');
  const og = fs.existsSync(ogPath) ? JSON.parse(fs.readFileSync(ogPath, 'utf8')) : {};
  const next = {};
  const b = await chromium.launch({ executablePath: process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' });
  for (const l of r.langs) {
    const key = ogKey(l), image = ogFile(l), out = path.join(OUT, image), { source } = r.lock.og[key];
    if (!args.includes('--force') && og[key] && og[key].source === source && fs.existsSync(out) && sha(fs.readFileSync(out)) === og[key].png) {
      next[key] = og[key];
      console.log(`${image}: up to date`);
      continue;
    }
    const p = await b.newPage({ viewport: { width: CARD.w, height: CARD.h }, deviceScaleFactor: 2 });
    await p.setContent(r.cards[key], { waitUntil: 'networkidle' });
    await p.waitForFunction(() => document.documentElement.dataset.fit, null, { timeout: 15000 });
    const fit = await p.evaluate(() => document.documentElement.dataset.fit);
    if (fit !== 'ok') throw new Error(`${image}: the card does not fit: ${fit}`);
    const big = await p.screenshot({ type: 'png' });
    await p.close();
    // 2x -> 1x in the browser (high-quality smoothing), so the script needs nothing beyond Chrome
    const q = await b.newPage();
    const png = Buffer.from(await q.evaluate(async ([src, w, h]) => {
      const img = new Image();
      img.src = 'data:image/png;base64,' + src;
      await img.decode();
      const c = document.createElement('canvas');
      c.width = w; c.height = h;
      const x = c.getContext('2d');
      x.imageSmoothingEnabled = true; x.imageSmoothingQuality = 'high';
      x.drawImage(img, 0, 0, w, h);
      return c.toDataURL('image/png').split(',')[1];
    }, [big.toString('base64'), CARD.w, CARD.h]), 'base64');
    await q.close();
    fs.writeFileSync(out, png);
    next[key] = { source, png: sha(png) };
    console.log(`${image}: rendered`);
  }
  await b.close();
  fs.writeFileSync(ogPath, JSON.stringify(next, null, 1) + '\n');
  console.log(path.relative(process.cwd(), ogPath));
})().catch(e => { console.error(e.message || e); process.exit(1); });
