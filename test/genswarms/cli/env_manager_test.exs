defmodule Genswarms.CLI.EnvManagerTest do
  @moduledoc """
  .env auto-discovery must not walk above the project root, and load must not
  overwrite already-set environment variables (audit finding 35).
  """
  use ExUnit.Case, async: false

  alias Genswarms.CLI.EnvManager

  import ExUnit.CaptureIO

  setup do
    root = Path.join(System.tmp_dir!(), "envmgr_#{System.unique_integer([:positive])}")
    proj = Path.join(root, "proj")
    sub = Path.join(proj, "sub")
    File.mkdir_p!(sub)
    File.write!(Path.join(proj, "mix.exs"), "# marker")

    on_exit(fn -> File.rm_rf(root) end)
    {:ok, root: root, proj: proj, sub: sub}
  end

  describe "find_env_file/2 (project-root boundary)" do
    test "does not load a .env above the project root", %{root: root, sub: sub} do
      File.write!(Path.join(root, ".env"), "X=1")
      assert :not_found = EnvManager.find_env_file(sub, 5)
    end

    test "finds a .env inside the project (walking up to the root)", %{proj: proj, sub: sub} do
      env = Path.join(proj, ".env")
      File.write!(env, "X=1")
      assert {:ok, ^env} = EnvManager.find_env_file(sub, 5)
    end

    test "finds a .env in the start directory itself", %{sub: sub} do
      env = Path.join(sub, ".env")
      File.write!(env, "X=1")
      assert {:ok, ^env} = EnvManager.find_env_file(sub, 5)
    end
  end

  describe "load/1 (no overwrite)" do
    test "does not overwrite an already-set variable", %{proj: proj} do
      var = "ENVMGR_TEST_#{System.unique_integer([:positive])}"
      System.put_env(var, "from-shell")
      on_exit(fn -> System.delete_env(var) end)

      env = Path.join(proj, ".env")
      File.write!(env, "#{var}=from-dotenv")

      assert {:ok, applied} = EnvManager.load(env)
      assert applied == 0
      assert System.get_env(var) == "from-shell"
    end

    test "sets variables that are not already present", %{proj: proj} do
      var = "ENVMGR_NEW_#{System.unique_integer([:positive])}"
      System.delete_env(var)
      on_exit(fn -> System.delete_env(var) end)

      env = Path.join(proj, ".env")
      File.write!(env, "#{var}=value")

      assert {:ok, 1} = EnvManager.load(env)
      assert System.get_env(var) == "value"
    end
  end

  describe "load_for_cli/0" do
    test "loads a discovered file and prints only its path", %{proj: proj, sub: sub} do
      var = "ENVMGR_CLI_#{System.unique_integer([:positive])}"
      on_exit(fn -> System.delete_env(var) end)
      env = Path.join(proj, ".env")
      File.write!(env, "#{var}=value")

      File.cd!(sub, fn ->
        expected_path = Path.join(Path.dirname(File.cwd!()), ".env")
        output = capture_io(fn -> assert :ok = EnvManager.load_for_cli() end)
        assert output == "[Genswarms] Loaded environment from #{expected_path}\n"
      end)

      assert System.get_env(var) == "value"
    end

    test "stays silent when no environment file is found", %{sub: sub} do
      assert File.cd!(sub, fn -> capture_io(fn -> assert :ok = EnvManager.load_for_cli() end) end) ==
               ""
    end
  end
end
