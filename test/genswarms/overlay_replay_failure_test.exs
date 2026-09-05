defmodule Genswarms.OverlayReplayFailureTest do
  use ExUnit.Case, async: false

  alias Genswarms.CLI.SwarmRegistry
  alias Genswarms.SwarmManager

  defmodule Probe do
    @behaviour Genswarms.Objects.ObjectHandler
    def init(config) do
      send(Process.whereis(__MODULE__), {:booted, config[:label]})
      {:ok, %{}}
    end

    def handle_message(_, _, state), do: {:noreply, state}
    def interface, do: %{}
  end

  defmodule Reject do
    @behaviour Genswarms.Objects.ObjectHandler
    def init(config), do: {:error, Map.get(config, :reason, :fixture_rejected)}
    def handle_message(_, _, state), do: {:noreply, state}
    def interface, do: %{}
  end

  defmodule QueriesManager do
    @behaviour Genswarms.Objects.ObjectHandler
    def init(config) do
      {:ok, _} = SwarmManager.get_full_config(config.swarm)
      {:ok, %{}}
    end

    def handle_message(_, _, state), do: {:noreply, state}
    def interface, do: %{}
  end

  defmodule Blocked do
    @behaviour Genswarms.Objects.ObjectHandler
    def init(_) do
      send(Process.whereis(Probe), {:init_waiting, self()})

      receive do
        :release -> {:ok, %{}}
        :crash -> exit(:fixture_init_crash)
      end
    end

    def handle_message(_, _, state), do: {:noreply, state}
    def interface, do: %{}
  end

  setup do
    swarm = "replay-failure-#{System.unique_integer([:positive])}"
    Process.register(self(), Probe)
    Phoenix.PubSub.subscribe(Genswarms.PubSub, "swarm:#{swarm}")

    on_exit(fn ->
      SwarmManager.stop(swarm)
      SwarmRegistry.clear_overlay(swarm)
    end)

    seed = %{
      name: swarm,
      agents: [],
      topology: [],
      objects: [
        %{name: :seed, handler: Probe, config: %{label: :seed}}
      ]
    }

    {:ok, swarm: swarm, seed: seed}
  end

  test "an unknown operation is refused before any seed handler boots", %{
    swarm: swarm,
    seed: seed
  } do
    SwarmRegistry.append_overlay(swarm, :future_operation, %{private: "fixture-value"})

    assert {:error, {:overlay_replay_failed, 1, :future_operation, :unknown_operation}} =
             SwarmManager.start_from_config(seed)

    refute_received {:booted, _}
    refute_received {:swarm_started, ^swarm, :running}
    assert {:error, :not_found} = SwarmManager.status(swarm)
  end

  test "failed handler recovery stops replay and cleans earlier starts", %{
    swarm: swarm,
    seed: seed
  } do
    manager = Process.whereis(SwarmManager)
    SwarmRegistry.append_overlay(swarm, :add_object, %{name: :broken, handler: Reject})

    SwarmRegistry.append_overlay(swarm, :add_object, %{
      name: :later,
      handler: Probe,
      config: %{label: :later}
    })

    assert {:error, {:overlay_replay_failed, 1, :add_object, _reason}} =
             SwarmManager.start_from_config(seed)

    assert_received {:booted, :seed}
    refute_received {:booted, :later}
    refute_received {:swarm_started, ^swarm, :running}
    assert Process.whereis(SwarmManager) == manager
    assert {:error, :not_found} = SwarmManager.status(swarm)
    assert [] = Registry.lookup(Genswarms.AgentRegistry, {swarm, :seed})
    assert length(SwarmRegistry.load_overlay(swarm)) == 2
  end

  test "a missing removal target is not silently acknowledged", %{swarm: swarm, seed: seed} do
    SwarmRegistry.append_overlay(swarm, :remove_object, %{name: :missing})

    assert {:error, {:overlay_replay_failed, 1, :remove_object, :not_found}} =
             SwarmManager.start_from_config(seed)

    refute_received {:swarm_started, ^swarm, :running}
  end

  test "a rejected package stops replay and cleans the seed without deleting the log", %{
    swarm: swarm,
    seed: seed
  } do
    missing = Path.join(System.tmp_dir!(), "missing-package-#{swarm}")
    refute File.exists?(missing)
    handler = %{ref: "swarmidx:fixture/missing@1.0.0", digest: "sha256:aaaa", path: missing}
    SwarmRegistry.append_overlay(swarm, :add_object, %{name: :broken, handler: handler})

    SwarmRegistry.append_overlay(swarm, :add_object, %{
      name: :later,
      handler: Probe,
      config: %{label: :later}
    })

    assert {:error, {:overlay_replay_failed, 1, :add_object, {:handler_ref, :broken, _}}} =
             SwarmManager.start_from_config(seed)

    refute_received {:booted, :later}
    refute_received {:swarm_started, ^swarm, :running}
    assert {:error, :not_found} = SwarmManager.status(swarm)
    assert [] = Registry.lookup(Genswarms.AgentRegistry, {swarm, :seed})
    assert length(SwarmRegistry.load_overlay(swarm)) == 2
  end

  test "malformed updates are refused before prefolding or booting", %{swarm: swarm, seed: seed} do
    SwarmRegistry.append_overlay(swarm, :update_config, %{name: :seed, config: "not a map"})

    assert {:error, {:overlay_replay_failed, 1, :update_config, :invalid_payload}} =
             SwarmManager.start_from_config(seed)

    refute_received {:booted, _}
  end

  test "init can query the manager without deadlocking startup", %{swarm: swarm, seed: seed} do
    seed = %{seed | objects: [%{name: :query, handler: QueriesManager, config: %{swarm: swarm}}]}
    assert {:ok, ^swarm} = SwarmManager.start_from_config(seed)
    assert_received {:swarm_started, ^swarm, :running}
  end

  test "stop cancels pending readiness and stale timers cannot affect a new start", %{
    swarm: swarm,
    seed: seed
  } do
    blocked = %{seed | objects: [%{name: :blocked, handler: Blocked}]}
    task = Task.async(fn -> SwarmManager.start_from_config(blocked) end)
    assert_receive {:init_waiting, pid}, 1_000
    token = :sys.get_state(SwarmManager).starts[swarm].token
    assert {:ok, %{status: :starting, runtime_pending: true}} = SwarmManager.status(swarm)

    assert {:ok, _} = SwarmManager.stop(swarm)
    assert {:error, :start_cancelled} = Task.await(task, 10_000)
    refute Process.alive?(pid)
    assert [] = Registry.lookup(Genswarms.AgentRegistry, {swarm, :blocked})

    assert {:ok, ^swarm} = SwarmManager.start_from_config(seed)
    send(Process.whereis(SwarmManager), {:startup_timeout, swarm, token})
    assert {:ok, %{status: :running}} = SwarmManager.status(swarm)
  end

  test "startup deadline cleans a handler that never finishes init", %{swarm: swarm, seed: seed} do
    previous = Application.fetch_env(:genswarms, :startup_timeout_ms)
    Application.put_env(:genswarms, :startup_timeout_ms, 50)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:genswarms, :startup_timeout_ms, value)
        :error -> Application.delete_env(:genswarms, :startup_timeout_ms)
      end
    end)

    seed = %{seed | objects: [%{name: :blocked, handler: Blocked}]}
    task = Task.async(fn -> SwarmManager.start_from_config(seed) end)
    assert_receive {:init_waiting, pid}, 1_000
    assert {:error, {:startup_failed, :timeout}} = Task.await(task, 10_000)
    refute Process.alive?(pid)
    assert {:error, :not_found} = SwarmManager.status(swarm)
    refute_received {:swarm_started, ^swarm, :running}
  end

  test "an init exit is reported without a restart loop or killing the manager", %{
    swarm: swarm,
    seed: seed
  } do
    manager = Process.whereis(SwarmManager)
    seed = %{seed | objects: [%{name: :blocked, handler: Blocked}]}
    task = Task.async(fn -> SwarmManager.start_from_config(seed) end)
    assert_receive {:init_waiting, pid}, 1_000
    send(pid, :crash)
    assert {:error, {:startup_failed, {:object_not_ready, :blocked}}} = Task.await(task, 10_000)
    refute Process.alive?(pid)
    refute_receive {:init_waiting, _}, 100
    assert Process.whereis(SwarmManager) == manager
    assert {:error, :not_found} = SwarmManager.status(swarm)
  end

  test "init error values are not copied into startup logs", %{swarm: swarm, seed: seed} do
    marker = "fixture-sensitive-init-payload"
    seed = %{seed | objects: [%{name: :reject, handler: Reject, config: %{reason: marker}}]}

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert {:error, {:startup_failed, {:object_not_ready, :reject}}} =
                 SwarmManager.start_from_config(seed)
      end)

    refute log =~ marker
    assert {:error, :not_found} = SwarmManager.status(swarm)
  end
end
