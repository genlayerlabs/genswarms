defmodule Genswarms.Backends.LocalBackend do
  @moduledoc """
  Local backend implementation using Elixir Ports.

  Spawns subzeroclaw as a subprocess and communicates via stdin/stdout.
  Uses the szc-wrapper script to translate between JSON protocol and
  subzeroclaw's plain text interface.
  """

  @behaviour Genswarms.Backends.BackendBehaviour

  require Logger

  defstruct [:port, :name, :skills_dir, :session_id, :buffer]

  @type t :: %__MODULE__{
          port: port(),
          name: String.t(),
          skills_dir: String.t() | nil,
          session_id: String.t() | nil,
          buffer: binary()
        }

  @impl true
  def backend_type, do: :local

  @impl true
  def start(name, config) do
    wrapper_path = get_wrapper_path(config)
    subzeroclaw_path = get_subzeroclaw_path(config)
    skills_dir = Map.get(config, :skills_dir)
    workspace = prepare_workspace(config)

    builtin_env =
      [
        {~c"SUBZEROCLAW_AGENT_NAME", String.to_charlist(name)}
      ] ++
        maybe_add_skills_env(skills_dir) ++
        maybe_add_api_key_env(config) ++
        maybe_add_request_extra_env(config) ++
        maybe_add_compact_extra_env(config) ++
        maybe_add_endpoint_env(config)

    env =
      builtin_env ++
        maybe_add_workspace_env(workspace, builtin_env) ++
        maybe_add_extra_env(config, builtin_env)

    port_opts =
      [
        :binary,
        :exit_status,
        {:line, 16_384},
        {:env, env},
        :use_stdio,
        :stderr_to_stdout
      ] ++ maybe_add_cd(workspace)

    args = build_args(name, subzeroclaw_path, skills_dir)

    try do
      # spawn_executable + :args passes argv directly (no /bin/sh), so agent
      # names / paths cannot be interpreted as shell commands. Using {:spawn, str}
      # here would run the string through "/bin/sh -c" (command injection).
      port = Port.open({:spawn_executable, wrapper_path}, [{:args, args} | port_opts])

      ref = %__MODULE__{
        port: port,
        name: name,
        skills_dir: skills_dir,
        session_id: nil,
        buffer: ""
      }

      Logger.info("Started local agent #{name} with port #{inspect(port)}")
      {:ok, ref}
    rescue
      e ->
        Logger.error("Failed to start local agent #{name}: #{inspect(e)}")
        {:error, {:start_failed, e}}
    end
  end

  @impl true
  def stop(%__MODULE__{port: port, name: name}) do
    Logger.info("Stopping local agent #{name}")

    # Grab the OS pid BEFORE closing — the port is gone afterwards.
    os_pid =
      try do
        case Port.info(port, :os_pid) do
          {:os_pid, pid} -> pid
          _ -> nil
        end
      rescue
        _ -> nil
      end

    try do
      Port.close(port)
    rescue
      _ -> :ok
    end

    # Port.close only shuts the wrapper's stdin. A busy agent (subzeroclaw mid
    # LLM/tool call) is not reading stdin, never sees the EOF, and survives —
    # leaking the wrapper + subzeroclaw as orphans. Actually signal the wrapper
    # so its `trap cleanup EXIT` reaps subzeroclaw; hard-kill if it ignores TERM.
    if os_pid, do: terminate_os_process(os_pid)
    :ok
  end

  defp terminate_os_process(os_pid) do
    pid = Integer.to_string(os_pid)

    try do
      System.cmd("kill", ["-TERM", pid], stderr_to_stdout: true)

      unless wait_for_exit(pid, 20) do
        System.cmd("kill", ["-KILL", pid], stderr_to_stdout: true)
      end
    rescue
      _ -> :ok
    end
  end

  # Poll up to ~2s for the process to be gone (`kill -0` returns non-zero).
  defp wait_for_exit(_pid, 0), do: false

  defp wait_for_exit(pid, attempts) do
    case System.cmd("kill", ["-0", pid], stderr_to_stdout: true) do
      {_, 0} ->
        Process.sleep(100)
        wait_for_exit(pid, attempts - 1)

      _ ->
        true
    end
  end

  @impl true
  def send_input(%__MODULE__{port: port}, message) when is_binary(message) do
    # Ensure message ends with newline for line-based protocol
    data =
      if String.ends_with?(message, "\n") do
        message
      else
        message <> "\n"
      end

    try do
      Port.command(port, data)
      :ok
    rescue
      e ->
        {:error, {:send_failed, e}}
    end
  end

  @impl true
  def deploy_skills(%__MODULE__{} = ref, skills_dir) do
    # For local backend, skills are deployed via env var at start time
    # This callback is mainly for updating skills at runtime
    {:ok, %{ref | skills_dir: skills_dir}}
  end

  @impl true
  def health_check(%__MODULE__{port: port}) do
    case Port.info(port) do
      nil -> {:error, :port_closed}
      info when is_list(info) -> :ok
    end
  end

  @impl true
  def handle_output(%__MODULE__{buffer: buffer}, data) do
    # Combine buffer with new data and parse complete JSON lines
    combined = buffer <> data
    {messages, remaining} = parse_json_lines(combined)
    {:ok, messages, remaining}
  end

  # Private functions

  defp get_wrapper_path(config) do
    Map.get(config, :wrapper_path) ||
      Application.get_env(:genswarms, :wrapper_path) ||
      Path.join(:code.priv_dir(:genswarms), "szc-wrapper-fifo.sh")
  end

  defp get_subzeroclaw_path(config) do
    Map.get(config, :subzeroclaw_path) ||
      Application.get_env(:genswarms, :subzeroclaw_path, "subzeroclaw")
  end

  defp prepare_workspace(config) do
    case Map.get(config, :workspace) do
      workspace when is_binary(workspace) ->
        workspace = Path.expand(workspace)
        File.mkdir_p!(workspace)
        workspace

      _ ->
        nil
    end
  end

  # swarm-msg defaults its outbox/ask-reply paths to the bwrap mount
  # (/workspace/…); on :local the workspace is a host dir — point the
  # helper at it explicitly so agent sends don't die on a read-only /.
  defp maybe_add_workspace_env(nil, _builtin), do: []

  defp maybe_add_workspace_env(workspace, builtin_env) do
    [
      {~c"OUTBOX_DIR", String.to_charlist(Path.join(workspace, ".outbox"))},
      {~c"ASK_REPLY_DIR", String.to_charlist(Path.join(workspace, ".inbox/replies"))}
    ]
    |> Enum.reject(fn {k, _} -> List.keymember?(builtin_env, k, 0) end)
  end

  defp maybe_add_cd(nil), do: []
  defp maybe_add_cd(workspace), do: [{:cd, workspace}]

  # argv list passed to the wrapper: <agent_name> <subzeroclaw_path> [skills_dir].
  # Returned as a list (not a joined string) so Port spawn_executable hands them
  # to execvp directly and no shell metacharacter interpretation can occur.
  @doc false
  def build_args(name, subzeroclaw_path, skills_dir) do
    skills_arg = if skills_dir, do: skills_dir, else: ""
    [to_string(name), to_string(subzeroclaw_path), to_string(skills_arg)]
  end

  defp maybe_add_skills_env(nil), do: []

  defp maybe_add_skills_env(skills_dir) do
    [{~c"SUBZEROCLAW_SKILLS", String.to_charlist(Path.expand(skills_dir))}]
  end

  defp maybe_add_api_key_env(config) do
    # api_key is resolved via EndpointPolicy so the server-env key is not
    # forwarded alongside an untrusted/custom endpoint (SSRF key-exfil guard).
    case Genswarms.Backends.EndpointPolicy.resolve(config) do
      {_endpoint, nil} -> []
      {_endpoint, key} -> [{~c"SUBZEROCLAW_API_KEY", String.to_charlist(key)}]
    end
  end

  # subzeroclaw no longer reads SUBZEROCLAW_MODEL — the model rides in
  # SUBZEROCLAW_REQUEST_EXTRA (the generic body-override channel), alongside any
  # routing policy_ir for the unhardcoded router. Accept `:request_extra` directly
  # (map or JSON string); for back-compat wrap a bare `:model` as {"model": ...}.
  defp maybe_add_request_extra_env(config) do
    case config_json(config, :request_extra) || bare_model_extra(config) do
      nil -> []
      json -> [{~c"SUBZEROCLAW_REQUEST_EXTRA", String.to_charlist(json)}]
    end
  end

  # The compaction JSON (keep_recent + cheap summariser policy_ir): subzeroclaw
  # seals async via /v1/compact when set; absent → no compaction.
  defp maybe_add_compact_extra_env(config) do
    case config_json(config, :compact_extra) do
      nil -> []
      json -> [{~c"SUBZEROCLAW_COMPACT_EXTRA", String.to_charlist(json)}]
    end
  end

  defp bare_model_extra(config) do
    # ONLY a config-level :model is wrapped (back-compat). We do NOT read a
    # SUBZEROCLAW_MODEL env fallback: it is the dead var, and reading it would
    # clobber an inherited SUBZEROCLAW_REQUEST_EXTRA (the routing policy) with a
    # bare {"model": ...}. No config model -> emit nothing, let the env policy pass.
    case Map.get(config, :model) do
      nil -> nil
      model -> Jason.encode!(%{"model" => model})
    end
  end

  defp config_json(config, key) do
    case Map.get(config, key) do
      nil -> nil
      v when is_binary(v) -> v
      v when is_map(v) -> Jason.encode!(v)
      _ -> nil
    end
  end

  defp maybe_add_endpoint_env(config) do
    case Genswarms.Backends.EndpointPolicy.resolve(config) do
      {nil, _key} -> []
      {endpoint, _key} -> [{~c"SUBZEROCLAW_ENDPOINT", String.to_charlist(endpoint)}]
    end
  end

  defp maybe_add_extra_env(config, builtin_env) do
    reserved =
      builtin_env
      |> Enum.map(fn {key, _value} -> to_string(key) end)
      |> MapSet.new()

    case Map.get(config, :extra_env, %{}) do
      extra_env when is_map(extra_env) ->
        Enum.flat_map(extra_env, fn {key, value} ->
          key = to_string(key)

          if value && not MapSet.member?(reserved, key) do
            [{String.to_charlist(key), String.to_charlist(to_string(value))}]
          else
            []
          end
        end)

      _ ->
        []
    end
  end

  defp parse_json_lines(data) do
    lines = String.split(data, "\n")

    {complete_lines, [remaining]} =
      case lines do
        [] -> {[], [""]}
        _ -> Enum.split(lines, -1)
      end

    messages =
      complete_lines
      |> Enum.filter(&(&1 != ""))
      |> Enum.map(&parse_json_message/1)
      |> Enum.filter(&(&1 != nil))

    {messages, remaining}
  end

  defp parse_json_message(line) do
    case Jason.decode(line) do
      {:ok, message} ->
        message

      {:error, _} ->
        # Not valid JSON, treat as raw output
        %{"type" => "output", "content" => line}
    end
  end
end
