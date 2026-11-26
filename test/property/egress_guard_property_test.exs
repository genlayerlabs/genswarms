defmodule Genswarms.Property.EgressGuardPropertyTest do
  @moduledoc """
  Rule: an isolated agent's forwarder is only ever pinned to an allowlisted
  host and port, and the host that was checked is the host socat connects to.
  """
  use ExUnit.Case
  use ExUnitProperties

  # Long runs (PROPERTY_RUNS) outlast the default 60s per test.
  @moduletag timeout: :infinity

  alias Genswarms.Backends.EgressGuard

  # The operator endpoint's host (port 443 only), a bare-host entry (any port),
  # and a host:port entry (port 8443 only).
  @operator "llm.allowed.test"
  @any_port "second.allowed.test"
  @pinned "third.allowed.test"
  @allowed [@operator, @any_port, @pinned]

  setup do
    saved =
      for key <- ~w(SUBZEROCLAW_ENDPOINT GENSWARMS_ALLOWED_ENDPOINTS),
          do: {key, System.get_env(key)}

    System.put_env("SUBZEROCLAW_ENDPOINT", "https://#{@operator}/v1/chat")
    System.put_env("GENSWARMS_ALLOWED_ENDPOINTS", "#{@any_port}, #{@pinned}:8443")

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

  defp scheme, do: member_of(["http", "https"])

  # {scheme, ":port" | ""} for any port.
  defp any_port, do: {scheme(), one_of([constant(""), map(integer(1..65_535), &":#{&1}")])}

  # {scheme, ":port" | ""} spellings that mean exactly `port`.
  defp exact_port(port) do
    one_of(
      [{scheme(), constant(":#{port}")}] ++
        for(
          {s, default} <- [{"http", 80}, {"https", 443}],
          default == port,
          do: constant({s, ""})
        )
    )
  end

  # {scheme, ":port" | ""} spellings that mean any port except `port`.
  defp other_port(port) do
    one_of(
      [{scheme(), map(filter(integer(1..65_535), &(&1 != port)), &":#{&1}")}] ++
        for(
          {s, default} <- [{"http", 80}, {"https", 443}],
          default != port,
          do: constant({s, ""})
        )
    )
  end

  defp url(host_gen, scheme_port \\ any_port()) do
    gen all(
          {scheme, port} <- scheme_port,
          userinfo <-
            one_of([constant(""), map(one_of([label(), member_of(@allowed)]), &"#{&1}@")]),
          host <- host_gen,
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

  property "an allowlisted host and port is accepted and is what socat connects to" do
    check all(
            {endpoint, host} <-
              one_of([
                url(mixed_case(@operator), exact_port(443)),
                url(mixed_case(@pinned), exact_port(8443)),
                url(mixed_case(@any_port))
              ])
          ) do
      assert {:ok, ^endpoint} = EgressGuard.resolve_allowed_endpoint(%{endpoint: endpoint})
      assert {:ok, {connect_host, _port}} = EgressGuard.endpoint_target(endpoint)
      assert String.downcase(connect_host) == String.downcase(host)
    end
  end

  property "the operator's host on any other port is refused" do
    check all({endpoint, _host} <- url(mixed_case(@operator), other_port(443))) do
      assert {:error, {:endpoint_not_allowed, ^endpoint}} =
               EgressGuard.resolve_allowed_endpoint(%{endpoint: endpoint})
    end
  end

  property "a host:port entry refuses every other port" do
    check all({endpoint, _host} <- url(mixed_case(@pinned), other_port(8443))) do
      assert {:error, {:endpoint_not_allowed, ^endpoint}} =
               EgressGuard.resolve_allowed_endpoint(%{endpoint: endpoint})
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

  test "the operator's host on a different port is refused" do
    # Operator runs a local model; the orchestrator API is on the same host.
    System.put_env("SUBZEROCLAW_ENDPOINT", "http://localhost:11434/v1/chat")

    assert {:error, _} =
             EgressGuard.resolve_allowed_endpoint(%{
               endpoint: "http://localhost:4000/api/swarms"
             })
  end
end
