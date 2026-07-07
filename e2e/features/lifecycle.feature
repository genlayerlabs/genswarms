Feature: Swarm lifecycle — dynamic mutation and overlay replay
  Hot mutation and overlay replay are where #78 lived. Deterministic, no LLM:
  drive the SwarmManager API on real swarms (mock agents) and assert the three
  truths — live object, snapshot, listing — never diverge.

  Scenario: an object added at runtime persists across a restart
    Given a running swarm with an overlay-added counter object
    When the swarm is stopped and started again
    Then the counter object is present again via overlay replay

  Scenario: a seed-object config patch replays consistently after restart
    Given a swarm whose echo object was hot-patched to tag "live"
    When the swarm is stopped and started again
    Then the live object, the snapshot and the listing all agree on tag "live"

  # NOTE: rollback on an ASYNC init/1 rejection is broken — see genswarms#80
  # (the patch reports "updated" and the object dies). This scenario covers the
  # rollback that DOES work: a synchronous gate rejection leaves the object
  # untouched with its old config.
  Scenario: a rejected config patch leaves the object on its old config
    Given a running swarm with an echo object at tag "base"
    When an immutable key is patched on it
    Then the patch is refused and the echo object still runs at tag "base"

  Scenario: a scaled agent group replays deterministically after restart
    Given a swarm with a worker group scaled to 3 and persisted
    When the swarm is stopped and started again
    Then all 3 worker members are restored

  Scenario: starting an already-running swarm is refused
    Given a running swarm
    When it is started again under the same name
    Then the second start is refused as already running
