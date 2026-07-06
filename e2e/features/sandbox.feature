Feature: Sandbox & isolation — bwrap guarantees on a real sandbox
  A real bwrap agent boots; we assert its isolation from the ENGINE + the live
  sandbox process, deterministically (no dependence on a model executing a
  probe). Where three of this week's bugs lived. (Seccomp/rootless/cgroup-OOM
  need specific host privileges — tracked in TEST-PLAN §3.)

  Scenario: an isolated agent's sandbox process unshares the network namespace
    Given a bwrap agent started with network isolated
    Then the engine's egress guard requests --unshare-net for it
    And the live sandbox process runs with --unshare-net

  Scenario: a non-isolated agent keeps the network (contrast)
    Then the engine's egress guard requests no net-unshare for an open agent
