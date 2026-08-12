defmodule Genswarms.Backends.Tmux.RunnersTest do
  use ExUnit.Case, async: true

  alias Genswarms.Backends.Tmux.Adapters.{Claude, Codex, OpenCode}
  alias Genswarms.Backends.Tmux.ArgvFile
  alias Genswarms.Backends.Tmux.RunnerStore
  alias Genswarms.Backends.Tmux.Runners
  alias Genswarms.Backends.Tmux.Runners.{Bwrap, Docker, Host}

  defmodule CommandRunner do
    @behaviour Genswarms.Backends.Tmux.RunnerCommand

    @impl true
    def run(executable, args) do
      owner = Process.get({__MODULE__, :owner})
      if owner, do: send(owner, {:runner_command, executable, args})
      Process.get({__MODULE__, :handler}, fn _executable, _args -> {"", 0} end).(executable, args)
    end
  end

  setup do
    root = Path.join(System.tmp_dir!(), "tmux-runner-test-#{System.unique_integer([:positive])}")
    workspace = Path.join(root, "workspace")
    state_dir = Path.join(root, "state")
    skills_dir = Path.join(root, "skills")
    File.mkdir_p!(workspace)
    File.mkdir_p!(skills_dir)
    Process.put({CommandRunner, :owner}, self())
    Process.delete({CommandRunner, :handler})
    on_exit(fn -> File.rm_rf!(root) end)

    {:ok, root: root, workspace: workspace, state_dir: state_dir, skills_dir: skills_dir}
  end

  test "resolves only the supported host, Docker, and bwrap runners" do
    assert {:ok, Host} = Runners.resolve(:host)
    assert {:ok, Docker} = Runners.resolve("docker")
    assert {:ok, Bwrap} = Runners.resolve(:bwrap)
    assert {:error, {:unsupported_tmux_runner, :ssh}} = Runners.resolve(:ssh)
  end

  test "Docker creates an owned per-agent container and wraps the client with exec -it", ctx do
    Process.put({CommandRunner, :handler}, fn _executable, args ->
      case args do
        ["inspect", _name] -> {"Error: No such object", 1}
        ["run" | _] -> {"container-id\n", 0}
        ["rm", "-f", _name] -> {"container-id\n", 0}
      end
    end)

    config = docker_config(ctx)
    assert {:ok, configured} = Docker.configure(config)

    launch = %{executable: "codex", args: ["--no-alt-screen", "-C", "/workspace"], env: []}
    assert {:ok, ref, wrapped} = Docker.prepare(configured, launch, :missing)

    assert ref.container_name == "gstui-swarm-worker"
    assert ref.created?
    assert wrapped.executable == System.find_executable("echo")

    assert wrapped.args == [
             "exec",
             "-i",
             "-t",
             "--workdir",
             "/workspace",
             "gstui-swarm-worker",
             "codex",
             "--no-alt-screen",
             "-C",
             "/workspace"
           ]

    assert_receive {:runner_command, docker, ["run" | create_args]}
    assert docker == System.find_executable("echo")
    assert "--network" in create_args
    assert "none" in create_args
    assert "io.genswarms.client=codex" in create_args
    assert Enum.any?(create_args, &String.contains?(&1, "dst=/workspace"))
    assert Enum.any?(create_args, &String.contains?(&1, "dst=/root"))
    assert Enum.any?(create_args, &String.contains?(&1, "dst=/skills,readonly"))

    assert :ok = Docker.destroy(ref)
  end

  test "Docker refuses to reuse a container not owned by this agent", ctx do
    inspect =
      Jason.encode!([
        %{
          "State" => %{"Running" => true},
          "Config" => %{"Image" => "runner:test", "Labels" => %{"owner" => "someone"}}
        }
      ])

    Process.put({CommandRunner, :handler}, fn _executable, ["inspect", _name] ->
      {inspect, 0}
    end)

    assert {:ok, configured} = Docker.configure(docker_config(ctx))

    assert {:error, {:container_identity_mismatch, _label}} =
             Docker.prepare(configured, %{executable: "codex", args: [], env: []}, %{
               dead?: false
             })

    refute_receive {:runner_command, _, ["run" | _]}
  end

  test "Docker rejects an image value that could be parsed as a CLI option", ctx do
    config = docker_config(ctx) |> Map.put(:image, "--privileged")
    assert {:ok, configured} = Docker.configure(config)

    assert {:error, {:invalid_docker_image, "--privileged"}} =
             Docker.prepare(configured, %{executable: "codex", args: [], env: []}, :missing)

    refute_receive {:runner_command, _, ["run" | _]}
  end

  test "Docker refuses a stale per-agent container contract", ctx do
    config = docker_config(ctx)
    assert {:ok, configured} = Docker.configure(config)

    labels =
      configured
      |> Docker.create_args("gstui-swarm-worker", "runner:test", [])
      |> labels_from_create_args()

    inspect =
      Jason.encode!([
        %{
          "State" => %{"Running" => true},
          "Config" => %{"Image" => "runner:test", "Labels" => labels, "Env" => []}
        }
      ])

    Process.put({CommandRunner, :handler}, fn _executable, ["inspect", _name] ->
      {inspect, 0}
    end)

    changed = %{configured | runner_network: :open}

    assert {:error, {:container_identity_mismatch, "io.genswarms.config-sha256"}} =
             Docker.prepare(changed, %{executable: "codex", args: [], env: []}, %{
               dead?: false
             })
  end

  test "Docker compares configured environment without exposing its value", ctx do
    config = docker_config(ctx) |> Map.put(:runner_env, %{"RUNNER_MODE" => "alpha"})
    assert {:ok, configured} = Docker.configure(config)

    create_args = Docker.create_args(configured, "gstui-swarm-worker", "runner:test", [])
    labels = labels_from_create_args(create_args)

    assert "--env-file" in create_args
    refute Enum.any?(create_args, &String.contains?(&1, "alpha"))

    inspect =
      Jason.encode!([
        %{
          "State" => %{"Running" => true},
          "Config" => %{
            "Image" => "runner:test",
            "Labels" => labels,
            "Env" => ["RUNNER_MODE=beta"]
          }
        }
      ])

    Process.put({CommandRunner, :handler}, fn _executable, ["inspect", _name] ->
      {inspect, 0}
    end)

    assert {:error, {:container_environment_mismatch, "RUNNER_MODE"}} =
             Docker.prepare(configured, %{executable: "codex", args: [], env: []}, %{
               dead?: false
             })
  end

  test "bwrap argv isolates mounts, processes, capabilities, and optional network", ctx do
    config =
      base_config(ctx)
      |> Map.merge(%{
        runner: :bwrap,
        network: :none,
        runner_network: :none,
        runtime_workspace: "/workspace",
        state_dir: ctx.state_dir
      })

    File.mkdir_p!(ctx.state_dir)

    launch = %{
      executable: "/bin/sh",
      args: ["/workspace/task;still-one-argv.sh"],
      env: []
    }

    assert {:ok, args} =
             Bwrap.build_bwrap_args(
               config,
               "/usr/bin/bwrap",
               "gstui-swarm-worker",
               Path.join(ctx.root, "overlay"),
               "/nix/store/base",
               ["/nix/store/client"],
               launch,
               [{"HOME", "/root"}, {"GH_TOKEN", "not-in-argv"}]
             )

    assert Enum.take(args, 2) == ["/usr/bin/bwrap", "--unshare-user"]
    assert "--unshare-net" in args
    assert "--unshare-pid" in args
    assert "--cap-drop" in args
    assert "ALL" in args
    assert "/nix/store/client" in args
    refute "--setenv" in args
    refute "not-in-argv" in args

    assert Enum.take(args, -5) == [
             "--",
             "/bin/sh",
             "/root/.genswarms/launch-with-env",
             "/bin/sh",
             "/workspace/task;still-one-argv.sh"
           ]

    command_index = Enum.find_index(args, &(&1 == "--"))

    assert Enum.slice(args, command_index + 1, 3) == [
             "/bin/sh",
             "/root/.genswarms/launch-with-env",
             launch.executable
           ]
  end

  test "bwrap writes runner secrets to private state rather than process argv", ctx do
    assert :ok =
             Bwrap.write_environment_files(ctx.state_dir, [
               {"HOME", "/root"},
               {"GH_TOKEN", "dummy'quoted\nvalue"}
             ])

    env_path = Path.join([ctx.state_dir, ".genswarms", "runner.env"])
    launcher_path = Path.join([ctx.state_dir, ".genswarms", "launch-with-env"])

    assert File.stat!(env_path).mode |> Bitwise.band(0o777) == 0o600
    assert File.stat!(launcher_path).mode |> Bitwise.band(0o777) == 0o700

    assert File.read!(launcher_path) ==
             "#!/bin/sh\nset -a\n. /root/.genswarms/runner.env\nset +a\nexec \"$@\"\n"

    assert File.read!(env_path) =~ ~s(GH_TOKEN='dummy'"'"'quoted)
  end

  test "large bwrap commands use a private NUL argv file without shell parsing", ctx do
    marker = Path.join(ctx.root, "must-not-exist")

    original = %{
      executable: System.find_executable("printf"),
      args: ["<%s>\\n", "literal; touch #{marker}", "$(id)", "line one\nline two"],
      env: []
    }

    assert {:ok, wrapped} = ArgvFile.wrap(base_config(ctx), original)
    assert wrapped.executable == System.find_executable("xargs")

    manifest = Path.join([ctx.state_dir, ".genswarms", "host-launch.argv0"])
    assert File.stat!(manifest).mode |> Bitwise.band(0o777) == 0o600
    assert File.read!(manifest) == Enum.map_join(original.args, <<0>>, & &1) <> <<0>>

    refute Enum.any?(wrapped.args, &String.contains?(&1, ["touch", "$(id)", "line one"]))

    {output, 0} = System.cmd(wrapped.executable, wrapped.args)
    assert output =~ "<literal; touch #{marker}>"
    assert output =~ "<$(id)>"
    assert output =~ "<line one\nline two>"
    refute File.exists?(marker)
  end

  test "all three client adapters target the isolated runtime workspace", ctx do
    for {client, adapter, executable} <- [
          {:codex, Codex, "codex"},
          {:claude, Claude, "claude"},
          {:opencode, OpenCode, "opencode"}
        ] do
      config = base_config(ctx) |> Map.put(:client, client) |> Map.put(:runner, :docker)
      assert {:ok, configured} = Docker.configure(config)
      assert {:ok, launch} = adapter.launch(configured)
      assert launch.executable == executable

      if client == :codex do
        assert Enum.chunk_every(launch.args, 2, 1, :discard)
               |> Enum.member?(["-C", "/workspace"])
      end
    end
  end

  test "the LLM-only egress mode fails closed for interactive clients", ctx do
    config = base_config(ctx) |> Map.put(:network, :isolated)
    assert {:error, :tui_egress_isolation_unsupported} = Docker.configure(config)
    assert {:error, :tui_egress_isolation_unsupported} = Bwrap.configure(config)
  end

  test "bwrap defaults interactive panes to the PTY-preserving rootless launcher", ctx do
    assert {:ok, configured} = Bwrap.configure(base_config(ctx))
    assert configured.privilege_mode == :rootless

    assert {:error, {:unsupported_bwrap_privilege_mode, :unknown}} =
             Bwrap.configure(base_config(ctx) |> Map.put(:privilege_mode, :unknown))
  end

  test "host Nix injection rejects store-path traversal", _ctx do
    paths = ["/nix/store/../../etc"]

    assert {:error, {:invalid_client_store_paths, ^paths}} =
             RunnerStore.closure(%{client_store_paths: paths}, "/nix/store/unused")
  end

  defp docker_config(ctx) do
    base_config(ctx)
    |> Map.merge(%{
      runner: :docker,
      image: "runner:test",
      network: :none,
      client_source: :runtime,
      docker_executable: System.find_executable("echo"),
      runner_command_runner: CommandRunner
    })
  end

  defp base_config(ctx) do
    %{
      swarm_name: "swarm",
      agent_name: "worker",
      client: :codex,
      workspace: ctx.workspace,
      state_dir: ctx.state_dir,
      skills_dir: ctx.skills_dir
    }
  end

  defp labels_from_create_args(args) do
    args
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce(%{}, fn
      ["--label", label], acc ->
        [key, value] = String.split(label, "=", parts: 2)
        Map.put(acc, key, value)

      _pair, acc ->
        acc
    end)
  end
end
