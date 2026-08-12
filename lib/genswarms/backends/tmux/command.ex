defmodule Genswarms.Backends.Tmux.CommandRunner do
  @moduledoc false

  @callback run(String.t(), [String.t()]) :: {String.t(), non_neg_integer()}
end

defmodule Genswarms.Backends.Tmux.SystemRunner do
  @moduledoc false

  @behaviour Genswarms.Backends.Tmux.CommandRunner

  @impl true
  def run(executable, args) do
    System.cmd(executable, args, stderr_to_stdout: true)
  rescue
    error -> {Exception.message(error), 127}
  end
end

defmodule Genswarms.Backends.Tmux.Command do
  @moduledoc """
  Safe argv-only adapter around the tmux CLI.

  Task text is never interpolated into a host shell command. The tmux socket,
  session and window identifiers are validated independently even though swarm
  and agent names have already passed `SwarmConfig` validation.
  """

  alias Genswarms.Backends.Tmux.SystemRunner

  @identifier ~r/\A[a-zA-Z][a-zA-Z0-9_-]*\z/

  @type launch :: %{
          required(:executable) => String.t(),
          required(:args) => [String.t()],
          optional(:env) => [{String.t(), String.t()}]
        }

  @spec ensure_pane(map(), launch()) :: {:ok, map()} | {:error, term()}
  def ensure_pane(config, launch) do
    with :ok <- validate_config(config),
         {:ok, target} <- existing_pane(config) do
      ensure_live_pane(config, launch, target)
    else
      {:error, :pane_not_found} -> create_pane(config, launch)
      {:error, :session_not_found} -> create_session(config, launch)
      {:error, _} = error -> error
    end
  end

  @doc "Returns the current pane state without creating or respawning it."
  @spec pane_state(map()) :: {:ok, :missing | map()} | {:error, term()}
  def pane_state(config) do
    with :ok <- validate_config(config) do
      case existing_pane(config) do
        {:ok, target} ->
          with {:ok, info} <- pane_info(config, target.pane_id) do
            {:ok, Map.merge(target, info)}
          end

        {:error, reason} when reason in [:pane_not_found, :session_not_found] ->
          {:ok, :missing}

        {:error, _} = error ->
          error
      end
    end
  end

  defp ensure_live_pane(config, launch, target) do
    case pane_info(config, target.pane_id) do
      {:ok, %{dead?: false}} ->
        {:ok, Map.put(target, :restarted?, false)}

      {:ok, %{dead?: true}} ->
        respawn_pane(config, launch, target)

      {:error, _} = error ->
        error
    end
  end

  defp respawn_pane(config, launch, target) do
    with {:ok, _} <- command(config, respawn_args(config, launch, target.pane_id)) do
      {:ok, %{target | reattached?: false, restarted?: true}}
    end
  end

  @spec pane_info(map(), String.t()) :: {:ok, map()} | {:error, term()}
  def pane_info(config, pane_id) do
    format = "\#{pane_id}\t\#{pane_dead}\t\#{pane_current_command}\t\#{pane_pid}"

    with {:ok, output} <- command(config, ["display-message", "-p", "-t", pane_id, format]),
         [id, dead, current_command, pid] <- String.trim(output) |> String.split("\t") do
      {:ok,
       %{
         pane_id: id,
         dead?: dead == "1",
         current_command: current_command,
         pane_pid: parse_integer(pid)
       }}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_pane_info}
    end
  end

  @spec capture(map(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def capture(config, pane_id) do
    history_lines = positive_integer(Map.get(config, :history_lines), 200)

    command(config, [
      "capture-pane",
      "-p",
      "-J",
      "-S",
      "-#{history_lines}",
      "-t",
      pane_id
    ])
  end

  @spec send_text(map(), String.t(), String.t()) :: :ok | {:error, term()}
  def send_text(config, pane_id, text) when is_binary(text) do
    cond do
      text == "" ->
        {:error, :empty_input}

      String.contains?(text, <<0>>) ->
        {:error, :nul_in_input}

      true ->
        with {:ok, _} <- command(config, ["send-keys", "-l", "-t", pane_id, text]),
             :ok <- wait_before_submit(config),
             :ok <- send_enter(config, pane_id) do
          :ok
        end
    end
  end

  @doc "Submits text already staged at the pane's active prompt."
  @spec send_enter(map(), String.t()) :: :ok | {:error, term()}
  def send_enter(config, pane_id) do
    case command(config, ["send-keys", "-t", pane_id, "Enter"]) do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  @doc "Captures the active cursor row and a small amount of immediate context."
  @spec cursor_context(map(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def cursor_context(config, pane_id) do
    format = "\#{cursor_y}\t\#{pane_height}"

    with {:ok, position} <-
           command(config, ["display-message", "-p", "-t", pane_id, format]),
         {:ok, cursor_y, pane_height} <- parse_cursor_position(position),
         true <- (cursor_y >= 0 and cursor_y < pane_height) or {:error, :invalid_cursor_position} do
      context_lines = positive_integer(Map.get(config, :submission_context_lines), 6)
      start_line = max(cursor_y - context_lines + 1, 0)

      command(config, [
        "capture-pane",
        "-p",
        "-J",
        "-S",
        Integer.to_string(start_line),
        "-E",
        Integer.to_string(cursor_y),
        "-t",
        pane_id
      ])
    else
      {:error, _} = error -> error
    end
  end

  @spec interrupt(map(), String.t()) :: :ok | {:error, term()}
  def interrupt(config, pane_id) do
    case command(config, ["send-keys", "-t", pane_id, "C-c"]) do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  @spec kill_window(map()) :: :ok | {:error, term()}
  def kill_window(config) do
    target = window_target(config)

    case command(config, ["kill-window", "-t", target]) do
      {:ok, _} ->
        :ok

      {:error, {:tmux_command_failed, _status, output}} = error ->
        if String.contains?(output, ["can't find", "no server running", "error connecting to"]),
          do: :ok,
          else: error

      {:error, _} = error ->
        error
    end
  end

  @spec attach_args(map(), boolean()) :: [String.t()]
  def attach_args(config, read_only? \\ true) do
    base = ["-L", Map.fetch!(config, :tmux_socket), "attach-session"]
    mode = if read_only?, do: ["-r"], else: []
    base ++ mode ++ ["-t", window_target(config)]
  end

  @spec tmux_executable(map()) :: {:ok, String.t()} | {:error, term()}
  def tmux_executable(config) do
    configured = Map.get(config, :tmux_executable, "tmux")

    cond do
      not is_binary(configured) or configured == "" ->
        {:error, {:invalid_tmux_executable, configured}}

      Path.type(configured) == :absolute and File.regular?(configured) ->
        {:ok, configured}

      path = System.find_executable(configured) ->
        {:ok, path}

      true ->
        {:error, :tmux_not_found}
    end
  end

  defp existing_pane(config) do
    target = window_target(config)

    case command(config, ["list-panes", "-t", target, "-F", "\#{pane_id}"]) do
      {:ok, output} ->
        case String.split(output, "\n", trim: true) do
          [pane_id | _] -> {:ok, session_metadata(config, pane_id, true)}
          [] -> {:error, :pane_not_found}
        end

      {:error, {:tmux_command_failed, _status, output}} = error ->
        cond do
          String.contains?(output, [
            "can't find session",
            "no server running",
            "error connecting to"
          ]) ->
            {:error, :session_not_found}

          String.contains?(output, ["can't find window", "can't find pane"]) ->
            {:error, :pane_not_found}

          true ->
            error
        end

      {:error, _} = error ->
        error
    end
  end

  defp create_session(config, launch) do
    args =
      [
        "new-session",
        "-d",
        "-s",
        Map.fetch!(config, :session_name),
        "-n",
        Map.fetch!(config, :window_name),
        "-x",
        Integer.to_string(positive_integer(Map.get(config, :cols), 180)),
        "-y",
        Integer.to_string(positive_integer(Map.get(config, :rows), 48)),
        "-c",
        Map.fetch!(config, :workspace)
      ]

    case command(config, args) do
      {:ok, _} ->
        finish_created_pane(config, launch)

      # AgentServer processes start asynchronously. Two agents in the same
      # swarm can both observe a missing shared session before either creates
      # it; the loser of that race should add its own window to the winner.
      {:error, {:tmux_command_failed, _status, output}} = error ->
        if String.contains?(output, "duplicate session"),
          do: create_pane(config, launch),
          else: error

      {:error, _} = error ->
        error
    end
  end

  defp create_pane(config, launch) do
    args =
      [
        "new-window",
        "-d",
        "-t",
        Map.fetch!(config, :session_name),
        "-n",
        Map.fetch!(config, :window_name),
        "-c",
        Map.fetch!(config, :workspace)
      ]

    with {:ok, _} <- command(config, args) do
      finish_created_pane(config, launch)
    end
  end

  # Create the pane with tmux's default interactive shell first, configure
  # remain-on-exit, and only then replace it with the real client. If bwrap or
  # the TUI fails immediately, tmux now keeps the dead pane and its terminal
  # output available for diagnosis instead of dropping the entire session in
  # the small race before configure_window/1.
  defp finish_created_pane(config, launch) do
    with :ok <- configure_window(config),
         {:ok, target} <- existing_pane(config),
         {:ok, _} <- command(config, respawn_args(config, launch, target.pane_id)) do
      {:ok, %{target | reattached?: false, restarted?: false}}
    end
  end

  defp respawn_args(config, launch, pane_id) do
    [
      "respawn-pane",
      "-k",
      "-t",
      pane_id,
      "-c",
      Map.fetch!(config, :workspace)
    ] ++ env_args(launch) ++ launch_argv(launch)
  end

  defp configure_window(config) do
    target = window_target(config)
    history = Integer.to_string(positive_integer(Map.get(config, :history_limit), 20_000))

    commands = [
      ["set-option", "-w", "-t", target, "remain-on-exit", "on"],
      ["set-option", "-w", "-t", target, "automatic-rename", "off"],
      ["set-option", "-w", "-t", target, "allow-rename", "off"],
      ["set-option", "-w", "-t", target, "history-limit", history]
    ]

    Enum.reduce_while(commands, :ok, fn args, :ok ->
      case command(config, args) do
        {:ok, _} -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp command(config, args) do
    with {:ok, executable} <- tmux_executable(config) do
      runner = Map.get(config, :command_runner, SystemRunner)
      socket_args = ["-L", Map.fetch!(config, :tmux_socket)]

      case runner.run(executable, socket_args ++ args) do
        {output, 0} -> {:ok, output}
        {output, status} -> {:error, {:tmux_command_failed, status, String.trim(output)}}
      end
    end
  rescue
    error -> {:error, {:tmux_command_exception, Exception.message(error)}}
  end

  defp wait_before_submit(config) do
    delay_ms = non_negative_integer(Map.get(config, :submit_delay_ms), 100)

    if delay_ms > 0, do: Process.sleep(delay_ms)
    :ok
  end

  defp parse_cursor_position(position) do
    case String.trim(position) |> String.split("\t") do
      [cursor_y, pane_height] ->
        with {cursor_y, ""} <- Integer.parse(cursor_y),
             {pane_height, ""} <- Integer.parse(pane_height) do
          {:ok, cursor_y, pane_height}
        else
          _ -> {:error, :invalid_cursor_position}
        end

      _ ->
        {:error, :invalid_cursor_position}
    end
  end

  defp validate_config(config) do
    identifiers = [
      Map.get(config, :tmux_socket),
      Map.get(config, :session_name),
      Map.get(config, :window_name)
    ]

    cond do
      not Enum.all?(identifiers, &(is_binary(&1) and Regex.match?(@identifier, &1))) ->
        {:error, :invalid_tmux_identifier}

      not is_binary(Map.get(config, :workspace)) ->
        {:error, :invalid_workspace}

      true ->
        :ok
    end
  end

  defp window_target(config),
    do: "#{Map.fetch!(config, :session_name)}:#{Map.fetch!(config, :window_name)}"

  defp session_metadata(config, pane_id, reattached?) do
    %{
      socket: Map.fetch!(config, :tmux_socket),
      session: Map.fetch!(config, :session_name),
      window: Map.fetch!(config, :window_name),
      pane_id: String.trim(pane_id),
      reattached?: reattached?,
      restarted?: false
    }
  end

  defp env_args(%{env: env}) when is_list(env) do
    Enum.flat_map(env, fn
      {key, value} when is_binary(key) and is_binary(value) -> ["-e", key <> "=" <> value]
      _ -> []
    end)
  end

  defp env_args(_), do: []

  defp launch_argv(%{executable: executable, args: args}), do: [executable | args]

  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value, default), do: default

  defp non_negative_integer(value, _default) when is_integer(value) and value >= 0, do: value
  defp non_negative_integer(_value, default), do: default

  defp parse_integer(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _ -> nil
    end
  end
end
