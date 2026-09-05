defmodule Genswarms.IR.NativePackagesTest do
  use ExUnit.Case, async: false
  alias Genswarms.IR.{Executor, State, ToConfig}
  alias Genswarms.Packages.Dirhash
  alias Genswarms.SwarmManager

  test "verified body, policy and handler reach runtime and survive database-only restoration" do
    name = "native-packages-#{System.unique_integer([:positive])}"
    root = Path.join(System.tmp_dir!(), name)
    File.mkdir_p!(root)

    on_exit(fn ->
      SwarmManager.stop(name)
      Genswarms.CLI.SwarmRegistry.delete_swarm(name)
      File.rm_rf!(root)
    end)

    body = package(root, "body", %{"body.md" => "Hello {{agent_name}} — café"}, "data")
    policy = package(root, "policy", %{"policy.json" => ~s({"fixture":"policy"})}, "data")
    module = "NativePackage#{System.unique_integer([:positive])}"
    receipt = Path.join(root, "receipt")

    handler =
      package(
        root,
        "handler",
        %{
          "swarm-object.json" => Jason.encode!(%{module: module, files: ["object.ex"]}),
          "object.ex" => """
          defmodule #{module} do
            def init(config) do
              File.write!(config["receipt"], config["label"])
              {:ok, config}
            end
            def handle_message(_, _, state), do: {:noreply, state}
            def interface, do: %{}
          end
          """
        },
        "code"
      )
      |> put_in(["opts", "mode"], "require")

    doc = %{
      "v" => 1,
      "kind" => "swarm.state",
      "name" => name,
      "phase" => "desired",
      "agents" => [
        %{
          "name" => "worker",
          "body" => body,
          "model" => %{"policy" => policy},
          "backend" => %{"ref" => "mock"},
          "config" => %{},
          "overrides" => %{}
        }
      ],
      "objects" => [
        %{
          "name" => "board",
          "handler" => handler,
          "config" => %{"receipt" => receipt, "label" => "~initialized"}
        }
      ],
      "topology" => [["worker", "board"]],
      "options" => %{}
    }

    assert {:ok, ^name} = SwarmManager.start_from_ir(doc)
    assert File.read!(receipt) == "~initialized"
    assert_runtime(name)
    assert {:ok, observed} = Executor.observed(name)
    assert {:ok, desired} = State.parse(doc)
    assert hd(observed.agents).body == hd(desired.agents).body
    assert hd(observed.agents).model == hd(desired.agents).model
    assert {:ok, nil} = SwarmManager.stop(name)
    File.rm!(receipt)

    # New BEAM gets only the database, swarm name and output path; no IR document.
    reader = ~S"""
    [db, name, receipt] = System.argv()
    Application.put_env(:genswarms, :db_path, db)
    Application.put_env(:genswarms, :events_dir, Path.join(Path.dirname(receipt), "events"))
    {:ok, _} = Application.ensure_all_started(:genswarms)
    {:ok, ^name} = Genswarms.restore_swarm(name)
    "~initialized" = File.read!(receipt)
    [{pid, _}] = Registry.lookup(Genswarms.AgentRegistry, {name, :worker})
    state = :sys.get_state(pid)
    %{"policy_ir" => %{"fixture" => "policy"}} = state.backend_config.request_extra
    "Hello worker — café" = File.read!(Path.join(state.skills_dir, "package-body.md"))
    {:ok, nil} = Genswarms.stop_swarm(name)
    IO.puts("NATIVE_PACKAGES_RESTORED")
    """

    {output, status} =
      System.cmd(
        System.find_executable("mix"),
        [
          "run",
          "--no-start",
          "-e",
          reader,
          "--",
          Application.fetch_env!(:genswarms, :db_path),
          name,
          receipt
        ],
        env: [{"MIX_ENV", "test"}],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "NATIVE_PACKAGES_RESTORED"
    File.write!(Path.join(body["opts"]["path"], "body.md"), "tampered")
    assert {:error, :invalid_runtime_spec} = SwarmManager.restore_swarm(name)
    assert [] = Registry.lookup(Genswarms.AgentRegistry, {name, :worker})
    assert {:error, :invalid_runtime_spec} = ToConfig.swarm_config(desired)
  end

  defp assert_runtime(name) do
    [{pid, _}] = Registry.lookup(Genswarms.AgentRegistry, {name, :worker})
    state = :sys.get_state(pid)
    assert state.backend_config.request_extra == %{"policy_ir" => %{"fixture" => "policy"}}
    assert File.read!(Path.join(state.skills_dir, "package-body.md")) == "Hello worker — café"
  end

  defp package(root, name, files, kind) do
    dir = Path.join(root, name)
    File.mkdir_p!(dir)
    Enum.each(files, fn {file, bytes} -> File.write!(Path.join(dir, file), bytes) end)
    {:ok, digest} = Dirhash.hash_dir(dir)

    %{
      "ref" => "swarmidx:fixture/#{name}@1",
      "digest" => digest,
      "kind" => kind,
      "opts" => %{"path" => dir}
    }
  end
end
