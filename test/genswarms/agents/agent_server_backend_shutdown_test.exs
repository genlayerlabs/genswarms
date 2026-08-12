defmodule Genswarms.Agents.AgentServerBackendShutdownTest do
  use ExUnit.Case, async: true

  alias Genswarms.Agents.AgentServer

  defmodule FakeBackend do
    @behaviour Genswarms.Backends.BackendBehaviour

    def start(_name, _config), do: {:ok, %{owner: self()}}
    def stop(%{owner: owner}), do: send(owner, :backend_stopped)
    def send_input(_ref, _message), do: :ok
    def deploy_skills(ref, _skills_dir), do: {:ok, ref}
    def health_check(_ref), do: :ok
    def backend_type, do: :fake
  end

  defmodule FailingDestroyBackend do
    @behaviour Genswarms.Backends.BackendBehaviour

    def start(_name, _config), do: {:error, :not_used}
    def stop(_ref), do: :ok
    def destroy(_ref), do: {:error, :tmux_unavailable}
    def send_input(_ref, _message), do: :ok
    def deploy_skills(_ref, _skills_dir), do: :ok
    def health_check(_ref), do: :ok
    def backend_type, do: :failing_destroy
  end

  test "shutdown_backend stops the backend ref once and clears it" do
    state = %AgentServer{backend_module: FakeBackend, backend_ref: %{owner: self()}}

    assert {:reply, :ok, new_state} = AgentServer.handle_call(:shutdown_backend, self(), state)
    assert_receive :backend_stopped
    assert new_state.backend_ref == nil
    assert new_state.state == :stopped

    assert {:reply, {:error, :agent_stopped}, ^new_state} =
             AgentServer.handle_call({:send_task, "late task"}, self(), new_state)

    assert {:reply, :ok, ^new_state} =
             AgentServer.handle_call(:shutdown_backend, self(), new_state)

    refute_receive :backend_stopped
  end

  test "shutdown_backend preserves the live ref when explicit destruction fails" do
    ref = %{owner: self()}
    state = %AgentServer{backend_module: FailingDestroyBackend, backend_ref: ref}

    assert {:reply, {:error, :tmux_unavailable}, unchanged} =
             AgentServer.handle_call(:shutdown_backend, self(), state)

    assert unchanged.backend_ref == ref
    refute unchanged.state == :stopped
  end
end
