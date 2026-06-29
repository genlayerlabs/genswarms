defmodule Genswarms.Agents.AgentServerConfigTest do
  use ExUnit.Case, async: true

  alias Genswarms.Agents.AgentServer

  # These tests pin the spawn-config contract: a key set on an `agents:`-entry
  # (the per-agent `config:` map) only reaches the backend if it is in
  # `init/1`'s `backend_keys` allowlist. A bwrap-only key that is NOT
  # allowlisted is silently split out as a "domain" key and dropped — which
  # silently un-hardens the sandbox for that agent. Regression guard for the
  # recurring `backend_keys` omission (`:store` in #60, `:seccomp` in fe0a11d).

  defp backend_config_for(agent_config) do
    {:ok, state} =
      AgentServer.init(
        name: "agent_1",
        swarm_name: "swarm_1",
        backend: :bwrap,
        config: agent_config
      )

    # init/1 enqueues :start_backend to self(); drain it so the test mailbox
    # is clean and no backend is actually started.
    receive do
      :start_backend -> :ok
    after
      0 -> :ok
    end

    state.backend_config
  end

  describe "spawn-config contract: bwrap-only keys reach the backend" do
    test ":seccomp set on a per-agent config reaches backend_config" do
      assert %{seccomp: true} = backend_config_for(%{seccomp: true})
    end

    test ":store / :extra_store_paths reach backend_config" do
      cfg = backend_config_for(%{store: :closure, extra_store_paths: ["/nix/store/x"]})
      assert cfg.store == :closure
      assert cfg.extra_store_paths == ["/nix/store/x"]
    end

    test "domain keys are NOT leaked into backend_config" do
      cfg = backend_config_for(%{population_size: 10, max_iterations: 3})
      refute Map.has_key?(cfg, :population_size)
      refute Map.has_key?(cfg, :max_iterations)
    end
  end
end
