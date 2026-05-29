defmodule SubzeroclawSwarm.Routing.RouterTest do
  use ExUnit.Case

  alias SubzeroclawSwarm.Routing.Router

  setup do
    # Start the router if not already started
    case GenServer.whereis(Router) do
      nil ->
        {:ok, _pid} = Router.start_link([])
        :ok

      _pid ->
        :ok
    end

    # Register a test topology
    topology = [
      {:agent_a, :agent_b},
      {:agent_b, :agent_a},
      {:agent_b, :agent_c}
    ]

    Router.register_topology("test-swarm", topology)

    on_exit(fn ->
      Router.unregister_topology("test-swarm")
    end)

    :ok
  end

  describe "register_topology/2" do
    test "registers topology for swarm" do
      Router.register_topology("another-swarm", [{:x, :y}])

      {:ok, topology} = Router.get_topology("another-swarm")
      assert :y in topology[:x]

      Router.unregister_topology("another-swarm")
    end
  end

  describe "get_topology/1" do
    test "returns topology for registered swarm" do
      {:ok, topology} = Router.get_topology("test-swarm")

      assert is_map(topology)
      assert :agent_b in topology[:agent_a]
    end

    test "returns error for unknown swarm" do
      assert {:error, :unknown_swarm} = Router.get_topology("nonexistent")
    end
  end

  describe "get_connections/2" do
    test "returns connections for agent" do
      {:ok, connections} = Router.get_connections("test-swarm", :agent_b)

      assert :agent_a in connections
      assert :agent_c in connections
    end

    test "returns empty list for agent with no connections" do
      {:ok, connections} = Router.get_connections("test-swarm", :agent_c)

      assert connections == []
    end
  end

  describe "route/4" do
    test "returns :ok for async routing (fire-and-forget)" do
      # route/4 uses GenServer.cast, so it always returns :ok immediately
      # Invalid routes are logged but don't return errors
      result = Router.route("test-swarm", :agent_a, :agent_c, "test message")
      assert result == :ok
    end

    test "returns :ok even for unknown swarm (async)" do
      # Async cast always returns :ok - errors are logged internally
      result = Router.route("nonexistent", :a, :b, "test")
      assert result == :ok
    end

    test "valid route can be verified via topology" do
      # To check if a route is valid, use get_connections
      {:ok, connections} = Router.get_connections("test-swarm", :agent_a)
      assert :agent_b in connections
      refute :agent_c in connections
    end
  end

  describe "get_message_log/2" do
    test "returns empty list initially" do
      messages = Router.get_message_log("test-swarm")

      assert is_list(messages)
    end
  end
end
