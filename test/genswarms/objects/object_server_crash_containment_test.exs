defmodule Genswarms.Objects.ObjectServerCrashContainmentTest do
  @moduledoc """
  A handler that raises/throws/exits on a ROUTED message (or in handle_info)
  must not take the ObjectServer down with it: the supervisor restart wipes
  the handler's accumulated state (bindings, counters) and the reason only
  ever reached stdout — LogStore showed a bare object_started and nothing
  else. Found live 2026-07-07: a prod telegram sender crash-looped 7 times,
  losing its slot→conversation claims each time, so agent replies right
  after a restart dropped as "no target" — with proc_crash at 0 and zero
  error events to diagnose it by.

  The ask path already contains crashes (typed handler_error envelope);
  these tests pin the same containment for deliver_message and handle_info.

  async: false — shares the global AgentRegistry/Router/LogStore.
  """
  use ExUnit.Case, async: false

  alias Genswarms.SwarmManager
  alias Genswarms.CLI.SwarmRegistry
  alias Genswarms.Objects.ObjectServer
  alias Genswarms.Observability.LogStore

  defmodule FragileCounter do
    @moduledoc "Counts messages; 'boom'/'toss'/'bail' crash in three flavors."
    @behaviour Genswarms.Objects.ObjectHandler

    @impl true
    def init(config), do: {:ok, %{count: 0, test_pid: config[:test_pid]}}

    @impl true
    def handle_message(_from, "boom", _state), do: raise("kaboom")
    def handle_message(_from, "toss", _state), do: throw(:tossed)
    def handle_message(_from, "bail", _state), do: exit(:bailed)

    def handle_message(_from, "link_bomb", state) do
      # the previously silent killer: a linked process dying abnormally
      # AFTER the handler returned (an async exit signal, not an in-stack
      # exit) — System.cmd ports and accidental links behave like this
      spawn_link(fn -> exit(:linked_boom) end)
      {:noreply, state}
    end

    def handle_message(_from, _content, state) do
      state = %{state | count: state.count + 1}
      send(state.test_pid, {:counted, state.count})
      {:noreply, state}
    end

    @impl true
    def handle_info({:tick_boom, _}, _state), do: raise("info kaboom")

    def handle_info({:tick, _}, state) do
      state = %{state | count: state.count + 1}
      send(state.test_pid, {:counted, state.count})
      {:noreply, state}
    end

    def handle_info(_msg, state), do: {:noreply, state}

    @impl true
    def interface(), do: %{}
  end

  setup do
    swarm = "crash-contain-#{System.unique_integer([:positive])}"
    workspace = Path.join(System.tmp_dir!(), swarm)
    File.mkdir_p!(workspace)

    config = %{
      name: swarm,
      agents: [
        %{name: :alpha, backend: :mock, config: %{workspace: workspace}}
      ],
      objects: [
        %{name: :fragile, handler: FragileCounter, config: %{test_pid: self()}}
      ],
      topology: [{:alpha, :fragile}]
    }

    {:ok, ^swarm} = SwarmManager.start_from_config(config)
    SwarmRegistry.clear_overlay(swarm)

    # wait for the object to finish init
    pid = await_object(swarm, :fragile)

    on_exit(fn ->
      SwarmManager.stop(swarm)
      SwarmRegistry.clear_overlay(swarm)
      File.rm_rf(workspace)
    end)

    {:ok, swarm: swarm, pid: pid}
  end

  defp await_object(swarm, name, tries \\ 50) do
    case GenServer.whereis(ObjectServer.via_tuple(swarm, name)) do
      pid when is_pid(pid) ->
        if :sys.get_state(pid).state == :idle do
          pid
        else
          Process.sleep(20)
          await_object(swarm, name, tries - 1)
        end

      nil when tries > 0 ->
        Process.sleep(20)
        await_object(swarm, name, tries - 1)

      nil ->
        flunk("object #{name} never registered")
    end
  end

  defp deliver(swarm, content) do
    ObjectServer.deliver_message(swarm, :fragile, "tester", content)
  end

  defp crash_events(swarm) do
    [swarm: swarm, limit: 50]
    |> LogStore.query()
    |> Enum.filter(&(&1.event_type == :handler_crashed))
  end

  test "a raising handler keeps its pid AND its state", %{swarm: swarm, pid: pid} do
    deliver(swarm, "one")
    assert_receive {:counted, 1}, 2_000

    deliver(swarm, "boom")
    deliver(swarm, "two")

    # state survived the raise: the counter continued from 1, on the same pid
    assert_receive {:counted, 2}, 2_000
    assert GenServer.whereis(ObjectServer.via_tuple(swarm, :fragile)) == pid
    assert :sys.get_state(pid).state == :idle
  end

  test "throw and exit are contained the same way", %{swarm: swarm, pid: pid} do
    deliver(swarm, "toss")
    deliver(swarm, "bail")
    deliver(swarm, "after")

    assert_receive {:counted, 1}, 2_000
    assert GenServer.whereis(ObjectServer.via_tuple(swarm, :fragile)) == pid
  end

  test "the crash is queryable in LogStore with the reason", %{swarm: swarm} do
    deliver(swarm, "boom")
    deliver(swarm, "sync")
    assert_receive {:counted, 1}, 2_000

    assert [event | _] = crash_events(swarm)
    assert event.level == :error
    assert event.message =~ "raised"
    assert event.message =~ "kaboom"
    assert event.metadata.stacktrace =~ "object_server_crash_containment_test"
  end

  test "an abnormal LINKED exit no longer kills the object silently", %{swarm: swarm, pid: pid} do
    deliver(swarm, "link_bomb")
    deliver(swarm, "after the bomb")

    # the object outlived the linked death, same pid, and it's queryable
    assert_receive {:counted, 1}, 2_000
    assert GenServer.whereis(ObjectServer.via_tuple(swarm, :fragile)) == pid

    linked =
      [swarm: swarm, limit: 50]
      |> LogStore.query()
      |> Enum.filter(&(&1.event_type == :linked_exit))

    assert [event | _] = linked
    assert event.message =~ "linked_boom"
  end

  test "a raising handle_info keeps the object alive", %{swarm: swarm, pid: pid} do
    send(pid, {:tick_boom, 1})
    send(pid, {:tick, 1})

    # the timer path crashed, was logged, and the next tick still counted
    assert_receive {:counted, 1}, 2_000
    assert GenServer.whereis(ObjectServer.via_tuple(swarm, :fragile)) == pid
    assert [event | _] = crash_events(swarm)
    assert event.message =~ "handle_info"
  end
end
