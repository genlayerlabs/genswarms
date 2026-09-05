---
description: The GenSwarms Intermediate Representation (IR) — swarm.state and swarm.overlay, the pure data model that validates, mutates, and drives swarms, and the default control-plane gate.
---

# Intermediate representation (IR)

The **IR** is a pure-data model of a swarm. It lets GenSwarms *describe*, *validate*,
*mutate*, and *drive* a swarm as plain JSON-shaped data — with no `Code.eval`, no
shell, and no atom minting from untrusted input. It is also the foundation the
`gsp` package ecosystem (sharing reusable agent definitions) builds on.

It lives in `Genswarms.IR.*` and is exposed through the `Genswarms.IR` façade.

!!! note "Status"
    The IR core, the config→IR translator, the op-validation policy, the
    reconcile/actuation layer, and the **default validation gate** are all
    wired and in use. `gsp` and `swarmidx` provide authenticated package
    resolution and vendoring. Runtime translation retains native package
    handler refs and their explicit loader settings. Package body/policy loading
    and self-contained database-backed IR restart are not yet wired end to end;
    unsupported execution translations fail rather than silently using defaults.

## The two representations

| Representation | Module | What it is |
|----------------|--------|------------|
| `swarm.state` (IR1) | `Genswarms.IR.State` | A snapshot of a swarm: agents, objects, topology, options — in a declared `phase` (`desired` or `observed`). |
| `swarm.overlay` (IR2) | `Genswarms.IR.Overlay` | An ordered log of mutation events (`add_agent`, `scale_agent_group`, `bump_package`, …) that folds over a `swarm.state`. |

A swarm is the result of folding overlays onto a seed state:

```
materialized_state = fold(seed_state, overlay_events)
```

