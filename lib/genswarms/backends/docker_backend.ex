defmodule Genswarms.Backends.DockerBackend do
  @moduledoc """
  Docker backend implementation using NixOS-based containers.

  Runs subzeroclaw agents in Docker containers built with Nix.
  Each agent can have specific tools/presets defined in their config.

  ## Container Images

  Images are built from the flake using `nix build`:

      nix build .#agentContainer-base   # Minimal agent
      nix build .#agentContainer-web    # Web/HTTP tools
      nix build .#agentContainer-code   # Development tools
      nix build .#agentContainer-full   # All tools

  ## Usage in Swarm Config

      %{
        name: :researcher,
        backend: {:docker, "researcher"},
        presets: [:base, :web],        # NixOS tool presets
        tools: [:jq, :curl],           # Individual tools
        skills: ["web.md"]
      }

  The orchestrator will select or build the appropriate NixOS container.

  Argv building, env/volume/resource args, the in-container bootstrap and
  image selection are shared with the Apple `container` backend via
  `Genswarms.Backends.OciCli`; this module keeps only what is Docker-specific
  (the egress guard + `--network none`, `docker load`, and the container
  lifecycle/inspect commands).
  """

  @behaviour Genswarms.Backends.BackendBehaviour

  require Logger
  alias Genswarms.Backends.{EgressGuard, OciCli}
  alias Genswarms.Observability.LogStore

  defstruct [:port, :container_name, :container_id, :name, :skills_dir, :image, :egress, :buffer]

  @type t :: %__MODULE__{
          port: port() | nil,
          container_name: String.t(),
          container_id: String.t() | nil,
          name: String.t(),
          skills_dir: String.t() | nil,
          image: String.t(),
          egress: EgressGuard.t() | nil,
          buffer: binary()
        }

  @impl true
  def backend_type, do: :docker

  @impl true
  def start(name, config) do
    swarm_name = Map.get(config, :swarm_name, "default")
    container_name = Map.get(config, :container) || "szc-#{swarm_name}-#{name}"
    skills_dir = Map.get(config, :skills_dir)
    # EndpointPolicy withholds the server-env API key from an untrusted/custom
    # endpoint (SSRF key-exfil guard, finding 28).
    {endpoint, api_key} = Genswarms.Backends.EndpointPolicy.resolve(config)
    # Model comes from the agent config only. No SUBZEROCLAW_MODEL env fallback:
    # it is the dead var, and it would clobber a SUBZEROCLAW_REQUEST_EXTRA routing
    # policy with a bare {"model": ...}.
    model = Map.get(config, :model)

    # Check if container already exists
    case check_container_state(container_name) do
      :not_found ->
        # Good, proceed with start
        :ok

      {:running, _} ->
        LogStore.log(
          :warning,
          :backend,
          :container_already_running,
          "Container #{container_name} already running, removing it",
          swarm: swarm_name,
          agent: String.to_atom(name),
          metadata: %{container: container_name}
        )

        System.cmd("docker", ["rm", "-f", container_name], stderr_to_stdout: true)

      {:paused, _} ->
        LogStore.log(
          :warning,
          :backend,
          :container_paused,
          "Container #{container_name} was paused, removing it",
          swarm: swarm_name,
          agent: String.to_atom(name),
          metadata: %{container: container_name}
        )

        System.cmd("docker", ["rm", "-f", container_name], stderr_to_stdout: true)

      {:exited, exit_code} ->
        LogStore.log(
          :info,
          :backend,
          :container_cleanup,
          "Cleaning up exited container #{container_name} (exit code: #{exit_code})",
          swarm: swarm_name,
          agent: String.to_atom(name),
          metadata: %{container: container_name, exit_code: exit_code}
        )

        System.cmd("docker", ["rm", "-f", container_name], stderr_to_stdout: true)

      {:other, status} ->
        LogStore.log(
          :warning,
          :backend,
          :container_unexpected_state,
          "Container #{container_name} in unexpected state: #{status}, removing it",
          swarm: swarm_name,
          agent: String.to_atom(name),
          metadata: %{container: container_name, status: status}
        )

        System.cmd("docker", ["rm", "-f", container_name], stderr_to_stdout: true)
    end

    # Determine the image based on presets/tools or explicit image
    image = OciCli.determine_image(config)

    # Ensure image exists (build if needed)
    ensure_image_exists(image, config)

    # Network isolation (network: :isolated): give the agent a per-container
    # workspace (the default workspace is shared, which would collide sockets),
    # then start the egress sidecar before `docker run` so the socket/.curlrc
    # exist when the agent first calls the LLM.
    isolated = EgressGuard.isolated?(config)

    config =
      if isolated do
        ws = Map.get(config, :workspace) || Path.join("/tmp/szc-workspace", container_name)
        File.mkdir_p!(ws)
        Map.put(config, :workspace, ws)
      else
        config
      end

    egress_result =
      if isolated do
        # socat runs in a sidecar container (VM-side) sharing a docker volume with
        # the --network none agent — a host-side socket can't be reached from a
        # sibling container on Docker Desktop.
        EgressGuard.start_docker_sidecar(container_name, Map.fetch!(config, :workspace), config)
      else
        {:ok, nil}
      end

    with {:ok, egress} <- egress_result do
      # Build docker run argv (list, not a shell string)
      args =
        build_docker_args(
          container_name,
          image,
          skills_dir,
          api_key,
          model,
          endpoint,
          name,
          config
        )

      docker_bin = System.find_executable("docker") || "docker"

      Logger.info(
        "Starting NixOS Docker container for agent #{name}: #{container_name} (#{image})"
      )

      port_opts = [
        :binary,
        :exit_status,
        {:line, 16_384},
        :use_stdio,
        :stderr_to_stdout
      ]

      try do
        # spawn_executable + argv (no /bin/sh): container name, image, env values,
        # volumes, and the container command cannot be shell-injected on the host.
        port = Port.open({:spawn_executable, docker_bin}, [{:args, args} | port_opts])

        ref = %__MODULE__{
          port: port,
          container_name: container_name,
          name: name,
          skills_dir: skills_dir,
          image: image,
          egress: egress,
          buffer: ""
        }

        Logger.info("Started NixOS container #{container_name} (#{image}) for agent #{name}")

        LogStore.log(:info, :backend, :docker_start, "Started container #{container_name}",
          swarm: swarm_name,
          agent: String.to_atom(name),
          metadata: %{image: image, container: container_name}
        )

        {:ok, ref}
      rescue
        e ->
          EgressGuard.stop_forwarder(egress)
          Logger.error("Failed to start Docker container for agent #{name}: #{inspect(e)}")

          LogStore.log(
            :error,
            :backend,
            :docker_start_failed,
            "Failed to start container: #{inspect(e)}",
            swarm: swarm_name,
            agent: String.to_atom(name),
            metadata: %{image: image, container: container_name, error: inspect(e)}
          )

          {:error, {:start_failed, e}}
      end
    else
      {:error, reason} ->
        # Egress sidecar failed (e.g. endpoint not allowlisted): do not run an
        # "isolated" container that would actually have no network.
        Logger.error("Egress forwarder failed for agent #{name}: #{inspect(reason)}")

        LogStore.log(
          :error,
          :backend,
          :docker_egress_failed,
          "Failed to start egress forwarder: #{inspect(reason)}",
          swarm: swarm_name,
          agent: String.to_atom(name),
          metadata: %{container: container_name, reason: inspect(reason)}
        )

        {:error, {:egress_failed, reason}}
    end
  end

  @impl true
  def stop(%__MODULE__{
        port: port,
        container_name: container_name,
        egress: egress,
        name: name
      }) do
    Logger.info("Stopping Docker container #{container_name} for agent #{name}")

    # Capture container logs before stopping
    container_logs =
      case System.cmd("docker", ["logs", "--tail", "50", container_name], stderr_to_stdout: true) do
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

    # Stop the egress forwarder (isolated agents) and remove its socket
    EgressGuard.stop_forwarder(egress)

    System.cmd("docker", ["stop", container_name], stderr_to_stdout: true)
    System.cmd("docker", ["rm", "-f", container_name], stderr_to_stdout: true)

    LogStore.log(:info, :backend, :docker_stop, "Stopped container #{container_name}",
      agent: String.to_atom(name),
      metadata: %{container: container_name, last_logs: container_logs}
    )

    :ok
  end

  @impl true
  def send_input(%__MODULE__{port: port}, message) when is_binary(message) do
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
    {:ok, %{ref | skills_dir: skills_dir}}
  end

  @impl true
  def health_check(%__MODULE__{container_name: container_name}) do
    case System.cmd("docker", ["inspect", "-f", "{{.State.Running}}", container_name],
           stderr_to_stdout: true
         ) do
      {"true\n", 0} -> :ok
      {_, _} -> {:error, :container_not_running}
    end
  end

  # Private functions

  # Check if a container exists and its state
  defp check_container_state(container_name) do
    case System.cmd(
           "docker",
           ["inspect", "-f", "{{.State.Status}}:{{.State.ExitCode}}", container_name],
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        output = String.trim(output)

        case String.split(output, ":") do
          ["running", _] -> {:running, output}
          ["paused", _] -> {:paused, output}
          ["exited", code] -> {:exited, code}
          ["created", _] -> {:other, "created"}
          [status, _] -> {:other, status}
          _ -> {:other, output}
        end

      {_, _} ->
        :not_found
    end
  end

  @doc false
  # Image selection is shared; kept as a thin delegate for the public test API.
  def determine_image(config), do: OciCli.determine_image(config)

  defp ensure_image_exists(image, config) do
    # Check if image exists locally
    case System.cmd("docker", ["image", "inspect", image], stderr_to_stdout: true) do
      {_, 0} ->
        :ok

      {_, _} ->
        # Image doesn't exist, try to build it
        Logger.info("Image #{image} not found, attempting to build...")

        LogStore.log(:info, :backend, :image_build_start, "Building image #{image}",
          metadata: %{image: image, presets: Map.get(config, :presets, [:base])}
        )

        build_image(image, config)
    end
  end

  defp build_image(image, config) do
    presets = Map.get(config, :presets, [:base])
    preset_name = OciCli.preset_to_build_name(presets)

    # Try to build using nix
    case System.cmd("nix", ["build", ".#agentContainer-#{preset_name}", "-o", "result"],
           stderr_to_stdout: true,
           cd: get_project_root()
         ) do
      {_, 0} ->
        # Load the built image into Docker
        System.cmd("docker", ["load", "-i", "result"], stderr_to_stdout: true)
        Logger.info("Built and loaded image: #{image}")

        LogStore.log(:info, :backend, :image_build_success, "Built and loaded image #{image}",
          metadata: %{image: image, preset: preset_name}
        )

        :ok

      {output, code} ->
        Logger.warning("Failed to build image #{image}: #{output}")
        Logger.warning("Using fallback base image")

        LogStore.log(
          :warning,
          :backend,
          :image_build_failed,
          "Failed to build image #{image}, using fallback",
          metadata: %{
            image: image,
            preset: preset_name,
            exit_code: code,
            output: String.slice(output, 0, 500)
          }
        )

        :ok
    end
  end

  defp get_project_root do
    Application.get_env(:genswarms, :project_root, ".")
  end

  @doc false
  # Exposed for tests: builds the `docker run` argv list. Pure given its inputs.
  def build_docker_args(
        container_name,
        image,
        skills_dir,
        api_key,
        model,
        endpoint,
        agent_name,
        config
      ) do
    base_args = ["run", "-i", "--rm", "--name", to_string(container_name)]

    env_args =
      OciCli.build_env_args(
        api_key,
        model,
        endpoint,
        agent_name,
        config,
        "-e",
        docker_extra_env(config)
      )

    volume_args = OciCli.build_volume_args(skills_dir, config, &ro_mount/2, &rw_mount/2)
    network_args = build_network_args(config)
    resource_args = OciCli.build_resource_args(config)

    container_cmd =
      OciCli.normalize_container_cmd(Map.get(config, :cmd), agent_name, config, "docker")

    # Isolation: mount the shared egress volume so the agent reaches the sidecar
    # socat over /egress/llm.sock (its only path out, since --network none).
    egress_args =
      if EgressGuard.isolated?(config),
        do: EgressGuard.docker_agent_volume_args(container_name),
        else: []

    base_args ++
      env_args ++
      volume_args ++
      egress_args ++ network_args ++ resource_args ++ [to_string(image)] ++ container_cmd
  end

  # Docker-specific env vars layered on the shared base, inserted after the
  # endpoint var: the isolation curl redirect and the topology list.
  defp docker_extra_env(config) do
    curl =
      if EgressGuard.isolated?(config), do: [{"CURL_HOME", "/workspace"}], else: []

    topology =
      case Map.get(config, :connections, []) do
        [] ->
          []

        connections ->
          [{"SWARM_TOPOLOGY", connections |> Enum.map(&to_string/1) |> Enum.join(",")}]
      end

    curl ++ topology
  end

  defp ro_mount(host, container), do: ["-v", "#{host}:#{container}:ro"]
  defp rw_mount(host, container), do: ["-v", "#{host}:#{container}"]

  defp build_network_args(config) do
    cond do
      # Isolation: no network at all. Egress is the bind-mounted LLM socket only.
      EgressGuard.isolated?(config) ->
        ["--network", "none"]

      true ->
        case Map.get(config, :network) do
          nil -> []
          network -> ["--network", to_string(network)]
        end
    end
  end
end
