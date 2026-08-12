---
description: Troubleshoot GenSwarms — fixes for agents that won't start, messages not routing, and common backend issues.
---

# Troubleshooting

Common problems running GenSwarms and how to fix them. Most issues fall into agent startup, message routing, backend setup, task delivery, or the API server.

Before digging in, two commands surface most problems:

```bash
genswarms status [name]          # Swarm/agent lifecycle state
genswarms events --errors        # Recent error events across all swarms
```

## Agent not starting

1. Confirm the `subzeroclaw` binary is reachable. The bwrap backend searches in this order: explicit config (`subzeroclaw_path`), `../subzeroclaw/subzeroclaw` (a sibling checkout), the `SUBZEROCLAW_PATH` env var, then `PATH`. If none resolve to a regular file, the agent fails to start.
2. Verify your LLM provider key is set (`SUBZEROCLAW_API_KEY`), since agents need it to call the model. (If you are running without an LLM for testing, set `SUBZEROCLAW_MOCK_SCRIPT` instead so subzeroclaw returns canned responses.)
3. Inspect the swarm and agent state:

```bash
genswarms status example-swarm
genswarms logs example-swarm researcher
```

## Messages not routing

1. Make sure the topology allows the edge `source -> target`. The `Router` only routes along configured topology edges (system objects `:metrics`, `:tick`, and `:gateway` are always allowed without an explicit edge).
2. Check the agent is emitting the correct `@agent:` syntax, for example `@coder: please implement this`. Use `@all:` to broadcast to all connected agents.
3. Review the message log (the `limit` query param defaults to 100):

```bash
curl http://localhost:4000/api/swarms/example-swarm/messages
curl "http://localhost:4000/api/swarms/example-swarm/messages?limit=20"
```

4. As an alternative to `@agent:` syntax, agents can drop a JSON file (`{"to":"target","content":"msg"}`) into `{workspace}/.outbox/`; the LogWatcher polls that directory and routes it. Inside a container, the `swarm-msg send <target> <msg>` helper writes these files for you (it JSON-encodes the message and writes it into `/workspace/.outbox/`).

## SSH backend fails

1. Confirm key-based SSH works first: `ssh user@host` should connect without a password prompt.
2. Verify the remote `subzeroclaw` path is correct on the target host. On NixOS machines the backend defaults to skills at `/var/lib/subzeroclaw/skills` and runs the agent as the `subzeroclaw` user (via `sudo -u`); for non-NixOS hosts set `nixos: false` in the backend opts so it uses `~/.subzeroclaw/skills` and runs as the login user.
3. Ensure the remote skills/workspace directory is writable for the SSH user — skills are copied over via SFTP at startup.

## Docker backend fails

1. Check the Docker daemon is up: `docker ps`.
2. Confirm the agent image exists: `docker images`. Build images with `nix build .#agentContainer-<preset>` and `docker load < result` (presets: `base`, `web`, `code`, `data`, `python`, `node`, `full`). If the expected image is missing, the backend tries to build it via `nix` and otherwise falls back to `szc-agent-base:latest`.
3. Inspect a container's logs directly. GenSwarms names containers `szc-{swarm}-{agent}`:

```bash
docker logs szc-example-swarm-coder
```

4. Containers are run with `--rm`, so a crashed agent leaves no container behind. Catch the failure in the event log instead:

```bash
genswarms events --category backend
```

## Tmux agent is stuck at `starting`, `blocked`, or `needs_attention`

1. Confirm host-side tmux is installed with `tmux -V`. For `runner: :host`, also
   run `codex --version` (or `claude --version` / `opencode --version`) on the
   host. For an isolated runner, inspect the `runner` object returned by the
   session endpoint and use the checks below.
2. Fetch the exact session metadata and attach command:

```bash
curl http://localhost:4000/api/swarms/<swarm>/agents/<agent>/session
tmux -L genswarms attach-session -r -t genswarms-<swarm>:<agent>
```

   Remove `-r` only when you intend to answer a trust/permission prompt or steer
   the client. Detach with `Ctrl-b d`; the pane continues running.
3. `blocked` means the visible tail resembles a trust or permission prompt.
   Resolve it manually or interrupt the current turn with:

```bash
curl -X POST http://localhost:4000/api/swarms/<swarm>/agents/<agent>/interrupt
```

4. `needs_attention` means GenSwarms found an unacknowledged turn, an invalid
   completion receipt, or uncertain `send-keys` delivery. Inspect
   `<workspace>/.genswarms/turns/<swarm>/<agent>/<turn-id>/`. Preserve the turn
   directory while diagnosing it: `task.md` is the durable request, `reply.md`
   plus `done.json` is the completion, and `ack.json` proves GenSwarms handled
   it. A completed but unacknowledged turn may be delivered again after restart.
   `attention_reason: "nudge_not_submitted"` means the exact nudge remained at
   the active cursor after the backend's one Enter-only retry; the task text was
   not duplicated.
5. If the TUI prompt is not recognized, update its adapter pattern. Use
   `quiet_ready_fallback: true` only for a trusted, known client screen; a quiet
   terminal is not proof that a TUI is ready.
