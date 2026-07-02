defmodule Genswarms.Packages.LoaderTest do
  use ExUnit.Case, async: false

  alias Genswarms.Packages.{Dirhash, Loader}

  # ── fixtures ─────────────────────────────────────────────────────────────────

  defp write!(path, content) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
  end

  # A minimal, valid handler package: two files where compile ORDER matters
  # (the object @behaviour-references its core), plus the notarized entry file.
  defp fixture_package!(dir, module_suffix) do
    core = "PkgFixture#{module_suffix}.Core"
    obj = "PkgFixture#{module_suffix}"

    write!(Path.join(dir, "core.ex"), """
    defmodule #{core} do
      @callback ping() :: :pong
    end
    """)

    write!(Path.join(dir, "object.ex"), """
    defmodule #{obj} do
      @behaviour #{core}
      def ping, do: :pong
      def init(config), do: {:ok, config}
    end
    """)

    write!(
      Path.join(dir, "swarm-object.json"),
      Jason.encode!(%{module: obj, files: ["core.ex", "object.ex"]})
    )

    {:ok, digest} = Dirhash.hash_dir(dir)
    {obj, digest}
  end

  # ── dirhash: the cross-language contract ────────────────────────────────────

  test "dirhash matches the pinned Go/Python conformance vector" do
    dir = Path.join(System.tmp_dir!(), "dirhash-vec-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)

    write!(Path.join(dir, "web-researcher/body.md"), """
    # web-researcher

    A reusable agent `body` (data, not code): persona, tool affordances and the
    research loop. Plugs into any agent `body` slot of a swarm IR.
    """)

    # The same vector pinned by swarmidx (Python) and the gsp CLI (Go).
    assert Dirhash.hash_dir(Path.join(dir, "web-researcher")) ==
             {:ok, "sha256:880ecf8f8b0f1e3f59e0083186d9cc03f0809a66fcab66f310f1e55f1edd87cd"}
  end

  test "dirhash skips .git (a clone's VCS internals must not move the digest)" do
    dir = Path.join(System.tmp_dir!(), "dirhash-git-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)
    write!(Path.join(dir, "a.md"), "content\n")
    {:ok, clean} = Dirhash.hash_dir(dir)
    write!(Path.join(dir, ".git/config"), "[core]\n")
    write!(Path.join(dir, "sub/.git/HEAD"), "ref\n")
    assert Dirhash.hash_dir(dir) == {:ok, clean}
  end

  # ── loader ───────────────────────────────────────────────────────────────────

  test "plain module and nil handlers pass through untouched" do
    assert Loader.resolve_handler(nil) == {:ok, nil}
    assert Loader.resolve_handler(Genswarms.Packages.Dirhash) == {:ok, Genswarms.Packages.Dirhash}
  end

  test ":require loads verified bytes in entry order and returns the entry module" do
    dir = Path.join(System.tmp_dir!(), "pkg-req-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)
    {module_name, digest} = fixture_package!(dir, "Req#{System.unique_integer([:positive])}")

    assert {:ok, mod} =
             Loader.resolve_handler(%{
               ref: "swarmidx:acme/fixture@1.0.0",
               digest: digest,
               path: dir,
               mode: :require
             })

    assert to_string(mod) == "Elixir." <> module_name
    assert mod.ping() == :pong
    assert {:ok, %{a: 1}} = mod.init(%{a: 1})
  end

  test "digest mismatch refuses to bind (fail-closed) in both modes" do
    dir = Path.join(System.tmp_dir!(), "pkg-bad-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)
    {_module, _digest} = fixture_package!(dir, "Bad#{System.unique_integer([:positive])}")

    for mode <- [:require, :verify] do
      assert {:error, {:digest_mismatch, _, _}} =
               Loader.resolve_handler(%{
                 ref: "swarmidx:acme/fixture@1.0.0",
                 digest: "sha256:0000000000000000000000000000000000000000000000000000000000000000",
                 path: dir,
                 mode: mode
               })
    end
  end

  test "tampering after notarization is caught" do
    dir = Path.join(System.tmp_dir!(), "pkg-tamper-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)
    {_module, digest} = fixture_package!(dir, "Tamper#{System.unique_integer([:positive])}")
    write!(Path.join(dir, "object.ex"), "defmodule Evil do\nend\n")

    assert {:error, {:digest_mismatch, _, _}} =
             Loader.resolve_handler(%{
               ref: "swarmidx:acme/fixture@1.0.0",
               digest: digest,
               path: dir,
               mode: :require
             })
  end

  test "missing swarm-object.json refuses to bind" do
    dir = Path.join(System.tmp_dir!(), "pkg-noentry-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)
    write!(Path.join(dir, "object.ex"), "defmodule NoEntry#{System.unique_integer([:positive])} do\nend\n")
    {:ok, digest} = Dirhash.hash_dir(dir)

    assert {:error, {:missing_entry_file, _}} =
             Loader.resolve_handler(%{ref: "r", digest: digest, path: dir, mode: :require})
  end

  test ":verify attests an already-loaded module without loading code" do
    dir = Path.join(System.tmp_dir!(), "pkg-ver-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)

    # The entry names a module that IS already compiled in this BEAM (the mix-dep
    # case); the dir carries the notarized bytes it was compiled from.
    write!(Path.join(dir, "swarm-object.json"), Jason.encode!(%{module: "Genswarms.Packages.Dirhash"}))
    {:ok, digest} = Dirhash.hash_dir(dir)

    assert {:ok, Genswarms.Packages.Dirhash} =
             Loader.resolve_handler(%{ref: "r", digest: digest, path: dir, mode: :verify})
  end

  test ":verify fails when the entry module is not loaded (never invents one)" do
    dir = Path.join(System.tmp_dir!(), "pkg-ver2-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)
    write!(Path.join(dir, "swarm-object.json"), Jason.encode!(%{module: "No.Such.Module.Anywhere"}))
    {:ok, digest} = Dirhash.hash_dir(dir)

    assert {:error, {:entry_module_not_loaded, _}} =
             Loader.resolve_handler(%{ref: "r", digest: digest, path: dir, mode: :verify})
  end

  test "unsafe entry file paths are rejected" do
    dir = Path.join(System.tmp_dir!(), "pkg-unsafe-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)
    write!(Path.join(dir, "swarm-object.json"), Jason.encode!(%{module: "X", files: ["../../evil.ex"]}))
    {:ok, digest} = Dirhash.hash_dir(dir)

    assert {:error, {:unsafe_entry_files, _}} =
             Loader.resolve_handler(%{ref: "r", digest: digest, path: dir, mode: :require})
  end
end
