defmodule Genswarms.IR.OpPolicyTest do
  # not async: one test mutates the global :max_agents_per_swarm app env.
  use ExUnit.Case, async: false

  alias Genswarms.IR.{State, OpPolicy}
  alias Genswarms.IR.Overlay.Event

  # A state with `n` agents (OpPolicy only counts them).
  defp state_with(n),
    do: %State{name: "s", phase: :desired, agents: List.duplicate(%{}, n)}

  defp add_agent(config \\ %{}),
    do: %Event{seq: 1, op: :add_agent, payload: %{"name" => "x", "config" => config}}

  defp scale(target),
    do: %Event{
      seq: 1,
      op: :scale_agent_group,
      payload: %{"base_name" => "coder", "target_count" => target}
    }

  describe "agent cap (#28)" do
    test "add_agent is allowed below the cap and rejected at/over it" do
      assert OpPolicy.validate(add_agent(), state_with(4), max_agents: 5) == :ok

      assert {:error, {:agent_cap_exceeded, 6, 5}} =
               OpPolicy.validate(add_agent(), state_with(5), max_agents: 5)
    end

    test "scale_agent_group is bounded by the cap" do
      assert OpPolicy.validate(scale(5), state_with(0), max_agents: 5) == :ok

      assert {:error, {:agent_cap_exceeded, 100_000, 5}} =
               OpPolicy.validate(scale(100_000), state_with(0), max_agents: 5)
    end

    test "the cap defaults to config :genswarms, :max_agents_per_swarm" do
      prev = Application.get_env(:genswarms, :max_agents_per_swarm)
      Application.put_env(:genswarms, :max_agents_per_swarm, 2)

      on_exit(fn ->
        if prev,
          do: Application.put_env(:genswarms, :max_agents_per_swarm, prev),
          else: Application.delete_env(:genswarms, :max_agents_per_swarm)
      end)

      assert {:error, {:agent_cap_exceeded, 3, 2}} = OpPolicy.validate(add_agent(), state_with(2))
    end
  end

  describe "host-escape config keys (#24)" do
    test "native IR backend opts have the same restrictions as config" do
      event = %Event{
        seq: 1,
        op: :add_agent,
        payload: %{
          "name" => "x",
          "backend" => %{"ref" => "bwrap", "opts" => %{"subzeroclaw_path" => "/host/executable"}}
        }
      }

      assert {:error, {:forbidden_config_keys, ["subzeroclaw_path"]}} =
               OpPolicy.validate(event, state_with(0))
    end

    test "add_agent with a forbidden backend key is rejected" do
      for key <- OpPolicy.forbidden_config_keys() do
        assert {:error, {:forbidden_config_keys, [^key]}} =
                 OpPolicy.validate(add_agent(%{key => "whatever"}), state_with(0))
      end
    end

    test "multiple forbidden keys are reported sorted and deduped" do
      cfg = %{"extra_rw_binds" => [], "subzeroclaw_path" => "/x"}

      assert {:error, {:forbidden_config_keys, ["extra_rw_binds", "subzeroclaw_path"]}} =
               OpPolicy.validate(add_agent(cfg), state_with(0))
    end

    test "safe domain/resource config keys are allowed" do
      cfg = %{"memory_limit" => "512M", "population_size" => 10, "network" => "isolated"}
      assert OpPolicy.validate(add_agent(cfg), state_with(0), max_agents: 100) == :ok
    end
  end

  describe "operator-authorized read-only mounts" do
    setup do
      previous = Application.get_env(:genswarms, :dynamic_agent_ro_binds)

      Application.put_env(:genswarms, :dynamic_agent_ro_binds, %{
        "s" => [{"/app/reply.sh", "/usr/local/bin/reply"}, {"/app/help", "/help"}]
      })

      on_exit(fn ->
        if previous,
          do: Application.put_env(:genswarms, :dynamic_agent_ro_binds, previous),
          else: Application.delete_env(:genswarms, :dynamic_agent_ro_binds)
      end)

      :ok
    end

    test "DSL tuples and native IR arrays accept the exact ordered list" do
      binds = [{"/app/reply.sh", "/usr/local/bin/reply"}, {"/app/help", "/help"}]
      assert :ok = OpPolicy.validate(add_agent(%{extra_ro_binds: binds}), state_with(0))

      event = %Event{
        seq: 1,
        op: :add_agent,
        payload: %{
          "backend" => %{
            "ref" => "bwrap",
            "opts" => %{"extra_ro_binds" => Enum.map(binds, &Tuple.to_list/1)}
          }
        }
      }

      assert :ok = OpPolicy.validate(event, state_with(0))
    end

    test "different swarm, source, destination, order, subset and malformed lists fail closed" do
      binds = [{"/app/reply.sh", "/usr/local/bin/reply"}, {"/app/help", "/help"}]

      assert {:error, {:forbidden_config_keys, ["extra_ro_binds"]}} =
               OpPolicy.validate(add_agent(%{"extra_ro_binds" => binds}), %{
                 state_with(0)
                 | name: "other"
               })

      for bad <- [
            [{"/etc", "/help"}],
            [{"/app/help", "/etc"}],
            Enum.reverse(binds),
            Enum.take(binds, 1),
            binds ++ [{"/etc", "/etc"}],
            [],
            nil,
            ["bad"]
          ] do
        assert {:error, {:forbidden_config_keys, ["extra_ro_binds"]}} =
                 OpPolicy.validate(add_agent(%{"extra_ro_binds" => bad}), state_with(0))
      end
    end

    test "authorization never permits writable mounts, executable overrides or cap bypass" do
      binds = [{"/app/reply.sh", "/usr/local/bin/reply"}, {"/app/help", "/help"}]

      for key <- ["extra_rw_binds", "extra_path", "subzeroclaw_path"] do
        assert {:error, {:forbidden_config_keys, [^key]}} =
                 OpPolicy.validate(
                   add_agent(%{"extra_ro_binds" => binds, key => binds}),
                   state_with(0)
                 )
      end

      assert {:error, {:agent_cap_exceeded, 2, 1}} =
               OpPolicy.validate(add_agent(%{"extra_ro_binds" => binds}), state_with(1),
                 max_agents: 1
               )
    end

    test "state options cannot authorize a request" do
      Application.delete_env(:genswarms, :dynamic_agent_ro_binds)
      binds = [{"/etc", "/host"}]
      state = %{state_with(0) | options: %{"dynamic_agent_ro_binds" => %{"s" => binds}}}

      assert {:error, {:forbidden_config_keys, ["extra_ro_binds"]}} =
               OpPolicy.validate(add_agent(%{"extra_ro_binds" => binds}), state)
    end
  end

  describe "ops with no policy" do
    test "remove/bump/edges/etc. are allowed by this layer" do
      for op <- [:remove_agent, :remove_object, :bump_package, :add_topology_edges, :set_options] do
        assert OpPolicy.validate(%Event{seq: 1, op: op, payload: %{}}, state_with(50)) == :ok
      end
    end
  end
end