6. A bwrap pane uses a short `xargs` parent command while the actual client runs
   below it. If startup reports an argv-manifest or `xargs` error, confirm GNU
   `xargs` is available on the host and that
   `<state_dir>/.genswarms/host-launch.argv0` is a regular mode-0600 file. Do not
   print that manifest into a shared log.

For `runner: :docker`:

```bash
docker inspect gstui-<swarm>-<agent>
docker exec gstui-<swarm>-<agent> codex --version  # client_source: runtime
docker exec gstui-<swarm>-<agent> "$(readlink -f "$(command -v codex)")" --version  # host_nix
```

The container image must contain the client when `client_source: :runtime`.
With `client_source: :host_nix`, the host client must resolve into `/nix/store`
and `nix-store --query --requisites <store-root>` must succeed. A
`container_identity_mismatch` means a persistent same-named container was
created with a different image/mount/network/resource contract; explicitly stop
the agent to destroy it, then start with the new config. An environment mismatch
reports only the variable name, never its value.

For `runner: :bwrap`, confirm `bwrap` and `/run/swarm/sandbox-base/base` exist.
Rootless TUI panes have no virtual-address limit by default; an explicit small
`memory_limit` becomes `RLIMIT_AS` and may crash JS clients such as OpenCode even
when their resident memory is modest. Explicit cgroup mode defaults to a `2G`
hard limit. The sandbox lives at
`/run/swarm/agents/gstui-<swarm>-<agent>` and is removed after an explicit
destroy or a failed fresh preparation.

`network: :none` is a full cutoff and will also break cloud model calls.
`network: :isolated` intentionally fails for interactive TUI runners because
the existing LLM-only forwarder is specific to subzeroclaw. Docker supports
`:open`, `:none`, or a named network; bwrap supports `:open` or `:none`.

## Apple container backend fails

1. Confirm the `container` CLI is installed and the service is running:

```bash
container system status --format json
container system start
```

2. Confirm the image exists in Apple's local image store:

```bash
container image inspect szc-agent-code:latest
```

Build preset images with `nix build .#agentContainer-<preset> -o result`. Current Nix container outputs are Docker archives; Apple `container image load` expects an OCI archive. Convert or publish the image before loading it into Apple's image store, for example:

```bash
docker load -i result
skopeo copy docker-daemon:szc-agent-base:latest oci-archive:szc-agent-base-oci.tar:szc-agent-base:latest
container image load --input szc-agent-base-oci.tar
```

The backend tries the build/load path when an image is missing, but a failed build, missing Nix, or incompatible archive leaves the final image error to `container run`.

3. Inspect a container directly. GenSwarms names Apple containers `szc-{swarm}-{agent}` unless `container_name` is set:

```bash
container inspect szc-example-swarm-coder
container logs -n 50 szc-example-swarm-coder
```

4. If the error is `{:unsupported_network, :isolated}`, the backend is refusing to run with open network. Apple `container` does not currently expose the egress-forwarding semantics GenSwarms uses for Docker/bwrap isolation; use Docker or bwrap for agents that require `network: :isolated`.

5. Pause/resume is Docker-only. Apple `container` agents keep running when you call the pause/resume endpoints or Mix tasks.

## Tasks not delivered to daemon swarms

Daemon swarms (started with `genswarms start`) receive tasks through a SQLite-backed queue, not directly. The daemon polls the queue every 500ms.

1. Confirm the daemon is actually running: `genswarms status`.
2. Look for queued/processed task activity in the event log:

```bash
genswarms events --category agent
```

3. Inspect the queue itself in `.genswarms/swarms.db` (the `tasks` table) to confirm rows are inserted with status `pending` and later flipped to `processed`.
4. Check for errors:

```bash
genswarms events --errors
```

> Valid `--category` values: `backend`, `routing`, `agent`, `object`, `swarm`, `system`. Add `-s <swarm>` to scope to one swarm. `genswarms events` performs a one-shot query and prints the matching events (default limit 50); it does not continuously tail.

## API returns errors

1. Confirm the API server is up (the root path returns API info):

```bash
curl http://localhost:4000/
```

2. If a browser frontend is failing, CORS is already permissive on the API server (`origins: "*"`, all methods and headers allowed), so a CORS rejection usually points to a wrong URL or the server being down rather than a CORS policy.
3. Read the server output for the detailed error; start it in the foreground with `mix phx.server` while debugging.

## Cleaning up stuck state

If swarms are left in a `stopped` or `crashed` state, or the database accumulates stale rows, clean them up via the mix task:

```bash
mix genswarms.clean          # Remove stopped/crashed swarm entries and their files
mix genswarms.clean --all    # Also clear the event log
```

> The `clean` operation is not exposed as an escript subcommand — `genswarms clean` is not a recognized command and will error. Use the `mix genswarms.clean` task or the API route below.

Via the API, `POST /api/swarms/clean` removes stopped/crashed swarms (add `?all=true` to also clear the event log). To remove a single swarm and all of its data, `DELETE /api/swarms/:name?purge=true` stops the swarm and deletes its files, events, and queued tasks.

## See also

- [CLI reference](cli.md)
- [Backends](backends.md)
- [Observability](observability.md)
