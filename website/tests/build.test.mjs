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
  for (const phrase of ['One agent', 'supervisor restarts', 'Seven teams', 'Copy', 'Copied', 'Select and copy']) assert.ok(!script.includes(phrase), phrase);
});

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
  // desktop: live figure is >= ~690px wide for 800 units at >= 1280px; phones: stills bleed to ~360px for 400 units
  for (const k of ['ts', 'log']) assert.ok(L.fs[k] >= 16, `L.fs.${k}`);
  for (const k of ['t', 'ts', 'log']) assert.ok(P.fs[k] >= 14.5, `P.fs.${k}`);
});
