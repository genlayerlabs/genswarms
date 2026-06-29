defmodule GenswarmsWeb.AppleContainerBackendApiTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest

  alias Genswarms.CLI.SwarmRegistry
  alias Genswarms.SwarmManager
  alias GenswarmsWeb.SwarmController

  setup do
    swarm = "apple-api-#{System.unique_integer([:positive])}"

    config = %{
      name: swarm,
      agents: [%{name: :seed, backend: :mock}],
      topology: []
    }

    {:ok, ^swarm} = SwarmManager.start_from_config(config)
    SwarmRegistry.clear_overlay(swarm)

    on_exit(fn ->
      SwarmManager.stop(swarm)
      SwarmRegistry.clear_overlay(swarm)
    end)

    {:ok, swarm: swarm}
  end

  test "add-agent REST backend object preserves Apple container image", %{swarm: swarm} do
    conn =
      build_conn()
      |> SwarmController.add_agent(%{
        "swarm_name" => swarm,
        "name" => "mac",
        "backend" => %{
          "type" => "apple_container",
          "image" => "szc-agent-base:latest"
        },
        "config" => %{"network" => "isolated"}
      })

    assert conn.status == 201
    assert %{"status" => "added", "name" => "mac"} = Jason.decode!(conn.resp_body)

    {:ok, config} = SwarmManager.get_full_config(swarm)
    added = Enum.find(config.agents, &(&1.name == :mac))

    assert added.backend == {:apple_container, "szc-agent-base:latest"}
    assert added.config.network == "isolated"
  end
end
