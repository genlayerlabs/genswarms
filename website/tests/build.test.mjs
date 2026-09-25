import { test } from 'node:test';
import assert from 'node:assert/strict';
import { renderPage } from '../src/page.mjs';
import { readFileSync } from 'node:fs';
import { system, L, P } from '../src/figures.mjs';
const css = () => readFileSync(new URL('../src/page.css', import.meta.url), 'utf8');

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
  for (const phrase of ['One agent', 'supervisor restarts', 'Seven teams', 'Figure', 'Copy', 'Copied', 'Select and copy']) assert.ok(!script.includes(phrase), phrase);
});

const text = html.replace(/<script[\s\S]*?<\/script>|<style[\s\S]*?<\/style>/g, '').replace(/<[^>]+>/g, ' ').replace(/&nbsp;/g, ' ').replace(/\s+/g, ' ');

test('banned claims are absent', () => {
  assert.doesNotMatch(text, /GenLayer(?! Labs)|unhardcoded|blockchain/i);
  assert.doesNotMatch(text, /\bRBAC\b|per-user permission|approval workflow|sandboxed packages/i);
  assert.doesNotMatch(text, /(?<!not )exactly once/i);
  assert.doesNotMatch(text, /\bmemory\b/i);
});

test('approved copy deck is applied (design/2026-09-25-copy-deck.md)', () => {
  assert.match(text, /Deploy, coordinate and control thousands of AI agents across your organization\./);
  assert.match(text, /One example runs through the page: a customer who was charged twice\./);
  assert.match(text, /GenSwarms makes those decisions for agents: roles access to tools, data and systems who hands work to whom review and escalation recovery when an agent fails human oversight/);
  assert.match(text, /The charged-twice ticket enters at the classifier\./);
  assert.match(text, /Each agent is its own supervised process\. A crash restarts that agent; the ticket carries on\./);
  assert.match(text, /How is it different from LangGraph, CrewAI or AutoGen\?/);
  assert.match(text, /Read https:\/\/genswarms\.com\/skill\.md and set up a swarm\./);
  // removed: explanatory paragraphs, the old analogy list, the Control surface row
  assert.doesNotMatch(text, /share context|how agents communicate|A runtime, not a library|Control surface|production-ready/);
  // the two example lines are the only italic example style
  assert.equal((html.match(/class="ex"/g) || []).length, 2);
});

