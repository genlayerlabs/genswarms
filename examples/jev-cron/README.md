# Jev-cron

A `Genswarms.Objects.JevCron` object gates an LLM agent. Every 10 minutes, and
on every message routed to it, `watch` asks a Jev decision model to pick one of
three actions and applies it:

| Action | Effect |
|--------|--------|
| `nothing` | no effect |
| `wake` | sends the report to `coder` and remembers it as `last_issue` |
| `clear` | forgets `last_issue` (the coder replies `@watch: resolved: …`) |

Only `wake` spends an LLM turn, so while things are fine the coder costs
nothing. A decision costs about $0.00002.

```bash
export GENSWARMS_JEV_ENDPOINT=https://router.ygr.ai     # router base URL
export GENSWARMS_JEV_API_KEY=...                         # never put it in the config
genswarms start examples/jev-cron/jev_cron_swarm.exs
genswarms events -s jev-cron        # one jev_decision event per decision
```

Reports reach `watch` through the topology: an agent writing `@watch: …`, or
a bridge/gateway object (email, WhatsApp, CI webhook) with an edge to `watch`.
On the timer, Jev sees the time, its memory (`last_issue`, `last_wake`) and
its recent decisions, so a periodic check can decide to re-wake the coder if
an issue is still open.

To pin the decision model, add a router `policy_ir` to the config (for
example one that selects the `jev-1.13` family). See the jev-cron section in
[docs/objects.md](../../docs/objects.md#jev-cron) for every option.