`fold/2` (`Genswarms.IR.Fold`) is **pure**: it applies events in `seq` order and
performs no runtime effects. Executing the result against the live system is a
separate concern (see [Actuation](#actuation)).

### swarm.state (IR1)

Each agent has three orthogonal slots, each answering a different question:

| Slot | Question | Example |
|------|----------|---------|
| `body` | **who is the agent / what does it do** (its persona, today the skills) | `{"ref": "inline:researcher", "kind": "data"}` |
| `model` | **which LLM** | `{"ref": "openrouter:anthropic/claude-sonnet-4", "attested": true}` |
| `backend` | **where it runs** | `{"ref": "bwrap"}` / `{"ref": "oci:web", "kind": "data"}` / `{"ref": "apple_container", "image": "szc-agent-code:latest"}` / `{"ref": "ssh", "host": "pi@h"}` / `{"ref": "tmux", "client": "codex"}` |

Objects have a `handler` slot (`kind: code`). References (`Genswarms.IR.Ref`) carry
a content `digest` when they are content-addressable (`swarmidx:`/`oci:`), or are
marked `attested` / represented as backend metadata when they are not
(`openrouter:`, `ssh`, `apple_container`).

A `swarm.state` must satisfy the structural invariants on parse: unique node
names, every topology endpoint exists, and **slot-typing** — `body`/`policy` are
`kind: data`, `handler` is `kind: code`. That data/code split is the privilege
boundary: data is loadable from anywhere, code is not.

### swarm.overlay (IR2) — op catalogue

| `op` | Payload | Effect |
|------|---------|--------|
| `add_agent` / `add_object` | a full agent/object | add a node (name must be new) |
| `remove_agent` / `remove_object` | `{name}` | remove the node and its edges |
| `add_topology_edges` / `remove_topology_edges` | `{edges}` | add/remove edges |
| `scale_agent_group` | `{base_name, target_count}` | materialize `base#1..base#N` |
| `bump_package` | `{target, field, from, to}` | swap a slot's digest (`from` must match) |
| `set_options` | `{options}` | merge into `options` |
| `update_config` | `{target, config}` | merge into a node's config |

Unknown ops fail validation — they are never silently ignored, and op strings are
matched against a fixed set (no atom minting).

## The public API

```elixir
alias Genswarms.IR

{:ok, state}   = IR.state(state_map)        # parse + validate a swarm.state
{:ok, overlay} = IR.overlay(overlay_map)    # parse + validate a swarm.overlay

# apply one proposed op: security policy first, then structural fold
{:ok, state2} = IR.apply_op(state, event)
# apply a whole overlay, op by op
{:ok, state3} = IR.apply_overlay(state, overlay)

# fold a seed + overlay into the desired state
{:ok, desired} = IR.materialize(seed, overlay)
# checkpoint + log compaction
{:ok, checkpoint, remaining} = IR.compact(seed, overlay, at_seq)

# public JSON serialization (not a dump of internal structs/BEAM terms)
json = state |> Genswarms.IR.State.to_map() |> Jason.encode!()
{:ok, restored} = json |> Jason.decode!() |> IR.state()
```

`apply_op/3` is the single choke point where **both** the security policy
(`IR.OpPolicy`) and the structural preconditions (`IR.Fold`) are enforced.

## From your config

`Genswarms.IR.FromConfig` translates the existing `.exs`/`.json`/`.yaml`
[swarm configuration](configuration.md) into a validated `swarm.state`:

| Config | IR |
|--------|-----|
| `skills` / `presets` | `body {ref: "inline:<name>"}` + `overrides` |
| `model: "x/y"` | `{ref: "openrouter:x/y", attested: true}` |
| `endpoint` / `request_extra` / `compact_extra` | Same fields in agent `overrides`, restored on runtime translation |
| `backend: :bwrap` / `:local` / `:mock` | bare refs `{ref: "bwrap"}` … |
| `backend: {kind, opts}` for local/bwrap/mock | bare refs with `opts` retained |
| `backend: {:docker, n}` | `{ref: "oci:<n>", kind: data}` |
| `backend: {:docker, n, opts}` | `{ref: "oci:<n>", kind: data, opts: opts}` |
| `backend: :apple_container` | `{ref: "apple_container"}` |
| `backend: {:apple_container, n}` | `{ref: "apple_container", image: n}` |
| `backend: {:apple_container, n, opts}` | `{ref: "apple_container", image: n, opts: opts}` |
| `backend: {:ssh, "u@h"}` | `{ref: "ssh", host: "u@h"}` |
| `backend: {:ssh, "u@h", opts}` | `{ref: "ssh", host: "u@h", opts: opts}` |
| `backend: {:tmux, client}` | `{ref: "tmux", client: client}` |
| `backend: {:tmux, client, opts}` | `{ref: "tmux", client: client, opts: opts}`; runner options such as `{runner: "docker", image: "coding-tuis:latest", client_source: "runtime"}` round-trip unchanged |
| `object.handler Mod` | `{ref: "module:<Mod>", kind: code}` |
| `object.handler %{ref, digest, path, mode}` | Native `swarmidx:` handler ref and digest, with `{path, mode}` in `handler.opts` |

The Apple container ref is intentionally not content-addressable in the current
IR mapping: it stores the backend choice and optional image/options metadata, but
does not claim an OCI digest. Docker keeps the existing `oci:<image>` mapping.
`Genswarms.IR.ToConfig` round-trips these Apple forms back to
`:apple_container`, `{:apple_container, image}`, or
`{:apple_container, image, opts}`.
Tmux refs likewise preserve the declared client and known option keys across
the config → IR → config round trip.

Backend options are also retained for local, bwrap, mock, Docker and SSH refs.
Known execution keys are restored to atom keys; JSON selectors such as
`network: "isolated"` and `privilege_mode: "rootless"` become the runtime's
atom selectors. Arbitrary string values are not converted to atoms. An Apple
ref with nonempty options must declare its image explicitly; `ToConfig` refuses
an unrepresentable form instead of dropping those options.

Package handlers require an explicit `opts.path` to the installed package and
`opts.mode: "verify" | "require"` (`"verify"` by default, matching the existing
config loader). These options describe local execution, not signed registry
metadata. Unknown load modes are rejected. The loader still checks package
bytes; a successful config/IR round trip alone is not proof of BEAM provenance.

`State.to_map/1` and `Ref.to_map/1` emit the public JSON shape, retaining native
refs, model-policy wrappers, execution metadata and explicit null options.
They do not make arbitrary Elixir values portable: functions, tuples and
other non-JSON metadata must not be treated as serialized IR checkpoints.

## The default control-plane gate

The IR is wired into the orchestrator as a **strict, fail-closed gate**
(`Genswarms.IR.Gate`), so it governs every swarm without changing how agents are
spawned:

- **On swarm start** — the config must translate to a valid `swarm.state` (the
  §6 invariants). An invalid or untranslatable config is **refused before
  spawning**.
- **On `add_agent`** — rejects host-escape backend config keys
  (`subzeroclaw_path`, `extra_ro_binds`, `extra_rw_binds`, `extra_path`) and the
  per-swarm agent cap. The key restrictions apply both to agent `config` and
  backend tuple options / native IR `backend.opts`.
- **On `scale_agent_group`** — enforces the agent cap.

The cap defaults to `config :genswarms, :max_agents_per_swarm` (100) and applies
to **dynamic** mutations, not to operator-authored configs.

## Actuation

`Genswarms.IR.Reconcile.plan(desired, observed)` computes the ordered actions
that bring a live swarm to a desired state (start/restart/stop nodes, add/remove
edges) — pure, no runtime access.

`Genswarms.IR.Executor` runs that plan against the orchestrator: it reads the
live config (`observed`) and translates each action into a `SwarmManager` call.
`Executor.reconcile(swarm, desired)` does the whole loop — observed → plan →
apply.

All runtime spec conversions are checked before the first mutation in a plan.
An unsupported body/policy, missing handler binding or invalid runtime option
returns `{:error, {:invalid_runtime_spec, one_based_position}}`, without dumping
configuration values. A restart also stops if removing the old node fails;
it does not attempt to add the replacement anyway. This preflight is not
transactional rollback of runtime failures after valid actions have begun.

## Design spec

The normative format and semantics (the ref model, the §6 invariants, the op
catalogue, fold/materialize/compaction) are defined in the GenSwarms IR
specification. This page documents what is implemented and usable today.
