defmodule Genswarms.Backends.Tmux.Runners.Docker do
  @moduledoc false

  @behaviour Genswarms.Backends.Tmux.Runner

  alias Genswarms.Backends.OciCli
  alias Genswarms.Backends.Tmux.{RunnerHelpers, RunnerStore}

  @owner_label "io.genswarms.tmux"

  defstruct [
    :config,
    :docker,
    :container_name,
    :image,
    :workspace,
    :state_dir,
    :client,
    :network,
    :client_source,
    :fingerprint,
    :expected_env,
    created?: false
  ]

  @impl true
  def configure(config) do
    with {:ok, source} <-
           RunnerHelpers.normalize_source(Map.get(config, :client_source), :runtime),
         {:ok, network} <- RunnerHelpers.normalize_network(config) do
      state_dir =
        Path.expand(Map.get(config, :state_dir) || RunnerHelpers.default_state_dir(config))

      {:ok,
       config
       |> Map.put(:runner_kind, :docker)
       |> Map.put(:client_source, source)
       |> Map.put(:runner_network, network)
       |> Map.put(:state_dir, state_dir)
       |> Map.put(:runtime_workspace, "/workspace")
       |> Map.put(:runtime_skills_dir, "/skills")
       |> Map.put(:runtime_home, "/root")
       |> Map.put(:executable_scope, if(source == :runtime, do: :runtime, else: :host))}
    end
  end

  @impl true
  def prepare(config, launch, pane_state) do
    with {:ok, docker} <-
           RunnerHelpers.resolve_host_executable(config, :docker_executable, "docker"),
         {:ok, image} <- image(config),
         {:ok, container_name} <- container_name(config),
         :ok <- prepare_directories(config),
         {:ok, launch, store_paths} <- prepare_client(config, launch),
         {:ok, expected_env} <- container_env(config),
         fingerprint = container_fingerprint(config, store_paths),
         {:ok, status} <- inspect_container(config, docker, container_name),
         {:ok, created?} <-
           ensure_container(
             config,
             docker,
             container_name,
             image,
             store_paths,
             fingerprint,
             expected_env,
             status,
             pane_state
           ) do
      ref = %__MODULE__{
        config: config,
        docker: docker,
        container_name: container_name,
        image: image,
        workspace: config.workspace,
        state_dir: config.state_dir,
        client: config.client,
        network: config.runner_network,
        client_source: config.client_source,
        fingerprint: fingerprint,
        expected_env: expected_env,
        created?: created?
      }

      {:ok, ref, exec_launch(ref, launch)}
    end
  end

  @impl true
  def destroy(%__MODULE__{} = ref) do
    case RunnerHelpers.run(ref.config, ref.docker, ["rm", "-f", ref.container_name]) do
      {_output, 0} ->
        :ok

      {output, status} ->
        if missing_container?(output),
          do: :ok,
          else: {:error, {:docker_destroy_failed, status, String.trim(output)}}
    end
  end

  @impl true
  def health_check(%__MODULE__{} = ref) do
    case inspect_container(ref.config, ref.docker, ref.container_name) do
      {:ok, %{running?: true} = info} ->
        with :ok <- verify_owned(info, ref.config, ref.image, ref.fingerprint),
             :ok <- verify_environment(info, ref.expected_env) do
          :ok
        end

      {:ok, :not_found} ->
        {:error, :container_not_found}

      {:ok, _info} ->
        {:error, :container_not_running}

      {:error, _} = error ->
        error
    end
  end

  @impl true
  def session_info(%__MODULE__{} = ref) do
    %{
      kind: :docker,
      filesystem_isolation: true,
      process_isolation: true,
      network: ref.network,
      container: ref.container_name,
      image: ref.image,
      client_source: ref.client_source,
      workspace: ref.workspace,
      state_dir: ref.state_dir
    }
  end

  @doc false
  def create_args(config, container_name, image, store_paths) do
    {:ok, expected_env} = container_env(config)
    create_args(config, container_name, image, store_paths, expected_env)
  end

  defp create_args(config, container_name, image, store_paths, expected_env) do
    labels = ownership_labels(config, image, container_fingerprint(config, store_paths))

    base =
      ["run", "-d", "--name", container_name, "--init"] ++
        Enum.flat_map(labels, fn {key, value} -> ["--label", "#{key}=#{value}"] end) ++
        ["--workdir", "/workspace"] ++
        mount_args(config, store_paths) ++
        network_args(config.runner_network) ++
        OciCli.build_resource_args(config) ++
        env_file_args(config, expected_env)

    keepalive = Map.get(config, :keepalive_command, ["sleep", "infinity"])
    base ++ [image] ++ keepalive
  end

  @doc false
  def exec_launch(%__MODULE__{} = ref, launch) do
    args =
      ["exec", "-i", "-t", "--workdir", "/workspace"] ++
        launch_env_args(launch) ++
        [ref.container_name, launch.executable | launch.args]

    %{executable: ref.docker, args: args, env: []}
  end

  defp image(config) do
    value = Map.get(config, :image) || OciCli.determine_image(config)

    if is_binary(value) and value != "" and not String.starts_with?(value, "-") and
         not String.contains?(value, <<0>>),
       do: {:ok, value},
       else: {:error, {:invalid_docker_image, value}}
  end

  defp container_name(config) do
    value =
      Map.get(config, :container_name) ||
        "gstui-#{config.swarm_name}-#{config.agent_name}"

    with :ok <- RunnerHelpers.validate_identifier(value), do: {:ok, value}
  end

  defp prepare_directories(config) do
    with :ok <- File.mkdir_p(config.workspace),
         :ok <- RunnerHelpers.private_dir(config.state_dir),
         :ok <- RunnerHelpers.validate_mount_path(config.workspace),
         :ok <- RunnerHelpers.validate_mount_path(config.state_dir),
         :ok <- maybe_validate_skills(config),
         :ok <- validate_keepalive(config),
         :ok <- RunnerHelpers.validate_pass_env_values(config),
         {:ok, _pairs} <- RunnerHelpers.runner_env(config),
         {:ok, _ro, _rw} <- RunnerHelpers.extra_binds(config) do
      :ok
    end
  end

  defp maybe_validate_skills(%{skills_dir: path}) when is_binary(path) do
    with true <- File.dir?(path) or {:error, {:skills_dir_not_found, path}},
         :ok <- RunnerHelpers.validate_mount_path(Path.expand(path)) do
      :ok
    end
  end

  defp maybe_validate_skills(_config), do: :ok

  defp validate_keepalive(config) do
    value = Map.get(config, :keepalive_command, ["sleep", "infinity"])

    if is_list(value) and value != [] and Enum.all?(value, &is_binary/1),
      do: :ok,
      else: {:error, {:invalid_keepalive_command, value}}
  end

  defp prepare_client(%{client_source: :runtime}, launch), do: {:ok, launch, []}

  defp prepare_client(%{client_source: :host_nix} = config, launch) do
    RunnerStore.resolve_host_launch(config, launch)
  end

  defp ensure_container(
         config,
         docker,
         name,
         image,
         store_paths,
         _fingerprint,
         expected_env,
         :not_found,
         pane_state
       ) do
    if live_pane?(pane_state) do
      {:error, {:runner_state_mismatch, :live_pane_without_container}}
    else
      with {:ok, env_file} <- write_env_file(config, expected_env) do
        args = create_args(config, name, image, store_paths, expected_env)

        try do
          case RunnerHelpers.run(config, docker, args) do
            {_output, 0} -> {:ok, true}
            {output, status} -> {:error, {:docker_start_failed, status, String.trim(output)}}
          end
        after
          remove_env_file(env_file)
        end
      end
    end
  end

  defp ensure_container(
         config,
         docker,
         name,
         image,
         _store_paths,
         fingerprint,
         expected_env,
         info,
         pane_state
       ) do
    with :ok <- verify_owned(info, config, image, fingerprint),
         :ok <- verify_environment(info, expected_env) do
      cond do
        info.running? ->
          {:ok, false}

        live_pane?(pane_state) ->
          {:error, {:runner_state_mismatch, :live_pane_with_stopped_container}}

        true ->
          case RunnerHelpers.run(config, docker, ["start", name]) do
            {_output, 0} -> {:ok, false}
            {output, status} -> {:error, {:docker_start_failed, status, String.trim(output)}}
          end
      end
    end
  end

  defp inspect_container(config, docker, name) do
    case RunnerHelpers.run(config, docker, ["inspect", name]) do
      {output, 0} ->
        parse_inspect(output)

      {output, _status} ->
        if missing_container?(output),
          do: {:ok, :not_found},
          else: {:error, {:docker_inspect_failed, String.trim(output)}}
    end
  end

  defp parse_inspect(output) do
    with {:ok, [entry | _]} <- Jason.decode(output),
         state when is_map(state) <- Map.get(entry, "State", %{}),
         config when is_map(config) <- Map.get(entry, "Config", %{}) do
      {:ok,
       %{
         running?: Map.get(state, "Running") == true,
         labels: Map.get(config, "Labels") || %{},
         image: Map.get(config, "Image"),
         env: parse_container_env(Map.get(config, "Env") || [])
       }}
    else
      _ -> {:error, :invalid_docker_inspect}
    end
  end

  defp verify_owned(%{labels: labels}, config, image, fingerprint) when is_map(labels) do
    expected = ownership_labels(config, image, fingerprint)

    case Enum.find(expected, fn {key, value} -> Map.get(labels, key) != value end) do
      nil -> :ok
      {key, _value} -> {:error, {:container_identity_mismatch, key}}
    end
  end

  defp verify_owned(_info, _config, _image, _fingerprint),
    do: {:error, :container_identity_mismatch}

  defp ownership_labels(config, image, fingerprint) do
    %{
      @owner_label => "1",
      "io.genswarms.swarm" => to_string(config.swarm_name),
      "io.genswarms.agent" => to_string(config.agent_name),
      "io.genswarms.client" => to_string(config.client),
      "io.genswarms.image" => image,
      "io.genswarms.config-sha256" => fingerprint
    }
  end

  defp verify_environment(%{env: actual}, expected) when is_map(actual) do
    case Enum.find(expected, fn {key, value} -> Map.get(actual, key) != value end) do
      nil -> :ok
      {key, _value} -> {:error, {:container_environment_mismatch, key}}
    end
  end

  defp verify_environment(_info, _expected), do: {:error, :container_environment_mismatch}

  defp container_env(config) do
    with {:ok, names} <- RunnerHelpers.pass_env(config),
         {:ok, configured} <- RunnerHelpers.runner_env(config) do
      passed = Enum.map(names, &{&1, System.fetch_env!(&1)})
      env = Map.new(passed ++ configured)

      if Enum.all?(env, fn {_key, value} ->
           not String.contains?(value, ["\n", "\r", <<0>>])
         end),
         do: {:ok, env},
         else: {:error, :docker_env_file_multiline_value}
    end
  end

  defp parse_container_env(values) when is_list(values) do
    Enum.reduce(values, %{}, fn value, acc ->
      case String.split(value, "=", parts: 2) do
        [key, env_value] -> Map.put(acc, key, env_value)
        _ -> acc
      end
    end)
  end

  defp parse_container_env(_values), do: %{}

  defp container_fingerprint(config, store_paths) do
    {:ok, pass_env} = RunnerHelpers.pass_env(config)
    {:ok, runner_env} = RunnerHelpers.runner_env(config)

    contract = %{
      mounts: mount_args(config, store_paths),
      network: network_args(config.runner_network),
      resources: OciCli.build_resource_args(config),
      pass_env: Enum.sort(pass_env),
      runner_env: runner_env |> Enum.map(&elem(&1, 0)) |> Enum.sort(),
      keepalive: Map.get(config, :keepalive_command, ["sleep", "infinity"]),
      client_source: config.client_source
    }

    :sha256
    |> :crypto.hash(:erlang.term_to_binary(contract, [:deterministic]))
    |> Base.encode16(case: :lower)
  end

  defp mount_args(config, store_paths) do
    core = [
      {config.workspace, "/workspace", false},
      {config.state_dir, "/root", false}
    ]

    core =
      case Map.get(config, :skills_dir) do
        path when is_binary(path) -> core ++ [{Path.expand(path), "/skills", true}]
        _ -> core
      end

    {:ok, ro, rw} = RunnerHelpers.extra_binds(config)

    binds =
      core ++
        Enum.map(ro, fn {host, runtime} -> {host, runtime, true} end) ++
        Enum.map(rw, fn {host, runtime} -> {host, runtime, false} end) ++
        Enum.map(store_paths, fn path -> {path, path, true} end)

    Enum.flat_map(binds, fn {host, runtime, readonly?} ->
      spec = "type=bind,src=#{host},dst=#{runtime}" <> if(readonly?, do: ",readonly", else: "")
      ["--mount", spec]
    end)
  end

  defp network_args(:open), do: []
  defp network_args(:none), do: ["--network", "none"]
  defp network_args(network) when is_binary(network), do: ["--network", network]

  defp env_file_args(_config, expected_env) when map_size(expected_env) == 0, do: []

  defp env_file_args(config, _expected_env) do
    ["--env-file", env_file_path(config)]
  end

  defp write_env_file(_config, expected_env) when map_size(expected_env) == 0,
    do: {:ok, nil}

  defp write_env_file(config, expected_env) do
    path = env_file_path(config)

    body =
      expected_env
      |> Enum.sort()
      |> Enum.map_join("", fn {key, value} -> "#{key}=#{value}\n" end)

    result =
      with :ok <- File.write(path, body, [:binary]),
           :ok <- File.chmod(path, 0o600) do
        :ok
      end

    case result do
      :ok ->
        {:ok, path}

      {:error, _} = error ->
        _ = File.rm(path)
        error
    end
  end

  defp remove_env_file(nil), do: :ok
  defp remove_env_file(path), do: File.rm(path)

  defp env_file_path(config), do: Path.join(config.state_dir, ".genswarms-container.env")

  defp launch_env_args(%{env: env}) when is_list(env) do
    Enum.flat_map(env, fn
      {key, value} when is_binary(key) and is_binary(value) -> ["--env", "#{key}=#{value}"]
      _ -> []
    end)
  end

  defp launch_env_args(_launch), do: []

  defp live_pane?(%{dead?: false}), do: true
  defp live_pane?(_pane_state), do: false

  defp missing_container?(output) do
    String.contains?(String.downcase(output), ["no such object", "no such container"])
  end
end
