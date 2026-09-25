# genswarms.com landing page: "The operating system for AI workforces"

Design spec · 2026-09-25 · status: for owner review

## 1. Goal

Replace the current landing page (`website/index.html`) with a leveled-up page that positions GenSwarms as
**the operating system for AI workforces**, keeps the visual family of today's site, and fixes the defects found in
the 2026-09-25 review. The page must be ready for translation into es, ko, zh-Hans, ru and tr (done afterwards
through the multilingual playbook, not in this spec).

**Primary reader:** a technical lead evaluating a platform for running many agents. They need the vision in seconds
and then proof they can check.

**Success:**
- A cold reader understands "operating system for AI workforces" from the first screen and can say what GenSwarms does
  after one scroll.
- Every concrete sentence, label and number is true of v0.2.0 (see §4).
- Works without JavaScript, with reduced motion, and on a 360px phone as a designed experience.
- Lighthouse: accessibility, best practices, SEO 100; performance ≥ 90 on mobile.

**Only GenSwarms.** No GenLayer, unhardcoded or "stack" narrative.

## 2. Chosen direction

Direction 1, "Cinematic story", chosen by the owner from three prototypes.
Reference prototype (throwaway, not committed): `scratchpad/gs-directions-2/1-cinematic.html`, with its figure
generator in `scratchpad/gs1-work/gen.cjs` (session scratchpad of the design conversation). Implementation rebuilds it
properly; it does not ship the prototype file.

One ink drawing stays in view beside the story and grows figure by figure as the reader scrolls. After the story, the
proof sections switch to a calmer, precise register on a deeper sand; the close sits on night.

## 3. Narrative and page structure

Owner's copy, kept in structure and voice. Edits are limited to the honesty rules in §4 ("permissions" becomes
"boundaries"; "and share context" dropped from the list).

| # | Section (copy) | Figure |
|---|---|---|
| 1 | **The operating system for AI workforces.** Deploy, coordinate and control thousands of AI agents across your organization. GenSwarms gives you one system to manage how agents work together: their roles, tools, boundaries, communication, workflows and supervision. **Instead of building isolated agents, build an AI workforce.** CTAs: Read the docs · View on GitHub. Facts line: open source (MIT) · v0.2.0 · built on Elixir/OTP. | Fig. 1: the opening frame already reads "workforce": a single agent (model, prompt, tools) set against the faint outline of the organization it will join. |
| 2 | **Your agents need more than models and prompts.** As companies deploy more agents, the hard problem changes. It is no longer: **How do I build an agent?** It becomes: **How do I run thousands of them together?** GenSwarms provides the coordination layer between individual agents and the organization they operate inside. | Fig. 2: many agents, each wired by hand (tangled dotted links). Fig. 3: a coordination layer between the agents and the organization. |
| 3 | **Think of it as an operating system.** A computer operating system manages the processes, resources and permissions behind the applications you use. GenSwarms does the same for agents. It determines: which agents exist and what their roles are · what tools, data and systems each agent can access · how work is delegated between agents · how agents communicate · how work is checked and escalated · what happens when an agent fails · how humans observe, intervene and control the system. | Fig. 4: each agent a supervised process inside its own boundary. |
| 4 | **From individual agents to autonomous teams.** A customer-service agent can answer a question. A GenSwarms customer-service team can classify the request, retrieve account information, investigate the problem, coordinate with billing or technical support, verify the proposed resolution and escalate exceptional cases. | Fig. 5: the customer-operations team on a declared topology (request → classifier → account lookup → investigator → billing / technical support → verifier → reply; human beside the verifier). |
| 4a | Caption step (added, owner to confirm): **When an agent fails, the team keeps working.** | Fig. 6 (signature): a request token moves along the edges; the investigator crashes (red), its supervisor line draws in, it restarts (sage) and the request continues; an event stream logs `message`, `crash`, `restart`. Labelled "illustration". |
| 4b | Caption step (added, owner to confirm): **Exceptional cases reach a person.** The verifier stops and waits for human input; the event stream reports it as `agent_blocked`; an operator attaches to the agent's session, answers, and the work continues. | Fig. 7: `agent_blocked` at the verifier, the human line lights. |
| 5 | **The same architecture can coordinate agents across:** Customer operations · Software engineering · Sales · Finance · Research · Security · Network operations. | Fig. 8: the team shrinks into one of seven clusters (team shapes illustrative) under one GenSwarms band. |
| 6 | **One control layer for your AI organization.** Your agents can use different models, tools and infrastructure. GenSwarms sits above them. **Models provide intelligence. Agents perform work. GenSwarms runs the organization.** | Fig. 9: GenSwarms above the teams, models underneath. |
| 7 | **How it works, as an operating system.** The analogy is not a metaphor stretched over a library: each part is a mechanism that ships in v0.2.0. Ten rows: processes · isolation · communication · boot · recovery · drivers · network · packages · observability · control (content in §4.2). | — |
| 8 | **A runtime, not a library.** (added, owner to confirm) Comparison with LangGraph, CrewAI, AutoGen (§5). | — |
| 9 | **Security and operations.** What it guarantees / what it doesn't do yet (§4.3). | — |
| 10 | **Start with one team. Scale to thousands of agents.** Build your first swarm, connect your existing systems and expand from individual workflows into an organization-wide AI workforce. CTAs: Read the docs · View on GitHub. Secondary: "Or hand it to your agent" prompt pointing at `https://genswarms.com/skill.md` with a copy button. | — (night band) |
| — | Footer: brand, one-line description, links (Docs, GitHub, License, skill.md, llms.txt), © GenLayer Labs · MIT. | — |

