defmodule Genswarms.Property.SwarmConfigPropertyTest do
  @moduledoc """
  Rules: validation never crashes on junk; whatever it accepts is internally
  consistent (safe names, edges only between declared nodes).
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  # Long runs (PROPERTY_RUNS) outlast the default 60s per test.
  @moduletag timeout: :infinity

  alias Genswarms.Config.SwarmConfig

  # Fixed pool: parse/1 interns names, so unbounded random names would leak atoms.
  @names ~w(pc_a pc_b pc_c pc_d pc_e)

  defp junk do
    one_of([
      integer(),
      boolean(),
      constant(nil),
      string(:printable, max_length: 12),
      list_of(one_of([integer(), string(:printable, max_length: 5)]), max_length: 3),
      constant(%{}),
      constant(%{name: 5}),
      constant(%{name: ""}),
      constant({:a}),
      constant({"pc_a", 3})
    ])
  end

  defp agent_gen do
    map({member_of(@names), member_of([:mock, :local, :bwrap])}, fn {name, backend} ->
      %{name: name, backend: backend}
    end)
  end

  defp edge_gen, do: tuple({member_of(@names), member_of(@names)})

  property "parse never crashes on junk" do
    check all(
            config <-
              one_of([
                junk(),
                fixed_map(%{
                  name: one_of([junk(), constant("ok-name")]),
                  agents: one_of([junk(), list_of(one_of([junk(), agent_gen()]), max_length: 4)]),
                  objects: one_of([junk(), constant([])]),
                  topology: one_of([junk(), list_of(one_of([junk(), edge_gen()]), max_length: 4)])
                })
              ])
          ) do
      result = SwarmConfig.parse(config)
      assert match?({:ok, %SwarmConfig{}}, result) or match?({:error, _}, result)
    end
  end

  property "swarm names are accepted exactly when they are safe identifiers" do
    check all(name <- one_of([string(:printable, max_length: 20), string(:alphanumeric)])) do
      safe? = Regex.match?(~r/\A[a-zA-Z][a-zA-Z0-9_-]*\z/, name)
      result = SwarmConfig.parse(%{name: name, agents: [%{name: "pc_a", backend: :mock}]})
      assert match?({:ok, _}, result) == safe?
    end
  end

  property "an accepted config only has edges between declared nodes" do
    check all(
            agents <-
              map(
                list_of(agent_gen(), min_length: 1, max_length: 5),
                &Enum.uniq_by(&1, fn a -> a.name end)
              ),
            topology <- list_of(edge_gen(), max_length: 8)
          ) do
      declared = MapSet.new(agents, & &1.name)
      all_declared? = Enum.all?(topology, fn {a, b} -> a in declared and b in declared end)

      case SwarmConfig.parse(%{name: "prop-config", agents: agents, topology: topology}) do
        {:ok, config} ->
          assert all_declared?
          assert Enum.map(config.agents, & &1.name) == Enum.map(agents, &String.to_atom(&1.name))

          adjacency = SwarmConfig.build_adjacency_map(config.topology)

          for {from, to} <- config.topology do
            assert SwarmConfig.can_send?(config, from, to)
            assert to in Map.fetch!(adjacency, from)
          end

        {:error, _} ->
          refute all_declared?
      end
    end
  end

  describe "known bugs" do
    @describetag :known_bug

    property "two nodes can never share a name" do
      check all(agents <- list_of(agent_gen(), min_length: 2, max_length: 5)) do
        names = Enum.map(agents, & &1.name)

        case SwarmConfig.parse(%{name: "prop-config", agents: agents}) do
          {:ok, _} -> assert names == Enum.uniq(names)
          {:error, _} -> :ok
        end
      end
    end

    test "a misspelled network setting is rejected, not treated as open" do
      for value <- ["Isolated", "ISOLATED", "isolate", :Isolated] do
        agent = %{name: "pc_a", backend: :bwrap, config: %{network: value}}
        result = SwarmConfig.parse(%{name: "prop-config", agents: [agent]})

        assert match?({:error, _}, result) or
                 Genswarms.Backends.EgressGuard.isolated?(agent.config),
               "network: #{inspect(value)} was accepted and means an open network"
      end
    end
  end
end
