# genswarms.com "Operating system for AI workforces" — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `website/index.html` with the approved cinematic-story landing page, built from small source modules, translation-ready, and verified against the spec's quality bar.

**Architecture:** A dependency-free Node build (`website/build.mjs`) assembles `website/index.html` from `website/src/` modules: a figure model that draws the system at nine stages in two layouts, a content module with every string, the page assembler, CSS and a small story controller. The built HTML is committed; GitHub Pages copies `website/` (minus sources) into the site root next to the MkDocs docs.

**Tech Stack:** Node ≥ 20 (ES modules, `node:test`), plain HTML/CSS/SVG/JS, Playwright-core + system Chrome for local browser checks, Lighthouse 12, GitHub Actions Pages.

**Spec:** `design/2026-09-25-landing-page-design.md`

**Reference prototype (throwaway, outside the repo):** `$PROTO = /private/tmp/claude-501/-Users-albert-dev-subzeroclaw/2e6b04ad-2439-425b-80d2-288d1d28886a/scratchpad` — page `$PROTO/gs-directions-2/1-cinematic.html`, generator `$PROTO/gs1-work/gen.cjs`, styles `$PROTO/gs1-work/page.css`, controller `$PROTO/gs1-work/page.js`. Playwright/Lighthouse are installed in `$PROTO/node_modules` (use `NODE_PATH=$PROTO/node_modules`).

## Global Constraints

- Only GenSwarms: no GenLayer, unhardcoded, blockchain or "stack" wording anywhere on the page.
- Palette: sand `#E9E0D2`, deeper sand `#DED3BF`, ink `#33301f`, secondary ink `#5f5946`, clay `#A84E36`, lighter clay `#D2704F` (on night), night `#12110d`, sage `#8fa06f` (running), `#E0664A` (crashed). No other hues.
- Type: Bricolage Grotesque (display), Instrument Sans (text), JetBrains Mono (code and event data only). Body ≥ 16px; captions ≥ 13px; no text under 12px anywhere.
- Words never used as GenSwarms features: "memory", "permissions"/"RBAC"/"per-user", "approval workflow", "exactly once" (except in "not exactly once"), any agent-count benchmark, "sandboxed packages".
- Facts: version `0.2.0`; 7 backends named `Local, Tmux (Codex, Claude Code and OpenCode sessions), Docker, Apple container, SSH, Bwrap, Mock`; default 100 agents per swarm (configurable); REST API, WebSocket, CLI.
- Every simulated UI (event stream, figure animation) carries the word "illustration" in small text.
- All copy and every figure visible with JavaScript disabled and with `prefers-reduced-motion: reduce`.
- Phones: no horizontal page scroll at 320–1440px; 16px side gutters; tap targets ≥ 44px.
- Built `website/index.html` < 150 KB (153,600 bytes) uncompressed.
- Lighthouse on the built page: accessibility, best practices, SEO = 100; performance ≥ 90 (mobile).
- No FAQPage structured data. No template tells: tracked uppercase eyebrows, pill badges, bordered chip buttons, numbering on non-sequences, "→" on every link.
- Owner copy: keep headlines verbatim; the only edits are "permissions" → "boundaries" (hero sentence) and dropping "and share context". List item reads "what tools, data and systems each agent can access".

## Review Focus

1. **Resizing across the 1000px breakpoint mid-scroll** (a desktop user narrows the window while reading step 5): the page must switch between pinned and in-flow modes without a blank or stale figure. Pinned in Task 4, Step 6.
2. **Reload or deep link into the middle of the story** (browser restores scroll to step 6, or `#s6`): the pinned figure must show stage 6 on first paint after load, not stage 0. Pinned in Task 4, Step 6.
3. **Short or landscape viewports** (1440×640 laptop, 844×390 phone landscape): the pinned figure and the step text must not overlap, and the figure must fit the viewport. Pinned in Task 6 (audit adds 1440×640 and 844×390).
4. **Keyboard users** tabbing through links inside steps: focused links must never be hidden under the pinned figure or the sticky nav; a skip link reaches the proof sections. Pinned in Task 4, Step 6.
5. **200% zoom / large default font** (browser font size 24px): step text must wrap within its column and not run under the figure; no horizontal scroll. Pinned in Task 6 (audit runs at `deviceScaleFactor` 1 with `font-size` 24px root).

---

## File Structure

