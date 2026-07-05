defmodule GenswarmsWeb.Plugs.ApiAuth do
  @moduledoc """
  Authenticates REST API requests using `Genswarms.Auth`.

  Expects `Authorization: Bearer <token>` when a token is configured;
  otherwise allows loopback callers only. Responds `401` (JSON) and halts on
  failure.

  Scoping: `plug ApiAuth` guards with the FULL token (`GENSWARMS_API_TOKEN`,
  the whole control plane). `plug ApiAuth, scope: :config` additionally
  accepts the narrow `GENSWARMS_CONFIG_API_TOKEN` — the grant for config
  tooling (schema-gated object config PATCHes + the overlay audit trail),
  which never unlocks the full API.
  """

  @behaviour Plug
  import Plug.Conn

  @impl true
  def init(opts) when is_list(opts), do: Keyword.get(opts, :scope, :full)
  def init(_opts), do: :full

  @impl true
  def call(conn, scope) do
    case Genswarms.Auth.authorize_scoped(scope, bearer_token(conn), conn.remote_ip) do
      :ok ->
        conn

      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{error: message(reason)}))
        |> halt()
    end
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token | _] -> token
      _ -> nil
    end
  end

  defp message(:unauthorized), do: "Invalid or missing API token"

  defp message(:token_required),
    do:
      "API token required for non-local requests. Set GENSWARMS_API_TOKEN on the " <>
        "server and send 'Authorization: Bearer <token>'."
end
