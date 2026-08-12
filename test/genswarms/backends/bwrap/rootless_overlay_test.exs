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

  test "setup_overlay/3 :rootless materializes a private root without following symlinks",
       %{tmp: tmp} do
    base = Path.join(tmp, "base")
    outside = Path.join(tmp, "outside-resolv.conf")
    File.mkdir_p!(Path.join(base, "etc"))
    File.write!(Path.join(base, "hello.txt"), "lower\n")
    File.write!(outside, "must-not-change\n")
    File.ln_s!(outside, Path.join([base, "etc", "resolv.conf"]))
    File.ln_s!("/nix/store/example-tool", Path.join(base, "tool"))

    seed = fn agent_dir ->
      etc = Path.join([agent_dir, "upper", "etc"])
      secrets = Path.join([agent_dir, "upper", "run", "secrets"])
      File.mkdir_p!(etc)
      File.mkdir_p!(secrets)
      File.write!(Path.join(etc, "resolv.conf"), "sandbox-dns\n")
      File.chmod!(secrets, 0o700)
      File.write!(Path.join(secrets, "api-key"), "private")
      File.chmod!(Path.join(secrets, "api-key"), 0o600)
      :ok
    end

    assert {:ok, agent_dir, ^base} =
             OverlayManager.setup_overlay("sbx-1", [{:custom, base}],
               mode: :rootless,
               seed: seed
             )

    assert File.dir?(Path.join(agent_dir, "upper"))
    assert File.dir?(Path.join(agent_dir, "work"))
    merged = Path.join(agent_dir, "merged")
    assert File.read!(Path.join(merged, "hello.txt")) == "lower\n"
    assert File.read!(Path.join([merged, "etc", "resolv.conf"])) == "sandbox-dns\n"
    assert File.read!(outside) == "must-not-change\n"
    assert File.read_link!(Path.join(merged, "tool")) == "/nix/store/example-tool"
    secret = Path.join([merged, "run", "secrets", "api-key"])
    assert Bitwise.band(File.stat!(secret).mode, 0o777) == 0o600
    assert Bitwise.band(File.stat!(Path.dirname(secret)).mode, 0o777) == 0o700
    assert File.dir?(Path.join([merged, "nix", "store"]))
    assert File.dir?(Path.join([merged, "usr", "local", "bin"]))
    assert File.dir?(Path.join(merged, "workspace"))

    # cleanup is safe even though fuse never ran (and even without fusermount).
    assert :ok = OverlayManager.cleanup_overlay("sbx-1")
    refute File.exists?(agent_dir)
  end

  test "build_bwrap_args binds the prepared merged root in both privilege modes",
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
        %{privilege_mode: :rootless},
        []
      )

    merged = Path.join(overlay_dir, "merged")
    root_index = Enum.find_index(rootless_args, &(&1 == "--bind"))
    assert Enum.slice(rootless_args, root_index, 3) == ["--bind", merged, "/"]
    refute "--overlay-src" in rootless_args
    refute "--overlay" in rootless_args

    cgroup_args =
      BwrapBackend.build_bwrap_args("sbx", overlay_dir, nil, tmp, [:base], %{}, [])

    assert merged in cgroup_args
    refute "--overlay-src" in cgroup_args
  end

  @tag :integration
  test "the production root argv binds a writable materialized root with zero privileges",
       %{tmp: tmp} do
    if System.find_executable("bwrap") == nil do
      IO.puts("Skipping: bwrap not installed")
    else
      base = Path.join(tmp, "base")
      File.mkdir_p!(base)
      File.write!(Path.join(base, "f.txt"), "lower\n")
      sh = Path.expand(:os.cmd(~c"readlink -f $(command -v sh)") |> to_string() |> String.trim())

      assert {:ok, agent_dir, ^base} =
               OverlayManager.setup_overlay("integration", [{:custom, base}], :rootless)

      merged = Path.join(agent_dir, "merged")

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
            "--bind",
            merged,
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

      assert code == 0, "bwrap materialized root failed: #{out}"
      assert out =~ "READ=lower"
      assert File.read!(Path.join(merged, "w.txt")) == "w\n"
      assert :ok = OverlayManager.cleanup_overlay("integration")
    end
  end
end