| File | Responsibility |
|---|---|
| `website/src/figures.mjs` | Figure geometry for layouts `L` (800×640) and `P` (400×660); `system(layout, stage, opts)` returns one `<svg>`; `figureCSS()` returns stage/morph/animation CSS. No copy strings except figure labels. |
| `website/src/content.mjs` | All page copy as data: `STAGES` (caption, alt), `STEPS` (HTML per story step), `OS_ROWS`, `COMPARISON`, `GUARANTEES`, `NOT_YET`, `CLOSE`, `META`. |
| `website/src/page.mjs` | `renderPage()` → full HTML string (head, nav, story, proof, close, footer, inline CSS/JS). |
| `website/src/page.css` | Page styles (ported, then leveled up). |
| `website/src/story.js` | Scroll controller: mode switch, stage sync, rail, copy button. Reads captions/alt from the DOM; contains no copy. |
| `website/build.mjs` | Writes `website/index.html`; `--check` exits 1 if the committed file differs from a fresh build. |
| `website/tests/build.test.mjs` | `node --test` suite: structure, size, copy rules, facts, pruning, no-copy-in-JS. |
| `website/tests/browser/story.cjs` | Playwright checks of the story behaviour (modes, deep link, resize, focus, no-JS, reduced motion). |
| `website/tests/browser/audit.cjs` | 12-width + landscape + large-font layout audit. |
| `website/tools/og.cjs` | Renders `website/og-image.png` (1200×630) from the built hero. |
| `website/llms.txt`, `website/404.html`, `website/sitemap.xml` | Rewritten / restyled / `lastmod`. |
| `.github/workflows/pages.yml` | Run `node --test website/tests` and `node website/build.mjs --check`; copy all of `website/` except `src/`, `tests/`, `tools/`, `build.mjs`. |
| `design/comparison-sources.md` | Source URL + date for every competitor cell. |

---

### Task 1: Build pipeline from the prototype (port, no visual change)

**Files:**
- Create: `website/src/figures.mjs`, `website/src/content.mjs`, `website/src/page.mjs`, `website/src/page.css`, `website/src/story.js`, `website/build.mjs`, `website/tests/build.test.mjs`

**Interfaces:**
- Produces: `system(Lo, stage, { extraClass, label, crop, prune })` → `string` (`<svg class="sys L|P …" data-s="{stage}">`); `LAYOUTS = [L, P]`; `figureCSS()` → `string`; `renderPage()` → `string`; content exports named above; `build.mjs` CLI `node website/build.mjs [--check]`.

- [ ] **Step 1: Write the failing test**

```js
// website/tests/build.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { renderPage } from '../src/page.mjs';

const html = renderPage();

test('page has the owner headline and all nine story steps', () => {
  assert.match(html, /<h1>The operating system for AI(&nbsp;| )workforces\.<\/h1>/);
  for (let k = 0; k <= 8; k++) assert.match(html, new RegExp(`id="s${k}" data-step="${k}"`));
});

test('one live figure and nine stills per layout', () => {
  assert.equal((html.match(/<svg class="sys L live/g) || []).length, 1);
  assert.equal((html.match(/<svg class="sys L"/g) || []).length, 9);
  assert.equal((html.match(/<svg class="sys P"/g) || []).length, 9);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test website/tests/`
Expected: FAIL with `Cannot find module '…/website/src/page.mjs'`.

- [ ] **Step 3: Port the prototype into modules**

1. `cp $PROTO/gs1-work/page.css website/src/page.css` and `cp $PROTO/gs1-work/page.js website/src/story.js`.
2. Create `website/src/figures.mjs` from `$PROTO/gs1-work/gen.cjs` lines 1–306 (geometry `L`, `P`, `LAYOUTS`, `TEAMS`, `SHAPES`, `agentPos`, helpers, `band`, `system`, `genCSS`). Convert to ESM: delete the `require`/`OUT` lines, rename `genCSS` → `figureCSS`, and add `export` to `L`, `P`, `LAYOUTS`, `TEAMS`, `system`, `figureCSS`. Change the `system` signature to take an options object:

```js
export function system(Lo, stage, { extraClass = '', label = '', crop = null, prune = false } = {}) {
  // body unchanged for now; prune is implemented in Task 2
  // … (ported body) …
  return `<svg class="sys ${Lo.id}${extraClass ? ' ' + extraClass : ''}" data-s="${stage}" viewBox="${crop || `0 0 ${Lo.w} ${Lo.h}`}" role="img" aria-label="${label}">${s}</svg>`;
}
```

3. Create `website/src/content.mjs` from gen.cjs lines 308–427: export `STAGES`, `CROP`, `STEPS`, `OS`, `GLY`, `CMP` and the remaining section data exactly as in the prototype (`STEPS` references `TEAMS` — import it from `./figures.mjs`).
4. Create `website/src/page.mjs` from gen.cjs lines 324–392 (`still`, `stepsHTML`) and 428–567 (the `html` template), exporting `renderPage()`:

```js
import { readFileSync } from 'node:fs';
import { L, P, system, figureCSS } from './figures.mjs';
import { STAGES, CROP, STEPS, OS, GLY, CMP } from './content.mjs';
const here = new URL('.', import.meta.url);
const css = readFileSync(new URL('page.css', here), 'utf8');
const js = readFileSync(new URL('story.js', here), 'utf8');

const still = k => `<figure class="still" aria-label="Figure ${k + 1}">
  ${system(L, k, { label: STAGES[k].aria, crop: CROP.L[k] })}
  ${system(P, k, { label: STAGES[k].aria, crop: CROP.P[k] })}
  <figcaption><span class="fig-n">Figure ${k + 1}</span> ${STAGES[k].cap}</figcaption>
