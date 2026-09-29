// ---------- page content ----------
// Copy follows design/2026-09-25-copy-deck-v2.md, as set in the approved "v4 · Zoom" design (the hero facts row,
// the section sub-lines, the comparison's sources note, the readouts, the legend and the zoom caption are that
// design's additions). Every string goes through t() (src/i18n.mjs) with a note on where it shows; names and
// identifiers (agent and object names, event kinds, package refs, digests, document keys) stay as they are.
import { escText, fill } from './i18n.mjs';

// the camera's keyframes: K0 organization (hero) · K1 the support team · K2 one agent · K3 many agents wired by hand ·
// K4 the genswarms layer · K5 processes and sandboxes · K6 declared paths · K7 objects · K8 packages · K9 the swarm
// document · K10 the organization under one control layer. ARIA[k] is the drawing's text alternative at keyframe k.
export const ARIA = [
  'Illustration: an organization of 36 swarms, several thousand agents. Each swarm is a small structure of agents (circles) and objects (squares) on declared paths, under supervisors. Messages pulse along the paths; now and then one agent crashes and its supervisor restarts it.',
  'Illustration: the camera zooms into one swarm, a support team.',
  'Illustration: one agent, seen up close: a model, a prompt and some tools.',
  'Illustration: twelve agents, each wired to the others by hand.',
  'Illustration: the agents in rows under the GenSwarms layer, which starts, isolates, routes and restarts them.',
  'Illustration: each agent in its own sandbox under its own supervisor; one agent crashes and is restarted while the others keep running.',
  'Illustration: a support team: a Telegram object and triage, answer and research agents on declared paths. A message from research to Telegram is off the graph and dropped.',
  'Illustration: the same team with more objects: cron, a browser, and a budget that answer and research call for their model calls.',
  'Illustration: each object comes from a signed package, verified before it loads.',
  'Illustration: the swarm as a document: a seed and a log of changes. A change over the 100-agent cap is refused and never logged.',
  'Illustration: the camera pulls back to the whole organization, now under one control layer.',
];
export const aria = (t, k) => t(ARIA[k], `the zoom drawing, keyframe ${k}: its text alternative (aria-label of the canvas; read by screen readers, not shown). It changes as the reader scrolls`, { kind: 'attr' });

// the words drawn inside the canvas (sent to the page as JSON, in the page's language). Short labels carry a width
// budget: `max` characters on one line in the English design (count Chinese and Korean characters as two)
export function canvasStrings(t) {
  const L = (en, where, max) => t(en, `zoom drawing (canvas label): ${where}`, { kind: 'svg', max, lines: 1 });
  return {
    lv: [
      t('organization', 'zoom caption, top left of the drawing: the scale the camera is at (the whole organization; one word, lower case)', { kind: 'svg', max: 14, lines: 1 }),
      t('team', 'zoom caption: the scale the camera is at (one swarm, a team of agents; one word, lower case)', { kind: 'svg', max: 14, lines: 1 }),
      t('agent', 'zoom caption: the scale the camera is at (a single agent; one word, lower case); also the label under the agent drawn up close', { kind: 'svg', max: 14, lines: 1 }),
    ],
    count: t('{swarms} swarms · {agents} agents', 'zoom caption, after the scale while the whole organization is in view ({swarms} = 36, {agents} = about 2,900; numbers are formatted for your language)', { kind: 'svg', max: 30, lines: 1 }),
    layer: L('start · isolate · route · restart', 'the four jobs written inside the GenSwarms layer bar, right of the wordmark (four short verbs; hidden when the bar is too short for them)', 36),
    supervisor: L('supervisor', 'callout at the right of the process tree: the diamond above each agent', 15),
    process: L('process', 'callout at the right of the process tree: each agent runs as its own process', 15),
    sandbox: L('sandbox', 'callout at the right of the process tree: the dashed box around each agent', 15),
    dropped: L('dropped', 'orange, under the × on the message that is off the declared graph', 12),
    crashed: L('crashed', 'orange, under the agent that crashes; followed by “→ restarted”', 12),
    restarted: L('restarted', 'after “crashed →”, once its supervisor has restarted the agent', 14),
    modelCalls: L('model calls', 'under the dotted lines from answer and research to the budget object', 16),
    model: L('model', 'one agent up close: the hexagon (the model that decides the next step)', 10),
    tools: L('tools', 'one agent up close: the square (the tools that do the work)', 10),
    prompt: L('prompt', 'one agent up close: the page (the prompt that says what the job is)', 10),
    agent: t('agent', 'zoom caption: the scale the camera is at (a single agent; one word, lower case); also the label under the agent drawn up close', { kind: 'svg', max: 14, lines: 1 }),
    seed: L('seed', 'the swarm document: note at the right of its first heading, swarm.state (the swarm’s starting definition)', 22),
    log: L('log of changes', 'the swarm document: note at the right of its second heading, swarm.overlay', 22),
    declared: L('{n} declared', 'the swarm document, the “paths” row: how many message paths the swarm declares ({n} = 4)', 20),
    refused: t('refused: over the {cap}-agent cap', 'zoom drawing, the swarm document: why the last change was refused ({cap} = 100; keep it short, it may wrap once)', { kind: 'svg', max: 33, lines: 2 }),
    never: L('never logged', 'the swarm document, under the refused change: it gets no number and is not written to the log', 22),
    defines: L('defines', 'beside the arrow from the swarm document up to the running swarm (the document defines it)', 12),
    restores: t('restores from its database', 'zoom drawing: under the database cylinder left of the swarm document (a stopped swarm comes back from it; may wrap to two lines)', { kind: 'svg', max: 20, lines: 2 }),
  };
}

