defmodule Genswarms.Backends.RealTuiCodexTest do
  use ExUnit.Case, async: false
  alias Genswarms.Test.RealTuiFixture, as: Fixture
  alias Genswarms.Backends.Tmux.Adapters.Codex
  @moduletag skip: System.get_env("GENSWARMS_REAL_TUI") != "1"
  @moduletag timeout: 60_000

  defmodule IsolatedCodex do
    @behaviour Genswarms.Backends.Tmux.Adapter
    defdelegate client(), to: Codex
    defdelegate ready?(snapshot, config), to: Codex
    defdelegate blocked?(snapshot, config), to: Codex
    defdelegate nudge(turn, config), to: Codex

    def launch(config),
      do: Fixture.launch(Codex, config, ["CODEX_HOME=#{config.fixture_home}/codex"])
  end

  defmodule Provider do
    @behaviour Plug
    import Plug.Conn
    def init(opts), do: opts

    def call(conn, opts) do
      {:ok, body, conn} = read_body(conn, length: 2_000_000)
      request = Jason.decode!(body)
      input = request["input"] || []
      last_user = input |> Enum.filter(&(&1["role"] == "user")) |> List.last()
      content = if last_user, do: Jason.encode!(last_user["content"]), else: ""
      match = Regex.run(~r/read and execute .([^\x60]+\/task\.md)/, content)
      tools = request["tools"] || []
      names = Enum.map(tools, & &1["name"])
      send(opts[:owner], {:fixture_request, conn.request_path, names})
      completed? = List.last(input)["type"] == "function_call_output"
      id = "resp_#{System.unique_integer([:positive])}"

      item =
        if match && Enum.any?(names, &(&1 in ["exec_command", "shell_command", "shell"])) &&
             not completed? do
          [_, task_path] = match

          command = Fixture.receipt_command(task_path, opts[:root], "real-codex-completed")

          {name, args} =
            cond do
              "exec_command" in names -> {"exec_command", %{cmd: command, login: false}}
              "shell_command" in names -> {"shell_command", %{command: command, login: false}}
              "shell" in names -> {"shell", %{command: ["bash", "-c", command]}}
              true -> raise "fixture requires a shell tool: #{inspect(names)}"
            end

          send(opts[:owner], {:fixture_tool_requested, task_path})

          %{
            id: "fc_#{id}",
            type: "function_call",
            call_id: "call_#{id}",
            name: name,
            arguments: Jason.encode!(args),
            status: "completed"
          }
        else
          %{
            id: "msg_#{id}",
            type: "message",
            role: "assistant",
            status: "completed",
            content: [%{type: "output_text", text: "Fixture complete", annotations: []}]
          }
        end

      response = %{
        id: id,
        object: "response",
        created_at: 1,
        model: "fixture",
        status: "completed",
        output: [item],
        usage: %{input_tokens: 10, output_tokens: 10, total_tokens: 20}
      }

      events = [
        %{type: "response.created", response: %{response | status: "in_progress", output: []}},
        %{type: "response.output_item.added", output_index: 0, item: item},
        %{type: "response.output_item.done", output_index: 0, item: item},
        %{type: "response.completed", response: response}
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

  test "real Codex completes two turns and reattaches the same client" do
    assert System.find_executable("tmux")
    assert System.find_executable("codex")
    assert {"codex-cli 0.153.4\n", 0} = System.cmd("codex", ["--version"])
    %{root: root, home: home, workspace: workspace, socket: socket} = Fixture.workspace("codex")
    File.mkdir_p!(Path.join(home, "codex"))

    server =
      start_supervised!(
        {Bandit, plug: {Provider, root: root, owner: self()}, ip: {127, 0, 0, 1}, port: 0}
      )

    {:ok, {_, port}} = ThousandIsland.listener_info(server)

    File.write!(Path.join(home, "codex/config.toml"), """
    model = "fixture"
    model_provider = "fixture"
    check_for_update_on_startup = false
    web_search = "disabled"
    [analytics]
    enabled = false
    [feedback]
    enabled = false
    [projects.#{Jason.encode!(workspace)}]
    trust_level = "trusted"
    [model_providers.fixture]
    name = "Local fixture"
    base_url = "http://127.0.0.1:#{port}/v1"
    wire_api = "responses"
    requires_openai_auth = false
    supports_websockets = false
    request_max_retries = 0
    stream_max_retries = 0
    """)

    config = %{
      client: IsolatedCodex,
      swarm_name: "real-codex",
      workspace: workspace,
      fixture_home: home,
      tmux_socket: socket,
      session_name: socket,
      window_name: "worker",
      model: "fixture",
      approval_policy: :never,
      sandbox: :workspace_write,
      poll_interval_ms: 100,
      submit_delay_ms: 50
    }

    Fixture.exercise(config, "real-codex-completed")
  end
end
