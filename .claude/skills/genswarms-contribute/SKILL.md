---
name: genswarms-contribute
description: >-
  Develop and extend genswarms — the Elixir/OTP swarm orchestrator. Load this
  before adding a backend or an object, or touching the IR control plane, the
  OTP supervision tree, the messaging layer, the daemon/SQLite coordination, or
  the Phoenix API. Orients and points into AGENTS.md, CLAUDE.md and docs/. To
  merely operate a swarm, use genswarms-use.
---

# Contributing to genswarms

genswarms orchestrates subzeroclaw agents under OTP supervision. Read `AGENTS.md`
(the coding-agent contract) and `CLAUDE.md` (the codebase quick reference) first —
this skill orients the two most common extensions (a backend, an object) and the
invariants around them; `docs/architecture.md` and `docs/intermediate-representation.md`
are the deep references.

## The shape of the system

- **OTP tree** (`lib/genswarms/application.ex`): one `Genswarms.Supervisor` over
  `Registry` (`Genswarms.AgentRegistry`), `Router` (inter-agent routing),
  `SkillsManager`, `LogStore`, a `DynamicSupervisor` (`Genswarms.AgentSupervisor`)
  hosting `AgentServer {swarm, agent}` and `ObjectServer {swarm, object}`, and
  `SwarmManager` (lifecycle GenServer). Agents and objects share one supervisor
  and registry keyed `{swarm_name, name}`. The diagrams in the README/CLAUDE are
  simplified; `docs/architecture.md` states the real tree — trust it.
- **Daemon + SQLite:** swarms run as independent OS processes; the CLI/API and
  daemons coordinate through `.genswarms/swarms.db` (`swarms`, `events`, `tasks`),
  daemons polling the task queue (~500ms).

## The IR control plane (the gate everything passes)

`Genswarms.IR.*` (façade `Genswarms.IR`) is the validated control plane:
- **`swarm.state`** — the pure structural model (agents/objects/topology/options),
  with invariants: unique names, every topology endpoint exists, the data/code
  slot typing holds.
- **`swarm.overlay`** — an ordered log of mutation ops (`add_agent`,
  `scale_agent_group`, `add/remove_topology_edges`, `bump_package`, `set_options`,
  `update_config`, …) folded over a seed state.
- **`Genswarms.IR.Gate`** — **fail-closed** validation. Every swarm start and
  every dynamic mutation must translate to a valid `swarm.state`/op; unknown ops
  fail (no silent ignore, **no atom minting**), host-escape keys are rejected, and
  a per-swarm agent cap (default 100) is enforced. **Do not route mutations around
  the Gate** — it is the security boundary of the control plane.

## Add a backend

A backend is where an agent process runs. Implement
`@behaviour Genswarms.Backends.BackendBehaviour`
(`lib/genswarms/backends/backend_behaviour.ex`) — the callbacks are the source of
truth (`start/2`, `stop/1`, `send_input/2`, `deploy_skills/2`, `health_check/1`,
`backend_type/0`, optional `handle_output/2`). Then:
1. Add a `backend_module/1` clause in `lib/genswarms/config/swarm_config.ex` that
   maps your `:name` (and `{:name, opts}` tuples) to the module.
2. Whitelist any new config keys in `@backend_config_keys` (same file) and handle
   them in the REST agent-creation path.
3. If the backend supports untrusted content, wire `network: :isolated` (the
   existing modes: bwrap `:host_socat`, docker `:docker_sidecar`; Apple fails
   closed).
4. Tests (a Mock-backed test where possible) + `docs/backends.md`.

A new backend is not a one-liner — the concern is spread across the codebase
(shotgun surgery): beyond `backend_module/1`, expect to touch `backend_config/1`,
`determine_mode/1` (`lib/genswarms/objects/object_server.ex`), the `@type backend`,
the IR round-trip (`FromConfig`/`ToConfig`), and the CLI/status + web controllers.
`AGENTS.md` (§ Configuration, the backend argument builders) enumerates the full
set — read it before starting, and budget for the smear.

## Add an object

An object is a deterministic, non-agentic node in the topology. Implement
`@behaviour Genswarms.Objects.ObjectHandler`
(`lib/genswarms/objects/object_handler.ex`): `init/1`, `handle_message/3`,
`interface/0` (optional `handle_info/2`, `terminate/2`). `handle_message/3`
returns `{:reply|:send|:broadcast|:noreply|:send_many|:multi, …, state}`; the
`ObjectServer` GenServer hosts it under the same `AgentSupervisor` as agents. Add
it to the swarm config `objects:` list and wire it into the topology. See
`docs/objects.md`.

## Messaging

Agents address each other with `@target:` prefixes in stdout, parsed by
`AgentProtocol.parse_output/1`; sandboxed agents deliver via files
(`{workspace}/.inbox/…`, `.outbox/…`) polled by `LogWatcher` (~500ms), with the
`swarm-msg` helper mounted in. System objects `:metrics`, `:tick`, `:gateway` are
always routable regardless of topology edges. See `docs/messaging.md`.

## Dev loop

```bash
nix develop                    # pins Elixir 1.17 / Erlang OTP 27 / Node 20
mix deps.get
mix test                       # mock backend => LLM-free; single file: mix test path; tags: --only tag
mix format
mix escript.build              # → ./genswarms
mix phx.server                 # the API in dev
nix build .#agentContainer-<preset>   # container images (base|code|data|node|python|web)
```

Docs site: `mkdocs.yml` over `docs/`. If you change config parsing, backends, or
the IR, update the matching `docs/` page and the tests — `AGENTS.md` states the
expected test coverage per area.

## Where to read more

- `AGENTS.md` — the coding-agent contract (test expectations, backend/IR change rules).
- `CLAUDE.md` — build/dev commands, architecture, config DSL, env vars.
- `docs/architecture.md` — the real supervision tree and per-swarm layout.
- `docs/intermediate-representation.md` — `swarm.state` / `swarm.overlay` / the Gate.
- `docs/backends.md`, `docs/objects.md`, `docs/messaging.md`, `docs/security.md`, `docs/testing.md`.