// ---------- readouts: what the drawing shows, as text ----------
// Each is shown in the stage (cine) or in the step's text (phones, no JS, screen readers). kv rows are [key, value].
const esc = escText;
const ill = t => t('(illustration)', 'readout heading suffix: the events and packages shown are simulated (after “events”, “packages · swarmidx”, “one event stream”)');
const kvRows = rows => `<dl class="log kv">${rows.map(([k, v, cls]) => `<div class="ln${cls ? ' ' + cls : ''}"><dt class="k">${k}</dt><dd>${v}</dd></div>`).join('')}</dl>`;
const ev = (k, a, b, hot, t) => `<div class="ln${hot ? ' hot' : ''}"><span class="k">${k}</span><span>${a} <span class="ar">→</span> ${b}</span>${hot ? `<span class="tag">${esc(t('dropped', 'readout (events): tag on the message that was dropped (it is off the declared graph)', { kind: 'svg', max: 12, lines: 1 }))}</span>` : ''}</div>`;
const W = (n, what) => `readout at keyframe ${n} (${what})`;
// nf formats a number for the page's language
export function readouts(t, nf = n => String(n)) {
  const agentN = (n, w) => fill(esc(t('agent {n}', `${w}: one of the twelve unnamed agents ({n} is its number)`, { kind: 'svg', max: 10, lines: 1 })), { n: nf(n) });
  return {
    2: `<p class="cap">${t('One agent: a model, a prompt and some tools.', W(2, 'one agent up close') + ': caption over the three rows')}</p>` + kvRows([
      [esc(t('model', 'zoom drawing (canvas label): one agent up close: the hexagon (the model that decides the next step)', { kind: 'svg', max: 10, lines: 1 })), t('decides the next step', W(2, 'one agent') + ': what the model does (a fragment)')],
      [esc(t('prompt', 'zoom drawing (canvas label): one agent up close: the page (the prompt that says what the job is)', { kind: 'svg', max: 10, lines: 1 })), t('says what the job is', W(2, 'one agent') + ': what the prompt does (a fragment)')],
      [esc(t('tools', 'zoom drawing (canvas label): one agent up close: the square (the tools that do the work)', { kind: 'svg', max: 10, lines: 1 })), t('do the work', W(2, 'one agent') + ': what the tools do (a fragment)')],
    ]),
    3: `<p class="cap">${t('Twelve agents, each wired to the others by hand.', W(3, 'agents wired by hand') + ': caption over the three rows')}</p>` + kvRows([
      [t('who talks to whom', W(3, 'agents wired by hand') + ': row label (a question, lower case)'), t('written into each agent', W(3, 'agents wired by hand') + ': answer to “who talks to whom”')],
      [t('where each one runs', W(3, 'agents wired by hand') + ': row label'), t('wherever it was started', W(3, 'agents wired by hand') + ': answer to “where each one runs”')],
      [t('when one fails', W(3, 'agents wired by hand') + ': row label'), t('nothing restarts it', W(3, 'agents wired by hand') + ': answer to “when one fails”')],
    ]),
    4: kvRows([
      [t('start', W(4, 'the operating system layer') + ': row label, the first of four jobs (a verb)'), t('each agent as its own process', W(4, 'the operating system layer') + ': what “start” means')],
      [t('isolate', W(4, 'the operating system layer') + ': row label (a verb)'), t('each one in its own sandbox', W(4, 'the operating system layer') + ': what “isolate” means')],
      [t('route', W(4, 'the operating system layer') + ': row label (a verb)'), t('messages along declared paths only', W(4, 'the operating system layer') + ': what “route” means')],
      [t('restart', W(4, 'the operating system layer') + ': row label (a verb)'), t('a failed agent, by its supervisor', W(4, 'the operating system layer') + ': what “restart” means')],
    ]),
    5: kvRows([
      [agentN(10, W(5, 'processes')), esc(t('crashed', 'zoom drawing (canvas label): orange, under the agent that crashes; followed by “→ restarted”; readout at keyframe 5: the agent’s state', { kind: 'svg', max: 12, lines: 1 })), 'hot'],
      [agentN(10, W(5, 'processes')), t('restarted by its supervisor', W(5, 'processes') + ': the same agent a moment later')],
      [fill(esc(t('{n} others', W(5, 'processes') + ': the rest of the twelve agents ({n} = 11)', { kind: 'svg', max: 10, lines: 1 })), { n: nf(11) }), t('running', W(5, 'processes') + ': state of the other agents'), 'dim'],
    ]),
    6: `<div class="log ev">${ev('message_routed', 'telegram', 'triage', 0, t)}${ev('message_routed', 'triage', 'research', 0, t)}${ev('invalid_route', 'research', 'telegram', 1, t)}${ev('message_routed', 'research', 'answer', 0, t)}</div>`,
    7: `<p class="cap">${t('Objects are plain code on the graph. Answer and research call <b>budget</b> for their model calls.', W(7, 'objects') + ': caption. <b>budget</b> is the object’s name: keep it as it is')}</p>` + kvRows([
      [t('agents', W(7, 'objects') + ': row label (the circles)'), esc(t('{names}: use a model', W(7, 'objects') + ': {names} = “triage, research, answer”, the agents’ names', { kind: 'svg', max: 40, lines: 2 })).replace('{names}', 'triage, research, answer')],
      [t('objects', W(7, 'objects') + ': row label (the squares)'), esc(t('{names}: plain code', W(7, 'objects') + ': {names} = “telegram, cron, browser, budget”, the objects’ names', { kind: 'svg', max: 40, lines: 2 })).replace('{names}', 'telegram, cron, browser, budget')],
    ]),
    8: `<div class="log pk">${[['genswarms-telegram@0.6.6', '9f2c…'], ['cron@0.2.8', '4be1…'], ['browser@0.2.4', '51d3…'], ['genswarms-llm-proxy@0.4.2', 'c07a…']].map(([n, d]) => `<div class="ln"><span class="pn">genlayerlabs/${n}</span><span class="dg">sha256:${d}</span><span class="vf">${esc(t('verified', 'readout at keyframe 8 (packages): after each package and its digest; it was checked against the signed log on this machine (one short word)', { kind: 'svg', max: 16, lines: 1 }))}</span></div>`).join('')}</div>`,
    9: `<p class="cap">${t('Refused changes are never logged. A stopped swarm restores from its database: the seed, then the logged changes, in order.', W(9, 'the swarm document') + ': caption')}</p>` + kvRows([
      [t('restore', W(9, 'the swarm document') + ': row label (a noun or verb: what happens when a stopped swarm comes back)'), t('seed, then changes 1, 2, 3', W(9, 'the swarm document') + ': the order of the restore')],
    ]),
    10: `<div class="log st">${[['support', 'message_routed', 'triage → answer'], ['observer', 'message_routed', 'watch → report'], ['trading sim', 'restart', agentN(3, W(10, 'one event stream')), true], ['coding', 'output', agentN(2, W(10, 'one event stream'))]].map(([s, k, v, h]) => `<div class="ln${h ? ' hot' : ''}"><span class="k">${s}</span><span class="e2">${k}</span><span>${v}</span></div>`).join('')}</div>`,
  };
}
// readout headings, where a readout has one
export const roTitles = t => ({
  5: esc(t('events (illustration)', 'readout heading over the event log (keyframes 5 and 6); the events are simulated', { kind: 'svg', max: 43 })),
  6: esc(t('events (illustration)', 'readout heading over the event log (keyframes 5 and 6); the events are simulated', { kind: 'svg', max: 43 })),
  8: `${t('packages', 'readout heading at keyframe 8, before “· swarmidx (illustration)”: the list of packages')} · swarmidx ${ill(t)}`,
  10: `${t('one event stream', 'readout heading at keyframe 10, before “(illustration)”: every swarm’s events in one stream')} ${ill(t)}`,
});

