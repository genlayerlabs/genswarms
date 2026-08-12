defmodule Genswarms.CLI.DaemonBridgePersistentBackendTest do
  use ExUnit.Case, async: false

  alias Genswarms.Agents.AgentServer
  alias Genswarms.CLI.{DaemonBridge, SwarmRegistry}
  alias Genswarms.SwarmManager

  setup do
    swarm = "bridge-session-#{System.unique_integer([:positive])}"

    assert {:ok, ^swarm} =
             SwarmManager.start_from_config(%{
               name: swarm,
               agents: [%{name: :worker, backend: :mock}],
               topology: []
             })

    SwarmRegistry.clear_overlay(swarm)

    on_exit(fn ->
      SwarmManager.stop(swarm)
      SwarmRegistry.clear_overlay(swarm)
    end)

    {:ok, swarm: swarm}
  end

  test "session and interrupt operations retain explicit unsupported results", %{swarm: swarm} do
    assert {:ok, %{}} = DaemonBridge.dispatch(swarm, :agent_session, %{name: "worker"})

    assert {:error, :unsupported} =
             DaemonBridge.dispatch(swarm, :interrupt_agent, %{name: "worker"})
  end

  test "agent restart uses its effective config rather than a name-only placeholder", %{
    swarm: swarm
  } do
    [{before_pid, _}] = Registry.lookup(Genswarms.AgentRegistry, {swarm, :worker})

    assert :ok = DaemonBridge.dispatch(swarm, :restart_agent, %{name: "worker"})

    [{after_pid, _}] = Registry.lookup(Genswarms.AgentRegistry, {swarm, :worker})
    refute before_pid == after_pid
    assert AgentServer.get_status(swarm, :worker).backend == :mock
  end

  test "restart lookup does not mint an atom for an unknown API name", %{swarm: swarm} do
    missing = "missing-agent-#{System.unique_integer([:positive])}"
    assert_raise ArgumentError, fn -> String.to_existing_atom(missing) end

    assert {:error, :agent_not_found} =
             DaemonBridge.dispatch(swarm, :restart_agent, %{name: missing})

    assert_raise ArgumentError, fn -> String.to_existing_atom(missing) end
  end
end