</figure>`;

export function renderPage() {
  // ported template from gen.cjs 431–566, with `system(L, 0, 'live', …)` → `system(L, 0, { extraClass: 'live', label: STAGES[0].aria })`
  return html;
}
```

5. Create `website/build.mjs`:

```js
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
```

- [ ] **Step 4: Run test to verify it passes, and compare with the prototype**

Run: `node --test website/tests/ && node website/build.mjs && cmp <(sed 's/Prototype 1 · Cinematic story//' website/index.html | wc -c) <(wc -c < $PROTO/gs-directions-2/1-cinematic.html) ; true`
Expected: tests PASS; build prints ~400,000 bytes (same as prototype, pruning comes next). Open `website/index.html` and the prototype side by side: identical rendering.

- [ ] **Step 5: Commit**

```bash
git add website/src website/build.mjs website/tests/build.test.mjs website/index.html
git commit -m "website: build the landing page from source modules (port of the cinematic prototype)"
```

---

### Task 2: Prune stills and move copy out of JavaScript (size budget + translation-ready)

**Files:**
- Modify: `website/src/figures.mjs` (`system`), `website/src/page.mjs` (`still`, live figure, script data), `website/src/story.js` (`setStage`)
- Test: `website/tests/build.test.mjs`

**Interfaces:**
- Consumes: `system(Lo, stage, opts)` from Task 1.
- Produces: `system(…, { prune: true })` omits every group whose stage list excludes `stage`; stills call it with `prune: true`; live figure keeps `prune: false`. `story.js` reads `figure.still figcaption` text and still `svg[aria-label]` for the live caption/label.

- [ ] **Step 1: Write the failing tests**

```js
// append to website/tests/build.test.mjs
import { system, L } from '../src/figures.mjs';

test('pruned still contains only its stage', () => {
  const s0 = system(L, 0, { prune: true });
  assert.doesNotMatch(s0, /supervisor/);          // stage 5 only
  assert.doesNotMatch(s0, /Customer operations/); // stages 7–8 only
  const s5 = system(L, 5, { prune: true });
  assert.match(s5, /supervisor/);
  assert.match(s5, /illustration/);
});

test('built page is under 150 KB', () => {
  assert.ok(Buffer.byteLength(html) < 153600, `${Buffer.byteLength(html)} bytes`);
});

test('no copy lives in the script', () => {
  const script = html.match(/<script>([\s\S]*?)<\/script>/g).join('\n');
  assert.doesNotMatch(script, /CAPS|ARIA/);
  for (const phrase of ['One agent', 'supervisor restarts', 'Seven teams']) assert.ok(!script.includes(phrase), phrase);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `node --test website/tests/`
Expected: FAIL on all three (stills unpruned, ~400 KB, `CAPS` in script).

- [ ] **Step 3: Implement pruning**

In `figures.mjs`, add a group helper and use it for every `<g class="${vis([...])}…">…</g>` in `system`:

```js
// inside system(), before first use:
const grp = (stages, inner, extra = '') =>
  prune && !stages.includes(stage) ? '' : `<g class="${vis(stages)}${extra ? ' ' + extra : ''}">${inner}</g>`;
```

Replace, for example, `s += \`<g class="${vis([7, 8])}">${con}${band(Lo, b7, 'control layer')}</g>\`;` with `s += grp([7, 8], con + band(Lo, b7, 'control layer'));`, and likewise for the groups at stages `[1]`, `[2, 3]`, `[2]`, `[3]`, `[0]`, `[4, 5, 6]`, `[6]` (with extra `'escal'`), `[5]`, the two log groups, cluster groups (extra `cl${k}`) and the models group. For agents, skip the agent entirely when pruning and `!AGENT_VIS(i).includes(stage)`, and skip the `bnd` rect / label sub-groups by the same rule. Skip the token when pruning and stage ∉ [4,5,6].

In `page.mjs`, call `system(…, { prune: true, … })` in `still()`.

- [ ] **Step 4: Move captions/alt text into the DOM**

In `page.mjs`, delete the `const CAPS = …; const ARIA = …;` lines from the inline script. In `story.js`, replace the two array reads in `setStage`:

```js
var still = steps[k].querySelector('figure.still');
stage.setAttribute('aria-label', still.querySelector('svg').getAttribute('aria-label'));
figCap.textContent = still.querySelector('figcaption').lastChild.textContent.trim();
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `node --test website/tests/ && node website/build.mjs`
Expected: PASS; build prints < 153,600 bytes. Open the page: the live figure caption still changes per step; stills look identical to Task 1.

- [ ] **Step 6: Commit**

```bash
git add website/src website/tests website/index.html
git commit -m "website: prune figure stills to their stage and keep all copy in the markup"
```

---

### Task 3: Copy, facts and honesty rules

**Files:**
- Modify: `website/src/content.mjs`, `website/src/page.mjs` (nav, hero facts line, close, footer)
- Test: `website/tests/build.test.mjs`

**Interfaces:**
- Consumes: content exports from Task 1.
- Produces: final English copy per spec §3–4 (the i18n source).

- [ ] **Step 1: Write the failing tests**

```js
// append to website/tests/build.test.mjs
const text = html.replace(/<script[\s\S]*?<\/script>|<style[\s\S]*?<\/style>/g, '').replace(/<[^>]+>/g, ' ').replace(/&nbsp;/g, ' ').replace(/\s+/g, ' ');

