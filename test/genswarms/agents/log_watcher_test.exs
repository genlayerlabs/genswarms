defmodule Genswarms.Agents.LogWatcherTest do
  @moduledoc """
  LogWatcher must not retain an unbounded per-message hash set — position
  tracking already dedups (audit finding 32).
  """
  use ExUnit.Case, async: false

  alias Genswarms.Agents.{AgentServer, LogWatcher}
  alias Genswarms.{SwarmManager, Routing.Router}

  defmodule Recorder do
    @behaviour Genswarms.Objects.ObjectHandler
    def init(config), do: {:ok, config}

    def handle_message(from, content, state) do
      send(state.test_pid, {:recorded, from, content})
      {:reply, content, state}
    end

    def interface(), do: %{}
  end

  setup do
    dir = Path.join(System.tmp_dir!(), "logwatcher_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    {:ok, dir: dir}
  end

  test "state has no unbounded processed_hashes set", %{dir: dir} do
    {:ok, pid} =
      LogWatcher.start_link(
        swarm_name: "lw-test",
        agent_name: :lw_agent,
        log_dir: dir,
        workspace: dir
      )

    state = :sys.get_state(pid)

    refute Map.has_key?(state, :processed_hashes),
           "processed_hashes (unbounded growth) should be gone"

    assert Map.has_key?(state, :last_positions)

    GenServer.stop(pid)
  end

  defp watcher(dir, opts \\ []) do
    start_supervised!(
      {LogWatcher,
       Keyword.merge(
         [
           swarm_name: "lw-test",
           agent_name: :lw_agent,
           log_dir: dir,
           workspace: dir,
           track_sends: true
         ],
         opts
       )}
    )
  end

  defp fresh_name, do: "lw_unknown_#{System.unique_integer([:positive])}"

  defp outbox(dir, name, fields) do
    File.mkdir_p!(Path.join(dir, ".outbox"))
    path = Path.join([dir, ".outbox", name <> ".json"])
    File.write!(path, Jason.encode!(fields))
    path
  end

  defp assert_uninterned(name) do
    assert_raise ArgumentError, fn -> String.to_existing_atom(name) end
  end

  defp poll(pid) do
    send(pid, :poll)
    :sys.get_state(pid)
    # Drain routing casts before measuring VM-global atom counts.
    Router.get_message_log("lw-test")
  end

  defp start_swarm(dir) do
    swarm = "lw-flow-#{System.unique_integer([:positive])}"
    workspace = Path.join(dir, "asker")

    {:ok, ^swarm} =
      SwarmManager.start_from_config(%{
        name: swarm,
        agents: [%{name: :lw_agent, backend: :mock, config: %{workspace: workspace}}],
        objects: [%{name: :lw_recorder, handler: Recorder, config: %{test_pid: self()}}],
        topology: [{:lw_agent, :lw_recorder}]
      })

    on_exit(fn -> SwarmManager.stop(swarm) end)
    {swarm, workspace}
  end

  test "unknown outbox sends do not create atoms or count as routed sends", %{dir: dir} do
    pid = watcher(dir)
    outbox(dir, "warmup", %{to: fresh_name(), content: "warmup"})
    LogWatcher.sweep_outbox(pid)
    Router.get_message_log("lw-test")

    name = fresh_name()
    path = outbox(dir, "send", %{to: name, content: "x"})
    assert_uninterned(name)
    before = :erlang.system_info(:atom_count)
    targets = LogWatcher.sweep_outbox(pid, 5_000)
    after_count = :erlang.system_info(:atom_count)

    assert after_count == before
    assert_uninterned(name)
    assert targets == []
    refute File.exists?(path)

    path = outbox(dir, "poll_send", %{to: fresh_name(), content: "x"})
    poll(pid)
    assert LogWatcher.sweep_outbox(pid) == []
    refute File.exists?(path)
  end

  test "unknown outbox asks return a prompt target_not_found envelope without new atoms",
       %{dir: dir} do
    {swarm, workspace} = start_swarm(dir)
    pid = watcher(dir, swarm_name: swarm)

    for corr <- ["warmup", "unknown"] do
      name = fresh_name()
      path = outbox(dir, corr, %{to: name, content: "x", reply_to: corr})
      assert_uninterned(name)
      before = :erlang.system_info(:atom_count)
      assert LogWatcher.sweep_outbox(pid, 5_000) == []
      # Delivery must be a cast: the agent can be blocked in sweep_outbox/2.
      Router.get_message_log(swarm)
      :sys.get_state(AgentServer.via_tuple(swarm, :lw_agent))
      reply = Path.join([workspace, ".inbox", "replies", corr <> ".json"])
      envelope = reply |> File.read!() |> Jason.decode!()
      after_count = :erlang.system_info(:atom_count)

      if corr == "unknown" do
        assert after_count == before
        assert_uninterned(name)
      end

      assert envelope["ok"] == false
      assert envelope["timeout"] == false
      assert envelope["error"]["code"] == "target_not_found"
      assert envelope["correlation_id"] == corr
      refute File.exists?(path)
    end
  end

  test "invalid ask correlations are discarded before resolving the destination", %{dir: dir} do
    pid = watcher(dir)
    name = fresh_name()
    path = outbox(dir, "invalid", %{to: name, content: "x", reply_to: "../escape"})
    assert LogWatcher.sweep_outbox(pid) == []
    assert_uninterned(name)
    refute File.exists?(path)
  end

  test "unknown SWARM_MSG destinations do not create atoms", %{dir: dir} do
    pid = watcher(dir)
    log = Path.join(dir, "agent.txt")

    File.write!(
      log,
      "[2026-10-07 10:00:00] RES: <<SWARM_MSG:TO=#{fresh_name()}:START>>warmup<<SWARM_MSG:END>>\n"
    )

    poll(pid)

    name = fresh_name()

    File.write!(
      log,
      "[2026-10-07 10:00:01] RES: <<SWARM_MSG:TO=#{name}:START>>x<<SWARM_MSG:END>>\n",
      [:append]
    )

    assert_uninterned(name)
    before = :erlang.system_info(:atom_count)
    poll(pid)
    after_count = :erlang.system_info(:atom_count)

    assert after_count == before
    assert_uninterned(name)
    assert :sys.get_state(pid).last_positions[log] == File.stat!(log).size
  end

  test "known outbox targets and valid blocks beside unknown blocks still route", %{dir: dir} do
    {swarm, _workspace} = start_swarm(dir)
    pid = watcher(dir, swarm_name: swarm)
    path = outbox(dir, "known", %{to: "lw_recorder", content: "outbox"})
    assert LogWatcher.sweep_outbox(pid) == [:lw_recorder]
    refute File.exists?(path)
    assert_receive {:recorded, :lw_agent, "outbox"}, 1_000

    name = fresh_name()

    File.write!(Path.join(dir, "agent.txt"), """
    [2026-10-07 10:00:00] RES: <<SWARM_MSG:TO=#{name}:START>>drop<<SWARM_MSG:END>><<SWARM_MSG:TO=lw_recorder:START>>keep<<SWARM_MSG:END>><<SWARM_MSG:BROADCAST:START>>broadcast<<SWARM_MSG:END>>
    """)

    poll(pid)
    assert_receive {:recorded, :lw_agent, "keep"}, 1_000
    assert_receive {:recorded, :lw_agent, "broadcast"}, 1_000
    assert_uninterned(name)
  end
end
