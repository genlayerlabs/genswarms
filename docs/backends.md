---
description: GenSwarms execution backends — Local, persistent tmux TUIs, Docker, Apple container, SSH, Bubblewrap, and Mock — and how to choose one per agent.
---

# Backends

A backend is how GenSwarms runs an agent runtime. Most backends launch
`subzeroclaw`; the tmux backend launches an existing interactive coding client.
Every agent declares a `backend:`, and GenSwarms uses the matching module to
start it, deliver input, expose health/session state, and stop it. All backends
implement `Genswarms.Backends.BackendBehaviour`, so the topology and router do
not depend on the selected runtime.

This guide covers each backend: how it runs, the config it accepts, and what you need on the host.

## The backend contract

Every backend implements `Genswarms.Backends.BackendBehaviour` (`lib/genswarms/backends/backend_behaviour.ex`). The callbacks are:

| Callback | Required? | Purpose |
|----------|-----------|---------|
| `start/2` | yes | Start the agent process; returns `{:ok, ref}` or `{:error, term}` |
| `stop/1` | yes | Stop the running agent |
| `send_input/2` | yes | Deliver a message; may return backend metadata such as a turn ID |
| `deploy_skills/2` | yes | Make skills available to the agent |
| `health_check/1` | yes | Report whether the agent is alive (`:ok` or `{:error, reason}`) |
| `backend_type/0` | yes | Return the backend's atom (e.g. `:local`) |
| `handle_output/2` | optional | Parse raw output into messages |
| `capabilities/0` | optional | Advertise readiness events, interrupt, persistence, and raw terminal support |
| `interrupt/1` | optional | Interrupt the current turn without destroying the worker |
| `session_info/1` | optional | Return non-secret attach/session metadata |
| `disconnect/1` / `destroy/1` | optional | Separate orchestrator disconnect from intentional resource destruction |
| `acknowledge/2` | optional | Confirm that a durable turn completion was handled |

Backends without the optional lifecycle callbacks retain the original Port-style behavior. Event-driven backends receive an `event_sink` and a per-start `backend_id`; the ID prevents delayed events from an older backend generation from mutating a restarted agent.

The subzeroclaw backends share the `szc-wrapper` wire protocol, which translates
between JSON lines and subzeroclaw's plain-text interface. Tmux uses typed
lifecycle events and durable per-turn files instead; its terminal stream remains
diagnostic and human-facing.

## Choosing a backend

| Backend | When to use | Isolation level |
|---------|-------------|-----------------|
| `:local` | Development, debugging, single-host runs | None (plain subprocess) |
| `{:tmux, client}` | Warm, human-attachable Codex/Claude/OpenCode sessions | Selectable: host, per-agent Docker, or per-agent bwrap |
| `{:docker, "name"}` | Reproducible tool environments, per-agent images | Container (namespaces + image) |
| `{:apple_container, "name"}` | OCI containers on macOS / Apple silicon without Docker Desktop | Apple container VM |
| `{:ssh, "user@host"}` | Bare-metal / remote NixOS machines | Remote host |
| `:bwrap` | Massive scale (10k+ agents on one box) | Lightweight sandbox (user namespaces) |
| `:mock` | Tests without LLM calls | None (no process spawned) |

Every *real* backend (local, docker, apple_container, ssh, bwrap) resolves the LLM settings from the agent config. `api_key` and `endpoint` fall back to the process environment (`SUBZEROCLAW_API_KEY`, `SUBZEROCLAW_ENDPOINT`) when not set in config. The **`model` has no environment fallback**: `SUBZEROCLAW_MODEL` is a dead variable that `subzeroclaw` no longer reads. A config-level `model` is passed through as `SUBZEROCLAW_REQUEST_EXTRA = {"model": …}`; for router routing you set `request_extra` directly (a `policy_ir`), and when neither is set `subzeroclaw` uses its own default. The `:mock` backend ignores all of this — it never spawns a process.

## Local

The local backend (`lib/genswarms/backends/local_backend.ex`) spawns subzeroclaw as an Elixir `Port` subprocess and communicates over stdin/stdout. It is the simplest backend and the easiest to debug, but provides no isolation — the agent runs as your user with full access to the host. `stop/1` terminates the whole OS process tree (SIGTERM, then SIGKILL after a short grace) rather than just closing stdin, so a wedged agent and its children are cleaned up.

