Code.require_file("objects/bridge.ex", __DIR__)

%{
  name: "swarm-a",
  agents: [
    %{
      name: :messenger_a,
      backend: {:docker, "szc-agent-code:latest", %{memory_limit: "512m"}},
      skills: [Path.join(__DIR__, "skills/messenger.md")]
    }
  ],
  objects: [
    %{
      name: :bridge,
      handler: Bridge.Objects.Bridge,
      config: %{
        swarm_name: "swarm-a",
        routing: %{messenger_a: {"swarm-b", :messenger_b}}
      }
    }
  ],
  topology: [
    {:messenger_a, :bridge},
    {:bridge, :messenger_a}
  ]
}
