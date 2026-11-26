# Verification

Two layers, both checked into the repo.

## Property tests (`test/property/`)

Random-input tests against the real code. They run with the normal suite:

```bash
mix test test/property                      # 100 random cases per rule
PROPERTY_RUNS=200000 mix test test/property # long run, fixed count
PROPERTY_SECONDS=90 mix test test/property  # long run, fixed time per property
```

| File | Rule |
|------|------|
| `router_property_test.exs` | A message is routed only along an edge that exists at that moment |
| `agent_protocol_property_test.exs` | Agent output never crashes the parser or invents a target |
| `swarm_config_property_test.exs` | Validation never crashes; what it accepts is consistent |
| `egress_guard_property_test.exs` | An isolated agent is only ever pinned to an allowlisted host |
| `task_queue_property_test.exs` | The SQLite queue returns exactly the unprocessed tasks, in order |
| `swarm_lifecycle_property_test.exs` | Manager config, router edges and live processes always agree |

A test tagged `:known_bug` states a rule the code does not keep yet; such tests
are excluded by default (`--include known_bug` runs them). There are none today.

## TLA+ model (`verification/tla/`)

`SwarmDaemon.tla` models the daemon, the SQLite registry row and the task queue
for one swarm. `Fixed = FALSE` is today's code, `Fixed = TRUE` a proposed design
(per-swarm process lock, claim-before-deliver, failed state for undeliverable
tasks, pid-guarded status writes).

| Config | Expected result |
|--------|-----------------|
| `Current.cfg` | `OneLiveDaemon`, `AtMostOnce`, `RowTracksDaemon` all violated |
| `CurrentLiveness.cfg` | no errors (before the missing-agent fix, `EveryTaskResolved` was violated) |
| `Fixed.cfg` | no errors |
| `FixedLarge.cfg` | no errors; takes long, meant for a big machine |

The model is a design check, not a proof about the Elixir code: it only helps
while its actions match what the code does.

## Long run

```bash
scripts/verify.sh          # TLC on Fixed + FixedLarge, then property tests at 200000 runs
TLC_WORKERS=8 TLC_HEAP=64g scripts/verify.sh tla
```

Needs `java` for the models and either `mix` or `docker` for the tests.

`scripts/verify-shard.sh` runs one short, self-contained job (one test file with a
seed, or one model size) and prints a single `SHARD_RESULT` line, for fanning
many jobs out across machines.
