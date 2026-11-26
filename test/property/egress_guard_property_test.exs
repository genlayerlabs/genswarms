defmodule Genswarms.Property.EgressGuardPropertyTest do
  @moduledoc """
  Rule: an isolated agent's forwarder is only ever pinned to an allowlisted
  host, and the host that was checked is the host socat connects to.
  """
  use ExUnit.Case
  use ExUnitProperties

  # Long runs (PROPERTY_RUNS) outlast the default 60s per test.
  @moduletag timeout: :infinity

  alias Genswarms.Backends.EgressGuard

  @allowed ["llm.allowed.test", "second.allowed.test"]

  setup do
    saved =
      for key <- ~w(SUBZEROCLAW_ENDPOINT GENSWARMS_ALLOWED_ENDPOINTS),
          do: {key, System.get_env(key)}

    System.put_env("SUBZEROCLAW_ENDPOINT", "https://llm.allowed.test/v1/chat")
    System.put_env("GENSWARMS_ALLOWED_ENDPOINTS", "second.allowed.test")

    on_exit(fn ->
      for {key, value} <- saved do
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end
    end)
  end

  defp label, do: string([?a..?z, ?0..?9], min_length: 1, max_length: 8)

  # Hosts that are not allowed but try to look like it.
  defp evil_host do
    one_of([
      map(label(), &"#{&1}.evil.test"),
      map(member_of(@allowed), &"#{&1}.evil.test"),
      map(member_of(@allowed), &"evil-#{&1}"),
      map(member_of(@allowed), &"#{&1}."),
      map({label(), member_of(@allowed)}, fn {l, a} -> "#{l}.#{a}" end),
      constant("127.0.0.1"),
      constant("localhost")
    ])
  end

  defp url(host_gen) do
    gen all(
          scheme <- member_of(["http", "https"]),
          userinfo <-
            one_of([constant(""), map(one_of([label(), member_of(@allowed)]), &"#{&1}@")]),
          host <- host_gen,
          port <- one_of([constant(""), map(integer(1..65_535), &":#{&1}")]),
          path <- one_of([constant(""), map(one_of([label(), member_of(@allowed)]), &"/#{&1}")]),
          query <- one_of([constant(""), map(member_of(@allowed), &"?u=https://#{&1}/")])
        ) do
      {"#{scheme}://#{userinfo}#{host}#{port}#{path}#{query}", host}
    end
  end

  defp mixed_case(host) do
    map(list_of(boolean(), length: String.length(host)), fn flips ->
      host
      |> String.graphemes()
      |> Enum.zip(flips)
      |> Enum.map_join(fn {char, up?} -> if up?, do: String.upcase(char), else: char end)
    end)
  end

  property "a per-agent endpoint on any other host is refused" do
    check all({endpoint, _host} <- url(evil_host())) do
      assert {:error, {:endpoint_not_allowed, ^endpoint}} =
               EgressGuard.resolve_allowed_endpoint(%{endpoint: endpoint})
    end
  end

  property "an allowlisted host is accepted and is the host socat connects to" do
    check all({endpoint, host} <- url(bind(member_of(@allowed), &mixed_case/1))) do
      assert {:ok, ^endpoint} = EgressGuard.resolve_allowed_endpoint(%{endpoint: endpoint})
      assert {:ok, {connect_host, _port}} = EgressGuard.endpoint_target(endpoint)
      assert String.downcase(connect_host) == String.downcase(host)
    end
  end

  property "anything that is not a URL string is refused" do
    check all(
            endpoint <-
              one_of([
                integer(),
                boolean(),
                binary(max_length: 20),
                string(:printable, max_length: 20)
              ])
          ) do
      case EgressGuard.resolve_allowed_endpoint(%{endpoint: endpoint}) do
        {:error, _} ->
          :ok

        {:ok, ^endpoint} ->
          {:ok, {host, _port}} = EgressGuard.endpoint_target(endpoint)
          assert String.downcase(host) in @allowed
      end
    end
  end

  test "no per-agent endpoint means the operator endpoint" do
    assert {:ok, "https://llm.allowed.test/v1/chat"} = EgressGuard.resolve_allowed_endpoint(%{})
  end

  describe "known bugs" do
    @describetag :known_bug

    test "an allowed host on a different port is refused" do
      # Operator runs a local model; the orchestrator API is on the same host.
      System.put_env("SUBZEROCLAW_ENDPOINT", "http://localhost:11434/v1/chat")

      assert {:error, _} =
               EgressGuard.resolve_allowed_endpoint(%{
                 endpoint: "http://localhost:4000/api/swarms"
               })
    end
  end
end
