defmodule Genswarms.Backends.Tmux.Adapters.OpenCode do
  @moduledoc "Adapter for the persistent OpenCode interactive CLI."

  @behaviour Genswarms.Backends.Tmux.Adapter

  alias Genswarms.Backends.Tmux.AdapterHelpers, as: Helpers

  @impl true
  def client, do: :opencode

  @impl true
  def launch(config) do
    with {:ok, executable} <- Helpers.executable(config, "opencode"),
         {:ok, extra_args} <- Helpers.extra_args(config),
         {:ok, resume_args} <- resume_args(config) do
      base = ["--mini"]
      base = if Map.get(config, :auto_approve) == true, do: base ++ ["--auto"], else: base

      args =
        base
        |> Helpers.maybe_model(config, "--model")
        |> Kernel.++(extra_args ++ resume_args)

      {:ok, %{executable: executable, args: args, env: []}}
    end
  end

  @impl true
  def ready?(snapshot, _config) do
    Helpers.prompt_visible?(snapshot) or
      (Regex.match?(~r/(?:^|\n)\s*Ask anything\.\.\.[^\n]*(?:\n|$)/u, snapshot) and
         Regex.match?(~r/(?:^|\n)\s*(?:BUILD|PLAN)\s+[^\n]*ctrl\+p cmd\s*(?:\n|$)/u, snapshot))
  end

  @impl true
  def blocked?(snapshot, _config), do: Helpers.blocked?(snapshot)

  @impl true
  def nudge(turn, config), do: Helpers.nudge(turn, config)

  defp resume_args(config) do
    case Map.get(config, :resume) do
      value when value in [nil, false] -> {:ok, []}
      true -> {:ok, ["--continue"]}
      session when is_binary(session) and session != "" -> {:ok, ["--session", session]}
      other -> {:error, {:invalid_resume, other}}
    end
  end
end
