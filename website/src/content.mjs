// ---------- page content ----------
// Copy follows design/2026-09-25-copy-deck-v2.md. `aria` is each figure's alt text; `note` is the
// small label kept under the simulated figures (spec §4: simulated motion is labelled).
export const STAGES = [
  { aria: 'A single agent with its model, prompt and tools.' },
  { aria: 'Twelve agents joined by hand-made connections.' },
  { aria: 'The agents in a grid under GenSwarms, the operating system layer, beneath the organization.' },
  { aria: 'Each agent inside its own boundary under a GenSwarms supervisor; one agent crashes and restarts while the others keep running.' },
  { aria: 'A support swarm: a Telegram object and triage, research and answer agents on declared paths; a message from research to Telegram is off the graph and dropped.', note: 'illustration' },
  { aria: 'The same swarm with its objects drawn as squares and its agents as circles: Telegram, a cron scheduler, a browser, and a budget that answer and research call their model through.', note: 'illustration' },
  { aria: 'Each object comes from a signed package in the swarmidx index, verified before it loads.', note: 'illustration' },
  { aria: 'The swarm as a document: a seed of agents, objects and edges, a log of two changes, and a change over the 100-agent cap that is refused and never logged.', note: 'illustration' },
  { aria: 'GenSwarms on top, several swarms of agents in the middle, models underneath.' },
];

export const CROP = {
  L: ['0 84 800 374', '0 30 800 600', '0 70 800 500', '0 70 800 500', '0 195 800 456', '0 75 800 500', '0 75 800 580', '0 100 800 325', '0 70 800 520'],
  P: ['12 108 376 428', '12 30 376 570', '12 85 376 460', '12 85 376 520', '12 20 376 577', '12 20 376 505', '12 20 376 640', '12 10 376 360', '12 10 376 560'],
};

// Each step is rendered through t() (src/i18n.mjs): one catalogue entry per element that owns text, with its inline
// markup, so translators get whole sentences. `where` tells them where it shows.
const ctas = (t, w) => `<div class="ctas"><a class="btn btn-primary" href="/docs/">${t('Read the docs', `${w}: primary button`)}</a><a class="btn btn-ghost" href="https://github.com/genlayerlabs/genswarms">${t('View on GitHub', `${w}: secondary link`)}</a></div>`;
const step = (n, t, h, ps) => `<div class="copy">
    <h2>${t(h, `story step ${n}: headline (h2, display size; also names rail button ${n})`)}</h2>
${ps.map(([cls, p], i) => `    <p${cls ? ` class="${cls}"` : ''}>${t(p, `story step ${n}: ${cls === 'ex' ? 'italic example line' : `paragraph ${i + 1}`}`)}</p>`).join('\n')}
  </div>`;
