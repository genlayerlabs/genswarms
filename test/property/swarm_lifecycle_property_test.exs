defmodule Genswarms.Property.SwarmLifecyclePropertyTest do
  @moduledoc """
  Rule: after any sequence of scale / add / remove / edge edits, the three
  copies of the truth agree — the manager's config, the router's edges and
  the processes that are actually alive.
  """
  use ExUnit.Case
  use ExUnitProperties

  # Long runs (PROPERTY_RUNS) outlast the default 60s per test.
  @moduletag timeout: :infinity

  alias Genswarms.CLI.SwarmRegistry
  alias Genswarms.Routing.Router
  alias Genswarms.SwarmManager

  defmodule NoopHandler do
    @behaviour Genswarms.Objects.ObjectHandler
    @impl true
    def init(_config), do: {:ok, %{}}
    @impl true
    def handle_message(_from, _content, state), do: {:noreply, state}
    @impl true
    def interface, do: %{}
  end

  @extras [:pl_extra_a, :pl_extra_b]
  @nodes [:pl_worker, :pl_worker_1, :pl_worker_2, :pl_worker_3, :pl_sink | @extras]

  defp op_gen do
    one_of([
      tuple({constant(:scale), integer(0..3)}),
      tuple(
        {constant(:add_agent), member_of(@extras), list_of(member_of(@nodes), max_length: 2)}
      ),
      tuple({constant(:remove_agent), member_of(@nodes -- [:pl_sink])}),
      tuple({constant(:add_edges), list_of(edge_gen(), min_length: 1, max_length: 2)}),
      tuple({constant(:remove_edges), list_of(edge_gen(), min_length: 1, max_length: 2)})
    ])
  end

  defp edge_gen, do: tuple({member_of(@nodes), member_of(@nodes)})

  # Results are not asserted: an op may legitimately be refused. The rule is
  # that refused or not, the system is left consistent.
  defp run_op({:scale, n}, swarm), do: SwarmManager.scale_agent_group(swarm, :pl_worker, n)

  defp run_op({:add_agent, name, connections}, swarm),
    do: SwarmManager.add_agent(swarm, %{name: name, backend: :mock}, connections: connections)

  defp run_op({:remove_agent, name}, swarm), do: SwarmManager.remove_agent(swarm, name)
  defp run_op({:add_edges, edges}, swarm), do: SwarmManager.add_topology_edges(swarm, edges)
  defp run_op({:remove_edges, edges}, swarm), do: SwarmManager.remove_topology_edges(swarm, edges)

  defp live_names(swarm) do
    Genswarms.AgentRegistry
    |> Registry.select([{{{swarm, :"$1"}, :_, :_}, [], [:"$1"]}])
    |> MapSet.new()
  end

  # Registry entries clear a moment after a process dies.
  defp settle(swarm, expected, attempts \\ 100) do
    live = live_names(swarm)

    if live == expected or attempts == 0 do
      live
    else
      Process.sleep(5)
      settle(swarm, expected, attempts - 1)
    end
  end

  defp assert_consistent(swarm, history) do
    {:ok, config} = SwarmManager.get_full_config(swarm)
    {:ok, adjacency} = Router.get_topology(swarm)

    declared = MapSet.new(Enum.map(config.agents ++ config.objects, & &1.name))
    live = settle(swarm, declared)

    router_edges =
      for {from, targets} <- adjacency, to <- targets, into: MapSet.new(), do: {from, to}

    context = "after #{inspect(history)}"

    assert live == declared, "live processes differ from the manager's config #{context}"

    assert router_edges == MapSet.new(config.topology),
           "router edges differ from the config #{context}"

    for {from, to} <- router_edges do
      assert from in live and to in live, "edge #{from} -> #{to} touches a dead node #{context}"
    end
  end

  defp check_ops(ops) do
    swarm = "prop-life-#{System.unique_integer([:positive])}"
    SwarmRegistry.clear_overlay(swarm)

    {:ok, ^swarm} =
      SwarmManager.start_from_config(%{
        name: swarm,
        agents: [%{name: :pl_worker, backend: :mock}],
        objects: [%{name: :pl_sink, handler: NoopHandler}],
        topology: [{:pl_worker, :pl_sink}]
      })

    try do
      assert_consistent(swarm, [])

      Enum.reduce(ops, [], fn op, history ->
        run_op(op, swarm)
        history = history ++ [op]
        assert_consistent(swarm, history)
        history
      end)
    after
      SwarmManager.stop(swarm)
      SwarmRegistry.clear_overlay(swarm)
    end

    assert settle(swarm, MapSet.new()) == MapSet.new(), "processes left alive after stop"
    assert {:error, :unknown_swarm} = Router.get_topology(swarm)
  end

  property "manager, router and live processes always agree" do
    check all(ops <- list_of(op_gen(), max_length: 12)) do
      check_ops(ops)
    end
  end

  test "sending a task to an agent that does not exist returns an error" do
    swarm = "prop-life-task-#{System.unique_integer([:positive])}"

    {:ok, ^swarm} =
      SwarmManager.start_from_config(%{
        name: swarm,
        agents: [%{name: :pl_worker, backend: :mock}]
      })

    on_exit(fn -> SwarmManager.stop(swarm) end)

    # The daemon's task poller calls exactly this; an exit here stops the daemon.
    assert {:error, :agent_not_found} =
             SwarmManager.send_task(swarm, "pl_no_such_agent", "hello")
  end
end
