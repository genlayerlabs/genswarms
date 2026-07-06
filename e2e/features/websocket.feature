Feature: Live feed — the PubSub the WebSocket channel relays
  The swarm:<name> channel is a relay: it subscribes to the engine's PubSub
  topics and pushes each event to WS clients (swarm_channel.ex handle_info →
  push). We assert the SOURCE of that feed deterministically by subscribing to
  the same PubSub, no WS client library needed. (A full stdio WS-client join is
  tracked in TEST-PLAN §10.)

  Scenario: a swarm start broadcasts a lifecycle event on its topic
    Given a subscription to a swarm's live topic
    When the swarm starts
    Then a swarm_started event is received on the topic

  Scenario: the channel relays every push kind it handles
    Given the swarm channel source
    Then it pushes agent_output, message_routed, agent_status and swarm lifecycle
