defmodule Genswarms.E2E.RejectObject do
  @moduledoc """
  Init rejects any config carrying `bad: true` — for the overlay rollback e2e:
  a patch that init refuses must roll back and leave the old object alive.
  Keeps `n` so we can see which config actually took.
  """

  def init(config) do
    if cfg(config, :bad, false) in [true, "true"] do
      {:error, :rejected_by_init}
    else
      {:ok, %{n: cfg(config, :n, 0)}}
    end
  end

  def interface, do: %{noop: %{input: "{}", output: "{}"}}
  def handle_message(_from, _content, state), do: {:noreply, state}

  defp cfg(config, key, default),
    do: Map.get(config, key, Map.get(config, to_string(key), default))
end
