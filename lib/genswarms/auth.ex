defmodule Genswarms.Auth do
  @moduledoc """
  Authorization policy for the GenSwarms HTTP REST + WebSocket API.

  Policy:

    * If an API token is configured (`GENSWARMS_API_TOKEN`), every request must
      present a matching `Bearer` token, compared in constant time.
    * If no token is configured, only loopback (localhost) callers are allowed;
      remote callers are refused. This keeps a server from ever being silently
      open to the network — set a token to expose it beyond localhost.

  The decision logic lives in `authorize/3` as a pure function so it can be
  shared by `GenswarmsWeb.Plugs.ApiAuth` (REST) and `GenswarmsWeb.SwarmSocket`
  (WebSocket) and tested exhaustively without HTTP plumbing.
  """

  @type ip :: :inet.ip_address() | nil
  @type reason :: :unauthorized | :token_required

  @doc """
  Returns the configured API token, or `nil` if unset or blank.
  """
  @spec configured_token() :: String.t() | nil
  def configured_token do
    case Application.get_env(:genswarms, :api_token) do
      token when is_binary(token) and token != "" -> token
      _ -> nil
    end
  end

  @doc """
  Returns the configured CONFIG-scoped API token (`GENSWARMS_CONFIG_API_TOKEN`),
  or `nil` if unset or blank.

  A deliberately narrow grant for config tooling (the dashboard configurator):
  it authorizes ONLY the `:config` route scope — schema-gated object config
  PATCHes and the overlay audit trail — never the full control plane
  (create/delete swarms, add agents, route messages). A host can hand this
  token to a configurator UI without reopening the whole mutating API; even
  if it leaks, the blast radius is the `x-mutable` tuning surface each
  package declared (host-escape keys are rejected by the op gate regardless).
  """
  @spec configured_config_token() :: String.t() | nil
  def configured_config_token do
    case Application.get_env(:genswarms, :config_api_token) do
      token when is_binary(token) and token != "" -> token
      _ -> nil
    end
  end

  @doc """
  Scope-aware authorization.

    * `:full` — exactly `authorize/3` with the full token; the config token
      plays NO part (it must never unlock the control plane).
    * `:config` — a presented token matching EITHER the full token or the
      config token authorizes. With neither token configured, the
      loopback-only rule applies, same as everywhere else.
  """
  @spec authorize_scoped(:full | :config, String.t() | nil, ip()) :: :ok | {:error, reason()}
  def authorize_scoped(:full, presented, remote_ip),
    do: authorize(configured_token(), presented, remote_ip)

  def authorize_scoped(:config, presented, remote_ip) do
    full = configured_token()
    config = configured_config_token()

    cond do
      is_nil(full) and is_nil(config) -> authorize(nil, presented, remote_ip)
      is_binary(presented) and matches?(full, presented) -> :ok
      is_binary(presented) and matches?(config, presented) -> :ok
      true -> {:error, :unauthorized}
    end
  end

  defp matches?(configured, presented) when is_binary(configured) and configured != "",
    do: Plug.Crypto.secure_compare(configured, presented)

  defp matches?(_, _), do: false

  @doc """
  Decides whether a request is authorized.

    * `configured` — the configured token, or `nil`/`""` if none.
    * `presented` — the token the caller presented, or `nil`.
    * `remote_ip` — the caller's IP tuple, or `nil`.

  Returns `:ok`, `{:error, :unauthorized}` (token configured but wrong/missing),
  or `{:error, :token_required}` (no token configured and caller is non-local).
  """
  @spec authorize(String.t() | nil, String.t() | nil, ip()) :: :ok | {:error, reason()}
  def authorize(configured, presented, remote_ip)

  def authorize(configured, presented, _remote_ip)
      when is_binary(configured) and configured != "" do
    if is_binary(presented) and Plug.Crypto.secure_compare(configured, presented) do
      :ok
    else
      {:error, :unauthorized}
    end
  end

  def authorize(_configured, _presented, remote_ip) do
    if loopback?(remote_ip), do: :ok, else: {:error, :token_required}
  end

  @doc """
  True if `ip` is an IPv4 (127.0.0.0/8) or IPv6 (`::1`, IPv4-mapped) loopback.
  """
  @spec loopback?(ip()) :: boolean()
  def loopback?({127, _, _, _}), do: true
  def loopback?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  # IPv4-mapped IPv6 loopback, e.g. ::ffff:127.0.0.1
  def loopback?({0, 0, 0, 0, 0, 0xFFFF, 0x7F00, _}), do: true
  def loopback?(_), do: false
end
