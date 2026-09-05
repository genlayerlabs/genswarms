defmodule Genswarms.CLI.SwarmRegistryCodecTest do
  use ExUnit.Case, async: false

  alias Genswarms.CLI.SwarmRegistry

  setup do
    swarm = "codec-#{System.unique_integer([:positive])}"
    SwarmRegistry.init()
    on_exit(fn -> SwarmRegistry.clear_overlay(swarm) end)
    {:ok, swarm: swarm}
  end

  test "overlay payload preserves tuples, lists, atoms and literal tilde strings", %{swarm: swarm} do
    payload = %{
      name: :worker,
      backend: {:mock, %{script: ["~literal", {:reply, "done"}]}},
      config: %{
        "~name" => "~worker",
        "nested" => [[:a, "~a"], {:a, "~a"}],
        "tag_shaped_data" => ["atom", "not_an_atom"],
        "values" => [true, false, nil, 7, 1.5]
      }
    }

    assert :ok = SwarmRegistry.append_overlay(swarm, :add_agent, payload)
    assert [{:add_agent, ^payload}] = SwarmRegistry.load_overlay(swarm)
  end

  test "daemon command and result use the same lossless codec", %{swarm: swarm} do
    payload = %{backend: {:docker, "image:tag", %{network: :isolated}}, label: "~literal"}
    assert {:ok, id} = SwarmRegistry.enqueue_command(swarm, :add_agent, payload)

    assert [%{id: ^id, op: :add_agent, payload: ^payload}] =
             SwarmRegistry.get_pending_commands(swarm)

    result = %{status: "error", reason: {:unavailable, ["~literal", :backend]}}
    assert :ok = SwarmRegistry.mark_command_done(id, result)
    assert {:done, ^result} = SwarmRegistry.get_command_result(id)
  end

  test "a separate BEAM reads persisted backend types without writer memory", %{swarm: swarm} do
    payload = %{name: :worker, backend: {:mock, %{script: ["~literal"]}}}
    assert :ok = SwarmRegistry.append_overlay(swarm, :add_agent, payload)

    reader = ~S"""
    [db, swarm] = System.argv()
    Application.put_env(:genswarms, :db_path, db)
    Application.put_env(:genswarms, :events_dir, Path.dirname(db))
    [{:add_agent, %{name: :worker, backend: {:mock, %{script: ["~literal"]}}}}] =
      Genswarms.CLI.SwarmRegistry.load_overlay(swarm)
    IO.puts("PERSISTED_TYPES_OK")
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
          swarm
        ],
        env: [{"MIX_ENV", "test"}],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "PERSISTED_TYPES_OK"
  end

  test "literal strings do not mint atoms and tag-shaped user maps remain data", %{swarm: swarm} do
    name = "codec_literal_#{System.unique_integer([:positive])}"
    assert_raise ArgumentError, fn -> String.to_existing_atom(name) end
    payload = %{"~#{name}" => "~#{name}", "$genswarms" => "term-v1", "value" => ["atom", name]}

    assert :ok = SwarmRegistry.append_overlay(swarm, :update_config, payload)
    assert [{:update_config, ^payload}] = SwarmRegistry.load_overlay(swarm)
    assert_raise ArgumentError, fn -> String.to_existing_atom(name) end
  end

  test "non-data values fail before writing an overlay", %{swarm: swarm} do
    assert_raise ArgumentError, "Cannot serialize function in overlay payload", fn ->
      SwarmRegistry.append_overlay(swarm, :update_config, %{callback: fn -> :ok end})
    end

    assert SwarmRegistry.load_overlay(swarm) == []
  end

  test "legacy unversioned rows remain readable without guessing old list types", %{swarm: swarm} do
    # The old format cannot distinguish lists from tuples, or literal ~ strings
    # from atoms. Preserve its interpretation; do not guess a destructive repair.
    raw = ~s({"~name":"~worker","~backend":"~mock","~config":{"text":"hello","list":[1,2]}})
    insert_legacy!(swarm, raw)

    assert [
             {:add_agent,
              %{name: :worker, backend: :mock, config: %{"text" => "hello", "list" => [1, 2]}}}
           ] =
             SwarmRegistry.load_overlay(swarm)
  end

  defp insert_legacy!(swarm, json) do
    {:ok, db} = Exqlite.Sqlite3.open(Application.fetch_env!(:genswarms, :db_path))

    try do
      {:ok, stmt} =
        Exqlite.Sqlite3.prepare(
          db,
          "INSERT INTO swarm_overlays (swarm, seq, op, payload, applied_at) VALUES (?, 1, 'add_agent', ?, 'fixture')"
        )

      :ok = Exqlite.Sqlite3.bind(stmt, [swarm, json])
      :done = Exqlite.Sqlite3.step(db, stmt)
      :ok = Exqlite.Sqlite3.release(db, stmt)
    after
      Exqlite.Sqlite3.close(db)
    end
  end
end
