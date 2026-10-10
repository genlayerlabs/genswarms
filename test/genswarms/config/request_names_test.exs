defmodule Genswarms.Config.RequestNamesTest do
  use ExUnit.Case, async: false

  alias Genswarms.Config.{Loader, RequestNames}

  setup do
    previous =
      for key <- [:restricted_names, :max_dynamic_names],
          do: {key, Application.fetch_env(:genswarms, key)}

    Application.put_env(:genswarms, :restricted_names, false)
    Application.put_env(:genswarms, :max_dynamic_names, RequestNames.allocated() + 100)

    on_exit(fn ->
      for {key, value} <- previous do
        case value do
          {:ok, value} -> Application.put_env(:genswarms, key, value)
          :error -> Application.delete_env(:genswarms, key)
        end
      end
    end)

    :ok
  end

  defp fresh, do: "admission_#{System.unique_integer([:positive])}"
  defp uninterned(name), do: assert_raise(ArgumentError, fn -> String.to_existing_atom(name) end)

  test "restricted mode rejects new names but accepts existing ones without charging" do
    Application.put_env(:genswarms, :restricted_names, true)
    before = RequestNames.allocated()
    name = fresh()
    assert {:error, :restricted_names} = RequestNames.admit([name])
    uninterned(name)
    assert :ok = RequestNames.admit([:worker, "worker"])
    assert RequestNames.allocated() == before
  end

  test "batches are all-or-nothing and repeated names cost nothing" do
    before = RequestNames.allocated()
    Application.put_env(:genswarms, :max_dynamic_names, before + 1)
    first = fresh()
    second = fresh()
    assert {:error, :dynamic_name_limit_reached} = RequestNames.admit([first, second])
    uninterned(first)
    uninterned(second)
    assert RequestNames.allocated() == before
    assert :ok = Task.async(fn -> RequestNames.admit([first, first]) end) |> Task.await()
    assert RequestNames.allocated() == before + 1
    assert :ok = RequestNames.admit([first])
    assert {:error, :dynamic_name_limit_reached} = RequestNames.admit([second])
    uninterned(second)
  end

  test "concurrent requests cannot exceed the VM-wide budget" do
    before = RequestNames.allocated()
    Application.put_env(:genswarms, :max_dynamic_names, before + 3)
    names = for _ <- 1..12, do: fresh()

    results =
      names
      |> Task.async_stream(&RequestNames.admit([&1]), max_concurrency: 12)
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &(&1 == :ok)) == 3
    assert Enum.count(results, &(&1 == {:error, :dynamic_name_limit_reached})) == 9
    assert RequestNames.allocated() == before + 3
  end

  test "concurrent admission of the same name charges it once" do
    before = RequestNames.allocated()
    Application.put_env(:genswarms, :max_dynamic_names, before + 1)
    name = fresh()

    assert Enum.all?(
             Task.async_stream(1..12, fn _ -> RequestNames.admit([name]) end),
             &(&1 == {:ok, :ok})
           )

    assert RequestNames.allocated() == before + 1
  end

  test "invalid identifiers and oversized names never consume capacity" do
    before = RequestNames.allocated()

    for name <- [nil, 123, "", "bad/name", "bad\n", String.duplicate("a", 256)] do
      assert {:error, :invalid_node_name} = RequestNames.admit([name])
    end

    assert RequestNames.allocated() == before
  end

  test "invalid operator settings fail closed and string settings are supported" do
    name = fresh()
    Application.put_env(:genswarms, :restricted_names, "typo")
    assert {:error, :invalid_name_policy} = RequestNames.admit([name])
    Application.put_env(:genswarms, :restricted_names, "false")
    Application.put_env(:genswarms, :max_dynamic_names, "unlimited")
    assert {:error, :invalid_name_policy} = RequestNames.admit([name])
    uninterned(name)
    Application.put_env(:genswarms, :max_dynamic_names, to_string(RequestNames.allocated() + 1))
    assert :ok = RequestNames.admit([name])
  end

  test "environment settings apply when application settings are absent" do
    env_keys = ["GENSWARMS_RESTRICTED_NAMES", "GENSWARMS_MAX_DYNAMIC_NAMES"]
    previous = for key <- env_keys, do: {key, System.get_env(key)}

    on_exit(fn ->
      for {key, value} <- previous do
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end
    end)

    Application.delete_env(:genswarms, :restricted_names)
    Application.delete_env(:genswarms, :max_dynamic_names)
    System.put_env("GENSWARMS_RESTRICTED_NAMES", "true")
    System.put_env("GENSWARMS_MAX_DYNAMIC_NAMES", "10000")
    name = fresh()
    assert {:error, :restricted_names} = RequestNames.admit([name])
    System.put_env("GENSWARMS_RESTRICTED_NAMES", "false")
    System.put_env("GENSWARMS_MAX_DYNAMIC_NAMES", to_string(RequestNames.allocated()))
    assert {:error, :dynamic_name_limit_reached} = RequestNames.admit([name])
    uninterned(name)
    System.delete_env("GENSWARMS_RESTRICTED_NAMES")
    System.delete_env("GENSWARMS_MAX_DYNAMIC_NAMES")
    assert :ok = RequestNames.admit([name])
  end

  test "a fresh VM also bounds an excessively large configured budget" do
    script = ~S"""
    alias Genswarms.Config.RequestNames
    Application.put_env(:genswarms, :restricted_names, false)
    Application.put_env(:genswarms, :max_dynamic_names, 1_000_000_000)
    :ok = RequestNames.admit([:worker])
    limit = :erlang.system_info(:atom_limit)
    names = Enum.map(1..(div(limit, 4) + 1), &"bounded_name_#{&1}")
    {:error, :dynamic_name_limit_reached} = RequestNames.admit(names)
    0 = RequestNames.allocated()
    false = Enum.any?(names, fn name ->
      try do
        String.to_existing_atom(name)
        true
      rescue
        ArgumentError -> false
      end
    end)
    # Simulate trusted code using the rest of the table. Admission leaves a
    # quarter free instead of spending the configured budget into VM failure.
    target = limit - div(limit, 4)
    missing = target - :erlang.system_info(:atom_count)
    if missing > 0 do
      Enum.each(1..missing, &String.to_atom("trusted_filler_#{&1}"))
    end
    {:error, :atom_table_capacity_low} = RequestNames.admit(["last_dynamic_name"])
    0 = RequestNames.allocated()
    IO.puts("BOUNDED")
    """

    paths =
      Path.wildcard(Path.join(Mix.Project.build_path(), "lib/*/ebin"))
      |> Enum.flat_map(&["-pa", &1])

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        ["--erl", "+t 32768"] ++ paths ++ ["-e", script],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "BOUNDED"
  end

  test "validating a config does not allocate; creation admits declared topology nodes only" do
    before = RequestNames.allocated()
    first = fresh()
    second = fresh()

    config = %{
      "name" => "request-config",
      "agents" => [
        %{"name" => first, "backend" => "mock"},
        %{"name" => second, "backend" => "mock"}
      ],
      "topology" => [[first, second]]
    }

    assert {:ok, _} = Loader.load_map(config, allocate: false)
    assert RequestNames.allocated() == before
    uninterned(first)
    uninterned(second)
    unknown = fresh()

    assert {:error, {:invalid_topology, _}} =
             Loader.load_map(%{config | "topology" => [[first, unknown]]})

    uninterned(first)
    uninterned(unknown)
    assert {:ok, parsed} = Loader.load_map(config)
    assert parsed.topology == [{String.to_existing_atom(first), String.to_existing_atom(second)}]
    assert RequestNames.allocated() == before + 2
  end

  test "an invalid backend is rejected before a declared name is allocated" do
    name = fresh()
    backend = fresh()

    assert {:error, _} =
             Loader.load_map(%{
               "name" => "request",
               "agents" => [%{"name" => name, "backend" => backend}]
             })

    uninterned(name)
    uninterned(backend)
  end
end
