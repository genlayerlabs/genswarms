defmodule Genswarms.Backends.Tmux.ClientIsolationIntegrationTest do
  use ExUnit.Case, async: false

  alias Genswarms.Backends.Bwrap.{CgroupManager, OverlayManager}
  alias Genswarms.Backends.Tmux.Runners.{Bwrap, Docker}

  @clients [:codex, :claude, :opencode]

  @host_nix_ready not is_nil(System.find_executable("nix-store")) and
                    Enum.all?(@clients, fn client ->
                      case System.find_executable(to_string(client)) do
                        nil ->
                          false

                        executable ->
                          case :file.read_link_all(String.to_charlist(executable)) do
                            {:ok, resolved} ->
                              resolved |> List.to_string() |> String.starts_with?("/nix/store/")

                            {:error, _reason} ->
                              false
                          end
                      end
                    end)

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
                  not @host_nix_ready ->
                    "Codex, Claude, and OpenCode must be Nix-installed"

                  not @docker_ready ->
                    "Docker or the cached python:3.12-slim image is unavailable"

                  true ->
                    false
                end)

  @bwrap_skip (cond do
                 not @host_nix_ready -> "Codex, Claude, and OpenCode must be Nix-installed"
                 not @bwrap_ready -> "bwrap infrastructure is unavailable"
                 true -> false
               end)

  setup context do
    unique = System.unique_integer([:positive])
    swarm = "client-smoke-#{unique}"
    root = Path.join(System.tmp_dir!(), "genswarms-tmux-client-smoke-#{unique}")
    File.mkdir_p!(root)

    on_exit(fn ->
      Enum.each(@clients, fn client ->
        sandbox_id = "gstui-#{swarm}-#{client}"

        case context.runner do
          :docker ->
            docker = System.find_executable("docker")
            System.cmd(docker, ["rm", "-f", sandbox_id], stderr_to_stdout: true)

          :bwrap ->
            CgroupManager.kill_scope("szc-#{sandbox_id}")
            OverlayManager.cleanup_overlay(sandbox_id)
        end
      end)

      _ = File.rm_rf(root)
    end)

    {:ok, root: root, swarm: swarm}
  end

  @tag runner: :docker, skip: @docker_skip
  test "host Nix closures run Codex, Claude, and OpenCode inside per-agent Docker containers",
       context do
    Enum.each(@clients, fn client ->
      config = runner_config(context, client, :docker)
      assert {:ok, configured} = Docker.configure(config)

      launch = %{
        executable: System.find_executable(to_string(client)),
        args: ["--version"],
        env: []
      }

      assert {:ok, ref, wrapped} = Docker.prepare(configured, launch, :missing)

      try do
        client_argv = argv_after(wrapped.args, ref.container_name)

        assert {output, 0} =
                 System.cmd(wrapped.executable, ["exec", ref.container_name | client_argv],
                   stderr_to_stdout: true
                 )

        assert String.trim(output) != ""
      after
        Docker.destroy(ref)
      end
    end)
  end

  @tag runner: :bwrap, skip: @bwrap_skip
  test "host Nix closures run Codex, Claude, and OpenCode inside per-agent bwrap sandboxes",
       context do
    Enum.each(@clients, fn client ->
      config = runner_config(context, client, :bwrap)
      assert {:ok, configured} = Bwrap.configure(config)

      launch = %{
        executable: System.find_executable(to_string(client)),
        args: ["--version"],
        env: []
      }

      assert {:ok, ref, wrapped} = Bwrap.prepare(configured, launch, :missing)

      try do
        {output, status} =
          System.cmd(wrapped.executable, wrapped.args, stderr_to_stdout: true)

        assert status == 0, "#{client} exited #{status}: #{String.slice(output, 0, 300)}"
        assert String.trim(output) != ""
      after
        Bwrap.destroy(ref)
      end
    end)
  end

  defp runner_config(context, client, runner) do
    workspace = Path.join([context.root, to_string(client), "workspace"])
    state_dir = Path.join([context.root, to_string(client), "state"])
    File.mkdir_p!(workspace)

    %{
      runner: runner,
      swarm_name: context.swarm,
      agent_name: to_string(client),
      client: client,
      workspace: workspace,
      state_dir: state_dir,
      network: :none,
      client_source: :host_nix,
      image: "python:3.12-slim",
      privilege_mode: :rootless,
      presets: [:base],
      store: :closure
    }
  end

  defp argv_after(args, marker) do
    case Enum.split_while(args, &(&1 != marker)) do
      {_before, [^marker | argv]} -> argv
      _ -> flunk("runner launch does not contain its container name")
    end
  end
end
