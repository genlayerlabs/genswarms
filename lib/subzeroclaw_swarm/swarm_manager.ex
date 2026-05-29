defmodule SubzeroclawSwarm.SwarmManager do
  @moduledoc """
  GenServer for managing multiple swarms.

  Handles swarm lifecycle:
  - Starting swarms from configuration files
  - Stopping swarms
  - Tracking swarm status
  - Coordinating agent startup
  """

  use GenServer
  require Logger

  alias SubzeroclawSwarm.Agents.{AgentSupervisor, AgentServer}
  alias SubzeroclawSwarm.Observability.LogStore
  alias SubzeroclawSwarm.Config.{Loader, SwarmConfig}
  alias SubzeroclawSwarm.Objects.ObjectSupervisor
  alias SubzeroclawSwarm.Routing.Router

  defstruct swarms: %{}

  @type swarm_info :: %{
          config: SwarmConfig.t(),
          config_path: String.t() | nil,
          started_at: DateTime.t(),
          status: :starting | :running | :stopping | :stopped | :error
        }

  @type t :: %__MODULE__{
          swarms: %{String.t() => swarm_info()}
        }

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Starts a swarm from a configuration file.
  """
  @spec start_swarm(String.t()) :: {:ok, String.t()} | {:error, term()}
  def start_swarm(config_path) do
    GenServer.call(__MODULE__, {:start_swarm, config_path}, 60_000)
  end

  @doc """
  Starts a swarm from a configuration map.
  """
  @spec start_from_config(map()) :: {:ok, String.t()} | {:error, term()}
  def start_from_config(config) do
    GenServer.call(__MODULE__, {:start_from_config, config}, 60_000)
  end

  @doc """
  Stops a running swarm.
  """
  @spec stop(String.t()) :: :ok | {:error, term()}
  def stop(swarm_name) do
    GenServer.call(__MODULE__, {:stop, swarm_name})
  end

  @doc """
  Gets the status of a swarm.
  """
  @spec status(String.t()) :: {:ok, map()} | {:error, :not_found}
  def status(swarm_name) do
    GenServer.call(__MODULE__, {:status, swarm_name})
  end

  @doc """
  Lists all swarms.
  """
  @spec list() :: [map()]
  def list do
    GenServer.call(__MODULE__, :list)
  end

  @doc """
  Sends a task to an agent in a swarm.
  """
  @spec send_task(String.t(), atom() | String.t(), String.t()) :: :ok | {:error, term()}
  def send_task(swarm_name, agent_name, task) do
    agent_name = if is_binary(agent_name), do: String.to_atom(agent_name), else: agent_name
    AgentServer.send_task(swarm_name, agent_name, task)
  end

  @doc """
  Gets the topology of a swarm.
  """
  @spec get_topology(String.t()) :: {:ok, map()} | {:error, term()}
  def get_topology(swarm_name) do
    Router.get_topology(swarm_name)
  end

  @doc """
  Pauses a swarm (freezes all Docker containers).
  """
  @spec pause(String.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def pause(swarm_name) do
    GenServer.call(__MODULE__, {:pause, swarm_name})
  end

  @doc """
  Resumes a paused swarm.
  """
  @spec resume(String.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def resume(swarm_name) do
    GenServer.call(__MODULE__, {:resume, swarm_name})
  end

  @doc """
  Checks if a swarm is paused.
  """
  @spec paused?(String.t()) :: boolean()
  def paused?(swarm_name) do
    GenServer.call(__MODULE__, {:paused?, swarm_name})
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call({:start_swarm, config_path}, _from, state) do
    case Loader.load(config_path) do
      {:ok, config} ->
        do_start_swarm(config, config_path, state)

      {:error, reason} ->
        LogStore.log(
          :error,
          :swarm,
          :config_load_failed,
          "Failed to load config from #{config_path}: #{inspect(reason)}",
          metadata: %{config_path: config_path, reason: inspect(reason)}
        )

        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:start_from_config, config_map}, _from, state) do
    case SwarmConfig.parse(config_map) do
      {:ok, config} ->
        do_start_swarm(config, nil, state)

      {:error, reason} ->
        LogStore.log(
          :error,
          :swarm,
          :config_parse_failed,
          "Failed to parse swarm config: #{inspect(reason)}",
          metadata: %{reason: inspect(reason)}
        )

        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:stop, swarm_name}, _from, state) do
    case Map.get(state.swarms, swarm_name) do
      nil ->
        LogStore.log(:warning, :swarm, :not_found, "Cannot stop swarm '#{swarm_name}': not found",
          swarm: swarm_name
        )

        {:reply, {:error, :not_found}, state}

      swarm_info ->
        Logger.info("Stopping swarm #{swarm_name}")

        # Stop all agents and objects
        AgentSupervisor.stop_all_agents(swarm_name)
        ObjectSupervisor.stop_all_objects(swarm_name)

        # Unregister topology
        Router.unregister_topology(swarm_name)

        # Broadcast stop event
        Phoenix.PubSub.broadcast(
          SubzeroclawSwarm.PubSub,
          "swarm:#{swarm_name}",
          {:swarm_stopped, swarm_name}
        )

        emit_telemetry(:swarm_stopped, %{swarm: swarm_name})

        LogStore.log(:info, :swarm, :stopped, "Swarm #{swarm_name} stopped",
          swarm: swarm_name,
          metadata: %{
            agent_count: length(swarm_info.config.agents),
            object_count: length(swarm_info.config.objects || [])
          }
        )

        # Remove swarm from state entirely (allows clean restart)
        new_swarms = Map.delete(state.swarms, swarm_name)
        {:reply, {:ok, swarm_info.config_path}, %{state | swarms: new_swarms}}
    end
  end

  def handle_call({:status, swarm_name}, _from, state) do
    case Map.get(state.swarms, swarm_name) do
      nil ->
        {:reply, {:error, :not_found}, state}

      swarm_info ->
        agents = AgentSupervisor.list_agents(swarm_name)
        agent_counts = AgentSupervisor.count_by_state(swarm_name)
        objects = ObjectSupervisor.list_objects(swarm_name)

        status = %{
          name: swarm_name,
          status: swarm_info.status,
          started_at: swarm_info.started_at,
          config_path: Map.get(swarm_info, :config_path),
          agents: agents,
          objects: objects,
          agent_counts: agent_counts,
          config: %{
            agent_count: length(swarm_info.config.agents),
            object_count: length(swarm_info.config.objects || []),
            topology_edges: length(swarm_info.config.topology)
          }
        }

        {:reply, {:ok, status}, state}
    end
  end

  def handle_call(:list, _from, state) do
    swarms =
      Enum.map(state.swarms, fn {name, info} ->
        %{
          name: name,
          status: info.status,
          started_at: info.started_at,
          agent_count: length(info.config.agents),
          object_count: length(info.config.objects || [])
        }
      end)

    {:reply, swarms, state}
  end

  def handle_call({:pause, swarm_name}, _from, state) do
    case Map.get(state.swarms, swarm_name) do
      nil ->
        {:reply, {:error, :not_found}, state}

      _swarm_info ->
        case do_pause_containers(swarm_name) do
          {:ok, count} ->
            Logger.info("Paused #{count} containers for swarm #{swarm_name}")
            {:reply, {:ok, count}, state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  def handle_call({:resume, swarm_name}, _from, state) do
    case Map.get(state.swarms, swarm_name) do
      nil ->
        {:reply, {:error, :not_found}, state}

      _swarm_info ->
        case do_resume_containers(swarm_name) do
          {:ok, count} ->
            Logger.info("Resumed #{count} containers for swarm #{swarm_name}")
            {:reply, {:ok, count}, state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  def handle_call({:paused?, swarm_name}, _from, state) do
    case Map.get(state.swarms, swarm_name) do
      nil ->
        {:reply, false, state}

      _swarm_info ->
        {:reply, check_containers_paused(swarm_name), state}
    end
  end

  # Private functions

  defp do_start_swarm(config, config_path, state) do
    swarm_name = config.name

    if Map.has_key?(state.swarms, swarm_name) do
      LogStore.log(
        :error,
        :swarm,
        :already_running,
        "Cannot start swarm '#{swarm_name}': already running",
        swarm: swarm_name,
        metadata: %{config_path: config_path}
      )

      {:reply, {:error, :already_exists}, state}
    else
      object_count = length(config.objects || [])

      Logger.info(
        "Starting swarm #{swarm_name} with #{length(config.agents)} agents and #{object_count} objects"
      )

      swarm_info = %{
        config: config,
        config_path: config_path,
        started_at: DateTime.utc_now(),
        status: :starting
      }

      new_state = %{state | swarms: Map.put(state.swarms, swarm_name, swarm_info)}

      # Register topology
      Router.register_topology(swarm_name, config.topology)

      # Build adjacency map to get connections for each agent
      adjacency_map = SwarmConfig.build_adjacency_map(config.topology)

      # Start agents
      agent_results =
        Enum.map(config.agents, fn agent ->
          # Get connections for this agent from topology
          connections = Map.get(adjacency_map, agent.name, [])

          agent_config = %{
            name: agent.name,
            swarm_name: swarm_name,
            backend: agent.backend,
            skills: Map.get(agent, :skills, []),
            model: Map.get(agent, :model),
            endpoint: Map.get(agent, :endpoint),
            presets: Map.get(agent, :presets, []),
            config: Map.get(agent, :config, %{}),
            connections: connections
          }

          AgentSupervisor.start_agent(agent_config)
        end)

      # Start objects
      object_results =
        Enum.map(config.objects || [], fn object ->
          object_config = %{
            name: object.name,
            swarm_name: swarm_name,
            handler: Map.get(object, :handler),
            backend: Map.get(object, :backend),
            config: Map.get(object, :config, %{})
          }

          ObjectSupervisor.start_object(object_config)
        end)

      # Check if all agents and objects started successfully
      all_results = agent_results ++ object_results
      errors = Enum.filter(all_results, &match?({:error, _}, &1))

      final_status = if Enum.empty?(errors), do: :running, else: :error

      updated_info = %{swarm_info | status: final_status}
      final_state = %{new_state | swarms: Map.put(new_state.swarms, swarm_name, updated_info)}

      # Broadcast start event
      Phoenix.PubSub.broadcast(
        SubzeroclawSwarm.PubSub,
        "swarm:#{swarm_name}",
        {:swarm_started, swarm_name, final_status}
      )

      emit_telemetry(:swarm_started, %{
        swarm: swarm_name,
        agent_count: length(config.agents),
        object_count: object_count,
        status: final_status
      })

      if Enum.empty?(errors) do
        LogStore.log(:info, :swarm, :started, "Swarm #{swarm_name} started successfully",
          swarm: swarm_name,
          metadata: %{agent_count: length(config.agents), object_count: object_count}
        )

        {:reply, {:ok, swarm_name}, final_state}
      else
        error_details = Enum.map(errors, fn {:error, reason} -> inspect(reason) end)

        LogStore.log(:error, :swarm, :partial_start, "Swarm #{swarm_name} started with errors",
          swarm: swarm_name,
          metadata: %{
            agent_count: length(config.agents),
            object_count: object_count,
            error_count: length(errors),
            errors: error_details
          }
        )

        {:reply, {:error, {:partial_start, errors}}, final_state}
      end
    end
  end

  defp emit_telemetry(event, metadata) do
    :telemetry.execute(
      [:subzeroclaw_swarm, :swarm, event],
      %{time: System.system_time()},
      metadata
    )
  end

  defp do_pause_containers(swarm_name) do
    prefix = "szc-#{swarm_name}-"

    case System.cmd("docker", ["ps", "--filter", "name=#{prefix}", "--format", "{{.Names}}"],
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        containers =
          output
          |> String.split("\n", trim: true)
          |> Enum.filter(&String.starts_with?(&1, prefix))

        if containers == [] do
          {:ok, 0}
        else
          results =
            Enum.map(containers, fn container ->
              case System.cmd("docker", ["pause", container], stderr_to_stdout: true) do
                {_, 0} -> :ok
                _ -> :error
              end
            end)

          {:ok, Enum.count(results, &(&1 == :ok))}
        end

      {err, _} ->
        {:error, err}
    end
  end

  defp do_resume_containers(swarm_name) do
    prefix = "szc-#{swarm_name}-"

    case System.cmd(
           "docker",
           [
             "ps",
             "--filter",
             "name=#{prefix}",
             "--filter",
             "status=paused",
             "--format",
             "{{.Names}}"
           ],
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        containers =
          output
          |> String.split("\n", trim: true)
          |> Enum.filter(&String.starts_with?(&1, prefix))

        if containers == [] do
          {:ok, 0}
        else
          results =
            Enum.map(containers, fn container ->
              case System.cmd("docker", ["unpause", container], stderr_to_stdout: true) do
                {_, 0} -> :ok
                _ -> :error
              end
            end)

          {:ok, Enum.count(results, &(&1 == :ok))}
        end

      {err, _} ->
        {:error, err}
    end
  end

  defp check_containers_paused(swarm_name) do
    prefix = "szc-#{swarm_name}-"

    case System.cmd(
           "docker",
           [
             "ps",
             "--filter",
             "name=#{prefix}",
             "--filter",
             "status=paused",
             "--format",
             "{{.Names}}"
           ],
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        containers =
          output
          |> String.split("\n", trim: true)
          |> Enum.filter(&String.starts_with?(&1, prefix))

        length(containers) > 0

      _ ->
        false
    end
  end
end
