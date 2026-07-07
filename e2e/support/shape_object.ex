defmodule Genswarms.E2E.ShapeObject do
  @moduledoc """
  Emits each ObjectHandler return shape on demand, so an e2e can assert the
  ENGINE routes them correctly:
    {"do":"send","to":"x"}   -> {:send, :x, msg, state}
    {"do":"broadcast"}       -> {:broadcast, msg, state}
    anything else            -> {:noreply, state}   (nothing routed)
  The forwarded message is {"action":"tick"} so a CounterObject target counts it.
  """

  def init(_config), do: {:ok, %{}}
  def interface, do: %{shape: %{input: ~s({"do":"send","to":"x"}), output: "routes the shape"}}

  def handle_message(_from, content, state) do
    tick = Jason.encode!(%{action: "tick"})

    case Jason.decode(content) do
      {:ok, %{"do" => "send", "to" => to}} -> {:send, String.to_atom(to), tick, state}
      {:ok, %{"do" => "broadcast"}} -> {:broadcast, tick, state}
      _ -> {:noreply, state}
    end
  end
end
