defmodule Genswarms.Backends.TmuxIsolatedRunnerIntegrationTest do
  use ExUnit.Case, async: false

  alias Genswarms.Backends.Bwrap.{CgroupManager, OverlayManager}
  alias Genswarms.Backends.Tmux.AdapterHelpers
  alias Genswarms.Backends.TmuxBackend

  @tmux_ready not is_nil(System.find_executable("tmux"))

  @docker_ready (case System.find_executable("docker") do
                   nil ->
                     false

                   docker ->
                     match?(
                       {_, 0},
                       System.cmd(docker, ["version", "--format", "{{.Server.Version}}"],
                         stderr_to_stdout: true
                       )
                     ) and
                       match?(
                         {_, 0},
                         System.cmd(docker, ["image", "inspect", "python:3.12-slim"],
                           stderr_to_stdout: true
                         )
                       )
                 end)

  @bwrap_ready not is_nil(System.find_executable("bwrap")) and
                 OverlayManager.infrastructure_ready?()

  @docker_skip (cond do
                  not @tmux_ready ->
                    "tmux is not installed"

                  not @docker_ready ->
                    "Docker or the cached python:3.12-slim image is unavailable"

                  true ->
                    false
                end)

  @bwrap_skip (cond do
                 not @tmux_ready -> "tmux is not installed"
                 not @bwrap_ready -> "bwrap infrastructure is unavailable"
                 true -> false
               end)

  defmodule FakeAdapter do
    @behaviour Genswarms.Backends.Tmux.Adapter

    @impl true
    def client, do: :fake_isolated

    @impl true
    def launch(config) do
      {:ok,
       %{
         executable: "/bin/sh",
         args: [
           Map.fetch!(config, :runtime_fake_tui_script),
           Map.fetch!(config, :runtime_workspace),
           Map.fetch!(config, :swarm_name),
           Map.fetch!(config, :agent_name),
           "complete"
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

  setup context do
    unique = System.unique_integer([:positive])
    root = Path.join(System.tmp_dir!(), "genswarms-isolated-tmux-test-#{unique}")
    workspace = Path.join(root, "workspace")
    state_dir = Path.join(root, "state")
    script = Path.join(workspace, "fake_tui.sh")
    socket = "gsiso#{unique}"
    session = "gsiso#{unique}"
    swarm = "isoswarm#{unique}"
    sandbox_id = "gstui-#{swarm}-worker"
    File.mkdir_p!(workspace)
    File.cp!(Path.expand("../../support/tmux_fake_tui.sh", __DIR__), script)
    File.chmod!(script, 0o755)

    on_exit(fn ->
      System.cmd("tmux", ["-L", socket, "kill-session", "-t", session], stderr_to_stdout: true)

      case context.runner do
        :docker ->
          docker = System.find_executable("docker")
          System.cmd(docker, ["rm", "-f", sandbox_id], stderr_to_stdout: true)

        :bwrap ->
          CgroupManager.kill_scope("szc-#{sandbox_id}")
          OverlayManager.cleanup_overlay(sandbox_id)
      end

      File.rm(
        Path.join([
          System.tmp_dir!(),
          "genswarms-tmux-control",
          "tmux",
          swarm,
          "worker.json"
        ])
      )

      File.rm_rf!(root)
    end)

    {:ok,
     root: root,
     workspace: workspace,
     state_dir: state_dir,
     script: script,
     socket: socket,
     session: session,
     swarm: swarm}
  end

  @tag runner: :docker, skip: @docker_skip
  test "runs a durable TUI turn inside a per-agent Docker container", context do
    backend_id = make_ref()

    config =
      base_config(context, backend_id)
      |> Map.merge(%{
        runner: :docker,
        image: "python:3.12-slim",
        network: :none,
        client_source: :runtime
      })

    assert {:ok, ref} = TmuxBackend.start("worker", config)
    assert_receive {:genswarms_backend_event, ^backend_id, {:lifecycle, :ready, _}}, 5_000

    assert {:ok, %{turn_id: turn_id}} =
             TmuxBackend.send_input(
               ref,
               Jason.encode!(%{type: "task", content: "docker isolated turn"})
             )

    assert_receive {:genswarms_backend_event, ^backend_id,
                    {:turn_completed, ^turn_id, reply, _metadata}},
                   5_000

    assert reply == "fake reply for #{turn_id}\n"
    assert :ok = TmuxBackend.acknowledge(ref, turn_id)
    assert_receive {:genswarms_backend_event, ^backend_id, {:lifecycle, :ready, _}}, 5_000

    info = TmuxBackend.session_info(ref)
    assert info.runner.kind == :docker
    assert info.runner.network == :none
    assert info.runner.container == "gstui-#{context.swarm}-worker"
    assert :ok = TmuxBackend.health_check(ref)
    assert :ok = TmuxBackend.disconnect(ref)

    reconnect_id = make_ref()
    reconnect_config = %{config | backend_id: reconnect_id}
    assert {:ok, reconnected} = TmuxBackend.start("worker", reconnect_config)

    assert_receive {:genswarms_backend_event, ^reconnect_id,
                    {:lifecycle, :started, %{reattached: true}}},
                   5_000

    assert_receive {:genswarms_backend_event, ^reconnect_id, {:lifecycle, :ready, _}}, 5_000
    assert :ok = TmuxBackend.destroy(reconnected)

    assert {output, status} =
             System.cmd("docker", ["inspect", "gstui-#{context.swarm}-worker"],
               stderr_to_stdout: true
             )

    assert status != 0
    assert String.contains?(String.downcase(output), "no such")
  end

  @tag runner: :bwrap, skip: @bwrap_skip
  test "runs a durable TUI turn inside a per-agent rootless bwrap sandbox", context do
    backend_id = make_ref()

    config =
      base_config(context, backend_id)
      |> Map.merge(%{
        runner: :bwrap,
        network: :none,
        client_source: :runtime,
        privilege_mode: :rootless,
        presets: [:base],
        store: :full
      })

    assert {:ok, ref} = TmuxBackend.start("worker", config)
    assert_receive {:genswarms_backend_event, ^backend_id, {:lifecycle, :ready, _}}, 5_000

    assert {:ok, %{turn_id: turn_id}} =
             TmuxBackend.send_input(
               ref,
               Jason.encode!(%{type: "task", content: "bwrap isolated turn"})
             )

    assert_receive {:genswarms_backend_event, ^backend_id,
                    {:turn_completed, ^turn_id, reply, _metadata}},
                   5_000

    assert reply == "fake reply for #{turn_id}\n"
    assert :ok = TmuxBackend.acknowledge(ref, turn_id)
    assert_receive {:genswarms_backend_event, ^backend_id, {:lifecycle, :ready, _}}, 5_000

    info = TmuxBackend.session_info(ref)
    assert info.runner.kind == :bwrap
    assert info.runner.network == :none
    assert info.runner.privilege_mode == :rootless
    assert :ok = TmuxBackend.health_check(ref)
    assert :ok = TmuxBackend.disconnect(ref)

    reconnect_id = make_ref()
    reconnect_config = %{config | backend_id: reconnect_id}
    assert {:ok, reconnected} = TmuxBackend.start("worker", reconnect_config)

    assert_receive {:genswarms_backend_event, ^reconnect_id,
                    {:lifecycle, :started, %{reattached: true}}},
                   5_000

    assert_receive {:genswarms_backend_event, ^reconnect_id, {:lifecycle, :ready, _}}, 5_000
    assert :ok = TmuxBackend.destroy(reconnected)
    refute File.exists?(Path.join("/run/swarm/agents", "gstui-#{context.swarm}-worker"))
  end

  @tag runner: :bwrap, skip: @bwrap_skip
  test "cleans a newly-created bwrap sandbox when preparation fails", context do
    config =
      base_config(context, make_ref())
      |> Map.merge(%{
        runner: :bwrap,
        network: :none,
        client_source: :runtime,
        privilege_mode: :rootless,
        presets: [:base],
        store: :unsupported
      })

    assert {:error, {:unknown_store_mode, :unsupported}} = TmuxBackend.start("worker", config)
    refute File.exists?(Path.join("/run/swarm/agents", "gstui-#{context.swarm}-worker"))
  end

  @tag runner: :bwrap, skip: @bwrap_skip
  test "refuses to reattach a live bwrap pane under a changed isolation contract", context do
    config =
      base_config(context, make_ref())
      |> Map.merge(%{
        runner: :bwrap,
        network: :none,
        client_source: :runtime,
        privilege_mode: :rootless,
        presets: [:base],
        store: :full
      })

    assert {:ok, ref} = TmuxBackend.start("worker", config)
    assert_receive {:genswarms_backend_event, _, {:lifecycle, :ready, _}}, 5_000
    assert :ok = TmuxBackend.disconnect(ref)

    changed = config |> Map.put(:backend_id, make_ref()) |> Map.put(:memory_limit, "3G")

    assert {:error, {:runner_state_mismatch, :bwrap_config_changed}} =
             TmuxBackend.start("worker", changed)

    assert :ok = TmuxBackend.destroy(ref)
  end

  defp base_config(context, backend_id) do
    %{
      event_sink: self(),
      backend_id: backend_id,
      client: FakeAdapter,
      swarm_name: context.swarm,
      workspace: context.workspace,
      state_dir: context.state_dir,
      tmux_socket: context.socket,
      session_name: context.session,
      window_name: "worker",
      poll_interval_ms: 25,
      ready_quiet_ms: 50,
      runtime_fake_tui_script: "/workspace/fake_tui.sh"
    }
  end
end
