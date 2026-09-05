defmodule Genswarms.Backends.RealTuiOpenCodeTest do
  use ExUnit.Case, async: false

  alias Genswarms.Backends.TmuxBackend
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

    def launch(config) do
      with {:ok, launch} <- OpenCode.launch(config) do
        env = [
          "PATH=#{System.get_env("PATH")}",
          "HOME=#{config.fixture_home}",
          "XDG_CONFIG_HOME=#{config.fixture_home}/config",
          "XDG_DATA_HOME=#{config.fixture_home}/data",
          "XDG_CACHE_HOME=#{config.fixture_home}/cache",
          "XDG_STATE_HOME=#{config.fixture_home}/state",
          "TERM=xterm-256color",
          "OPENCODE_DISABLE_MODELS_FETCH=true",
          "OPENCODE_CONFIG_CONTENT=#{config.fixture_config}"
        ]

        {:ok,
         %{
           executable: System.find_executable("env"),
           args: ["-i"] ++ env ++ [launch.executable | launch.args],
           env: []
         }}
      end
    end
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

          unless String.starts_with?(task_path, opts[:root] <> "/"),
            do: raise("unexpected task path")

          dir = Path.dirname(task_path)
          # Only the real client's bash tool writes files, not this server.
          command =
            "cat #{quote_arg(task_path)} >/dev/null && " <>
              "printf '%s' 'real-opencode-completed' > #{quote_arg(Path.join(dir, "reply.md"))} && " <>
              "printf '%s' '{\"status\":\"completed\"}' > #{quote_arg(Path.join(dir, "done.json.tmp"))} && " <>
              "mv #{quote_arg(Path.join(dir, "done.json.tmp"))} #{quote_arg(Path.join(dir, "done.json"))}"

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

    defp quote_arg(value), do: "'" <> String.replace(value, "'", "'\\''") <> "'"
  end

  test "real OpenCode completes two turns with a disconnect and reattach between them" do
    assert System.find_executable("tmux"), "tmux is required for the opted-in real-client test"
    assert System.find_executable("opencode"), "OpenCode is required for the opted-in test"
    {version, 0} = System.cmd("opencode", ["--version"])

    assert String.trim(version) == @client_version,
           "Review and update the pinned fixture for OpenCode #{String.trim(version)}"

    unique = System.unique_integer([:positive])
    root = Path.join(System.tmp_dir!(), "genswarms-real-tui-#{unique}")
    File.mkdir_p!(root)
    socket = "gsreal#{unique}"
    session = "gsreal#{unique}"

    on_exit(fn ->
      System.cmd("tmux", ["-L", socket, "kill-session", "-t", session], stderr_to_stdout: true)
      File.rm_rf!(root)
    end)

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
      event_sink: self(),
      backend_id: make_ref(),
      client: IsolatedOpenCode,
      swarm_name: "real-tui",
      workspace: Path.join(root, "workspace"),
      fixture_home: Path.join(root, "home"),
      fixture_config: provider_config,
      tmux_socket: socket,
      session_name: session,
      window_name: "worker",
      auto_approve: true,
      model: "fixture/fixture",
      args: ["--pure"],
      poll_interval_ms: 100,
      submit_delay_ms: 50
    }

    assert {:ok, ref} = TmuxBackend.start("worker", config)
    id = config.backend_id
    assert_receive {:genswarms_backend_event, ^id, {:lifecycle, :ready, _}}, 15_000
    run_turn(ref, id, "first")
    assert :ok = TmuxBackend.disconnect(ref)

    id2 = make_ref()
    assert {:ok, ref2} = TmuxBackend.start("worker", %{config | backend_id: id2})

    assert_receive {:genswarms_backend_event, ^id2, {:lifecycle, :started, %{reattached: true}}},
                   3_000

    assert_receive {:genswarms_backend_event, ^id2, {:lifecycle, :ready, _}}, 3_000
    run_turn(ref2, id2, "second")
    assert :ok = TmuxBackend.destroy(ref2)
  end

  defp run_turn(ref, id, prompt) do
    assert {:ok, %{turn_id: turn}} =
             TmuxBackend.send_input(
               ref,
               Jason.encode!(%{type: "task", content: prompt})
             )

    assert_receive {:fixture_tool_requested, task_path}, 15_000
    assert String.contains?(task_path, turn)
    assert_receive {:genswarms_backend_event, ^id, {:turn_completed, ^turn, reply, _}}, 15_000
    assert reply == "real-opencode-completed"
    assert :ok = TmuxBackend.acknowledge(ref, turn)
    assert_receive {:genswarms_backend_event, ^id, {:lifecycle, :ready, _}}, 5_000
  end
end