Nav: How it works · Compare · Security · Docs · GitHub. The version appears once, in the hero facts line (no badge in
the nav, which is what broke the mobile header).

## 4. Honesty rules and claims ledger

Vision lives in the headlines ("thousands", "across your organization", "AI workforce"). Every concrete sentence,
label, figure and number describes what ships in v0.2.0. No invented customers, logos, testimonials, benchmarks,
uptime or counts. Simulated UI (event streams, figure animations) is labelled "illustration" in small text.

### 4.1 Words we don't use
"memory" (no memory feature); "permissions"/"RBAC"/"per-user" (one operator token); "approval workflow" (none built
in); "exactly once" (delivery is at least once); "10k agents" or any agent-count benchmark (default cap 100 agents per
swarm, configurable); "sandboxed packages" (package code is trusted host code).

### 4.2 "How it works, as an operating system" (each row true of v0.2.0)
| OS concept | GenSwarms mechanism | Source |
|---|---|---|
| Processes | Every agent and object runs as a supervised OTP process; agent groups scale up and down while the swarm runs. | docs/architecture.md |
| Isolation | Per-agent sandbox: bwrap namespaces with a copy-on-write root and seccomp, or Docker / Apple container. | docs/backends.md, docs/containers.md |
| Communication | A declared topology is the only way messages move; every hop is checked against it. | docs/messaging.md |
| Boot | The IR gate checks the whole configuration before anything starts and refuses a bad one. | docs/intermediate-representation.md |
| Recovery | Crashed agents restart under supervision; a swarm can be restored from its database. | docs/architecture.md, `genswarms ir restore` |
| Drivers | 7 backends: Local, Tmux (Codex, Claude Code and OpenCode sessions), Docker, Apple container, SSH, Bwrap, Mock. | README.md |
| Network | With `network: :isolated` an agent reaches its model endpoint and nothing else (bwrap and Docker). | docs/security.md |
| Packages | `gsp` and the `swarmidx` notary: signed, verified packages with a transparency log. | genswarms-packages README |
| Observability | One event stream: every message, crash, restart and output, live over WebSocket. | docs/observability.md |
| Control | A REST API, a WebSocket and a CLI. | docs/rest-api.md, docs/cli.md |

### 4.3 Security and operations
**What it guarantees:** every agent is a separate supervised process and a crash restarts that agent, not the swarm ·
agents can run in their own sandbox · messages move only along the declared topology and every hop is checked · a bad
configuration is refused at boot · an isolated agent reaches its model endpoint and nothing else · packages are signed
and verified, with a transparency log · every message, crash, restart and output is on one live event stream.
**What it doesn't do yet:** one operator token (no per-user roles yet) · messages are delivered at least once, not
exactly once · no token or dollar caps in the core (budget packages exist) · swarms run up to 100 agents by default;
the limit is configurable.

### 4.4 Figure labels
Only real event kinds and real names: `message`, `crash`, `restart`, `output`, `scale`, `agent_blocked`; backends and
objects as they exist. Team shapes in Fig. 8 are illustrative and captioned so.

## 5. Comparison ("A runtime, not a library")
Columns: GenSwarms · LangGraph · CrewAI · AutoGen. Rows: What it is · Where agents run · What a crash affects ·
Control surface. Before launch every competitor cell is checked against that project's current official docs, with
the source URL and date recorded in `design/comparison-sources.md`. Cells stay neutral and factual; if a project
offers a hosted or deployment product (e.g. a platform tier), the cell says so rather than omitting it. No
disparaging language. The "Draft" stamp from the prototype is removed only when every cell has a source.