// the legend under the hero drawing: the four marks the world is drawn with
export const legend = t => `<div class="ro legend" data-at="0"><span class="lg"><svg viewBox="0 0 14 14" aria-hidden="true"><circle cx="7" cy="7" r="5" class="ag-o"/><circle cx="7" cy="7" r="1.7" class="ag-i"/></svg>${esc(t('agent', 'legend under the hero drawing: the circle mark (one word)', { kind: 'svg', max: 14, lines: 1 }))}</span><span class="lg"><svg viewBox="0 0 14 14" aria-hidden="true"><rect x="2.5" y="2.5" width="9" height="9" class="ob"/></svg>${esc(t('object', 'legend under the hero drawing: the square mark (plain code on the graph; one word)', { kind: 'svg', max: 14, lines: 1 }))}</span><span class="lg"><svg viewBox="0 0 14 14" aria-hidden="true"><path d="M7 2.5L11.5 7 7 11.5 2.5 7z" class="sp"/></svg>${esc(t('supervisor', 'zoom drawing (canvas label): callout at the right of the process tree: the diamond above each agent; also the legend under the hero drawing', { kind: 'svg', max: 15, lines: 1 }))}</span><span class="lg"><svg viewBox="0 0 24 14" aria-hidden="true"><path d="M1 7H23" class="e"/><path d="M9 7H16" class="pu"/></svg>${esc(t('message on a declared path', 'legend under the hero drawing: a line with a short bright dash moving along it', { kind: 'svg', max: 30, lines: 1 }))}</span></div>`;

