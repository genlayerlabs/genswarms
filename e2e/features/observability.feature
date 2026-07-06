@todo
Feature: Observability — events, detectors, and the observer loop
  The engine emits a structured event stream (telemetry → LogStore) and the
  observer swarm runs deterministic detectors over it. Closing this loop in a
  real e2e validates the engine AND the operating tools in one test.
  Steps UNIMPLEMENTED — the written contract.

  Scenario: agent and object lifecycle transitions land in the event stream
    Given a running swarm
    When an agent starts, receives a task, and an object restarts
    Then get_events shows agent_started, message_received and object_started rows

  Scenario: the observer raises endpoint_down when a watched swarm dies
    Given the observer watching a target swarm
    When the target's dashboard endpoint is killed
    Then within one tick the observer emits an endpoint_down alert for that swarm

  Scenario: the observer raises error_burst on a spike of error events
    Given the observer watching a swarm with a low error_burst threshold
    When several llm_error events occur inside the window
    Then the observer emits an error_burst alert with the sample as evidence

  Scenario: an alert is escalated once, deduped by cooldown
    Given a persisting fault and a cooldown window
    When two ticks observe the same fault
    Then exactly one alert card and one escalation are produced

  Scenario: pool_saturated only fires after the saturation is sustained
    Given a pool at leased == size
    When it stays saturated past pool_saturated_s
    Then a pool_saturated alert fires, and not before
