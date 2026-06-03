defmodule SubzeroclawSwarmWeb.Plugs.ReadAuth do
  @moduledoc """
  Read-only bearer auth for the dashboard's read endpoints. If `DASHBOARD_API_TOKEN`
  is set, requires `Authorization: Bearer <token>`; if unset, allows (localhost dev).
  Scoped to READ routes only — it must never be attached to mutating routes.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case System.get_env("DASHBOARD_API_TOKEN") do
      nil ->
        conn

      "" ->
        conn

      token ->
        case get_req_header(conn, "authorization") do
          ["Bearer " <> ^token] -> conn
          _ -> conn |> send_resp(401, ~s({"error":"unauthorized"})) |> halt()
        end
    end
  end
end