test('banned claims are absent', () => {
  assert.doesNotMatch(text, /GenLayer(?! Labs)|unhardcoded|blockchain/i);
  assert.doesNotMatch(text, /\bRBAC\b|per-user permission|approval workflow|sandboxed packages/i);
  assert.doesNotMatch(text, /(?<!not )exactly once/i);
  assert.doesNotMatch(text, /\bmemory\b/i);
});

test('owner copy edits are applied', () => {
  assert.match(text, /their roles, tools, boundaries, communication, workflows and supervision/);
  assert.match(text, /what tools, data and systems each agent can access/);
  assert.match(text, /how agents communicate(?! and share)/);
});

test('facts match v0.2.0', () => {
  assert.match(text, /0\.2\.0/);
  for (const b of ['Local', 'Tmux', 'Docker', 'Apple container', 'SSH', 'Bwrap', 'Mock']) assert.ok(text.includes(b), b);
  assert.match(text, /100 agents/);
  assert.match(text, /illustration/i);
});

test('comparison has no Draft stamp once sourced', () => {
  assert.doesNotMatch(text, /Draft/);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `node --test website/tests/`
Expected: FAIL on "owner copy edits" (prototype says "files … reach") and "comparison has no Draft stamp".

- [ ] **Step 3: Apply the copy**

In `content.mjs` `STEPS[3]` change `<li>what tools, files and systems each agent can reach</li>` → `<li>what tools, data and systems each agent can access</li>`. Set `OS` to the ten rows of spec §4.2 (text verbatim from the spec table, column 2). Set the guarantees and not-yet lists to spec §4.3 verbatim. Nav in `page.mjs`: `How it works` (`#os`) · `Compare` (`#compare`) · `Security` (`#security`) · `Docs` (`/docs/`) · `GitHub` (`https://github.com/genlayerlabs/genswarms`); no version badge. Hero facts line: `Open source under the MIT license. Version 0.2.0, built on Elixir/OTP.` Footer links: Docs, GitHub, License (`https://github.com/genlayerlabs/genswarms/blob/main/LICENSE`), `skill.md` (`/skill.md`), `llms.txt` (`/llms.txt`); `© 2026 GenLayer Labs · MIT License`.

- [ ] **Step 4: Fill the comparison from sources**

Research each cell (What it is · Where agents run · What a crash affects · Control surface) for LangGraph, CrewAI and AutoGen from their current official docs (use WebFetch/WebSearch; prefer docs.langchain.com / langchain-ai.github.io, docs.crewai.com, microsoft.github.io/autogen). Record each cell's URL and the access date in `design/comparison-sources.md`:

```markdown
# Comparison sources (accessed 2026-09-25)
| Project | Row | Cell text | Source |
|---|---|---|---|
| LangGraph | What it is | … | https://… |
```

Write the cells neutrally; where a project offers a hosted/deployment product, say so in the cell. Remove the "Draft — to be fact-checked" tag and its CSS.

- [ ] **Step 5: Run tests to verify they pass**

Run: `node --test website/tests/ && node website/build.mjs`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add website design/comparison-sources.md
git commit -m "website: final copy, v0.2.0 facts and a sourced comparison"
```

---

### Task 4: Story controller robustness and the no-JS baseline

**Files:**
- Modify: `website/src/story.js`, `website/src/page.css`, `website/src/page.mjs` (skip link)
- Create: `website/tests/browser/story.cjs`

**Interfaces:**
- Consumes: DOM contract from Tasks 1–2: `html.cine` class toggles pinned mode; `.sys.live[data-s]`; `.step[data-step]` each containing `figure.still`; `#figN`, `#figCap`; `.rail button[data-go]`.
- Produces: `story.js` behaviours checked by `story.cjs`.

- [ ] **Step 1: Write the failing browser test**

```js
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
  // focus is never hidden under the figure or nav
  await p.goto(BASE); await p.waitForTimeout(300);
  for (let i = 0; i < 25; i++) {
    await p.keyboard.press('Tab');
    const r = await p.evaluate(() => { const e = document.activeElement, b = e.getBoundingClientRect(), fig = document.querySelector('.stage-col'), nav = document.querySelector('header nav');
      const hit = x => x && (() => { const c = x.getBoundingClientRect(); return b.left < c.right && c.left < b.right && b.top < c.bottom && c.top < b.bottom; })();
      return { tag: e.tagName, hidden: e.closest('.stage-col') ? false : (hit(fig) || (hit(nav) && !e.closest('nav'))) }; });
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
  await b.close();
  if (fail.length) { console.log(fail.join('\n')); process.exit(1); }
  console.log('story ok');
})();
```

- [ ] **Step 2: Run it to verify it fails**

Run: `node website/build.mjs && (python3 -m http.server 8766 --directory website >/dev/null 2>&1 &) && sleep 1 && NODE_PATH=$PROTO/node_modules node website/tests/browser/story.cjs`
Expected: FAIL at least on "deep link #s6 shows stage 6" (the prototype only updates on intersection), "wide again → stage 6" and "skip link".

- [ ] **Step 3: Sync the stage on load and on mode change**

In `story.js`, add a function that finds the step whose top is closest above the viewport's 46% line and call it on load, on `resize`, and inside `mode()`:

```js
function current() {
  var line = innerHeight * 0.46, best = 0;
  for (var i = 0; i < steps.length; i++) if (steps[i].getBoundingClientRect().top <= line) best = i;
  return best;
}
function sync() { setStage(current()); }
function mode() { root.classList.toggle('cine', mqW.matches && !mqR.matches); sync(); }
addEventListener('load', sync);
addEventListener('resize', sync, { passive: true });
```

- [ ] **Step 4: Skip link and focus offset**

In `page.mjs`, add as the first element in `<body>`: `<a class="skip" href="#os">Skip to how it works</a>` (the proof section already has `id="os"`). In `page.css`:

```css
.skip{position:absolute;left:16px;top:-60px;background:var(--ink);color:var(--sand);padding:10px 14px;border-radius:8px;z-index:100}
.skip:focus{top:12px}
html{scroll-padding-top:88px}
.cine .step :focus-visible{scroll-margin-top:96px}
```

- [ ] **Step 5: No-JS baseline**

In `page.css`, make in-flow the default and pinned layout apply only under `.cine` (which only JS adds): confirm every rule that hides `figure.still` is scoped to `.cine` (e.g. `.cine .still{display:none}`), and that `.sys.live`'s column is `display:none` unless `.cine`.

- [ ] **Step 6: Run the browser test to verify it passes**

Run: `node website/build.mjs && NODE_PATH=$PROTO/node_modules node website/tests/browser/story.cjs`
Expected: `story ok`.

- [ ] **Step 7: Commit**

```bash
git add website
git commit -m "website: story syncs on load and resize, skip link, JS-free baseline"
```

---

### Task 5: Level up the figures and layout

**Files:**
- Modify: `website/src/figures.mjs` (geometry `L.fs`, strokes, hero figure), `website/src/page.css`
- Test: `website/tests/build.test.mjs` (hero figure content), visual review screenshots

**Interfaces:**
- Consumes: `system()` from Tasks 1–2.
- Produces: final drawings; no interface change.

- [ ] **Step 1: Write the failing test**

```js
// append to website/tests/build.test.mjs
test('hero figure already reads as a workforce', () => {
  const s0 = system(L, 0, { prune: true });
  assert.match(s0, /class="[^"]*\borg-ghost\b/);            // faint organization outline in figure 1
  assert.match(s0, />model<.*>prompt<.*>tools</s);
});
test('no pill badges or tracked uppercase eyebrows', () => {
  assert.doesNotMatch(html, /class="[^"]*\b(pill|badge|eyebrow)\b/);
  assert.doesNotMatch(css(), /text-transform:\s*uppercase[^}]*letter-spacing|letter-spacing[^}]*text-transform:\s*uppercase/);
});
```

(with `import { readFileSync } from 'node:fs'; const css = () => readFileSync(new URL('../src/page.css', import.meta.url), 'utf8');` at the top of the file.)

- [ ] **Step 2: Run to verify it fails**

Run: `node --test website/tests/`
Expected: FAIL on `org-ghost`.

- [ ] **Step 3: Figure 1 shows the workforce ahead**

In `system()`, stage `[0]` group: add a faint organization outline behind the single agent — the stage-7 cluster positions drawn at 12% opacity:

```js
const ghost = Lo.clusters.map(([x, y]) => `<circle class="org-ghost" cx="${x}" cy="${y}" r="${Lo.id === 'L' ? 34 : 26}"/>`).join('');
// in the stage-0 group: g0 = ghost + g0;
```

and in `page.css`: `.org-ghost{fill:none;stroke:var(--ink);stroke-opacity:.12;stroke-width:1.2;stroke-dasharray:2 5}`.

- [ ] **Step 4: Scale, stroke hierarchy and colour discipline**

In `page.css`:

```css
/* figure column takes the room on wide screens */
.cine .stage-col{width:min(58vw,880px)}
.cine .sys.live{width:100%;height:min(78vh,720px)}
/* ink hierarchy: declared paths solid and strong, manual wiring dotted and light */
.sys .e{stroke:var(--ink);stroke-width:1.8}
.sys .wire{stroke:var(--ink);stroke-opacity:.45;stroke-width:1.2;stroke-dasharray:2 5}
.sys .bnd{stroke:var(--ink);stroke-opacity:.35;stroke-width:1.2;stroke-dasharray:3 4}
/* clay only for moving work, active state and failure */
.sys .tok circle,.sys .eh,.sys .e-h.esc{fill:var(--clay);stroke:var(--clay)}
.sys .burst{stroke:#E0664A}.sys .restart{stroke:#8fa06f}
/* morphs between stages */
@media (prefers-reduced-motion:no-preference){.sys .ag{transition:transform .9s cubic-bezier(.22,1,.36,1)}.sys .fx{transition:opacity .5s}}
/* display type: stronger scale */
h1{font-size:clamp(46px,6.6vw,104px);line-height:.95;letter-spacing:-.035em}
.step h2{font-size:clamp(34px,4.2vw,64px);line-height:1;letter-spacing:-.03em}
```

In `figures.mjs` raise `L.fs` to `{ t: 20, ts: 16, tb: 26, log: 15 }` so labels stay ≥ 13px at the rendered width (live figure ≈ 800 user units at ≥ 700px wide).

- [ ] **Step 5: Fix step transitions that collide**

Give every story step enough room that its heading never meets the previous step's text: in `page.css` `.cine .step{min-height:100vh;padding:18vh 0}` and `.cine .step-hero{padding-top:12vh}`; for phones (in-flow) `.step{padding:56px 0}` and `.still{margin-top:28px}`.

- [ ] **Step 6: Remove template tells**

In `page.mjs`/`page.css`: remove pill badges and bordered chip buttons (ghost button becomes an underlined text link: `.btn-ghost{border:0;text-decoration:underline;text-underline-offset:4px}`), remove any uppercase+tracked label styles, keep "Figure N" (a real sequence).

- [ ] **Step 7: Run tests, build, and review screenshots**

Run: `node --test website/tests/ && node website/build.mjs && NODE_PATH=$PROTO/node_modules node website/tests/browser/story.cjs`
Expected: PASS and `story ok`. Then take full-page screenshots at 1440×900 and 390×844 (scroll through as in the prototype review) and Read them: headings never collide, figures fill their column, labels readable.

- [ ] **Step 8: Commit**

```bash
git add website
git commit -m "website: level up figures, type scale and step rhythm"
```

---

### Task 6: Layout audit at 12 widths, landscape and large font

**Files:**
- Create: `website/tests/browser/audit.cjs`

**Interfaces:**
- Consumes: built `website/index.html` served at `BASE`.

- [ ] **Step 1: Write the audit**

```js
// website/tests/browser/audit.cjs
const { chromium } = require('playwright-core');
const BASE = process.env.BASE || 'http://localhost:8766/';
const SIZES = [[320,720],[360,780],[375,812],[390,844],[414,896],[480,900],[600,900],[768,1024],[820,1180],[1024,768],[1280,800],[1440,900],[1440,640],[844,390]];
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' });
  const out = [];
  for (const [w, h] of SIZES) for (const big of [false, true]) {
    const phone = w <= 820 && h > w;
    const c = await b.newContext({ viewport: { width: w, height: h }, isMobile: phone, hasTouch: phone });
    const p = await c.newPage(); const errs = [];
    p.on('pageerror', e => errs.push(e.message)); p.on('console', m => m.type() === 'error' && errs.push(m.text()));
    p.on('response', r => r.status() >= 400 && errs.push(r.status() + ' ' + r.url()));
    await p.goto(BASE, { waitUntil: 'networkidle' });
    if (big) await p.addStyleTag({ content: 'html{font-size:24px}' });
    const H = await p.evaluate(() => document.documentElement.scrollHeight);
    for (let y = 0; y < H; y += h) {
      await p.evaluate(y => scrollTo(0, y), y); await p.waitForTimeout(120);
      const r = await p.evaluate(({ phone }) => {
        const o = [], de = document.documentElement;
        if (de.scrollWidth > innerWidth) o.push(`overflow ${de.scrollWidth}`);
        const fig = document.querySelector('.cine .stage-col');
        if (fig) { const f = fig.getBoundingClientRect();
          if (f.height > innerHeight + 1) o.push('pinned figure taller than viewport');
          for (const t of document.querySelectorAll('.step .copy')) { const b = t.getBoundingClientRect();
            if (b.bottom > 0 && b.top < innerHeight && b.left < f.right && f.left < b.right && b.top < f.bottom && f.top < b.bottom) o.push('step text under figure'); } }
        const tw = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
        for (let n; (n = tw.nextNode());) { const e = n.parentElement; if (!n.textContent.trim() || !e.offsetParent || e.closest('svg,.skip')) continue;
          if (parseFloat(getComputedStyle(e).fontSize) < 12) o.push('text < 12px: ' + n.textContent.trim().slice(0, 20)); }
        if (phone) for (const a of document.querySelectorAll('a,button')) { if (!a.offsetParent || a.closest('p,li') || a.classList.contains('skip')) continue;
          const r = a.getBoundingClientRect(); if (r.height < 44) o.push('tap target ' + Math.round(r.height) + 'px: ' + a.textContent.trim().slice(0, 20)); }
        return o;
      }, { phone });
      r.forEach(m => out.push(`${w}x${h}${big ? ' 24px' : ''}: ${m}`));
    }
    errs.forEach(m => out.push(`${w}x${h}: ${m}`));
    await c.close();
  }
  await b.close();
  const uniq = [...new Set(out)];
  if (uniq.length) { console.log(uniq.join('\n')); process.exit(1); }
  console.log(`audit ok: ${SIZES.length} sizes × 2 font sizes`);
})();
```

- [ ] **Step 2: Run it**

Run: `node website/build.mjs && NODE_PATH=$PROTO/node_modules node website/tests/browser/audit.cjs`
Expected on first run: some failures (likely `1440x640` pinned figure taller than viewport, `844x390` step text under figure, large-font text under figure).

- [ ] **Step 3: Fix what it reports**

Typical fixes in `page.css`:

```css
/* short viewports: figure never taller than the viewport minus nav */
.cine .sys.live{max-height:calc(100vh - 110px)}
/* landscape phones and short screens: in-flow mode (JS mode switch uses this query) */
@media (max-height:560px){ .stage-col{display:none} }
/* large fonts: story text column never shares space with the figure */
.cine .story{display:grid;grid-template-columns:minmax(0,1fr) min(58vw,880px);gap:48px}
```

and in `story.js` extend the mode query: `var mqW = matchMedia('(min-width: 1000px) and (min-height: 561px)');`.

- [ ] **Step 4: Run audit and story test again**

Run: `node website/build.mjs && NODE_PATH=$PROTO/node_modules node website/tests/browser/audit.cjs && NODE_PATH=$PROTO/node_modules node website/tests/browser/story.cjs`
Expected: `audit ok: 14 sizes × 2 font sizes` and `story ok`.

- [ ] **Step 5: Commit**

```bash
git add website
git commit -m "website: layout audit across widths, landscape and large fonts"
```

---

### Task 7: Head, structured data, llms.txt, 404, OG image, sitemap

**Files:**
- Modify: `website/src/page.mjs` (head), `website/llms.txt`, `website/404.html`, `website/sitemap.xml`
- Create: `website/tools/og.cjs`
- Test: `website/tests/build.test.mjs`

- [ ] **Step 1: Write the failing tests**

```js
// append to website/tests/build.test.mjs
test('head metadata', () => {
  const desc = html.match(/<meta name="description" content="([^"]+)"/)[1];
  assert.ok(desc.length <= 150, `description ${desc.length} chars`);
  assert.match(html, /<title>GenSwarms: the operating system for AI workforces<\/title>/);
  assert.match(html, /<link rel="canonical" href="https:\/\/genswarms\.com\/"/);
  assert.match(html, /<meta http-equiv="content-language" content="en"/);
  for (const i of ['/favicon.svg', '/favicon-32.png', '/apple-touch-icon.png']) assert.ok(html.includes(`href="${i}"`), i);
  const ld = JSON.parse(html.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/)[1]);
  assert.equal(ld['@type'], 'SoftwareApplication');
  assert.equal(ld.softwareVersion, '0.2.0');
  assert.doesNotMatch(html, /FAQPage/);
});
test('llms.txt matches the new positioning', () => {
  const t = readFileSync(new URL('../llms.txt', import.meta.url), 'utf8');
  assert.match(t, /operating system for AI workforces/);
  assert.match(t, /0\.2\.0/);
  assert.match(t, /Apple container/);
  assert.doesNotMatch(t, /~380|54 ?KB/);
});
```

- [ ] **Step 2: Run to verify failure**

Run: `node --test website/tests/`
Expected: FAIL on title/description/ld+json/llms.txt.

- [ ] **Step 3: Implement the head**

In `page.mjs` head:

```html
<title>GenSwarms: the operating system for AI workforces</title>
<meta name="description" content="GenSwarms runs AI agents as isolated, supervised processes on declared message paths, with an API and a live event stream. Open source, MIT.">
<link rel="canonical" href="https://genswarms.com/">
<meta http-equiv="content-language" content="en">
<meta property="og:type" content="website"><meta property="og:locale" content="en_US">
<meta property="og:title" content="GenSwarms: the operating system for AI workforces">
<meta property="og:description" content="Deploy, coordinate and control AI agents as isolated, supervised processes.">
<meta property="og:url" content="https://genswarms.com/"><meta property="og:image" content="https://genswarms.com/og-image.png">
<meta name="twitter:card" content="summary_large_image">
<link rel="icon" href="/favicon.svg" type="image/svg+xml"><link rel="icon" href="/favicon-32.png" sizes="32x32"><link rel="apple-touch-icon" href="/apple-touch-icon.png">
<script type="application/ld+json">{"@context":"https://schema.org","@type":"SoftwareApplication","name":"GenSwarms","applicationCategory":"DeveloperApplication","operatingSystem":"Linux, macOS","softwareVersion":"0.2.0","license":"https://opensource.org/licenses/MIT","url":"https://genswarms.com/","codeRepository":"https://github.com/genlayerlabs/genswarms","description":"The operating system for AI workforces: runs AI agents as isolated, supervised processes on declared message paths, with a REST + WebSocket API and a live event stream.","offers":{"@type":"Offer","price":"0","priceCurrency":"USD"},"author":{"@type":"Organization","name":"GenLayer Labs"}}</script>
```

(`author` "GenLayer Labs" is the MIT copyright holder, allowed; the test's `GenLayer(?! Labs)` excludes it.)

- [ ] **Step 4: llms.txt, 404, sitemap**

Rewrite `website/llms.txt`: title `# GenSwarms`, summary `> The operating system for AI workforces. …` with the spec §4.2 mechanisms as bullets, version 0.2.0, the 7 backends, links to docs, `skill.md`, `llms-full.txt`, GitHub. Restyle `website/404.html` with the page palette and fonts (reuse the `.btn-primary` look; message "This page ran off the swarm." and a link home). Set `<lastmod>` in `website/sitemap.xml` to the merge date.

- [ ] **Step 5: OG image**

```js
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
```

Run it, then Read `website/og-image.png`: headline and figure 1 fully visible, nothing cut.

- [ ] **Step 6: Run tests**

Run: `node --test website/tests/ && node website/build.mjs`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add website
git commit -m "website: head, structured data, llms.txt, 404, OG image, sitemap"
```

---

### Task 8: Deploy workflow

**Files:**
- Modify: `.github/workflows/pages.yml`

- [ ] **Step 1: Write the failing check**

```bash
# design/check-deploy-copy.sh — simulates the Pages copy step into a temp dir
set -euo pipefail
T=$(mktemp -d); mkdir -p "$T/_site"
# the copy command under test (keep identical to pages.yml):
rsync -a --exclude src --exclude tests --exclude tools --exclude build.mjs website/ "$T/_site/"
for f in index.html 404.html favicon.svg favicon-32.png apple-touch-icon.png og-image.png robots.txt sitemap.xml llms.txt CNAME; do test -f "$T/_site/$f" || { echo "missing $f"; exit 1; }; done
for d in src tests tools build.mjs; do test ! -e "$T/_site/$d" || { echo "leaked $d"; exit 1; }; done
echo "deploy copy ok"
```

Run: `bash design/check-deploy-copy.sh`
Expected: `deploy copy ok` (this validates the command before it goes in the workflow).

- [ ] **Step 2: Update the workflow**

In `.github/workflows/pages.yml`, replace the `cp website/index.html … cp website/llms.txt _site/llms.txt` lines in "Place landing page at site root" with:

```yaml
          rsync -a --exclude src --exclude tests --exclude tools --exclude build.mjs website/ _site/
          touch _site/.nojekyll
          cp SKILL.md _site/skill.md
```

(keep the existing `llms-full.txt` block after it), and add before "Build docs into _site/docs":

```yaml
      - uses: actions/setup-node@v4
        with:
          node-version: "20"
      - name: Landing page is built from its sources and passes its tests
        run: |
          node --test website/tests/
          node website/build.mjs --check
```

- [ ] **Step 3: Verify**

Run: `node --test website/tests/ && node website/build.mjs --check && bash design/check-deploy-copy.sh`
Expected: tests pass, `website/index.html is up to date`, `deploy copy ok`.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/pages.yml design/check-deploy-copy.sh
git commit -m "pages: deploy the whole website folder (fixes 404 icons) and gate on the landing build"
```

---

### Task 9: Final verification and PR

- [ ] **Step 1: Full local run**

```bash
node --test website/tests/ && node website/build.mjs --check
(python3 -m http.server 8766 --directory website >/dev/null 2>&1 &) ; sleep 1
NODE_PATH=$PROTO/node_modules node website/tests/browser/story.cjs
NODE_PATH=$PROTO/node_modules node website/tests/browser/audit.cjs
```

Expected: all pass.

- [ ] **Step 2: Lighthouse**

```bash
for f in mobile desktop; do CHROME_PATH="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" $PROTO/node_modules/.bin/lighthouse http://localhost:8766/ --preset=$( [ $f = desktop ] && echo desktop || echo perf ) --only-categories=performance,accessibility,best-practices,seo --chrome-flags="--headless=new" --output=json --output-path=/tmp/lh-$f.json --quiet; done
node -e "for (const f of ['mobile','desktop']) { const c=require('/tmp/lh-'+f+'.json').categories; console.log(f, Object.values(c).map(x=>x.title+' '+Math.round(x.score*100)).join(' | ')) }"
```

Expected: accessibility, best practices, SEO 100; performance ≥ 90 on mobile. Fix and re-run until met.

- [ ] **Step 3: Claims trace**

Write the PR description's "Claims" table: every concrete sentence in the page's story and proof sections → the doc/code path from spec §4.2 or `design/comparison-sources.md`.

- [ ] **Step 4: Owner visual review**

Serve `website/`, open it in the owner's browser, and share full-page screenshots at 1440 and 390. Wait for approval.

- [ ] **Step 5: Push and open the PR**

Write `/tmp/pr-landing.md` with three sections: "Problem and outcome" (spec §1 goal and success criteria), "Implementation and validation" (the architecture from spec §7, the claims table from Step 3, and the literal output of Steps 1–2), and the line `🤖 Generated with [Claude Code](https://claude.com/claude-code)`. Then:

```bash
git push -u origin website/agentic-os
gh pr create --base main --title "Landing page: the operating system for AI workforces" --body-file /tmp/pr-landing.md
```
