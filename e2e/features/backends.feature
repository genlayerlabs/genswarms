@todo
Feature: Backends — the execution substrates
  Each backend (mock, local, docker, apple_container, ssh, bwrap) is a distinct
  way to run an agent. The engine must behave the same where it should and
  differently where it must. Steps UNIMPLEMENTED — the written contract.
  See e2e/TEST-PLAN.md §1 for the full matrix and code locations.

  Scenario: the mock backend starts without spawning a process
    Given an agent on the mock backend
    Then it reports healthy with no OS process and makes no LLM call

  Scenario: a local agent is a child of the BEAM, not a shell
    Given an agent on the local backend
    Then its process parent is the engine, not bash
    And stopping it reaps all descendants

  Scenario: a bwrap :cgroup memory limit OOM-kills a memory hog
    Given a bwrap agent with memory_limit 64M in cgroup mode
    When it allocates past the limit
    Then it is OOM-killed and sibling agents are unaffected

  Scenario: a bwrap :rootless agent runs with zero elevated capabilities
    Given a bwrap agent in rootless privilege mode
    Then it runs with no SYS_ADMIN and no systemd scope
    And its overlay is mounted inside the user namespace

  Scenario: tasks_max bounds a fork bomb without taking the host down
    Given a bwrap agent with tasks_max 10
    When it forks past the limit
    Then further spawns fail and the box survives

  Scenario: store :closure binds only the paths the sandbox needs
    Given a bwrap agent with store :closure
    Then the bind set is the minimal closure, and a missing path fails boot

  Scenario: docker network :isolated blocks everything but the LLM
    Given a docker agent with network :isolated
    Then an arbitrary host is unreachable and the router is reachable via the forwarder

  Scenario: apple_container rejects network :isolated fail-closed
    Given an apple_container agent with network :isolated
    Then it fails closed with unsupported_network rather than running open

  Scenario: preset resolution selects the right base or image
    Given presets [:code, :base]
    Then the resolved sandbox base is base-code (or image szc-agent-code)

  Scenario: an unknown preset falls back to base with a warning
    Given a preset directory that does not exist
    Then the agent runs on base and a warning is logged

  Scenario: SUBZEROCLAW_PATH is honored and a missing binary fails boot
    Given an explicit subzeroclaw_path
    Then that binary is used, and a nonexistent one fails the agent start

  Scenario: mock_script runs a real backend agent with no LLM
    Given a bwrap agent with a mock_script
    Then its turns complete with zero router calls

  Scenario: extra_ro_binds mounts host dirs read-only inside the sandbox
    Given a bwrap agent with an extra read-only bind
    Then the file is visible in the sandbox and a write is denied

  Scenario: teardown leaves no zombies or stale sandbox directories
    Given a bwrap agent that has run and stopped
    Then its /run/swarm/agents directory is gone and no orphan processes remain
