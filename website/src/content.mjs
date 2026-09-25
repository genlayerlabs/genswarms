import { TEAMS } from './figures.mjs';

// ---------- page content ----------
export const STAGES = [
  { cap: 'One agent: a model, a prompt, some tools.', aria: 'A single agent connected to a model, a prompt and its tools.' },
  { cap: 'More agents, each built on its own and wired by hand.', aria: 'Twelve agents scattered, joined by ad-hoc hand-made connections.' },
  { cap: 'A coordination layer between the agents and the organization.', aria: 'The agents arranged in a grid beneath a GenSwarms coordination layer, which sits beneath the organization.' },
  { cap: 'Each agent a supervised process inside its own boundary.', aria: 'Each agent enclosed by a boundary, with a supervisor on the GenSwarms layer.' },
  { cap: 'A customer-operations team on a declared topology.', aria: 'A request flows from classifier to account lookup to investigator, then to billing or technical support, then to a verifier and out as a reply. The verifier can escalate to a human.' },
  { cap: 'The investigator crashes; its supervisor restarts it.', aria: 'The investigator agent crashes and its supervisor restarts it while the request continues through technical support. An event stream lists message, crash, restart, message.' },
  { cap: 'An exceptional case waits for a person.', aria: 'The verifier is blocked waiting on human input; the case goes to a human. The event stream shows agent_blocked.' },
  { cap: 'Seven teams under one control layer.', aria: 'Seven teams: customer operations, software engineering, sales, finance, research, security and network operations, all connected to one GenSwarms control layer.' },
  { cap: 'GenSwarms above the teams, models underneath.', aria: 'The GenSwarms control layer on top, seven teams of agents in the middle, and a row of models underneath.' },
];

export const CROP = {
  L: ['0 84 800 374', '0 30 800 600', '0 70 800 500', '0 70 800 500', '0 110 800 380', '0 30 800 530', '0 30 800 470', '0 70 800 420', '0 70 800 520'],
  P: ['0 108 400 428', '0 30 400 570', '0 85 400 460', '0 85 400 520', '0 15 400 530', '0 15 400 680', '0 15 400 652', '0 10 400 565', '0 10 400 640'],
};

export const STEPS = [
  `<div class="copy hero-copy">
    <h1>The operating system for AI&nbsp;workforces.</h1>
    <p class="lead">Deploy, coordinate and control thousands of AI agents across your organization.</p>
    <p>GenSwarms gives you one system to manage how agents work together: their roles, tools, boundaries, communication, workflows and supervision.</p>
    <p class="pull">Instead of building isolated agents, build an AI&nbsp;workforce.</p>
    <div class="ctas"><a class="btn btn-primary" href="/docs/">Read the docs</a><a class="btn btn-ghost" href="https://github.com/genlayerlabs/genswarms">View on GitHub</a></div>
    <p class="meta">Open source under the MIT license. Version 0.2.0, built on Elixir/OTP.</p>
    <a class="scroll-cue" href="#s1">Scroll to see how it grows</a>
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
    <p>GenSwarms provides the coordination layer between individual agents and the organization they operate inside.</p>
  </div>`,
  `<div class="copy">
    <h2>Think of it as an operating system.</h2>
    <p>A computer operating system manages the processes, resources and permissions behind the applications you use. GenSwarms does the same for agents. It determines:</p>
    <ul class="determines">
      <li>which agents exist and what their roles are</li>
      <li>what tools, data and systems each agent can access</li>
      <li>how work is delegated between agents</li>
      <li>how agents communicate</li>
      <li>how work is checked and escalated</li>
      <li>what happens when an agent fails</li>
      <li>how humans observe, intervene and control the system</li>
    </ul>
  </div>`,
  `<div class="copy">
    <h2>From individual agents to autonomous teams.</h2>
    <p class="big">A customer-service agent can answer a question.</p>
    <p>A GenSwarms customer-service team can classify the request, retrieve account information, investigate the problem, coordinate with billing or technical support, verify the proposed resolution and escalate exceptional cases.</p>
    <p class="note">Each role is an agent. The arrows are a declared topology: the only paths a message can take.</p>
  </div>`,
  `<div class="copy">
    <h2>When an agent fails, the team keeps working.</h2>
    <p>Every agent runs as its own supervised process. If the investigator crashes, only the investigator goes down. Its supervisor starts it again, the rest of the team keeps running, and both the crash and the restart appear on the event stream.</p>
  </div>`,
  `<div class="copy">
    <h2>Exceptional cases reach a person.</h2>
    <p>When a case is not one the team should settle alone, the verifier stops and waits for human input. The event stream reports it as <code>agent_blocked</code>. An operator attaches to the agent’s session, answers, and the work continues.</p>
  </div>`,
  `<div class="copy">
    <p class="big across">The same architecture can coordinate agents across</p>
    <ul class="teams">${TEAMS.map(t => `<li>${t}</li>`).join('')}</ul>
  </div>`,
  `<div class="copy">
    <h2>One control layer for your AI organization.</h2>
    <p>Your agents can use different models, tools and infrastructure. GenSwarms sits above them.</p>
    <p class="triad"><span>Models provide intelligence.</span> <span>Agents perform work.</span> <span>GenSwarms runs the organization.</span></p>
  </div>`,
];

