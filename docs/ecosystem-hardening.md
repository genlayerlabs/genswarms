# Ecosystem hardening work log

Local implementation of the ecosystem review, started 2026-09-05.
Working branch: `codex/ecosystem-hardening` in genswarms, subzeroclaw,
subzero-sim, phylogenesis, opencode-unhardcoded, and genswarms-packages. Existing review changes
in genswarms and phylogenesis are preserved on these branches.

This is a chronological work log; the initial checkboxes below are historical.
Current stabilization status, acceptance and PR delivery order are tracked in
[ecosystem-stabilization.md](ecosystem-stabilization.md). Later commits have
implemented and tested the native package/database restart gate described as
pending in older entries below.

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
- [ ] Package/IR integrity: verified package bytes, complete Go/Elixir state
      conformance, and rejection of tampered digests/transparency records.
- [ ] Persistence contract: materialized desired IR survives an isolated database
      restart and reconstructs equivalent execution, not merely a config path.

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

The package/IR/persistence gates are central ecosystem requirements, explicitly
confirmed by the user; they are not optional follow-up work.

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
  `/home/jm/docs/genlayer/wingston-ecosystem-hardening` worktree.
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
  Removing implicit sibling selection and obsolete browser hot-loading made
  dependency resolution reproducible. Two dependency tests reproduce the old
  behavior and pass after the change. Seven focused scripts passed (real-DB
  dedup assertion explicitly skipped); sender rebind and slot-notice seams
  each passed four checks. The final harness also passes with the dotenv fix.
- Wingston implementation: `780d1c9`, engine gitlink `9c4f9a4`, runtime gitlink
  `ce1dbfb`. Full detail and runnable offline commands live in the consumer's
  `docs/ecosystem-hardening.md`. No paid provider, Telegram, Postgres service,
  dashboard upgrade, rebuilt image or deployment was exercised by this gate.

## Deterministic cgroup transport tests (2026-09-05)

- The intermittent cgroup failures were tests launching the real subzeroclaw
  without a provider key. A controlled startup comparison showed the empty-key
  process already closed after 200 ms while a dummy-key process remained alive
  (loopback endpoint, no turn or model call). A transient live unit was a false
  positive, not proof of a functioning transport.
- Backend lifecycle tests now run an explicit NUL-input echo fixture through
  the actual bwrap/systemd/FIFO stack and demand matching output frames. Input
  testing covers two turns; health also checks the stopped state. Cleanup runs
  after failed assertions, and unsupported infrastructure uses ExUnit skip tags.
  A test accepting any success or error was removed: it proved no contract.
- Focused backend: 35 passed, including the previously failing seed. Full suite
  with that seed: 725 tests, zero failures, five skips. Opted-in three-client TUI
  suite: 725 tests, zero failures, two platform skips.
- User subsequently authorized controlled use of existing Unhardcoded keys for
  real-provider verification. This does not authorize live bots, deployments,
  funds or user operations. Live provider verification is separate from the
  credential-free default suite.

## Real Unhardcoded verification (2026-09-05)

- Authenticated minimal completion: HTTP 200, exact requested marker, 30 tokens.
  The router reported USD 0.000012 for that call; this is not a price estimate
  or the total cost of later runtime checks. `/x/policy/templates` returned 404
  on this deployment; `/v1/models` advertised `profile:agent`, which was used
  without copying a raw policy from a different host version.
- The actual corrected subzeroclaw binary completed two tool-using turns through
  bwrap/systemd/FIFO with `network: :isolated` and the router-pinned socket.
  Host-side file checks observed 17 then 23; both replies and final health passed.
  A rerun of the durable `scripts/unhardcoded-smoke.exs` entrypoint also passed.
- The explicit manual script bounds client requests, output tokens and turn
  time, reads only the selected consumer key from an operator-provided env file,
  and cleans its private workspace. The ordinary test suite remains offline.
- The `sigma-policy-author` guide led to checking published capabilities first
  and using the advertised agent profile. These are live transport/tool checks,
  not a held-out product benchmark or evidence of bot/market behavior.
- MicroMarkets now has a separate worktree and `codex/ecosystem-hardening`
  branch at `/home/jm/docs/genlayer/micromarkets-ecosystem-hardening`.
  Core/runtime pins there are staged as working changes; product tests and a
  consumer commit are pending. The original dirty submodules were not changed.

## Package IR conformance (2026-09-05)

- Both `/home/jm/docs/genlayer/genswarms-packages` and
  `/home/jm/docs/genlayer/swarmidx` are present and inspected. The former owns
  the Go authoring/materialization client; the latter is the name-to-digest
  notary and signed transparency log, not a package blob store.
