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
  assert.doesNotMatch(s0, /supervisor/);      // stage 3 only
  assert.doesNotMatch(s0, /invalid_route/);   // stage 4 only
  assert.doesNotMatch(s0, /swarm\.overlay/);  // stage 7 only
  const s3 = system(L, 3, { prune: true });
  assert.match(s3, /supervisor/);
  assert.match(s3, /crashed, restarted/);
  assert.doesNotMatch(s3, /illustration/);
  const s4 = system(L, 4, { prune: true });
  assert.match(s4, /events \(illustration\)/);
  assert.doesNotMatch(s4, /swarmidx/);
});

test('built page is under 150 KB', () => {
  assert.ok(Buffer.byteLength(html) < 153600, `${Buffer.byteLength(html)} bytes`);
});

test('no copy lives in the script', () => {
  const script = html.match(/<script>([\s\S]*?)<\/script>/g).join('\n');
  assert.doesNotMatch(script, /CAPS|ARIA/);
  for (const phrase of ['operating system', 'Every agent is a process', 'declared paths', 'Not everything needs a model', 'Install what your agents need', 'A swarm is a document', 'One control layer', 'Step', 'Figure', 'illustration', 'dropped', 'Copy', 'Copied', 'Select and copy']) assert.ok(!script.includes(phrase), phrase);
});

const text = html.replace(/<script[\s\S]*?<\/script>|<style[\s\S]*?<\/style>/g, '').replace(/<[^>]+>/g, ' ').replace(/&nbsp;/g, ' ').replace(/\s+/g, ' ');

test('banned claims are absent', () => {
  // (the package scope genlayerlabs/ in the stage-6 figure is a real swarmidx identifier)
  assert.doesNotMatch(text, /GenLayer(?! Labs|labs\/)|unhardcoded|blockchain/i);
  assert.doesNotMatch(text, /\bRBAC\b|per-user permission|approval workflow|sandboxed packages/i);
  assert.doesNotMatch(text, /(?<!not )exactly once/i);
  assert.doesNotMatch(text, /\bmemory\b/i);
});

