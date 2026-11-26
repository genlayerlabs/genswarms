defmodule Genswarms.Property.RouterPropertyTest do
  @moduledoc """
  Rule: a message is routed only along an edge that exists at that moment
  (system objects excepted), whatever sequence of topology edits came before.
  """
  use ExUnit.Case
  use ExUnitProperties

  # Long runs (PROPERTY_RUNS) outlast the default 60s per test.
  @moduletag timeout: :infinity

  alias Genswarms.Routing.Router

  @nodes [:pn0, :pn1, :pn2, :pn3, :pn4]
  @system_objects [:metrics, :tick, :gateway]

  defp node_gen, do: member_of(@nodes)
  defp edge_gen, do: tuple({node_gen(), node_gen()})

  defp op_gen do
    one_of([
      tuple({constant(:add), list_of(edge_gen(), max_length: 3)}),
      tuple({constant(:remove), list_of(edge_gen(), max_length: 3)}),
      tuple({constant(:remove_node), node_gen()}),
      tuple({constant(:route), node_gen(), one_of([node_gen(), member_of(@system_objects)])})
    ])
  end

  defp apply_op({:add, edges}, swarm, {model, sent}, _i) do
    :ok = Router.add_edges(swarm, edges)
    {MapSet.union(model, MapSet.new(edges)), sent}
  end

  defp apply_op({:remove, edges}, swarm, {model, sent}, _i) do
    :ok = Router.remove_edges(swarm, edges)
    {MapSet.difference(model, MapSet.new(edges)), sent}
  end

  defp apply_op({:remove_node, node}, swarm, {model, sent}, _i) do
    :ok = Router.remove_node(swarm, node)
    {MapSet.reject(model, fn {from, to} -> from == node or to == node end), sent}
  end

  defp apply_op({:route, from, to}, swarm, {model, sent}, i) do
    content = "m#{i}"
    :ok = Router.route(swarm, from, to, content)
    allowed? = MapSet.member?(model, {from, to}) or to in @system_objects
    {model, if(allowed?, do: [{from, to, content} | sent], else: sent)}
  end

  defp live_edges(swarm) do
    {:ok, topology} = Router.get_topology(swarm)
    for {from, targets} <- topology, to <- targets, into: MapSet.new(), do: {from, to}
  end

  defp check_against_model(initial, ops) do
    swarm = "prop-router-#{System.unique_integer([:positive])}"
    :ok = Router.register_topology(swarm, initial)

    try do
      {model, sent} =
        ops
        |> Enum.with_index()
        |> Enum.reduce({MapSet.new(initial), []}, fn {op, i}, acc ->
          apply_op(op, swarm, acc, i)
        end)

      assert live_edges(swarm) == model

      # get_message_log is a call, so it runs after every cast above.
      routed =
        swarm
        |> Router.get_message_log(1000)
        |> Enum.map(&{&1.from, &1.to, &1.content_preview})

      assert Enum.sort(routed) == Enum.sort(sent)
    after
      Router.unregister_topology(swarm)
    end
  end

  property "routes exactly the messages that have an edge" do
    check all(
            initial <- uniq_list_of(edge_gen(), max_length: 6),
            ops <- list_of(op_gen(), max_length: 30)
          ) do
      check_against_model(initial, ops)
    end
  end

  describe "known bugs" do
    @describetag :known_bug

    # Shrinks to: register [{a, b}, {a, b}], remove it once, the edge is still there.
    property "an edge listed twice in the config can still be removed" do
      check all(
              initial <- list_of(edge_gen(), max_length: 6),
              ops <- list_of(op_gen(), max_length: 30)
            ) do
        check_against_model(initial, ops)
      end
    end

    test "router survives a message whose content is not text" do
      swarm = "prop-router-crash-#{System.unique_integer([:positive])}"
      :ok = Router.register_topology(swarm, [{:pn0, :pn1}])
      pid = Process.whereis(Router)
      ref = Process.monitor(pid)

      # What POST /api/swarms/:name/message passes through for {"content": {}}.
      Router.route(swarm, :pn0, :pn1, %{})

      refute_receive {:DOWN, ^ref, :process, ^pid, _}, 500
      assert {:ok, _} = Router.get_topology(swarm)
    end

    test "topologies survive a router restart" do
      swarm = "prop-router-restart-#{System.unique_integer([:positive])}"

      {:ok, ^swarm} =
        Genswarms.SwarmManager.start_from_config(%{
          name: swarm,
          agents: [%{name: :pn0, backend: :mock}, %{name: :pn1, backend: :mock}],
          topology: [{:pn0, :pn1}]
        })

      on_exit(fn -> Genswarms.SwarmManager.stop(swarm) end)

      pid = Process.whereis(Router)
      ref = Process.monitor(pid)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}
      wait_for_router()

      assert {:ok, %{pn0: [:pn1]}} = Router.get_topology(swarm)
    end
  end

  defp wait_for_router(attempts \\ 100) do
    cond do
      Process.whereis(Router) -> :ok
      attempts == 0 -> flunk("router did not restart")
      true -> Process.sleep(10) && wait_for_router(attempts - 1)
    end
  end
end
