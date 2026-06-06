defmodule Genswarms.Backends.EndpointPolicyTest do
  @moduledoc """
  The server-env SUBZEROCLAW_API_KEY must never be co-forwarded to an
  untrusted/custom endpoint (audit finding 28, CWE-918).
  """
  # async: false — manipulates process/system env vars.
  use ExUnit.Case, async: false

  alias Genswarms.Backends.EndpointPolicy

  @vars ~w(SUBZEROCLAW_API_KEY SUBZEROCLAW_ENDPOINT GENSWARMS_ALLOWED_ENDPOINTS)

  setup do
    saved = Map.new(@vars, fn v -> {v, System.get_env(v)} end)
    Enum.each(@vars, &System.delete_env/1)

    on_exit(fn ->
      Enum.each(saved, fn
        {v, nil} -> System.delete_env(v)
        {v, val} -> System.put_env(v, val)
      end)
    end)

    :ok
  end

  test "no endpoint: env key is forwarded (default behavior)" do
    System.put_env("SUBZEROCLAW_API_KEY", "sk-server")
    assert {nil, "sk-server"} = EndpointPolicy.resolve(%{})
  end

  test "custom per-agent endpoint WITHOUT allowlist: env key is withheld" do
    System.put_env("SUBZEROCLAW_API_KEY", "sk-server")
    assert {"http://attacker/v1", nil} = EndpointPolicy.resolve(%{endpoint: "http://attacker/v1"})
  end

  test "custom endpoint WITH an explicit config api_key: that key is used" do
    System.put_env("SUBZEROCLAW_API_KEY", "sk-server")

    assert {"http://attacker/v1", "sk-explicit"} =
             EndpointPolicy.resolve(%{endpoint: "http://attacker/v1", api_key: "sk-explicit"})
  end

  test "endpoint equal to the server's own SUBZEROCLAW_ENDPOINT is trusted" do
    System.put_env("SUBZEROCLAW_API_KEY", "sk-server")
    System.put_env("SUBZEROCLAW_ENDPOINT", "https://api.provider.com/v1")

    assert {"https://api.provider.com/v1", "sk-server"} =
             EndpointPolicy.resolve(%{endpoint: "https://api.provider.com/v1"})
  end

  test "an allowlisted host receives the env key; a non-allowlisted one does not" do
    System.put_env("SUBZEROCLAW_API_KEY", "sk-server")
    System.put_env("GENSWARMS_ALLOWED_ENDPOINTS", "api.openai.com, openrouter.ai")

    assert {"https://api.openai.com/v1", "sk-server"} =
             EndpointPolicy.resolve(%{endpoint: "https://api.openai.com/v1"})

    assert {"https://evil.example/v1", nil} =
             EndpointPolicy.resolve(%{endpoint: "https://evil.example/v1"})
  end

  test "no key configured anywhere yields nil key" do
    assert {nil, nil} = EndpointPolicy.resolve(%{})
    assert {"http://x/v1", nil} = EndpointPolicy.resolve(%{endpoint: "http://x/v1"})
  end

  test "trusted_endpoint?/2: nil endpoint is always trusted" do
    assert EndpointPolicy.trusted_endpoint?(nil, nil)
    assert EndpointPolicy.trusted_endpoint?(nil, "https://api.provider.com")
  end
end
