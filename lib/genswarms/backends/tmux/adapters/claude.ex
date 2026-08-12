defmodule Genswarms.Backends.Tmux.Adapters.Claude do
  @moduledoc "Adapter for the persistent Claude Code interactive CLI."

  @behaviour Genswarms.Backends.Tmux.Adapter

  alias Genswarms.Backends.Tmux.AdapterHelpers, as: Helpers

  @permission_modes ~w(acceptEdits auto manual dontAsk plan bypassPermissions)
  @efforts ~w(low medium high xhigh max)

  @impl true
  def client, do: :claude

  @impl true
  def launch(config) do
    with {:ok, executable} <- Helpers.executable(config, "claude"),
         {:ok, extra_args} <- Helpers.extra_args(config),
         {:ok, mode_args} <- permission_args(config),
         {:ok, effort_args} <- effort_args(config),
         {:ok, resume_args} <- resume_args(config) do
      display_name = "#{Map.fetch!(config, :swarm_name)}-#{Map.fetch!(config, :agent_name)}"
      base = ["--ax-screen-reader", "--name", display_name]

      args =
        base
        |> Helpers.maybe_model(config, "--model")
        |> Kernel.++(mode_args ++ effort_args ++ extra_args ++ resume_args)

      {:ok, %{executable: executable, args: args, env: []}}
    end
  end

  @impl true
  def ready?(snapshot, _config), do: Helpers.prompt_visible?(snapshot)

  @impl true
  def blocked?(snapshot, _config), do: Helpers.blocked?(snapshot)

  @impl true
  def nudge(turn, config), do: Helpers.nudge(turn, config)

  defp permission_args(config) do
    value = Map.get(config, :permission_mode)
    normalized = normalize_option(value)

    cond do
      Map.get(config, :dangerously_bypass) == true ->
        {:ok, ["--dangerously-skip-permissions"]}

      is_nil(normalized) ->
        {:ok, []}

      normalized in @permission_modes ->
        {:ok, ["--permission-mode", normalized]}

      true ->
        {:error, {:invalid_permission_mode, value}}
    end
  end

  defp effort_args(config) do
    value = Map.get(config, :effort)
    normalized = normalize_option(value)

    cond do
      is_nil(normalized) -> {:ok, []}
      normalized in @efforts -> {:ok, ["--effort", normalized]}
      true -> {:error, {:invalid_effort, value}}
    end
  end

  defp resume_args(config) do
    case Map.get(config, :resume) do
      value when value in [nil, false] -> {:ok, []}
      true -> {:ok, ["--continue"]}
      session when is_binary(session) and session != "" -> {:ok, ["--resume", session]}
      other -> {:error, {:invalid_resume, other}}
    end
  end

  defp normalize_option(nil), do: nil
  defp normalize_option(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_option(value), do: value
end
