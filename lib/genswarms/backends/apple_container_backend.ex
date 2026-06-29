defmodule Genswarms.Backends.AppleContainerBackend do
  @moduledoc """
  Apple `container` backend implementation.

  Runs agents with Apple's OCI-compatible `container` CLI on macOS hosts. The
  backend uses argv lists for every host command; configured names, paths, env
  values, images, and commands are never joined into a host shell string.

  Argv building, env/volume/resource args, the in-container bootstrap and image
  selection are shared with the Docker backend via
  `Genswarms.Backends.OciCli`; this module keeps only what is specific to
  Apple's `container` CLI: failing closed on unsupported isolated networking,
  the OCI image load path, and the container lifecycle/inspect commands.
  """

  @behaviour Genswarms.Backends.BackendBehaviour

  require Logger

  alias Genswarms.Backends.{EndpointPolicy, OciCli}
  alias Genswarms.Observability.LogStore

  defstruct [:port, :container_name, :name, :skills_dir, :image, :buffer]

  @type t :: %__MODULE__{
          port: port() | nil,
          container_name: String.t(),
          name: String.t(),
          skills_dir: String.t() | nil,
          image: String.t(),
          buffer: binary()
        }

  @impl true
  def backend_type, do: :apple_container

  @impl true
  def start(name, config) do
    swarm_name = Map.get(config, :swarm_name, "default")
    container_name = Map.get(config, :container_name) || "szc-#{swarm_name}-#{name}"
    skills_dir = Map.get(config, :skills_dir)
    image = determine_image(config)
    {endpoint, api_key} = EndpointPolicy.resolve(config)
    model = Map.get(config, :model)

    with :ok <- validate_network(config),
         :ok <- ensure_system_ready(),
         :ok <- cleanup_existing_container(container_name, swarm_name, name),
         :ok <- ensure_image_exists(image, config),
         {:ok, args} <-
           build_apple_container_args(
             container_name,
             image,
             skills_dir,
             api_key,
             model,
             endpoint,
             name,
             config
           ) do
      container_bin = container_executable()

      Logger.info("Starting Apple container for agent #{name}: #{container_name} (#{image})")

      port_opts = [
        :binary,
        :exit_status,
        {:line, 16_384},
        :use_stdio,
        :stderr_to_stdout
      ]

      try do
        port = Port.open({:spawn_executable, container_bin}, [{:args, args} | port_opts])

        ref = %__MODULE__{
          port: port,
          container_name: container_name,
          name: name,
          skills_dir: skills_dir,
          image: image,
          buffer: ""
        }

        LogStore.log(
          :info,
          :backend,
          :apple_container_start,
          "Started container #{container_name}",
          swarm: swarm_name,
          agent: String.to_atom(name),
          metadata: %{image: image, container: container_name}
        )

        {:ok, ref}
      rescue
        e ->
          stop_container(container_name)

          LogStore.log(
            :error,
            :backend,
            :apple_container_start_failed,
            "Failed to start Apple container: #{inspect(e)}",
            swarm: swarm_name,
            agent: String.to_atom(name),
            metadata: %{image: image, container: container_name, error: inspect(e)}
          )

          {:error, {:start_failed, e}}
      end
    else
      {:error, reason} ->
        LogStore.log(
          :error,
          :backend,
          :apple_container_start_failed,
          "Failed to start Apple container: #{inspect(reason)}",
          swarm: swarm_name,
          agent: String.to_atom(name),
          metadata: %{image: image, container: container_name, reason: inspect(reason)}
        )

        {:error, reason}
    end
  end

  @impl true
  def stop(%__MODULE__{
        port: port,
        container_name: container_name,
        name: name
      }) do
    Logger.info("Stopping Apple container #{container_name} for agent #{name}")

    container_logs =
      case container_cmd(["logs", "-n", "50", container_name]) do
        {output, 0} -> output
        _ -> nil
      end

    if port do
      try do
        Port.close(port)
      rescue
        _ -> :ok
      end
    end

    stop_container(container_name)

    LogStore.log(:info, :backend, :apple_container_stop, "Stopped container #{container_name}",
      agent: String.to_atom(name),
      metadata: %{container: container_name, last_logs: container_logs}
    )

    :ok
  end

  @impl true
  def send_input(%__MODULE__{port: port}, message) when is_binary(message) do
    data = if String.ends_with?(message, "\n"), do: message, else: message <> "\n"

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
    {:ok, %{ref | skills_dir: skills_dir}}
  end

  @impl true
  def health_check(%__MODULE__{container_name: container_name}) do
    case inspect_container(container_name) do
      {:ok, %{"status" => "running"}} -> :ok
      {:ok, %{"state" => "running"}} -> :ok
      {:ok, _} -> {:error, :container_not_running}
      {:error, _} -> {:error, :container_not_running}
    end
  end

  @doc false
  def system_ready? do
    case container_cmd(["system", "status", "--format", "json"]) do
      {_output, 0} -> true
      _ -> false
    end
  end

  @doc false
  def image_exists?(image) when is_binary(image) do
    case container_cmd(["image", "inspect", image]) do
      {_output, 0} -> true
      _ -> false
    end
  end

  @doc false
  def build_apple_container_args(
        container_name,
        image,
        skills_dir,
        api_key,
        model,
        endpoint,
        agent_name,
        config
      ) do
    with {:ok, network_args} <- build_network_args(config) do
      base_args = ["run", "--progress", "none", "-i", "--rm", "--name", to_string(container_name)]
      env_args = OciCli.build_env_args(api_key, model, endpoint, agent_name, config, "--env")
      volume_args = OciCli.build_volume_args(skills_dir, config, &ro_mount/2, &rw_mount/2)
      # Apple `container` supports only --memory / --cpus (no memory-swap/pids-limit).
      resource_args =
        OciCli.build_resource_args(config, [{:memory_limit, "--memory"}, {:cpu_limit, "--cpus"}])

      container_cmd =
        OciCli.normalize_container_cmd(
          Map.get(config, :cmd),
          agent_name,
          config,
          "apple_container"
        )

      {:ok,
       base_args ++
         env_args ++
         volume_args ++ network_args ++ resource_args ++ [to_string(image)] ++ container_cmd}
    end
  end

  # Apple `container` uses `--mount type=bind` for read-only binds and
  # `--volume` for read-write ones (vs Docker's single `-v ...:ro` syntax).
  defp ro_mount(host, container),
    do: ["--mount", "type=bind,source=#{host},target=#{container},readonly"]

  defp rw_mount(host, container), do: ["--volume", "#{host}:#{container}"]

  defp validate_network(config) do
    case build_network_args(config) do
      {:ok, _} -> :ok
      {:error, _} = err -> err
    end
  end

  defp ensure_system_ready do
    if system_ready?(), do: :ok, else: {:error, :apple_container_not_ready}
  end

  defp cleanup_existing_container(container_name, swarm_name, name) do
    case check_container_state(container_name) do
      :not_found ->
        :ok

      {:running, status} ->
        LogStore.log(
          :warning,
          :backend,
          :apple_container_already_running,
          "Container #{container_name} already running, removing it",
          swarm: swarm_name,
          agent: String.to_atom(name),
          metadata: %{container: container_name, status: status}
        )

        stop_container(container_name)
        :ok

      {:other, status} ->
        LogStore.log(
          :info,
          :backend,
          :apple_container_cleanup,
          "Cleaning up Apple container #{container_name} (status: #{status})",
          swarm: swarm_name,
          agent: String.to_atom(name),
          metadata: %{container: container_name, status: status}
        )

        delete_container(container_name)
        :ok
    end
  end

  defp check_container_state(container_name) do
    case inspect_container(container_name) do
      {:ok, map} ->
        status = Map.get(map, "status") || Map.get(map, "state") || "unknown"

        case status do
          "running" -> {:running, status}
          other -> {:other, other}
        end

      {:error, _} ->
        :not_found
    end
  end

  defp inspect_container(container_name) do
    case container_cmd(["inspect", container_name]) do
      {output, 0} ->
        decode_first_json_object(output)

      {output, _} ->
        {:error, output}
    end
  end

  defp decode_first_json_object(output) do
    case Jason.decode(output) do
      {:ok, [first | _]} when is_map(first) -> {:ok, first}
      {:ok, %{} = map} -> {:ok, map}
      {:ok, _} -> {:error, :unexpected_inspect_json}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc false
  # Image selection is shared, with Apple's extra `:container_name`-as-image
  # fallback layered on top.
  def determine_image(config) do
    cond do
      Map.has_key?(config, :image) -> config.image
      Map.has_key?(config, :container_name) -> config.container_name
      true -> OciCli.determine_image(config)
    end
  end

  defp ensure_image_exists(image, config) do
    if image_exists?(image) do
      :ok
    else
      Logger.info("Apple container image #{image} not found locally, attempting to build/load...")
      build_image(image, config)
      :ok
    end
  end

  defp build_image(image, config) do
    presets = Map.get(config, :presets, [:base])
    preset_name = OciCli.preset_to_build_name(presets)

    case System.find_executable("nix") do
      nil ->
        Logger.warning("Cannot build Apple container image #{image}: nix executable not found")

      nix ->
        case System.cmd(nix, ["build", ".#agentContainer-#{preset_name}", "-o", "result"],
               stderr_to_stdout: true,
               cd: get_project_root()
             ) do
          {_, 0} ->
            case container_cmd(["image", "load", "--input", "result"]) do
              {_, 0} ->
                Logger.info("Built and loaded Apple container image: #{image}")

              {output, code} ->
                Logger.warning(
                  "Built #{image}, but Apple container image load failed (#{code}). " <>
                    "Nix agentContainer outputs are Docker archives; convert/preload an OCI archive " <>
                    "for Apple container. Output: #{output}"
                )
            end

          {output, code} ->
            Logger.warning("Failed to build Apple container image #{image} (#{code}): #{output}")
        end
    end
  end

  defp get_project_root do
    Application.get_env(:genswarms, :project_root, ".")
  end

  # Apple `container` does not support isolated networking; fail closed rather
  # than silently running with full network access.
  defp build_network_args(%{network: :isolated}), do: {:error, {:unsupported_network, :isolated}}
  defp build_network_args(%{network: "isolated"}), do: {:error, {:unsupported_network, :isolated}}
  defp build_network_args(%{network: nil}), do: {:ok, []}
  defp build_network_args(%{network: :open}), do: {:ok, []}
  defp build_network_args(%{network: network}), do: {:ok, ["--network", to_string(network)]}
  defp build_network_args(_), do: {:ok, []}

  defp stop_container(container_name) do
    container_cmd(["stop", container_name])
    delete_container(container_name)
    :ok
  end

  defp delete_container(container_name) do
    container_cmd(["delete", "--force", container_name])
    :ok
  end

  defp container_cmd(args), do: OciCli.cmd("container", args)

  defp container_executable do
    System.find_executable("container") || "container"
  end
end
