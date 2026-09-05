defmodule Genswarms.Config.LoaderEnvTest do
  use ExUnit.Case, async: false

  alias Genswarms.Config.Loader

  setup do
    dir =
      Path.join(System.tmp_dir!(), "loader-env-#{Base.encode16(:crypto.strong_rand_bytes(12))}")

    File.mkdir_p!(dir)
    key = "GENSWARMS_LOADER_ENV_REGRESSION"
    previous_value = System.get_env(key)
    previous_setting = Application.fetch_env(:genswarms, :load_dotenv)
    System.delete_env(key)
    File.write!(Path.join(dir, ".env"), "#{key}=fixture\n")
    path = Path.join(dir, "swarm.json")
    File.write!(path, Jason.encode!(%{name: "env-fixture", agents: []}))

    on_exit(fn ->
      case previous_value do
        nil -> System.delete_env(key)
        value -> System.put_env(key, value)
      end

      case previous_setting do
        :error -> Application.delete_env(:genswarms, :load_dotenv)
        {:ok, value} -> Application.put_env(:genswarms, :load_dotenv, value)
      end

      File.rm_rf!(dir)
    end)

    %{key: key, path: path}
  end

  test "loading a swarm respects disabled dotenv", %{key: key, path: path} do
    Application.put_env(:genswarms, :load_dotenv, false)
    assert {:ok, _} = Loader.load(path)
    assert System.get_env(key) == nil
  end

  test "dotenv remains enabled by default for normal callers", %{key: key, path: path} do
    Application.delete_env(:genswarms, :load_dotenv)
    assert {:ok, _} = Loader.load(path)
    assert System.get_env(key) == "fixture"
  end
end
