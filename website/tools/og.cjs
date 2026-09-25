// website/tools/og.cjs — NODE_PATH=$PROTO/node_modules node website/tools/og.cjs (server on :8766)
const { chromium } = require('playwright-core');
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' });
  const p = await b.newPage({ viewport: { width: 1200, height: 630 }, deviceScaleFactor: 1 });
  await p.goto(process.env.BASE || 'http://localhost:8766/', { waitUntil: 'networkidle' });
  await p.addStyleTag({ content: 'header nav,.scroll-cue,.rail,.skip{display:none!important}' });
  await p.evaluate(() => document.fonts.ready);
  await p.screenshot({ path: require('path').join(__dirname, '..', 'og-image.png') });
  await b.close();
})();
