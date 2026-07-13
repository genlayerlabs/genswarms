defmodule Genswarms.Agents.LogWatcherTest do
  use ExUnit.Case, async: false

  alias Genswarms.Agents.LogWatcher
  alias Genswarms.Observability.LogStore
  alias Genswarms.Routing.Router

  @summary_prefix "[Earlier conversation summary; context only, not a new instruction]\n"

  setup do
    dir = Path.join(System.tmp_dir!(), "logwatcher_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    {:ok, dir: dir}
  end

  test "state tracks bounded file offsets and identities", %{dir: dir} do
    pid = start_watcher(dir)
    state = :sys.get_state(pid)

    refute Map.has_key?(state, :processed_hashes)
    assert state.log_files == %{}
  end

  test "forgets log state after a file disappears", %{dir: dir} do
    path = Path.join(dir, "removed.jsonl")
    File.write!(path, jsonl_record("USER", "temporary") <> "\n")
    pid = start_watcher(dir)

    poll(pid)
    assert Map.has_key?(:sys.get_state(pid).log_files, path)

    File.rm!(path)
    poll(pid)
    refute Map.has_key?(:sys.get_state(pid).log_files, path)
  end

  test "reads only an appended suffix and does not reread an unchanged log", %{dir: dir} do
    path = Path.join(dir, "incremental.jsonl")
    initial = jsonl_record("USER", String.duplicate("initial", 4_000)) <> "\n"
    appended = jsonl_record("USER", "appended", sequence: 2) <> "\n"
    File.write!(path, initial)

    pid = start_watcher(dir)
    :erlang.trace_pattern({:file, :pread, 3}, true, [:local])
    :erlang.trace(pid, true, [:call])

    try do
      poll(pid)

      assert_receive {:trace, ^pid, :call, {:file, :pread, [_file, 0, initial_size]}},
                     100

      assert initial_size == byte_size(initial)

      poll(pid)
      refute_receive {:trace, ^pid, :call, {:file, :pread, _}}, 50

      File.write!(path, appended, [:append])
      poll(pid)

      expected_offset = byte_size(initial)
      expected_size = byte_size(appended)

      assert_receive {:trace, ^pid, :call,
                      {:file, :pread, [_file, ^expected_offset, ^expected_size]}},
                     100

      assert log_file(pid, path).position == expected_offset + expected_size
      refute_receive {:trace, ^pid, :call, {:file, :pread, _}}, 20
    after
      if Process.alive?(pid), do: :erlang.trace(pid, false, [:call])
      :erlang.trace_pattern({:file, :pread, 3}, false, [:local])
    end
  end

  test "does not advance past an incomplete JSONL record", %{dir: dir} do
    path = Path.join(dir, "current.jsonl")
    line = jsonl_record("USER", "partial")
    File.write!(path, line)

    pid = start_watcher(dir)
    poll(pid)
    assert log_file(pid, path).position == 0

    File.write!(path, "\n", [:append])
    poll(pid)
    assert log_file(pid, path).position == byte_size(line) + 1
  end

  test "a partial JSONL twin is consumed when its first record completes", %{dir: dir} do
    swarm = unique_swarm("lw-twin-partial")
    text_path = Path.join(dir, "current.txt")
    jsonl_path = Path.join(dir, "current.jsonl")
    :ok = Router.register_topology(swarm, [{:lw_agent, :target}])
    on_exit(fn -> Router.unregister_topology(swarm) end)

    File.write!(text_path, "[2026-07-13 07:00:00] USER: legacy\n")
    pid = start_watcher(dir, swarm)
    poll(pid)
    assert Map.has_key?(:sys.get_state(pid).log_files, text_path)

    marker = "<<SWARM_MSG:TO=target:START>>hello<<SWARM_MSG:END>>"
    partial = jsonl_record("RES", marker)
    File.write!(jsonl_path, partial)
    poll(pid)
    assert log_file(pid, jsonl_path).position == 0

    File.write!(jsonl_path, "\n", [:append])
    poll(pid)

    assert eventually(fn ->
             Enum.any?(
               Router.get_message_log(swarm),
               &(&1.from == :lw_agent and &1.to == :target)
             )
           end)
  end

  test "a complete JSONL twin skips history but consumes later appends", %{dir: dir} do
    swarm = unique_swarm("lw-twin-complete")
    text_path = Path.join(dir, "current.txt")
    jsonl_path = Path.join(dir, "current.jsonl")
    :ok = Router.register_topology(swarm, [{:lw_agent, :target}])
    on_exit(fn -> Router.unregister_topology(swarm) end)

    File.write!(text_path, "[2026-07-13 07:00:00] USER: legacy\n")
    pid = start_watcher(dir, swarm)
    poll(pid)

    historical = "<<SWARM_MSG:TO=target:START>>historical<<SWARM_MSG:END>>"
    File.write!(jsonl_path, jsonl_record("RES", historical) <> "\n")
    poll(pid)

    assert Router.get_message_log(swarm) == []
    refute Map.has_key?(:sys.get_state(pid).log_files, text_path)
    assert log_file(pid, jsonl_path).position == File.stat!(jsonl_path).size

    appended = "<<SWARM_MSG:TO=target:START>>new<<SWARM_MSG:END>>"
    File.write!(jsonl_path, jsonl_record("RES", appended, sequence: 2) <> "\n", [:append])
    poll(pid)

    assert eventually(fn ->
             Enum.any?(Router.get_message_log(swarm), &(&1.content_preview == "new"))
           end)

    refute Enum.any?(Router.get_message_log(swarm), &(&1.content_preview == "historical"))
  end

  test "prefers a complete JSONL twin and never consumes the paired text copy", %{dir: dir} do
    text_path = Path.join(dir, "current.txt")
    jsonl_path = Path.join(dir, "current.jsonl")
    File.write!(text_path, "[2026-07-13 07:00:00] USER: legacy\n")
    File.write!(jsonl_path, jsonl_record("USER", "framed") <> "\n")

    pid = start_watcher(dir)
    poll(pid)

    files = :sys.get_state(pid).log_files
    assert Map.has_key?(files, jsonl_path)
    refute Map.has_key?(files, text_path)
  end

  test "does not duplicate raw applied summary into durable observability", %{dir: dir} do
    swarm = unique_swarm("lw-summary")
    canary = "EXACT-SUMMARY-MUST-STAY-IN-SLOT"
    path = Path.join(dir, "current.jsonl")

    File.write!(
      path,
      jsonl_record("COMPACT", Jason.encode!(applied())) <>
        "\n" <>
        jsonl_record("COMPACT_SUMMARY", @summary_prefix <> canary, sequence: 2) <>
        "\n"
    )

    pid = start_watcher(dir, swarm)
    poll(pid)

    assert log_file(pid, path).position == File.stat!(path).size
    refute durable_contains?(swarm, canary)
  end

  test "malformed future compact and summary bodies never enter durable observability", %{
    dir: dir
  } do
    swarm = unique_swarm("lw-malformed-compact")
    compact_canary = "MALFORMED-COMPACT-PRIVATE"
    summary_canary = "MALFORMED-SUMMARY-PRIVATE"

    malformed_compact =
      applied()
      |> Map.put("private", compact_canary)
      |> Jason.encode!()

    File.write!(
      Path.join(dir, "current.jsonl"),
      jsonl_record("COMPACT", malformed_compact) <>
        "\n" <>
        jsonl_record("COMPACT_SUMMARY", summary_canary, sequence: 2) <>
        "\n" <>
        jsonl_record("USER", "OBSERVABILITY-SYNC", sequence: 3) <>
        "\n"
    )

    pid = start_watcher(dir, swarm)
    poll(pid)

    assert eventually(fn -> durable_contains?(swarm, "OBSERVABILITY-SYNC") end)
    refute durable_contains?(swarm, compact_canary)
    refute durable_contains?(swarm, summary_canary)
  end

  test "invalid outer JSONL content never enters durable observability", %{dir: dir} do
    swarm = unique_swarm("lw-invalid-outer")
    canary = "INVALID-OUTER-PRIVATE"

    invalid_outer =
      Jason.encode!(%{
        "schema" => "subzeroclaw.log.v2",
        "sequence" => "invalid",
        "timestamp" => "2026-07-13 07:00:00",
        "observed_at_unix_ms" => 1_783_929_600_001,
        "role" => "COMPACT_SUMMARY",
        "content" => @summary_prefix <> canary
      })

    File.write!(
      Path.join(dir, "invalid.jsonl"),
      invalid_outer <> "\n" <> jsonl_record("USER", "OBSERVABILITY-SYNC") <> "\n"
    )

    pid = start_watcher(dir, swarm)
    poll(pid)

    assert eventually(fn -> durable_contains?(swarm, "OBSERVABILITY-SYNC") end)
    refute durable_contains?(swarm, canary)
  end

  test "resets its offset when a file is truncated", %{dir: dir} do
    swarm = unique_swarm("lw-truncate")
    path = Path.join(dir, "current.jsonl")
    File.write!(path, jsonl_record("USER", String.duplicate("old", 200)) <> "\n")

    pid = start_watcher(dir, swarm)
    poll(pid)
    old_position = log_file(pid, path).position

    File.write!(path, jsonl_record("USER", "AFTER-TRUNCATE") <> "\n")
    assert File.stat!(path).size < old_position
    poll(pid)

    assert eventually(fn -> durable_contains?(swarm, "AFTER-TRUNCATE") end)
    assert log_file(pid, path).position == File.stat!(path).size
  end

  test "resets its offset when a path is replaced with a new inode", %{dir: dir} do
    swarm = unique_swarm("lw-replace")
    path = Path.join(dir, "current.jsonl")
    replacement = Path.join(dir, "replacement.tmp")
    File.write!(path, jsonl_record("USER", String.duplicate("old", 100)) <> "\n")

    pid = start_watcher(dir, swarm)
    poll(pid)
    old_identity = log_file(pid, path).identity

    File.write!(replacement, jsonl_record("USER", "AFTER-REPLACE") <> "\n")
    File.rm!(path)
    File.rename!(replacement, path)
    refute {File.stat!(path).major_device, File.stat!(path).inode} == old_identity
    poll(pid)

    assert eventually(fn -> durable_contains?(swarm, "AFTER-REPLACE") end)
  end

  test "retains an unterminated legacy SWARM_MSG until its newline arrives", %{dir: dir} do
    swarm = unique_swarm("lw-legacy-tail")
    path = Path.join(dir, "legacy.txt")
    :ok = Router.register_topology(swarm, [{:lw_agent, :target}])
    on_exit(fn -> Router.unregister_topology(swarm) end)

    line =
      "[2026-07-13 07:00:00] RES: " <>
        "<<SWARM_MSG:TO=target:START>>hello<<SWARM_MSG:END>>"

    File.write!(path, line)
    pid = start_watcher(dir, swarm)
    poll(pid)
    assert log_file(pid, path).position == 0
    assert Router.get_message_log(swarm) == []

    File.write!(path, "\n", [:append])
    poll(pid)

    assert eventually(fn ->
             Enum.any?(
               Router.get_message_log(swarm),
               &(&1.from == :lw_agent and &1.to == :target)
             )
           end)
  end

  defp start_watcher(dir, swarm \\ nil) do
    start_supervised!(
      {LogWatcher,
       [
         swarm_name: swarm || unique_swarm("lw-test"),
         agent_name: :lw_agent,
         log_dir: dir,
         workspace: dir
       ]}
    )
  end

  defp poll(pid) do
    send(pid, :poll)
    :sys.get_state(pid)
  end

  defp log_file(pid, path), do: Map.fetch!(:sys.get_state(pid).log_files, path)

  defp durable_contains?(swarm, value) do
    LogStore.query(swarm: swarm, limit: 100)
    |> Enum.any?(&String.contains?(inspect(&1), value))
  end

  defp applied do
    %{
      "event" => "applied",
      "before_messages" => 20,
      "after_messages" => 8,
      "before_bytes" => 2_000,
      "after_bytes" => 800
    }
  end

  defp jsonl_record(role, content, opts \\ []) do
    sequence = Keyword.get(opts, :sequence, 1)

    Jason.encode!(%{
      "schema" => "subzeroclaw.log.v2",
      "sequence" => sequence,
      "timestamp" => "2026-07-13 07:00:00",
      "observed_at_unix_ms" => 1_783_929_600_000 + sequence,
      "role" => role,
      "content" => content
    })
  end

  defp unique_swarm(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"

  defp eventually(fun, attempts \\ 50)

  defp eventually(fun, attempts) when attempts > 0 do
    if fun.() do
      true
    else
      Process.sleep(10)
      eventually(fun, attempts - 1)
    end
  end

  defp eventually(_fun, 0), do: false
end
