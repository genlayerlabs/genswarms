defmodule Genswarms.Test.RealTuiFixture do
  @moduledoc false
  import ExUnit.Assertions
  alias Genswarms.Backends.TmuxBackend

  def workspace(client) do
    unique = Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
    root = Path.join(System.tmp_dir!(), "genswarms-#{client}-#{unique}")
    home = Path.join(root, "home")
    workspace = Path.join(root, "workspace")
    socket = "gs#{client}#{unique}"
    File.mkdir_p!(home)
    File.mkdir_p!(workspace)

    ExUnit.Callbacks.on_exit(fn ->
      System.cmd("tmux", ["-L", socket, "kill-server"], stderr_to_stdout: true)
      File.rm_rf!(root)
    end)

    %{root: root, home: home, workspace: workspace, socket: socket}
  end

  def launch(adapter, config, extra_env) do
    with {:ok, launch} <- adapter.launch(config) do
      # No inherited login/profile/provider secrets. These paths belong only to
      # this fixture's child process; the user's configuration is never modified.
      env =
        [
          "PATH=#{System.get_env("PATH")}",
          "HOME=#{config.fixture_home}",
          "SHELL=#{System.find_executable("bash")}",
          "TERM=xterm-256color",
          "HTTP_PROXY=http://127.0.0.1:9",
          "HTTPS_PROXY=http://127.0.0.1:9",
          "ALL_PROXY=http://127.0.0.1:9",
          "NO_PROXY=127.0.0.1,localhost"
        ] ++ extra_env

      {:ok,
       %{
         executable: System.find_executable("env"),
         args: ["-i"] ++ env ++ [launch.executable | launch.args],
         env: []
       }}
    end
  end

  def receipt_command(task_path, root, reply) do
    unless String.starts_with?(task_path, root <> "/"), do: raise("unexpected fixture task path")
    dir = Path.dirname(task_path)
    # The provider returns this command, but never writes the receipts itself.
    # Only the real client's shell tool reads task.md and produces the result.
    "cat #{quote_arg(task_path)} >/dev/null && " <>
      "printf '%s' #{quote_arg(reply)} > #{quote_arg(Path.join(dir, "reply.md"))} && " <>
      "printf '%s' '{\"status\":\"completed\"}' > #{quote_arg(Path.join(dir, "done.json.tmp"))} && " <>
      "mv #{quote_arg(Path.join(dir, "done.json.tmp"))} #{quote_arg(Path.join(dir, "done.json"))}"
  end

  def exercise(config, reply) do
    config = Map.merge(config, %{event_sink: self(), backend_id: make_ref()})
    assert {:ok, ref} = TmuxBackend.start("worker", config)
    id = config.backend_id
    assert_receive {:genswarms_backend_event, ^id, {:lifecycle, :ready, _}}, 15_000
    run_turn(ref, id, "first", reply)
    assert :ok = TmuxBackend.disconnect(ref)
    id2 = make_ref()
    assert {:ok, ref2} = TmuxBackend.start("worker", %{config | backend_id: id2})

    assert_receive {:genswarms_backend_event, ^id2, {:lifecycle, :started, %{reattached: true}}},
                   3000

    assert_receive {:genswarms_backend_event, ^id2, {:lifecycle, :ready, _}}, 3000
    run_turn(ref2, id2, "second", reply)
    assert :ok = TmuxBackend.destroy(ref2)
  end

  defp run_turn(ref, id, prompt, expected) do
    assert {:ok, %{turn_id: turn}} =
             TmuxBackend.send_input(ref, Jason.encode!(%{type: "task", content: prompt}))

    assert_receive {:fixture_tool_requested, task_path}, 15_000
    assert String.contains?(task_path, turn)
    assert_receive {:genswarms_backend_event, ^id, {:turn_completed, ^turn, reply, _}}, 15_000
    assert reply == expected
    assert :ok = TmuxBackend.acknowledge(ref, turn)
    assert_receive {:genswarms_backend_event, ^id, {:lifecycle, :ready, _}}, 5000
  end

  defp quote_arg(value), do: "'" <> String.replace(value, "'", "'\\''") <> "'"
end
