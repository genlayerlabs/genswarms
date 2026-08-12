defmodule Genswarms.Backends.Tmux.Runner do
  @moduledoc """
  Isolation boundary used underneath the host tmux transport.

  A runner translates a client launch into the command that belongs in the
  pane. Host keeps the client command unchanged, Docker wraps it in
  `docker exec -it`, and bwrap wraps it in a per-agent sandbox. The tmux server
  remains host-side so operators always have one stable attach surface.
  """

  @type launch :: Genswarms.Backends.Tmux.Adapter.launch()
  @type pane_state :: :missing | %{required(:dead?) => boolean(), optional(atom()) => term()}

  @callback configure(map()) :: {:ok, map()} | {:error, term()}
  @callback prepare(map(), launch(), pane_state()) ::
              {:ok, term(), launch()} | {:error, term()}
  @callback destroy(term()) :: :ok | {:error, term()}
  @callback health_check(term()) :: :ok | {:error, term()}
  @callback session_info(term()) :: map()
end

defmodule Genswarms.Backends.Tmux.Runners do
  @moduledoc false

  alias Genswarms.Backends.Tmux.Runners.{Bwrap, Docker, Host}

  @known %{
    host: Host,
    docker: Docker,
    bwrap: Bwrap
  }

  @spec resolve(atom() | String.t() | nil) :: {:ok, module()} | {:error, term()}
  def resolve(nil), do: {:ok, Host}

  def resolve(value) when is_binary(value) do
    case value do
      "host" -> {:ok, Host}
      "docker" -> {:ok, Docker}
      "bwrap" -> {:ok, Bwrap}
      _ -> {:error, {:unsupported_tmux_runner, value}}
    end
  end

  def resolve(value) when is_atom(value) do
    case Map.fetch(@known, value) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, {:unsupported_tmux_runner, value}}
    end
  end

  def resolve(value), do: {:error, {:unsupported_tmux_runner, value}}

  @spec known?(term()) :: boolean()
  def known?(value) when is_binary(value), do: value in ~w(host docker bwrap)
  def known?(value) when is_atom(value), do: Map.has_key?(@known, value)
  def known?(_value), do: false
end

defmodule Genswarms.Backends.Tmux.RunnerCommand do
  @moduledoc false

  @callback run(String.t(), [String.t()]) :: {String.t(), non_neg_integer()}
end

defmodule Genswarms.Backends.Tmux.RunnerSystemCommand do
  @moduledoc false

  @behaviour Genswarms.Backends.Tmux.RunnerCommand

  @impl true
  def run(executable, args) do
    System.cmd(executable, args, stderr_to_stdout: true)
  rescue
    error -> {Exception.message(error), 127}
  end
end

