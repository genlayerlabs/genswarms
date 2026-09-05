defmodule Genswarms.Backends.RealTuiClaudeTest do
  use ExUnit.Case, async: false
  alias Genswarms.Test.RealTuiFixture, as: Fixture
  alias Genswarms.Backends.Tmux.Adapters.Claude
  @moduletag skip: System.get_env("GENSWARMS_REAL_TUI") != "1"
  @moduletag timeout: 60_000

  defmodule IsolatedClaude do
    @behaviour Genswarms.Backends.Tmux.Adapter
    defdelegate client(), to: Claude
    defdelegate ready?(snapshot, config), to: Claude
    defdelegate blocked?(snapshot, config), to: Claude
    defdelegate nudge(turn, config), to: Claude

    def launch(config),
      do:
        Fixture.launch(Claude, config, [
          "ANTHROPIC_BASE_URL=#{config.fixture_url}",
          "ANTHROPIC_AUTH_TOKEN=local-fixture-only",
          "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1",
          "DISABLE_PROMPT_CACHING=1"
        ])
  end

  defmodule Provider do
    @behaviour Plug
    import Plug.Conn
    def init(opts), do: opts

    def call(%{request_path: "/v1/messages/count_tokens"} = conn, _opts),
      do:
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, ~s({"input_tokens":10}))

    def call(conn, opts) do
      {:ok, body, conn} = read_body(conn, length: 2_000_000)
      request = Jason.decode!(body)
      messages = request["messages"] || []

      content =
        messages
        |> Enum.filter(&(&1["role"] == "user"))
        |> List.last()
        |> then(&Jason.encode!(&1))

      match = Regex.run(~r/read and execute .([^\x60]+\/task\.md)/, content)
      has_bash? = Enum.any?(request["tools"] || [], &(&1["name"] == "Bash"))
      tool_result? = String.contains?(content, "tool_result")
      id = "msg_#{System.unique_integer([:positive])}"

      {block, delta, stop} =
        if match && has_bash? && not tool_result? do
          [_, task_path] = match

          command = Fixture.receipt_command(task_path, opts[:root], "real-claude-completed")

          send(opts[:owner], {:fixture_tool_requested, task_path})

          {%{type: "tool_use", id: "tool_#{id}", name: "Bash", input: %{}},
           %{
             type: "input_json_delta",
             partial_json:
               Jason.encode!(%{command: command, description: "Complete isolated fixture"})
           }, "tool_use"}
        else
          {%{type: "text", text: ""}, %{type: "text_delta", text: "Fixture complete"}, "end_turn"}
        end

      message = %{
        id: id,
        type: "message",
        role: "assistant",
        model: request["model"],
        content: [],
        stop_reason: nil,
        stop_sequence: nil,
        usage: %{input_tokens: 10, output_tokens: 0}
      }

      events = [
        %{type: "message_start", message: message},
        %{type: "content_block_start", index: 0, content_block: block},
        %{type: "content_block_delta", index: 0, delta: delta},
        %{type: "content_block_stop", index: 0},
        %{
          type: "message_delta",
          delta: %{stop_reason: stop, stop_sequence: nil},
          usage: %{output_tokens: 10}
        },
        %{type: "message_stop"}
      ]

      payload =
        Enum.map_join(
          events,
          "",
          &("event: " <> &1.type <> "\ndata: " <> Jason.encode!(&1) <> "\n\n")
        )

      conn |> put_resp_content_type("text/event-stream") |> send_resp(200, payload)
    end
  end

  test "real Claude completes two turns and reattaches the same client" do
    assert System.find_executable("tmux")
    assert System.find_executable("claude")
    assert {"2.1.260 (Claude Code)\n", 0} = System.cmd("claude", ["--version"])
    %{root: root, home: home, workspace: workspace, socket: socket} = Fixture.workspace("claude")

    File.write!(
      Path.join(home, ".claude.json"),
      Jason.encode!(%{
        hasCompletedOnboarding: true,
        theme: "dark",
        projects: %{workspace => %{hasTrustDialogAccepted: true}}
      })
    )

    server =
      start_supervised!(
        {Bandit, plug: {Provider, root: root, owner: self()}, ip: {127, 0, 0, 1}, port: 0}
      )

    {:ok, {_, port}} = ThousandIsland.listener_info(server)

    config = %{
      client: IsolatedClaude,
      swarm_name: "real-claude",
      workspace: workspace,
      fixture_home: home,
      fixture_url: "http://127.0.0.1:#{port}",
      tmux_socket: socket,
      session_name: socket,
      window_name: "worker",
      model: "claude-sonnet-4-6",
      permission_mode: "dontAsk",
      args: ["--safe-mode", "--tools", "Bash", "--allowedTools", "Bash"],
      poll_interval_ms: 100,
      submit_delay_ms: 50
    }

    Fixture.exercise(config, "real-claude-completed")
  end
end
