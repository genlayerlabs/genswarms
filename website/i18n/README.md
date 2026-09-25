# Translations of the landing page

English in `website/src` is the only source. Every other language is built from it and this folder; nobody edits a
built page by hand. The rules come from the multilingual playbook (one URL per language, offer instead of redirect,
the build refuses stale or partial translations).

| File | What it is |
|---|---|
| `en.json` | The catalogue: every string the page shows or reads out, with its id (a hash of the English), kind, where it appears, placeholders, and the width or length budget. Generated. |
| `<lang>.json` | A translation (`es`, `ko`, `zh`, `ru`, `tr`): `{ "<id>": "<text>", "_same_as_english": [ids] }`. Its presence is what builds `website/<lang>/`. |
| `<lang>.ledger.md` | The translator's term decisions for that language. |
| `build.lock.json` | Written by a successful build: hashes of the English source, the catalogue, each translation and each output. |
| `og.lock.json` | Written by `tools/og.cjs`: which hero each share image shows, and the image's hash. |

## Day to day

1. Edit the English in `website/src` (`content.mjs`, `page.mjs`, `figures.mjs`).
2. `node website/build.mjs --extract`: rewrites `en.json`. A changed sentence gets a new id.
3. `node website/build.mjs`: lists every id each language is missing (or whose markup, placeholders, protected names or
   length are wrong) and writes nothing until they are fixed. Translate those ids in `<lang>.json`, keeping the ledger's terms.
4. `node website/build.mjs` again: writes `index.html`, `<lang>/index.html`, `404.html`, `sitemap.xml`, `llms.txt` and `build.lock.json`.
5. With `website/` served (e.g. `python3 -m http.server 8790 --directory website`), run
   `node website/tools/og.cjs` (share images) and the checks:
   `node --test website/tests/*.mjs`, `node website/tests/browser/i18n-audit.cjs http://localhost:8790/`
   (every language × 14 sizes, suggestion bar), `audit.cjs` and `story.cjs`.
6. `node website/build.mjs --check` passes, then commit. CI runs the tests and `--check` on pull requests and before
   every deploy; after a deploy, `node website/build.mjs --verify https://genswarms.com/` checks every version is served right.

Browser tools need `NODE_PATH` pointing at a `node_modules` with `playwright-core`, and Chrome (`CHROME=` to override).
Without a URL, `i18n-audit.cjs` builds pseudo-locales (`website/tools/pseudo.mjs`) into a temp folder and audits those.