export const OS = [
  ['Processes', 'Every agent and object runs as a supervised OTP process; agent groups scale up and down while the swarm runs.'],
  ['Isolation', 'Per-agent sandbox: bwrap namespaces with a copy-on-write root and seccomp, or Docker / Apple container.'],
  ['Communication', 'A declared topology is the only way messages move; every hop is checked against it.'],
  ['Boot', 'The IR gate checks the whole configuration before anything starts and refuses a bad one.'],
  ['Recovery', 'Crashed agents restart under supervision; a swarm can be restored from its database.'],
  ['Drivers', '7 backends: Local, Tmux (Codex, Claude Code and OpenCode sessions), Docker, Apple container, SSH, Bwrap, Mock.'],
  ['Network', 'With <code>network: :isolated</code> an agent reaches its model endpoint and nothing else (bwrap and Docker).'],
  ['Packages', '<code>gsp</code> and the <code>swarmidx</code> notary: signed, verified packages with a transparency log.'],
  ['Observability', 'One event stream: every message, crash, restart and output, live over WebSocket.'],
  ['Control', 'A REST API, a WebSocket and a CLI.'],
];

export const GLY = {
  Processes: '<circle cx="16" cy="16" r="9" class="gl-r"/><circle cx="16" cy="16" r="4.5" class="gl-f"/>',
  Isolation: '<rect x="4.5" y="4.5" width="23" height="23" rx="6" class="gl-d"/><circle cx="16" cy="16" r="4.5" class="gl-f"/>',
  Communication: '<circle cx="6" cy="16" r="3.5" class="gl-f"/><circle cx="27" cy="16" r="3.5" class="gl-f"/><path d="M10 16H20" class="gl-s"/><path d="M23 16l-5-3v6z" class="gl-f"/>',
  Boot: '<path d="M21 5V27" class="gl-s gl-w"/><path d="M4 16H14" class="gl-s"/><path d="M17 16l-5-3v6z" class="gl-f"/>',
  Recovery: '<path d="M24.5 12A9 9 0 1 0 25 17" class="gl-s"/><path d="M25.5 6.5v6h-6" class="gl-s"/><circle cx="16" cy="16" r="3.5" class="gl-f"/>',
  Drivers: '<rect x="4" y="9" width="7" height="14" rx="2" class="gl-s"/><rect x="12.5" y="9" width="7" height="14" rx="2" class="gl-s"/><rect x="21" y="9" width="7" height="14" rx="2" class="gl-s"/>',
  Network: '<rect x="3.5" y="8.5" width="15" height="15" rx="4" class="gl-d"/><circle cx="11" cy="16" r="3" class="gl-f"/><path d="M18.5 16H23" class="gl-s"/><path d="M27 11.5l3.9 2.25v4.5L27 20.5l-3.9-2.25v-4.5z" class="gl-s"/>',
  Packages: '<rect x="5" y="5" width="22" height="22" rx="4" class="gl-s"/><path d="M10.5 16.5l3.8 3.8 7.2-7.8" class="gl-s"/>',
  Observability: '<path d="M5 9H27M5 16H21M5 23H24" class="gl-s"/>',
  Control: '<rect x="3" y="11" width="26" height="10" rx="5" class="gl-f"/>',
};
// Competitor cells are sourced in design/comparison-sources.md (accessed 2026-09-25).
export const CMP = [
  ['What it is', 'A runtime that runs each agent as a supervised process', 'Orchestration framework and runtime for stateful agents; LangSmith Deployment hosts them', 'Open-source framework for agent crews and flows; AMP deploys them', 'Multi-agent framework, now in maintenance mode; Microsoft Agent Framework succeeds it'],
  ['Where agents run', 'Each in its own supervised process: local, sandbox, container or SSH', 'In your Python or JS process, or on LangSmith Deployment servers', 'In your Python process, or on CrewAI AMP managed infrastructure', 'In your process, or across workers via its experimental distributed runtime'],
  ['What a crash affects', 'The agent that crashed. Its supervisor restarts it', 'The run; checkpoints let it resume, and nodes can retry', 'The run; agents retry errors, and flows can persist and resume', 'Your code handles it; team state can be saved and reloaded'],
  ['Control surface', 'REST API, WebSocket event stream, CLI', 'Python/JS API; Agent Server REST API and streaming when deployed', 'Python API; AMP adds a REST API, traces and logs', 'Python and .NET APIs; AutoGen Studio GUI for prototyping'],
];
