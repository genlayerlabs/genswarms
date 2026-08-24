defmodule Genswarms.SwarmManagerObjectInitRejectTest do
  @moduledoc """
  Regression test for #80: update_object_config (and add_object) must not
  report success when the object's own init/1 asynchronously rejects the
  config. Before the fix, `do_add_object` treated
  `ObjectSupervisor.start_object`'s `{:ok, pid}` (process spawned) as proof
  the config was accepted — but the handler's real init/1 runs afterward,
  asynchronously, via ObjectServer's deferred `:init_object` message. A
  rejecting init/1 was reported as "added"/"updated" while the object was
  actually left in :error state (handler_state nil).

  async: false — shares the global AgentRegistry/Router/LogStore, same as
  the other object-lifecycle integration tests in this suite.
  """
  use ExUnit.Case, async: false

  alias Genswarms.SwarmManager
  alias Genswarms.CLI.SwarmRegistry
  alias Genswarms.Objects.ObjectServer

  defmodule GatedHandler do
    @moduledoc "Rejects init when config[:bad] is true; otherwise fine."
    @behaviour Genswarms.Objects.ObjectHandler

    @impl true
    def init(%{bad: true}), do: {:error, :rejected}
    def init(_config), do: {:ok, %{}}

    @impl true
    def handle_message(_from, _content, state), do: {:noreply, state}

    @impl true
    def interface(), do: %{}
  end

  setup do
    swarm = "init-reject-#{System.unique_integer([:positive])}"
    workspace = Path.join(System.tmp_dir!(), swarm)
    File.mkdir_p!(workspace)

    config = %{
      name: swarm,
      agents: [
        %{name: :alpha, backend: :mock, config: %{workspace: workspace}}
      ],
      objects: [
        %{name: :gated, handler: GatedHandler, config: %{tag: "base"}}
      ],
      topology: []
    }

    {:ok, ^swarm} = SwarmManager.start_from_config(config)
    SwarmRegistry.clear_overlay(swarm)

    # wait for the seed object to finish its (successful) init before tests run
    assert :ok = ObjectServer.await_init(swarm, :gated)

    on_exit(fn ->
      SwarmManager.stop(swarm)
      SwarmRegistry.clear_overlay(swarm)
      File.rm_rf(workspace)
    end)

    {:ok, swarm: swarm}
  end

  test "update_object_config rolls back and reports failure when init/1 rejects", %{swarm: swarm} do
    assert {:error, _reason} = SwarmManager.update_object_config(swarm, :gated, %{bad: true})

    # The object must still be ALIVE and back on its old config, not dead —
    # this is the exact three-way divergence (#78-style) #80 reintroduced.
    assert :ok = ObjectServer.await_init(swarm, :gated)
    status = ObjectServer.get_status(swarm, :gated)
    assert status.state == :idle
  end

  test "a valid config patch still applies normally (no false rejection)", %{swarm: swarm} do
    assert {:ok, :gated} = SwarmManager.update_object_config(swarm, :gated, %{tag: "live"})
    assert :ok = ObjectServer.await_init(swarm, :gated)
    assert ObjectServer.get_status(swarm, :gated).state == :idle
  end

  test "add_object reports failure (not :added) when init/1 rejects", %{swarm: swarm} do
    spec = %{name: :new_gated, handler: GatedHandler, config: %{bad: true}}

    assert {:error, _reason} = SwarmManager.add_object(swarm, spec)

    # Must not be left registered/running at all — the add is atomic.
    assert GenServer.whereis(ObjectServer.via_tuple(swarm, :new_gated)) == nil
  end

  test "add_object still succeeds normally when init/1 accepts", %{swarm: swarm} do
    spec = %{name: :new_ok, handler: GatedHandler, config: %{tag: "fine"}}

    assert {:ok, :new_ok} = SwarmManager.add_object(swarm, spec)
    assert :ok = ObjectServer.await_init(swarm, :new_ok)
  end
end
