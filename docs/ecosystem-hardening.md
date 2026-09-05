# Ecosystem hardening work log

Local implementation of the ecosystem review, started 2026-09-05.
Working branch: `codex/ecosystem-hardening` in genswarms, subzeroclaw,
subzero-sim, phylogenesis, and opencode-unhardcoded. Existing review changes
in genswarms and phylogenesis are preserved on these branches.

## Acceptance gates

- [x] Subzeroclaw compaction survives user turns, failure, and normal shutdown; tool-call
      alias compatibility is included; real-loop tests use a local fake endpoint.
- [x] OpenCode plugin uses its typed SDK compaction API, recovers from failures,
      and has regression tests for duplicate events and concurrent triggers.
- [x] SubzeroSim and Phylogenesis compile against the current engine; normal
      deterministic tests cannot accidentally invoke a live LLM.
- [x] Generated candidates cannot execute Elixir on the trusted host; evaluation
      objectives and held-out cases are owned by the evaluator.
- [x] Runtime task completion has one internal finalization route, documented
      at-least-once delivery, and recovery tests.
- [x] A real-client TUI harness covers two turns and reconnect with pinned
      client versions; unavailable credentials/services are reported distinctly
      from successful execution.
- [ ] Conversation and fake-chain product flows have repeatable failure/recovery
      checks; no live bot polling, payments, settlements, or deployments.
- [ ] A reproducible compatibility manifest and bounded evaluation compare a
      simple baseline, a fixed architecture, and candidates at equal budgets.
- [ ] Consumer contracts and documentation agree; only demonstrated duplication
      or unused machinery is removed.

## Verification already established in review

- Genswarms: 718 tests, 0 failures, 2 skipped with `nix shell nixpkgs#jq --command mix test`.
- TUI-focused suite: 57 tests, 0 failures, 2 skipped; existing real-client smoke
  tests only invoke `--version` and do not establish full-turn behavior.
- Subzeroclaw: 31 tests pass; they do not execute the complete agent loop.
- Phylogenesis selector: regression test fails before the duplicate generator
  dispatch removal and passes afterward; whole pipeline compilation was blocked.
- OpenCode plugin: typecheck passed despite a nonexistent optional SDK method;
  the reproducer exceeded the compaction threshold with zero HTTP requests.

This log records completed evidence as work progresses. A checked gate requires
its stated result; scaffolding or an unavailable live service is not completion.

## Implementation evidence

- Subzeroclaw: 31 unit tests and six real-executable, loopback-only integration
  tests pass. Compaction state now belongs to the session; snapshots include
  tool replies; failed HTTP and empty seals retain history. Normal EOF cancels
  and reaps pending work and removes its private temporary files. HTTP transport
  uses curl argv and private header files, with no interpolated host shell;
  endpoint metacharacters cannot execute a host command (regression-tested).
  Abrupt SIGKILL cleanup is not guaranteed and is not covered by this result.
- OpenCode: seven SDK-backed tests and typecheck pass. Uses session.summarize,
  typed toast bodies, bounded duplicate-message bookkeeping, and request-owned
  concurrency guards (a completion event cannot release a pending request).
- Genswarms: 719 tests, zero failures, two platform skips after extracting the
  shared turn finalizer. Typed replies no longer pass through the Port grammar;
  literal sentinels and routing-looking text stay data. Existing receipt ACK and
  readiness ordering remain in place. Delivery is not exactly-once persistence.
- SubzeroSim: current engine namespace restored. All 124 tests pass
  without starting runtime applications or opening the user's DETS files.
  Backend validation delegates to the engine instead of maintaining a stale
  second list. Added compile/parse checks for 16 backend shapes, with no launches.
- Phylogenesis: test config restored; full compilation works. Six selector tests
  pass. Failed/timeout runs cannot win, empty generations are safe, objectives
  are evaluator-configured (including minimization), and crowding uses normalized
  objective distances rather than evenly spaced scalar fitness.
- Candidate data decoder: four focused tests pass for bounded JSON patches to
  explicitly mutable roles. Backend, paths, budgets, metrics and immutable judge
  roles cannot be changed. Now wired into the default evolution runner; generated
  Elixir loading, file polling, fixer stages and memory-agent stages were removed.
- Real OpenCode 1.18.28: the installed executable completes two tool-using turns
  through tmux, with disconnect/reattach between turns, using a local SSE provider
  fixture and an allowlisted environment/private HOME. The original readiness
  detector fails this test; recognition of the actual input+footer fixes it.
  This verifies runtime transport, not model quality. Claude/Codex now have the
  equivalent full-turn fixtures described below.
- Evaluator API added in Phylogenesis (three focused tests): compares bounded
  baseline/fixed/candidate JSON patches using an operator-owned runner and scorer.
  Expected answers reach only the scorer, reported candidate fitness is ignored,
  tasks run without links to the caller, and crashes/timeouts are failures.
  Reports separate training and held-out aggregates. These are deterministic
  fixture checks, not evidence of model/architecture quality improvements.
  Final holdout comparisons must not feed back into the evolution loop.

