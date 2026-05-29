Code.require_file("objects/bridge.ex", __DIR__)

%{
  name: "swarm-b",
  agents: [
    %{
      name: :messenger_b,
      backend: {:docker, "szc-agent-code:latest", %{memory_limit: "512m"}},
      skills: [Path.join(__DIR__, "skills/messenger.md")]
    }
  ],
  objects: [
    %{
      name: :bridge,
      handler: Bridge.Objects.Bridge,
      config: %{
        swarm_name: "swarm-b",
        routing: %{messenger_b: {"swarm-a", :messenger_a}}
      }
    }
  ],
  topology: [
    {:messenger_b, :bridge},
    {:bridge, :messenger_b}
  ]
}