export const STEPS = [
  t => `<div class="copy hero-copy">
    <h1>${t('The operating system for AI&nbsp;workforces.', 'story step 1: the page headline (h1; also rail button 1 and the share image). &nbsp; keeps two words together')}</h1>
    <p class="lead">${t('Deploy, coordinate and control thousands of AI agents across your organization.', 'story step 1: lead paragraph under the headline')}</p>
    ${ctas(t, 'story step 1')}
    <p class="meta">${t('Open source, MIT. Version 0.2.0.', 'story step 1: small line under the buttons')}</p>
  </div>`,
  t => step(2, t, 'Your agents need more than models and prompts.', [['', 'One agent is easy. Many agents working together need somewhere to run, rules for who talks to whom, and a way back when one fails.']]),
  t => step(3, t, 'Think of it as an operating system.', [['', 'An operating system runs programs it didn’t write. GenSwarms does that for agents: it starts them, isolates them, routes their messages and restarts them when they fail.']]),
  t => step(4, t, 'Every agent is a process.', [['', 'Each one runs in its own sandbox, under its own supervisor. If one crashes, it restarts and the others keep working. You set its role, its model and where it runs separately.']]),
  t => step(5, t, 'Agents talk only along declared paths.', [['', 'You draw the graph. Every message is checked against it, and anything off the graph is dropped.'], ['ex', 'From here the drawings follow one swarm: a support team that answers customers on Telegram.']]),
  t => step(6, t, 'Not everything needs a model.', [['', 'Objects are plain code on the same graph: a Telegram gateway, a scheduler, a budget for model spend. They do the same thing every time.']]),
  t => step(7, t, 'Install what your agents need.', [['', 'Telegram, WhatsApp and email connectors, a browser, a scheduler: signed packages from the swarmidx index, verified before they load.']]),
  t => step(8, t, 'A swarm is a document.', [['', 'Its definition is data, and every change is logged. A bad change is refused before it runs; a stopped swarm comes back from its database.']]),
  t => `<div class="copy">
    <h2>${t('One control layer for your AI organization.', 'story step 9: headline (h2, display size; also names rail button 9)')}</h2>
    <p>${t('Watch every message, crash and restart as it happens. Drive it by API or CLI, or hand it to your coding agent.', 'story step 9: paragraph 1')}</p>
    <p class="triad"><span>${t('Models provide intelligence.', 'story step 9: closing triad, line 1 of 3 (large display type, one short sentence)')}</span> <span>${t('Agents perform work.', 'story step 9: closing triad, line 2 of 3')}</span> <span>${t('GenSwarms runs the organization.', 'story step 9: closing triad, line 3 of 3')}</span></p>
  </div>`,
];

// "How it works." — a spec sheet: label + one line (copy deck v2; claims ledger: spec §4.2).
export const OS = [
  ['Processes', 'every agent a supervised OTP process: role, model and backend set separately'],
  ['Isolation', 'bwrap, Docker or Apple container, per agent'],
  ['Network', 'isolated agents reach their model endpoint only'],
  ['Messages', 'only along declared paths, checked each hop'],
  ['Services', 'objects: deterministic code on the same graph'],
  ['Drivers', 'Local, Tmux, Docker, Apple container, SSH, Bwrap, Mock'],
  ['Packages', 'gsp and swarmidx: signed, content-addressed, checked on your machine'],
  ['State', 'a seed plus a log of changes; bad changes refused; restore from the database'],
  ['Control', 'REST, WebSocket, CLI, and a skill file for your coding agent'],
  ['Events', 'every message, crash and restart, live'],
];

export const SEC = {
  yes: ['a crash restarts one agent, not the swarm', 'messages follow declared paths only', 'bad configurations and changes are refused before they run', 'packages are verified against a signed log'],
  not: ['one operator token, no per-user roles', 'at-least-once delivery, not exactly once', 'spend budgets come as a package, not in the core', 'updating a package restarts the agent; no live swap yet', '100 agents per swarm by default (configurable)'],
};

// the close: what it is used for today (copy deck v2, replaces the v1 line)
export const CLOSE = 'In use today for chat assistants, coding agents, trading simulations and swarms that watch other swarms.';

// Competitor cells are sourced in design/comparison-sources.md (accessed 2026-09-25).
export const CMP = [
  ['What it is', 'A runtime that runs each agent as a supervised process', 'Orchestration framework and runtime for stateful agents; LangSmith Deployment hosts them', 'Open-source framework for agent crews and flows; AMP deploys them', 'Multi-agent framework, now in maintenance mode; Microsoft Agent Framework succeeds it'],
  ['Where agents run', 'Each in its own supervised process: local, sandbox, container or SSH', 'In your Python or JS process, or on LangSmith Deployment servers', 'In your Python process, or on CrewAI AMP managed infrastructure', 'In your process, or across workers via its experimental distributed runtime'],
  ['What a crash affects', 'The agent that crashed. Its supervisor restarts it', 'The run; checkpoints let it resume, and nodes can retry', 'The run; agents retry errors, and flows can persist and resume', 'Your code handles it; team state can be saved and reloaded'],
];
