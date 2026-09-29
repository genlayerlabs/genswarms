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
| `og.lock.json` | Written by `tools/og.cjs`: the hash of the share card each image was rendered from, and the image's hash. |

## Day to day

1. Edit the English in `website/src` (`content.mjs`, `page.mjs`). The zoom drawing's words are catalogued in
   `content.mjs` (`canvasStrings`) and reach the canvas as a JSON block (`#zoom-strings`) in each page's language.
2. `node website/build.mjs --extract`: rewrites `en.json`. A changed sentence gets a new id.
3. `node website/build.mjs`: lists every id each language is missing (or whose markup, placeholders, protected names or
   length are wrong) and writes nothing until they are fixed. Translate those ids in `<lang>.json`, keeping the ledger's terms.
4. `node website/build.mjs` again: writes `index.html`, `<lang>/index.html`, `404.html`, `sitemap.xml`, `llms.txt` and `build.lock.json`.
5. `node website/tools/og.cjs`: the share images (see below; no server needed). Then, with `website/` served (e.g.
   `python3 -m http.server 8790 --directory website`), the checks: `node --test website/tests/*.mjs`,
   `node website/tests/browser/i18n-audit.cjs http://localhost:8790/` (every language × 14 sizes, suggestion bar),
   `audit.cjs` and `story.cjs`.
6. `node website/build.mjs --check` passes, then commit. CI runs the tests and `--check` on pull requests and before
   every deploy; after a deploy, `node website/build.mjs --verify https://genswarms.com/` checks every version is served right.

## Share images

Each version has its own share card (`og-image.png`, `og-<lang>.png`, 1200×630), drawn from HTML the build makes
per language (`src/card.mjs`, never deployed): the wordmark, the page's headline, `genswarms.com` with the hero's
"Open source, MIT", and on the right a still of the organization the page's zoom starts from, drawn on a canvas by the
page's own engine (`src/zoom-*.js`) under the zoom caption ("organization · 36 swarms · 2,861 agents", numbers in the
language's format). It has no strings of its own: every word is the page's, so translating the page translates the
card. `tools/og.cjs` renders each card at 2x and scales it down; the card's script draws the world, then steps the
headline size down (from the per-language size in `card.mjs`) until nothing overflows and the last line is not a
stranded word, and og.cjs refuses a card that still doesn't fit. The build hashes each card into `build.lock.json`
(`og`), so `--check` fails when the headline, a caption string or the card template changed and the image wasn't
re-rendered. Pages carry `og:image:width`/`height` and `og:image:alt` (the page title).

The icons (`favicon.svg`, hand-made: a Geist Mono "g" as an outline and the wordmark's cursor) have PNG versions
rendered by `tools/icons.cjs` (`favicon-32.png`, `apple-touch-icon.png`).

## The zoom drawing in other languages

The canvas measures every label in the page's own font stack (`--fc` in `page.css`, set per writing system in
`TYPE`, `src/page.mjs`), fits each camera frame around its labels, wraps the long ones (the refused change, the
database note) and leaves out a label rather than clip it or push it over the drawing. Keep labels near their `max`
budget anyway: a shorter label keeps the drawing larger. `story.cjs` and `i18n-audit.cjs` check every keyframe at
every size: no label over another, over a node, outside the canvas, or under the caption or the readout.

Browser tools need `NODE_PATH` pointing at a `node_modules` with `playwright-core`, and Chrome (`CHROME=` to override).
Without a URL, `i18n-audit.cjs` builds pseudo-locales (`website/tools/pseudo.mjs`) into a temp folder and audits those.
