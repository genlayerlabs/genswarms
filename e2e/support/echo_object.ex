defmodule Genswarms.E2E.EchoObject do
  @moduledoc """
  Minimal object for the REAL e2e harness: replies to a `swarm-msg ask` and
  counts them, and carries one x-mutable field (`tag`) so the harness can
  exercise a real hot-patch overlay through the REST config gate.

  Deliberately tiny — the point is to exercise the ENGINE (ask reply path,
  overlay restart, snapshot consistency) with a real bwrap agent driving it,
  not to be a product.
  """

  def init(config) do
    {:ok, %{asks: 0, last: nil, tag: cfg(config, :tag, "base")}}
  end

  def interface do
    %{
      echo: %{
        input: ~s({"action":"echo","text":"hi"}),
        output: ~s({"ok":true,"echo":"hi","tag":"base","asks":1})
      }
    }
  end

  def handle_message(_from, content, state) do
    case Jason.decode(content) do
      {:ok, %{"action" => "echo", "text" => text}} ->
        s = %{state | asks: state.asks + 1, last: to_string(text)}
        {:reply, Jason.encode!(%{ok: true, echo: text, tag: state.tag, asks: s.asks}), s}

      _ ->
        {:noreply, state}
    end
  end

  defp cfg(config, key, default),
    do: Map.get(config, key, Map.get(config, to_string(key), default))
end
