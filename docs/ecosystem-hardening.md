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
- [ ] Generated candidates cannot execute Elixir on the trusted host; evaluation
      objectives and held-out cases are owned by the evaluator.
- [x] Runtime task completion has one internal finalization route, documented
      at-least-once delivery, and recovery tests.
- [ ] A real-client TUI harness covers two turns and reconnect with pinned
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
  roles cannot be changed. **Not yet wired into the evolution runner**: the legacy
  generated-Elixir execution path must still be replaced before using evolution.
- Real OpenCode 1.18.28: the installed executable completes two tool-using turns
  through tmux, with disconnect/reattach between turns, using a local SSE provider
  fixture and an allowlisted environment/private HOME. The original readiness
  detector fails this test; recognition of the actual input+footer fixes it.
  This verifies runtime transport, not model quality. Claude/Codex full-turn
  executions remain unverified.
- Evaluator API added in Phylogenesis (three focused tests): compares bounded
  baseline/fixed/candidate JSON patches using an operator-owned runner and scorer.
  Expected answers reach only the scorer, reported candidate fitness is ignored,
  tasks run without links to the caller, and crashes/timeouts are failures.
  Reports separate training and held-out aggregates. These are deterministic
  fixture checks, not evidence of model/architecture quality improvements.
  Final holdout comparisons must not feed back into the evolution loop.

## Remaining integration work

1. Replace the legacy generated-.sim runner path with Candidate + evaluator.
   Prefer candidates delivered as JSON messages: no host reads of agent-chosen
   paths, no generated Elixir evaluation. Keep evaluator code/held-out answers
   out of generator mounts. Reduce the LLM fixer stage to deterministic schema
   validation once the data format is wired in; do not leave two competing paths.
2. Bound whole generations and per-run resources, classify timeouts as failures,
   retain generation artifacts, and test duplicate/stale generation messages.
3. Extend real-client fixtures to Claude/Codex. Codex custom-provider docs were
   checked at https://learn.chatgpt.com/docs/config-file/config-reference:
   custom providers support a base_url, wire_api=responses and
   requires_openai_auth=false. Use private fixture config, never user credentials.
   No Codex configuration was changed and no Codex full-turn fixture exists yet.
4. Read product-specific instructions before changes; test conversation/fake-chain
   recovery without live bot polling or funds. Preserve dirty product submodules.
5. Record exact local compatibility revisions, validate consumer pin changes in
   branches, and provide a repeatable bounded benchmark command.

Local commits so far: genswarms 552de3e + a4721c0; subzeroclaw ce1dbfb;
opencode-unhardcoded 6476b08; subzero-sim 17a703a; phylogenesis eae7711.
