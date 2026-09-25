// ---------- page content ----------
// Copy follows design/2026-09-25-copy-deck-v2.md. `aria` is each figure's alt text; `note` is the
// small label kept under the simulated figures (spec §4: simulated motion is labelled).
export const STAGES = [
  { aria: 'A single agent with its model, prompt and tools.' },
  { aria: 'Twelve agents joined by hand-made connections.' },
  { aria: 'The agents in a grid under GenSwarms, the operating system layer, beneath the organization.' },
  { aria: 'Each agent inside its own boundary under a GenSwarms supervisor; one agent crashes and restarts while the others keep running.' },
  { aria: 'A support swarm: a Telegram object and triage, research and answer agents on declared paths; a message from research to Telegram is off the graph and dropped.', note: 'illustration' },
  { aria: 'The same swarm with its objects drawn as squares and its agents as circles: Telegram, a cron scheduler, a model-spend budget and a browser.', note: 'illustration' },
  { aria: 'Each object comes from a signed package in the swarmidx index, verified before it loads.', note: 'illustration' },
  { aria: 'The swarm as a document: a seed of agents, objects and edges, and a log of changes in which a bad change is refused.', note: 'illustration' },
  { aria: 'GenSwarms on top, several swarms of agents in the middle, models underneath.' },
];

export const CROP = {
  L: ['0 84 800 374', '0 30 800 600', '0 70 800 500', '0 70 800 500', '0 195 800 410', '0 75 800 480', '0 75 800 540', '0 100 800 325', '0 70 800 520'],
  P: ['12 108 376 428', '12 30 376 570', '12 85 376 460', '12 85 376 520', '12 20 376 555', '12 20 376 505', '12 20 376 640', '12 10 376 360', '12 10 376 560'],
};

export const STEPS = [
  `<div class="copy hero-copy">
    <h1>The operating system for AI&nbsp;workforces.</h1>
    <p class="lead">Deploy, coordinate and control thousands of AI agents across your organization.</p>
    <div class="ctas"><a class="btn btn-primary" href="/docs/">Read the docs</a><a class="btn btn-ghost" href="https://github.com/genlayerlabs/genswarms">View on GitHub</a></div>
    <p class="meta">Open source, MIT. Version 0.2.0.</p>
  </div>`,
  `<div class="copy">
    <h2>Your agents need more than models and prompts.</h2>
    <p>One agent is easy. Many agents working together need somewhere to run, rules for who talks to whom, and a way back when one fails.</p>
  </div>`,
  `<div class="copy">
    <h2>Think of it as an operating system.</h2>
    <p>An operating system runs programs it didn’t write. GenSwarms does that for agents: it starts them, isolates them, routes their messages and restarts them when they fail.</p>
  </div>`,
  `<div class="copy">
    <h2>Every agent is a process.</h2>
    <p>Each one runs in its own sandbox, under its own supervisor. If one crashes, it restarts and the others keep working. You set its role, its model and where it runs separately.</p>
  </div>`,
  `<div class="copy">
    <h2>Agents talk only along declared paths.</h2>
    <p>You draw the graph. Every message is checked against it, and anything off the graph is dropped.</p>
    <p class="ex">From here the drawings follow one swarm: a support team that answers customers on Telegram.</p>
  </div>`,
  `<div class="copy">
    <h2>Not everything needs a model.</h2>
    <p>Objects are plain code on the same graph: a Telegram gateway, a scheduler, a budget for model spend. They do the same thing every time.</p>
  </div>`,
  `<div class="copy">
    <h2>Install what your agents need.</h2>
    <p>Telegram, WhatsApp and email connectors, a browser, a scheduler: signed packages from the swarmidx index, verified before they load.</p>
  </div>`,
  `<div class="copy">
    <h2>A swarm is a document.</h2>
    <p>Its definition is data, and every change is logged. A bad change is refused before it runs; a stopped swarm comes back from its database.</p>
  </div>`,
  `<div class="copy">
    <h2>One control layer for your AI organization.</h2>
    <p>Watch every message, crash and restart as it happens. Drive it by API or CLI, or hand it to your coding agent.</p>
    <p class="triad"><span>Models provide intelligence.</span> <span>Agents perform work.</span> <span>GenSwarms runs the organization.</span></p>
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
