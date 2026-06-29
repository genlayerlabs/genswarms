defmodule Genswarms.Backends.LocalBackendTest do
  # not async: spawns a real OS process and touches the filesystem
  use ExUnit.Case, async: false

  alias Genswarms.Backends.LocalBackend

  describe "build_args/3" do
    test "returns argv as separate literal elements (no shell string)" do
      assert LocalBackend.build_args("researcher", "subzeroclaw", "/skills") ==
               ["researcher", "subzeroclaw", "/skills"]
    end

    test "keeps a name with shell metacharacters intact as a single arg" do
      evil = "a; touch /tmp/pwned"
      assert [^evil, "subzeroclaw", ""] = LocalBackend.build_args(evil, "subzeroclaw", nil)
    end
  end

  describe "start/2 spawns via argv (command-injection regression test)" do
    setup do
      tmp = Path.join(System.tmp_dir!(), "gs_local_be_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp)
      argv_out = Path.join(tmp, "argv.txt")
      # A stub "wrapper" that records the argv it actually received, then exits.
      stub = Path.join(tmp, "stub-wrapper.sh")
      File.write!(stub, """
      #!/usr/bin/env bash
      printf '%s\\n' "$@" > "#{argv_out}"
      exit 0
      """)
      File.chmod!(stub, 0o755)
      on_exit(fn -> File.rm_rf(tmp) end)
      {:ok, tmp: tmp, stub: stub, argv_out: argv_out}
    end

    test "a malicious agent name is passed literally and NOT shell-executed", ctx do
      marker = Path.join(ctx.tmp, "INJECTED")
      # If the name were interpolated into a /bin/sh -c string, this would run `touch marker`.
      evil_name = "evil; touch #{marker} #"

      {:ok, ref} =
        LocalBackend.start(evil_name, %{
          wrapper_path: ctx.stub,
          subzeroclaw_path: "subzeroclaw",
          skills_dir: nil
        })

      # wait for the stub to record argv (it exits immediately after writing)
      wait_until(fn -> File.exists?(ctx.argv_out) end)
      LocalBackend.stop(ref)

      argv = ctx.argv_out |> File.read!() |> String.split("\n", trim: true)

      # the entire malicious string arrived as ONE argv element, verbatim
      assert hd(argv) == evil_name
      # and the injection side-effect never happened
      refute File.exists?(marker), "command injection: marker file was created"
    end
  end

  describe "stop/1 terminates a busy agent's process tree (leak regression, #62)" do
    setup do
      tmp = Path.join(System.tmp_dir!(), "gs_local_be_stop_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp)
      child_pid_file = Path.join(tmp, "child.pid")

      # Mimics szc-wrapper-fifo.sh's relevant shape: spawn a BUSY child that
      # never reads stdin, reap it from a `trap ... EXIT`, and block in `wait`.
      # This is the exact state where a `Port.close`-only stop leaked: closing
      # the wrapper's stdin does nothing because the wrapper isn't reading it.
      wrapper = Path.join(tmp, "busy-wrapper.sh")

      File.write!(wrapper, """
      #!/usr/bin/env bash
      sleep 100000 &
      child=$!
      printf '%s' "$child" > "#{child_pid_file}"
      cleanup() { kill -TERM "$child" 2>/dev/null; }
      trap cleanup EXIT
      wait "$child"
      """)

      File.chmod!(wrapper, 0o755)
      on_exit(fn -> File.rm_rf(tmp) end)

      {:ok, wrapper: wrapper, child_pid_file: child_pid_file}
    end

    test "wrapper and its busy child are both dead after stop/1", ctx do
      {:ok, ref} =
        LocalBackend.start("busy_agent", %{
          wrapper_path: ctx.wrapper,
          subzeroclaw_path: "unused",
          skills_dir: nil
        })

      {:os_pid, wrapper_pid} = Port.info(ref.port, :os_pid)
      wait_until(fn -> File.exists?(ctx.child_pid_file) end)
      child_pid = ctx.child_pid_file |> File.read!() |> String.trim()

      # Belt-and-braces: never leave the fake processes behind if an assert fails.
      on_exit(fn ->
        System.cmd("kill", ["-KILL", to_string(wrapper_pid)], stderr_to_stdout: true)
        System.cmd("kill", ["-KILL", child_pid], stderr_to_stdout: true)
      end)

      assert alive?(wrapper_pid), "precondition: wrapper should be running"
      assert alive?(child_pid), "precondition: busy child should be running"

      assert :ok = LocalBackend.stop(ref)

      assert eventually(fn -> not alive?(wrapper_pid) end),
             "wrapper (pid #{wrapper_pid}) still alive after stop/1"

      assert eventually(fn -> not alive?(child_pid) end),
             "LEAK: busy child (pid #{child_pid}) still alive after stop/1"
    end
  end

  defp wait_until(fun, attempts \\ 50) do
    cond do
      fun.() ->
        :ok

      attempts <= 0 ->
        flunk("condition not met in time")

      true ->
        Process.sleep(20)
        wait_until(fun, attempts - 1)
    end
  end

  # Like wait_until/2 but returns a boolean instead of flunking, so the caller
  # can attach a specific failure message (e.g. which pid leaked).
  defp eventually(fun, attempts \\ 100) do
    cond do
      fun.() -> true
      attempts <= 0 -> false
      true -> Process.sleep(20) && eventually(fun, attempts - 1)
    end
  end

  defp alive?(pid) when is_integer(pid), do: alive?(Integer.to_string(pid))

  defp alive?(pid) when is_binary(pid),
    do: match?({_, 0}, System.cmd("kill", ["-0", pid], stderr_to_stdout: true))
end
