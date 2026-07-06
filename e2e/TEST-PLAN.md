# Genswarms e2e test plan — real swarms, all features

The written, exhaustive map of what must be tested with swarms that **actually
run** (bwrap + router paying, no mocks). Built from a full sweep of the engine
(2026-07-06). Each row is a scenario; every scenario asserts an **invariant
property of real execution**, never non-deterministic LLM text.

Format: scenarios live in `e2e/features/*.feature` (Gherkin). Implemented ones
run via `mix run e2e/run_features.exs`; `@todo` features are the coverage gaps
— specs written, steps pending, rendered as PENDING so the map is always in
front of us. As we implement, an `@todo` file loses its tag and its steps get
bound in the runner.

Status legend: ✅ implemented+passing · 🟡 partial · ⬜ spec-only (@todo)

## Current status (2026-07-06) — ALL 10 FEATURES IMPLEMENTED
**38 scenarios implemented and passing on real swarms.** Every feature file is
implemented (no `@todo` left); each scenario asserts an invariant of real
execution:
- ✅ engine_core (4) — ask #79, overlay #78, cache #75 (real bwrap+router)
- ✅ scheduling (2) — real cron seed job fires + fail-closed
- ✅ lifecycle (5) — overlay replay, snapshot coherence, sync rollback, scale
- ✅ security (11) — auth, config gate, loader, secrets, endpoint policy
- ✅ messaging (4) — topology routing, dynamic edges, broadcast
- ✅ sandbox (2) — live bwrap process runs --unshare-net (real isolation)
- ✅ observability (3) — engine event stream + real observer detectors
- ✅ routing_economics (1) — real free-first turn metered at $0
- ✅ backends (4) — mock, egress fail-close, preset, sandbox teardown
- ✅ websocket (2) — PubSub source of the channel feed + push coverage

**Honest SKIPs** (host/infra this machine lacks, documented not faked):
apple_container backend (no Apple host), ssh backend (no remote host), bwrap
cgroup OOM / tasks_max / rootless-zero-caps (need a memory-hog agent + specific
kernel privileges), full observer-swarm loop and cross-daemon bridge (multi-
process). These stay as written scenarios in §1/§3/§8 for when the host allows.

Bugs found implementing this: **genswarms#80** (rollback on async init/1
rejection is broken — the e2e caught it). That's the point of the suite.

---

