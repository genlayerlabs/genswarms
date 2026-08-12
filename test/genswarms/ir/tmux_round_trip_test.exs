defmodule Genswarms.IR.TmuxRoundTripTest do
  use ExUnit.Case, async: true

  alias Genswarms.Config.SwarmConfig
  alias Genswarms.Backends.TmuxBackend
  alias Genswarms.IR.{FromConfig, Ref, ToConfig}

  test "tmux client and options survive config to IR to config" do
    backend =
      {:tmux, :codex,
       %{
         workspace: "/work/project",
         approval_policy: "on-request",
         resume: true,
         runner: "docker",
         image: "coding-tuis:latest",
         client_source: "runtime",
         network: "none"
       }}

    config = %{
      name: "tmux-swarm",
      agents: [%{name: :coder, backend: backend, model: "openai/test"}],
      topology: []
    }

    assert {:ok, state} = FromConfig.from_config(config)
    agent = hd(state.agents)

    assert agent.backend.ref == "tmux"
    assert agent.backend.scheme == "tmux"
    assert agent.backend.client == "codex"
    assert agent.backend.opts["workspace"] == "/work/project"
    assert agent.backend.opts["runner"] == "docker"

    assert ToConfig.agent_spec(agent).backend ==
             {:tmux, "codex",
              %{
                workspace: "/work/project",
                approval_policy: "on-request",
                resume: true,
                runner: "docker",
                image: "coding-tuis:latest",
                client_source: "runtime",
                network: "none"
              }}
  end

  test "tmux refs and swarm configs reject unknown clients" do
    assert {:error, {:invalid_tmux_client, "mystery"}} =
             Ref.parse(%{"ref" => "tmux", "client" => "mystery"})

    assert {:error, {:unsupported_tmux_client, :mystery}} =
             SwarmConfig.parse(%{
               name: "tmux-swarm",
               agents: [%{name: :coder, backend: {:tmux, :mystery}}],
               topology: []
             })
  end

  test "backend module and config mapping keep the declared client authoritative" do
    assert SwarmConfig.backend_module({:tmux, :claude}) == TmuxBackend

    assert SwarmConfig.backend_config({:tmux, :claude, %{client: :codex, resume: true}}) ==
             %{client: :claude, resume: true}
  end

  test "swarm config validates tmux runner and client-source names" do
    base = %{
      name: "tmux-swarm",
      agents: [%{name: :coder, backend: {:tmux, :codex}}],
      topology: []
    }

    assert {:ok, _config} =
             SwarmConfig.parse(%{
               base
               | agents: [
                   %{
                     name: :coder,
                     backend: {:tmux, :codex, %{runner: :bwrap, client_source: :host_nix}}
                   }
                 ]
             })

    assert {:error, {:unsupported_tmux_runner, :ssh}} =
             SwarmConfig.parse(%{
               base
               | agents: [%{name: :coder, backend: {:tmux, :codex, %{runner: :ssh}}}]
             })

    assert {:error, {:unsupported_client_source, :host_path}} =
             SwarmConfig.parse(%{
               base
               | agents: [
                   %{
                     name: :coder,
                     backend: {:tmux, :codex, %{client_source: :host_path}}
                   }
                 ]
             })
  end
end