## 6. Visual system
Same family as today, leveled up.
- **Palette:** sand `#E9E0D2`, deeper sand `#DED3BF`, ink `#33301f`, secondary ink `#5f5946`, clay `#A84E36`
  (lighter clay `#D2704F` on night), night `#12110d`; sage `#8fa06f` = running, `#E0664A` = crashed. Clay is reserved
  for moving work, active states and failures in figures.
- **Type:** Bricolage Grotesque (display), Instrument Sans (text), JetBrains Mono (code and event data only). A
  stronger display scale than the prototype; body ≥ 16px; captions ≥ 13px.
- **Figures:** one drawing language: ink strokes on sand, rounded process boundaries, dotted = undeclared/manual,
  solid = declared path. Larger and more crafted than the prototype on wide screens (figure column uses the space);
  smooth morphs between consecutive figures instead of hard swaps.
- **Motion:** one signature sequence (Fig. 6–7) plus figure morphs tied to scroll. No fade-up on sections. Respect
  `prefers-reduced-motion` (static figures).
- **Avoid:** tracked uppercase eyebrows, pill badges, bordered chip buttons, numbering on non-sequences, arrows
  appended to every link.
- **Phones:** separate portrait layouts per figure (vertical team, two-column cluster tree), each figure sits with its
  own text; no pinned column. 16px gutters; tap targets ≥ 44px.

## 7. Architecture

```
website/
  src/
    index.template.html   page markup and all copy (English source for i18n)
    styles.css            page styles (inlined at build)
    story.js              scroll/figure controller (inlined at build)
    figures/fig-1.svg … fig-9.svg   one source per figure; text as <text> elements
    figures/fig-5-portrait.svg …    portrait variants where the layout differs
  build.mjs               Node ≥ 20, no dependencies: inlines CSS/JS/figures into website/index.html
  index.html              built output (committed; what Pages serves)
  404.html, llms.txt, robots.txt, sitemap.xml, favicon.svg, favicon-32.png, apple-touch-icon.png, og-image.png
```

- **One source per figure.** The same SVG serves the pinned animated figure and its static in-flow fallback (the
  prototype duplicated 18 drawings; target total HTML < 150 KB before compression).
- **No-JS baseline:** the built HTML shows every section with its static figure in flow. JavaScript upgrades to the
  pinned, animated story only when the viewport is ≥ 1000px wide and motion is allowed.
- **Translation-ready:** every visible string is in `index.template.html` or in figure `<text>` elements, never
  assembled in JS. Animation labels (event-stream lines) live in the markup as hidden-until-played elements, so the
  i18n extractor sees them. Later, the playbook's generator builds `/es/ /ko/ /zh/ /ru/ /tr/` from this template.
- **Deploy:** `.github/workflows/pages.yml` copies the whole `website/` folder except `website/src/` and build files,
  replacing today's hand-kept file list (which left the three icons out and made them 404). `skill.md`,
  `llms-full.txt` and the docs build stay as they are.

## 8. Other deliverables
- `website/llms.txt`: rewritten to the new positioning, 7 backends, v0.2.0.
- Structured data: `SoftwareApplication` with the new description and version; FAQPage only if visible FAQ content
  exists on the page (it won't in this design, so drop it).
- New `og-image.png` from the hero (1200×630), generated by a script from the built page.
- `sitemap.xml` `lastmod`; 404 page restyled to match.

## 9. Verification (all must pass before merge)
1. Layout audit at 320–1440px (12 widths): no horizontal overflow, no overlaps, no text < 12px, 44px tap targets on
   phones, no console errors or failed requests.
2. JavaScript disabled and `prefers-reduced-motion: reduce`: all copy and every static figure visible.
3. Lighthouse on the built page: accessibility, best practices, SEO 100; performance ≥ 90 (mobile).
4. Claims check: every concrete sentence in §3–4 traced to a doc or code path (table kept in the PR description).
5. Comparison: every cell sourced in `design/comparison-sources.md`.
6. Visual review of full-page screenshots at desktop and phone by the owner.

## 10. Out of scope
Translations (next step, via the playbook), search-engine registration, changes to the MkDocs docs site, product
changes.

## 11. For the owner to confirm
- Added headlines not in the original copy: "When an agent fails, the team keeps working.", "Exceptional cases reach
  a person.", "A runtime, not a library.", "How it works, as an operating system."
- "permissions" → "boundaries" in the hero sentence; list item "how agents communicate and share context" →
  "how agents communicate" (there is no shared-context feature).
