#!/usr/bin/env node
// Builds website/index.html from website/src. `--check` fails if the committed file is stale.
import { readFileSync, writeFileSync } from 'node:fs';
import { renderPage } from './src/page.mjs';
const out = new URL('./index.html', import.meta.url);
const html = renderPage();
if (process.argv.includes('--check')) {
  const cur = readFileSync(out, 'utf8');
  if (cur !== html) { console.error('website/index.html is stale: run `node website/build.mjs`'); process.exit(1); }
  console.log('website/index.html is up to date');
} else {
  writeFileSync(out, html);
  console.log(`website/index.html ${Buffer.byteLength(html)} bytes`);
}
