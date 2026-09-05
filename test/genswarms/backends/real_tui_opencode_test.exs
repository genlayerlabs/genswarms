defmodule Genswarms.Backends.RealTuiOpenCodeTest do
  use ExUnit.Case, async: false

  alias Genswarms.Test.RealTuiFixture, as: Fixture
  alias Genswarms.Backends.Tmux.Adapters.OpenCode

  @moduletag skip: System.get_env("GENSWARMS_REAL_TUI") != "1"
  @moduletag timeout: 60_000
  @client_version "1.18.28"

  # Only the environment changes. Launch flags, readiness, nudge, permissions
  # and tool execution use the real OpenCode adapter and executable.
  defmodule IsolatedOpenCode do
    @behaviour Genswarms.Backends.Tmux.Adapter
    defdelegate client(), to: OpenCode
    defdelegate ready?(snapshot, config), to: OpenCode
    defdelegate blocked?(snapshot, config), to: OpenCode
    defdelegate nudge(turn, config), to: OpenCode

    def launch(config),
      do:
        Fixture.launch(OpenCode, config, [
          "XDG_CONFIG_HOME=#{config.fixture_home}/config",
          "XDG_DATA_HOME=#{config.fixture_home}/data",
          "XDG_CACHE_HOME=#{config.fixture_home}/cache",
          "XDG_STATE_HOME=#{config.fixture_home}/state",
          "OPENCODE_DISABLE_MODELS_FETCH=true",
          "OPENCODE_CONFIG_CONTENT=#{config.fixture_config}"
        ])
  end

  defmodule Provider do
    @behaviour Plug
    import Plug.Conn
    def init(opts), do: opts

    def call(conn, opts) do
      {:ok, body, conn} = read_body(conn, length: 2_000_000)
      request = Jason.decode!(body)
      messages = Map.get(request, "messages", [])
      last_user = messages |> Enum.filter(&(&1["role"] == "user")) |> List.last()
      content = if last_user, do: Jason.encode!(last_user["content"]), else: ""
      match = Regex.run(~r/read and execute .([^\x60]+\/task\.md)/, content)
      tool_result? = List.last(messages)["role"] == "tool"
      has_bash? = Enum.any?(request["tools"] || [], &(get_in(&1, ["function", "name"]) == "bash"))

      {delta, finish} =
        if match && has_bash? && not tool_result? do
          [_, task_path] = match

          command = Fixture.receipt_command(task_path, opts[:root], "real-opencode-completed")

          send(opts[:owner], {:fixture_tool_requested, task_path})

          {%{
             tool_calls: [
               %{
                 index: 0,
                 id: "fixture-call",
                 type: "function",
                 function: %{
                   name: "bash",
                   arguments:
                     Jason.encode!(%{
                       command: command,
                       description: "Complete isolated runtime fixture"
                     })
                 }
               }
             ]
           }, "tool_calls"}
        else
          {%{content: "Fixture complete"}, "stop"}
        end

      chunks = [
        %{
          id: "fixture",
          object: "chat.completion.chunk",
          model: "fixture",
          created: 1,
          choices: [%{index: 0, delta: Map.put(delta, :role, "assistant"), finish_reason: nil}]
        },
        %{
          id: "fixture",
          object: "chat.completion.chunk",
          model: "fixture",
          created: 1,
          choices: [%{index: 0, delta: %{}, finish_reason: finish}],
          usage: %{prompt_tokens: 10, completion_tokens: 10, total_tokens: 20}
        }
      ]

      payload =
        Enum.map_join(chunks, "", &("data: " <> Jason.encode!(&1) <> "\n\n")) <>
          "data: [DONE]\n\n"

      conn |> put_resp_content_type("text/event-stream") |> send_resp(200, payload)
    end
  end

  test "real OpenCode completes two turns with a disconnect and reattach between them" do
    assert System.find_executable("tmux"), "tmux is required for the opted-in real-client test"
    assert System.find_executable("opencode"), "OpenCode is required for the opted-in test"
    {version, 0} = System.cmd("opencode", ["--version"])

    assert String.trim(version) == @client_version,
           "Review and update the pinned fixture for OpenCode #{String.trim(version)}"

    %{root: root, home: home, workspace: workspace, socket: socket} =
      Fixture.workspace("opencode")

    server =
      start_supervised!(
        {Bandit, plug: {Provider, root: root, owner: self()}, ip: {127, 0, 0, 1}, port: 0}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)

    provider_config =
      Jason.encode!(%{
        enabled_providers: ["fixture"],
        model: "fixture/fixture",
        provider: %{
          fixture: %{
            npm: "@ai-sdk/openai-compatible",
            name: "Local fixture",
            options: %{baseURL: "http://127.0.0.1:#{port}/v1", apiKey: "local-fixture-only"},
            models: %{fixture: %{name: "Fixture", limit: %{context: 100_000, output: 4096}}}
          }
        },
        permission: "allow"
      })

    config = %{
      client: IsolatedOpenCode,
      swarm_name: "real-tui",
      workspace: workspace,
      fixture_home: home,
      fixture_config: provider_config,
      tmux_socket: socket,
      session_name: socket,
      window_name: "worker",
      auto_approve: true,
      model: "fixture/fixture",
      args: ["--pure"],
      poll_interval_ms: 100,
      submit_delay_ms: 50
    }

    Fixture.exercise(config, "real-opencode-completed")
  end
end
