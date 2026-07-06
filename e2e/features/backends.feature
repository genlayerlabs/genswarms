Feature: Backends — substrate guarantees
  The deterministic backend guarantees, asserted off the engine code + a real
  bwrap sandbox. (OOM/tasks_max/cgroup runtime limits need a memory-hog agent;
  apple_container and ssh need hosts this machine lacks — all SKIP, tracked in
  TEST-PLAN §1 with the reason.)

  Scenario: the mock backend starts without an OS process
    Given a mock backend agent
    Then it reports healthy with no OS process

  Scenario: egress fail-closes on a non-allowlisted endpoint
    When egress resolves an endpoint that is not allowlisted
    Then it is refused as endpoint_not_allowed

  Scenario: a preset resolves to a real sandbox base layer
    When the base layer for the base preset is resolved
    Then it resolves to an existing sandbox base

  Scenario: an isolated agent's sandbox directory is removed on teardown
    Given a bwrap agent has started and recorded its sandbox directory
    When the swarm is stopped
    Then the sandbox directory is gone

  Scenario: an ssh-backend agent connects and runs against localhost
    Given an ssh-backend agent pointed at localhost
    Then the ssh agent is registered and running
