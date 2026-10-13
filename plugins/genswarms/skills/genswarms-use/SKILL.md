---
name: genswarms-use
description: >-
  Drive genswarms — the Elixir/OTP orchestrator for swarms of subzeroclaw
  agents. Load this to define a swarm (agents + objects + topology), run it as a
  daemon, and observe/scale/message it via the `genswarms` CLI or the REST +
  WebSocket API. Orients and links to the hosted docs and upstream source
  references for depth. To develop or extend genswarms itself (add a backend or
  object, touch the IR/API/daemon), use genswarms-contribute.
---

# Using genswarms

A **swarm** is a declarative set of **agents** (each an execution backend +
skills + model), optional non-agentic **objects** (deterministic Elixir
components in the graph), and a directed **topology** connecting them. Swarms run
as independent **daemon** OS processes; the CLI, the optional Phoenix API, and
the daemons coordinate through SQLite at `.genswarms/swarms.db`. This skill is the
orientation; the upstream
[operating guide](https://github.com/genlayerlabs/genswarms/blob/main/SKILL.md)
and [hosted docs](https://genswarms.com/docs/) carry the deeper references.

## Define a swarm

A config file (`.exs` / `.json` / `.yaml`) with required `name:` and `agents:`,
plus optional `objects:`, `topology:`, `skills_base_dir:`. Each agent carries
three orthogonal slots — `body` (skills/persona), `model` (LLM), `backend`
(execution env). See [Configuration](https://genswarms.com/docs/configuration/)
and [Getting started](https://genswarms.com/docs/getting-started/). Under the
hood a config is translated to the IR `swarm.state` and validated before
anything spawns (see genswarms-contribute /
[Intermediate representation](https://genswarms.com/docs/intermediate-representation/)).

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
`delete`, `clean`, `restart_agent`. Full reference:
[CLI docs](https://genswarms.com/docs/cli/).

## Drive it — the API

Optional Phoenix server (`mix phx.server`, default `:4000`, `PORT` to change):
- **REST** `/api/*`: swarms (list/create/detail/stop), per-agent ops
  (`task`, `restart`, `logs`, `history`, `skills`), dynamic `topology`,
  `objects`, `overlay`/`snapshot`, `messages`/`events`, `skills`,
  `config/validate`. See [REST API](https://genswarms.com/docs/rest-api/).
- **WebSocket** channel `swarm:{name}` at `/swarm/websocket`: inbound
  `send_task` / `get_status` / `subscribe_logs` / `subscribe_events`; outbound
  `agent_output`, `message_routed`, `agent_status`, `topology_changed`,
  `log_entry`, `event`, … See [WebSocket API](https://genswarms.com/docs/websocket/).
- **Auth:** Bearer `GENSWARMS_API_TOKEN`. If unset, the server is
  **loopback-only** by default ([Security](https://genswarms.com/docs/security/)).

## Backends & isolation

An agent's `backend` is where it runs: `:local` (Port subprocess), `:docker`
(NixOS container), `:apple_container`, `:ssh`, `:bwrap` (bubblewrap sandbox),
`:mock` (no LLM, for tests). Add `network: :isolated` to run an agent that
ingests untrusted content with no network except a forwarder pinned to the LLM —
so a prompt-injected agent can't reach the orchestrator or exfiltrate (bwrap and
docker support it; Apple `container` rejects it). See
[Backends](https://genswarms.com/docs/backends/),
[Containers](https://genswarms.com/docs/containers/), and
[Security](https://genswarms.com/docs/security/).

## Gotchas

- **The model rides through to subzeroclaw.** Agents are subzeroclaw processes;
  their routing/model is configured per the subzeroclaw contract (`request_extra`
  etc.) — see the `subzeroclaw-use` skill.
- **Build targets are eight named images.** `genswarms build` accepts `base`,
  `web`, `code`, `data`, `full`, `python`, `node`, and `devops`
  (`@available_images` in `lib/mix/tasks/genswarms/build.ex`). These match the
  images documented in [CLI](https://genswarms.com/docs/cli/#build) and
  [Containers](https://genswarms.com/docs/containers/). You can also build one
  directly with `nix build .#agentContainer-<name>`.
- **Loopback by default.** Without `GENSWARMS_API_TOKEN` the API refuses
  non-loopback callers — set the token before exposing it.
- **Mock without LLM:** `backend: :mock` spawns nothing; for a real agent loop
  without spending, set `SUBZEROCLAW_MOCK_SCRIPT`.

## Where to read more

- [Operating guide](https://github.com/genlayerlabs/genswarms/blob/main/SKILL.md)
  — the full operate-a-swarm guide.
- [Getting started](https://genswarms.com/docs/getting-started/),
  [CLI](https://genswarms.com/docs/cli/),
  [Configuration](https://genswarms.com/docs/configuration/) — define + run.
- [REST API](https://genswarms.com/docs/rest-api/),
  [WebSocket](https://genswarms.com/docs/websocket/),
  [Programmatic usage](https://genswarms.com/docs/programmatic/) — drive over HTTP/WS.
- [Backends](https://genswarms.com/docs/backends/),
  [Containers](https://genswarms.com/docs/containers/),
  [Security](https://genswarms.com/docs/security/) — execution + isolation.
- [Observability](https://genswarms.com/docs/observability/),
  [Messaging](https://genswarms.com/docs/messaging/),
  [Objects](https://genswarms.com/docs/objects/) — watch + wire.
