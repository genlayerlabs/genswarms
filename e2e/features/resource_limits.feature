Feature: Resource limits — real cgroup enforcement
  A bwrap :cgroup agent's limits are placed on a real systemd scope; we assert
  the kernel actually carries them (MemoryMax/TasksMax/CPUWeight on the live
  scope), the same deterministic way sandbox asserts --unshare-net — no need to
  provoke an OOM to prove the cap exists.

  Scenario: cgroup mode puts the configured limits on the live scope
    Given a bwrap cgroup agent limited to 64M memory, 30 tasks, cpu weight 50
    Then its systemd scope carries MemoryMax of 64M
    And its systemd scope carries TasksMax of 30
    And its systemd scope carries CPUWeight of 50
