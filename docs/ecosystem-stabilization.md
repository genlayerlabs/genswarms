# Ecosystem stabilization

Started 2026-09-05. The user merges the PRs and communicates with consumer teams.
No merges, deployments, live bot polling, or team messages are part of this work.

## Order and acceptance

1. Inventory: preserve the initial branches, commits and dirty paths in
   `ecosystem-inventory-2026-09-05.json`. This is a historical snapshot, not a
   claim that local branches are deployed or that cached remote refs are current.
2. Core: Genswarms/IR, gsp and swarmidx. Review pending changes, run relevant
   suites and the signed-package → vendoring → execution → independent SQLite
   restore conformance test. Include subzeroclaw's required runtime changes in
   the core dependency chain. Open reviewable PRs with exact validation results.
3. Consumers: MicroMarkets and current Wingston, then direct integrations that
   need changes. Pin tested runtime revisions; preserve unrelated worktrees.
   Consumer PRs must name the core PRs they depend on. Diagnose MicroMarkets's
   existing mock-resolution test failure before changing its package versions.
4. Simulation/evolution: SubzeroSim, Phylogenesis and the OpenCode adapter.
   Verify deterministic behavior, failure/recovery and full supervised cycles.
   Model-quality experiments and new product features are a later workstream.

Each completed stage records commits, commands, results, limitations and PR URLs.
Draft dependent PRs may be prepared before upstream merges, but are not declared
ready until their dependency and consumer checks are satisfied.

## Package version audit

Read-only live audit on 2026-09-05 found Telegram and telegram-editor 0.6.5 in
swarmidx (published 2026-08-21); GitHub main equals the 0.6.5 tag. GitHub Releases
still lists 0.6.2. Current Wingston pins 0.6.5; MicroMarkets and the separate local
Telegram development checkout use 0.6.2. Tag 0.6.3 is absent from the returned
notary history, while 0.6.4 and 0.6.5 are present. No republishing is needed to
consume 0.6.5. Telegram's open PRs #41 and #42 are not part of that release.

`gsp log --endpoint https://swarmidx.ygr.ai` verified 127 returned entries against
the server-advertised key, not an independently authenticated key. This is an
inventory observation, not an authorization to install or proof of freshness.

## Initial evidence and open items

- Core starts at `f6103d7`; a fresh focused run passed 23 native IR/persistence/
  package tests. Prior logs record 770 broad tests with zero failures and five
  skips before the last loader adjustment. Reverify the final PR revision.
- Gsp has uncommitted batch installation/recovery and Git transport changes;
  swarmidx has uncommitted source restrictions and PostgreSQL append locking.
  Prior logs are supporting history; final checks must exercise reviewed code.
- MicroMarkets's latest prior broad run: 15 properties, 3452 tests, one failure,
  25 skips. `MockResolutionGuardTest` misses the expected refusal event.
- Current Wingston has uncommitted dependency and attestation integration;
  the earlier hardening worktree is historical, not the integration target.
- The older `ecosystem-hardening.md` is chronological. Its unchecked initial
  gates and the compatibility manifest lag newer native persistence/package
  commits; update the manifest after final validation, rather than treating
  the old checklist as current evidence.

## PRs and final validation

Core validation on 2026-09-05:

| Component | Revision | Validation |
| --- | --- | --- |
| Genswarms | `31c4ed5` | 771 tests, zero failures, five optional/platform skips; seed 968530. All three opted-in real TUI fixtures pass separately; escript build passes. Changed Elixir files pass formatting. |
| Subzeroclaw | `8684b8b` | 32 unit tests and six real-executable loopback integration tests pass. |
| Gsp | `58e6d73` | `go test -race ./...`, `go vet ./...`; Windows amd64 and Darwin arm64 cross-builds, Windows vendorer test compilation. |
| Swarmidx | `f366b49` | Checks and migration drift pass; 45 tests on SQLite (one PostgreSQL-only skip) and all 45 on an isolated PostgreSQL 17 cluster. |
| Cross-repository | Above revisions | Four complete Go/Elixir IR fixtures in both directions; nine CLI/Django scenarios including body/policy/handler execution and independent BEAM restore after deleting the JSON seed. |

The first broad core run exposed a scale-down assertion racing Registry's
asynchronous DOWN cleanup. The corrected test checks that the original child
PIDs are dead immediately after scaling, then waits for Registry removal; it
does not relax the synchronous child-termination assertion. The same full-suite
seed passes after the change. Native persistence/package tests also passed a
fresh 23-test focused run before this final broad check.

The engine and runtime now have PR CI test workflows. Gsp CI runs the race
detector; swarmidx CI runs both SQLite and PostgreSQL to exercise append locking.
CI outcomes will be recorded separately from local evidence.

The compatibility manifest pins executable revisions; subsequent documentation
commits do not change those tested source bytes. Core PR URLs pending creation.