// ---------- story steps: [headline, paragraphs, example line, keyframes shown while the step is read] ----------
const GH = `<svg viewBox="0 0 16 16" aria-hidden="true"><path fill="currentColor" d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"/></svg>`;
export const ctas = (t, w) => `<div class="ctas"><a class="btn btn-p" href="/docs/">${t('Read the docs', `${w}: primary button`)}</a><a class="btn btn-s" href="https://github.com/genlayerlabs/genswarms">${GH}${t('View on GitHub', `${w}: secondary link`)}</a></div>`;

export const STEPS = [
  { hero: true, k: [0] },
  { h: 'Your agents need more than models and prompts.', p: ['One agent is easy. Many agents working together need somewhere to run, rules for who talks to whom, and a way back when one fails.'], k: [2, 3] },
  { h: 'Think of it as an operating system.', p: ['An operating system runs programs it didn’t write. GenSwarms does that for agents: it starts them, isolates them, routes their messages and restarts them when they fail.'], k: [4] },
  { h: 'Every agent is a process.', p: ['Each one runs in its own sandbox, under its own supervisor. If one crashes, it restarts and the others keep working. You set its role, its model and where it runs separately.'], k: [5] },
  { h: 'Agents talk only along declared paths.', p: ['You draw the graph. Every message is checked against it, and anything off the graph is dropped.'], ex: 'From here the drawings follow one swarm: a support team that answers customers on Telegram.', k: [6] },
  { h: 'Not everything needs a model.', p: ['Objects are plain code on the same graph: a Telegram gateway, a scheduler, a budget for model spend. They do the same thing every time.'], k: [7] },
  { h: 'Install what your agents need.', p: ['Telegram, WhatsApp and email connectors, a browser, a scheduler: signed packages from the swarmidx index, verified before they load.'], k: [8] },
  { h: 'A swarm is a document.', p: ['Its definition is data, and every change is logged. A bad change is refused before it runs; a stopped swarm comes back from its database.'], k: [9] },
  { last: true, k: [10] },
];