- Confirmed a compatibility bug: Go rejected bare `tmux`/`apple_container`
  references and silently dropped backend `opts`, `image` and `client` data.
  Losing options can change execution/isolation semantics. New table-driven
  tests failed before the fix. Commit `9c805ab` in genswarms-packages preserves
  the fields and mirrors Elixir execution-metadata validation, including
  explicit null versus absent options.
- Replaced the three-field conformance summary with complete parsed-state
  equality. Removed jq and the pipeline that suppressed Elixir failures.
  Four offline fixture runs now cover CLI-authored add/bump, group scaling,
  backend metadata, policies, object/agent config updates and swarm options.
  All pass, as do `go test ./...`, `go vet ./...`, and the Elixir script format
  check. This is semantic equality, not canonical JSON byte equality, and not
  a claim of exhaustive parity on every malformed input or overlay sequence.
- SQLite currently records `config_path` and `swarm_overlays`; executor
  `observed` is reconstructed from config. Full verified-package-to-database
  restart equivalence remains an explicit acceptance gate, not inferred from
  those tables or from successful pure folds. Swarmidx remains unmodified.

## Lossless database payloads (2026-09-05)

- Reproduced three failures before fixing the internal SQLite codec: backend
  tuples became lists, literal `~` strings/keys became atoms, and the same loss
  affected queued daemon commands. These were real persistence changes, not
  presentation differences. The codec now tags containers and atoms under a
  versioned JSON envelope; tag-shaped user maps/lists remain ordinary data.
- Six registry tests cover payloads, commands/results, legacy rows, literal
  strings not minting atoms, rejection of functions before a write, and an
  independent BEAM process reading the database. A runtime restart test checks
  the restored mock backend's actual script as well as its manager config.
  Focused registry/dynamic/daemon tests: 36 passed. Full suite: 732 tests,
  zero failures, five optional/platform skips (log:
  `/tmp/genswarms-ecosystem-persistence-suite.log`).
- Changed Elixir files were formatted. Repository-wide format checking still
  reports pre-existing formatting differences in unrelated files; those were
  not mass-reformatted. No development database was migrated or modified.
- Legacy records retain their old interpretation. Already-lost tuple/string
  information cannot be restored by guessing. CLI/API/daemons sharing a DB
  must upgrade together; an old engine cannot decode newly tagged records.
  Consumer pins still need the final coordinated runtime revision.
- This fixes the internal mutation/command payload transport, not the public
  IR format or the remaining self-contained desired-state persistence gate.
  Seed files are still required. Replay currently logs some failed/unknown
  events and continues; database write acknowledgement and replay failure
  semantics still need tightening before restart equivalence can be claimed.

## Runtime IR option preservation and policy (2026-09-05)

- Four regressions failed before the fix: local/bwrap options were discarded,
  resource/isolation/SSH/mock options did not survive IR translation, and both
  the runtime gate and native IR policy allowed forbidden host-path keys inside
  backend options. These keys were previously checked only in agent config.
- FromConfig now retains options for local/bwrap/mock/Docker/SSH, and ToConfig
  uses one option attachment path for all backends. It restores known execution
  keys and fixed JSON selectors, including `network: "isolated"`, in both
  backend options and agent config. Domain string keys remain strings. Apple
  refs with options but no image are refused rather than silently losing options.
- Policy checks now cover backend tuple options and IR `backend.opts` as well
  as agent config. A real SwarmManager mutation test verifies rejection before
  agent registration or overlay persistence. Operator-authored seeds retain
  their existing authority to declare these options.
- Final full suite: 738 tests, zero failures, five optional/platform skips;
  `/tmp/genswarms-ecosystem-ir-options-suite.log`. Changed files pass formatting
  and diff checks. All four Go/Elixir conformance fixture runs still pass.
- Remaining mapping audit: native package body/policy/handler resolution is not
  fully wired through ToConfig; provider override fields and structured option
  values (e.g. bind tuples after JSON serialization) need end-to-end coverage.
  These results prove the tested execution options and policy correction, not
  the outstanding complete native IR-to-runtime/persistence acceptance gate.

## Replay failure and object readiness (2026-09-05)

- SwarmManager changes replace repeated log-and-ignore branches
  with one error-returning replay path, validate unknown operations/malformed
  updates before boot, and clean started runtime nodes after a replay error.
  Start-success notification is no longer emitted before structural replay.
- New `overlay_replay_failure_test.exs` reproduced a readiness bug:
  ObjectServer acknowledges process creation before asynchronous handler init;
  an init returning `{:error, :fixture_rejected}` let recovery advance and startup
  return success. The failing assertion was preserved until implementation
  fixed it; it was not skipped or changed to accept the broken outcome.
