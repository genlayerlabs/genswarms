defmodule Genswarms.IR.PackageActuationTest do
  use ExUnit.Case, async: false

  alias Genswarms.CLI.SwarmRegistry
  alias Genswarms.IR.{Executor, FromConfig, State}
  alias Genswarms.Packages.Dirhash
  alias Genswarms.SwarmManager

  test "a JSON-round-tripped handler ref reaches the actual loader and object runtime" do
    unique = System.unique_integer([:positive])
    swarm = "ir-package-#{unique}"
    dir = Path.join(System.tmp_dir!(), "ir-package-actuation-#{unique}")
    module = "IRPackageActuationFixture#{unique}"
    Process.register(self(), :ir_package_actuation_probe)
    File.mkdir_p!(dir)

    on_exit(fn ->
      SwarmManager.stop(swarm)
      SwarmRegistry.clear_overlay(swarm)
      File.rm_rf!(dir)
    end)

    File.write!(Path.join(dir, "object.ex"), """
    defmodule #{module} do
      def init(config) do
        send(Process.whereis(:ir_package_actuation_probe), {:package_initialized, config["label"]})
        {:ok, config}
      end
      def handle_message(_, _, state), do: {:noreply, state}
      def interface, do: %{}
    end
    """)

    File.write!(
      Path.join(dir, "swarm-object.json"),
      Jason.encode!(%{module: module, files: ["object.ex"]})
    )

    assert {:ok, digest} = Dirhash.hash_dir(dir)
    handler = %{ref: "swarmidx:fixture/board@1", digest: digest, path: dir, mode: :require}

    assert {:ok, state} =
             FromConfig.from_config(%{
               name: swarm,
               agents: [],
               objects: [%{name: :board, handler: handler, config: %{"label" => "~json-fixture"}}]
             })

    assert {:ok, restored} =
             state |> State.to_map() |> Jason.encode!() |> Jason.decode!() |> State.parse()

    assert {:ok, ^swarm} = SwarmManager.start_from_config(%{name: swarm, agents: []})
    assert :ok = Executor.apply_plan(swarm, [{:start_object, hd(restored.objects)}])
    assert_receive {:package_initialized, "~json-fixture"}, 2000
    assert {:ok, observed} = Executor.observed(swarm)
    assert hd(observed.objects).handler == hd(restored.objects).handler
    assert {:ok, config} = SwarmManager.get_full_config(swarm)
    assert hd(config.objects).handler == handler
  end
end
