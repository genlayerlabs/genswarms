// website/tools/og.cjs — the share images, rendered from each built page's hero.
//
//   node website/build.mjs && NODE_PATH=<dir with playwright-core> node website/tools/og.cjs [BASE] [--force]
//
// BASE serves website/ (default http://localhost:8790/). For every version the last build wrote (i18n/build.lock.json)
// it screenshots the page's hero at 1200x630 (header links, picker, rail and skip link hidden): og-image.png for
// English, og-<lang>.png for the others. It writes i18n/og.lock.json: per version, the hash of the hero it drew (the
// hash `build.mjs --check` computes from the page) and of the image, so a changed headline or an edited image stops
// the deploy. Images already up to date are left alone unless --force.
const { chromium } = require('playwright-core');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const WEB = path.resolve(__dirname, '..');
const I18N = process.env.I18N_DIR ? path.resolve(process.env.I18N_DIR) : path.join(WEB, 'i18n');
const sha = b => crypto.createHash('sha256').update(b).digest('hex');
const args = process.argv.slice(2);
const BASE = (args.find(a => !a.startsWith('--')) || 'http://localhost:8790/').replace(/\/?$/, '/');

(async () => {
  const { ogSource } = await import(path.join(WEB, 'src/site.mjs'));
  const { LANGS } = await import(path.join(WEB, 'src/i18n.mjs'));
  const lock = JSON.parse(fs.readFileSync(path.join(I18N, 'build.lock.json'), 'utf8'));
  const ogPath = path.join(I18N, 'og.lock.json');
  const og = fs.existsSync(ogPath) ? JSON.parse(fs.readFileSync(ogPath, 'utf8')) : {};
  const next = {};
  const b = await chromium.launch({ executablePath: process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' });
  for (const [key, { image, source }] of Object.entries(lock.og)) {
    const l = LANGS.find(x => (x.file || 'en') === key), out = path.join(WEB, image);
    if (!args.includes('--force') && og[key] && og[key].source === source && fs.existsSync(out) && sha(fs.readFileSync(out)) === og[key].png) {
      next[key] = og[key];
      console.log(`${image}: up to date`);
      continue;
    }
    const p = await b.newPage({ viewport: { width: 1200, height: 630 }, deviceScaleFactor: 1 });
    const res = await p.goto(BASE + l.dir, { waitUntil: 'networkidle' });
    // never draw a page other than the one just built
    if (ogSource(await res.text()) !== source) throw new Error(`${BASE + l.dir} is not the page website/build.mjs just wrote (is BASE serving website/?)`);
    await p.addStyleTag({ content: 'header nav,.rail,.skip{display:none!important}' });
    await p.evaluate(() => document.fonts.ready);
    fs.writeFileSync(out, await p.screenshot());
    await p.close();
    next[key] = { source, png: sha(fs.readFileSync(out)) };
    console.log(`${image}: rendered`);
  }
  await b.close();
  fs.writeFileSync(ogPath, JSON.stringify(next, null, 1) + '\n');
  console.log(path.relative(process.cwd(), ogPath));
})().catch(e => { console.error(e.message || e); process.exit(1); });
