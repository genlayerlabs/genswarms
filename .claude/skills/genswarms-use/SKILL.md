---
name: genswarms-use
description: >-
  Drive genswarms — the Elixir/OTP orchestrator for swarms of subzeroclaw
  agents. Load this to define a swarm (agents + objects + topology), run it as a
  daemon, and observe/scale/message it via the `genswarms` CLI or the REST +
  WebSocket API. Orients and points into the root SKILL.md (operating-genswarms)
  and docs/ for depth. To develop or extend genswarms itself (add a backend or
  object, touch the IR/API/daemon), use genswarms-contribute.
---

# Using genswarms

A **swarm** is a declarative set of **agents** (each an execution backend +
skills + model), optional non-agentic **objects** (deterministic Elixir
components in the graph), and a directed **topology** connecting them. Swarms run
as independent **daemon** OS processes; the CLI, the optional Phoenix API, and
the daemons coordinate through SQLite at `.genswarms/swarms.db`. This skill is the
orientation; the root **`SKILL.md`** (`operating-genswarms`) is the full
operating guide and `docs/` carries every topic.

## Update requests

If the user asks to update vendors or "everything", treat that as packages +
vendors + dependencies together. Explain the result in chat: version deltas first,
then the main features or compatibility changes, simply and briefly.

## Define a swarm

A config file (`.exs` / `.json` / `.yaml`) with required `name:` and `agents:`,
plus optional `objects:`, `topology:`, `skills_base_dir:`. Each agent carries
three orthogonal slots — `body` (skills/persona), `model` (LLM), `backend`
(execution env). See `docs/configuration.md` and `docs/getting-started.md`. Under
the hood a config is translated to the IR `swarm.state` and validated before
anything spawns (see genswarms-contribute / `docs/intermediate-representation.md`).

## Drive it — the CLI

Build the escript once (`mix escript.build` → `./genswarms`), then:

```
genswarms start <config>      start a swarm as a daemon
genswarms status [name]       lifecycle + agent state
genswarms task <name> …       send a task into the swarm
genswarms msg  <name> …       send a message to an agent
genswarms logs / events       stream logs / the event log
genswarms scale <name> …      grow/shrink an agent group live
genswarms overlay / snapshot  inspect/mutate the running swarm's IR
genswarms stop | restart      lifecycle
genswarms list-skills | build | config | check | init | dashboard(up)/down | env
```

Entry point: `Genswarms.CLI.main/1` (`lib/genswarms/cli.ex`). A few operations are
**Mix-task-only** (not on the escript): `mix genswarms.pause`, `resume`,
`delete`, `clean`, `restart_agent`. Full reference: `docs/cli.md`.

## Drive it — the API

Optional Phoenix server (`mix phx.server`, default `:4000`, `PORT` to change):
- **REST** `/api/*`: swarms (list/create/detail/stop), per-agent ops
  (`task`, `restart`, `logs`, `history`, `skills`), dynamic `topology`,
  `objects`, `overlay`/`snapshot`, `messages`/`events`, `skills`,
  `config/validate`. See `docs/rest-api.md`.
- **WebSocket** channel `swarm:{name}` at `/swarm/websocket`: inbound
  `send_task` / `get_status` / `subscribe_logs` / `subscribe_events`; outbound
  `agent_output`, `message_routed`, `agent_status`, `topology_changed`,
  `log_entry`, `event`, … See `docs/websocket.md`.
- **Auth:** Bearer `GENSWARMS_API_TOKEN`. If unset, the server is
  **loopback-only** by default (`docs/security.md`).

## Backends & isolation

An agent's `backend` is where it runs: `:local` (Port subprocess), `:docker`
(NixOS container), `:apple_container`, `:ssh`, `:bwrap` (bubblewrap sandbox),
`:mock` (no LLM, for tests). Add `network: :isolated` to run an agent that
ingests untrusted content with no network except a forwarder pinned to the LLM —
so a prompt-injected agent can't reach the orchestrator or exfiltrate (bwrap and
docker support it; Apple `container` rejects it). See `docs/backends.md`,
`docs/containers.md`, `docs/security.md`.

## Gotchas

- **The model rides through to subzeroclaw.** Agents are subzeroclaw processes;
  their routing/model is configured per the subzeroclaw contract (`request_extra`
  etc.) — see the `subzeroclaw-use` skill.
- **Container presets vs the `build` allowlist don't match today.** The real Nix
  presets are `base`, `code`, `data`, `node`, `python`, `web`
  (`nix/tool-presets.nix`), built via `nix build .#agentContainer-<preset>`. The
  `genswarms build` command's own allowlist (`@available_images` in
  `lib/mix/tasks/genswarms/build.ex`, mirrored in `docs/cli.md`) currently lists
  `base, python, node, elixir` — so `elixir` isn't a real preset and
  `code`/`data`/`web` aren't reachable through the command. Prefer the `nix
  build` form until this is reconciled.
- **Loopback by default.** Without `GENSWARMS_API_TOKEN` the API refuses
  non-loopback callers — set the token before exposing it.
- **Mock without LLM:** `backend: :mock` spawns nothing; for a real agent loop
  without spending, set `SUBZEROCLAW_MOCK_SCRIPT`.

## Where to read more

- Root `SKILL.md` (`operating-genswarms`) — the full operate-a-swarm guide.
- `docs/getting-started.md`, `docs/cli.md`, `docs/configuration.md` — define + run.
- `docs/rest-api.md`, `docs/websocket.md`, `docs/programmatic.md` — drive over HTTP/WS.
- `docs/backends.md`, `docs/containers.md`, `docs/security.md` — execution + isolation.
- `docs/observability.md`, `docs/messaging.md`, `docs/objects.md` — watch + wire.
