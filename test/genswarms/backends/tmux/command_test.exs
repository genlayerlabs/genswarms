defmodule Genswarms.Backends.Tmux.CommandTest do
  use ExUnit.Case, async: true

  alias Genswarms.Backends.Tmux.Command

  defmodule Runner do
    @behaviour Genswarms.Backends.Tmux.CommandRunner

    @impl true
    def run(executable, args) do
      calls = Process.get({__MODULE__, :calls}, [])
      Process.put({__MODULE__, :calls}, [{executable, args} | calls])
      Process.get({__MODULE__, :handler}, fn _args -> {"", 0} end).(args)
    end
  end

  setup do
    Process.put({Runner, :calls}, [])
    Process.delete({Runner, :handler})
    :ok
  end

  test "send_text transports hostile-looking text as one argv element" do
    config = config()
    payload = "do work; touch /tmp/never-executed && $(id)"

    assert :ok = Command.send_text(config, "%7", payload)

    calls = calls()

    assert {"/bin/sh", ["-L", "testsocket", "send-keys", "-l", "-t", "%7", ^payload]} =
             Enum.at(calls, 0)

    assert {"/bin/sh", ["-L", "testsocket", "send-keys", "-t", "%7", "Enter"]} =
             Enum.at(calls, 1)
  end

  test "cursor_context captures only rows ending at the active cursor" do
    Process.put({Runner, :handler}, fn args ->
      case Enum.drop(args, 2) do
        ["display-message", "-p", "-t", "%7", _format] -> {"17\t48\n", 0}
        ["capture-pane" | _] -> {"> staged task", 0}
      end
    end)

    assert {:ok, "> staged task"} = Command.cursor_context(config(), "%7")

    assert {_executable,
            [
              "-L",
              "testsocket",
              "capture-pane",
              "-p",
              "-J",
              "-S",
              "12",
              "-E",
              "17",
              "-t",
              "%7"
            ]} = Enum.at(calls(), 1)
  end

  test "cursor_context rejects malformed cursor metadata" do
    Process.put({Runner, :handler}, fn _args -> {"not-a-position", 0} end)
    assert {:error, :invalid_cursor_position} = Command.cursor_context(config(), "%7")
  end

  test "creates a missing session with executable and arguments kept separate" do
    Process.put({Runner, :handler}, fn args ->
      command = Enum.drop(args, 2)

      case command do
        ["list-panes" | _] ->
          if Process.get(:tmux_session_created),
            do: {"%11\n", 0},
            else: {"no server running on test socket", 1}

        ["new-session" | _] ->
          Process.put(:tmux_session_created, true)
          {"", 0}

        ["set-option" | _] ->
          {"", 0}

        ["respawn-pane" | _] ->
          {"", 0}
      end
    end)

    launch = %{
      executable: "/bin/echo",
      args: ["hello; touch /tmp/never", "$(id)"],
      env: []
    }

    assert {:ok, %{pane_id: "%11", reattached?: false}} =
             Command.ensure_pane(config(), launch)

    {_executable, new_session} =
      Enum.find(calls(), fn {_executable, args} -> Enum.at(args, 2) == "new-session" end)

    refute "/bin/echo" in new_session

    {_executable, respawn} =
      Enum.find(calls(), fn {_executable, args} -> Enum.at(args, 2) == "respawn-pane" end)

    assert Enum.take(respawn, -3) == ["/bin/echo", "hello; touch /tmp/never", "$(id)"]
  end

  test "respawns a dead pane instead of returning a dead persistent session" do
    Process.put({Runner, :handler}, fn args ->
      case Enum.drop(args, 2) do
        ["list-panes" | _] -> {"%12\n", 0}
        ["display-message" | _] -> {"%12\t1\tdead\t123\n", 0}
        ["respawn-pane" | _] -> {"", 0}
      end
    end)

    launch = %{executable: "/bin/echo", args: ["worker"], env: []}

    assert {:ok, %{pane_id: "%12", restarted?: true, reattached?: false}} =
             Command.ensure_pane(config(), launch)

    assert Enum.any?(calls(), fn {_executable, args} ->
             Enum.at(args, 2) == "respawn-pane" and Enum.take(args, -2) == ["/bin/echo", "worker"]
           end)
  end

  test "falls back to a new window when another agent wins session creation" do
    Process.put({Runner, :handler}, fn args ->
      case Enum.drop(args, 2) do
        ["list-panes" | _] ->
          if Process.get(:tmux_window_created),
            do: {"%13\n", 0},
            else: {"no server running on test socket", 1}

        ["new-session" | _] ->
          {"duplicate session: testsession", 1}

        ["new-window" | _] ->
          Process.put(:tmux_window_created, true)
          {"", 0}

        ["set-option" | _] ->
          {"", 0}

        ["respawn-pane" | _] ->
          {"", 0}
      end
    end)

    launch = %{executable: "/bin/echo", args: ["worker"], env: []}

    assert {:ok, %{pane_id: "%13", reattached?: false}} =
             Command.ensure_pane(config(), launch)

    assert Enum.any?(calls(), fn {_executable, args} -> Enum.at(args, 2) == "new-window" end)
  end

  test "does not disguise an arbitrary tmux failure as a missing pane" do
    Process.put({Runner, :handler}, fn args ->
      case Enum.drop(args, 2) do
        ["list-panes" | _] -> {"permission denied", 1}
      end
    end)

    assert {:error, {:tmux_command_failed, 1, "permission denied"}} =
             Command.ensure_pane(config(), %{executable: "/bin/echo", args: [], env: []})

    refute Enum.any?(calls(), fn {_executable, args} ->
             Enum.at(args, 2) in ["new-session", "new-window"]
           end)
  end

  test "kill_window propagates executable lookup failures" do
    config = %{config() | tmux_executable: "/definitely/missing/tmux"}
    assert {:error, :tmux_not_found} = Command.kill_window(config)
  end

  test "kill_window is idempotent when the tmux socket no longer exists" do
    Process.put({Runner, :handler}, fn _args -> {"error connecting to /tmp/missing", 1} end)
    assert :ok = Command.kill_window(config())
  end

  defp config do
    %{
      tmux_executable: "/bin/sh",
      command_runner: Runner,
      tmux_socket: "testsocket",
      session_name: "testsession",
      window_name: "worker",
      submit_delay_ms: 0,
      workspace: "/tmp/workspace with spaces"
    }
  end

  defp calls, do: Process.get({Runner, :calls}, []) |> Enum.reverse()
end
