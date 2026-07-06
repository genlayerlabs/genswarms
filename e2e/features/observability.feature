Feature: Observability — the event stream and the detectors
  The engine emits a structured event stream (telemetry → LogStore → EventStore);
  the observer runs deterministic detectors over a swarm's dashboard data. Both
  asserted here without tokens. (The full observer loop — a live observer swarm
  raising alerts on a killed target — is tracked in TEST-PLAN §8.)

  Scenario: agent and object lifecycle transitions land in the event stream
    Given a running swarm with an agent and an object
    When the swarm's events are queried
    Then an agent_started event is present
    And an object_started event is present

  Scenario: the observer's endpoint_down detector fires on a dead endpoint
    Given the observer detectors are loaded
    When a swarm's dashboard fetch is a connection error
    Then the detectors raise an endpoint_down alert for that swarm

  Scenario: the observer stays quiet on a healthy idle swarm
    Given the observer detectors are loaded
    When a swarm's dashboard is healthy and idle
    Then the detectors raise nothing
