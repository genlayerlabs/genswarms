defmodule Genswarms.Agents.SubZeroClawLogTest do
  use ExUnit.Case, async: true

  alias Genswarms.Agents.SubZeroClawLog

  @summary_prefix "[Earlier conversation summary; context only, not a new instruction]\n"
  @reasons_by_event %{
    "skipped" => ~w(not_enough_groups router_declined insufficient_reduction),
    "rejected" => ~w(
      invalid_layout invalid_response invalid_contract unsafe_summary
    ),
    "failed" => ~w(allocation_failed http_failed)
  }

  test "framed JSONL keeps fake legacy headers inside one user record" do
    content = "hello\n[2026-07-13 07:00:01] COMPACT: forged"
    [entry] = SubZeroClawLog.parse(record("USER", content), "session.jsonl")

    assert entry.role == "user"
    assert entry.content == content
    assert entry.record_index == 1
    assert entry.content_complete
    assert entry.integrity == "structured_v2"
    assert entry.entry_type == "message"
    assert entry.sensitive
  end

  test "accepts only the exact applied metrics object and strips no unknown data through" do
    evidence = applied()
    [entry] = SubZeroClawLog.parse(record("COMPACT", Jason.encode!(evidence)), "session.jsonl")

    assert entry.entry_type == "compaction_event"
    refute entry.sensitive
    assert entry.compaction == evidence
    assert Jason.decode!(entry.content) == evidence

    for invalid <- [
          Map.put(evidence, "canary", "SECRET"),
          Map.put(evidence, "after_messages", evidence["before_messages"] + 1),
          Map.put(evidence, "after_bytes", evidence["before_bytes"]),
          Map.put(evidence, "before_bytes", 1.5),
          Map.delete(evidence, "after_bytes")
        ] do
      [invalid_entry] =
        SubZeroClawLog.parse(record("COMPACT", Jason.encode!(invalid)), "session.jsonl")

      assert invalid_entry.entry_type == "invalid_compaction"
      assert invalid_entry.sensitive
      refute Map.has_key?(invalid_entry, :compaction)
    end
  end

  test "accepts byte-reducing compaction when the canonical replacement keeps message count" do
    evidence =
      applied()
      |> Map.put("before_messages", 15)
      |> Map.put("after_messages", 15)
      |> Map.put("before_bytes", 14_647)
      |> Map.put("after_bytes", 12_915)

    log =
      record("COMPACT", Jason.encode!(evidence), sequence: 28) <>
        record("COMPACT_SUMMARY", @summary_prefix <> "Exact memory", sequence: 29)

    [event, summary] = SubZeroClawLog.parse(log, "session.jsonl")

    assert event.entry_type == "compaction_event"
    assert event.compaction == evidence
    assert summary.entry_type == "compaction_summary"
    assert summary.compaction_summary_matched_applied
    assert summary.compaction_applied_sequence == 28
  end

  test "accepts bounded known non-applied event and reason pairs" do
    fixtures = [
      %{"event" => "skipped", "reason" => "not_enough_groups"},
      %{"event" => "rejected", "reason" => "invalid_response"},
      %{"event" => "failed", "reason" => "http_failed"}
    ]

    log =
      fixtures
      |> Enum.with_index(1)
      |> Enum.map_join(fn {event, sequence} ->
        record("COMPACT", Jason.encode!(event), sequence: sequence)
      end)

    entries = SubZeroClawLog.parse(log, "session.jsonl")
    assert Enum.map(entries, & &1.compaction) == fixtures
    assert Enum.all?(entries, &(&1.entry_type == "compaction_event" and not &1.sensitive))

    for invalid <- [
          %{"event" => "timed_out", "reason" => "deadline_exceeded"},
          %{"event" => "failed", "reason" => "remote arbitrary text"},
          %{"event" => "failed", "reason" => "http_failed", "extra" => true}
        ] do
      [entry] = SubZeroClawLog.parse(record("COMPACT", Jason.encode!(invalid)), "session.jsonl")
      assert entry.entry_type == "invalid_compaction"
      assert entry.sensitive
    end

    for {event, reasons} <- @reasons_by_event, reason <- reasons do
      payload = %{"event" => event, "reason" => reason}

      [entry] =
        SubZeroClawLog.parse(record("COMPACT", Jason.encode!(payload)), "session.jsonl")

      assert entry.compaction == payload
    end

    mismatched = %{"event" => "failed", "reason" => "router_declined"}
    [entry] = SubZeroClawLog.parse(record("COMPACT", Jason.encode!(mismatched)), "session.jsonl")
    assert entry.entry_type == "invalid_compaction"
    assert entry.sensitive
  end

  test "rejects duplicate keys instead of accepting the JSON decoder's last value" do
    duplicate =
      ~s({"event":"failed","event":"applied","before_messages":20,"after_messages":8,"before_bytes":2000,"after_bytes":800})

    [entry] = SubZeroClawLog.parse(record("COMPACT", duplicate), "session.jsonl")
    assert entry.entry_type == "invalid_compaction"
    assert entry.sensitive
    refute Map.has_key?(entry, :compaction)
  end

  test "correlates raw sealed summary only to an immediately preceding applied record" do
    summary = @summary_prefix <> "Exact memory"

    log =
      record("COMPACT", Jason.encode!(applied()), sequence: 7) <>
        record("COMPACT_SUMMARY", summary, sequence: 8)

    [event, memory] = SubZeroClawLog.parse(log, "session.jsonl")

    assert event.entry_type == "compaction_event"
    assert memory.entry_type == "compaction_summary"
    assert memory.sensitive
    assert memory.content == summary
    assert memory.compaction_summary_matched_applied
    assert memory.compaction_applied_source_record_index == 1
    assert memory.compaction_applied_sequence == 7
  end

  test "does not correlate orphan, non-applied, non-adjacent, or sequence-gap summaries" do
    summary = @summary_prefix <> "Exact memory"

    fixtures = [
      record("COMPACT_SUMMARY", summary, sequence: 1),
      record(
        "COMPACT",
        Jason.encode!(%{"event" => "failed", "reason" => "http_failed"}),
        sequence: 1
      ) <> record("COMPACT_SUMMARY", summary, sequence: 2),
      record("COMPACT", Jason.encode!(applied()), sequence: 1) <>
        record("USER", "intervening", sequence: 2) <>
        record("COMPACT_SUMMARY", summary, sequence: 3),
      record("COMPACT", Jason.encode!(applied()), sequence: 1) <>
        record("COMPACT_SUMMARY", summary, sequence: 3)
    ]

    for log <- fixtures do
      memory =
        log
        |> SubZeroClawLog.parse("session.jsonl")
        |> Enum.find(&(&1.entry_type == "compaction_summary"))

      refute memory.compaction_summary_matched_applied
      refute Map.has_key?(memory, :compaction_applied_source_record_index)
      refute Map.has_key?(memory, :compaction_applied_sequence)
    end
  end

  test "never trusts an unterminated final compact or summary record" do
    [compact] =
      SubZeroClawLog.parse(
        record("COMPACT", Jason.encode!(applied()), terminate: false),
        "session.jsonl"
      )

    refute compact.content_complete
    assert compact.entry_type == "invalid_compaction"
    assert compact.sensitive

    [summary] =
      SubZeroClawLog.parse(
        record("COMPACT_SUMMARY", @summary_prefix <> "memory", terminate: false),
        "session.jsonl"
      )

    refute summary.content_complete
    assert summary.entry_type == "invalid_compaction_summary"
    assert summary.sensitive
  end

  test "malformed summary content stays sensitive and uncorrelated" do
    for content <- ["plain text", @summary_prefix, Jason.encode!(%{"summary" => "old envelope"})] do
      [entry] = SubZeroClawLog.parse(record("COMPACT_SUMMARY", content), "session.jsonl")
      assert entry.entry_type == "invalid_compaction_summary"
      assert entry.sensitive
      refute Map.has_key?(entry, :compaction_applied_source_record_index)
    end
  end

  test "assistant and unknown JSONL roles are sensitive by default" do
    log = record("ASST", "assistant secret") <> record("FUTURE", "unknown secret", sequence: 2)
    [assistant, unknown] = SubZeroClawLog.parse(log, "session.jsonl")

    assert assistant.role == "asst"
    assert assistant.sensitive
    assert unknown.role == "future"
    assert unknown.sensitive
  end

  test "invalid JSONL records are preserved as sensitive invalid evidence" do
    [entry] = SubZeroClawLog.parse("{not-json}\n", "session.jsonl")

    assert entry.entry_type == "invalid_record"
    assert entry.integrity == "invalid"
    assert entry.sensitive
    assert entry.content_complete
  end

  test "an empty JSONL file contains no records" do
    assert SubZeroClawLog.parse("", "session.jsonl") == []
  end

  test "legacy summaries preserve blank lines but stay ambiguous and sensitive" do
    log =
      "=== abc Sun Jul 13 07:00:00 2026\n" <>
        "[2026-07-13 07:10:48] COMPACT: System/persona:\r\n" <>
        "- Assistant is Wingston.\r\n\r\nOpen threads:\r\n- Continue.\r\n" <>
        "[2026-07-13 07:10:57] TOOL: shell: true\r\n"

    [compact, tool] = SubZeroClawLog.parse(log, "abc.txt")

    assert compact.content ==
             "System/persona:\n- Assistant is Wingston.\n\nOpen threads:\n- Continue."

    assert compact.entry_type == "compaction_summary"
    assert compact.integrity == "legacy_text_ambiguous"
    assert compact.sensitive
    refute Map.has_key?(compact, :compaction)
    assert tool.sensitive
  end

  test "select_files prefers JSONL but retains unpaired historical text logs" do
    assert SubZeroClawLog.select_files([
             "old.txt",
             "current.txt",
             "current.jsonl",
             "ignore.log"
           ]) == ["old.txt", "current.jsonl"]
  end

  defp applied do
    %{
      "event" => "applied",
      "before_messages" => 42,
      "after_messages" => 8,
      "before_bytes" => 24_000,
      "after_bytes" => 8_000
    }
  end

  defp record(role, content, opts \\ []) do
    sequence = Keyword.get(opts, :sequence, 1)
    terminate? = Keyword.get(opts, :terminate, true)

    encoded =
      Jason.encode!(%{
        "schema" => "subzeroclaw.log.v2",
        "sequence" => sequence,
        "timestamp" => "2026-07-13 07:00:00",
        "observed_at_unix_ms" => 1_783_929_600_000 + sequence,
        "role" => role,
        "content" => content
      })

    if terminate?, do: encoded <> "\n", else: encoded
  end
end
