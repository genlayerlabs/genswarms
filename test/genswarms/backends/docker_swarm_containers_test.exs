defmodule Genswarms.Backends.DockerSwarmContainersTest do
  use ExUnit.Case, async: false

  alias Genswarms.Backends.DockerBackend
  alias Genswarms.SwarmManager

  setup do
    dir = Path.join(System.tmp_dir!(), "docker-list-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = System.get_env("PATH")
    System.put_env("PATH", dir)

    on_exit(fn ->
      System.put_env("PATH", path)
      File.rm_rf!(dir)
    end)

    {:ok, dir: dir}
  end

  test "selects running, all, and paused containers with the corresponding Docker filters", %{
    dir: dir
  } do
    docker(dir, "printf 'szc-demo-agent\\n'")

    for {state, expected} <- [
          {:running, ["ps", "--filter", "name=szc-demo-", "--format", "{{.Names}}"]},
          {:all, ["ps", "-a", "--filter", "name=szc-demo-", "--format", "{{.Names}}"]},
          {:paused,
           [
             "ps",
             "--filter",
             "name=szc-demo-",
             "--filter",
             "status=paused",
             "--format",
             "{{.Names}}"
           ]}
        ] do
      assert {:ok, ["szc-demo-agent"]} = DockerBackend.swarm_containers("demo", state)
      assert File.read!(Path.join(dir, "args")) |> String.split("\n", trim: true) == expected
    end
  end

  test "rejects Docker substring and regex matches outside the literal swarm prefix", %{dir: dir} do
    docker(
      dir,
      "printf 'szc-demo-agent\\nother-szc-demo-agent\\nszc-demo2-agent\\nszc-demox-agent\\n\\nszc-demo-second\\n'"
    )

    assert {:ok, ["szc-demo-agent", "szc-demo-second"]} =
             DockerBackend.swarm_containers("demo", :all)
  end

  test "keeps an untrusted swarm name in a single literal argv element", %{dir: dir} do
    marker = Path.join(dir, "injected")
    swarm = "demo; touch #{marker}; $(touch #{marker})"
    docker(dir, "printf ''")

    assert {:ok, []} = DockerBackend.swarm_containers(swarm, :running)

    assert File.read!(Path.join(dir, "args")) |> String.split("\n", trim: true) == [
             "ps",
             "--filter",
             "name=szc-#{swarm}-",
             "--format",
             "{{.Names}}"
           ]

    refute File.exists?(marker)
  end

  test "returns the Docker error instead of treating a failed list as an empty swarm", %{dir: dir} do
    docker(dir, "printf 'daemon unavailable\\n' >&2\nexit 7")

    assert {:error, "daemon unavailable\n"} = DockerBackend.swarm_containers("demo", :paused)
  end

  test "returns an error when Docker is absent" do
    assert {:error, "docker executable not found"} = DockerBackend.swarm_containers("demo", :all)
  end

  test "manager keeps list failures for pause/resume and maps the paused query to false", %{
    dir: dir
  } do
    docker(dir, "printf 'daemon unavailable\\n' >&2\nexit 7")
    state = %SwarmManager{swarms: %{"demo" => %{}}}

    for operation <- [:pause, :resume] do
      assert {:reply, {:error, "daemon unavailable\n"}, ^state} =
               SwarmManager.handle_call({operation, "demo"}, self(), state)
    end

    assert {:reply, false, ^state} = SwarmManager.handle_call({:paused?, "demo"}, self(), state)
  end

  test "manager counts only successful actions on containers with the swarm prefix", %{dir: dir} do
    docker(dir, """
    case "$1" in
      ps) printf 'szc-demo-ok\\nszc-demo-fail\\nother-szc-demo-ok\\n' ;;
      pause|unpause) [ "$2" != 'szc-demo-fail' ] ;;
    esac
    """)

    state = %SwarmManager{swarms: %{"demo" => %{}}}

    for operation <- [:pause, :resume] do
      assert {:reply, {:ok, 1}, ^state} =
               SwarmManager.handle_call({operation, "demo"}, self(), state)
    end

    assert {:reply, true, ^state} = SwarmManager.handle_call({:paused?, "demo"}, self(), state)
  end

  test "Mix pause and resume fail instead of reporting success when enumeration fails", %{
    dir: dir
  } do
    docker(dir, "printf 'daemon unavailable\\n' >&2\nexit 7")

    for task <- [Mix.Tasks.Genswarms.Pause, Mix.Tasks.Genswarms.Resume] do
      error = assert_raise MatchError, fn -> task.run(["demo"]) end
      assert error.term == {:error, "daemon unavailable\n"}
    end
  end

  defp docker(dir, result) do
    File.write!(
      Path.join(dir, "docker"),
      "#!/bin/sh\nprintf '%s\\n' \"$@\" > '#{Path.join(dir, "args")}'\n#{result}\n"
    )

    File.chmod!(Path.join(dir, "docker"), 0o755)
  end
end
