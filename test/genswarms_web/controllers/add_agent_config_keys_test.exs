defmodule GenswarmsWeb.AddAgentConfigKeysTest do
  @moduledoc """
  Defense-in-depth: the dynamic add_agent API must reject host-escape backend
  config keys (extra_ro_binds, extra_rw_binds, extra_path, subzeroclaw_path) so a
  caller cannot mount host paths or run an arbitrary binary inside an agent
  sandbox via config. Safe/domain keys pass through.
  """
  use ExUnit.Case, async: false

  import Phoenix.ConnTest

  alias GenswarmsWeb.SwarmController

  defp add_agent(config) do
    params = %{"swarm_name" => "__no_such_swarm__", "name" => "a1", "config" => config}
    build_conn() |> SwarmController.add_agent(params)
  end

  defp error(conn), do: Jason.decode!(conn.resp_body)["error"]

  test "rejects extra_ro_binds" do
    conn = add_agent(%{"extra_ro_binds" => [["/", "/host"]]})
    assert conn.status == 400
    assert error(conn) == "Disallowed config keys: extra_ro_binds"
  end

  test "rejects subzeroclaw_path" do
    conn = add_agent(%{"subzeroclaw_path" => "/bin/sh"})
    assert conn.status == 400
    assert error(conn) == "Disallowed config keys: subzeroclaw_path"
  end

  test "rejects extra_path and extra_rw_binds" do
    conn = add_agent(%{"extra_path" => ["/evil/bin"], "extra_rw_binds" => [["/etc", "/etc"]]})
    assert conn.status == 400
    # Sorted, comma-joined.
    assert error(conn) == "Disallowed config keys: extra_path, extra_rw_binds"
  end

  test "lists every disallowed key present, sorted and de-duplicated" do
    conn =
      add_agent(%{
        "subzeroclaw_path" => "/x",
        "extra_path" => ["/y"],
        "extra_ro_binds" => [],
        "population_size" => 10
      })

    assert conn.status == 400
    assert error(conn) == "Disallowed config keys: extra_path, extra_ro_binds, subzeroclaw_path"
  end

  test "allows safe domain and resource keys (passes the key check)" do
    conn = add_agent(%{"memory_limit" => "256M", "population_size" => 10, "max_iterations" => 50})

    # Past the key check; only the missing swarm fails it.
    assert conn.status == 400
    assert error(conn) != "Disallowed config keys: "
    refute error(conn) =~ "Disallowed config keys"
    assert error(conn) =~ "swarm_not_found"
  end

  test "allows an empty / absent config" do
    conn = add_agent(%{})
    assert conn.status == 400
    refute error(conn) =~ "Disallowed config keys"
  end
end
