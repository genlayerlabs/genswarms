defmodule Genswarms.Backends.BackendBehaviour do
  @moduledoc """
  Behaviour definition for agent backends.

  Backends are responsible for starting, stopping, and communicating with
  agent runtimes. Implementations include:

  - `LocalBackend` - Runs subzeroclaw as a local Port process
  - `DockerBackend` - Runs subzeroclaw in a Docker container
  - `BwrapBackend` - Runs subzeroclaw in a bubblewrap sandbox
  - `SSHBackend` - Runs subzeroclaw on a remote machine via SSH
  - `TmuxBackend` - Runs a persistent interactive coding-agent TUI
  """

  @type ref :: any()
  @type config :: map()
  @type skills :: [String.t()]
  @type message :: String.t()
  @type send_result :: :ok | {:ok, map()} | {:error, term()}

  @type capability ::
          :readiness_events
          | :interrupt
          | :persistent_session
          | :raw_terminal

  @type backend_event ::
          {:lifecycle, atom(), map()}
          | {:turn_completed, String.t(), String.t(), map()}
          | {:terminal, String.t(), map()}
          | {:stopped, term(), map()}

  @doc """
  Starts an agent process with the given name and configuration.

  Returns `{:ok, ref}` where `ref` is a backend-specific reference
  that can be used with other callbacks.
  """
  @callback start(name :: String.t(), config :: config()) ::
              {:ok, ref()} | {:error, term()}

  @doc """
  Stops a running agent process.
  """
  @callback stop(ref :: ref()) :: :ok | {:error, term()}

  @doc """
  Sends input to the agent's stdin.
  """
  @callback send_input(ref :: ref(), message :: message()) :: send_result()

  @doc """
  Deploys skills to the agent.

  For local backend, this sets the SUBZEROCLAW_SKILLS env var.
  For Docker, this mounts the skills directory as a volume.
  For SSH, this SCPs the skills to the remote machine.
  """
  @callback deploy_skills(ref :: ref(), skills_dir :: String.t()) ::
              :ok | {:error, term()}

  @doc """
  Performs a health check on the agent.
  """
  @callback health_check(ref :: ref()) :: :ok | {:error, term()}

  @doc """
  Returns the backend type as an atom.
  """
  @callback backend_type() :: atom()

  @doc """
  Optional callback for handling output from the agent.
  Called by the agent server when data is received.
  """
  @callback handle_output(ref :: ref(), data :: binary()) ::
              {:ok, [map()]} | {:ok, [map()], binary()}

  @doc """
  Returns optional capabilities exposed by the backend.

  Event-driven backends receive `:event_sink` and `:backend_id` in their start
  config and send messages in this form:

      {:genswarms_backend_event, backend_id, backend_event}

  A backend advertising `:readiness_events` is kept in `:starting` until it
  emits `{:lifecycle, :ready, metadata}`. After acknowledging a typed turn
  completion, it must emit a fresh ready event before accepting another turn.
  """
  @callback capabilities() :: MapSet.t(capability()) | [capability()]

  @doc "Interrupts the current turn without destroying the worker session."
  @callback interrupt(ref :: ref()) :: :ok | {:error, term()}

  @doc "Returns non-secret backend/session metadata for status surfaces."
  @callback session_info(ref :: ref()) :: map()

  @doc "Disconnects the orchestrator while preserving a persistent worker."
  @callback disconnect(ref :: ref()) :: :ok | {:error, term()}

  @doc "Intentionally destroys the worker and its persistent session."
  @callback destroy(ref :: ref()) :: :ok | {:error, term()}

  @doc "Acknowledges durable handling of a backend turn completion."
  @callback acknowledge(ref :: ref(), turn_id :: String.t()) :: :ok | {:error, term()}

  @optional_callbacks [
    handle_output: 2,
    capabilities: 0,
    interrupt: 1,
    session_info: 1,
    disconnect: 1,
    destroy: 1,
    acknowledge: 2
  ]
end
