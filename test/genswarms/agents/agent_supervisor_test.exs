defmodule Genswarms.Agents.AgentSupervisorTest do
  use ExUnit.Case, async: true

  alias Genswarms.Agents.AgentSupervisor

  defmodule StatusAgent do
    use GenServer

    def start_link({swarm, name, status}) do
      GenServer.start_link(__MODULE__, status,
        name: {:via, Registry, {Genswarms.AgentRegistry, {swarm, name}}}
      )
    end

    @impl true
    def init(status), do: {:ok, status}

    @impl true
    def handle_call(:get_status, _from, status), do: {:reply, status, status}
  end

  test "list_agents preserves non-secret backend lifecycle and session metadata" do
    swarm = "agent-list-#{System.unique_integer([:positive])}"

    status = %{
      state: :needs_attention,
      backend: :tmux,
      inbox_size: 1,
      message_count: 2,
      turn_id: "turn-1",
      attention_reason: "nudge_not_submitted",
      session: %{transport: :tmux, client: :codex, pane_id: "%9"},
      skills: ["private prompt content is not a status field"]
    }

    pid = start_supervised!({StatusAgent, {swarm, :worker, status}})

    assert [listed] = AgentSupervisor.list_agents(swarm)
    assert listed.name == :worker
    assert listed.pid == inspect(pid)
    assert listed.state == :needs_attention
    assert listed.backend == :tmux
    assert listed.turn_id == "turn-1"
    assert listed.attention_reason == "nudge_not_submitted"
    assert listed.session.pane_id == "%9"
    refute Map.has_key?(listed, :skills)
  end
end