test('visible copy stays short (deck target ~430 words)', () => {
  const words = h => h.replace(/<svg[\s\S]*?<\/svg>|<script[\s\S]*?<\/script>|<style[\s\S]*?<\/style>/g, ' ')
    .replace(/<[^>]+>/g, ' ').replace(/&nbsp;/g, ' ').split(/\s+/).filter(w => /[\p{L}\p{N}]/u.test(w)).length;
  // the page's prose: <main> outside svg/script/style, without screen-reader-only text, the
  // pinned figure's label copies (shown one at a time, instead of the stills' labels) and the
  // comparison table (sourced data, fixed by design/comparison-sources.md)
  const prose = words(html.match(/<main[\s\S]*<\/main>/)[0].replace(/<(span|caption) class="sr"[\s\S]*?<\/\1>/g, ' ')
    .replace(/<figcaption class="stage-cap[\s\S]*?<\/figcaption>/, ' ').replace(/<table[\s\S]*?<\/table>/, ' '));
  assert.ok(prose <= 500, `${prose} words of prose`);
  // and everything outside svg/script/style in <body>, nav, footer and comparison cells included
  const all = words(html.match(/<body>[\s\S]*<\/body>/)[0]);
  assert.ok(all <= 660, `${all} words on the whole page`);
});

test('facts match v0.2.0', () => {
  assert.match(text, /0\.2\.0/);
  for (const b of ['Local', 'Tmux', 'Docker', 'Apple container', 'SSH', 'Bwrap', 'Mock']) assert.ok(text.includes(b), b);
  assert.match(text, /100 agents/);
  assert.match(text, /illustration/i);
});

test('every simulated/animated figure is labelled illustration', () => {
  // Figs. 5-7 (stages 4-6) carry a small "illustration" label; Fig. 8 (stage 7) says its team
  // shapes are illustrative (spec §4.4). Stills carry it in flow; the pinned figure shows it by stage.
  const note = k => html.match(new RegExp(`id="s${k}" data-step="${k}">[\\s\\S]*?</article>`))[0].match(/<figcaption class="fig-note">([^<]*)<\/figcaption>/);
  for (const k of [4, 5, 6]) assert.equal(note(k) && note(k)[1], 'illustration', `still ${k + 1}`);
  assert.equal(note(7) && note(7)[1], 'team shapes are illustrative');
  for (const k of [0, 1, 2, 3, 8]) assert.equal(note(k), null, `still ${k + 1} has no caption`);
  const live = html.match(/<figcaption class="stage-cap[^"]*">([\s\S]*?)<\/figcaption>/)[1];
  for (const k of [4, 5, 6]) assert.match(live, new RegExp(`data-at="${k}">illustration<`));
  assert.match(live, /data-at="7">team shapes are illustrative</);
  for (const k of [4, 5, 6, 7]) assert.match(css(), new RegExp(`\\.live\\[data-s="${k}"\\]~\\.stage-cap \\[data-at="${k}"\\]`));
  // Figs. 6-7 (stages 5-6): the event stream itself is labelled
  assert.match(system(L, 5, { prune: true }), /event stream \(illustration\)/);
  assert.match(system(L, 6, { prune: true }), /event stream \(illustration\)/);
});

test('comparison has no Draft stamp once sourced', () => {
  assert.doesNotMatch(text, /Draft/);
});

test('hero figure already reads as a workforce', () => {
  const s0 = system(L, 0, { prune: true });
  assert.match(s0, /class="[^"]*\borg-ghost\b/);            // faint organization outline in figure 1
  assert.match(s0, />model<.*>prompt<.*>tools</s);
});
test('no pill badges or tracked uppercase eyebrows', () => {
  assert.doesNotMatch(html, /class="[^"]*\b(pill|badge|eyebrow)\b/);
  assert.doesNotMatch(css(), /text-transform:\s*uppercase[^}]*letter-spacing|letter-spacing[^}]*text-transform:\s*uppercase/);
});
test('org ghost is pruned from later stills', () => {
  for (let k = 1; k <= 8; k++) assert.doesNotMatch(system(L, k, { prune: true }), /org-ghost/, `stage ${k}`);
  assert.match(system(P, 0, { prune: true }), /org-ghost/);
});
test('no bordered chip buttons: secondary actions are underlined links', () => {
  const c = css();
  assert.match(c, /\.btn-ghost\{[^}]*border:0[^}]*text-decoration:underline/);
  assert.doesNotMatch(c, /\.gh\{[^}]*border:1px/);
});
test('inlined CSS and JS are minified', () => {
  const style = html.match(/<style>([\s\S]*?)<\/style>/)[1];
  assert.doesNotMatch(style, /\/\*/, 'no CSS comments');
  assert.doesNotMatch(style, /\n[ \t]/, 'no indentation in CSS');
  const script = html.match(/<body>[\s\S]*<script>([\s\S]*?)<\/script>/)[1];
  assert.doesNotMatch(script, /^\s*\/\//m, 'no comment lines in JS');
  assert.doesNotMatch(script, /\n[ \t]/, 'no indentation in JS');
  assert.doesNotMatch(html.replace(/<script[\s\S]*?<\/script>|<style[\s\S]*?<\/style>/g, ''), /\n[ \t]+</, 'no indentation between tags');
});
test('figure labels are sized to stay >= 13px where they render', () => {
  // desktop: live figure is >= ~690px wide for 800 units at >= 1280px; phones: stills are 328px for 376 units at 360px
  for (const k of ['ts', 'log']) assert.ok(L.fs[k] >= 16, `L.fs.${k}`);
  for (const k of ['t', 'ts', 'log']) assert.ok(P.fs[k] >= 15, `P.fs.${k}`);
});
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
