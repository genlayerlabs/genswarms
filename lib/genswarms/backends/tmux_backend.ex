defmodule Genswarms.Backends.TmuxBackend do
  @moduledoc """
  Persistent interactive-agent backend hosted in tmux.

  Host-side tmux owns the PTY and keeps the coding client attachable. A runner
  can execute that client directly, through `docker exec -it`, or inside a
  per-agent bwrap sandbox. GenSwarms owns worker identity and routing, while
  per-turn files provide the durable task and completion boundary.
  """

  @behaviour Genswarms.Backends.BackendBehaviour

  alias Genswarms.Backends.Tmux.{Adapters, Command, Runners, SessionWorker}

  defstruct [:worker, :name, :workspace, :config, :runner, :runner_ref, :identity_path]

  @type t :: %__MODULE__{
          worker: pid(),
          name: String.t(),
          workspace: String.t(),
          config: map(),
          runner: module(),
          runner_ref: term(),
          identity_path: String.t()
        }

  @impl true
  def backend_type, do: :tmux

  @impl true
  def capabilities,
    do: MapSet.new([:readiness_events, :interrupt, :persistent_session, :raw_terminal])

  @impl true
  def start(name, config) when is_binary(name) and is_map(config) do
    with {:ok, owner} <- fetch_owner(config),
         {:ok, backend_id} <- fetch_backend_id(config),
         {:ok, adapter} <- Adapters.resolve(Map.get(config, :client)),
         {:ok, normalized} <- normalize_config(name, config),
         {:ok, runner} <- Runners.resolve(Map.get(normalized, :runner)),
         {:ok, runner_config} <- runner.configure(normalized),
         {:ok, pane_state} <- Command.pane_state(runner_config),
         {:ok, client_launch} <- adapter.launch(runner_config),
         identity = runtime_identity(runner_config, runner, client_launch),
         :ok <- verify_runtime_identity(runner_config, runner, pane_state, identity),
         {:ok, runner_ref, pane_launch} <-
           runner.prepare(runner_config, client_launch, pane_state) do
      start_session(
        name,
        owner,
        backend_id,
        adapter,
        runner,
        runner_ref,
        runner_config,
        pane_launch,
        pane_state,
        identity
      )
    end
  end

  @impl true
  def stop(%__MODULE__{} = ref), do: destroy(ref)

  @impl true
  def destroy(%__MODULE__{} = ref) do
    pane_result =
      case call_worker(fn -> SessionWorker.destroy(ref.worker) end) do
        {:error, {:worker_unavailable, _reason}} -> Command.kill_window(ref.config)
        result -> result
      end

    with :ok <- pane_result,
         :ok <- ref.runner.destroy(ref.runner_ref) do
      _ = File.rm(ref.identity_path)
      :ok
    end
  end

  @impl true
  def disconnect(%__MODULE__{worker: worker}),
    do: call_worker(fn -> SessionWorker.disconnect(worker) end)

  @impl true
  def send_input(%__MODULE__{worker: worker}, message),
    do: call_worker(fn -> SessionWorker.send_input(worker, message) end)

  @impl true
  def deploy_skills(%__MODULE__{}, _skills_dir), do: :ok

  @impl true
  def health_check(%__MODULE__{} = ref) do
    with :ok <- call_worker(fn -> SessionWorker.health_check(ref.worker) end),
         :ok <- ref.runner.health_check(ref.runner_ref) do
      :ok
    end
  end

  @impl true
  def interrupt(%__MODULE__{worker: worker}),
    do: call_worker(fn -> SessionWorker.interrupt(worker) end)

  @impl true
  def acknowledge(%__MODULE__{worker: worker}, turn_id),
    do: call_worker(fn -> SessionWorker.acknowledge(worker, turn_id) end)

  @impl true
  def session_info(%__MODULE__{} = ref) do
    terminal =
      case call_worker(fn -> SessionWorker.session_info(ref.worker) end) do
        info when is_map(info) -> info
        _ -> %{}
      end

    Map.put(terminal, :runner, ref.runner.session_info(ref.runner_ref))
  end

  defp normalize_config(name, config) do
    swarm_name = to_string(Map.fetch!(config, :swarm_name))
    workspace = Map.get(config, :workspace) || default_workspace(swarm_name, name)

    normalized =
      config
      |> Map.put(:agent_name, name)
      |> Map.put(:swarm_name, swarm_name)
      |> Map.put(:workspace, Path.expand(workspace))
      |> Map.put_new(:tmux_socket, "genswarms")
      |> Map.put_new(:session_name, "genswarms-#{swarm_name}")
      |> Map.put_new(:window_name, name)

    with true <- is_binary(workspace) or {:error, :invalid_workspace},
         :ok <- File.mkdir_p(normalized.workspace) do
      {:ok, normalized}
    else
      {:error, reason} -> {:error, {:workspace_failed, reason}}
    end
  rescue
    KeyError -> {:error, :missing_swarm_name}
    error -> {:error, {:invalid_tmux_config, Exception.message(error)}}
  end

  defp fetch_owner(config) do
    case Map.get(config, :event_sink) do
      owner when is_pid(owner) -> {:ok, owner}
      _ -> {:error, :missing_event_sink}
    end
  end

  defp fetch_backend_id(config) do
    case Map.fetch(config, :backend_id) do
      {:ok, backend_id} -> {:ok, backend_id}
      :error -> {:error, :missing_backend_id}
    end
  end

  defp default_workspace(swarm_name, name) do
    Path.join([System.tmp_dir!(), "genswarms-tmux", swarm_name, name])
  end

  defp start_session(
         name,
         owner,
         backend_id,
         adapter,
         runner,
         runner_ref,
         config,
         launch,
         pane_state,
         identity
       ) do
    identity_path = identity_path(config)

    # Claim the durable runtime identity before tmux can make a pane visible.
    # If AgentServer dies between pane creation and backend return, its restart
    # can now verify and reattach to the same sandbox instead of failing closed
    # on a live pane with no identity file.
    case write_runtime_identity(identity_path, identity) do
      :ok ->
        start_session_worker(
          name,
          owner,
          backend_id,
          adapter,
          runner,
          runner_ref,
          config,
          launch,
          pane_state,
          identity_path
        )

      {:error, reason} ->
        maybe_cleanup_new_runner(runner, runner_ref, pane_state)
        {:error, {:runtime_identity_failed, reason}}
    end
  end

  defp start_session_worker(
         name,
         owner,
         backend_id,
         adapter,
         runner,
         runner_ref,
         config,
         launch,
         pane_state,
         identity_path
       ) do
    case SessionWorker.start(
           owner: owner,
           backend_id: backend_id,
           adapter: adapter,
           config: config,
           launch: launch
         ) do
      {:ok, worker} ->
        # SessionWorker deliberately starts unlinked so an init error is a
        # return value. Once it is healthy, restore the ownership relationship:
        # AgentServer termination disconnects it, while an abnormal worker exit
        # still restarts the owning agent through the existing link semantics.
        Process.link(worker)

        {:ok,
         %__MODULE__{
           worker: worker,
           name: name,
           workspace: config.workspace,
           config: config,
           runner: runner,
           runner_ref: runner_ref,
           identity_path: identity_path
         }}

      {:error, reason} ->
        # Keep the identity next to the preserved pane. It records exactly what
        # was attempted and permits a controlled restart to inspect or reattach
        # without weakening the live-pane identity check.
        maybe_cleanup_new_runner(runner, runner_ref, pane_state)
        {:error, reason}
    end
  end

  defp verify_runtime_identity(config, runner, pane_state, expected) do
    path = identity_path(config)

    case File.read(path) do
      {:ok, body} ->
        with {:ok, actual} <- Jason.decode(body) do
          cond do
            actual == expected -> :ok
            match?(%{dead?: false}, pane_state) -> {:error, {:runtime_identity_mismatch, actual}}
            true -> :ok
          end
        else
          {:error, _} = error -> error
        end

      {:error, :enoent} ->
        if not match?(%{dead?: false}, pane_state) or
             runner == Genswarms.Backends.Tmux.Runners.Host,
           do: :ok,
           else: {:error, :missing_runtime_identity}

      {:error, reason} ->
        {:error, {:runtime_identity_read_failed, reason}}
    end
  end

  defp write_runtime_identity(path, identity) do
    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.chmod(Path.dirname(path), 0o700),
         :ok <- write_atomic(path, Jason.encode!(identity)),
         :ok <- File.chmod(path, 0o600) do
      :ok
    end
  end

  defp runtime_identity(config, runner, client_launch) do
    %{
      "runner" => runner_name(runner),
      "client" => to_string(config.client),
      "socket" => config.tmux_socket,
      "session" => config.session_name,
      "window" => config.window_name,
      "launch_sha256" => launch_fingerprint(client_launch)
    }
  end

  defp launch_fingerprint(launch) do
    :sha256
    |> :crypto.hash(:erlang.term_to_binary(launch, [:deterministic]))
    |> Base.encode16(case: :lower)
  end

  defp runner_name(Genswarms.Backends.Tmux.Runners.Host), do: "host"
  defp runner_name(Genswarms.Backends.Tmux.Runners.Docker), do: "docker"
  defp runner_name(Genswarms.Backends.Tmux.Runners.Bwrap), do: "bwrap"

  defp identity_path(config) do
    transport =
      :sha256
      |> :crypto.hash("#{config.tmux_socket}\0#{config.session_name}")
      |> Base.encode16(case: :lower)
      |> binary_part(0, 16)

    Path.join([
      System.tmp_dir!(),
      "genswarms-tmux-control",
      "tmux",
      transport,
      to_string(config.swarm_name),
      "#{config.agent_name}.json"
    ])
  end

  defp write_atomic(path, body) do
    tmp = path <> ".tmp-#{System.unique_integer([:positive])}"

    with :ok <- File.write(tmp, body, [:binary]),
         :ok <- File.rename(tmp, path) do
      :ok
    else
      {:error, _} = error ->
        _ = File.rm(tmp)
        error
    end
  end

  defp maybe_cleanup_new_runner(runner, runner_ref, pane_state) do
    if Map.get(runner_ref, :created?, false) and not match?(%{dead?: false}, pane_state) do
      runner.destroy(runner_ref)
    else
      :ok
    end
  end

  defp call_worker(fun) do
    fun.()
  catch
    :exit, reason -> {:error, {:worker_unavailable, reason}}
  end
end
