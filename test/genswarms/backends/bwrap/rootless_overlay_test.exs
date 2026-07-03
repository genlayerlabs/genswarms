defmodule Genswarms.Backends.Bwrap.RootlessOverlayTest do
  use ExUnit.Case, async: false

  alias Genswarms.Backends.BwrapBackend
  alias Genswarms.Backends.Bwrap.OverlayManager

  setup do
    tmp = Path.join(System.tmp_dir!(), "rootless-ovl-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    prev = Application.get_env(:genswarms, :bwrap_agents_dir)
    Application.put_env(:genswarms, :bwrap_agents_dir, Path.join(tmp, "agents"))

    on_exit(fn ->
      if prev,
        do: Application.put_env(:genswarms, :bwrap_agents_dir, prev),
        else: Application.delete_env(:genswarms, :bwrap_agents_dir)

      File.rm_rf!(tmp)
    end)

    {:ok, tmp: tmp}
  end

  test "setup_overlay/3 :rootless creates upper/work WITHOUT mounting anything", %{tmp: tmp} do
    base = Path.join(tmp, "base")
    File.mkdir_p!(base)
    File.write!(Path.join(base, "hello.txt"), "lower\n")

    assert {:ok, agent_dir, ^base} =
             OverlayManager.setup_overlay("sbx-1", [{:custom, base}], :rootless)

    assert File.dir?(Path.join(agent_dir, "upper"))
    assert File.dir?(Path.join(agent_dir, "work"))
    # NOTHING mounted host-side: merged stays an empty plain dir.
    assert File.ls!(Path.join(agent_dir, "merged")) == []

    # cleanup is safe even though fuse never ran (and even without fusermount).
    assert :ok = OverlayManager.cleanup_overlay("sbx-1")
    refute File.exists?(agent_dir)
  end

  test "build_bwrap_args roots on --overlay-src/--overlay in rootless, merged bind otherwise",
       %{tmp: tmp} do
    overlay_dir = Path.join(tmp, "agent")
    Enum.each(~w(upper work merged), &File.mkdir_p!(Path.join(overlay_dir, &1)))

    rootless_args =
      BwrapBackend.build_bwrap_args(
        "sbx",
        overlay_dir,
        nil,
        tmp,
        [:base],
        %{rootless_base: "/some/base"},
        []
      )

    assert ["--overlay-src", "/some/base", "--overlay", upper, work, "/"] =
             Enum.slice(
               rootless_args,
               Enum.find_index(rootless_args, &(&1 == "--overlay-src")),
               6
             )

    assert upper == Path.join(overlay_dir, "upper")
    assert work == Path.join(overlay_dir, "work")
    refute Path.join(overlay_dir, "merged") in rootless_args

    cgroup_args =
      BwrapBackend.build_bwrap_args("sbx", overlay_dir, nil, tmp, [:base], %{}, [])

    assert Path.join(overlay_dir, "merged") in cgroup_args
    refute "--overlay-src" in cgroup_args
  end

  @tag :integration
  test "the PRODUCTION root argv shape mounts a working overlay with zero privileges",
       %{tmp: tmp} do
    if System.find_executable("bwrap") == nil do
      IO.puts("Skipping: bwrap not installed")
    else
      base = Path.join(tmp, "base")
      upper = Path.join(tmp, "up")
      work = Path.join(tmp, "wk")
      Enum.each([base, upper, work], &File.mkdir_p!/1)
      File.write!(Path.join(base, "f.txt"), "lower\n")
      sh = Path.expand(:os.cmd(~c"readlink -f $(command -v sh)") |> to_string() |> String.trim())

      {out, code} =
        System.cmd(
          System.find_executable("bwrap"),
          [
            "--unshare-user",
            "--unshare-pid",
            "--uid",
            "1000",
            "--gid",
            "1000",
            "--overlay-src",
            base,
            "--overlay",
            upper,
            work,
            "/",
            "--dev",
            "/dev",
            "--proc",
            "/proc",
            "--tmpfs",
            "/tmp",
            "--ro-bind",
            "/nix/store",
            "/nix/store",
            "--die-with-parent",
            "--",
            sh,
            "-c",
            "read x < /f.txt && echo READ=$x && echo w > /w.txt"
          ],
          stderr_to_stdout: true
        )

      assert code == 0, "bwrap overlay failed: #{out}"
      assert out =~ "READ=lower"
      assert File.read!(Path.join(upper, "w.txt")) == "w\n"
    end
  end
end
