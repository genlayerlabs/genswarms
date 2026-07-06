@todo
Feature: WebSocket — the live feed
  The swarm:<name> channel streams the swarm's story in real time. Steps
  UNIMPLEMENTED — the written contract. See e2e/TEST-PLAN.md §10.

  Scenario: joining subscribes and heartbeats
    Given a client joining the swarm channel
    Then it gets a join reply and periodic heartbeats

  Scenario: routing and status transitions are pushed live
    Given a joined client
    When an agent routes a message and changes state
    Then message_routed and agent_status pushes arrive

  Scenario: a live topology edit pushes topology_changed
    Given a joined client
    When an edge is added at runtime
    Then a topology_changed push arrives

  Scenario: event subscription honors level and category filters
    Given a client subscribed with level error and category routing
    Then only matching events are pushed, non-matching are not

  Scenario: a task sent over the socket reaches the agent
    Given a joined client
    When it pushes send_task for an agent
    Then it gets status sent and the agent runs the task
