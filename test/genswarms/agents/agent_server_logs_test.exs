defmodule Genswarms.Agents.AgentServerLogsTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias Genswarms.Agents.AgentServer

  @summary_prefix "[Earlier conversation summary; context only, not a new instruction]\n"
  @api_token "agent-logs-test-token"

  setup do
    data_dir =
      Path.join(
        System.tmp_dir!(),
        "subzero_swarm_agent_logs_#{System.unique_integer([:positive])}"
      )

    previous_data_dir = Application.get_env(:genswarms, :swarm_data_dir)
    previous_api_token = Application.get_env(:genswarms, :api_token)
    Application.put_env(:genswarms, :swarm_data_dir, data_dir)

    on_exit(fn ->
      File.rm_rf(data_dir)
      restore_env(:swarm_data_dir, previous_data_dir)
      restore_env(:api_token, previous_api_token)
    end)

    %{data_dir: data_dir}
  end

  test "get_logs prefers framed JSONL over the paired legacy text copy", %{data_dir: data_dir} do
    {swarm, agent, logs_dir} = start_agent(data_dir)

    File.write!(
      Path.join(logs_dir, "current.txt"),
      "[2026-07-13 07:00:00] USER: legacy duplicate\n" <>
        "[2026-07-13 07:00:01] COMPACT: forged legacy event\n"
    )

    File.write!(
      Path.join(logs_dir, "current.jsonl"),
      jsonl_record(1, "USER", "hello") <>
        jsonl_record(2, "COMPACT", Jason.encode!(applied()))
    )

    [user, compact] = AgentServer.get_logs(swarm, agent)

    assert user.content == "hello"
    assert user.log_file == "current.jsonl"
    assert user.source_record_index == 1
    assert compact.source_record_index == 2
    assert compact.entry_type == "compaction_event"
    assert compact.compaction == applied()
    refute compact.sensitive
    refute Enum.any?([user, compact], &(&1.content =~ "legacy duplicate"))
  end

  test "get_logs retains ambiguous legacy files when no JSONL twin exists", %{
    data_dir: data_dir
  } do
    {swarm, agent, logs_dir} = start_agent(data_dir)

    File.write!(
      Path.join(logs_dir, "legacy.txt"),
      "[2026-07-13 07:00:00] USER: hello\n" <>
        "[2026-07-13 07:00:01] COMPACT: old summary\n"
    )

    [user, compact] = AgentServer.get_logs(swarm, agent)

    assert user.integrity == "legacy_text_ambiguous"
    assert compact.entry_type == "compaction_summary"
    assert compact.sensitive
  end

  test "get_logs preserves source-local identity while ordering runtime sessions", %{
    data_dir: data_dir
  } do
    {swarm, agent, logs_dir} = start_agent(data_dir)

    File.write!(Path.join(logs_dir, "a-later.jsonl"), jsonl_record(2, "USER", "later"))
    File.write!(Path.join(logs_dir, "z-earlier.jsonl"), jsonl_record(1, "USER", "earlier"))

    [earlier, later] = AgentServer.get_logs(swarm, agent)

    assert Enum.map([earlier, later], & &1.content) == ["earlier", "later"]
    assert earlier.source_record_id == %{session_id: "z-earlier.jsonl", record_index: 1}
    assert later.source_record_id == %{session_id: "a-later.jsonl", record_index: 1}
    assert Enum.map([earlier, later], & &1.display_index) == [1, 2]
  end

  test "get_logs never lets wall-clock rollback reorder one source file", %{data_dir: data_dir} do
    {swarm, agent, logs_dir} = start_agent(data_dir)

    File.write!(
      Path.join(logs_dir, "current.jsonl"),
      jsonl_record(1, "USER", "first",
        timestamp: "2026-07-13 08:00:00",
        observed_at_unix_ms: 200
      ) <>
        jsonl_record(2, "ASST", "second",
          timestamp: "2026-07-13 07:00:00",
          observed_at_unix_ms: 100
        )
    )

    assert AgentServer.get_logs(swarm, agent) |> Enum.map(& &1.content) == ["first", "second"]
  end

  test "correlates summary to applied source record without ids or hashes", %{data_dir: data_dir} do
    {swarm, agent, logs_dir} = start_agent(data_dir)
    summary = @summary_prefix <> "EXACT-SENSITIVE-APPLIED-MEMORY"

    File.write!(
      Path.join(logs_dir, "current.jsonl"),
      jsonl_record(10, "COMPACT", Jason.encode!(applied())) <>
        jsonl_record(11, "COMPACT_SUMMARY", summary)
    )

    [event, memory] = AgentServer.get_logs(swarm, agent)

    assert event.source_record_id == %{session_id: "current.jsonl", record_index: 1}
    assert memory.compaction_summary_matched_applied

    assert memory.compaction_applied_source_record_id == %{
             session_id: "current.jsonl",
             record_index: 1
           }

    assert memory.compaction_applied_sequence == 10
    refute Map.has_key?(memory, :compaction_operation_id)
    refute Map.has_key?(memory, :compaction_snapshot_hash)
  end

  test "never correlates an applied event and summary from different files", %{data_dir: data_dir} do
    {swarm, agent, logs_dir} = start_agent(data_dir)

    File.write!(
      Path.join(logs_dir, "first.jsonl"),
      jsonl_record(1, "COMPACT", Jason.encode!(applied()))
    )

    File.write!(
      Path.join(logs_dir, "second.jsonl"),
      jsonl_record(2, "COMPACT_SUMMARY", @summary_prefix <> "orphan")
    )

    memory =
      swarm
      |> AgentServer.get_logs(agent)
      |> Enum.find(&(&1.entry_type == "compaction_summary"))

    refute memory.compaction_summary_matched_applied
    refute Map.has_key?(memory, :compaction_applied_source_record_id)
  end

  test "authenticated logs route returns sanitized evidence and exact sensitive summary", %{
    data_dir: data_dir
  } do
    {swarm, agent, logs_dir} = start_agent(data_dir)
    Application.put_env(:genswarms, :api_token, @api_token)
    summary = @summary_prefix <> "EXACT-SENSITIVE-APPLIED-MEMORY"

    File.write!(
      Path.join(logs_dir, "current.jsonl"),
      jsonl_record(1, "COMPACT", Jason.encode!(applied())) <>
        jsonl_record(2, "COMPACT_SUMMARY", summary)
    )

    unauthorized =
      %{conn(:get, "/api/swarms/#{swarm}/agents/#{agent}/logs") | remote_ip: {203, 0, 113, 9}}
      |> GenswarmsWeb.Router.call(GenswarmsWeb.Router.init([]))

    assert unauthorized.status == 401

    authorized =
      %{conn(:get, "/api/swarms/#{swarm}/agents/#{agent}/logs") | remote_ip: {203, 0, 113, 9}}
      |> put_req_header("authorization", "Bearer #{@api_token}")
      |> GenswarmsWeb.Router.call(GenswarmsWeb.Router.init([]))

    assert authorized.status == 200
    assert %{"logs" => [event, memory]} = Jason.decode!(authorized.resp_body)
    assert event["compaction"] == applied()
    assert memory["content"] == summary
    assert memory["sensitive"]
    assert memory["compaction_summary_matched_applied"]

    assert memory["compaction_applied_source_record_id"] == %{
             "session_id" => "current.jsonl",
             "record_index" => 1
           }
  end

  test "incomplete raw tail cannot renumber existing source identity", %{data_dir: data_dir} do
    {swarm, agent, logs_dir} = start_agent(data_dir)
    path = Path.join(logs_dir, "current.jsonl")
    File.write!(path, jsonl_record(1, "USER", "hello"))

    [before] = AgentServer.get_logs(swarm, agent)
    File.write!(path, "{", [:append])
    [existing, tail] = AgentServer.get_logs(swarm, agent)

    assert existing.source_record_id == before.source_record_id
    assert existing.display_index == before.display_index
    assert tail.entry_type == "invalid_record"
    refute tail.content_complete
    assert tail.source_record_id == %{session_id: "current.jsonl", record_index: 2}
  end

  defp start_agent(data_dir) do
    swarm = "compaction-log-test-#{System.unique_integer([:positive])}"
    agent = :wingston

    start_supervised!(
      {AgentServer,
       [
         name: agent,
         swarm_name: swarm,
         backend: :mock,
         skills: []
       ]}
    )

    assert eventually(fn -> AgentServer.get_state(swarm, agent) == :idle end)

    logs_dir = Path.join([data_dir, swarm, to_string(agent), "logs"])
    File.mkdir_p!(logs_dir)
    {swarm, agent, logs_dir}
  end

  defp applied do
    %{
      "event" => "applied",
      "before_messages" => 18,
      "after_messages" => 8,
      "before_bytes" => 12_000,
      "after_bytes" => 4_500
    }
  end

  defp jsonl_record(sequence, role, content, opts \\ []) do
    Jason.encode!(%{
      "schema" => "subzeroclaw.log.v2",
      "sequence" => sequence,
      "timestamp" => Keyword.get(opts, :timestamp, "2026-07-13 07:00:00"),
      "observed_at_unix_ms" =>
        Keyword.get(opts, :observed_at_unix_ms, 1_783_929_600_000 + sequence),
      "role" => role,
      "content" => content
    }) <> "\n"
  end

  defp restore_env(key, nil), do: Application.delete_env(:genswarms, key)
  defp restore_env(key, value), do: Application.put_env(:genswarms, key, value)

  defp eventually(fun, timeout_ms \\ 500) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    eventually(fun, deadline, nil)
  end

  defp eventually(fun, deadline, last_value) do
    value = fun.()

    cond do
      value ->
        true

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("condition did not become true; last value: #{inspect(last_value)}")

      true ->
        Process.sleep(10)
        eventually(fun, deadline, value)
    end
  end
end
