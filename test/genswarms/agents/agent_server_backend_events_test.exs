defmodule Genswarms.Agents.AgentServerBackendEventsTest do
  use ExUnit.Case, async: true

  alias Genswarms.Agents.{AgentServer, Inbox}

  defmodule EventBackend do
    @behaviour Genswarms.Backends.BackendBehaviour

    def start(_name, _config), do: {:error, :not_used}

    def stop(%{owner: owner}) do
      send(owner, :backend_stopped)
      :ok
    end

    def stop(_ref), do: :ok

    def send_input(%{owner: owner, fail?: true}, message) do
      send(owner, {:backend_send_attempt, message})
      {:error, :transport_failed}
    end

    def send_input(%{owner: owner}, message) do
      send(owner, {:backend_input, message})
      {:ok, %{turn_id: "sent-turn"}}
    end

    def acknowledge(%{owner: owner}, turn_id) do
      send(owner, {:backend_acknowledged, turn_id})
      :ok
    end

    def deploy_skills(_ref, _skills_dir), do: :ok
    def health_check(_ref), do: :ok
    def backend_type, do: :event_test
  end

  test "typed completion is finalized once and acknowledged after handling" do
    id = make_ref()
    state = state(id, :blocked) |> Map.put(:backend_turn_id, "turn-1")

    event =
      {:genswarms_backend_event, id,
       {:turn_completed, "turn-1", "finished reply", %{pane_id: "%1"}}}

    assert {:noreply, completed} = AgentServer.handle_info(event, state)
    assert_receive {:backend_acknowledged, "turn-1"}
    assert completed.state == :starting
    assert completed.backend_turn_id == nil
    assert completed.backend_metadata.pane_id == "%1"
  end

  test "typed completion acknowledges and waits for readiness before the next queued turn" do
    id = make_ref()
    {:ok, inbox} = Inbox.push(Inbox.new(), queued_task("next task"))

    state =
      state(id, :working)
      |> Map.put(:backend_turn_id, "turn-1")
      |> Map.put(:inbox, inbox)

    event =
      {:genswarms_backend_event, id,
       {:turn_completed, "turn-1", "finished reply", %{pane_id: "%1"}}}

    assert {:noreply, waiting} = AgentServer.handle_info(event, state)
    assert_receive {:backend_acknowledged, "turn-1"}
    assert waiting.state == :starting
    assert Inbox.size(waiting.inbox) == 1
    refute_receive {:backend_input, _}

    ready = {:genswarms_backend_event, id, {:lifecycle, :ready, %{pane_id: "%1"}}}
    assert {:noreply, next_turn} = AgentServer.handle_info(ready, waiting)
    assert_receive {:backend_input, encoded}
    assert Jason.decode!(encoded)["content"] == "next task"
    assert next_turn.state == :working
    assert next_turn.backend_turn_id == "sent-turn"
    assert Inbox.size(next_turn.inbox) == 0
  end

  test "ready dispatches a queued task and only pops it after a successful send" do
    id = make_ref()
    {:ok, inbox} = Inbox.push(Inbox.new(), queued_task("queued task"))
    state = %{state(id, :starting) | inbox: inbox}

    event = {:genswarms_backend_event, id, {:lifecycle, :ready, %{pane_id: "%2"}}}
    assert {:noreply, running} = AgentServer.handle_info(event, state)

    assert_receive {:backend_input, encoded}
    assert Jason.decode!(encoded)["content"] == "queued task"
    assert running.state == :working
    assert running.backend_turn_id == "sent-turn"
    assert Inbox.size(running.inbox) == 0
  end

  test "a delayed ready event cannot reset or dispatch over an active turn" do
    id = make_ref()
    {:ok, inbox} = Inbox.push(Inbox.new(), queued_task("must remain queued"))
    state = %{state(id, :working) | inbox: inbox, backend_turn_id: nil}

    event = {:genswarms_backend_event, id, {:lifecycle, :ready, %{pane_id: "%2"}}}
    assert {:noreply, still_running} = AgentServer.handle_info(event, state)

    assert still_running.state == :working
    assert still_running.backend_metadata.pane_id == "%2"
    assert Inbox.size(still_running.inbox) == 1
    refute_receive {:backend_input, _}
  end

  test "a failed backend send leaves the durable inbox entry queued" do
    id = make_ref()
    {:ok, inbox} = Inbox.push(Inbox.new(), queued_task("keep me"))

    state = %{
      state(id, :starting)
      | inbox: inbox,
        backend_ref: %{owner: self(), fail?: true}
    }

    event = {:genswarms_backend_event, id, {:lifecycle, :ready, %{}}}
    assert {:noreply, failed} = AgentServer.handle_info(event, state)

    assert_receive {:backend_send_attempt, _}
    assert failed.state == :idle
    assert Inbox.size(failed.inbox) == 1
  end

  test "follow-up tasks queue while a persistent turn needs human attention" do
    state = state(make_ref(), :needs_attention)

    assert {:reply, :ok, queued} =
             AgentServer.handle_call({:send_task, "follow up"}, self(), state)

    assert Inbox.size(queued.inbox) == 1
    refute_receive {:backend_input, _}
  end

  test "needs-attention status exposes a non-secret recovery reason and turn id" do
    id = make_ref()
    state = state(id, :working) |> Map.put(:backend_turn_id, "turn-staged")

    event =
      {:genswarms_backend_event, id,
       {:lifecycle, :needs_attention,
        %{reason: :nudge_not_submitted, turn_id: "turn-staged", pane_id: "%9"}}}

    assert {:noreply, attention} = AgentServer.handle_info(event, state)
    assert {:reply, status, ^attention} = AgentServer.handle_call(:get_status, self(), attention)
    assert status.state == :needs_attention
    assert status.turn_id == "turn-staged"
    assert status.attention_reason == "nudge_not_submitted"
  end

  test "events from a previous backend generation are ignored" do
    state = state(make_ref(), :starting)
    stale = make_ref()
    event = {:genswarms_backend_event, stale, {:lifecycle, :ready, %{pane_id: "%old"}}}

    assert {:noreply, ^state} = AgentServer.handle_info(event, state)
  end

  test "a Port backend exit immediately releases its non-Port resources" do
    port = make_ref()

    state = %{
      state(make_ref(), :working)
      | backend_ref: %{owner: self(), port: port},
        backend_turn_id: "dead-turn"
    }

    assert {:noreply, stopped} = AgentServer.handle_info({port, {:exit_status, 137}}, state)
    assert_receive :backend_stopped
    assert stopped.state == :stopped
    assert stopped.backend_ref == nil
    assert stopped.backend_turn_id == nil
  end

  defp state(id, phase) do
    %AgentServer{
      name: :worker,
      swarm_name: "event-test",
      backend_module: EventBackend,
      backend_ref: %{owner: self()},
      backend_id: id,
      backend_config: %{},
      inbox: Inbox.new(),
      skills: [],
      state: phase,
      started_at: DateTime.utc_now()
    }
  end

  defp queued_task(content) do
    %{
      from: "orchestrator",
      content: content,
      received_at: DateTime.utc_now(),
      task?: true
    }
  end
end
