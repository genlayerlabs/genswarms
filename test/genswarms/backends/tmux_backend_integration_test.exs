defmodule Genswarms.Backends.TmuxBackendIntegrationTest do
  use ExUnit.Case, async: true

  alias Genswarms.Backends.Tmux.AdapterHelpers
  alias Genswarms.Backends.Tmux.SessionWorker
  alias Genswarms.Backends.TmuxBackend

  defmodule FakeAdapter do
    @behaviour Genswarms.Backends.Tmux.Adapter

    @impl true
    def client, do: :fake

    @impl true
    def launch(config) do
      {:ok,
       %{
         executable: "/bin/sh",
         args: [
           Map.fetch!(config, :fake_tui_script),
           Map.fetch!(config, :workspace),
           Map.fetch!(config, :swarm_name),
           Map.fetch!(config, :agent_name),
           Map.get(config, :fake_mode, "complete")
         ],
         env: []
       }}
    end

    @impl true
    def ready?(snapshot, _config), do: String.contains?(snapshot, "FAKE_TUI_READY")

    @impl true
    def blocked?(_snapshot, _config), do: false

    @impl true
    def nudge(turn, config), do: AdapterHelpers.nudge(turn, config)
  end

  setup do
    if is_nil(System.find_executable("tmux")) do
      {:skip, "tmux is not installed"}
    else
      unique = System.unique_integer([:positive])
      root = Path.join(System.tmp_dir!(), "genswarms-tmux-test-#{unique}")
      socket = "gstest#{unique}"
      session = "gstest#{unique}"
      File.mkdir_p!(root)

      on_exit(fn ->
        System.cmd("tmux", ["-L", socket, "kill-session", "-t", session], stderr_to_stdout: true)

        File.rm_rf!(root)
      end)

      {:ok, root: root, socket: socket, session: session}
    end
  end

  test "runs a durable turn, acknowledges it, and reattaches to the live pane", context do
    backend_id = make_ref()
    config = backend_config(context, backend_id)

    assert {:ok, ref} = TmuxBackend.start("worker", config)
    assert_receive {:genswarms_backend_event, ^backend_id, {:lifecycle, :started, started}}, 2_000
    refute started.reattached
    assert_receive {:genswarms_backend_event, ^backend_id, {:lifecycle, :ready, _}}, 2_000

    message = Jason.encode!(%{type: "task", from: "orchestrator", content: "do the test"})
    assert {:ok, %{turn_id: turn_id}} = TmuxBackend.send_input(ref, message)

    assert_receive {:genswarms_backend_event, ^backend_id,
                    {:lifecycle, :running, %{turn_id: ^turn_id}}},
                   1_000

    assert_receive {:genswarms_backend_event, ^backend_id,
                    {:turn_completed, ^turn_id, reply, metadata}},
                   2_000

    assert reply == "fake reply for #{turn_id}\n"
    assert metadata.task_path =~ turn_id

    task_document = File.read!(metadata.task_path)
    assert task_document =~ "read every regular Markdown file"
    assert task_document =~ "Treat those files as binding"
    assert task_document =~ "worker instructions"
    assert task_document =~ "Re-scan this turn directory before finishing"

    refute File.exists?(
             Path.join(metadata |> Map.fetch!(:task_path) |> Path.dirname(), "ack.json")
           )

    assert :ok = TmuxBackend.acknowledge(ref, turn_id)
    assert File.exists?(Path.join(Path.dirname(metadata.task_path), "ack.json"))

    assert_receive {:genswarms_backend_event, ^backend_id, {:lifecycle, :ready, _}}, 2_000

    session_info = TmuxBackend.session_info(ref)
    assert session_info.phase == :idle
    assert session_info.session == context.session

    assert session_info.attach.read_only.args == [
             "-L",
             context.socket,
             "attach-session",
             "-r",
             "-t",
             "#{context.session}:worker"
           ]

    assert :ok = TmuxBackend.disconnect(ref)

    second_id = make_ref()
    assert {:ok, second_ref} = TmuxBackend.start("worker", backend_config(context, second_id))

    assert_receive {:genswarms_backend_event, ^second_id,
                    {:lifecycle, :started, %{reattached: true}}},
                   2_000

    assert_receive {:genswarms_backend_event, ^second_id, {:lifecycle, :ready, _}}, 2_000
    assert :ok = TmuxBackend.destroy(second_ref)
  end

  test "submits one extra Enter when the exact nudge remains staged at the cursor", context do
    backend_id = make_ref()

    config =
      backend_config(context, backend_id)
      |> Map.put(:fake_mode, "needs_second_enter")

    assert {:ok, ref} = TmuxBackend.start("worker", config)
    assert_receive {:genswarms_backend_event, ^backend_id, {:lifecycle, :ready, _}}, 2_000

    assert {:ok, %{turn_id: turn_id}} =
             TmuxBackend.send_input(
               ref,
               Jason.encode!(%{type: "task", content: "recover staged input"})
             )

    assert_receive {:genswarms_backend_event, ^backend_id,
                    {:turn_completed, ^turn_id, reply,
                     %{submission_attempts: 2, submission_pending: true}}},
                   2_000

    assert reply == "fake reply for #{turn_id}\n"
    assert :ok = TmuxBackend.destroy(ref)
  end

  test "needs human attention when a staged nudge survives the bounded Enter retry", context do
    backend_id = make_ref()

    config =
      backend_config(context, backend_id)
      |> Map.put(:fake_mode, "never_submit")

    assert {:ok, ref} = TmuxBackend.start("worker", config)
    assert_receive {:genswarms_backend_event, ^backend_id, {:lifecycle, :ready, _}}, 2_000

    assert {:ok, %{turn_id: turn_id}} =
             TmuxBackend.send_input(
               ref,
               Jason.encode!(%{type: "task", content: "leave staged"})
             )

    assert_receive {:genswarms_backend_event, ^backend_id,
                    {:lifecycle, :needs_attention,
                     %{turn_id: ^turn_id, reason: :nudge_not_submitted, submit_attempts: 2}}},
                   2_000

    refute_receive {:genswarms_backend_event, ^backend_id,
                    {:turn_completed, ^turn_id, _reply, _metadata}},
                   100

    assert :ok = TmuxBackend.destroy(ref)
  end

  test "does not retry Enter after the TUI has visibly started working", context do
    backend_id = make_ref()

    config =
      backend_config(context, backend_id)
      |> Map.put(:fake_mode, "working_hold")

    assert {:ok, ref} = TmuxBackend.start("worker", config)
    assert_receive {:genswarms_backend_event, ^backend_id, {:lifecycle, :ready, _}}, 2_000

    assert {:ok, %{turn_id: turn_id}} =
             TmuxBackend.send_input(
               ref,
               Jason.encode!(%{type: "task", content: "keep working"})
             )

    assert_receive {:genswarms_backend_event, ^backend_id,
                    {:lifecycle, :running, %{turn_id: ^turn_id}}},
                   1_000

    Process.sleep(250)
    assert %{phase: :running, submission_pending: false} = TmuxBackend.session_info(ref)
    refute File.exists?(Path.join(context.root, "unexpected-enter"))
    assert :ok = TmuxBackend.destroy(ref)
  end

  test "an unacknowledged active turn is recovered visibly after reconnect", context do
    first_id = make_ref()
    config = backend_config(context, first_id) |> Map.put(:fake_mode, "hold")

    assert {:ok, ref} = TmuxBackend.start("worker", config)
    assert_receive {:genswarms_backend_event, ^first_id, {:lifecycle, :ready, _}}, 2_000

    message = Jason.encode!(%{type: "task", content: "hold this turn"})
    assert {:ok, %{turn_id: turn_id}} = TmuxBackend.send_input(ref, message)
    assert_receive {:genswarms_backend_event, ^first_id, {:lifecycle, :running, _}}, 1_000
    assert :ok = TmuxBackend.disconnect(ref)

    second_id = make_ref()
    reconnect = backend_config(context, second_id) |> Map.put(:fake_mode, "hold")
    assert {:ok, second_ref} = TmuxBackend.start("worker", reconnect)

    assert_receive {:genswarms_backend_event, ^second_id,
                    {:lifecycle, :started, %{reattached: true}}},
                   2_000

    assert_receive {:genswarms_backend_event, ^second_id,
                    {:lifecycle, :needs_attention,
                     %{reason: :incomplete_turn_recovered, turn_id: ^turn_id}}},
                   2_000

    assert :ok = TmuxBackend.destroy(second_ref)
  end

  test "refuses to reuse a live pane with changed client launch arguments", context do
    config = backend_config(context, make_ref())
    assert {:ok, ref} = TmuxBackend.start("worker", config)
    assert_receive {:genswarms_backend_event, _, {:lifecycle, :ready, _}}, 2_000
    assert :ok = TmuxBackend.disconnect(ref)

    changed =
      config
      |> Map.put(:backend_id, make_ref())
      |> Map.put(:fake_mode, "hold")

    assert {:error, {:runtime_identity_mismatch, _identity}} =
             TmuxBackend.start("worker", changed)

    assert :ok = TmuxBackend.destroy(ref)
  end

  test "replaces stale runtime identity after the pane is gone", context do
    config = backend_config(context, make_ref())
    assert {:ok, ref} = TmuxBackend.start("worker", config)
    assert_receive {:genswarms_backend_event, _, {:lifecycle, :ready, _}}, 2_000
    assert :ok = TmuxBackend.disconnect(ref)

    assert {_, 0} =
             System.cmd(
               "tmux",
               ["-L", context.socket, "kill-session", "-t", context.session],
               stderr_to_stdout: true
             )

    changed =
      config
      |> Map.put(:backend_id, make_ref())
      |> Map.put(:fake_mode, "hold")

    assert {:ok, changed_ref} = TmuxBackend.start("worker", changed)
    assert_receive {:genswarms_backend_event, _, {:lifecycle, :ready, _}}, 2_000
    assert :ok = TmuxBackend.destroy(changed_ref)
  end

  test "rejects a symlinked agent reply instead of reading through it on the host", context do
    File.write!(Path.join(context.root, "host-secret.txt"), "must not become a reply")
    backend_id = make_ref()

    config =
      backend_config(context, backend_id)
      |> Map.put(:fake_mode, "symlink")

    assert {:ok, ref} = TmuxBackend.start("worker", config)
    assert_receive {:genswarms_backend_event, ^backend_id, {:lifecycle, :ready, _}}, 2_000

    assert {:ok, %{turn_id: turn_id}} =
             TmuxBackend.send_input(
               ref,
               Jason.encode!(%{type: "task", content: "attempt a symlinked reply"})
             )

    assert_receive {:genswarms_backend_event, ^backend_id,
                    {:lifecycle, :needs_attention,
                     %{turn_id: ^turn_id, reason: :invalid_completion_receipt}}},
                   2_000

    refute_receive {:genswarms_backend_event, ^backend_id,
                    {:turn_completed, ^turn_id, _reply, _metadata}},
                   100

    assert :ok = TmuxBackend.destroy(ref)
  end

  test "fails closed when tmux is asked to provide network isolation", context do
    config = backend_config(context, make_ref()) |> Map.put(:network, :isolated)

    assert {:error, {:unsupported_network, :isolated}} = TmuxBackend.start("worker", config)
  end

  test "a session-worker init error is returned without killing its caller", context do
    config =
      backend_config(context, make_ref())
      |> Map.put(:tmux_executable, "/definitely/missing/tmux")

    assert {:error, :tmux_not_found} =
             SessionWorker.start(
               owner: self(),
               backend_id: make_ref(),
               adapter: FakeAdapter,
               config: config,
               launch: %{executable: "/bin/sh", args: ["-c", "exit 0"], env: []}
             )

    assert Process.alive?(self())
  end

  defp backend_config(context, backend_id) do
    %{
      event_sink: self(),
      backend_id: backend_id,
      client: FakeAdapter,
      swarm_name: "testswarm",
      workspace: context.root,
      tmux_socket: context.socket,
      session_name: context.session,
      window_name: "worker",
      poll_interval_ms: 25,
      ready_quiet_ms: 50,
      submit_delay_ms: 0,
      submit_retry_after_ms: 75,
      fake_tui_script: Path.expand("../../support/tmux_fake_tui.sh", __DIR__)
    }
  end
end