- Recovery now uses OTP asynchronous status requests, without introducing a
  worker process per startup. Each seed object is checked before replay and each
  added/updated object before the next event. Pending startup callers receive
  success only at the end; callback failure, request failure and deadline expiry
  clean the runtime and return an error. Init callbacks can query the manager.
- Stop cancels pending readiness; stale timeout tokens cannot affect a later
  swarm incarnation. Cleanup does not query blocked object handlers. The stop
  call allows supervisor shutdown time instead of timing out at the same five
  seconds as a child's shutdown grace period. Native init exceptions/throws/exits
  become queryable error states, with opaque failure values omitted from logs.
- Focused recovery/dynamic/crash-containment run: 42 tests passed before adding
  the final log-redaction check. Final full suite: 748 tests, zero failures,
  five optional/platform skips; log `/tmp/genswarms-ecosystem-readiness-suite.log`.
  Changed Elixir files pass formatting and diff checks.
  The independent persisted-IR gate remains open:
  neither object readiness nor successful replay removes the seed-file dependency.

## Notary client trust and wire compatibility (2026-09-05)

- Worked directly in `/home/jm/docs/genlayer/genswarms-packages` and
  `/home/jm/docs/genlayer/swarmidx`, both on `codex/ecosystem-hardening`.
  New regressions reproduced malformed HTTP success bodies being accepted as
  an empty verified log, valid Python Unicode signatures rejected by Go,
  duplicate/zero sequence numbers accepted, and invalid public keys panicking.
- Gsp now rejects malformed/trailing/non-object JSON and invalid log envelopes,
  preserves signed JSON numbers, bounds HTTP responses and total fetched logs,
  and omits opaque server error bodies from CLI errors. Unicode escaping now
  matches Python's existing canonical representation, including DEL and
  non-BMP surrogate pairs. Server canonical bytes and historical entries were
  not changed. Both languages pin an identical public-fixture hash/signature.
- The log command fetches from genesis through every returned page, refusing
  non-progressing pagination; `--since` only filters display after successful
  verification. `--public-key HEX` verifies against an independently supplied
  key without fetching one from the endpoint. Without it, output explicitly
  identifies the server-advertised key as unauthenticated. Neither mode claims
  freshness or protection against split views/truncated signed prefixes.
- Verification: all Go packages pass `go test -race ./...` and `go vet ./...`;
  Django system checks and migration-drift check pass, and 41 tests pass using
  an isolated test SQLite database. A missing local `staticfiles/` warning is
  non-fatal. No live notary calls, signing keys, production DBs or deployments.
- Commits: gsp `675cc53`, swarmidx `80f572b`. This is not the complete package
  integrity gate: resolve/materialize/vendor still need authenticated binding
  of metadata to signed releases, and runtime package loading and self-contained
  persisted IR still need end-to-end verification. Concurrent notary appends
  also need a PostgreSQL-backed audit; SQLite tests do not prove that safety.

## Authenticated package resolution (2026-09-05)

- Reproduced the untrusted-resolution gap with a CLI regression: an altered
  `/v1/resolve` digest was accepted without fetching or checking a signature.
  Removed that client method rather than adding a second metadata authority
  to cross-check. Gsp now derives active releases directly from a verified
  log snapshot, including signed withdrawals and transitive exact-pin deps.
- `resolve`, `vendor` and `materialize --resolve` now require `--public-key`
  or `SWARMIDX_PUBLIC_KEY` from an independent trust channel. No implicit
  endpoint-key bootstrap or insecure fallback. Unsigned card/module metadata
  is excluded from resolution; `log_seq` is explicitly an unsigned locator,
  not a trusted checkpoint. Unknown operations, malformed signed metadata,
  forward dependencies and duplicate active releases are rejected.
- Authenticated IR resolution checks body/policy/handler slot roles and all
  existing digest pins before downloads. Removed the unused unauthenticated
  IR digest-filling helper, whose skip-pinned behavior did not provide that
  guarantee. Offline folding remains key/network-free and unchanged.
- Added `genswarms-packages/conformance/notary.py`: actual Go CLI publishing
  through the Django HTTP API, token authentication, Python dirhash/signing,
  SQLite persistence, resolution, IR materialization, transitive vendoring
  and on-disk rehash. Six scenarios pass, including Unicode paths, altered
  unsigned index records, signed withdrawals, wrong keys, tampered signatures,
  and IR pin/kind mismatches before writes. Uses public fixture credentials,
  a fresh in-memory test DB, temporary files and a loopback listener only.
- `go test -race ./...`, `go vet ./...`, diff/format checks, and all four
  complete parsed-state Go/Elixir conformance runs pass. Commit `bc4dae6`.
  No production notary, git source, signing key or deployment was used.
