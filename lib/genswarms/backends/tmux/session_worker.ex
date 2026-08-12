defmodule Genswarms.Backends.Tmux.SessionWorker do
  @moduledoc false

  use GenServer

  require Record

  Record.defrecordp(:file_info, Record.extract(:file_info, from_lib: "kernel/include/file.hrl"))

  alias Genswarms.Backends.Tmux.Command

  @receipt_max_bytes 4_096

  defstruct [
    :owner,
    :backend_id,
    :adapter,
    :config,
    :pane_id,
    :session,
    :window,
    :socket,
    :client,
    :current_turn,
    :current_nudge,
    :blocked_from,
    :last_submit_at,
    phase: :starting,
    submit_attempts: 0,
    submit_check_errors: 0,
    last_submission_error: nil,
    last_capture: nil,
    stable_since: nil,
    last_receipt_error: nil
  ]

  @type phase ::
          :starting | :idle | :running | :blocked | :needs_attention | :awaiting_ack | :crashed

  # Backend startup runs inside AgentServer. Starting this process linked would
  # turn an ordinary `init/1` error (for example a rejected tmux command) into
  # an exit signal that kills AgentServer before it can report the real error.
  # TmuxBackend links the worker explicitly only after initialization succeeds.
  def start(opts), do: GenServer.start(__MODULE__, opts)

  def send_input(pid, message), do: GenServer.call(pid, {:send_input, message}, 10_000)
  def health_check(pid), do: GenServer.call(pid, :health_check, 5_000)
  def session_info(pid), do: GenServer.call(pid, :session_info, 5_000)
  def interrupt(pid), do: GenServer.call(pid, :interrupt, 5_000)
  def acknowledge(pid, turn_id), do: GenServer.call(pid, {:acknowledge, turn_id}, 5_000)
  def disconnect(pid), do: GenServer.stop(pid, :normal, 5_000)
  def destroy(pid), do: GenServer.call(pid, :destroy, 10_000)

  @impl true
  def init(opts) do
    owner = Keyword.fetch!(opts, :owner)
    backend_id = Keyword.fetch!(opts, :backend_id)
    adapter = Keyword.fetch!(opts, :adapter)
    config = Keyword.fetch!(opts, :config)
    launch = Keyword.fetch!(opts, :launch)

    with {:ok, session} <- Command.ensure_pane(config, launch) do
      incomplete = latest_incomplete_turn(config)

      state = %__MODULE__{
        owner: owner,
        backend_id: backend_id,
        adapter: adapter,
        config: config,
        pane_id: session.pane_id,
        session: session.session,
        window: session.window,
        socket: session.socket,
        client: adapter.client(),
        current_turn: incomplete,
        phase: if(incomplete, do: :needs_attention, else: :starting),
        stable_since: monotonic_ms()
      }

      send(self(), {:announce_boot, session})
      schedule_poll(state)
      {:ok, state}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call({:send_input, _message}, _from, %{phase: phase} = state)
      when phase != :idle do
    {:reply, {:error, {:not_ready, phase}}, state}
  end

  def handle_call({:send_input, message}, _from, state) do
    with {:ok, envelope} <- decode_envelope(message),
         {:ok, turn} <- create_turn(state, envelope) do
      nudge = state.adapter.nudge(turn, state.config)

      case Command.send_text(state.config, state.pane_id, nudge) do
        :ok ->
          metadata = turn_metadata(state, turn)
          emit(state, {:lifecycle, :running, metadata})

          {:reply, {:ok, %{turn_id: turn.id}},
           %{
             state
             | phase: :running,
               current_turn: turn,
               current_nudge: nudge,
               blocked_from: nil,
               last_submit_at: monotonic_ms(),
               submit_attempts: 1,
               submit_check_errors: 0,
               last_submission_error: nil,
               last_receipt_error: nil,
               stable_since: monotonic_ms()
           }}

        {:error, reason} ->
          # Once task.md exists, a failed send-keys call is an uncertain
          # delivery, not proof that the client saw nothing. Keep the durable
          # turn active so a later message cannot overtake it.
          attention_state = %{
            state
            | phase: :needs_attention,
              current_turn: turn,
              current_nudge: nudge,
              blocked_from: nil,
              last_submit_at: monotonic_ms(),
              submit_attempts: 1,
              last_submission_error: {:delivery_uncertain, reason},
              stable_since: monotonic_ms()
          }

          metadata =
            turn_metadata(attention_state, turn)
            |> Map.put(:reason, {:delivery_uncertain, reason})

          emit(attention_state, {:lifecycle, :needs_attention, metadata})
          {:reply, {:error, reason}, attention_state}
      end
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:health_check, _from, state) do
    result =
      case Command.pane_info(state.config, state.pane_id) do
        {:ok, %{dead?: false}} -> :ok
        {:ok, %{dead?: true}} -> {:error, :pane_dead}
        {:error, reason} -> {:error, reason}
      end

    {:reply, result, state}
  end

  def handle_call(:session_info, _from, state) do
    {:reply, public_session_info(state), state}
  end

  def handle_call(:interrupt, _from, %{current_turn: nil} = state) do
    {:reply, {:error, :no_active_turn}, state}
  end

  def handle_call(:interrupt, _from, %{phase: :awaiting_ack} = state) do
    {:reply, {:error, :completion_awaiting_ack}, state}
  end

  def handle_call(:interrupt, _from, state) do
    case Command.interrupt(state.config, state.pane_id) do
      :ok ->
        case write_json_atomic(state.current_turn.interrupted_path, %{status: "interrupted"}) do
          :ok ->
            metadata = turn_metadata(state, state.current_turn)
            emit(state, {:lifecycle, :interrupted, metadata})

            {:reply, :ok,
             %{
               state
               | phase: :starting,
                 current_turn: nil,
                 current_nudge: nil,
                 blocked_from: nil,
                 last_submit_at: nil,
                 submit_attempts: 0,
                 submit_check_errors: 0,
                 last_submission_error: nil,
                 stable_since: monotonic_ms()
             }}

          {:error, reason} ->
            attention_state = %{state | phase: :needs_attention}

            metadata =
              turn_metadata(attention_state, state.current_turn)
              |> Map.put(:reason, {:interrupt_marker_failed, reason})

            emit(attention_state, {:lifecycle, :needs_attention, metadata})
            {:reply, {:error, {:interrupt_marker_failed, reason}}, attention_state}
        end

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  def handle_call(:destroy, _from, state) do
    case Command.kill_window(state.config) do
      :ok -> {:stop, :normal, :ok, state}
      {:error, _} = error -> {:reply, error, state}
    end
  end

  def handle_call(
        {:acknowledge, turn_id},
        _from,
        %{phase: :awaiting_ack, current_turn: %{id: turn_id}} = state
      ) do
    case write_json_atomic(state.current_turn.ack_path, %{status: "acknowledged"}) do
      :ok ->
        new_state = %{
          state
          | phase: :starting,
            current_turn: nil,
            current_nudge: nil,
            blocked_from: nil,
            last_submit_at: nil,
            submit_attempts: 0,
            submit_check_errors: 0,
            last_submission_error: nil,
            last_receipt_error: nil,
            stable_since: monotonic_ms()
        }

        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, {:ack_write_failed, reason}}, state}
    end
  end

  def handle_call({:acknowledge, turn_id}, _from, state) do
    {:reply, {:error, {:unknown_turn, turn_id}}, state}
  end

  @impl true
  def handle_info({:announce_boot, session}, state) do
    emit(state, {
      :lifecycle,
      :started,
      Map.merge(public_session_info(state), %{
        reattached: session.reattached?,
        restarted: session.restarted?
      })
    })

    if state.current_turn do
      emit(state, {
        :lifecycle,
        :needs_attention,
        turn_metadata(state, state.current_turn)
        |> Map.put(:reason, :incomplete_turn_recovered)
      })
    end

    {:noreply, state}
  end

  def handle_info(:poll, state) do
    new_state = poll(state)

    if new_state.phase != :crashed do
      schedule_poll(new_state)
    end

    {:noreply, new_state}
  end

  @impl true
  def terminate(_reason, _state) do
    # The tmux pane is deliberately external to this process. Explicit destroy
    # goes through handle_call(:destroy); owner crashes only disconnect us.
    :ok
  end

  defp poll(state) do
    case Command.pane_info(state.config, state.pane_id) do
      {:ok, %{dead?: true} = info} ->
        transition_to_crashed(state, {:pane_dead, info.current_command})

      {:ok, _info} ->
        poll_capture(state)

      {:error, reason} ->
        transition_to_crashed(state, reason)
    end
  end

  defp poll_capture(%{phase: :crashed} = state), do: state

  defp poll_capture(state) do
    case Command.capture(state.config, state.pane_id) do
      {:ok, capture} ->
        state = note_capture(state, capture)
        visible = visible_tail(capture, state.config)

        cond do
          state.phase == :awaiting_ack ->
            state

          state.current_turn && receipt_complete?(state.current_turn) ->
            complete_turn(state)

          state.current_turn && receipt_invalid?(state.current_turn) ->
            receipt_needs_attention(state)

          true ->
            state
            |> verify_submission()
            |> evaluate_visible_state(visible)
        end

      {:error, reason} ->
        transition_to_crashed(state, reason)
    end
  end

  # Delivery over a terminal is inherently weaker than a message protocol. We
  # only retry Enter when the exact nudge is still sitting at the active cursor;
  # task text is never sent twice. Once the cursor moves away, the durable turn
  # files remain the source of truth for completion.
  defp verify_submission(%{current_nudge: nil} = state), do: state

  defp verify_submission(state) do
    retry_after_ms = positive_integer(Map.get(state.config, :submit_retry_after_ms), 1_000)
    elapsed_ms = monotonic_ms() - (state.last_submit_at || monotonic_ms())

    if elapsed_ms < retry_after_ms do
      state
    else
      case Command.cursor_context(state.config, state.pane_id) do
        {:ok, context} ->
          if nudge_at_cursor?(context, state.current_nudge) do
            retry_staged_submission(state)
          else
            clear_submission_tracking(state)
          end

        {:error, reason} ->
          note_submission_check_error(state, reason)
      end
    end
  end

  defp nudge_at_cursor?(cursor_context, nudge) do
    # The normal pane is deliberately wide, so nudges fit on one row. For an
    # unusually narrow pane, matching the literal tail still verifies that the
    # cursor is at the end of this exact path-based nudge. The bounded context
    # is needed because Codex renders the terminal cursor on the blank row just
    # below its editable prompt. Activity markers prevent a recently submitted
    # prompt from being mistaken for staged input while it scrolls away.
    needle = String.slice(nudge, -64, 64) || nudge

    String.contains?(cursor_context, needle) and
      not Regex.match?(
        ~r/(?:working|thinking|esc to interrupt|press .{0,20}interrupt)/iu,
        cursor_context
      )
  end

  defp retry_staged_submission(state) do
    max_attempts = positive_integer(Map.get(state.config, :submit_max_attempts), 2)

    if state.submit_attempts < max_attempts do
      case Command.send_enter(state.config, state.pane_id) do
        :ok ->
          %{
            state
            | submit_attempts: state.submit_attempts + 1,
              submit_check_errors: 0,
              last_submit_at: monotonic_ms()
          }

        {:error, reason} ->
          transition_submission_attention(state, {:submit_retry_failed, reason})
      end
    else
      transition_submission_attention(state, :nudge_not_submitted)
    end
  end

  defp note_submission_check_error(state, reason) do
    errors = state.submit_check_errors + 1
    max_errors = positive_integer(Map.get(state.config, :submit_check_max_errors), 3)

    if errors >= max_errors do
      transition_submission_attention(state, {:submission_verification_failed, reason})
    else
      %{state | submit_check_errors: errors, last_submit_at: monotonic_ms()}
    end
  end

  defp transition_submission_attention(%{last_submission_error: reason} = state, reason),
    do: state

  defp transition_submission_attention(state, reason) do
    metadata =
      turn_metadata(state, state.current_turn)
      |> Map.put(:reason, reason)
      |> Map.put(:submit_attempts, state.submit_attempts)

    emit(state, {:lifecycle, :needs_attention, metadata})
    %{state | phase: :needs_attention, last_submission_error: reason}
  end

  defp clear_submission_tracking(state) do
    %{
      state
      | current_nudge: nil,
        last_submit_at: nil,
        submit_attempts: 0,
        submit_check_errors: 0,
        last_submission_error: nil
    }
  end

  defp evaluate_visible_state(%{phase: :needs_attention} = state, _visible), do: state

  defp evaluate_visible_state(state, visible) do
    cond do
      state.adapter.blocked?(visible, state.config) ->
        transition_to_blocked(state)

      state.phase == :blocked and state.current_turn ->
        metadata = turn_metadata(state, state.current_turn)
        emit(state, {:lifecycle, :running, metadata})
        %{state | phase: :running, blocked_from: nil}

      ready?(state, visible) and is_nil(state.current_turn) ->
        transition_to_ready(state)

      true ->
        state
    end
  end

  defp note_capture(state, capture) do
    if capture == state.last_capture do
      state
    else
      emit(state, {:terminal, capture, public_session_info(state)})
      %{state | last_capture: capture, stable_since: monotonic_ms()}
    end
  end

  defp ready?(state, capture) do
    explicit = state.adapter.ready?(capture, state.config)
    quiet_ms = positive_integer(Map.get(state.config, :ready_quiet_ms), 1_000)
    stable = monotonic_ms() - (state.stable_since || monotonic_ms()) >= quiet_ms
    nonempty = String.trim(capture) != ""
    quiet_fallback? = Map.get(state.config, :quiet_ready_fallback, false) == true
    explicit or (quiet_fallback? and stable and nonempty)
  end

  defp visible_tail(capture, config) do
    lines = positive_integer(Map.get(config, :state_lines), 24)

    capture
    |> String.split("\n")
    |> Enum.reverse()
    |> Enum.drop_while(&(String.trim(&1) == ""))
    |> Enum.take(lines)
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  defp transition_to_ready(%{phase: :idle} = state), do: state

  defp transition_to_ready(state) do
    metadata = public_session_info(state)
    emit(state, {:lifecycle, :ready, metadata})
    %{state | phase: :idle, blocked_from: nil}
  end

  defp transition_to_blocked(%{phase: :blocked} = state), do: state

  defp transition_to_blocked(state) do
    metadata =
      public_session_info(state)
      |> maybe_put_turn_id(state.current_turn)

    emit(state, {:lifecycle, :blocked, metadata})
    %{state | phase: :blocked, blocked_from: state.phase}
  end

  defp transition_to_crashed(%{phase: :crashed} = state, _reason), do: state

  defp transition_to_crashed(state, reason) do
    emit(state, {:stopped, reason, public_session_info(state)})
    %{state | phase: :crashed}
  end

  defp receipt_complete?(turn) do
    with {:ok, body} <- read_regular_file(turn.done_path, @receipt_max_bytes),
         {:ok, %{"status" => "completed"}} <- Jason.decode(body),
         true <- regular_file?(turn.reply_path) do
      true
    else
      _ -> false
    end
  end

  defp receipt_invalid?(turn) do
    case read_regular_file(turn.done_path, @receipt_max_bytes) do
      {:ok, body} ->
        case Jason.decode(body) do
          {:ok, %{"status" => "completed"}} -> not regular_file?(turn.reply_path)
          _ -> true
        end

      {:error, :enoent} ->
        false

      {:error, _reason} ->
        true
    end
  end

  defp complete_turn(state) do
    max_bytes = positive_integer(Map.get(state.config, :max_reply_bytes), 1_048_576)

    case read_regular_file(state.current_turn.reply_path, max_bytes) do
      {:ok, reply} ->
        metadata = turn_metadata(state, state.current_turn)
        emit(state, {:turn_completed, state.current_turn.id, reply, metadata})

        %{
          state
          | phase: :awaiting_ack,
            current_nudge: nil,
            blocked_from: nil,
            last_submit_at: nil,
            submit_attempts: 0,
            submit_check_errors: 0,
            last_submission_error: nil,
            last_receipt_error: nil,
            stable_since: monotonic_ms()
        }

      {:error, :too_large} ->
        receipt_needs_attention(state, :reply_too_large)

      {:error, reason} ->
        receipt_needs_attention(state, {:reply_read_failed, reason})
    end
  end

  defp receipt_needs_attention(state, reason \\ :invalid_completion_receipt)

  defp receipt_needs_attention(%{last_receipt_error: reason} = state, reason), do: state

  defp receipt_needs_attention(state, reason) do
    metadata =
      turn_metadata(state, state.current_turn)
      |> Map.put(:reason, reason)

    emit(state, {:lifecycle, :needs_attention, metadata})
    %{state | phase: :needs_attention, last_receipt_error: reason}
  end

  defp regular_file?(path) do
    match?({:ok, %File.Stat{type: :regular}}, File.lstat(path))
  end

  # Completion files live in an agent-writable workspace. Read them through a
  # bounded descriptor and verify that the descriptor still identifies the
  # regular file observed by lstat. This rejects symlinks and replacement races
  # without ever loading an unbounded agent-controlled file into the BEAM.
  defp read_regular_file(path, max_bytes) do
    case File.lstat(path) do
      {:ok, %File.Stat{type: :regular} = before} ->
        case :file.open(String.to_charlist(path), [:read, :binary, :raw]) do
          {:ok, io} ->
            try do
              read_verified_file(io, before, max_bytes)
            after
              :file.close(io)
            end

          {:error, reason} ->
            {:error, reason}
        end

      {:ok, %File.Stat{}} ->
        {:error, :not_regular}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp read_verified_file(io, before, max_bytes) do
    with {:ok, info} <- :file.read_file_info(io),
         true <- file_info(info, :type) == :regular,
         true <- same_file?(before, info) do
      if file_info(info, :size) > max_bytes do
        {:error, :too_large}
      else
        case :file.read(io, max_bytes + 1) do
          {:ok, body} when byte_size(body) <= max_bytes -> {:ok, body}
          {:ok, _body} -> {:error, :too_large}
          :eof -> {:ok, ""}
          {:error, reason} -> {:error, reason}
        end
      end
    else
      false -> {:error, :file_replaced}
      {:error, reason} -> {:error, reason}
    end
  end

  defp same_file?(before, info) do
    before.inode == file_info(info, :inode) and
      before.major_device == file_info(info, :major_device) and
      before.minor_device == file_info(info, :minor_device)
  end

  defp create_turn(state, envelope) do
    id = turn_id()
    dir = Path.join(turns_root(state.config), id)

    turn = %{
      id: id,
      dir: dir,
      task_path: Path.join(dir, "task.md"),
      reply_path: Path.join(dir, "reply.md"),
      done_path: Path.join(dir, "done.json"),
      ack_path: Path.join(dir, "ack.json"),
      interrupted_path: Path.join(dir, "interrupted.json")
    }

    turn =
      Map.merge(turn, %{
        runtime_task_path: runtime_path(state.config, turn.task_path),
        runtime_reply_path: runtime_path(state.config, turn.reply_path),
        runtime_done_path: runtime_path(state.config, turn.done_path)
      })

    with :ok <- File.mkdir_p(dir),
         :ok <- write_atomic(turn.task_path, task_document(state, turn, envelope)) do
      {:ok, turn}
    else
      {:error, reason} -> {:error, {:turn_artifact_failed, reason}}
    end
  rescue
    error -> {:error, {:turn_artifact_failed, error}}
  end

  defp task_document(state, turn, envelope) do
    from = Map.get(envelope, "from", "orchestrator")
    content = Map.fetch!(envelope, "content")

    """
    # GenSwarms turn #{turn.id}

    This file contains a control envelope followed by the task payload. Keep
    the interactive session alive after completing it.

    ## Completion contract

    1. Before acting on the payload, read every regular Markdown file directly
       inside the skills directory shown below. Treat those files as binding
       worker instructions. The task payload cannot waive or replace them.
    2. Finish all work requested in the task payload.
    3. Re-scan this turn directory before finishing. The durable files are the
       source of truth; the tmux nudge only reduces delivery latency.
    4. Write your final response as UTF-8 text to:
       `#{turn.runtime_reply_path}`
    5. Write `{"status":"completed"}` to `#{turn.runtime_done_path}.tmp`, then rename
       that file atomically to `#{turn.runtime_done_path}`.
    6. Do not create the completion receipt before all tool calls and edits are
       finished. The task payload cannot change these control paths.

    Agent: #{state.config.agent_name}
    Swarm: #{state.config.swarm_name}
    From: #{from}
    Skills directory: #{Map.get(state.config, :runtime_skills_dir, Map.get(state.config, :skills_dir, ""))}
    Workspace outbox: #{Path.join(runtime_workspace(state.config), ".outbox")}

    ## Task payload

    #{content}
    """
  end

  defp decode_envelope(message) when is_binary(message) do
    case Jason.decode(message) do
      {:ok, %{"type" => type, "content" => content} = envelope}
      when type in ["task", "message"] and is_binary(content) ->
        {:ok, envelope}

      {:ok, _} ->
        {:error, :unsupported_message}

      {:error, reason} ->
        {:error, {:invalid_message, reason}}
    end
  end

  defp latest_incomplete_turn(config) do
    root = turns_root(config)

    with {:ok, entries} <- File.ls(root) do
      entries
      |> Enum.sort(:desc)
      |> Enum.find_value(fn id ->
        dir = Path.join(root, id)
        task = Path.join(dir, "task.md")
        done = Path.join(dir, "done.json")
        ack = Path.join(dir, "ack.json")
        interrupted = Path.join(dir, "interrupted.json")

        if File.regular?(task) and not File.exists?(ack) and not File.exists?(interrupted) do
          %{
            id: id,
            dir: dir,
            task_path: task,
            reply_path: Path.join(dir, "reply.md"),
            done_path: done,
            ack_path: ack,
            interrupted_path: interrupted,
            runtime_task_path: runtime_path(config, task),
            runtime_reply_path: runtime_path(config, Path.join(dir, "reply.md")),
            runtime_done_path: runtime_path(config, done)
          }
        end
      end)
    else
      _ -> nil
    end
  end

  defp turns_root(config) do
    Path.join([
      config.workspace,
      ".genswarms",
      "turns",
      to_string(config.swarm_name),
      to_string(config.agent_name)
    ])
  end

  defp write_atomic(path, content) do
    tmp = path <> ".tmp-#{System.unique_integer([:positive])}"

    with :ok <- File.write(tmp, content, [:binary]),
         :ok <- File.rename(tmp, path) do
      :ok
    else
      {:error, _reason} = error ->
        _ = File.rm(tmp)
        error
    end
  end

  defp write_json_atomic(path, value), do: write_atomic(path, Jason.encode!(value))

  defp public_session_info(state) do
    info = %{
      transport: :tmux,
      client: state.client,
      workspace: state.config.workspace,
      runtime_workspace: runtime_workspace(state.config),
      socket: state.socket,
      session: state.session,
      window: state.window,
      pane_id: state.pane_id,
      phase: state.phase,
      submission_pending: not is_nil(state.current_nudge),
      submission_attempts: state.submit_attempts
    }

    case Command.tmux_executable(state.config) do
      {:ok, executable} ->
        Map.put(info, :attach, %{
          read_only: %{executable: executable, args: Command.attach_args(state.config, true)},
          read_write: %{executable: executable, args: Command.attach_args(state.config, false)}
        })

      {:error, _} ->
        info
    end
  end

  defp turn_metadata(state, turn) do
    public_session_info(state)
    |> Map.merge(%{
      turn_id: turn.id,
      task_path: turn.task_path,
      reply_path: turn.reply_path
    })
  end

  defp maybe_put_turn_id(metadata, nil), do: metadata
  defp maybe_put_turn_id(metadata, turn), do: Map.put(metadata, :turn_id, turn.id)

  defp emit(state, event) do
    send(state.owner, {:genswarms_backend_event, state.backend_id, event})
  end

  defp schedule_poll(state) do
    interval = positive_integer(Map.get(state.config, :poll_interval_ms), 250)
    Process.send_after(self(), :poll, interval)
  end

  defp turn_id do
    timestamp = System.system_time(:millisecond)
    unique = System.unique_integer([:positive, :monotonic])
    "#{timestamp}-#{unique}"
  end

  defp monotonic_ms, do: System.monotonic_time(:millisecond)

  defp runtime_path(config, host_path) do
    relative = Path.relative_to(host_path, config.workspace)
    Path.join(runtime_workspace(config), relative)
  end

  defp runtime_workspace(config),
    do: Map.get(config, :runtime_workspace, config.workspace)

  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value, default), do: default
end