```elixir
%{
  name: :researcher,
  backend: :local,
  skills: ["research.md"],
  model: "anthropic/claude-sonnet-4"
}
```

It launches the `szc-wrapper` script, which in turn runs the `subzeroclaw` binary. Both paths are resolved from config or application environment:

| Config key | Purpose | Resolution order |
|------------|---------|------------------|
| `wrapper_path` | Path to the wrapper script | config `:wrapper_path` → app env `:wrapper_path` → `priv/szc-wrapper-fifo.sh` |
| `subzeroclaw_path` | Path to the subzeroclaw binary | config `:subzeroclaw_path` → app env `:subzeroclaw_path` → `"subzeroclaw"` (from `PATH`) |
| `api_key` | LLM API key | config → `SUBZEROCLAW_API_KEY` env |
| `model` | Model identifier | config only → wrapped into `SUBZEROCLAW_REQUEST_EXTRA` as `{"model": …}` (no `SUBZEROCLAW_MODEL` env fallback — it is dead) |
| `endpoint` | LLM endpoint | config → `SUBZEROCLAW_ENDPOINT` env |
| `request_extra` | Router routing/body-override JSON (`policy_ir`) | config → `SUBZEROCLAW_REQUEST_EXTRA` env |
| `compact_extra` | Async compaction JSON (`keep_recent` + summariser policy) | config → `SUBZEROCLAW_COMPACT_EXTRA` env |

The wrapper is invoked as `<wrapper_path> <name> <subzeroclaw_path> <skills_dir>`. When a `skills_dir` is present, its expanded path is also exported to the subprocess as the `SUBZEROCLAW_SKILLS` environment variable; the agent name is exported as `SUBZEROCLAW_AGENT_NAME`.

Requirements: a `subzeroclaw` binary on the host (on `PATH` or via `subzeroclaw_path`).

## Tmux persistent TUI

The tmux backend (`lib/genswarms/backends/tmux_backend.ex`) runs an existing
interactive coding client in a persistent pane instead of flattening it into a
one-shot command. Supported clients are Codex, Claude Code, and OpenCode:

```elixir
%{
  name: :coder,
  backend: {:tmux, :codex, %{
    workspace: "/home/me/project",
    runner: :docker,
    image: "coding-tuis:latest",
    client_source: :runtime,
    approval_policy: :on_request,
    sandbox: :workspace_write
  }}
}
```

Use `:claude` or `:opencode` as the second tuple element for those clients.
String client names (`"codex"`, `"claude"`, `"opencode"`) are also accepted.
There is intentionally no bare `:tmux` form: the client must be explicit.

tmux itself always runs on the host and remains the observation/control plane.
The pane command can run the client directly (`runner: :host`), enter one
dedicated container with `docker exec -it` (`runner: :docker`), or enter one
dedicated bubblewrap sandbox (`runner: :bwrap`). The latter two give every agent
its own process/filesystem boundary while preserving the same host-side attach
command.

### Lifecycle and durable turns

One tmux socket contains one named session per swarm and one window per agent.
GenSwarms stores the stable pane ID and emits normalized lifecycle states:
`starting`, `ready`, `running`, `blocked`, `needs_attention`, `interrupted`, and
`stopped`. Screen capture is used for human visibility and conservative prompt
detection; it is **not** treated as a delivery acknowledgement.

Each turn gets a directory under:

```text
<workspace>/.genswarms/turns/<swarm>/<agent>/<turn-id>/
├── task.md
├── reply.md
├── done.json
├── ack.json
└── interrupted.json
```

The backend writes `task.md` atomically and sends only a short path-based nudge
with `tmux send-keys`. It briefly separates the literal paste from `Enter`. If
the exact nudge is still present at the active cursor after the grace period,
the backend retries only `Enter` once; it never pastes the task text twice. A
nudge that remains staged moves the turn to `needs_attention`. This is bounded
TUI recovery, not an acceptance acknowledgement. The client completes the
contract by writing `reply.md`
and atomically renaming a `done.json.tmp` receipt to `done.json`. GenSwarms
processes the reply and then writes `ack.json`. The dispatcher still waits for
a fresh recognized prompt before sending queued work. A task without `ack.json` is
recovered as `needs_attention` after an orchestrator restart; a completed but
unacknowledged turn may therefore be delivered again. The stable turn ID makes
that replay visible in the artifacts and session metadata; output delivery is
still at-least-once, not exactly-once.