- Still open: vendoring path/symlink containment, local-source authority,
  failure atomicity and remote-git transport checks; PostgreSQL append
  concurrency; runtime package-byte/BEAM binding; self-contained persisted
  IR and equivalent restart. The new cross-process test proves the tested
  notary-to-vendored-bytes segment, not that entire remaining chain.

## Vendoring filesystem boundaries and preservation (2026-09-05)

- Four regressions failed before implementation: failed replacement deleted
  existing edited files, package symlinks copied external fixture bytes, a
  traversal ref wrote outside the vendor root, and a linked vendor lock
  redirected writes to another file. All targets were private test fixtures.
- Removed automatic delete/rebuild of existing packages. Unmodified entries
  are re-verified; changed entries fail and remain intact. New entries copy
  regular files into private staging, verify the staged bytes, and rename
  into place only on success. Package paths/entries and vendor destinations
  reject symlinks, special files and traversal. Lock writes are sorted and
  staged/synced/renamed rather than truncating an existing inode.
- Source and destination operations use Go 1.25 directory capabilities
  (`os.Root`). A rename-during-copy regression exposed `DirEntry.Info` reopening
  the old display path; metadata now uses the same opened root as content.
  Added `HashFS` sharing the existing digest algorithm, not a new hash format.
  Existing `HashDir` bytes and server signing/canonicalization are unchanged.
- Signed `local:` sources are no longer implicit host read authority.
  `--local-source-root DIR` grants access to an independently chosen subtree;
  no flag, an outside path or an escaping link fails. Remote Git transport
  remains a separate audit; this change does not claim to harden that process.
- Verification: all Go packages pass `go test -race ./...` and `go vet ./...`.
  Tests cover changed-file preservation, path and symlink escapes, FIFO refusal
  without opening it, hardlinked lock preservation, confined hashing parity,
  staging cleanup and renamed source directories. Eight actual CLI/Django
  scenarios pass using only loopback and a fresh test DB. Four Go/Elixir IR
  fixture comparisons pass. Windows amd64 and Darwin arm64 cross-builds and
  Windows vendorer test compilation pass; no execution on those OSes claimed.
- Commit `08c79f8`. Remaining installation gate: a batch is still incremental,
  so earlier new packages can remain if a later dependency fails. Concurrent
  writer coordination and crash/power-loss recovery are not established.
  Server-side local-source authority and concurrent log appends also remain
  to audit. Package-to-BEAM binding and self-contained IR/DB restart are still
  explicit acceptance gates, not inferred from these filesystem tests.

## Public IR serialization and runtime translation (2026-09-05)

- Rechecked the actual DB/start path before attempting persistence. SQLite
  still stores `config_path` plus legacy overlays, not the native seed or a
  self-contained desired-state checkpoint. Current restart re-evaluates the
  config file. Persisting FromConfig's old output would have lost provider
  settings and turned a handler package map into a bogus `module:%{...}` ref.
  Two regressions reproduced those losses before implementation.
- FromConfig/ToConfig now retain `endpoint`, `request_extra`, `compact_extra`
  through agent overrides and preserve package handler ref/digest plus explicit
  `handler.opts.path/mode`. Default verify mode remains explicit on translation;
  unsupported load modes fail. A real object-runtime test converts through
  public JSON, invokes the loader, receives the actual handler init probe and
  observes the same native package identity afterward.
- `State.to_map/1` and `Ref.to_map/1` serialize the public JSON shape, preserving
  all parsed state fields, policy wrappers, native refs and null ref options.
  This is not the internal term-v1 codec and does not pretend arbitrary DSL
  tuples, functions or typed domain values are portable JSON checkpoints.
- Removed silent fallback of unsupported body/policy slots to empty skills or
  default models. Those translations now fail explicitly until real package
  data loading is wired. Executor translates every agent/object spec before
  any plan effect, reports only the failing action position, and stops a
  restart if removal fails. Preset conversion no longer creates unknown atoms.
  Preflight is not a transaction over failures after valid actions start.
- Final full suite: 757 tests, zero failures, five optional/platform skips;
  `/tmp/genswarms-ecosystem-ir-serialization-suite.log`. The first broad run
  lacked jq and failed 12 wrapper setup checks; rerunning with jq/socat supplied
  passed without skipping those checks. Changed Elixir files pass formatting.
- Extended gsp conformance to serialize Elixir's fold, round-trip it through
  the actual Go CLI, and compare every parsed field again. All four fixtures
  pass in both directions, including provider and handler-loader metadata.
  Engine commit `5947570`, gsp harness commit `d00b75a`.
- No seed/checkpoint table or file-independent restart entry point has been
  added yet. Next persistence work must wire actual startup/recovery and prove
  a fresh process can restore the same desired swarm without its original
  config file. Native body/policy loading, typed option transport, runtime
  package/BEAM provenance and durable mutation acknowledgements remain open.
