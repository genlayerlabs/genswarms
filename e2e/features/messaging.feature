@todo
Feature: Messaging — routing, asks, and cross-swarm bridges
  Topology-gated routing is the engine's backbone. engine_core covers the
  happy-path ask; these are the edges and the multi-swarm shapes, all
  UNIMPLEMENTED — the written contract.

  Scenario: the router refuses a message that violates the topology
    Given a swarm where "a" is NOT connected to "b"
    When "a" sends to "b"
    Then the message is dropped as an invalid route and "b" never receives it

  Scenario: a swarm-msg ask to a missing target returns a typed timeout, not a hang
    Given an agent that asks an object with no return edge
    When the ask is issued
    Then the agent gets an ok:false/timeout envelope within the ask timeout, never blocks forever

  Scenario: a broadcast reaches every connected agent exactly once
    Given a mesh of agents
    When one broadcasts
    Then each connected peer receives it exactly once

  Scenario: two daemon swarms exchange a message through a bridge object
    # examples/bridge
    Given daemon swarm A and daemon swarm B sharing a bridge over the task queue
    When A sends through the bridge
    Then B's receiver records the message

  Scenario: file-inbox delivery works for a default-workspace bwrap agent
    # the other half of #79 — the .inbox path, not just the ask reply
    Given a bwrap agent with no explicit workspace
    When a message is delivered to its file inbox
    Then the agent processes it
