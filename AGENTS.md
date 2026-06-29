# AGENTS.md

Guidance for coding agents working in this repository.

## Project Shape

Genswarms is an Elixir/OTP orchestrator for swarms of `subzeroclaw` agents. It
has pluggable backends under `lib/genswarms/backends` (`:local`, Docker, Apple
`container`, SSH, bwrap, mock), directed topology routing, per-agent skills,
file inbox/outbox messaging, deterministic objects, a Phoenix JSON API, and a
SQLite-backed daemon registry.

Use `CLAUDE.md` as the longer quick-reference and `docs/` as the source of
truth for user-facing behavior.

## Commands

Use the narrowest relevant command while iterating, then broaden before
finishing.

```bash
mix deps.get
mix format
mix test
mix test test/path/to/file_test.exs
mix escript.build
mix phx.server
```

Container image builds use Nix:

```bash
nix build .#agentContainer-base
nix build .#agentContainer-code
docker load < result
```

## Runtime Contracts

- Backends implement `Genswarms.Backends.BackendBehaviour`.
- `AgentServer` selects backends through `Genswarms.Config.SwarmConfig`.
- Container backends must preserve the agent runtime contract:
  skills at `/skills`, logs at `/root/.subzeroclaw/logs`, workspace at
  `/workspace`, topology/env routing, and `subzeroclaw` protocol translation
  through `priv/szc-wrapper-fifo.sh`.
- Never pass untrusted config through a host shell. Build host commands as argv
  lists. A container-local `sh -c` is acceptable only for the container bootstrap
  and must keep untrusted values out of the script body.
- Preserve secret handling and redaction. Do not print API keys or raw secret
  env values in logs, tests, docs, or final reports.
- `network: :isolated` is supported for Docker and bwrap. Apple `container`
  must fail closed unless equivalent isolation semantics are actually available.
- Do not fake unsupported backend features such as Apple `container`
  pause/unpause.

## Configuration And IR

Supported backend config forms include:

- `:local`
- `:bwrap` and `{:bwrap, opts}`
- `:mock` and `{:mock, opts}`
- `{:docker, image}` and `{:docker, image, opts}`
- `:apple_container`, `{:apple_container, image}`, and
  `{:apple_container, image, opts}`
- `{:ssh, host}` and `{:ssh, host, opts}`

When changing config shapes, also update validation, `backend_module/1`,
`backend_config/1`, REST parsing/formatting, CLI/status formatting, IR
round-trip mapping, and docs.

## Testing Expectations

- Add focused tests for behavior changes.
- For backend argument builders, test argv shape and command-injection safety.
- For config/API/IR changes, test parsing, validation, module/config mapping,
  and round trips.
- Platform-specific integration tests should skip cleanly when required tools or
  services are unavailable.
- Before claiming completion, run `mix format` and the relevant tests. For broad
  changes, run `mix test`.

## Working Notes

- Prefer existing local patterns over new abstractions.
- Keep changes scoped; avoid unrelated formatting churn.
- The worktree may contain user changes. Do not revert changes you did not make.
- Runtime artifacts such as `.genswarms/`, `.test-logs/`, image tarballs, and
  `.context/` files should not be committed unless explicitly requested.
