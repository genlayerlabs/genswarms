Feature: Messaging & topology — routing over real swarms
  Deterministic, no LLM: drive the Router and object handlers directly and
  assert delivery follows the declared topology. (Ask error-path envelopes,
  agent broadcast, file-inbox and the cross-swarm bridge need a real agent —
  tracked in TEST-PLAN §2 for the LLM block.)

  Scenario: a message off the topology is dropped
    Given a swarm where shape is connected to seen but not to unseen
    When shape is told to send to unseen
    Then unseen never receives it

  Scenario: a message along a declared edge is delivered
    Given a swarm where shape is connected to seen but not to unseen
    When shape is told to send to seen
    Then seen receives exactly one tick

  Scenario: adding an edge at runtime makes a denied route work
    Given a swarm where shape is connected to seen but not to unseen
    When an edge from shape to unseen is added and shape sends to unseen
    Then unseen receives exactly one tick

  Scenario: a broadcast reaches every connected target
    Given a swarm where shape is connected to both seen and also_seen
    When shape broadcasts
    Then both seen and also_seen receive a tick
