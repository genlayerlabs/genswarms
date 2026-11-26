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

  # Agent and object names drawn from one pool, as atoms or strings, so
  # duplicates (including :pc_a vs "pc_a", agent vs object) come up often.
  defp node_name, do: one_of([member_of(@names), map(member_of(@names), &String.to_atom/1)])

  # An unloaded handler module is accepted (it may live in the host app).
  defp object_gen, do: map(node_name(), &%{name: &1, handler: PropConfig.NotLoadedHandler})

  property "an accepted config has unique node names and only edges between them" do
    check all(
            agents <-
              list_of(map({agent_gen(), node_name()}, fn {a, n} -> %{a | name: n} end),
                min_length: 1,
                max_length: 5
              ),
            objects <- list_of(object_gen(), max_length: 2),
            topology <- list_of(edge_gen(), max_length: 8)
          ) do
      names = Enum.map(agents ++ objects, &to_string(&1.name))
      unique? = names == Enum.uniq(names)
      declared = MapSet.new(names)
      all_declared? = Enum.all?(topology, fn {a, b} -> a in declared and b in declared end)

      config = %{name: "prop-config", agents: agents, objects: objects, topology: topology}

      case SwarmConfig.parse(config) do
        {:ok, config} ->
          assert unique? and all_declared?

          assert Enum.map(config.agents, & &1.name) ==
                   Enum.map(agents, &String.to_atom(to_string(&1.name)))

          adjacency = SwarmConfig.build_adjacency_map(config.topology)

          for {from, to} <- config.topology do
            assert SwarmConfig.can_send?(config, from, to)
            assert to in Map.fetch!(adjacency, from)
          end

        {:error, {:duplicate_name, name}} ->
          refute unique?
          assert Enum.count(names, &(&1 == name)) > 1

        {:error, _} ->
          refute unique? and all_declared?
      end
    end
  end

  # A value an agent could plausibly write for `network`: the reserved words in
  # any case/padding, near-misses, and docker-style network names.
  defp network_value do
    word =
      one_of([
        member_of(~w(open none isolated isolate Isolated ISOLATED None OPEN my-net bridge)),
        map(
          {member_of(~w(open none isolated)), list_of(boolean(), length: 8),
           member_of(["", " "])},
          fn {w, flips, pad} ->
            w
            |> String.graphemes()
            |> Enum.zip(flips ++ List.duplicate(false, 8))
            |> Enum.map_join(fn {c, up?} -> if up?, do: String.upcase(c), else: c end)
            |> Kernel.<>(pad)
          end
        )
      ])

    one_of([word, map(word, &String.to_atom/1)])
  end

  property "a network setting is accepted only if the backend honours it as written" do
    check all(
            value <- network_value(),
            backend <-
              member_of([:bwrap, {:bwrap, %{}}, nil, {:docker, "img"}, :local, {:tmux, :codex}]),
            where <- member_of([:config, :backend])
          ) do
      agent =
        case {where, backend} do
          {:backend, {:bwrap, _}} ->
            %{name: "pc_a", backend: {:bwrap, %{network: value}}}

          {:backend, {:docker, img}} ->
            %{name: "pc_a", backend: {:docker, img, %{network: value}}}

          {_, nil} ->
            %{name: "pc_a", config: %{network: value}}

          _ ->
            %{name: "pc_a", backend: backend, config: %{network: value}}
        end

      exact? = to_string(value) in ~w(open none isolated)

      near_miss? =
        not exact? and String.downcase(String.trim(to_string(value))) in ~w(open none isolated)

      bwrap? = backend in [:bwrap, {:bwrap, %{}}, nil]

      accepted? =
        match?({:ok, _}, SwarmConfig.parse(%{name: "prop-config", agents: [agent]}))

      cond do
        near_miss? -> refute accepted?
        bwrap? -> assert accepted? == to_string(value) in ~w(open isolated)
        true -> assert accepted?
      end
    end
  end

  test "a misspelled network setting is rejected, not treated as open" do
    for value <- ["Isolated", "ISOLATED", "isolate", :Isolated] do
      agent = %{name: "pc_a", backend: :bwrap, config: %{network: value}}
      result = SwarmConfig.parse(%{name: "prop-config", agents: [agent]})

      assert {:error, {:invalid_network, ^value}} = result
    end
  end
end
