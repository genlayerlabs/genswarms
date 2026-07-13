defmodule Genswarms.Agents.LogWatcher do
  @moduledoc """
  Watches agent log files for SWARM_MSG patterns and routes messages.
  """

  use GenServer
  require Logger

  alias Genswarms.Agents.Ask
  alias Genswarms.Agents.SubZeroClawLog
  alias Genswarms.Routing.Router
  alias Genswarms.Observability.LogStore

  @poll_interval 500

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Synchronously drain the agent's `.outbox/` now, routing every pending file,
  and return the targets of ALL the plain sends routed this turn
  (`:__broadcast__` for broadcasts; asks are not included): the targets the
  500ms poll already routed since the previous sweep (the accumulator,
  cleared here) plus the targets drained right now. Called by the AgentServer
  at TURN_COMPLETE, which stamps every returned target with the COMPLETING
  turn's seq — exact attribution, because the agent can only write outbox
  files while its turn is running (it is blocked at the prompt otherwise), so
  everything routed between turn start and TURN_COMPLETE belongs to that
  turn. This replaces the old async `note_agent_send` cast, which the
  AgentServer (blocked in this very call) could only process AFTER the
  TURN_COMPLETE handler — by which time the next turn may have begun, so the
  note stamped a FALSE mark on the wrong turn and its legitimate reply was
  silently suppressed (review round 3 finding 1).

  INVARIANT — this is the only synchronous edge in the otherwise all-cast
  Router↔AgentServer↔LogWatcher cycle, and it is safe ONLY while it stays
  one-directional: LogWatcher (including everything reachable from its outbox
  processing: `Router.route/ask` and delivery casts) must NEVER
  `GenServer.call` back into the AgentServer, which is blocked inside this
  call. Turning any of those casts into a call deadlocks the agent at every
  TURN_COMPLETE.
  """
  def sweep_outbox(pid, timeout \\ 4_000) do
    GenServer.call(pid, :sweep_outbox, timeout)
  end

  def init(opts) do
    swarm_name = Keyword.fetch!(opts, :swarm_name)
    agent_name = Keyword.fetch!(opts, :agent_name)
    log_dir = Keyword.fetch!(opts, :log_dir)
    workspace = Keyword.get(opts, :workspace)

    state = %{
      swarm_name: swarm_name,
      agent_name: agent_name,
      log_dir: log_dir,
      workspace: workspace,
      # Plain-send targets the poll path routed since the last sweep, oldest
      # first. Only maintained when the AgentServer actually sweeps (it does
      # iff reply_to is configured — track_sends mirrors that), otherwise the
      # accumulator would grow with no reader.
      track_sends: Keyword.get(opts, :track_sends, false),
      routed_since_sweep: [],
      log_files: %{}
    }

    Process.send_after(self(), :poll, @poll_interval)
    {:ok, state}
  end

  def handle_info(:poll, state) do
    new_state = state |> poll_logs() |> poll_outbox()
    Process.send_after(self(), :poll, @poll_interval)
    {:noreply, new_state}
  end

  def handle_call(:sweep_outbox, _from, state) do
    {targets, new_state} = drain_outbox(state)
    {:reply, state.routed_since_sweep ++ targets, %{new_state | routed_since_sweep: []}}
  end

  defp poll_logs(state) do
    case File.ls(state.log_dir) do
      {:ok, files} ->
        paths =
          files
          |> SubZeroClawLog.select_files()
          |> Enum.sort()
          |> Enum.map(&Path.join(state.log_dir, &1))

        state = Enum.reduce(paths, state, &process_log_file/2)
        %{state | log_files: Map.take(state.log_files, paths)}

      {:error, _} ->
        state
    end
  end

  defp process_log_file(file_path, state) do
    with {:ok, stat} <- File.stat(file_path) do
      identity = {stat.major_device, stat.inode}

      if unchanged_log?(state, file_path, identity, stat.size) do
        state
      else
        # The path-level stat is only a cheap unchanged hint. Rotation may occur
        # after it, so offset selection and pread use one opened descriptor.
        case File.open(file_path, [:read, :binary], fn file ->
               process_open_log(file, file_path, state)
             end) do
          {:ok, new_state} -> new_state
          {:error, _} -> state
        end
      end
    else
      _ -> state
    end
  end

  defp unchanged_log?(state, file_path, identity, size) do
    case Map.get(state.log_files, file_path) do
      %{identity: ^identity, size: ^size} -> true
      _ -> false
    end
  end

  defp process_open_log(file, file_path, state) do
    with {:ok, file_info} <- :file.read_file_info(file) do
      stat = File.Stat.from_record(file_info)
      identity = {stat.major_device, stat.inode}

      if unchanged_log?(state, file_path, identity, stat.size) do
        state
      else
        process_log_suffix(file, file_path, stat.size, identity, state)
      end
    else
      _ -> state
    end
  end

  defp process_log_suffix(file, file_path, size, identity, state) do
    {last_pos, skip_existing?} = initial_log_position(file_path, size, identity, state)

    with {:ok, suffix} <- read_suffix(file, last_pos, size) do
      complete_bytes = complete_size(suffix)
      state = remember_log_position(state, file_path, last_pos + complete_bytes, identity, size)

      if not skip_existing? and complete_bytes > 0 do
        entries =
          suffix
          |> binary_part(0, complete_bytes)
          |> SubZeroClawLog.parse(Path.basename(file_path))

        log_conversation_entries(entries, state)

        entries
        |> parse_swarm_messages()
        |> Enum.each(fn msg -> route_message(msg, state) end)
      end

      state
    else
      _ -> state
    end
  end

  defp read_suffix(_file, position, size) when position == size, do: {:ok, ""}

  defp read_suffix(file, position, size) when position < size,
    do: :file.pread(file, position, size - position)

  defp read_suffix(_file, _position, _size), do: {:error, :invalid_position}

  # A record is authoritative only after its newline has landed. JSONL has a
  # strict framing requirement; retaining the legacy text tail also prevents a
  # complete SWARM_MSG body observed just before its terminating newline from
  # being discarded as incomplete while its bytes are marked consumed. The
  # producer opens these logs append-only; same-inode, same-size rewrites are
  # outside this contract because detecting them requires rereading old bytes.
  defp complete_size(content) do
    if not String.ends_with?(content, "\n") do
      case :binary.matches(content, "\n") do
        [] ->
          0

        matches ->
          {offset, length} = List.last(matches)
          offset + length
      end
    else
      byte_size(content)
    end
  end

  # During an in-process upgrade, a JSONL twin may appear after its legacy text
  # stream was already consumed. Start at the current JSONL boundary to avoid
  # replaying old SWARM_MSG results a second time. Normal startup sees JSONL
  # from byte zero because no legacy position exists yet.
  defp initial_log_position(file_path, size, identity, state) do
    case Map.get(state.log_files, file_path) do
      %{position: position, identity: previous_identity} ->
        if previous_identity != identity or size < position do
          {0, false}
        else
          {position, false}
        end

      nil ->
        legacy_path = Path.rootname(file_path) <> ".txt"

        if String.ends_with?(file_path, ".jsonl") and
             Map.has_key?(state.log_files, legacy_path) and size > 0 do
          {0, true}
        else
          # Remember a zero-length/partial JSONL twin immediately. If its first
          # line completes on the next poll it is new work, not a historical
          # twin that may be skipped to EOF.
          {0, false}
        end
    end
  end

  defp remember_log_position(state, file_path, position, identity, size) do
    file = %{position: position, identity: identity, size: size}
    %{state | log_files: Map.put(state.log_files, file_path, file)}
  end

  defp parse_swarm_messages(entries) do
    messages =
      entries
      |> Enum.filter(&(&1.role == "res" and &1.content_complete))
      |> Enum.flat_map(&parse_msg_block(&1.content))

    # Debug: log if we found multiple messages
    if length(messages) > 1 do
      Logger.debug("Found #{length(messages)} SWARM_MSG blocks in single poll")
    end

    messages
  end

  defp parse_msg_block(content) do
    # Match SWARM_MSG blocks - newline after START is optional
    sends =
      ~r/<<SWARM_MSG:TO=([a-zA-Z_][a-zA-Z0-9_]*):START>>\n?(.*?)<<SWARM_MSG:END>>/s
      |> Regex.scan(content)
      |> Enum.map(fn [_, to, msg] ->
        %{type: :send, to: String.to_atom(to), content: String.trim(msg)}
      end)

    broadcasts =
      ~r/<<SWARM_MSG:BROADCAST:START>>\n?(.*?)<<SWARM_MSG:END>>/s
      |> Regex.scan(content)
      |> Enum.map(fn [_, msg] -> %{type: :broadcast, content: String.trim(msg)} end)

    sends ++ broadcasts
  end

  defp route_message(%{type: :send, to: to, content: content}, state) do
    Logger.info("[#{state.swarm_name}/#{state.agent_name}] Routing message to #{to}")

    content_preview =
      if String.length(content) > 100 do
        String.slice(content, 0, 100) <> "..."
      else
        content
      end

    LogStore.log(
      :info,
      :routing,
      :message_routed,
      "Message: #{state.agent_name} -> #{to}: #{content_preview}",
      swarm: state.swarm_name,
      agent: state.agent_name,
      metadata: %{from: state.agent_name, to: to, content: content}
    )

    Router.route(state.swarm_name, state.agent_name, to, content)
  end

  defp route_message(%{type: :broadcast, content: content}, state) do
    Logger.info("[#{state.swarm_name}/#{state.agent_name}] Broadcasting message")

    content_preview =
      if String.length(content) > 100 do
        String.slice(content, 0, 100) <> "..."
      else
        content
      end

    LogStore.log(
      :info,
      :routing,
      :message_broadcast,
      "Broadcast from #{state.agent_name}: #{content_preview}",
      swarm: state.swarm_name,
      agent: state.agent_name,
      metadata: %{from: state.agent_name, content: content}
    )

    Router.broadcast(state.swarm_name, state.agent_name, content)
  end

  defp log_conversation_entries(entries, state) do
    Enum.each(entries, fn entry ->
      role_lower = entry.role
      content_trimmed = String.trim(entry.content)

      if durable_observability_entry?(entry, content_trimmed) do
        event_type =
          case role_lower do
            "user" -> :user_message
            "asst" -> :assistant_response
            "tool" -> :tool_call
            "res" -> :tool_result
            "sys" -> :system_message
            "compact" -> :context_compact
            _ -> :log_entry
          end

        # Determine log level based on content
        level =
          cond do
            String.contains?(content_trimmed, "error") or
                String.contains?(content_trimmed, "Error") ->
              :warning

            role_lower == "sys" ->
              :debug

            true ->
              :info
          end

        # Truncate content for the message, keep full in metadata
        preview =
          if String.length(content_trimmed) > 150 do
            String.slice(content_trimmed, 0, 150) <> "..."
          else
            content_trimmed
          end

        LogStore.log(level, :agent, event_type, "[#{role_lower}] #{preview}",
          swarm: state.swarm_name,
          agent: state.agent_name,
          metadata: %{
            role: role_lower,
            timestamp: entry.timestamp,
            content: content_trimmed
          }
        )
      end
    end)
  end

  # The exact applied memory is intentionally available only through the
  # sensitive current-slot file endpoint. Classify at the parsed-entry boundary
  # instead of relying only on the wire role: legacy summaries use COMPACT, and
  # an invalid outer JSONL envelope has no trustworthy role but may still carry
  # the complete raw summary body. Lifecycle COMPACT records are sanitized by
  # SubZeroClawLog before they reach this admission check.
  defp durable_observability_entry?(entry, content_trimmed) do
    content_trimmed != "" and entry.entry_type in ["message", "compaction_event"]
  end

  # ============================================================================
  # Outbox: file-based outbound message routing
  # ============================================================================
  #
  # Agents write JSON files to /workspace/.outbox/ to send messages:
  #   {"to": "target_name", "content": "message body"}
  # or for broadcasts:
  #   {"broadcast": true, "content": "message body"}
  #
  # Files are processed in sorted order and deleted after routing.
  # This eliminates the need for swarm-msg send in agent skills.

  defp poll_outbox(state) do
    {targets, new_state} = drain_outbox(state)

    # Mid-turn sends drained by the poll still belong to the in-flight turn —
    # remember them so the TURN_COMPLETE sweep can hand them to the
    # AgentServer for stamping with the correct seq (no async cast; see
    # sweep_outbox/2).
    if new_state.track_sends do
      %{new_state | routed_since_sweep: new_state.routed_since_sweep ++ targets}
    else
      new_state
    end
  end

  # Drain every pending outbox file, returning the routed targets
  # (`:__broadcast__` for broadcasts; asks excluded) for sweep_outbox callers.
  defp drain_outbox(state) do
    workspace = Map.get(state, :workspace)

    if workspace do
      outbox_dir = Path.join(Path.expand(workspace), ".outbox")
      do_drain_outbox(outbox_dir, state)
    else
      {[], state}
    end
  end

  defp do_drain_outbox(outbox_dir, state) do
    case File.ls(outbox_dir) do
      {:ok, files} ->
        targets =
          files
          |> Enum.filter(&String.ends_with?(&1, ".json"))
          |> Enum.sort()
          |> Enum.flat_map(fn filename ->
            case process_outbox_file(Path.join(outbox_dir, filename), state) do
              {:routed, target} -> [target]
              _ -> []
            end
          end)

        {targets, state}

      {:error, _} ->
        {[], state}
    end
  end

  # Returns {:routed, target} for a plain send ({:routed, :__broadcast__} for
  # a broadcast) so sweep_outbox can attribute explicit sends to the turn that
  # just completed; :ok otherwise. Binary guards on to/content/corr: these
  # values come from inside the agent sandbox, and a non-binary would
  # otherwise crash the Router (String.slice on a map) or mint garbage atoms.
  defp process_outbox_file(file_path, state) do
    case File.read(file_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          # Synchronous ask (swarm-msg ask): carries a reply_to correlation id.
          # Routed via Router.ask so the object's reply is written to the
          # caller's reply file instead of arriving as a new turn. This clause
          # must precede the plain send clause (an ask also has to/content).
          # `"reply_to": null` is NOT an ask — pre-existing writers emit the
          # field on plain sends — so nil falls through to the plain-send
          # clause below instead of being dropped as an invalid ask (review
          # round 3 finding 4). The correlation id crossed the sandbox
          # boundary — validate it before it can become a file name (path
          # traversal).
          {:ok, %{"to" => to, "content" => msg, "reply_to" => corr}}
          when is_binary(to) and is_binary(msg) and not is_nil(corr) ->
            if Ask.valid_correlation_id?(corr) do
              Logger.info("[#{state.swarm_name}/#{state.agent_name}] Outbox ask → #{to}")
              Router.ask(state.swarm_name, state.agent_name, String.to_atom(to), msg, corr)
            else
              Logger.warning(
                "[#{state.swarm_name}/#{state.agent_name}] Dropping ask with invalid correlation id"
              )
            end

            File.rm(file_path)
            :ok

          {:ok, %{"to" => to, "content" => msg}} when is_binary(to) and is_binary(msg) ->
            Logger.info("[#{state.swarm_name}/#{state.agent_name}] Outbox → #{to}")
            target = String.to_atom(to)
            Router.route(state.swarm_name, state.agent_name, target, msg)
            File.rm(file_path)
            {:routed, target}

          {:ok, %{"broadcast" => true, "content" => msg}} when is_binary(msg) ->
            Logger.info("[#{state.swarm_name}/#{state.agent_name}] Outbox broadcast")
            # A broadcast reaches the reply sink too (if it's in the topology),
            # so it counts as an explicit send for auto-delivery suppression
            # (the :__broadcast__ wildcard the AgentServer checks).
            Router.broadcast(state.swarm_name, state.agent_name, msg)
            File.rm(file_path)
            {:routed, :__broadcast__}

          _ ->
            Logger.warning(
              "[#{state.swarm_name}/#{state.agent_name}] Invalid outbox file: #{Path.basename(file_path)}"
            )

            File.rm(file_path)
            :ok
        end

      {:error, _} ->
        :ok
    end
  end
end
