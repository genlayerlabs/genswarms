defmodule Genswarms.Backends.Bwrap.RootlessLauncherTest do
  use ExUnit.Case, async: true

  alias Genswarms.Backends.Bwrap.RootlessLauncher

  describe "memory_to_kb/1" do
    test "parses systemd-style suffixes into RLIMIT_AS kilobytes" do
      assert RootlessLauncher.memory_to_kb("32M") == 32 * 1024
      assert RootlessLauncher.memory_to_kb("1G") == 1024 * 1024
      assert RootlessLauncher.memory_to_kb("512K") == 512
      assert RootlessLauncher.memory_to_kb("2048") == 2
    end

    test "nil / zero / junk mean NO limit (0), never a guessed one" do
      assert RootlessLauncher.memory_to_kb(nil) == 0
      assert RootlessLauncher.memory_to_kb("") == 0
      assert RootlessLauncher.memory_to_kb("lots") == 0
      assert RootlessLauncher.memory_to_kb("32X") == 0
      assert RootlessLauncher.memory_to_kb(0) == 0
    end

    test "accepts a bare integer byte count" do
      assert RootlessLauncher.memory_to_kb(1_048_576) == 1024
    end
  end

  describe "launch_spec/2" do
    test "returns the systemd-shaped triple with a NIL scope and the priv launcher" do
      {exe, argv, scope} =
        RootlessLauncher.launch_spec(["bwrap", "--unshare-user", "--", "cmd"], %{
          memory_max: "32M",
          nice: 10
        })

      assert scope == nil, "there is no cgroup scope in rootless mode"
      assert String.ends_with?(exe, "priv/bwrap-rootless-launch.sh")
      # <rlimit_as_kb> <nice> -- <bwrap argv...>
      assert argv == ["32768", "10", "--", "bwrap", "--unshare-user", "--", "cmd"]
    end

    test "no memory_max ⇒ 0 (launcher treats 0 as unlimited)" do
      {_exe, argv, _scope} = RootlessLauncher.launch_spec(["bwrap"], %{})
      assert ["0", "19", "--", "bwrap"] == argv
    end

    test "nice is clamped to the POSIX range" do
      {_e, ["0", "19", "--" | _], _s} = RootlessLauncher.launch_spec(["bwrap"], %{nice: 999})
      {_e2, ["0", "-20", "--" | _], _s2} = RootlessLauncher.launch_spec(["bwrap"], %{nice: -999})
    end

    test "the bwrap argv is passed through verbatim (no shell interpretation)" do
      nasty = ["bwrap", "--setenv", "X", "a; rm -rf /", "--", "cmd"]
      {_exe, argv, _scope} = RootlessLauncher.launch_spec(nasty, %{})
      # The dangerous string survives as ONE argv slot, unmangled.
      assert "a; rm -rf /" in argv
    end
  end
end

defmodule Genswarms.Backends.Bwrap.RootlessLauncherScriptTest do
  use ExUnit.Case, async: true

  @script Path.join(:code.priv_dir(:genswarms), "bwrap-rootless-launch.sh")

  test "the launcher applies RLIMIT_AS and execs the tail with args intact" do
    {out, 0} =
      System.cmd("sh", [
        @script,
        "65536",
        "19",
        "--",
        "sh",
        "-c",
        "echo \"AS=$(ulimit -v) TAIL=$*\"",
        "_",
        "hello",
        "a; rm -rf /"
      ])

    assert out =~ "AS=65536"
    # the shell-metachar arg reaches the tail as ONE untouched token
    assert out =~ "TAIL=hello a; rm -rf /"
  end

  test "a zero limit means unlimited (no ulimit clamp)" do
    {out, 0} = System.cmd("sh", [@script, "0", "5", "--", "sh", "-c", "echo \"AS=$(ulimit -v)\""])
    assert out =~ "AS=unlimited"
  end
end