There are no lock files or automatic retry engine. A follow-up task remains in
the existing GenSwarms inbox until the current turn completes. If the pane is
alive, an AgentServer restart disconnects and reattaches without killing the
conversation. If the pane process is dead, it is respawned; set `resume: true`
or a client session ID to ask the CLI to restore its own conversation. An
explicit agent/swarm stop destroys the tmux window.

### Attaching and interrupting

`GET /api/swarms/<swarm>/agents/<agent>/session` returns the socket, session,
window, pane ID, and argv for read-only or read-write attachment. The equivalent
command is normally:

```bash
tmux -L genswarms attach-session -r -t genswarms-<swarm>:<agent>  # observe only
tmux -L genswarms attach-session -t genswarms-<swarm>:<agent>     # interactive
```

Use `POST /api/swarms/<swarm>/agents/<agent>/interrupt` to send `C-c` to the
current pane without deleting it. The raw captured terminal is also published
on the in-process swarm terminal PubSub topic for BEAM-side UI consumers; it is
not currently forwarded through the public WebSocket channel.

### Options

| Config key | Purpose | Default |
|------------|---------|---------|
| `workspace` | Client working directory and durable turn root | `/tmp/genswarms-tmux/<swarm>/<agent>` |
| `runner` | Execution boundary: `:host`, `:docker`, or `:bwrap` | `:host` |
| `client_source` | `:runtime` (binary already in image/base) or `:host_nix` (read-only host Nix closure) | Docker: `:runtime`; bwrap: `:host_nix` |
| `image` | Persistent per-agent Docker container image | preset/default image |
| `state_dir` | Private host directory mounted as `/root` for client auth/config/session state | per-swarm/agent/client temp path |
| `network` | Host/open, Docker network name, or `:none`; see below | `:open` |
| `pass_env` | Names of existing host variables to pass to the isolated runtime | `[]` |
| `runner_env` | Explicit isolated-runtime environment map | `%{}` |
| `extra_ro_binds` / `extra_rw_binds` | Additional `{host, runtime}` mounts | `[]` |
| `memory_limit` | Per-agent memory limit | bwrap rootless: unset; bwrap cgroup: `"2G"` |
| `privilege_mode` | bwrap launcher: `:rootless` (keeps the pane's PTY) or explicit `:cgroup` | `:rootless` |
| `docker_executable` / `bwrap_executable` | Override isolation CLI executable | resolved from `PATH` |
| `xargs_executable` | Override the NUL-safe bwrap host-argv launcher | resolved from `PATH` |
| `model` | Native client model flag | client default |
| `resume` | `true` for the most recent session, or a client session ID | `false` |
| `tmux_socket` | Dedicated tmux socket name | `genswarms` |
| `tmux_executable` / `executable` | Override tmux/client executable | resolved from `PATH` |
| `args` | Extra client argv strings (never host-shell interpolated) | `[]` |
| `approval_policy` / `sandbox` | Codex approval and sandbox modes | client config/default |
| `permission_mode` / `effort` | Claude permission and effort modes | client config/default |
| `auto_approve` | OpenCode `--auto` | `false` |
| `dangerously_bypass` | Explicit Codex/Claude permission bypass | `false` |
| `poll_interval_ms` | Pane/receipt poll interval | `250` |
| `submit_delay_ms` / `submit_retry_after_ms` | Delay before initial `Enter` / cursor-check grace | `100` / `1000` |
| `submit_max_attempts` / `submit_check_max_errors` | Total Enter attempts / cursor-query errors before attention | `2` / `3` |
| `history_lines` / `state_lines` | Captured history / visible tail used for state recognition | `200` / `24` |
| `quiet_ready_fallback` | Allow a stable non-empty screen to count as ready | `false` |
| `max_reply_bytes` | Maximum accepted `reply.md` size | 1 MiB |

Dangerous bypass flags are never enabled implicitly. A blocked trust or
permission prompt moves the agent to `blocked` so a human can attach and decide.
Because a TUI is not a machine protocol, prompt recognition is deliberately
conservative; `quiet_ready_fallback` is opt-in.

### Per-agent Docker and bwrap runners

The isolated runners use this runtime contract:

| Runtime path | Source | Access |
|--------------|--------|--------|
| `/workspace` | the agent's host workspace | read/write |
| `/root` | the agent's private `state_dir` | read/write |
| `/skills` | deployed skills, when present | read-only |
| `/nix/store/...` | selected client closure with `client_source: :host_nix` | read-only |

Environment selected by `pass_env`/`runner_env` is not placed in the bwrap or
tmux argv. The runner writes a shell-quoted mode-0600 file under the private
`state_dir` and invokes a constant bootstrap path inside `/root`; the agent can
read those values because they are part of its granted authority, while host
process listings and systemd metadata cannot.

A minimal Nix closure can require hundreds of read-only bind arguments, more
than tmux accepts in one control command. The bwrap runner writes those
arguments as a private, NUL-delimited `host-launch.argv0` manifest and invokes
them once with `xargs --null --exit --max-args=<exact count>`. No host shell
parses the manifest, argument boundaries are preserved, and the short tmux
command contains only the manifest path and launcher metadata. GNU `xargs` is
therefore a host requirement for the bwrap TUI runner.

Docker creates one persistent container named `gstui-<swarm>-<agent>` and
refuses to reuse a same-named container whose ownership, mounts, image, network,
resource limits, or configured environment differ. bwrap creates one
copy-on-write root under `/run/swarm/agents/gstui-<swarm>-<agent>` and stores a
private contract fingerprint so a live pane cannot be reattached under changed
mounts, network, limits, executable, or environment. Explicit destroy removes
the container/overlay; an orchestrator disconnect leaves both the pane and its
boundary alive for reattachment.

There are two ways to supply a client:

- `client_source: :runtime` expects `codex`, `claude`, or `opencode` to be in the
  image/base runtime's `PATH`. This is the Docker default and is the most
  portable production setup.
- `client_source: :host_nix` resolves the selected host executable to
  `/nix/store`, queries its minimal closure, and mounts that closure read-only.
  It rejects arbitrary non-Nix host binaries. This is the bwrap default and is
  also useful with a minimal Docker image on NixOS.

Example using the locally installed Nix client in bwrap:

```elixir
%{
  name: :reviewer,
  backend: {:tmux, :claude, %{
    runner: :bwrap,
    client_source: :host_nix,
    privilege_mode: :rootless,
    network: :open
  }}
}
```

`network: :none` gives Docker or bwrap a real no-network namespace. That also
blocks cloud LLM APIs, so it is primarily useful for local providers or
offline/testing work. Docker additionally accepts a named Docker network;
bwrap accepts only `:open` and `:none`. The subzeroclaw-specific
`network: :isolated` mode (LLM-only forwarding) is not yet valid for an
interactive TUI and fails closed with `:tui_egress_isolation_unsupported`.

tmux itself is not the security boundary: it stays on the trusted host. Do not
mount its socket into the agent. Extra read/write binds enlarge the agent's
authority, and the private state directory may contain client credentials.
Dangerous client bypass flags remain explicit. In particular, only set
`dangerously_bypass: true` for Codex/Claude when the outer Docker/bwrap policy is
strong enough for the workload; it is never inferred merely because a runner
was selected.

Requirements: host-side tmux; Docker or bwrap for the selected runner; and
either a runtime image/base containing the selected client or a Nix-installed
host client plus `nix-store`.

## Docker

The Docker backend (`lib/genswarms/backends/docker_backend.ex`) runs each agent in a NixOS-based container. It is the right choice when agents need specific, reproducible tool sets, since the tools are baked into the image rather than your host.

```elixir
%{
  name: :coder,
  backend: {:docker, "coder"},
  presets: [:base, :code],
  skills: ["code.md"]
}
```

You can also pass options as a third tuple element:

```elixir
%{
  name: :coder,
  backend: {:docker, "coder", %{memory_limit: "512m", network: "swarmnet"}},
  skills: ["code.md"]
}
```

### Container naming and multi-swarm namespacing

Containers are named `szc-{swarm}-{agent}` unless you override the name with the `container` key. The swarm name is part of the name, so the same agent name in two different swarms maps to two distinct containers and they never collide. On start, if a container with that name already exists (running, paused, exited, or otherwise), it is forcibly removed (`docker rm -f`) and recreated. The container itself is run with `docker run -i --rm`, so it is also removed automatically when it exits.

### Image selection

The image is chosen in this order:

1. An explicit `image` key.
2. The `container` name used as an image.
3. A pre-built image matched from `presets` (sorted), e.g. `[:base, :web]` → `szc-agent-web:latest`. Unknown combinations fall back to `szc-agent-base:latest`.
4. The default `szc-agent-base:latest`.

If the chosen image is not present locally, the backend attempts to build it with `nix build .#agentContainer-<preset>` (where `<preset>` is derived from `presets`, defaulting to `full` for unrecognized combinations) and then `docker load -i result`. If the build fails the failure is logged and the backend proceeds with the originally selected image name — so make sure your preset images either build or already exist locally.

### Docker options

| Config key | Purpose |
|------------|---------|
| `container` | Explicit container name; also used as an image candidate |
| `image` | Explicit image to run |
| `presets` | NixOS tool presets used to pick/build the image |
| `workspace` | Host path mounted at `/workspace` (default `/tmp/szc-workspace`) |
| `volumes` | Extra mounts as `[{host_path, container_path}]` |
| `network` | Docker network to attach (`--network`) |
| `memory_limit` | Memory cap (`--memory`) |
| `memory_swap` | RAM+swap cap (`--memory-swap`); set equal to `memory_limit` for a true hard RAM ceiling (without it `--memory` allows ~2x via swap) |
| `cpu_limit` | CPU cap (`--cpus`) |
| `pids_limit` | Max process count (`--pids-limit`); bounds fork-bombs / runaway spawns |
| `env` | Extra env vars (a map); `${VAR}` / `$VAR` are expanded from the host. Empty/`nil` values are dropped |
| `cmd` | Override the in-container command |
| `api_key` / `model` / `endpoint` | LLM settings (fall back to env) |

The skills directory, if set, is mounted read-only at `/skills`, and a sibling `logs/` directory is mounted at `/root/.subzeroclaw/logs`. The workspace is mounted at `/workspace` (unless your own `volumes` already mount something under `/workspace`), the host `/tmp` is shared, and the subzeroclaw source directory is mounted read-only at `/src/subzeroclaw` for in-container compilation. Agent name and LLM settings are passed as `-e` env vars, and topology connections are exported as `SWARM_TOPOLOGY` so `swarm-msg list` works inside the container.

Requirements: Docker, and Nix if you want images built on demand. For details on NixOS containers, presets, and how the images are assembled, see [containers.md](containers.md).

## Apple container

The Apple container backend (`lib/genswarms/backends/apple_container_backend.ex`) runs each agent with Apple's `container` CLI. It is for macOS / Apple silicon hosts that want OCI-style agent containers without Docker Desktop.

```elixir
%{
  name: :coder,
  backend: {:apple_container, "szc-agent-code:latest"},
  presets: [:base, :code],
  skills: ["code.md"]
}
```

Options are passed as the third tuple element:

```elixir
%{
  name: :coder,
  backend: {:apple_container, "szc-agent-code:latest", %{
    memory_limit: "2g",
    cpu_limit: 2,
    workspace: "/tmp/genswarms/coder"
  }},
  skills: ["code.md"]
}
```

Use `:apple_container` when you want the backend to pick an image from presets/defaults. Do not use bare `:container`; that name is intentionally not accepted because it is ambiguous.

### Service and image selection

Apple's tool requires its API server to be running before agents start:

```bash
container system start
container system status --format json
```

If `container system status --format json` does not report a running service, GenSwarms fails the agent start with `:apple_container_not_ready`.

The image is chosen in the same order as Docker: explicit `image`, then `container_name`, then a preset-derived image such as `szc-agent-code:latest`, then `szc-agent-base:latest`. If the selected image is not present, the backend attempts `nix build .#agentContainer-<preset> -o result` and then asks Apple `container` to load the result. Current Nix `agentContainer-*` outputs are Docker archives, while Apple `container image load` expects an OCI archive, so operators should pre-load a compatible image by converting the Nix result to OCI or by pulling from a registry. If Nix is unavailable or the build/load fails, the agent still starts with the selected image name and the `container` CLI reports the final image error.

### Apple container options

| Config key | Purpose |
|------------|---------|
| `container_name` | Explicit container name; default `szc-{swarm}-{agent}` |
| `image` | Explicit image to run |
| `presets` | NixOS tool presets used to pick/build the image |
| `workspace` | Host path mounted at `/workspace` (default `/tmp/szc-workspace`) |
| `volumes` | Extra mounts as `[{host_path, container_path}]` |
| `network` | Apple container network to attach (`--network`); `:isolated` / `"isolated"` is rejected |
| `memory_limit` | Memory cap (`--memory`) |
| `cpu_limit` | CPU cap (`--cpus`) |
| `env` | Extra env vars (a map); values are passed as discrete argv entries |
| `cmd` | Override the in-container command. A string runs through `sh -c` inside the container; a list is used as argv |
| `api_key` / `model` / `endpoint` | LLM settings (fall back to env) |

The runtime contract matches Docker where Apple's CLI supports it: skills are mounted read-only at `/skills`, logs at `/root/.subzeroclaw/logs`, the workspace at `/workspace`, host `/tmp` is shared, and the subzeroclaw source directory is mounted read-only at `/src/subzeroclaw` when it can be found. Agent name, LLM request routing, extra request/compaction settings, and topology are passed as environment variables. Container commands are assembled as argv lists for the host `container` process, not shell-built host commands.

`network: :isolated` is not implemented for Apple `container` because the current command set does not expose the Docker/bwrap-style egress-forwarding primitive GenSwarms uses. The backend fails closed with `{:unsupported_network, :isolated}` instead of silently running with open network. Use Docker or bwrap for isolated untrusted-content agents.

Apple's CLI also does not currently expose Docker-style pause/unpause semantics, so GenSwarms pause/resume remains Docker-only.

Requirements: macOS on Apple silicon, Apple's `container` CLI, the `container-apiserver` service running, and Nix if you want images built on demand.

## SSH

The SSH backend (`lib/genswarms/backends/ssh_backend.ex`) runs subzeroclaw on a remote machine over an SSH connection. It targets bare-metal NixOS hosts that have been provisioned (via Colmena) with the agent module — tools installed, skills directory at `/var/lib/subzeroclaw/skills`, and a `subzeroclaw` user set up — but also works on plain hosts.

```elixir
%{
  name: :researcher,
  backend: {:ssh, "agent@192.168.1.51", %{
    key_path: "~/.ssh/id_ed25519",
    nixos: true
  }},
  presets: [:base, :web],
  skills: ["web.md"]
}
```

### SSH options

| Config key | Purpose | Default |
|------------|---------|---------|
| `host` | `user@host` (taken from the tuple) | required |
| `port` | SSH port | `22` |
| `key_path` | Private key path | keys in `~/.ssh` |
| `password` | Password auth (added alongside any key) | none |
| `nixos` | Treat host as a provisioned NixOS machine | `true` |
| `remote_skills_dir` | Where skills are deployed | `/var/lib/subzeroclaw/skills` (NixOS) or `~/.subzeroclaw/skills` |
| `remote_user` | User to run the agent as (NixOS only) | `subzeroclaw` |
| `subzeroclaw_path` | Remote binary path | `subzeroclaw` |
| `api_key` / `model` / `endpoint` | LLM settings (fall back to env) | — |

Authentication: if `key_path` points to an existing file, its directory is used as the SSH `user_dir`; otherwise the backend falls back to `~/.ssh`. A `password`, if given, is added in addition. Host keys are accepted automatically (`silently_accept_hosts: true`, `user_interaction: false`), so this backend trusts whatever host it connects to — pin keys yourself if that matters.

When `nixos: true`, the agent is launched as the `remote_user` (`subzeroclaw` by default) via `sudo -u <user> env … subzeroclaw`. On non-NixOS hosts set `nixos: false`; the agent then runs as the SSH login user (the `remote_user` key is ignored), and you must install subzeroclaw and its tools yourself. If a local `skills_dir` is set, its files are copied to the remote skills directory over SFTP at start time (and again on each `deploy_skills` call). The agent is started with `SUBZEROCLAW_AGENT_NAME`, `SUBZEROCLAW_SKILLS`, and the LLM env vars set on the remote command line.

Requirements: SSH access to the host; on non-NixOS hosts, subzeroclaw and tools installed yourself.

## Bwrap

The bubblewrap backend (`lib/genswarms/backends/bwrap_backend.ex`) sandboxes each agent with Linux user namespaces instead of a full container. It is built for scale — roughly 500KB RAM and ~50ms startup per agent — which is what makes 10k+ agents on a single NixOS machine practical, with no external daemon.

```elixir
# Defaults
%{
  name: :researcher,
  backend: :bwrap,
  skills: ["web.md"]
}

# With options
%{
  name: :coder,
  backend: {:bwrap, %{memory_limit: "256M", presets: [:base, :code]}},
  skills: ["code.md"]
}
```

### Backend keys

Bwrap config separates backend keys (which control the sandbox) from domain keys (your application logic). The backend reads:

| Config key | Purpose | Default |
|------------|---------|---------|
| `workspace` | Host dir bound at `/workspace` | `/tmp/szc-workspace/{sandbox_id}` |
| `extra_path` | Extra dirs prepended to `PATH` inside the sandbox | `[]` |
| `extra_ro_binds` | Read-only mounts as `[{host_path, container_path}]` | `[]` |
| `extra_env` | Extra environment variables (a map) injected into the sandbox | `%{}` |
| `memory_limit` | cgroup memory cap | `"256M"` |
| `cpu_shares` | cgroup CPU shares | `100` |
| `tasks_max` | Max tasks/processes in the cgroup (`:cgroup` mode only) | `50` |
| `privilege_mode` | `:cgroup` (systemd scopes, kernel-hard limits) or `:rootless` (zero elevated capabilities - see below) | `:cgroup` |
| `nice` | CPU niceness for the sandbox in `:rootless` mode | `19` |
| `subzeroclaw_path` | Explicit binary path | resolved (see below) |
| `presets` | Sandbox base layers to overlay | `[:base]` |
| `network` | Set `:isolated` to run with no network except a forwarder pinned to the LLM endpoint (untrusted-content agents) | open network |
| `seccomp` | Apply a cBPF syscall-filter profile (deny mount, ptrace, module load, reboot, …); also enabled by `GENSWARMS_BWRAP_SECCOMP=1`. **Fails closed** — if enabled but the wrapper can't apply it, the agent aborts rather than running unfiltered | `false` |
| `store` | Nix-store bind mode: `:full` binds the whole `/nix/store`; `:closure` binds only the paths the sandbox base + `subzeroclaw` (+ `extra_store_paths`) need — tighter isolation | `:full` |
| `extra_store_paths` | Extra `/nix/store` paths to bind when `store: :closure` (whitelist additional packages) | `[]` |
| `max_turns` | Per-turn step budget passed to `subzeroclaw` (caps the tool-call loop per turn) | `subzeroclaw`'s own default |
| `request_extra` / `compact_extra` | Routing / compaction JSON forwarded to `subzeroclaw` (see the LLM-settings note above) | — |

`sandbox_id` is `{swarm}-{agent}-{timestamp_ms}`. Resource limits are enforced by wrapping the bwrap command in a `systemd-run` cgroup scope (`:cgroup` mode, the default) or in a plain-POSIX rlimit/nice launcher (`:rootless` mode - see "Privilege modes" below). Inside the sandbox, the overlay's merged directory is bound as `/`, the skills directory is bind-mounted read-only at `/root/.subzeroclaw/skills`, a sibling `logs/` directory is bound writable at `/root/.subzeroclaw/logs`, the workspace is bound at `/workspace`, and the Nix store is mounted read-only so binaries resolve. `extra_ro_binds` entries are only mounted if the host path exists. The sandbox runs with `--unshare-{user,pid,uts,ipc}` as uid/gid 1000, with `PATH` defaulting to `/bin:/usr/local/bin` (your `extra_path` dirs are prepended).

> Note: `extra_rw_binds` is listed as a bwrap backend key in the project conventions (it is accepted in agent config without error), but the current backend implements only `extra_ro_binds` (read-only) for extra mounts — `extra_rw_binds` is silently ignored. Use `workspace` for the agent's writable area.

### Binary path resolution

The bwrap backend locates the `subzeroclaw` binary in this order (first existing regular file wins):

1. Explicit `subzeroclaw_path` in config, or the `:subzeroclaw_path` application env (used directly if the file exists).
2. `../subzeroclaw/subzeroclaw` relative to the current working directory (sibling checkout).
3. `../subzeroclaw/subzeroclaw` relative to the GenSwarms source dir (when GenSwarms is used as a dependency).
4. The `SUBZEROCLAW_PATH` environment variable.
5. The system `PATH` (via `which subzeroclaw`).

### Mock and recording inside the sandbox

If `mock_script` is set in config or `SUBZEROCLAW_MOCK_SCRIPT` is set in the environment, it is passed into the sandbox as `SUBZEROCLAW_MOCK_SCRIPT`, so bwrap agents can run without LLM calls. If the `SUBZEROCLAW_RECORD_SCRIPT` environment variable is set (any value), subzeroclaw records responses to `/workspace/.recorded_responses.json` inside the sandbox.

### Privilege modes

`privilege_mode` decides how much the HOST around the swarm must grant:

- **`:cgroup`** (default) - every sandbox is a `systemd-run --user` scope with kernel-hard limits (`MemoryMax` OOM-kills a runaway tree, `CPUWeight`, `TasksMax`) and per-agent cgroup telemetry (`systemd-cgtop`, `memory.current`). The price: the host (or the container the swarm runs in) needs systemd as PID 1 and `SYS_ADMIN` for delegated cgroups. Choose it on a DEDICATED box where you own the blast radius and want the hard guarantees.

- **`:rootless`** - **zero elevated capabilities**. The systemd scope is replaced by a small launcher applying `RLIMIT_AS` (from `memory_limit`) and `nice`; tree cleanup rides the sandbox's PID namespace + `--die-with-parent`. The Nix base's small directory/symlink forest is materialized into a private per-agent root and bound as `/` - **no fuse-overlayfs process, `/dev/fuse`, or nested kernel overlay mount**. This works on managed container backing filesystems that permit unprivileged user namespaces but reject overlayfs-in-userns. Choose it on SHARED or managed infrastructure (Kubernetes) where the pod/container is the hard security boundary and bwrap is defence-in-depth inside it; the pod then runs fully unprivileged and only needs permission to create user namespaces (a seccomp profile allowing `clone(CLONE_NEWUSER)`, or `hostUsers: false`).

  The honest trade-offs: memory is a per-process address-space cap (allocations fail) rather than a cgroup OOM kill; `tasks_max` is NOT enforced per agent (RLIMIT_NPROC counts per real UID, which all agents share - bound the aggregate at the pod level instead); no per-agent cgroup telemetry.

```elixir
%{
  name: :researcher,
  backend: {:bwrap, %{privilege_mode: :rootless, memory_limit: "32M", network: :isolated}},
  skills: ["web.md"]
}
```

Requirements: bubblewrap with unprivileged user namespaces enabled (`kernel.unprivileged_userns_clone = 1`, or the equivalent seccomp/`hostUsers` arrangement on Kubernetes), `/run/swarm` available (override the agents dir with the `:bwrap_agents_dir` app env), and pre-built sandbox base layers (`nix build .#sandboxBase-*`). `:cgroup` mode additionally requires systemd and fuse-overlayfs. Base layers are resolved from `/run/swarm/sandbox-base/<preset-name>` (plus any dirs in the `:extra_preset_dirs` app env), falling back to `base` when a preset is missing. For the NixOS setup, preset/base-layer internals, and overlay/cgroup details, see [containers.md](containers.md).

## Mock

The mock backend (`lib/genswarms/backends/mock_backend.ex`) spawns no external process at all. It is a stub: it accepts input (returning `:ok` and discarding it) and produces no output. Use it to exercise swarm orchestration — topology, routing, dynamic add/remove/scale — without any agent runtime or LLM cost.

```elixir
%{name: :worker, backend: :mock}
```

It also accepts an optional `script` (`{:mock, %{script: [...]}}`), but the backend only stores that script on its ref for introspection — it does **not** match against it or generate responses (`send_input/2` and `handle_output/2` are no-ops). The bare `:mock` form is what the test suite and examples use.

> Producing canned LLM responses (with a `match`/`response` script) is a feature of **subzeroclaw**, not of the `:mock` backend. To run *real* agents (local/docker/apple_container/bwrap) without calling an LLM, point them at a subzeroclaw mock script via the `SUBZEROCLAW_MOCK_SCRIPT` environment variable, or use `mix genswarms.test --mock script.json`. See [testing.md](testing.md).

## See also

- [configuration.md](configuration.md) — the swarm config DSL and how `backend:` fits in
- [containers.md](containers.md) — NixOS containers, tool presets, and bwrap base-layer internals
- [testing.md](testing.md) — using the mock backend with `mix genswarms.test`
- [troubleshooting.md](troubleshooting.md) — diagnosing backend startup and connection failures
