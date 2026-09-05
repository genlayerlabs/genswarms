defmodule Genswarms.Backends.Tmux.Adapters.Codex do
  @moduledoc "Adapter for the persistent Codex interactive CLI."

  @behaviour Genswarms.Backends.Tmux.Adapter

  alias Genswarms.Backends.Tmux.AdapterHelpers, as: Helpers

  @approval_policies ~w(on-request never)
  @sandboxes ~w(read-only workspace-write danger-full-access)

  @impl true
  def client, do: :codex

  @impl true
  def launch(config) do
    with {:ok, executable} <- Helpers.executable(config, "codex"),
         {:ok, extra_args} <- Helpers.extra_args(config),
         {:ok, args} <- permission_args(config),
         {:ok, resume_args} <- resume_args(config) do
      workspace = Map.get(config, :runtime_workspace, Map.fetch!(config, :workspace))
      base = ["--no-alt-screen", "-C", workspace]

      args =
        base
        |> Helpers.maybe_model(config, "--model")
        |> Kernel.++(args ++ extra_args ++ resume_args)

      {:ok, %{executable: executable, args: args, env: []}}
    end
  end

  @impl true
  def ready?(snapshot, _config), do: Helpers.prompt_visible?(snapshot)

  @impl true
  def blocked?(snapshot, _config), do: Helpers.blocked?(snapshot)

  @impl true
  def nudge(turn, config), do: Helpers.nudge(turn, config)

  defp permission_args(%{dangerously_bypass: true}),
    do: {:ok, ["--dangerously-bypass-approvals-and-sandbox"]}

  defp permission_args(config) do
    approval = config |> Map.get(:approval_policy) |> normalize_option()
    sandbox = config |> Map.get(:sandbox) |> normalize_option()

    cond do
      approval && approval not in @approval_policies ->
        {:error, {:invalid_approval_policy, approval}}

      sandbox && sandbox not in @sandboxes ->
        {:error, {:invalid_sandbox, sandbox}}

      true ->
        args = if approval, do: ["--ask-for-approval", approval], else: []
        args = if sandbox, do: args ++ ["--sandbox", sandbox], else: args
        {:ok, args}
    end
  end

  defp normalize_option(nil), do: nil

  defp normalize_option(value) when is_atom(value),
    do: value |> Atom.to_string() |> String.replace("_", "-")

  defp normalize_option(value) when is_binary(value), do: String.replace(value, "_", "-")
  defp normalize_option(value), do: value

  defp resume_args(config) do
    case Map.get(config, :resume) do
      value when value in [nil, false] -> {:ok, []}
      true -> {:ok, ["resume", "--last"]}
      session when is_binary(session) and session != "" -> {:ok, ["resume", session]}
      other -> {:error, {:invalid_resume, other}}
    end
  end
end
