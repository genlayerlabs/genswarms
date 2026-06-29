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

  test "shutdown_backend stops the backend ref once and clears it" do
    state = %AgentServer{backend_module: FakeBackend, backend_ref: %{owner: self()}}

    assert {:reply, :ok, new_state} = AgentServer.handle_call(:shutdown_backend, self(), state)
    assert_receive :backend_stopped
    assert new_state.backend_ref == nil

    assert {:reply, :ok, ^new_state} =
             AgentServer.handle_call(:shutdown_backend, self(), new_state)

    refute_receive :backend_stopped
  end
end
