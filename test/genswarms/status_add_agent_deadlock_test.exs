defmodule Genswarms.StatusAddAgentDeadlockTest do
  @moduledoc """
  Regression test: `SwarmManager.status/1` must not deadlock with an object
  that calls `SwarmManager.add_agent/3` from inside its own process.

  The cycle this guards against:

    1. A status read runs, and the swarm's processes are asked for their
       `:get_status`. While the request to the object is outstanding, the
       object is busy (here: about to call `add_agent`).
    2. The object calls `SwarmManager.add_agent/3` and blocks on the manager.
    3. If the status fan-out runs INSIDE the SwarmManager process, the
       manager is waiting on the object and the object is waiting on the
       manager. Neither moves until the 5 s `GenServer.call` timeout fires,
       and the fan-out asks the same object several times (list_agents,
       count_by_state, list_objects), so one status read stalls every
       manager call -- including the object's add_agent -- for ~15 s.

  The test makes the overlap deterministic: the object parks in
  `handle_info` until the status request is sitting in its mailbox, and only
  then calls `add_agent`.
  """

  use ExUnit.Case

  alias Genswarms.SwarmManager
  alias Genswarms.CLI.SwarmRegistry

  # A native object that, on {:spawn, test_pid, name}, waits for :go and then
  # calls SwarmManager.add_agent from inside its own process -- the shape of a
  # chat ingress that spawns one agent per conversation.
  defmodule SpawnerHandler do
    @behaviour Genswarms.Objects.ObjectHandler

    @impl true
    def init(config), do: {:ok, %{swarm: config[:swarm]}}

    @impl true
    def handle_message(_from, _content, state), do: {:noreply, state}

    @impl true
    def interface(), do: %{}

    @impl true
    def handle_info({:spawn, test_pid, swarm, name}, state) do
      send(test_pid, {:spawner_parked, self()})

      receive do
        :go -> :ok
      end

      started = System.monotonic_time(:millisecond)
      result = SwarmManager.add_agent(swarm, %{name: name, backend: :mock})
      elapsed = System.monotonic_time(:millisecond) - started
      send(test_pid, {:add_agent_done, result, elapsed})
      {:noreply, state}
    end

    def handle_info(_msg, state), do: {:noreply, state}
  end

  # Generous next to the ~5-35 ms an uncontended add_agent takes, and well
  # under the 5 s GenServer.call timeout the deadlock waits out.
  @bound_ms 2_000

  setup do
    swarm = "status-deadlock-#{System.unique_integer([:positive])}"
    SwarmRegistry.clear_overlay(swarm)

    config = %{
      name: swarm,
      agents: [%{name: :alpha, backend: :mock}],
      objects: [%{name: :ingress, handler: SpawnerHandler}],
      topology: [{:alpha, :ingress}]
    }

    {:ok, ^swarm} = SwarmManager.start_from_config(config)

    on_exit(fn ->
      SwarmManager.stop(swarm)
      SwarmRegistry.clear_overlay(swarm)
    end)

    [{ingress, _}] = Registry.lookup(Genswarms.AgentRegistry, {swarm, :ingress})
    {:ok, swarm: swarm, ingress: ingress}
  end

  test "add_agent from an object is not blocked by a concurrent status read",
       %{swarm: swarm, ingress: ingress} do
    # 1. Park the object inside a handler, so it cannot answer :get_status.
    send(ingress, {:spawn, self(), swarm, :spawned})
    assert_receive {:spawner_parked, ^ingress}, 1_000

    # 2. Start a status read and wait until its :get_status request to the
    #    object is queued -- the status fan-out is now in flight.
    status_task =
      Task.async(fn ->
        started = System.monotonic_time(:millisecond)
        # Caught so a timed-out status read is reported by the assertions
        # below instead of crashing the test process through the link.
        result =
          try do
            SwarmManager.status(swarm)
          catch
            :exit, reason -> {:exit, reason}
          end

        {result, System.monotonic_time(:millisecond) - started}
      end)

    assert wait_until(fn -> get_status_queued?(ingress) end),
           "status read never asked the object for :get_status"

    # 3. Let the object call add_agent while that request is outstanding.
    send(ingress, :go)

    assert_receive {:add_agent_done, result, elapsed}, 20_000
    assert result == {:ok, :spawned}

    assert elapsed < @bound_ms,
           "add_agent took #{elapsed} ms while a status read was in flight " <>
             "(SwarmManager blocked on the object that was blocked on it)"

    # 4. The status read completes too, and sees the object and the new agent.
    {status_result, status_elapsed} = Task.await(status_task, 20_000)
    assert {:ok, status} = status_result
    assert status_elapsed < @bound_ms, "status took #{status_elapsed} ms"
    assert Enum.any?(status.objects, &(&1.name == :ingress))
    assert is_map(status.agent_counts)
  end

  test "status keeps its shape", %{swarm: swarm} do
    assert {:ok, status} = SwarmManager.status(swarm)

    assert %{
             name: ^swarm,
             status: :running,
             runtime_pending: false,
             agents: agents,
             objects: objects,
             agent_counts: counts,
             config: %{agent_count: 1, object_count: 1, topology_edges: 1}
           } = status

    assert Map.has_key?(status, :started_at)
    assert Map.has_key?(status, :config_path)
    assert [%{name: :alpha, state: _, pid: "#PID<" <> _}] = agents
    assert [%{name: :ingress, handler: SpawnerHandler, pid: "#PID<" <> _}] = objects
    assert counts == Enum.frequencies_by(agents, & &1.state)
  end

  test "status of an unknown swarm" do
    assert {:error, :not_found} = SwarmManager.status("no-such-swarm-#{System.unique_integer()}")
  end

  defp get_status_queued?(pid) do
    {:messages, msgs} = Process.info(pid, :messages)
    Enum.any?(msgs, &match?({:"$gen_call", _, :get_status}, &1))
  end

  defp wait_until(fun, attempts \\ 200) do
    cond do
      fun.() -> true
      attempts == 0 -> false
      true -> Process.sleep(10) && wait_until(fun, attempts - 1)
    end
  end
end
