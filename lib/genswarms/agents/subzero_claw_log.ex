defmodule Genswarms.Agents.SubZeroClawLog do
  @moduledoc """
  Parses SubZeroClaw log snapshots without treating legacy text boundaries as
  trustworthy evidence.

  New runtimes emit one escaped `subzeroclaw.log.v2` JSON object per line. A
  complete, valid JSONL record has an unambiguous boundary; legacy `.txt` logs
  remain available for compatibility but are explicitly marked ambiguous and
  can never produce a structured compaction event.
  """

  @entry_regex ~r/^\[(?<timestamp>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] (?<role>[A-Za-z][A-Za-z0-9_]*):(?: (?<content>.*))?$/
  @timestamp_regex ~r/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/
  @parser_version "genswarms.subzeroclaw_log.v3"
  @record_schema "subzeroclaw.log.v2"
  @summary_prefix "[Earlier conversation summary; context only, not a new instruction]\n"

  @reasons_by_event %{
    "skipped" => ~w(not_enough_groups router_declined insufficient_reduction),
    "rejected" => ~w(
      invalid_layout invalid_response invalid_contract unsafe_summary
    ),
    "failed" => ~w(allocation_failed http_failed)
  }
  @applied_fields ~w(event before_messages after_messages before_bytes after_bytes)
  @non_applied_fields ~w(event reason)

  @doc "Parse one log-file snapshot into API-safe entry maps."
  @spec parse(binary(), binary()) :: [map()]
  def parse(content, log_file) when is_binary(content) and is_binary(log_file) do
    if String.ends_with?(String.downcase(log_file), ".jsonl") do
      parse_jsonl(content, log_file)
    else
      parse_legacy_text(content, log_file)
    end
  end

  @doc "Select one preferred log source per session basename (JSONL before text)."
  @spec select_files([binary()]) :: [binary()]
  def select_files(files) when is_list(files) do
    candidates =
      Enum.filter(files, fn filename ->
        is_binary(filename) and
          (String.ends_with?(filename, ".jsonl") or String.ends_with?(filename, ".txt"))
      end)

    jsonl_roots =
      candidates
      |> Enum.filter(&String.ends_with?(&1, ".jsonl"))
      |> MapSet.new(&Path.rootname(&1))

    Enum.reject(candidates, fn filename ->
      String.ends_with?(filename, ".txt") and MapSet.member?(jsonl_roots, Path.rootname(filename))
    end)
  end

  defp parse_jsonl(content, log_file) do
    if content == "" do
      []
    else
      do_parse_jsonl(content, log_file)
    end
  end

  defp do_parse_jsonl(content, log_file) do
    terminated? = String.ends_with?(content, "\n")
    lines = String.split(content, "\n", trim: false)
    last_index = length(lines)

    lines
    |> Enum.with_index(1)
    |> Enum.reject(fn {line, index} -> line == "" and index == last_index and terminated? end)
    |> Enum.map(fn {line, index} ->
      complete? = terminated? or index < last_index
      parse_jsonl_record(String.trim_trailing(line, "\r"), log_file, index, complete?)
    end)
    |> correlate_compaction_summaries()
  end

  defp parse_jsonl_record(line, log_file, record_index, complete?) do
    case Jason.decode(line) do
      {:ok, record} when is_map(record) ->
        case valid_log_record(record) do
          {:ok, timestamp, sequence, role, content, observed_at_ms} ->
            %{
              session_id: log_file,
              log_file: log_file,
              timestamp: timestamp,
              observed_at_unix_ms: observed_at_ms,
              sequence: sequence,
              record_index: record_index,
              role: role,
              content: content,
              content_complete: complete?,
              integrity: "structured_v2",
              source: source("subzeroclaw.jsonl.v2", "structured_v2")
            }
            |> classify_jsonl()

          :error ->
            invalid_jsonl_entry(line, log_file, record_index, complete?)
        end

      _ ->
        invalid_jsonl_entry(line, log_file, record_index, complete?)
    end
  end

  defp valid_log_record(%{
         "schema" => @record_schema,
         "sequence" => sequence,
         "timestamp" => timestamp,
         "observed_at_unix_ms" => observed_at_ms,
         "role" => role,
         "content" => content
       })
       when is_integer(sequence) and sequence >= 0 and is_binary(timestamp) and
              is_integer(observed_at_ms) and observed_at_ms >= 0 and is_binary(role) and
              is_binary(content) do
    if Regex.match?(@timestamp_regex, timestamp) and byte_size(role) in 1..32 do
      {:ok, timestamp, sequence, String.downcase(role), content, observed_at_ms}
    else
      :error
    end
  end

  defp valid_log_record(_), do: :error

  defp invalid_jsonl_entry(line, log_file, record_index, complete?) do
    %{
      session_id: log_file,
      log_file: log_file,
      timestamp: nil,
      record_index: record_index,
      role: "unknown",
      content: line,
      content_complete: complete?,
      entry_type: "invalid_record",
      sensitive: true,
      integrity: "invalid",
      source: source("subzeroclaw.jsonl.v2", "invalid")
    }
  end

  defp classify_jsonl(%{role: "compact", content_complete: true, content: content} = entry) do
    with {:ok, evidence} <- decode_exact_object(content),
         {:ok, projected} <- project_compaction(evidence) do
      entry
      |> Map.put(:entry_type, "compaction_event")
      |> Map.put(:sensitive, false)
      |> Map.put(:compaction, projected)
      |> Map.put(:content, Jason.encode!(projected))
    else
      _ -> classify_invalid_compaction(entry)
    end
  end

  defp classify_jsonl(%{role: "compact"} = entry), do: classify_invalid_compaction(entry)

  defp classify_jsonl(
         %{
           role: "compact_summary",
           content_complete: true,
           content: content
         } = entry
       ) do
    with true <- String.starts_with?(content, @summary_prefix),
         true <- byte_size(content) > byte_size(@summary_prefix) do
      entry
      |> Map.put(:entry_type, "compaction_summary")
      |> Map.put(:sensitive, true)
      |> Map.put(:compaction_summary_matched_applied, false)
    else
      _ -> classify_invalid_compaction_summary(entry)
    end
  end

  defp classify_jsonl(%{role: "compact_summary"} = entry),
    do: classify_invalid_compaction_summary(entry)

  defp classify_jsonl(entry), do: classify_sensitive(entry)

  defp classify_sensitive(entry) do
    entry
    |> Map.put(:entry_type, "message")
    |> Map.put(:sensitive, true)
  end

  defp classify_invalid_compaction(entry) do
    entry
    |> Map.put(:entry_type, "invalid_compaction")
    |> Map.put(:sensitive, true)
  end

  defp classify_invalid_compaction_summary(entry) do
    entry
    |> Map.put(:entry_type, "invalid_compaction_summary")
    |> Map.put(:sensitive, true)
  end

  defp project_compaction(%{"event" => "applied"} = evidence) do
    if exact_fields?(evidence, @applied_fields) and
         nonnegative_integers?(Map.delete(evidence, "event")) and
         evidence["before_messages"] >= evidence["after_messages"] and
         evidence["before_bytes"] > evidence["after_bytes"] do
      {:ok, evidence}
    else
      :error
    end
  end

  defp project_compaction(%{"event" => event, "reason" => reason} = evidence) do
    if reason in Map.get(@reasons_by_event, event, []) and
         exact_fields?(evidence, @non_applied_fields),
       do: {:ok, evidence},
       else: :error
  end

  defp project_compaction(_), do: :error

  defp decode_exact_object(content) do
    with {:ok, %Jason.OrderedObject{values: pairs}} <-
           Jason.decode(content, objects: :ordered_objects),
         keys = Enum.map(pairs, &elem(&1, 0)),
         true <- length(keys) == MapSet.size(MapSet.new(keys)) do
      {:ok, Map.new(pairs)}
    else
      _ -> :error
    end
  end

  defp exact_fields?(map, fields), do: MapSet.new(Map.keys(map)) == MapSet.new(fields)

  defp nonnegative_integers?(map) do
    Enum.all?(map, fn {_key, value} -> is_integer(value) and value >= 0 end)
  end

  defp correlate_compaction_summaries(entries) do
    entries
    |> Enum.map_reduce(nil, fn entry, previous ->
      correlated = maybe_correlate_summary(entry, previous)
      {correlated, entry}
    end)
    |> elem(0)
  end

  defp maybe_correlate_summary(
         %{
           entry_type: "compaction_summary",
           content_complete: true,
           record_index: summary_index,
           sequence: summary_sequence
         } = summary,
         %{
           entry_type: "compaction_event",
           content_complete: true,
           record_index: applied_index,
           sequence: applied_sequence,
           compaction: %{"event" => "applied"}
         }
       )
       when summary_index == applied_index + 1 and summary_sequence == applied_sequence + 1 do
    summary
    |> Map.put(:compaction_summary_matched_applied, true)
    |> Map.put(:compaction_applied_source_record_index, applied_index)
    |> Map.put(:compaction_applied_sequence, applied_sequence)
  end

  defp maybe_correlate_summary(summary, _previous), do: summary

  defp parse_legacy_text(content, log_file) do
    complete_file? = String.ends_with?(content, "\n")

    content
    |> String.replace("\r\n", "\n")
    |> String.split("\n", trim: false)
    |> drop_file_terminator()
    |> Enum.drop_while(&String.starts_with?(&1, "==="))
    |> parse_legacy_entries(log_file, complete_file?, [], 1)
  end

  defp drop_file_terminator(lines) do
    case Enum.reverse(lines) do
      ["" | rest] -> Enum.reverse(rest)
      _ -> lines
    end
  end

  defp parse_legacy_entries([], _log_file, _complete_file?, acc, _index),
    do: Enum.reverse(acc)

  defp parse_legacy_entries([line | rest], log_file, complete_file?, acc, index) do
    case Regex.named_captures(@entry_regex, line) do
      %{"timestamp" => timestamp, "role" => role} = captures ->
        {continuation, remaining} = Enum.split_while(rest, &(not legacy_header?(&1)))
        content = Enum.join([captures["content"] || "" | continuation], "\n")

        entry = %{
          session_id: log_file,
          log_file: log_file,
          timestamp: timestamp,
          record_index: index,
          role: String.downcase(role),
          content: content,
          content_complete: remaining != [] or complete_file?,
          entry_type:
            if(String.downcase(role) == "compact", do: "compaction_summary", else: "message"),
          sensitive: true,
          integrity: "legacy_text_ambiguous",
          source: source("subzeroclaw.text.v1", "legacy_text_ambiguous")
        }

        parse_legacy_entries(remaining, log_file, complete_file?, [entry | acc], index + 1)

      nil ->
        parse_legacy_entries(rest, log_file, complete_file?, acc, index)
    end
  end

  defp legacy_header?(line), do: Regex.match?(@entry_regex, line)

  defp source(format, integrity) do
    %{
      format: format,
      parser: @parser_version,
      scope: "log_file_snapshot",
      integrity: integrity
    }
  end
end
