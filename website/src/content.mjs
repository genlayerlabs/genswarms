// ---------- page content ----------
// Copy follows design/2026-09-25-copy-deck.md. `aria` is each figure's alt text; `note` is the
// small label kept under the simulated figures (spec §4: simulated motion is labelled).
export const STAGES = [
  { aria: 'A single agent with its model, prompt and tools.' },
  { aria: 'Twelve agents joined by hand-made connections.' },
  { aria: 'The agents in a grid under a GenSwarms layer, beneath the organization.' },
  { aria: 'Each agent inside its own boundary, supervised from the GenSwarms layer.' },
  { aria: 'A customer-operations team where a request moves from classifier to account lookup, investigator, billing or technical support and verifier, with a path to a person.', note: 'illustration' },
  { aria: 'The investigator crashes and its supervisor restarts it while the request carries on.', note: 'illustration' },
  { aria: 'The verifier waits for a person and the event stream shows agent_blocked.', note: 'illustration' },
  { aria: 'Seven teams under one GenSwarms control layer, drawn as illustrative shapes.', note: 'team shapes are illustrative' },
  { aria: 'GenSwarms on top, teams of agents in the middle, models underneath.' },
];

export const CROP = {
  L: ['0 84 800 374', '0 30 800 600', '0 70 800 500', '0 70 800 500', '0 110 800 380', '0 30 800 530', '0 30 800 470', '0 70 800 420', '0 70 800 520'],
  P: ['12 108 376 428', '12 30 376 570', '12 85 376 460', '12 85 376 520', '12 15 376 530', '12 15 376 680', '12 15 376 652', '12 10 376 565', '12 10 376 640'],
};

export const STEPS = [
  `<div class="copy hero-copy">
    <h1>The operating system for AI&nbsp;workforces.</h1>
    <p class="lead">Deploy, coordinate and control thousands of AI agents across your organization.</p>
    <p class="ex">One example runs through the page: a customer who was charged twice.</p>
    <div class="ctas"><a class="btn btn-primary" href="/docs/">Read the docs</a><a class="btn btn-ghost" href="https://github.com/genlayerlabs/genswarms">View on GitHub</a></div>
    <p class="meta">Open source, MIT. Version 0.2.0.</p>
  </div>`,
  `<div class="copy">
    <h2>Your agents need more than models and prompts.</h2>
    <p class="big">As companies deploy more agents, the hard problem changes.</p>
  </div>`,
  `<div class="copy turn">
    <p class="turn-k">It is no longer:</p>
    <p class="turn-q old"><span class="strike">How do I build an agent?</span></p>
    <p class="turn-k">It becomes:</p>
    <p class="turn-q new">How do I run thousands of them together?</p>
    <p>GenSwarms is the layer in between.</p>
  </div>`,
  `<div class="copy">
    <h2>Think of it as an operating system.</h2>
    <p>An operating system decides what runs, what each program may touch and what happens when one fails. GenSwarms makes those decisions for agents:</p>
    <ul class="determines">
      <li>roles</li>
      <li>access to tools, data and systems</li>
      <li>who hands work to whom</li>
      <li>review and escalation</li>
      <li>recovery when an agent fails</li>
      <li>human oversight</li>
    </ul>
  </div>`,
  `<div class="copy">
    <h2>From individual agents to autonomous teams.</h2>
    <p>A customer-service agent can answer a question. A team can classify it, look up the account, investigate, bring in billing or technical support, verify the fix and escalate the hard cases.</p>
    <p class="ex">The charged-twice ticket enters at the classifier.</p>
  </div>`,
  `<div class="copy">
    <h2>When one fails, the rest keep working.</h2>
    <p>Each agent is its own supervised process. A crash restarts that agent; the ticket carries on.</p>
  </div>`,
  `<div class="copy">
    <h2>Hard cases reach a person.</h2>
    <p>The verifier stops and reports <code>agent_blocked</code>. Someone attaches to its session, answers, and the work resumes.</p>
  </div>`,
  `<div class="copy">
    <h2>The same architecture runs other teams.</h2>
    <p>Customer operations, software engineering, sales, finance, research, security, network operations.</p>
  </div>`,
  `<div class="copy">
    <h2>One control layer for your AI organization.</h2>
    <p>Agents can use different models, tools and infrastructure. GenSwarms sits above them.</p>
    <p class="triad"><span>Models provide intelligence.</span> <span>Agents perform work.</span> <span>GenSwarms runs the organization.</span></p>
  </div>`,
];

// "How it works." — a spec sheet: label + one line (claims ledger: spec §4.2).
export const OS = [
  ['Processes', 'every agent a supervised OTP process'],
  ['Isolation', 'bwrap, Docker or Apple container, per agent'],
  ['Messages', 'only along declared paths, checked each hop'],
  ['Boot', 'a bad configuration never starts'],
  ['Recovery', 'crashed agents restart; swarms restore from their database'],
  ['Backends', 'Local, Tmux, Docker, Apple container, SSH, Bwrap, Mock'],
  ['Network', 'isolated agents reach their model endpoint only'],
  ['Packages', 'signed and verified, with a transparency log'],
  ['Events', 'every message, crash and restart, live over WebSocket'],
  ['Control', 'REST, WebSocket, CLI'],
];

export const SEC = {
  yes: ['a crash restarts one agent, not the swarm', 'messages follow declared paths only', 'bad configurations are refused at boot', 'packages are verified against a signed log'],
  not: ['one operator token, no per-user roles', 'at-least-once delivery, not exactly once', 'no token or dollar caps in the core', '100 agents per swarm by default (configurable)'],
};

// Competitor cells are sourced in design/comparison-sources.md (accessed 2026-09-25).
export const CMP = [
  ['What it is', 'A runtime that runs each agent as a supervised process', 'Orchestration framework and runtime for stateful agents; LangSmith Deployment hosts them', 'Open-source framework for agent crews and flows; AMP deploys them', 'Multi-agent framework, now in maintenance mode; Microsoft Agent Framework succeeds it'],
  ['Where agents run', 'Each in its own supervised process: local, sandbox, container or SSH', 'In your Python or JS process, or on LangSmith Deployment servers', 'In your Python process, or on CrewAI AMP managed infrastructure', 'In your process, or across workers via its experimental distributed runtime'],
  ['What a crash affects', 'The agent that crashed. Its supervisor restarts it', 'The run; checkpoints let it resume, and nodes can retry', 'The run; agents retry errors, and flows can persist and resume', 'Your code handles it; team state can be saved and reloaded'],
];
