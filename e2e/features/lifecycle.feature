@todo
Feature: Swarm lifecycle — dynamic mutation, overlay, scale
  Hot mutation and overlay replay are where #78 lived. engine_core covers a
  single config patch; these cover the rest of the dynamic surface and the
  replay-on-restart path. Steps UNIMPLEMENTED — the written contract.

  Scenario: an object added at runtime is routable and persists across restart
    Given a running swarm
    When an object is added with persist and the swarm is stopped and started
    Then the object is present again via overlay replay

  Scenario: overlay replay of a seed-object config patch stays consistent
    # #78 — the exact incident: snapshot, runtime and listing must agree
    Given a swarm whose overlay carries an update_config for a seed object
    When it is restarted
    Then the live object, the snapshot, and list_objects all agree on the patched value

  Scenario: an update_config on a removed-and-readded object keeps its trailing patch
    # the CodeRabbit finding on #78
    Given an overlay that removes, re-adds, then patches the same object
    When it is restarted
    Then the re-added object keeps the trailing patch

  Scenario: scaling an agent group replays deterministically
    Given a swarm with a scaled agent group persisted
    When it is restarted
    Then every group member is restored

  Scenario: a rejected config patch rolls back and the object stays alive
    Given a patch the handler's init rejects
    When it is applied
    Then a 422 is returned and the object keeps running its old config
