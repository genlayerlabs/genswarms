defmodule Genswarms.Backends.Tmux.Runners.Host do
  @moduledoc false

  @behaviour Genswarms.Backends.Tmux.Runner

  defstruct [:workspace]

  @impl true
  def configure(config) do
    case Map.get(config, :network, :open) do
      value when value in [:open, "open", nil] ->
        {:ok,
         config
         |> Map.put(:runner_kind, :host)
         |> Map.put(:client_source, :host)
         |> Map.put(:runtime_workspace, Map.fetch!(config, :workspace))
         |> Map.put(:runtime_skills_dir, Map.get(config, :skills_dir, ""))
         |> Map.put(:executable_scope, :host)}

      value when value in [:isolated, "isolated"] ->
        {:error, {:unsupported_network, :isolated}}

      value ->
        {:error, {:unsupported_host_network, value}}
    end
  end

  @impl true
  def prepare(config, launch, _pane_state) do
    {:ok, %__MODULE__{workspace: config.workspace}, launch}
  end

  @impl true
  def destroy(%__MODULE__{}), do: :ok

  @impl true
  def health_check(%__MODULE__{}), do: :ok

  @impl true
  def session_info(%__MODULE__{}) do
    %{kind: :host, filesystem_isolation: false, process_isolation: false, network: :host}
  end
end
