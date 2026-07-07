Feature: Scheduling — cron seed jobs
  The Genswarms.Cron object drives time-based delivery. Deterministic, no LLM —
  a seed job with a near-future run_at fires and delivers to its allowlisted
  target. (Retry/backoff and overlap-guard scenarios are tracked in
  e2e/TEST-PLAN.md §5 and land next.)

  Scenario: a seed job fires and delivers exactly one message to its target
    Given a cron swarm with a seed job due shortly targeting a counter object
    When the job's run_at elapses
    Then the counter object receives exactly one scheduled tick within 15 seconds

  Scenario: cron ignores a tick from an untrusted source (fail-closed)
    Given a cron swarm with empty trusted_sources
    When an untrusted node sends a tick to cron
    Then no scheduled delivery reaches the counter
