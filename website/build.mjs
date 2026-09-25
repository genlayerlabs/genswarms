#!/usr/bin/env node
// Builds the landing page from website/src: website/index.html (English) and website/<lang>/index.html for every
// translation in website/i18n/<lang>.json, plus 404.html, sitemap.xml, llms.txt and i18n/build.lock.json.
//
//   node website/build.mjs                 build every version (refuses, writing nothing, on stale or partial translations)
//   node website/build.mjs --extract       English source -> website/i18n/en.json (the catalogue translators work from)
//   node website/build.mjs --check         the committed pages, the lock and the share images match the sources (CI, deploy)
//   node website/build.mjs --verify <url>  a served site: 200s, /es -> /es/, lang, title, canonical, hreflang
//
// I18N_DIR and OUT_DIR override website/i18n and website/ (the tests build pseudo-locales into a temp dir).
// Workflow: website/i18n/README.md.
import { writeFileSync, mkdirSync, rmSync, rmdirSync, existsSync } from 'node:fs';
import { build, check, verify, catalogue, catalogueFile, defaults } from './src/site.mjs';
import { LANGS } from './src/i18n.mjs';

const args = process.argv.slice(2);
const { i18nDir, outDir } = defaults();
const shown = process.env.OUT_DIR || 'website';
const fail = (head, list) => { console.error(head + '\n  ' + list.join('\n  ')); process.exit(1); };

if (args.includes('--extract')) {
  const entries = catalogue();
  mkdirSync(i18nDir, { recursive: true });
  writeFileSync(new URL('en.json', i18nDir), catalogueFile(entries));
  const words = entries.reduce((n, e) => n + e.en.replace(/<[^>]+>|\{\w+\}/g, ' ').split(/\s+/).filter(w => /\p{L}/u.test(w)).length, 0);
  console.log(`${process.env.I18N_DIR || 'website/i18n'}/en.json: ${entries.length} entries, ${words} words`);
} else if (args.includes('--check')) {
  const bad = check({ i18nDir, outDir });
  if (bad.length) fail('Not up to date (the host keeps the last good version live):', bad);
  console.log('website is up to date: pages, build lock and share images match the sources');
} else if (args.includes('--verify')) {
  const base = args[args.indexOf('--verify') + 1] || 'https://genswarms.com/';
  // the versions this checkout builds
  const langs = LANGS.filter(l => !l.file || existsSync(new URL(`${l.file}.json`, i18nDir)));
  const { bad, log } = await verify(base, langs);
  console.log(log.join('\n'));
  if (bad.length) fail('verify failed:', bad);
  console.log(`verify ok: ${langs.length} version(s)`);
} else {
  const r = build({ i18nDir, outDir });
  if (r.errors.length) fail('Build refused, nothing written:', r.errors);
  r.notes.forEach(n => console.log('note: ' + n));
  for (const [f, v] of Object.entries(r.outputs)) {
    const u = new URL(f, outDir);
    if (v === null) {
      rmSync(u, { force: true });
      try { rmdirSync(new URL('.', u)); } catch {} // the folder too, once empty
      console.log(`${shown}/${f} removed (no translation)`);
      continue;
    }
    mkdirSync(new URL('.', u), { recursive: true });
    writeFileSync(u, v);
    if (f.endsWith('index.html')) console.log(`${shown}/${f} ${Buffer.byteLength(v)} bytes`);
  }
  mkdirSync(i18nDir, { recursive: true });
  writeFileSync(new URL('build.lock.json', i18nDir), JSON.stringify(r.lock, null, 1) + '\n');
  console.log(`${r.langs.map(l => l.code).join(', ')}: built; ${process.env.I18N_DIR || 'website/i18n'}/build.lock.json written`);
}