defmodule Genswarms.Backends.Tmux.RunnerHelpers do
  @moduledoc false

  alias Genswarms.Backends.Tmux.RunnerSystemCommand

  @identifier ~r/\A[a-zA-Z][a-zA-Z0-9_.-]*\z/
  @env_name ~r/\A[A-Z_][A-Z0-9_]*\z/

  def run(config, executable, args) when is_binary(executable) and is_list(args) do
    runner = Map.get(config, :runner_command_runner, RunnerSystemCommand)

    case runner.run(executable, args) do
      {output, status} when is_binary(output) and is_integer(status) -> {output, status}
      other -> {"invalid runner result: #{inspect(other)}", 127}
    end
  end

  def resolve_host_executable(config, key, default) do
    configured = Map.get(config, key, default)

    cond do
      not is_binary(configured) or configured == "" or String.contains?(configured, <<0>>) ->
        {:error, {:invalid_executable, configured}}

      Path.type(configured) == :absolute and File.regular?(configured) ->
        {:ok, configured}

      path = System.find_executable(configured) ->
        {:ok, path}

      true ->
        {:error, {:executable_not_found, configured}}
    end
  end

  def runtime_executable(config, default) do
    configured = Map.get(config, :executable, default)

    if is_binary(configured) and configured != "" and not String.contains?(configured, <<0>>),
      do: {:ok, configured},
      else: {:error, {:invalid_executable, configured}}
  end

  def private_dir(path) when is_binary(path) do
    with :ok <- File.mkdir_p(path),
         :ok <- File.chmod(path, 0o700) do
      :ok
    end
  end

  def validate_identifier(value) when is_binary(value) do
    if Regex.match?(@identifier, value), do: :ok, else: {:error, {:invalid_identifier, value}}
  end

  def validate_identifier(value), do: {:error, {:invalid_identifier, value}}

  def validate_mount_path(path) when is_binary(path) do
    cond do
      path == "" or String.contains?(path, [<<0>>, ","]) -> {:error, {:invalid_mount_path, path}}
      Path.type(path) != :absolute -> {:error, {:mount_path_not_absolute, path}}
      true -> :ok
    end
  end

  def validate_mount_path(path), do: {:error, {:invalid_mount_path, path}}

  def normalize_source(value, default) do
    case value || default do
      source when source in [:runtime, "runtime"] -> {:ok, :runtime}
      source when source in [:host_nix, "host_nix", "host-nix"] -> {:ok, :host_nix}
      other -> {:error, {:unsupported_client_source, other}}
    end
  end

  def pass_env(config) do
    names = Map.get(config, :pass_env, [])

    cond do
      not is_list(names) ->
        {:error, {:invalid_pass_env, names}}

      invalid = Enum.find(names, &(not is_binary(&1) or not Regex.match?(@env_name, &1))) ->
        {:error, {:invalid_env_name, invalid}}

      true ->
        {:ok, Enum.uniq(names)}
    end
  end

  def validate_pass_env_values(config) do
    with {:ok, names} <- pass_env(config) do
      case Enum.find(names, &is_nil(System.get_env(&1))) do
        nil -> :ok
        missing -> {:error, {:missing_pass_env, missing}}
      end
    end
  end

  def runner_env(config) do
    env = Map.get(config, :runner_env, %{})

    if is_map(env) do
      Enum.reduce_while(env, {:ok, []}, fn {key, value}, {:ok, acc} ->
        normalized_key =
          if is_binary(key) or is_atom(key),
            do: to_string(key),
            else: nil

        if is_binary(normalized_key) and Regex.match?(@env_name, normalized_key) and
             is_binary(value) and
             not String.contains?(value, <<0>>) do
          {:cont, {:ok, [{normalized_key, value} | acc]}}
        else
          {:halt, {:error, {:invalid_runner_env, normalized_key || key}}}
        end
      end)
      |> case do
        {:ok, pairs} -> {:ok, Enum.reverse(pairs)}
        error -> error
      end
    else
      {:error, {:invalid_runner_env, env}}
    end
  end

  def default_state_dir(config) do
    Path.join([
      System.tmp_dir!(),
      "genswarms-tmux-state",
      to_string(Map.fetch!(config, :swarm_name)),
      to_string(Map.fetch!(config, :agent_name)),
      to_string(Map.fetch!(config, :client))
    ])
  end

  def normalize_network(config) do
    case Map.get(config, :network, :open) do
      value when value in [:open, "open", nil] ->
        {:ok, :open}

      value when value in [:none, "none"] ->
        {:ok, :none}

      value when value in [:isolated, "isolated"] ->
        {:error, :tui_egress_isolation_unsupported}

      value when is_binary(value) and value != "" ->
        if String.contains?(value, <<0>>),
          do: {:error, {:invalid_network, value}},
          else: {:ok, value}

      other ->
        {:error, {:invalid_network, other}}
    end
  end

  def extra_binds(config) do
    with {:ok, ro} <- validate_binds(Map.get(config, :extra_ro_binds, [])),
         {:ok, rw} <- validate_binds(Map.get(config, :extra_rw_binds, [])) do
      {:ok, ro, rw}
    end
  end

  defp validate_binds(binds) when is_list(binds) do
    Enum.reduce_while(binds, {:ok, []}, fn
      {host, runtime}, {:ok, acc} when is_binary(host) and is_binary(runtime) ->
        host = Path.expand(host)

        with :ok <- validate_mount_path(host),
             :ok <- validate_mount_path(runtime),
             true <- File.exists?(host) or {:error, {:mount_source_not_found, host}} do
          {:cont, {:ok, [{host, runtime} | acc]}}
        else
          {:error, _} = error -> {:halt, error}
        end

      invalid, _acc ->
        {:halt, {:error, {:invalid_bind, invalid}}}
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  defp validate_binds(other), do: {:error, {:invalid_binds, other}}
end

defmodule Genswarms.Backends.Tmux.RunnerStore do
  @moduledoc false

  alias Genswarms.Backends.Bwrap.StoreClosure
  alias Genswarms.Backends.Tmux.RunnerHelpers

  @store_path ~r|\A/nix/store/[a-z0-9]{32}-[^/]+\z|

  def resolve_host_launch(config, %{executable: executable} = launch) do
    with {:ok, resolved} <- real_path(executable),
         true <-
           String.starts_with?(resolved, "/nix/store/") or
             {:error, {:host_client_not_in_nix_store, resolved}},
         {:ok, paths} <- closure(config, StoreClosure.store_root(resolved)) do
      {:ok, %{launch | executable: resolved}, paths}
    end
  end

  def closure(config, store_root) do
    case Map.get(config, :client_store_paths) do
      paths when is_list(paths) and paths != [] ->
        validate_store_paths(paths)

      nil ->
        query_closure(config, store_root)

      other ->
        {:error, {:invalid_client_store_paths, other}}
    end
  end

  def query_closure(config, store_root) do
    with {:ok, nix_store} <-
           RunnerHelpers.resolve_host_executable(config, :nix_store_executable, "nix-store") do
      case RunnerHelpers.run(config, nix_store, ["--query", "--requisites", store_root]) do
        {output, 0} -> StoreClosure.parse_requisites(output)
        {output, status} -> {:error, {:nix_store_failed, status, String.slice(output, 0, 300)}}
      end
    end
  end

  def valid_store_path?(path) when is_binary(path) do
    not String.contains?(path, <<0>>) and Regex.match?(@store_path, path) and File.exists?(path)
  end

  def valid_store_path?(_path), do: false

  defp validate_store_paths(paths) do
    if Enum.all?(paths, &valid_store_path?/1),
      do: {:ok, Enum.uniq(paths)},
      else: {:error, {:invalid_client_store_paths, paths}}
  end

  defp real_path(path) when is_binary(path) do
    case :file.read_link_all(String.to_charlist(path)) do
      {:ok, resolved} -> {:ok, List.to_string(resolved)}
      {:error, reason} -> {:error, {:client_realpath_failed, reason}}
    end
  end

  defp real_path(path), do: {:error, {:invalid_client_executable, path}}
end
