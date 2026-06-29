defmodule Genswarms.Backends.AppleContainerBackend do
  @moduledoc """
  Apple `container` backend implementation.

  Runs agents with Apple's OCI-compatible `container` CLI on macOS hosts. The
  backend uses argv lists for every host command; configured names, paths, env
  values, images, and commands are never joined into a host shell string.
  """

  @behaviour Genswarms.Backends.BackendBehaviour

  require Logger

  alias Genswarms.Backends.EndpointPolicy
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

  @preset_images %{
    [:base] => "szc-agent-base:latest",
    [:base, :web] => "szc-agent-web:latest",
    [:base, :code] => "szc-agent-code:latest",
    [:base, :data] => "szc-agent-data:latest",
    [:base, :python] => "szc-agent-python:latest",
    [:base, :node] => "szc-agent-node:latest",
    [:base, :code, :data, :node, :python, :web] => "szc-agent-full:latest",
    [:base, :cloud, :code, :containers] => "szc-agent-devops:latest"
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
      base_args = ["run", "-i", "--rm", "--name", to_string(container_name)]
      env_args = build_env_args(api_key, model, endpoint, agent_name, config)
      volume_args = build_volume_args(skills_dir, config)
      resource_args = build_resource_args(config)
      container_cmd = normalize_container_cmd(Map.get(config, :cmd), config)

      {:ok,
       base_args ++
         env_args ++
         volume_args ++ network_args ++ resource_args ++ [to_string(image)] ++ container_cmd}
    end
  end

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
  def determine_image(config) do
    cond do
      Map.has_key?(config, :image) ->
        config.image

      Map.has_key?(config, :container_name) ->
        config.container_name

      Map.has_key?(config, :container) ->
        config.container

      Map.has_key?(config, :presets) ->
        presets = Enum.sort(config.presets)
        Map.get(@preset_images, presets, "szc-agent-base:latest")

      true ->
        "szc-agent-base:latest"
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
    preset_name = preset_to_build_name(presets)

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
                  "Built #{image}, but Apple container image load failed (#{code}): #{output}"
                )
            end

          {output, code} ->
            Logger.warning("Failed to build Apple container image #{image} (#{code}): #{output}")
        end
    end
  end

  defp preset_to_build_name([:base]), do: "base"
  defp preset_to_build_name([:base, :web]), do: "web"
  defp preset_to_build_name([:base, :code]), do: "code"
  defp preset_to_build_name([:base, :data]), do: "data"
  defp preset_to_build_name([:base, :python]), do: "python"
  defp preset_to_build_name([:base, :node]), do: "node"
  defp preset_to_build_name([:base, :code, :containers, :cloud]), do: "devops"
  defp preset_to_build_name(_), do: "full"

  defp get_project_root do
    Application.get_env(:genswarms, :project_root, ".")
  end

  defp default_container_cmd(config) do
    budget =
      case Map.get(config, :max_turns) do
        n when is_integer(n) and n > 0 ->
          " && echo \"max_turns = #{n}\" >> /root/.subzeroclaw/config"

        nil ->
          ""

        bad ->
          Logger.warning("apple_container: ignoring non-integer max_turns #{inspect(bad)}")

          ""
      end

    [
      "sh",
      "-c",
      "export HOME=/root && mkdir -p /root/.subzeroclaw /root/build && echo \"skills_dir = /skills\" > /root/.subzeroclaw/config#{budget} && cp -r /src/subzeroclaw/* /root/build/ && cd /root/build && make -s 2>/dev/null && exec ./subzeroclaw"
    ]
  end

  defp normalize_container_cmd(nil, config), do: default_container_cmd(config)
  defp normalize_container_cmd(cmd, _config) when is_list(cmd), do: Enum.map(cmd, &to_string/1)
  defp normalize_container_cmd(cmd, _config) when is_binary(cmd), do: ["sh", "-c", cmd]

  defp config_json(config, key) do
    case Map.get(config, key) do
      nil -> nil
      v when is_binary(v) -> v
      v when is_map(v) -> Jason.encode!(v)
      _ -> nil
    end
  end

  defp build_env_args(api_key, model, endpoint, agent_name, config) do
    envs = [{"--env", "SUBZEROCLAW_AGENT_NAME=#{agent_name}"}]
    envs = if api_key, do: envs ++ [{"--env", "SUBZEROCLAW_API_KEY=#{api_key}"}], else: envs

    request_extra =
      config_json(config, :request_extra) || (model && Jason.encode!(%{"model" => model}))

    envs =
      if request_extra,
        do: envs ++ [{"--env", "SUBZEROCLAW_REQUEST_EXTRA=#{request_extra}"}],
        else: envs

    compact_extra = config_json(config, :compact_extra)

    envs =
      if compact_extra,
        do: envs ++ [{"--env", "SUBZEROCLAW_COMPACT_EXTRA=#{compact_extra}"}],
        else: envs

    envs = if endpoint, do: envs ++ [{"--env", "SUBZEROCLAW_ENDPOINT=#{endpoint}"}], else: envs

    additional_envs =
      Map.get(config, :env, %{})
      |> Enum.map(fn {k, v} -> {k, expand_env_var(v)} end)
      |> Enum.filter(fn {_k, v} -> v != nil and v != "" end)
      |> Enum.map(fn {k, v} -> {"--env", "#{k}=#{v}"} end)

    Enum.flat_map(envs ++ additional_envs, fn {flag, val} -> [flag, val] end)
  end

  defp expand_env_var(value) when is_binary(value) do
    Regex.replace(~r/\$\{([A-Z_][A-Z0-9_]*)\}/, value, fn _, var_name ->
      System.get_env(var_name) || ""
    end)
    |> then(fn v ->
      Regex.replace(~r/\$([A-Z_][A-Z0-9_]*)/, v, fn _, var_name ->
        System.get_env(var_name) || ""
      end)
    end)
  end

  defp expand_env_var(value), do: value

  defp build_volume_args(skills_dir, config) do
    volumes = []

    volumes =
      if skills_dir do
        expanded = Path.expand(skills_dir)
        volumes ++ readonly_mount(expanded, "/skills")
      else
        volumes
      end

    volumes =
      if skills_dir do
        logs_dir = skills_dir |> Path.dirname() |> Path.join("logs")
        File.mkdir_p!(logs_dir)
        volumes ++ ["--volume", "#{logs_dir}:/root/.subzeroclaw/logs"]
      else
        volumes
      end

    additional_vols = Map.get(config, :volumes, [])

    has_workspace_mount =
      Enum.any?(additional_vols, fn {_, container} ->
        container == "/workspace" or String.starts_with?(container, "/workspace")
      end)

    volumes =
      if not has_workspace_mount do
        workspace = Map.get(config, :workspace, "/tmp/szc-workspace")
        File.mkdir_p!(Path.expand(workspace))
        volumes ++ ["--volume", "#{workspace}:/workspace"]
      else
        volumes
      end

    volumes = volumes ++ ["--volume", "/tmp:/tmp"]

    subzeroclaw_src =
      Map.get(config, :subzeroclaw_src) ||
        Application.get_env(:genswarms, :subzeroclaw_src) ||
        find_subzeroclaw_source()

    volumes =
      if subzeroclaw_src && File.dir?(subzeroclaw_src) do
        volumes ++ readonly_mount(subzeroclaw_src, "/src/subzeroclaw")
      else
        Logger.warning("subzeroclaw source not found at #{inspect(subzeroclaw_src)}")
        volumes
      end

    additional_volumes =
      additional_vols
      |> Enum.flat_map(fn {host, container} ->
        ["--volume", "#{Path.expand(host)}:#{container}"]
      end)

    volumes ++ additional_volumes
  end

  defp readonly_mount(host, container) do
    ["--mount", "type=bind,source=#{Path.expand(host)},target=#{container},readonly"]
  end

  defp find_subzeroclaw_source do
    [
      Path.expand("../subzeroclaw", File.cwd!()),
      Path.expand("../../subzeroclaw", File.cwd!()),
      System.get_env("SUBZEROCLAW_SRC"),
      Path.expand("~/docs/personal/subzeroclaw")
    ]
    |> Enum.filter(&(&1 != nil))
    |> Enum.find(fn path ->
      File.dir?(path) && File.exists?(Path.join(path, "Makefile"))
    end)
  end

  defp build_network_args(%{network: :isolated}), do: {:error, {:unsupported_network, :isolated}}
  defp build_network_args(%{network: "isolated"}), do: {:error, {:unsupported_network, :isolated}}
  defp build_network_args(%{network: nil}), do: {:ok, []}
  defp build_network_args(%{network: :open}), do: {:ok, []}
  defp build_network_args(%{network: network}), do: {:ok, ["--network", to_string(network)]}
  defp build_network_args(_), do: {:ok, []}

  defp build_resource_args(config) do
    args = []

    args =
      case Map.get(config, :memory_limit) do
        nil -> args
        limit -> args ++ ["--memory", to_string(limit)]
      end

    case Map.get(config, :cpu_limit) do
      nil -> args
      limit -> args ++ ["--cpus", to_string(limit)]
    end
  end

  defp stop_container(container_name) do
    container_cmd(["stop", container_name])
    delete_container(container_name)
    :ok
  end

  defp delete_container(container_name) do
    container_cmd(["delete", "--force", container_name])
    :ok
  end

  defp container_cmd(args) do
    case System.find_executable("container") do
      nil -> {"container executable not found", 127}
      exe -> System.cmd(exe, args, stderr_to_stdout: true)
    end
  end

  defp container_executable do
    System.find_executable("container") || "container"
  end
end
