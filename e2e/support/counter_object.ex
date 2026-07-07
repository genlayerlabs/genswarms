defmodule Genswarms.E2E.CounterObject do
  @moduledoc """
  Counts messages by action, for deterministic e2e (scheduling, routing) with
  no LLM. `received` totals everything; `by_action` breaks it down.
  """

  def init(_config), do: {:ok, %{received: 0, by_action: %{}, last_from: nil}}

  def interface, do: %{tick: %{input: ~s({"action":"tick"}), output: "counted"}}

  def handle_message(from, content, state) do
    action =
      case Jason.decode(content) do
        {:ok, %{"action" => a}} -> to_string(a)
        _ -> "unknown"
      end

    {:noreply,
     %{
       state
       | received: state.received + 1,
         by_action: Map.update(state.by_action, action, 1, &(&1 + 1)),
         last_from: from
     }}
  end
end
