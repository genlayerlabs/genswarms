@todo
Feature: Sandbox — bwrap isolation, skills, and egress
  The bwrap backend is where THREE of this week's bugs lived (#79 seed order,
  workspace, ask). engine_core proves boot+ask; these prove the isolation
  guarantees themselves. Steps UNIMPLEMENTED — the written contract.

  Scenario: an isolated agent has no network except the LLM forwarder
    # examples/bwrap-skills
    Given a bwrap agent with network: :isolated
    When it tries to reach an arbitrary host
    Then the connection fails, but the LLM router is reachable through the forwarder

  Scenario: the egress forwarder is fail-closed to a non-allowlisted endpoint
    Given a per-agent endpoint whose host is not allowlisted
    When the agent starts
    Then it fails closed rather than run with an untrusted exfiltration target

  Scenario: skills are mounted read-only and nothing else is visible
    Given a bwrap agent with one skill file
    When it lists its filesystem
    Then it sees the skill read-only and NOT host paths outside the mounts

  Scenario: a max_turns budget is applied without killing the sandbox
    # #79 — a max_turns harness config used to kill the sandbox at launch
    Given a bwrap agent with a max_turns budget
    When it boots
    Then it starts cleanly and the budget file is visible inside the sandbox

  Scenario: rootless mode runs with zero elevated capabilities
    Given a bwrap agent in :rootless privilege mode
    When it boots
    Then it runs unprivileged and the overlay is mounted in-sandbox