test('approved copy deck v2 is applied (design/2026-09-25-copy-deck-v2.md)', () => {
  assert.match(text, /Deploy, coordinate and control thousands of AI agents across your organization\./);
  const heads = [...html.matchAll(/<article class="step[^"]*" id="s\d"[\s\S]*?<h[12]>([\s\S]*?)<\/h[12]>/g)].map(m => m[1].replace(/&nbsp;/g, ' '));
  assert.deepEqual(heads, ['The operating system for AI workforces.', 'Your agents need more than models and prompts.', 'Think of it as an operating system.',
    'Every agent is a process.', 'Agents talk only along declared paths.', 'Not everything needs a model.', 'Install what your agents need.',
    'A swarm is a document.', 'One control layer for your AI organization.']);
  assert.match(text, /One agent is easy\. Many agents working together need somewhere to run, rules for who talks to whom, and a way back when one fails\./);
  assert.match(text, /An operating system runs programs it didn’t write\. GenSwarms does that for agents: it starts them, isolates them, routes their messages and restarts them when they fail\./);
  assert.match(text, /You draw the graph\. Every message is checked against it, and anything off the graph is dropped\./);
  assert.match(text, /signed packages from the swarmidx index, verified before they load\./);
  assert.match(text, /A bad change is refused before it runs; a stopped swarm comes back from its database\./);
  assert.match(text, /Models provide intelligence\. Agents perform work\. GenSwarms runs the organization\./);
  assert.match(text, /How is it different from LangGraph, CrewAI or AutoGen\?/);
  assert.match(text, /In use today for chat assistants, coding agents, trading simulations and swarms that watch other swarms\./);
  assert.match(text, /Read https:\/\/genswarms\.com\/skill\.md and set up a swarm\./);
  // removed: v1's turn block and determines list, explanatory paragraphs, the Control surface row
  assert.doesNotMatch(html, /class="(turn|turn-k|turn-q|determines|strike)\b/);
  assert.doesNotMatch(text, /It becomes|share context|A runtime, not a library|Control surface|production-ready|build an AI workforce/);
  // one italic example line, on step 4
  assert.equal((html.match(/class="ex"/g) || []).length, 1);
  assert.match(html, /id="s4" data-step="4">\s*<div class="copy">[\s\S]*?<p class="ex">From here the drawings follow one swarm: a support team that answers customers on Telegram\.<\/p>/);
  // "How it works." has the deck's ten rows, in order
  assert.deepEqual([...html.matchAll(/<dt>([^<]+)<\/dt>/g)].map(m => m[1]), ['Processes', 'Isolation', 'Network', 'Messages', 'Services', 'Drivers', 'Packages', 'State', 'Control', 'Events']);
  assert.equal((html.match(/<ul class="yes">([\s\S]*?)<\/ul>/)[1].match(/<li>/g) || []).length, 4);
  assert.equal((html.match(/<ul class="not">([\s\S]*?)<\/ul>/)[1].match(/<li>/g) || []).length, 5);
});

test('none of the removed v1 story remains (page, llms.txt)', () => {
  const llms = readFileSync(new URL('../llms.txt', import.meta.url), 'utf8');
  for (const [name, t] of [['index.html', html], ['llms.txt', llms]]) {
    for (const re of [/charged/i, /classifier/i, /verifier/i, /escalat/i, /human/i, /agent_blocked/i, /attaches/i, /team shapes/i, /Customer operations/i, /coordination layer/i])
      assert.doesNotMatch(t, re, `${name}: ${re}`);
  }
});

test('rail buttons are named after their step headlines', () => {
  const names = [...html.matchAll(/<button type="button" data-go="(\d)" aria-label="([^"]+)"/g)].map(m => m[2]);
  assert.equal(names.length, 9);
  assert.equal(names[0], 'Step 1: The operating system for AI workforces.');
  assert.equal(names[2], 'Step 3: Think of it as an operating system.');
  assert.equal(names[5], 'Step 6: Not everything needs a model.');
  assert.equal(names[7], 'Step 8: A swarm is a document.');
  for (const [k, n] of names.entries()) assert.ok(text.includes(n.replace(/^Step \d: /, '')), `step ${k + 1} name matches a visible headline`);
});

test('visible copy stays short (deck v2: 530 words of prose)', () => {
  const words = h => h.replace(/<svg[\s\S]*?<\/svg>|<script[\s\S]*?<\/script>|<style[\s\S]*?<\/style>/g, ' ')
    .replace(/<[^>]+>/g, ' ').replace(/&nbsp;/g, ' ').split(/\s+/).filter(w => /[\p{L}\p{N}]/u.test(w)).length;
  // the page's prose: <main> outside svg/script/style, without screen-reader-only text, the
  // pinned figure's label copies (shown one at a time, instead of the stills' labels) and the
  // comparison table (sourced data, fixed by design/comparison-sources.md)
  const prose = words(html.match(/<main[\s\S]*<\/main>/)[0].replace(/<(span|caption) class="sr"[\s\S]*?<\/\1>/g, ' ')
    .replace(/<figcaption class="stage-cap[\s\S]*?<\/figcaption>/, ' ').replace(/<table[\s\S]*?<\/table>/, ' '));
  // caps pinned at deck v2's applied counts (530 / 711), so copy can't grow silently
  assert.ok(prose <= 530, `${prose} words of prose`);
  // and everything outside svg/script/style in <body>, nav, footer and comparison cells included
  const all = words(html.match(/<body>[\s\S]*<\/body>/)[0]);
  assert.ok(all <= 711, `${all} words on the whole page`);
});

test('facts match v0.2.0', () => {
  assert.match(text, /0\.2\.0/);
  for (const b of ['Local', 'Tmux', 'Docker', 'Apple container', 'SSH', 'Bwrap', 'Mock']) assert.ok(text.includes(b), b);
  assert.match(text, /100 agents/);
  assert.match(text, /illustration/i);
});

test('every simulated/animated figure is labelled illustration', () => {
  // Figs. 5-8 (stages 4-7: the support swarm, its routed and dropped messages, packages with
  // placeholder digests, the change log) carry a small "illustration" label (spec §4). Stills
  // carry it in flow; the pinned figure shows it by stage.
  const note = k => html.match(new RegExp(`id="s${k}" data-step="${k}">[\\s\\S]*?</article>`))[0].match(/<figcaption class="fig-note">([^<]*)<\/figcaption>/);
  for (const k of [4, 5, 6, 7]) assert.equal(note(k) && note(k)[1], 'illustration', `still ${k + 1}`);
  for (const k of [0, 1, 2, 3, 8]) assert.equal(note(k), null, `still ${k + 1} has no caption`);
  const live = html.match(/<figcaption class="stage-cap[^"]*">([\s\S]*?)<\/figcaption>/)[1];
  for (const k of [4, 5, 6, 7]) assert.match(live, new RegExp(`data-at="${k}">illustration<`));
  assert.doesNotMatch(live, /data-at="[0-38]"/);
  for (const k of [4, 5, 6, 7]) assert.match(css(), new RegExp(`\\.live\\[data-s="${k}"\\]~\\.stage-cap \\[data-at="${k}"\\]`));
  // Fig. 5 (stage 4): the event log itself is labelled, and uses the real telemetry event names
  for (const Lo of [L, P]) {
    const s4 = system(Lo, 4, { prune: true });
    assert.match(s4, /events \(illustration\)/);
    assert.match(s4, /message_routed/);
    assert.match(s4, /invalid_route\s*<\/tspan><tspan>research → telegram/);
    assert.match(s4, /message_routed\s*<\/tspan><tspan>answer → telegram/);
  }
});

test('figures draw the v2 story from real parts', () => {
  const both = k => system(L, k, { prune: true }) + system(P, k, { prune: true });
  assert.match(both(2), />operating system</);
  assert.match(both(3), />crashed, restarted</);
  assert.match(both(4), />telegram<[\s\S]*>triage<[\s\S]*>answer<[\s\S]*>research</);
  assert.match(both(4), />dropped</);
  for (const o of ['cron', 'budget', 'browser']) assert.match(both(5), new RegExp(`>${o}<`), o);
  assert.match(both(5), />agent, uses a model</);
  assert.match(both(5), />object, plain code</);
  // budget is called over HTTP, not a message route: dotted, arrowless lines from answer and research
  for (const Lo of [L, P]) assert.equal((system(Lo, 5, { prune: true }).match(/<line class="mc"/g) || []).length, 2, Lo.id);
  assert.doesNotMatch(both(5), /class="mc-h"/);
  assert.match(system(L, 5, { prune: true }), />model calls</);
  for (const pkg of ['genlayerlabs/genswarms-telegram@0.6.6', 'genlayerlabs/cron@0.2.8', 'genlayerlabs/genswarms-llm-proxy@0.4.2', 'genlayerlabs/browser@0.2.4'])
    assert.ok(both(6).includes(pkg), pkg);
  // digests are visibly shortened placeholders, never full-length hashes
  assert.doesNotMatch(html, /sha256:[0-9a-f]{5,}/);
  assert.match(both(7), /swarm\.state[\s\S]*swarm\.overlay/);
  assert.match(both(7), /1 add_agent research/);
  assert.match(both(7), /2 scale_agent_group answer 3/);
  // a refused change (OpPolicy agent_cap_exceeded, checked before a seq is assigned) is never
  // numbered or logged: shown after the log, without a seq
  assert.match(both(7), />scale_agent_group answer 150</);
  assert.doesNotMatch(both(7), /\b3 \w+_\w+/);
  assert.match(both(7), /refused: over the 100-agent cap/);
  assert.doesNotMatch(both(7), /add_topology_edges|billing/);
  assert.match(both(7), /restore: seed \+ 2 changes/);
  // stage 8: unnamed swarms, no people, no business teams
  assert.doesNotMatch(both(8), /Customer|Software|Sales|Finance|Security|Network operations|class="ch"|class="ce esc"/);
  assert.match(both(8), />Swarms</);
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
