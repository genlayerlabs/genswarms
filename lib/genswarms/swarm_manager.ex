defmodule Genswarms.SwarmManager do
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

  alias Genswarms.Agents.{AgentSupervisor, AgentServer}
  alias Genswarms.Observability.LogStore
  alias Genswarms.Config.{Loader, SwarmConfig}
  alias Genswarms.Objects.ObjectSupervisor
  alias Genswarms.Routing.Router

  defstruct swarms: %{}, starts: %{}

  @type swarm_info :: %{
          config: SwarmConfig.t(),
          config_path: String.t() | nil,
          started_at: DateTime.t(),
          status: :starting | :running | :stopping | :stopped | :error
        }

  @type t :: %__MODULE__{
          swarms: %{String.t() => swarm_info()},
          starts: map()
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

  @doc "Starts from a native desired IR document, persisting its immutable seed before boot."
  def start_from_ir(document),
    do: GenServer.call(__MODULE__, {:start_from_ir, document}, 60_000)

  @doc "Restores a stored IR seed and its overlays without the original config file."
  def restore_swarm(name), do: GenServer.call(__MODULE__, {:restore_swarm, name}, 60_000)

  @doc """
  Stops a running swarm.
  """
  @spec stop(String.t()) :: {:ok, String.t() | nil} | {:error, term()}
  def stop(swarm_name) do
    # Supervisor shutdown may itself allow five seconds for a blocked child.
    GenServer.call(__MODULE__, {:stop, swarm_name}, 60_000)
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

  @doc """
  Adds an agent to a running swarm at runtime.

  ## Spec

  Same shape as an entry in the `agents:` list of the swarm config:
  `%{name: :foo, backend: :bwrap, skills: [...], ...}`

  ## Options

  - `connections: [atom]` — add edges `agent → x` for each x
  - `incoming: [atom]`    — add edges `x → agent`
  - `persist: boolean`    — persist to overlay log (default false)
  """
  @spec add_agent(String.t(), map(), keyword()) ::
          {:ok, atom()} | {:error, term()}
  def add_agent(swarm_name, agent_spec, opts \\ []) do
    GenServer.call(__MODULE__, {:add_agent, swarm_name, agent_spec, opts}, 60_000)
  end

  @doc """
  Removes an agent from a running swarm.
  """
  @spec remove_agent(String.t(), atom() | String.t(), keyword()) ::
          :ok | {:error, term()}
  def remove_agent(swarm_name, agent_name, opts \\ []) do
    GenServer.call(__MODULE__, {:remove_agent, swarm_name, normalize_name(agent_name), opts})
  end

  @doc """
  Adds an object to a running swarm at runtime.
  """
  @spec add_object(String.t(), map(), keyword()) ::
          {:ok, atom()} | {:error, term()}
  def add_object(swarm_name, object_spec, opts \\ []) do
    GenServer.call(__MODULE__, {:add_object, swarm_name, object_spec, opts}, 60_000)
  end

  @doc """
  Removes an object from a running swarm.
  """
  @spec remove_object(String.t(), atom() | String.t(), keyword()) ::
          :ok | {:error, term()}
  def remove_object(swarm_name, object_name, opts \\ []) do
    GenServer.call(__MODULE__, {:remove_object, swarm_name, normalize_name(object_name), opts})
  end

  @doc """
  Updates a running object's config: merges `config_patch` over the declared
  config and restarts the object with the merged map (the IR `update_config`
  actuation — an object's config is `init/1` input, so a restart is the only
  deterministic apply). Topology edges touching the object are preserved.
  With `persist: true` the patch is recorded as an `:update_config` overlay
  event and re-applied on boot.

  Mutability gating (config_schema x-mutable) is the CALLER's job — this is
  the mechanism, `Genswarms.Objects.ConfigSchema.validate_patch/2` is the
  gate the HTTP surface applies.
  """
  @spec update_object_config(String.t(), atom() | String.t(), map(), keyword()) ::
          {:ok, atom()} | {:error, term()}
  def update_object_config(swarm_name, object_name, config_patch, opts \\ []) do
    GenServer.call(
      __MODULE__,
      {:update_object_config, swarm_name, normalize_name(object_name), config_patch, opts},
      60_000
    )
  end

  @doc """
  Adds topology edges to a running swarm.
  """
  @spec add_topology_edges(String.t(), [{atom(), atom()}], keyword()) ::
          :ok | {:error, term()}
  def add_topology_edges(swarm_name, edges, opts \\ []) do
    GenServer.call(__MODULE__, {:add_topology_edges, swarm_name, edges, opts})
  end

  @doc """
  Removes topology edges from a running swarm.
  """
  @spec remove_topology_edges(String.t(), [{atom(), atom()}], keyword()) ::
          :ok | {:error, term()}
  def remove_topology_edges(swarm_name, edges, opts \\ []) do
    GenServer.call(__MODULE__, {:remove_topology_edges, swarm_name, edges, opts})
  end

  @doc """
  Scales an agent group to a target count. The group is identified by
  `base_name` and matches agents named `base_name`, `base_name_1`,
  `base_name_2`, etc.

  Uses an existing agent's spec as the template for new agents.
  Returns partial success: agents that fail to start are reported in
  `:failed` rather than rolling back the whole operation.
  """
  @spec scale_agent_group(String.t(), atom() | String.t(), pos_integer(), keyword()) ::
          {:ok, %{added: [atom()], removed: [atom()], failed: [{atom(), term()}]}}
          | {:error, term()}
  def scale_agent_group(swarm_name, base_name, target_count, opts \\ [])
      when is_integer(target_count) and target_count >= 0 do
    GenServer.call(
      __MODULE__,
      {:scale_agent_group, swarm_name, normalize_name(base_name), target_count, opts},
      120_000
    )
  end

  defp normalize_name(name) when is_atom(name), do: name
  defp normalize_name(name) when is_binary(name), do: String.to_atom(name)

  @doc """
  Returns the effective in-memory SwarmConfig for a swarm (seed ⊕ overlay).
  """
  @spec get_full_config(String.t()) :: {:ok, map()} | {:error, :swarm_not_found}
  def get_full_config(swarm_name) do
    GenServer.call(__MODULE__, {:get_full_config, swarm_name})
  end

  @doc "Restarts one agent from its complete effective configuration."
  @spec restart_agent(String.t(), atom() | String.t()) :: {:ok, pid()} | {:error, term()}
  def restart_agent(swarm_name, agent_name) do
    GenServer.call(__MODULE__, {:restart_agent, swarm_name, agent_name}, 30_000)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call({:start_swarm, config_path}, from, state) do
    case Loader.load(config_path) do
      {:ok, config} ->
        do_start_swarm(config, config_path, state, from)

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

  def handle_call({:start_from_config, config_map}, from, state) do
    case SwarmConfig.parse(config_map) do
      {:ok, config} ->
        do_start_swarm(config, nil, state, from)

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

  def handle_call({:start_from_ir, document}, from, state) do
    case Genswarms.IR.State.parse(document) do
      {:ok, ir} -> start_ir(ir, from, state)
      {:error, _} -> {:reply, {:error, :invalid_ir_seed}, state}
    end
  end

  def handle_call({:restore_swarm, name}, from, state) do
    case Genswarms.CLI.SwarmRegistry.load_ir_seed(name) do
      {:ok, ir} -> start_ir(ir, from, state)
      error -> {:reply, error, state}
    end
  end

  def handle_call({:stop, swarm_name}, _from, %{starts: starts} = state)
      when is_map_key(starts, swarm_name) do
    config_path = state.swarms[swarm_name].config_path
    state = finish_start(swarm_name, {:error, :start_cancelled}, state)
    {:reply, {:ok, config_path}, state}
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
          Genswarms.PubSub,
          "swarm:#{swarm_name}",
          {:swarm_stopped, swarm_name}
        )

        emit_telemetry(:swarm_stopped, %{
          swarm: swarm_name,
          agent_count: length(swarm_info.config.agents),
          object_count: length(swarm_info.config.objects || [])
        })

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
        # A status request must not synchronously wait on an init callback;
        # that callback may itself be waiting for this manager.
        {agents, agent_counts, objects} =
          if swarm_info.status == :starting do
            {[], %{}, []}
          else
            {AgentSupervisor.list_agents(swarm_name), AgentSupervisor.count_by_state(swarm_name),
             ObjectSupervisor.list_objects(swarm_name)}
          end

        status = %{
          name: swarm_name,
          status: swarm_info.status,
          runtime_pending: swarm_info.status == :starting,
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

  def handle_call({:add_agent, swarm_name, spec, opts}, _from, state) do
    case Map.get(state.swarms, swarm_name) do
      nil ->
        {:reply, {:error, :swarm_not_found}, state}

      swarm_info ->
        with :ok <- Genswarms.IR.Gate.validate_add_agent(swarm_info.config, spec),
             {:ok, name, new_info} <- do_add_agent(swarm_name, swarm_info, spec, opts) do
          new_state = put_swarm(state, swarm_name, new_info)

          saved =
            maybe_persist(opts, swarm_name, :add_agent, normalize_spec_for_overlay(spec, opts))

          broadcast_topology_changed(swarm_name)
          mutation_reply(saved, {:ok, name}, new_state)
        else
          {:error, _} = err -> {:reply, err, state}
        end
    end
  end

  def handle_call({:remove_agent, swarm_name, agent_name, opts}, _from, state) do
    case Map.get(state.swarms, swarm_name) do
      nil ->
        {:reply, {:error, :swarm_not_found}, state}

      swarm_info ->
        case do_remove_agent(swarm_name, swarm_info, agent_name) do
          {:ok, new_info} ->
            new_state = put_swarm(state, swarm_name, new_info)
            saved = maybe_persist(opts, swarm_name, :remove_agent, %{name: agent_name})
            broadcast_topology_changed(swarm_name)
            mutation_reply(saved, :ok, new_state)

          {:error, _} = err ->
            {:reply, err, state}
        end
    end
  end

  def handle_call({:add_object, swarm_name, spec, opts}, _from, state) do
    case Map.get(state.swarms, swarm_name) do
      nil ->
        {:reply, {:error, :swarm_not_found}, state}

      swarm_info ->
        case do_add_object(swarm_name, swarm_info, spec, opts) do
          {:ok, name, new_info} ->
            new_state = put_swarm(state, swarm_name, new_info)

            saved =
              maybe_persist(opts, swarm_name, :add_object, normalize_spec_for_overlay(spec, opts))

            broadcast_topology_changed(swarm_name)
            mutation_reply(saved, {:ok, name}, new_state)

          {:error, _} = err ->
            {:reply, err, state}
        end
    end
  end

  def handle_call({:remove_object, swarm_name, object_name, opts}, _from, state) do
    case Map.get(state.swarms, swarm_name) do
      nil ->
        {:reply, {:error, :swarm_not_found}, state}

      swarm_info ->
        case do_remove_object(swarm_name, swarm_info, object_name) do
          {:ok, new_info} ->
            new_state = put_swarm(state, swarm_name, new_info)
            saved = maybe_persist(opts, swarm_name, :remove_object, %{name: object_name})
            broadcast_topology_changed(swarm_name)
            mutation_reply(saved, :ok, new_state)

          {:error, _} = err ->
            {:reply, err, state}
        end
    end
  end

  def handle_call({:update_object_config, swarm_name, object_name, patch, opts}, _from, state) do
    case Map.get(state.swarms, swarm_name) do
      nil ->
        {:reply, {:error, :swarm_not_found}, state}

      swarm_info ->
        case do_update_object_config(swarm_name, swarm_info, object_name, patch) do
          {:ok, name, new_info} ->
            new_state = put_swarm(state, swarm_name, new_info)

            saved =
              maybe_persist(opts, swarm_name, :update_config, %{name: object_name, config: patch})

            broadcast_topology_changed(swarm_name)
            mutation_reply(saved, {:ok, name}, new_state)

          {:error, _} = err ->
            {:reply, err, state}
        end
    end
  end

  def handle_call({:add_topology_edges, swarm_name, edges, opts}, _from, state) do
    case Map.get(state.swarms, swarm_name) do
      nil ->
        {:reply, {:error, :swarm_not_found}, state}

      swarm_info ->
        case Router.add_edges(swarm_name, edges) do
          :ok ->
            new_config =
              update_in_config_topology(swarm_info.config, edges, &Enum.uniq(&1 ++ edges))

            new_info = %{swarm_info | config: new_config}
            new_state = put_swarm(state, swarm_name, new_info)
            saved = maybe_persist(opts, swarm_name, :add_topology_edges, %{edges: edges})
            broadcast_topology_changed(swarm_name)
            mutation_reply(saved, :ok, new_state)

          err ->
            {:reply, err, state}
        end
    end
  end

  def handle_call({:remove_topology_edges, swarm_name, edges, opts}, _from, state) do
    case Map.get(state.swarms, swarm_name) do
      nil ->
        {:reply, {:error, :swarm_not_found}, state}

      swarm_info ->
        case Router.remove_edges(swarm_name, edges) do
          :ok ->
            new_topology = swarm_info.config.topology -- edges
            new_config = %{swarm_info.config | topology: new_topology}
            new_info = %{swarm_info | config: new_config}
            new_state = put_swarm(state, swarm_name, new_info)
            saved = maybe_persist(opts, swarm_name, :remove_topology_edges, %{edges: edges})
            broadcast_topology_changed(swarm_name)
            mutation_reply(saved, :ok, new_state)

          err ->
            {:reply, err, state}
        end
    end
  end

  def handle_call({:get_full_config, swarm_name}, _from, state) do
    case Map.get(state.swarms, swarm_name) do
      nil -> {:reply, {:error, :swarm_not_found}, state}
      swarm_info -> {:reply, {:ok, swarm_info.config}, state}
    end
  end

  def handle_call({:restart_agent, swarm_name, agent_name}, _from, state) do
    case Map.get(state.swarms, swarm_name) do
      nil ->
        {:reply, {:error, :swarm_not_found}, state}

      swarm_info ->
        case Enum.find(swarm_info.config.agents, &(to_string(&1.name) == to_string(agent_name))) do
          nil ->
            {:reply, {:error, :agent_not_found}, state}

          agent ->
            agent_name = agent.name

            connections =
              for {from, to} <- swarm_info.config.topology, from == agent_name, do: to

            config = Map.put(agent, :connections, connections)
            result = AgentSupervisor.restart_agent(swarm_name, agent_name, config)
            {:reply, result, state}
        end
    end
  end

  def handle_call({:scale_agent_group, swarm_name, base_name, target_count, opts}, _from, state) do
    case Map.get(state.swarms, swarm_name) do
      nil ->
        {:reply, {:error, :swarm_not_found}, state}

      swarm_info ->
        with :ok <- Genswarms.IR.Gate.validate_scale(swarm_info.config, base_name, target_count),
             {:ok, result, new_info} <-
               do_scale_agent_group(swarm_name, swarm_info, base_name, target_count, opts) do
          new_state = put_swarm(state, swarm_name, new_info)

          saved =
            maybe_persist(opts, swarm_name, :scale_agent_group, %{
              base_name: base_name,
              target_count: target_count
            })

          broadcast_topology_changed(swarm_name)
          mutation_reply(saved, {:ok, result}, new_state)
        else
          {:error, _} = err -> {:reply, err, state}
        end
    end
  end

  @impl true
  def handle_info({:startup_timeout, swarm, token}, state) do
    case state.starts[swarm] do
      %{token: ^token} = pending ->
        {:noreply, finish_start(swarm, startup_error(pending, :timeout), state)}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info(message, state) do
    response =
      Enum.find_value(state.starts, fn
        {swarm, %{request: {request, name}}} ->
          case :gen_server.check_response(message, request) do
            :no_reply -> nil
            response -> {swarm, name, response}
          end

        _ ->
          nil
      end)

    case response do
      nil ->
        {:noreply, state}

      {swarm, name, response} ->
        state = put_in(state.starts[swarm].request, nil)

        case response do
          {:reply, %{state: status}} when status in [:idle, :working] ->
            {:noreply, advance_start(swarm, state)}

          _ ->
            error = startup_error(state.starts[swarm], {:object_not_ready, name})
            {:noreply, finish_start(swarm, error, state)}
        end
    end
  end

  # Private functions

  defp start_ir(ir, from, state) do
    with :desired <- ir.phase,
         :ok <- Genswarms.IR.State.validate_resolved(ir),
         {:ok, config} <- Genswarms.IR.ToConfig.swarm_config(ir) do
      do_start_swarm(config, nil, state, from, ir)
    else
      :observed -> {:reply, {:error, :expected_desired_ir}, state}
      {:error, _} = error -> {:reply, error, state}
    end
  end

  defp do_start_swarm(config, config_path, state, from, ir_seed \\ nil) do
    swarm_name = config.name

    case Genswarms.IR.Gate.validate_start(config) do
      {:error, reason} ->
        LogStore.log(
          :error,
          :swarm,
          :ir_validation_failed,
          "Refusing to start swarm '#{swarm_name}': IR validation failed",
          swarm: swarm_name,
          metadata: %{config_path: config_path, reason: inspect(reason)}
        )

        {:reply, {:error, reason}, state}

      :ok ->
        with {:ok, events} <- recovery_events(swarm_name),
             :ok <- validate_replay_events(events),
             :ok <- persist_ir_seed(ir_seed, swarm_name, state) do
          start_validated_swarm(config, config_path, state, swarm_name, events, from)
        else
          {:error, reason} -> {:reply, {:error, reason}, state}
        end
    end
  end

  defp recovery_events(name) do
    {:ok, Genswarms.CLI.SwarmRegistry.load_overlay(name) |> Enum.with_index()}
  rescue
    _ -> {:error, :invalid_persisted_overlay}
  end

  defp persist_ir_seed(nil, name, _state) do
    case Genswarms.CLI.SwarmRegistry.load_ir_seed(name) do
      {:error, :not_found} -> :ok
      {:ok, _} -> {:error, :use_persisted_ir_restore}
      error -> error
    end
  end

  defp persist_ir_seed(seed, name, state) do
    if Map.has_key?(state.swarms, name),
      do: {:error, :already_exists},
      else: Genswarms.CLI.SwarmRegistry.save_ir_seed(seed)
  end

  defp start_validated_swarm(config, config_path, state, swarm_name, overlay_events, from) do
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
      # Fold persisted :update_config overlay events for SEED objects into the
      # config BEFORE anything starts: each object then boots ONCE with its
      # effective config. Replaying them post-start (the old motion) did a
      # remove+re-add against a Registry whose deregistration is eventually
      # consistent — at boot that raced the just-started seed object
      # (already_exists on the re-add AND on the rollback), leaving the
      # manager's spec, the runtime object, and the overlay disagreeing.
      # Events are loaded ONCE and indexed so the fold and the replay agree
      # on exactly which events were consumed.
      {config, consumed} = prefold_update_config_events(config, overlay_events)

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
            request_extra: Map.get(agent, :request_extra),
            compact_extra: Map.get(agent, :compact_extra),
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
          # A handler may be a MODULE (the classic path) or a notarized package
          # ref map resolved fail-closed by the Loader (gsp design §14.3):
          # digest mismatch / missing entry ⇒ the object does NOT start.
          case Genswarms.Packages.Loader.resolve_handler(Map.get(object, :handler)) do
            {:ok, handler} ->
              object_config = %{
                name: object.name,
                swarm_name: swarm_name,
                handler: handler,
                backend: Map.get(object, :backend),
                config: Map.get(object, :config, %{})
              }

              ObjectSupervisor.start_object(object_config)

            {:error, reason} ->
              {:error, {:handler_ref, object.name, reason}}
          end
        end)

      # Check if all agents and objects started successfully
      all_results = agent_results ++ object_results
      errors = Enum.filter(all_results, &match?({:error, _}, &1))

      events =
        for {{op, payload}, index} <- overlay_events,
            not MapSet.member?(consumed, index),
            do: {op, payload, index}

      token = make_ref()

      timeout =
        case Application.get_env(:genswarms, :startup_timeout_ms, 30_000) do
          n when is_integer(n) and n > 0 and n <= 50_000 -> n
          _ -> 30_000
        end

      timer = Process.send_after(self(), {:startup_timeout, swarm_name, token}, timeout)

      pending = %{
        from: from,
        events: events,
        objects: Enum.map(config.objects || [], & &1.name),
        request: nil,
        event: nil,
        timer: timer,
        token: token,
        deadline: System.monotonic_time(:millisecond) + timeout
      }

      new_state = %{new_state | starts: Map.put(new_state.starts, swarm_name, pending)}

      state =
        if errors == [],
          do: advance_start(swarm_name, new_state),
          else: finish_start(swarm_name, {:error, {:partial_start, errors}}, new_state)

      {:noreply, state}
    end
  end

  defp emit_telemetry(event, metadata) do
    :telemetry.execute(
      [:genswarms, :swarm, event],
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

  # -- Overlay replay --

  @replay_ops ~w(add_agent remove_agent add_object remove_object update_config add_topology_edges remove_topology_edges scale_agent_group)a

  defp validate_replay_events(events) do
    Enum.reduce_while(events, :ok, fn {{op, payload}, index}, :ok ->
      reason =
        cond do
          op not in @replay_ops -> :unknown_operation
          not is_map(payload) -> :invalid_payload
          op == :update_config and not is_map(payload[:config]) -> :invalid_payload
          true -> nil
        end

      if reason,
        do: {:halt, {:error, {:overlay_replay_failed, index + 1, op, reason}}},
        else: {:cont, :ok}
    end)
  end

  # Asynchronous gen_server requests let init callbacks query this manager.
  # Each object is checked before applying the next persisted operation.
  defp advance_start(swarm, state) do
    if System.monotonic_time(:millisecond) >= state.starts[swarm].deadline do
      finish_start(swarm, startup_error(state.starts[swarm], :timeout), state)
    else
      do_advance_start(swarm, state)
    end
  end

  defp do_advance_start(swarm, state) do
    pending = state.starts[swarm]

    case {pending.objects, pending.events} do
      {[name | rest], _} ->
        server = {:via, Registry, {Genswarms.AgentRegistry, {swarm, name}}}
        request = :gen_server.send_request(server, :get_status)
        put_in(state.starts[swarm], %{pending | objects: rest, request: {request, name}})

      {[], [{op, payload, index} | rest]} ->
        pending = %{pending | events: rest, event: {index + 1, op}}
        state = put_in(state.starts[swarm], pending)

        case replay_event(swarm, op, payload, state.swarms[swarm]) do
          {:ok, info} ->
            objects = if op in [:add_object, :update_config], do: [payload.name], else: []

            state =
              state
              |> put_swarm(swarm, info)
              |> put_in([Access.key(:starts), swarm, :objects], objects)

            advance_start(swarm, state)

          {:error, reason} ->
            finish_start(swarm, startup_error(pending, reason), state)
        end

      {[], []} ->
        finish_start(swarm, :ok, state)
    end
  end

  defp startup_error(%{event: nil}, reason), do: {:error, {:startup_failed, reason}}

  defp startup_error(%{event: {index, op}}, reason),
    do: {:error, {:overlay_replay_failed, index, op, reason}}

  defp finish_start(swarm, result, state) do
    {pending, starts} = Map.pop(state.starts, swarm)
    Process.cancel_timer(pending.timer)

    if pending.request do
      {request, _name} = pending.request
      :gen_server.receive_response(request, 0)
    end

    info = state.swarms[swarm]
    state = %{state | starts: starts}

    {reply, status, state} =
      case result do
        :ok ->
          {{:ok, swarm}, :running, put_swarm(state, swarm, %{info | status: :running})}

        {:error, _} = error ->
          cleanup_failed_start(swarm, info)
          {error, :error, %{state | swarms: Map.delete(state.swarms, swarm)}}
      end

    Phoenix.PubSub.broadcast(Genswarms.PubSub, "swarm:#{swarm}", {:swarm_started, swarm, status})

    emit_telemetry(:swarm_started, %{
      swarm: swarm,
      status: status,
      agent_count: length(info.config.agents),
      object_count: length(info.config.objects || []),
      error_count: if(status == :running, do: 0, else: 1),
      level: if(status == :running, do: :info, else: :error)
    })

    GenServer.reply(pending.from, reply)
    state
  end

  defp cleanup_failed_start(swarm, info) do
    objects = MapSet.new(info.config.objects || [], & &1.name)

    entries =
      Registry.select(Genswarms.AgentRegistry, [
        {{{swarm, :"$1"}, :"$2", :_}, [], [{{:"$1", :"$2"}}]}
      ])

    for {name, pid} <- entries do
      # Do not query object status: the callback may be blocked in init.
      if MapSet.member?(objects, name) do
        DynamicSupervisor.terminate_child(Genswarms.AgentSupervisor, pid)
      else
        case AgentSupervisor.stop_agent(swarm, name) do
          :ok -> :ok
          _ -> DynamicSupervisor.terminate_child(Genswarms.AgentSupervisor, pid)
        end
      end

      await_unregistered(swarm, name)
    end

    Router.unregister_topology(swarm)
  end

  defp replay_event(swarm, op, payload, info) do
    case apply_overlay_event(swarm, op, payload, info) do
      {:ok, %{failed: [_ | _] = failed}, _new_info} -> {:error, {:partial_scale, failed}}
      {:ok, _result, new_info} -> {:ok, new_info}
      result -> result
    end
  rescue
    _ -> {:error, :invalid_replay_operation}
  catch
    :exit, _ -> {:error, :replay_operation_exited}
  end

  # Pure pre-start fold of :update_config overlay events into the seed config
  # (same Map.merge the runtime actuation uses). An event folds only while its
  # target is still the SEED incarnation: once a remove_object/add_object
  # event touches that name, later update_configs belong to the NEW
  # incarnation and must replay post-start, in order (skipping them by name
  # would silently drop the re-added object's trailing patches). Returns the
  # folded config plus the set of consumed event INDEXES for replay to skip.
  defp prefold_update_config_events(config, indexed_events) do
    seed_names =
      for spec <- config.objects || [], into: MapSet.new(), do: to_string(Map.get(spec, :name))

    {config, consumed, _still_seed} =
      Enum.reduce(indexed_events, {config, MapSet.new(), seed_names}, fn
        {{:update_config, %{name: name, config: patch}}, idx}, {cfg, consumed, still_seed}
        when is_map(patch) ->
          if MapSet.member?(still_seed, to_string(name)) do
            objects =
              Enum.map(cfg.objects || [], fn spec ->
                if same_object_name?(spec, name) do
                  merged = Map.merge(Map.get(spec, :config, %{}) || %{}, patch)
                  Map.put(spec, :config, merged)
                else
                  spec
                end
              end)

            {%{cfg | objects: objects}, MapSet.put(consumed, idx), still_seed}
          else
            {cfg, consumed, still_seed}
          end

        {{op, payload}, _idx}, {cfg, consumed, still_seed}
        when op in [:remove_object, :add_object, :remove_agent, :add_agent] ->
          name = payload[:name] || payload["name"]
          {cfg, consumed, MapSet.delete(still_seed, to_string(name))}

        _event, acc ->
          acc
      end)

    {config, consumed}
  end

  defp same_object_name?(spec, name),
    do: to_string(Map.get(spec, :name) || Map.get(spec, "name") || "") == to_string(name)

  defp await_unregistered(swarm_name, name, attempts \\ 100) do
    case Registry.lookup(Genswarms.AgentRegistry, {swarm_name, name}) do
      [] ->
        :ok

      _ when attempts > 0 ->
        Process.sleep(10)
        await_unregistered(swarm_name, name, attempts - 1)

      _ ->
        Logger.warning(
          "#{inspect(name)} still registered in #{swarm_name} after stop — re-add may collide"
        )

        :timeout
    end
  end

  defp apply_overlay_event(swarm_name, :add_agent, payload, info) do
    {connections, payload} = Map.pop(payload, :_connections, [])
    {incoming, spec} = Map.pop(payload, :_incoming, [])
    do_add_agent(swarm_name, info, spec, connections: connections, incoming: incoming)
  end

  defp apply_overlay_event(swarm_name, :remove_agent, %{name: name}, info),
    do: do_remove_agent(swarm_name, info, name)

  defp apply_overlay_event(swarm_name, :add_object, payload, info) do
    {connections, payload} = Map.pop(payload, :_connections, [])
    {incoming, spec} = Map.pop(payload, :_incoming, [])
    do_add_object(swarm_name, info, spec, connections: connections, incoming: incoming)
  end

  defp apply_overlay_event(swarm_name, :update_config, %{name: name, config: patch}, info),
    do: do_update_object_config(swarm_name, info, name, patch)

  defp apply_overlay_event(swarm_name, :remove_object, %{name: name}, info),
    do: do_remove_object(swarm_name, info, name)

  defp apply_overlay_event(swarm_name, :add_topology_edges, %{edges: edges}, info) do
    edges = replay_edges(edges)

    with :ok <- Router.add_edges(swarm_name, edges) do
      {:ok, %{info | config: update_in_config_topology(info.config, edges, nil)}}
    end
  end

  defp apply_overlay_event(swarm_name, :remove_topology_edges, %{edges: edges}, info) do
    edges = replay_edges(edges)

    with :ok <- Router.remove_edges(swarm_name, edges) do
      {:ok, %{info | config: %{info.config | topology: info.config.topology -- edges}}}
    end
  end

  defp apply_overlay_event(
         swarm_name,
         :scale_agent_group,
         %{base_name: base, target_count: n},
         info
       ),
       do: do_scale_agent_group(swarm_name, info, base, n, [])

  defp apply_overlay_event(_swarm, _op, _payload, _info), do: {:error, :invalid_payload}

  defp replay_edges(edges),
    do:
      Enum.map(edges, fn
        [from, to] -> {from, to}
        {from, to} -> {from, to}
      end)

  # -- Dynamic mutation helpers --

  defp do_add_agent(swarm_name, swarm_info, spec, opts) do
    spec = normalize_agent_spec(spec)
    name = spec.name
    connections = Keyword.get(opts, :connections, [])
    incoming = Keyword.get(opts, :incoming, [])

    cond do
      # Runtime-created agent names flow into backend spawn commands, so apply the
      # same identifier rule used at config-parse time. This covers the dynamic
      # add-agent API and any other caller, which bypass SwarmConfig.parse.
      not SwarmConfig.valid_identifier?(name) ->
        {:error,
         {:invalid_agent_name,
          "Agent name must start with a letter and contain only alphanumeric, underscore, or hyphen characters"}}

      already_registered?(swarm_name, name) ->
        {:error, {:already_exists, name}}

      true ->
        # Compute new edges (skip duplicates against current topology)
        existing = swarm_info.config.topology
        out_edges = Enum.map(connections, fn t -> {name, t} end)
        in_edges = Enum.map(incoming, fn s -> {s, name} end)
        all_new_edges = Enum.uniq(out_edges ++ in_edges) -- existing

        # Edges first (so first message after start can route)
        case Router.add_edges(swarm_name, all_new_edges) do
          :ok ->
            agent_config = %{
              name: name,
              swarm_name: swarm_name,
              backend: Map.get(spec, :backend),
              skills: Map.get(spec, :skills, []),
              model: Map.get(spec, :model),
              request_extra: Map.get(spec, :request_extra),
              compact_extra: Map.get(spec, :compact_extra),
              endpoint: Map.get(spec, :endpoint),
              presets: Map.get(spec, :presets, []),
              config: Map.get(spec, :config, %{}),
              connections: connections
            }

            case AgentSupervisor.start_agent(agent_config) do
              {:ok, _pid} ->
                new_config = %{
                  swarm_info.config
                  | agents: swarm_info.config.agents ++ [spec],
                    topology: existing ++ all_new_edges
                }

                broadcast_agent_added(swarm_name, name, spec)
                emit_telemetry(:agent_added, %{swarm: swarm_name, agent: name})
                {:ok, name, %{swarm_info | config: new_config}}

              {:error, reason} ->
                # Rollback edges
                Router.remove_edges(swarm_name, all_new_edges)
                {:error, {:agent_start_failed, reason}}
            end

          err ->
            err
        end
    end
  end

  defp do_remove_agent(swarm_name, swarm_info, agent_name) do
    case AgentSupervisor.stop_agent(swarm_name, agent_name) do
      :ok ->
        # Remove from topology in both Router and config
        Router.remove_node(swarm_name, agent_name)

        new_topology =
          Enum.reject(swarm_info.config.topology, fn {f, t} ->
            f == agent_name or t == agent_name
          end)

        new_agents = Enum.reject(swarm_info.config.agents, &spec_has_name?(&1, agent_name))

        new_config = %{
          swarm_info.config
          | agents: new_agents,
            topology: new_topology
        }

        broadcast_agent_removed(swarm_name, agent_name)
        emit_telemetry(:agent_removed, %{swarm: swarm_name, agent: agent_name})
        {:ok, %{swarm_info | config: new_config}}

      err ->
        err
    end
  end

  defp do_add_object(swarm_name, swarm_info, spec, opts) do
    spec = normalize_object_spec(spec)
    name = spec.name
    connections = Keyword.get(opts, :connections, [])
    incoming = Keyword.get(opts, :incoming, [])

    cond do
      already_registered?(swarm_name, name) ->
        {:error, {:already_exists, name}}

      true ->
        existing = swarm_info.config.topology
        out_edges = Enum.map(connections, fn t -> {name, t} end)
        in_edges = Enum.map(incoming, fn s -> {s, name} end)
        all_new_edges = Enum.uniq(out_edges ++ in_edges) -- existing

        case Router.add_edges(swarm_name, all_new_edges) do
          :ok ->
            # Same fail-closed ref resolution as the boot path (design §14.3):
            # a notarized handler ref map is resolved to the bound MODULE here;
            # the spec stored in config keeps the original ref (provenance).
            case Genswarms.Packages.Loader.resolve_handler(Map.get(spec, :handler)) do
              {:ok, resolved_handler} ->
                object_config = %{
                  name: name,
                  swarm_name: swarm_name,
                  handler: resolved_handler,
                  backend: Map.get(spec, :backend),
                  config: Map.get(spec, :config, %{})
                }

                case ObjectSupervisor.start_object(object_config) do
                  {:ok, _pid} ->
                    new_objects = (swarm_info.config.objects || []) ++ [spec]

                    new_config = %{
                      swarm_info.config
                      | objects: new_objects,
                        topology: existing ++ all_new_edges
                    }

                    emit_telemetry(:object_added, %{swarm: swarm_name, object: name})
                    {:ok, name, %{swarm_info | config: new_config}}

                  {:error, reason} ->
                    Router.remove_edges(swarm_name, all_new_edges)
                    {:error, {:object_start_failed, reason}}
                end

              {:error, reason} ->
                Router.remove_edges(swarm_name, all_new_edges)
                {:error, {:handler_ref, name, reason}}
            end

          err ->
            err
        end
    end
  end

  # update_config actuation: remove + re-add with the merged config (config is
  # init/1 input — a restart is the only deterministic apply; same motion as
  # IR.Executor's :restart_object). Edges touching the object are captured
  # first and re-declared on the re-add, so topology survives the restart.
  # If the re-add fails (e.g. the handler rejects the new config), roll back
  # to the old spec — the object must not stay dead after a bad patch.
  defp do_update_object_config(swarm_name, swarm_info, object_name, patch) when is_map(patch) do
    case Enum.find(swarm_info.config.objects || [], &spec_has_name?(&1, object_name)) do
      nil ->
        {:error, {:object_not_found, object_name}}

      spec ->
        connections = for {f, t} <- swarm_info.config.topology, f == object_name, do: t
        incoming = for {f, t} <- swarm_info.config.topology, t == object_name, do: f

        merged = Map.merge(Map.get(spec, :config, %{}) || %{}, patch)
        new_spec = Map.put(Map.new(spec), :config, merged)
        opts = [connections: connections, incoming: incoming]

        with {:ok, info_removed} <- do_remove_object(swarm_name, swarm_info, object_name) do
          case do_add_object(swarm_name, info_removed, new_spec, opts) do
            {:ok, name, new_info} ->
              emit_telemetry(:object_config_updated, %{swarm: swarm_name, object: name})
              {:ok, name, new_info}

            {:error, reason} ->
              case do_add_object(swarm_name, info_removed, Map.new(spec), opts) do
                {:ok, _name, _rolled_back} ->
                  # runtime restored to the old spec; state was never mutated
                  {:error, {:config_rejected, reason}}

                {:error, rollback_reason} ->
                  Logger.error(
                    "update_object_config: #{object_name} rejected new config " <>
                      "(#{inspect(reason)}) AND rollback failed (#{inspect(rollback_reason)}) — " <>
                      "object is DOWN; restart the swarm or re-add it manually"
                  )

                  {:error, {:config_rejected_and_rollback_failed, reason, rollback_reason}}
              end
          end
        end
    end
  end

  defp do_remove_object(swarm_name, swarm_info, object_name) do
    case ObjectSupervisor.stop_object(swarm_name, object_name) do
      :ok ->
        # Registry deregistration is eventually consistent after process
        # death; an immediate re-add (update_config's remove→add motion)
        # would hit the stale entry and fail with already_exists.
        await_unregistered(swarm_name, object_name)
        Router.remove_node(swarm_name, object_name)

        new_topology =
          Enum.reject(swarm_info.config.topology, fn {f, t} ->
            f == object_name or t == object_name
          end)

        new_objects =
          Enum.reject(swarm_info.config.objects || [], &spec_has_name?(&1, object_name))

        new_config = %{
          swarm_info.config
          | objects: new_objects,
            topology: new_topology
        }

        emit_telemetry(:object_removed, %{swarm: swarm_name, object: object_name})
        {:ok, %{swarm_info | config: new_config}}

      err ->
        err
    end
  end

  defp do_scale_agent_group(swarm_name, swarm_info, base_name, target_count, _opts) do
    existing_members = find_group_members(swarm_name, base_name)

    case find_template_spec(swarm_info.config.agents, base_name) do
      nil ->
        {:error, {:no_template, base_name}}

      template ->
        # Target names: base_name_1..base_name_target_count
        target_names =
          if target_count == 0 do
            []
          else
            Enum.map(1..target_count, fn i -> :"#{base_name}_#{i}" end)
          end

        to_add = target_names -- existing_members
        to_remove = existing_members -- target_names

        # Remove extras first (frees names, frees workspaces)
        {removed, info_after_remove} =
          Enum.reduce(to_remove, {[], swarm_info}, fn name, {acc, info} ->
            case do_remove_agent(swarm_name, info, name) do
              {:ok, new_info} -> {[name | acc], new_info}
              {:error, _} -> {acc, info}
            end
          end)

        # Add new agents
        {added, failed, info_final} =
          Enum.reduce(to_add, {[], [], info_after_remove}, fn name, {add_acc, fail_acc, info} ->
            new_spec = derive_agent_spec(template, base_name, name)

            # Auto-connect new agent matching existing template's topology edges
            connections = derived_connections(swarm_info.config.topology, template_name(template))
            incoming = derived_incoming(swarm_info.config.topology, template_name(template))

            opts = [connections: connections, incoming: incoming]

            case do_add_agent(swarm_name, info, new_spec, opts) do
              {:ok, _name, new_info} -> {[name | add_acc], fail_acc, new_info}
              {:error, reason} -> {add_acc, [{name, reason} | fail_acc], info}
            end
          end)

        {:ok,
         %{
           added: Enum.reverse(added),
           removed: Enum.reverse(removed),
           failed: Enum.reverse(failed)
         }, info_final}
    end
  end

  # -- spec / template helpers --

  defp normalize_agent_spec(spec) when is_map(spec) do
    Map.update!(spec, :name, fn n ->
      cond do
        is_atom(n) -> n
        is_binary(n) -> String.to_atom(n)
      end
    end)
  end

  defp normalize_object_spec(spec) when is_map(spec) do
    normalize_agent_spec(spec)
  end

  defp spec_has_name?(spec, name) do
    case Map.get(spec, :name) do
      ^name -> true
      n when is_binary(n) -> String.to_atom(n) == name
      _ -> false
    end
  end

  defp template_name(spec), do: Map.get(spec, :name)

  defp find_template_spec(agents, base_name) do
    # Prefer `base_name_1`, fall back to `base_name`, fall back to any `base_name_*`
    Enum.find(agents, &spec_has_name?(&1, :"#{base_name}_1")) ||
      Enum.find(agents, &spec_has_name?(&1, base_name)) ||
      Enum.find(agents, fn spec ->
        n = Map.get(spec, :name) |> to_string()
        String.starts_with?(n, "#{base_name}_")
      end)
  end

  defp derive_agent_spec(template, base_name, new_name) do
    template
    |> Map.put(:name, new_name)
    |> maybe_rename_workspace(template_name(template), new_name, base_name)
  end

  defp maybe_rename_workspace(spec, old_name, new_name, _base_name) do
    case get_in(spec, [:config, :workspace]) do
      nil ->
        spec

      ws ->
        old_str = to_string(old_name)
        new_str = to_string(new_name)

        new_ws =
          cond do
            String.ends_with?(ws, "/" <> old_str) ->
              String.replace_suffix(ws, "/" <> old_str, "/" <> new_str)

            true ->
              # Append new agent name to workspace base
              Path.join(ws, new_str)
          end

        put_in(spec, [:config, :workspace], new_ws)
    end
  end

  defp derived_connections(topology, template_name) do
    topology
    |> Enum.filter(fn {f, _t} -> f == template_name end)
    |> Enum.map(fn {_f, t} -> t end)
    |> Enum.uniq()
  end

  defp derived_incoming(topology, template_name) do
    topology
    |> Enum.filter(fn {_f, t} -> t == template_name end)
    |> Enum.map(fn {f, _t} -> f end)
    |> Enum.uniq()
  end

  defp find_group_members(swarm_name, base_name) do
    prefix_re = ~r/^#{Regex.escape(to_string(base_name))}(_\d+)?$/

    Registry.select(Genswarms.AgentRegistry, [
      {{{swarm_name, :"$1"}, :_, :_}, [], [:"$1"]}
    ])
    |> Enum.filter(fn name -> Regex.match?(prefix_re, to_string(name)) end)
  end

  defp already_registered?(swarm_name, name) do
    case Registry.lookup(Genswarms.AgentRegistry, {swarm_name, name}) do
      [] -> false
      _ -> true
    end
  end

  defp update_in_config_topology(config, edges, _merge_fun) do
    %{config | topology: Enum.uniq(config.topology ++ edges)}
  end

  defp put_swarm(state, swarm_name, swarm_info) do
    %{state | swarms: Map.put(state.swarms, swarm_name, swarm_info)}
  end

  defp maybe_persist(opts, swarm_name, op, payload) do
    if Keyword.get(opts, :persist, false) do
      Genswarms.CLI.SwarmRegistry.append_overlay(swarm_name, op, payload)
    else
      :ok
    end
  rescue
    _ -> {:error, :overlay_storage_error}
  end

  defp mutation_reply(:ok, reply, state), do: {:reply, reply, state}

  defp mutation_reply({:error, _}, _reply, state),
    do: {:reply, {:error, :applied_but_not_persisted}, state}

  defp normalize_spec_for_overlay(spec, opts) do
    spec
    |> Map.new()
    |> Map.put(:_connections, Keyword.get(opts, :connections, []))
    |> Map.put(:_incoming, Keyword.get(opts, :incoming, []))
  end

  defp broadcast_agent_added(swarm_name, name, spec) do
    Phoenix.PubSub.broadcast(
      Genswarms.PubSub,
      "swarm:#{swarm_name}",
      {:agent_added, swarm_name, name, spec}
    )
  end

  defp broadcast_agent_removed(swarm_name, name) do
    Phoenix.PubSub.broadcast(
      Genswarms.PubSub,
      "swarm:#{swarm_name}",
      {:agent_removed, swarm_name, name}
    )
  end

  defp broadcast_topology_changed(swarm_name) do
    Phoenix.PubSub.broadcast(
      Genswarms.PubSub,
      "swarm:#{swarm_name}",
      {:topology_changed, swarm_name}
    )
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
