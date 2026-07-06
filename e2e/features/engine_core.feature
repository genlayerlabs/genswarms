Feature: Engine core over a real swarm
  Everything here runs a swarm that ACTUALLY executes — a bwrap sandbox with an
  isolated network, the unhardcoded router paying for real LLM turns. We assert
  invariant properties of real execution, never the non-deterministic text a
  model returns. Each scenario is pinned to the bug it would have caught.

  Background:
    Given a running engine on an isolated port
    And a swarm with a bwrap "asker" agent and an "echo" object connected both ways

  Scenario: a bwrap agent and an object boot cleanly
    # sandbox seeding (#79) + endpoint resolution
    Then the "echo" object is registered
    And the "asker" agent is registered

  Scenario: an agent's swarm-msg ask reaches an object and gets a real reply
    # #79 — default-workspace bwrap asks used to die at a 30s timeout
    When the "asker" agent is asked to ping the "echo" object
    Then the "echo" object records at least one ask within 150 seconds
    And the last echoed text is "E2E_PING"

  Scenario: a hot config patch is applied consistently
    # #78 — replay/patch used to leave spec, runtime and listing diverging
    When the "echo" object config is patched over REST to tag "patched"
    Then the patch is accepted through the schema gate
    And the live object restarts with tag "patched"
    And the swarm snapshot reflects tag "patched"
    And the "echo" object is still listed

  Scenario: a repeated prompt prefix is served from cache
    # #75 — the router injects anthropic cache breakpoints; a re-read must hit
    Given a bwrap "cacher" agent on the claude route with a large stable prefix
    When the "cacher" agent runs two turns in the same session
    Then subzeroclaw's usage meter reports prompt-cache hits on a later call
