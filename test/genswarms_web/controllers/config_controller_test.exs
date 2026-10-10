defmodule GenswarmsWeb.ConfigControllerTest do
  # not async: toggles global :api_token and dispatches through the router
  use ExUnit.Case, async: false

  import Plug.Test

  alias GenswarmsWeb.ConfigController

  setup do
    prev = Application.get_env(:genswarms, :api_token)
    # no token + loopback => auth allows the request through to the controller
    Application.delete_env(:genswarms, :api_token)

    on_exit(fn ->
      case prev do
        nil -> Application.delete_env(:genswarms, :api_token)
        v -> Application.put_env(:genswarms, :api_token, v)
      end
    end)

    :ok
  end

  defp post_validate(params) do
    %{conn(:post, "/api/config/validate", params) | remote_ip: {127, 0, 0, 1}}
    |> GenswarmsWeb.Router.call(GenswarmsWeb.Router.init([]))
  end

  test "rejects .exs request content with 400 and never executes it (RCE)" do
    marker = Path.join(System.tmp_dir!(), "cfg_ctrl_rce_#{System.unique_integer([:positive])}")
    File.rm(marker)
    content = ~s|File.write!(#{inspect(marker)}, "pwned"); %{name: "n", agents: []}|

    conn = post_validate(%{"content" => content, "format" => "exs"})

    assert conn.status == 400
    assert %{"valid" => false} = Jason.decode!(conn.resp_body)
    refute File.exists?(marker), "RCE: .exs request content was executed by the controller"
  end

  test "request config paths outside the operator config directory are rejected" do
    path =
      Path.join(System.tmp_dir!(), "config_request_#{System.unique_integer([:positive])}.json")

    name = "path_unknown_#{System.unique_integer([:positive])}"

    File.write!(
      path,
      Jason.encode!(%{name: "path-test", agents: [%{name: name, backend: "mock"}]})
    )

    on_exit(fn -> File.rm(path) end)

    conn = post_validate(%{"config_path" => path})
    assert conn.status == 400
    assert_raise ArgumentError, fn -> String.to_existing_atom(name) end
  end

  test "accepts a valid JSON content config" do
    content = ~s|{"name":"n","agents":[{"name":"a","backend":"local"}],"topology":[]}|
    conn = post_validate(%{"content" => content, "format" => "json"})

    assert conn.status == 200
    assert %{"valid" => true} = Jason.decode!(conn.resp_body)
  end

  test "validation of fresh names does not intern them or consume the dynamic budget" do
    before = Genswarms.Config.RequestNames.allocated()
    name = "validate_fresh_#{System.unique_integer([:positive])}"
    config = %{"name" => "validate-dynamic", "agents" => [%{"name" => name, "backend" => "mock"}]}

    for params <- [
          %{"config" => config},
          %{"content" => Jason.encode!(config), "format" => "json"}
        ] do
      conn = post_validate(params)
      assert conn.status == 200
      assert_raise ArgumentError, fn -> String.to_existing_atom(name) end
      assert Genswarms.Config.RequestNames.allocated() == before
    end
  end

  test "accepts Apple container scalar backend in JSON content" do
    content = ~s|{"name":"n","agents":[{"name":"a","backend":"apple_container"}],"topology":[]}|
    conn = post_validate(%{"content" => content, "format" => "json"})

    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert %{"valid" => true} = body
    assert [%{"backend" => "apple_container"}] = body["config"]["agents"]
  end

  test "formats Apple container tuple backends in config validation output" do
    conn =
      conn(:post, "/")
      |> ConfigController.validate(%{
        "config" => %{
          name: "n",
          agents: [%{name: :a, backend: {:apple_container, "img:tag"}}],
          topology: []
        }
      })

    assert conn.status in [200, nil]
    body = Jason.decode!(conn.resp_body)
    assert [%{"backend" => "apple_container:img:tag"}] = body["config"]["agents"]
  end
end
