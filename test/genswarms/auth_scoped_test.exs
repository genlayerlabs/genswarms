defmodule Genswarms.AuthScopedTest do
  # Application env is global state — serialize
  use ExUnit.Case, async: false

  alias Genswarms.Auth

  @loopback {127, 0, 0, 1}
  @remote {203, 0, 113, 7}

  setup do
    on_exit(fn ->
      Application.delete_env(:genswarms, :api_token)
      Application.delete_env(:genswarms, :config_api_token)
    end)
  end

  defp put_tokens(full, config) do
    if full, do: Application.put_env(:genswarms, :api_token, full)
    if config, do: Application.put_env(:genswarms, :config_api_token, config)
  end

  test "config token authorizes the :config scope only — NEVER :full" do
    put_tokens("full-secret", "config-secret")

    assert Auth.authorize_scoped(:config, "config-secret", @remote) == :ok
    # the critical property: config token must not unlock the control plane
    assert Auth.authorize_scoped(:full, "config-secret", @remote) == {:error, :unauthorized}
    assert Auth.authorize_scoped(:full, "config-secret", @loopback) == {:error, :unauthorized}
  end

  test "full token authorizes both scopes" do
    put_tokens("full-secret", "config-secret")

    assert Auth.authorize_scoped(:full, "full-secret", @remote) == :ok
    assert Auth.authorize_scoped(:config, "full-secret", @remote) == :ok
  end

  test "wrong or missing token is refused in both scopes when any token is set" do
    put_tokens("full-secret", "config-secret")

    for scope <- [:full, :config], presented <- ["nope", nil] do
      assert Auth.authorize_scoped(scope, presented, @remote) == {:error, :unauthorized}
    end
  end

  test "only the config token configured: :config gated by it, :full stays loopback-only" do
    put_tokens(nil, "config-secret")

    assert Auth.authorize_scoped(:config, "config-secret", @remote) == :ok
    assert Auth.authorize_scoped(:config, "nope", @remote) == {:error, :unauthorized}
    # no FULL token configured → the control plane keeps the loopback-only rule
    assert Auth.authorize_scoped(:full, nil, @loopback) == :ok
    assert Auth.authorize_scoped(:full, "config-secret", @remote) == {:error, :token_required}
  end

  test "no tokens configured: loopback-only everywhere (unchanged behavior)" do
    for scope <- [:full, :config] do
      assert Auth.authorize_scoped(scope, nil, @loopback) == :ok
      assert Auth.authorize_scoped(scope, nil, @remote) == {:error, :token_required}
    end
  end
end