## Remaining integration work

1. Migrate Phylogenesis's historical dashboard/reporting consumers from generated
   .sim paths and fixer stages to retained candidate reports. README/CLAUDE now
   state this limitation; the new evolution/prepare/init entry points are wired.
2. Verify a full supervised evolution cycle with deterministic generators, beyond
   the separately verified object pipeline and actual child-swarm/Gateway cycle.
   Abrupt BEAM loss can leave external work: report replay is not exactly-once.
3. Keep pinned real-client fixtures in the verification matrix when upgrading
   clients. All three now pass; no user login/configuration was changed.
4. Read product-specific instructions before changes; test conversation/fake-chain
   recovery without live bot polling or funds. Preserve dirty product submodules.
5. Validate consumer pin changes in branches against ecosystem-compatibility.json.
   The bounded benchmark command is now executable, but only a deterministic
   contract fixture; independent product-quality comparisons remain necessary.

## Data-only pipeline verification (2026-09-05)

- Genswarms: 721 tests, zero failures, three skips. Normal test application
  startup no longer auto-loads the developer's .env. Stop typespec now matches
  its existing {:ok, config_path_or_nil} return, discovered by the real child test.
- SubzeroSim: 126 tests pass. Deadline returns an error; Gateway accepts only
  Tick's start and the first valid final result, including null. A supervised
  owner prevents short-lived evaluator processes from closing shared DETS tables.
  This fixes an observed flaky table-write failure, not just a hypothetical race.
- Phylogenesis: 22 tests pass. Operator-owned evaluation config is required before
  startup. Generators send bounded JSON patches; the runner sees training cases
  only. Coordinator checkpoints restore missing slots/exact pending batches;
  completed report replay does not reevaluate, conflicts halt visibly, stale and
  duplicate messages do not advance generations. Generation/evaluation deadlines
  are bounded. Cleanup runs outside case tasks, including after timeout.
- The actual child runtime test starts local OTP components with mock agents,
  routes a deterministic object's final result through Gateway and stops the
  child. It verifies step caps, timeout errors, cleanup and unsafe-ID/backend
  rejection without credentials, providers, containers or a web listener.
- Removed 2,131 net lines in the Phylogenesis pipeline commit, including unused
  fixers/memory and the old phylo.test command whose missing mock fixture could
  fall back to a paid API. No experiment data was deleted.
- Reproducible no-provider check from Phylogenesis:
  `mix run --no-start examples/evaluator-contract/compare.exs -- /tmp/new-report.json`.
  The output must be new; it retains candidates, equal limits and train/holdout
  aggregates. Observed baseline=0, fixed=1, self-grading candidate=0 on held-out
  exact-match scoring. This demonstrates evaluator separation, not product gains.

Latest implementation commits: genswarms 8446460; subzeroclaw ce1dbfb;
opencode-unhardcoded 6476b08; subzero-sim bccd843; phylogenesis 3a6f125.

## Complete TUI transport fixture (2026-09-05)

- Codex 0.153.4 and Claude Code 2.1.260 each complete two actual tool-using turns
  and disconnect/reattach to the same client through the real tmux adapter.
  Codex uses local Responses SSE; Claude local Messages SSE. Receipts are written
  by the client's shell executor, never directly by the fixture server.
- Claude's forced screen-reader mode displays `$`; the previous generic prompt
  recognizer never considered it ready. The unit reproducer and real-client test
  failed before the adapter fix and pass after it. Bare shells still do not match.
- Codex's obsolete `untrusted` approval option is rejected before launch,
  matching the pinned executable's supported `on-request`/`never` flags.
- Shared workspace/environment/receipt/reconnect assertions replace duplicated
  harness logic. Combined adapter + three real-client tests: 9 passed.
- Full opted-in suite: 724 tests, zero failures, two platform skips. TUI source
  revision: 3b30131830d1f809801734625ce70d3039ebb066.
- Private fixture homes, no inherited provider credentials, integrations disabled
  and loopback-only model providers. Proxy configuration is not a claim of OS
  isolation; this is transport evidence, not model-quality or sandbox evidence.

## Consumer verification in progress (2026-09-05)

- Wingston has its own `codex/ecosystem-hardening` branch in the separate
  `../.. /genlayer/wingston-ecosystem-hardening` worktree (without the space).
  The original checkout and its dirty engine submodule remain untouched.
- Loading a swarm still imported `.env` despite `load_dotenv: false` at startup.
  A two-case regression demonstrates disabled loading and the enabled default;
  the loader now honors the same setting as the application. Focused loader
  suite: 10 tests passed.
- Latest broad core reruns: 726 tests, five skips, respectively two and one
  cgroup-start failures in `BwrapBackendTest`. All 36 backend tests passed alone.
  This intermittent full-suite failure is not declared fixed or hidden by skips.
- Wingston's original mock config attested Telegram 0.4.3 while its dependency
  and live config pinned 0.4.5. The harness reproduced a digest rejection;
  aligning the test pin restored all checks with the corrected engine.
  Offline sender/replay tests and reproducible dependency selection are ongoing.
