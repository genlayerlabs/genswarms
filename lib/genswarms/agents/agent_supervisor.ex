defmodule Genswarms.Agents.AgentSupervisor do
  @moduledoc """
  DynamicSupervisor for agent processes.

  Provides functions to start, stop, and list agents within a swarm.
  Uses the application's DynamicSupervisor (Genswarms.AgentSupervisor)
  for actual supervision.
  """

  require Logger

  alias Genswarms.Agents.AgentServer

  @supervisor Genswarms.AgentSupervisor

  @doc """
  Starts an agent under the supervisor.
  """
  @spec start_agent(map()) :: {:ok, pid()} | {:error, term()}
  def start_agent(agent_config) do
    child_spec = {AgentServer, agent_config_to_opts(agent_config)}

    case DynamicSupervisor.start_child(@supervisor, child_spec) do
      {:ok, pid} ->
        Logger.info("Started agent #{agent_config[:name]} in swarm #{agent_config[:swarm_name]}")
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        Logger.warning("Agent #{agent_config[:name]} already started")
        {:ok, pid}

      {:error, reason} = error ->
        Logger.error("Failed to start agent #{agent_config[:name]}: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Stops an agent.
  """
  @spec stop_agent(String.t(), atom()) :: :ok | {:error, term()}
  def stop_agent(swarm_name, agent_name) do
    case find_agent_pid(swarm_name, agent_name) do
      {:ok, pid} ->
        with :ok <- shutdown_backend(swarm_name, agent_name),
             :ok <- DynamicSupervisor.terminate_child(@supervisor, pid) do
          :ok
        end

      :error ->
        {:error, :not_found}
    end
  end

  @doc """
  Restarts an agent.
  """
  @spec restart_agent(String.t(), atom(), map()) :: {:ok, pid()} | {:error, term()}
  def restart_agent(swarm_name, agent_name, config) do
    # Terminating the AgentServer invokes its disconnect callback. Persistent
    # backends (tmux) keep the external session; ordinary backends fall back to
    # stop/1. An explicit stop_agent still destroys persistent resources.
    terminate_result =
      case find_agent_pid(swarm_name, agent_name) do
        {:ok, pid} -> DynamicSupervisor.terminate_child(@supervisor, pid)
        :error -> :ok
      end

    case terminate_result do
      :ok -> start_agent(Map.put(config, :swarm_name, swarm_name))
      {:error, :not_found} -> start_agent(Map.put(config, :swarm_name, swarm_name))
      {:error, _} = error -> error
    end
  end

  @doc """
  Lists all agents for a swarm (excludes objects).
  """
  @spec list_agents(String.t()) :: [map()]
  def list_agents(swarm_name) do
    Registry.select(Genswarms.AgentRegistry, [
      {{{swarm_name, :"$1"}, :"$2", :_}, [], [{{:"$1", :"$2"}}]}
    ])
    |> Enum.map(fn {name, pid} ->
      status =
        try do
          AgentServer.get_status(swarm_name, name)
        catch
          _, _ -> %{state: :unknown}
        end

      # Filter out objects (they have type: :object in status)
      if Map.get(status, :type) == :object do
        nil
      else
        status
        |> Map.take([
          :backend,
          :inbox_size,
          :message_count,
          :started_at,
          :last_activity,
          :turn_id,
          :attention_reason,
          :session
        ])
        |> Map.merge(%{
          name: name,
          pid: inspect(pid),
          state: Map.get(status, :state, :unknown)
        })
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Stops all agents for a swarm.
  """
  @spec stop_all_agents(String.t()) :: :ok
  def stop_all_agents(swarm_name) do
    agents = list_agents(swarm_name)

    Enum.each(agents, fn %{name: name} ->
      stop_agent(swarm_name, name)
    end)

    :ok
  end

  @doc """
  Counts agents by state for a swarm.
  """
  @spec count_by_state(String.t()) :: %{atom() => non_neg_integer()}
  def count_by_state(swarm_name) do
    list_agents(swarm_name)
    |> Enum.group_by(& &1.state)
    |> Enum.map(fn {state, agents} -> {state, length(agents)} end)
    |> Map.new()
  end

  # Private functions

  defp agent_config_to_opts(config) do
    [
      name: config[:name],
      swarm_name: config[:swarm_name],
      backend: config[:backend],
      skills: config[:skills] || [],
      model: config[:model],
      endpoint: config[:endpoint],
      presets: config[:presets] || [],
      request_extra: config[:request_extra],
      compact_extra: config[:compact_extra],
      config: config[:config] || %{},
      connections: config[:connections] || []
    ]
  end

  defp find_agent_pid(swarm_name, agent_name) do
    case Registry.lookup(Genswarms.AgentRegistry, {swarm_name, agent_name}) do
      [{pid, _}] -> {:ok, pid}
      [] -> :error
    end
  end

  defp shutdown_backend(swarm_name, agent_name) do
    AgentServer.shutdown_backend(swarm_name, agent_name)
  catch
    :exit, _ -> :ok
  end
end