// the hero's headline and facts (the share card reuses them)
export const heroH1 = t => t('The operating system for AI&nbsp;workforces.', 'story step 1: the page headline (h1; also the share image). &nbsp; keeps two words together');
export const facts = t => [
  [t('license', 'hero facts row: small label over “Open source, MIT” (lower case)'), t('Open source, MIT', 'hero facts row: the license (also on the share image)')],
  [t('version', 'hero facts row: small label over “0.2.0” (lower case)'), '0.2.0'],
  [t('runtime', 'hero facts row: small label over “Elixir / OTP”, what GenSwarms runs on (lower case)'), 'Elixir / OTP'],
];
export const triad = t => [
  t('Models provide intelligence.', 'story step 9: closing triad, line 1 of 3 (display type, one short sentence; also on the share image)'),
  t('Agents perform work.', 'story step 9: closing triad, line 2 of 3'),
  t('GenSwarms runs the organization.', 'story step 9: closing triad, line 3 of 3'),
];

// "How it works." — a spec sheet: label + one line (copy deck v2, as set in the v4 design: capitalized, full stops;
// claims ledger: spec §4.2). A line of names only (Drivers) is the same in every language and not catalogued.
export const OS = [
  ['Processes', 'Every agent a supervised OTP process: role, model and backend set separately.'],
  ['Isolation', 'bwrap, Docker or Apple container, per agent.'],
  ['Network', 'Isolated agents reach their model endpoint only.'],
  ['Messages', 'Only along declared paths, checked each hop.'],
  ['Services', 'Objects: deterministic code on the same graph.'],
  ['Drivers', 'Local, Tmux, Docker, Apple container, SSH, Bwrap, Mock.'],
  ['Packages', 'gsp and swarmidx: signed, content-addressed, checked on your machine.'],
  ['State', 'A seed plus a log of changes. Bad changes refused. Restore from the database.'],
  ['Control', 'REST, WebSocket, CLI, and a skill file for your coding agent.'],
  ['Events', 'Every message, crash and restart, live.'],
];

export const SEC = {
  yes: ['A crash restarts one agent, not the swarm.', 'Messages follow declared paths only.', 'Bad configurations and changes are refused before they run.', 'Packages are verified against a signed log.'],
  not: ['One operator token, no per-user roles.', 'At-least-once delivery, not exactly once.', 'Spend budgets come as a package, not in the core.', 'Updating a package restarts the agent; no live swap yet.', '100 agents per swarm by default (configurable).'],
};

// the close: what it is used for today (copy deck v2)
export const CLOSE = 'In use today for chat assistants, coding agents, trading simulations and swarms that watch other swarms.';

// Competitor cells are sourced in design/comparison-sources.md (accessed 2026-09-25).
export const CMP = [
  ['What it is', 'A runtime that runs each agent as a supervised process', 'Orchestration framework and runtime for stateful agents; LangSmith Deployment hosts them', 'Open-source framework for agent crews and flows; AMP deploys them', 'Multi-agent framework, now in maintenance mode; Microsoft Agent Framework succeeds it'],
  ['Where agents run', 'Each in its own supervised process: local, sandbox, container or SSH', 'In your Python or JS process, or on LangSmith Deployment servers', 'In your Python process, or on CrewAI AMP managed infrastructure', 'In your process, or across workers via its experimental distributed runtime'],
  ['What a crash affects', 'The agent that crashed. Its supervisor restarts it', 'The run; checkpoints let it resume, and nodes can retry', 'The run; agents retry errors, and flows can persist and resume', 'Your code handles it; team state can be saved and reloaded'],
];
