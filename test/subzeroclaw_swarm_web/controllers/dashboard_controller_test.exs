defmodule SubzeroclawSwarmWeb.DashboardControllerTest do
  use SubzeroclawSwarmWeb.ConnCase, async: false

  test "GET /dashboard returns 404 for unknown swarm", %{conn: conn} do
    conn = get(conn, "/api/swarms/does-not-exist/dashboard")
    assert json_response(conn, 404) == %{"error" => "swarm_not_found"}
  end

  test "401 when DASHBOARD_API_TOKEN set and no bearer", %{conn: conn} do
    System.put_env("DASHBOARD_API_TOKEN", "secret")
    on_exit(fn -> System.delete_env("DASHBOARD_API_TOKEN") end)
    conn = get(conn, "/api/swarms/x/dashboard")
    assert response(conn, 401)
  end

  test "session history returns unavailable for unknown swarm", %{conn: conn} do
    conn = get(conn, "/api/swarms/nope/sessions/tg:1:0/history")
    assert %{"source" => "unavailable", "turns" => []} = json_response(conn, 200)
  end
end
