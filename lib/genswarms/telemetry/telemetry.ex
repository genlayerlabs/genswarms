defmodule Genswarms.Telemetry do
  @moduledoc """
  Telemetry metrics and handlers for Genswarms.

  Tracks:
  - Swarm lifecycle events (start, stop)
  - Agent lifecycle events (start, stop, error)
  - Message routing events
  - Backend health
  """

  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Returns the list of telemetry metrics for LiveDashboard.
  """
  def metrics do
    [
      # Phoenix metrics
      summary("phoenix.endpoint.start.system_time",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.start.system_time",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.live_view.mount.start.system_time",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.live_view.mount.stop.duration",
        unit: {:native, :millisecond}
      ),

      # Swarm metrics
      counter("genswarms.swarm.swarm_started.count",
        tags: [:swarm]
      ),
      counter("genswarms.swarm.swarm_stopped.count",
        tags: [:swarm]
      ),
      last_value("genswarms.swarm.agent_count",
        tags: [:swarm]
      ),

      # Agent metrics
      counter("genswarms.agent.agent_started.count",
        tags: [:swarm, :agent]
      ),
      counter("genswarms.agent.agent_stopped.count",
        tags: [:swarm, :agent]
      ),
      counter("genswarms.agent.agent_error.count",
        tags: [:swarm, :agent]
      ),
      counter("genswarms.agent.task_sent.count",
        tags: [:swarm, :agent]
      ),
      counter("genswarms.agent.message_delivered.count",
        tags: [:swarm, :agent]
      ),

      # Router metrics
      counter("genswarms.router.message_routed.count",
        tags: [:swarm]
      ),
      counter("genswarms.router.message_broadcast.count",
        tags: [:swarm]
      ),
      counter("genswarms.router.invalid_route.count",
        tags: [:swarm]
      ),

      # VM metrics
      summary("vm.memory.total", unit: {:byte, :megabyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io")
    ]
  end

  defp periodic_measurements do
    [
      {__MODULE__, :measure_swarms, []}
    ]
  end

  @doc false
  def measure_swarms do
    # A periodic measurement must never blow up the poller: SwarmManager may
    # not be running (CLI commands → :noproc), the call can TIME OUT while the
    # manager is busy (:timeout — seen live under agent load), and a swarm
    # entry missing :agent_count would raise. Any of those previously escaped
    # the old {:noproc, _}-only guard and logged
    # "Error when calling MFA defined by measurement" every poll tick.
    try do
      swarms = Genswarms.SwarmManager.list()

      Enum.each(swarms, fn swarm ->
        :telemetry.execute(
          [:genswarms, :swarm, :agent_count],
          %{agent_count: Map.get(swarm, :agent_count, 0)},
          %{swarm: swarm.name}
        )
      end)
    rescue
      _ -> :ok
    catch
      :exit, _ -> :ok
    end
  end
end