## 0. engine_core — the bug surface of the week ✅
`features/engine_core.feature` — 4/4 passing against the live router.
- ✅ bwrap agent + object boot (sandbox seed #79, endpoint)
- ✅ swarm-msg ask agent→object gets a real reply (#79)
- ✅ REST config hot-patch: patch → restart → snapshot agree (#78)
- ✅ prompt-cache hit on a repeated prefix (#75)

---

## 1. Backends ⬜  `features/backends.feature`
Each backend is a distinct execution substrate. The engine must behave the same
where it should and differently where it must.

| # | scenario | assertion | where |
|---|----------|-----------|-------|
| 1.1 | mock backend starts without a process | health_check :ok, no Port, no tokens | mock_backend.ex |
| 1.2 | local backend spawns szc as a Port (no shell) | agent parent is the BEAM, not bash | local_backend.ex:58 |
| 1.3 | local stop reaps orphans (SIGTERM→SIGKILL) | after stop, no descendant PIDs | local_backend.ex:102 |
| 1.4 | bwrap :cgroup memory_limit OOM-kills a hog | agent dies, siblings unaffected | cgroup_manager.ex |
| 1.5 | bwrap :rootless runs with zero elevated caps | no SYS_ADMIN, no systemd scope, overlay in-userns | rootless_launcher.ex |
| 1.6 | bwrap tasks_max bounds a fork bomb | Nth spawn fails EAGAIN, box survives | cgroup_manager.ex |
| 1.7 | bwrap store :closure binds only the needed paths | multiple ro-binds, missing path → boot error | store_closure.ex |
| 1.8 | docker network :isolated blocks all but the LLM | curl host → timeout, curl endpoint → ok | docker_backend.ex:140 |
| 1.9 | apple_container rejects network :isolated fail-closed | {:unsupported_network,:isolated}, not open net | apple_container_backend.ex |
| 1.10 | preset resolution selects the right base/image | presets [:code,:base] → base-code / szc-agent-code | tool-presets, overlay_manager |
| 1.11 | preset fallback to base on missing dir (warning) | unknown preset → warns + runs base | overlay_manager |
| 1.12 | szc binary resolution honors SUBZEROCLAW_PATH | explicit path used; missing → boot error | bwrap_backend.ex:165 |
| 1.13 | mock_script runs an agent with no LLM | turns complete, zero router calls | backends.md:291 |
| 1.14 | extra_ro_binds mounts host dirs read-only | file visible in sandbox, write denied | bwrap_backend.ex |
| 1.15 | startup/teardown leaves no zombies or stale dirs | /run/swarm/agents/<id> gone after stop | overlay_manager |

## 2. Messaging & topology 🟡  `features/messaging.feature`
engine_core covers the happy-path ask; these are the edges.

| # | scenario | assertion |
|---|----------|-----------|
| 2.1 | router refuses a message off-topology | dropped as invalid_route, target never sees it |
| 2.2 | ask to a target with no return edge → typed timeout | ok:false/timeout envelope within the timeout, never hangs |
| 2.3 | ask to a missing object → typed not_found | ok:false, code target_not_found, immediate |
| 2.4 | ask to an agent (non-object) is rejected | ok:false, code not_an_object |
| 2.5 | ask correlation-id rejects path traversal | reply_to "../.." dropped, valid id processed |
| 2.6 | broadcast reaches every connected peer once | each of N peers records exactly one |
| 2.7 | outbox is polled ~500ms in lexical order | 0001 before 0002, file removed after route |
| 2.8 | file-inbox delivery for a default-workspace bwrap agent | agent processes an .inbox message (other half of #79) |
| 2.9 | dynamic add/remove edges rewire routing live | route denied then allowed then denied |
| 2.10 | system objects are always routable (no edge) | send to :metrics/:tick/:gateway without a topology edge |
| 2.11 | awaiting-reply gates user tasks until the reply | task queued mid-await, released on reply, 90s safety valve |
| 2.12 | two daemon swarms exchange via a bridge object | B's receiver records A's message (examples/bridge) |

## 3. Sandbox & isolation ⬜  `features/sandbox.feature`
Where three of this week's bugs lived. Prioritize fail-closed.

| # | scenario | assertion |
|---|----------|-----------|
| 3.1 | isolated agent has no net except the LLM forwarder | arbitrary host fails, router reachable |
| 3.2 | egress fail-closed on a non-allowlisted endpoint | agent fails to start rather than exfiltrate |
| 3.3 | seccomp blocks mount/ptrace/reboot (fail-closed) | denied syscall → EPERM; enabled-but-no-wrapper → boot abort |
| 3.4 | skills mounted read-only, nothing else visible | skill readable RO, host paths outside mounts absent |
| 3.5 | max_turns budget applies without killing the box | boots clean, budget file visible (regression of #79) |
| 3.6 | rootless overlay mounts in userns (no /dev/fuse) | no fuse-overlayfs process |
| 3.7 | unshare user/pid/uts/ipc, uid 1000 | inside PID ns, outer PIDs invisible |
| 3.8 | die-with-parent cleans the sandbox on BEAM death | no orphan sandbox after killing the engine |

## 4. Security & auth ⬜  `features/security.feature`
API surface + credential handling. All fail-closed.

| # | scenario | assertion |
|---|----------|-----------|
| 4.1 | no token → loopback only, remote → 401 | remote curl unauthorized |
| 4.2 | full token required on control-plane routes | wrong/absent token → 401, constant-time compare |
| 4.3 | config-scoped token: only config routes | patch config ok, create/delete swarm → 401 |
| 4.4 | config patch gate: only x-mutable keys | immutable key → 422 immutable_keys |
| 4.5 | config patch gate: no schema → all rejected | 422 no_config_schema |
| 4.6 | config patch gate: host-escape keys always rejected | subzeroclaw_path/extra_* → 422 forbidden_keys |
| 4.7 | patch with >200 nested keys rejected | 422 patch_too_large (atom-table backstop) |
| 4.8 | package loader refuses a digest mismatch | tampered vendor bytes → boot error, handler unbound |
| 4.9 | package loader refuses unsafe entry files | files: ["../etc/passwd"] → unsafe_entry_files |
| 4.10 | secrets redacted in snapshot | api_key → [REDACTED], grep of snapshot finds nothing |
| 4.11 | api key withheld from an untrusted endpoint | custom endpoint → agent gets api_key nil |
| 4.12 | tokens are env-var NAMES, never values, in config | get_config shows names; secrets structurally absent |
| 4.13 | cron/object allowlists fail-closed | empty trusted_sources/allowed_targets → nobody, nothing delivered |
| 4.14 | agent cap rejects the (max+1)th add_agent | agent_cap_exceeded before overlay write |

## 5. Scheduling ⬜  `features/scheduling.feature`
Genswarms.Cron — timers, seed jobs, retries.

| # | scenario | assertion |
|---|----------|-----------|
| 5.1 | a seed job fires on boot to its allowlisted target | target got exactly one message + job_run event |
| 5.2 | cron refuses a non-allowlisted target | rejected, nothing delivered |
| 5.3 | a crashing job retries with backoff then fails | never silently dropped, ends "failed" |
| 5.4 | overlapping ticks never double-launch a job | running job not launched twice |

## 6. Lifecycle & overlay ⬜  `features/lifecycle.feature`
Dynamic mutation + overlay replay (#78 territory).

| # | scenario | assertion |
|---|----------|-----------|
| 6.1 | object added at runtime persists across restart | present again via overlay replay |
| 6.2 | seed-object update_config replay stays consistent | live/snapshot/list agree (the #78 incident) |
| 6.3 | remove→re-add→update keeps the trailing patch | re-added object has the last patch (CodeRabbit finding) |
| 6.4 | scaled agent group replays deterministically | every member restored |
| 6.5 | rejected patch rolls back, object stays alive | 422 + old config still running |
| 6.6 | partial start reports errors, healthy nodes live | status :error, non-failing agents up |
| 6.7 | starting an already-running swarm is refused | :already_exists |

## 7. Objects ⬜  (fold into lifecycle/messaging)
| # | scenario | assertion |
|---|----------|-----------|
| 7.1 | handler return shapes route correctly | :reply→from, :send→edge, :broadcast→all, :noreply→nothing |
| 7.2 | init opening messages are sent on boot | {:ok,state,{:send,...}} delivered |
| 7.3 | config_schema↔init conformance | schema keys == keys init reads (per-package guard) |
| 7.4 | dashboard/1 extension surfaces in the envelope | object's extension block present |

## 8. Observability ⬜  `features/observability.feature`
Event spine + the observer loop (engine + tools in one test).

| # | scenario | assertion |
|---|----------|-----------|
| 8.1 | lifecycle transitions land in the event stream | agent_started/message_received/object_started rows |
| 8.2 | observer raises endpoint_down on a dead target | alert within one tick |
| 8.3 | observer raises error_burst on an error spike | alert with sample evidence |
| 8.4 | alert escalated once, deduped by cooldown | one card + one escalation for two ticks |
| 8.5 | pool_saturated only after sustained saturation | fires past the threshold, not before |
| 8.6 | events queryable cross-daemon via SQLite | two daemon swarms' events both visible |
| 8.7 | event relay tails new rows to WS subscribers | live push after boot tip |

## 9. Agent turns ⬜  (fold into sandbox/lifecycle)
| # | scenario | assertion |
|---|----------|-----------|
| 9.1 | per-turn wall-clock timeout discards late text | turn_timeout event, stale reply not delivered |
| 9.2 | reply_to auto-delivery fires once per turn | delivered unless the agent already sent there |
| 9.3 | inbox full refuses new tasks visibly | {:error,:inbox_full} + warning, not a silent drop |
| 9.4 | turns are strictly serial via the inbox | a task mid-turn queues, runs after TURN_COMPLETE |

## 10. WebSocket ⬜  `features/websocket.feature`
| # | scenario | assertion |
|---|----------|-----------|
| 10.1 | join subscribes and heartbeats | join reply + periodic heartbeat |
| 10.2 | message_routed / agent_status pushes arrive | events pushed to a joined client |
| 10.3 | topology_changed push on a live edge edit | client sees it after add_edges |
| 10.4 | subscribe_events honors level/category filters | only matching events pushed |
| 10.5 | send_task inbound over WS reaches the agent | {status:sent} + the agent runs it |

## 11. Routing economics ⬜  `features/routing_economics.feature`
| # | scenario | assertion |
|---|----------|-----------|
| 11.1 | a free-first policy routes to a $0 provider | USAGE shows the $0 model |
| 11.2 | a policy naming no model still selects & runs | provider chosen, turn completes |
| 11.3 | per-session metering sums across turns | /v1/session totals for the sid |
| 11.4 | a bare /v1 endpoint is refused, not silently empty | config rejected or turn error surfaced |

---

## Priority order for implementation
1. **Scheduling** (5) + **Lifecycle/overlay** (6) — deterministic, cheap, engine-only; no LLM needed for most. Fastest ROI, guards #78.
2. **Security & sandbox fail-closed** (3,4) — the highest-value invariants (what must NOT happen); a regression here is a breach, not a bug.
3. **Messaging edges** (2) — the ask/timeout/route surface; the other half of #79.
4. **Observability loop** (8) — closes the engine+observer+MCP loop, the culmination.
5. **Backends matrix** (1) — broad, some need docker/apple/ssh hosts; do what this host supports, note the rest.
6. **WebSocket** (10), **economics** (11), **turns** (9) — fill-ins.

Coverage today: 4 scenarios implemented, ~90 written as the map. The number
that matters is not the 4 green — it's that the ~86 gaps are now WRITTEN.
