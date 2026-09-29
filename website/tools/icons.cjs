// website/tools/icons.cjs — the PNG icons, rendered from website/favicon.svg in Chrome (as og.cjs renders the share
// cards): favicon-32.png (32x32, the SVG as it is) and apple-touch-icon.png (180x180, full bleed: iOS rounds the
// corners itself, so the square corners and the hairline border go and the mark sits a little smaller).
//
//   NODE_PATH=<dir with playwright-core> node website/tools/icons.cjs
//
// favicon.svg is hand-made: a graphite square, a Geist Mono "g" (its outline, so it needs no font) and the wordmark's
// orange block cursor. Re-run this after editing it.
const { chromium } = require('playwright-core');
const fs = require('fs');
const path = require('path');

const WEB = path.resolve(__dirname, '..');
const svg = fs.readFileSync(path.join(WEB, 'favicon.svg'), 'utf8');
// the touch icon: square corners, no border, the mark at 84% around the centre
const touch = svg
  .replace(/<rect width="64" height="64" rx="[\d.]+"/, '<rect width="64" height="64"')
  .replace(/\n\s*<rect x="\.75"[^>]*\/>/, '')
  .replace(/(<path [\s\S]*<\/svg>)/, m => `<g transform="translate(32 32) scale(.84) translate(-32 -32)">${m.replace('</svg>', '')}</g>\n</svg>`);

(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' });
  for (const [file, src, size] of [['favicon-32.png', svg, 32], ['apple-touch-icon.png', touch, 180]]) {
    const p = await b.newPage({ viewport: { width: size, height: size }, deviceScaleFactor: 1 });
    await p.setContent(`<!doctype html><html><body style="margin:0;background:transparent"><img width="${size}" height="${size}" style="display:block" src="data:image/svg+xml;base64,${Buffer.from(src).toString('base64')}"></body></html>`);
    await p.waitForFunction(() => document.querySelector('img').complete);
    fs.writeFileSync(path.join(WEB, file), await p.screenshot({ type: 'png', omitBackground: true }));
    await p.close();
    console.log(`website/${file}: ${size}x${size}`);
  }
  await b.close();
})().catch(e => { console.error(e.message || e); process.exit(1); });
