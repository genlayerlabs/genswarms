defmodule Genswarms.Backends.Tmux.Adapter do
  @moduledoc """
  Client-specific contract for interactive coding TUIs hosted by tmux.

  Adapters own launch arguments and the small amount of screen recognition
  needed for startup/blocked-state diagnostics. Durable turn completion does
  not depend on screen scraping: the session worker watches the per-turn
  receipt described in the generated task file.
  """

  @type launch :: %{
          required(:executable) => String.t(),
          required(:args) => [String.t()],
          optional(:env) => [{String.t(), String.t()}]
        }

  @callback client() :: atom()
  @callback launch(map()) :: {:ok, launch()} | {:error, term()}
  @callback ready?(String.t(), map()) :: boolean()
  @callback blocked?(String.t(), map()) :: boolean()
  @callback nudge(map(), map()) :: String.t()
end

defmodule Genswarms.Backends.Tmux.Adapters do
  @moduledoc false

  alias Genswarms.Backends.Tmux.Adapters.{Claude, Codex, OpenCode}

  @known %{
    codex: Codex,
    claude: Claude,
    opencode: OpenCode
  }

  @spec resolve(atom() | String.t()) :: {:ok, module()} | {:error, term()}
  def resolve(client) when is_binary(client) do
    case client do
      "codex" -> {:ok, Codex}
      "claude" -> {:ok, Claude}
      "opencode" -> {:ok, OpenCode}
      _ -> {:error, {:unsupported_tmux_client, client}}
    end
  end

  def resolve(client) when is_atom(client) do
    case Map.fetch(@known, client) do
      {:ok, module} -> {:ok, module}
      :error -> resolve_module(client)
    end
  end

  def resolve(other), do: {:error, {:unsupported_tmux_client, other}}

  @spec known_client?(term()) :: boolean()
  def known_client?(client) when is_binary(client), do: client in ~w(codex claude opencode)
  def known_client?(client) when is_atom(client), do: Map.has_key?(@known, client)
  def known_client?(_), do: false

  defp resolve_module(module) do
    if Code.ensure_loaded?(module) and
         function_exported?(module, :client, 0) and
         function_exported?(module, :launch, 1) and
         function_exported?(module, :ready?, 2) and
         function_exported?(module, :blocked?, 2) and
         function_exported?(module, :nudge, 2) do
      {:ok, module}
    else
      {:error, {:unsupported_tmux_client, module}}
    end
  end
end

defmodule Genswarms.Backends.Tmux.AdapterHelpers do
  @moduledoc false

  @blocked_patterns [
    ~r/do you trust/i,
    ~r/trust (?:this )?(?:workspace|folder|project)/i,
    ~r/permission (?:required|request)/i,
    ~r/allow (?:this )?(?:command|tool|action)/i,
    ~r/would you like to (?:run|allow|proceed)/i
  ]

  def executable(config, default) do
    case Map.get(config, :executable_scope, :host) do
      :runtime ->
        Genswarms.Backends.Tmux.RunnerHelpers.runtime_executable(config, default)

      _ ->
        Genswarms.Backends.Tmux.RunnerHelpers.resolve_host_executable(
          config,
          :executable,
          default
        )
    end
  end

  def extra_args(config) do
    case Map.get(config, :args, []) do
      args when is_list(args) ->
        if Enum.all?(args, &is_binary/1),
          do: {:ok, args},
          else: {:error, {:invalid_tmux_args, args}}

      other ->
        {:error, {:invalid_tmux_args, other}}
    end
  end

  def blocked?(snapshot) when is_binary(snapshot) do
    Enum.any?(@blocked_patterns, &Regex.match?(&1, snapshot))
  end

  def prompt_visible?(snapshot, extra_patterns \\ []) when is_binary(snapshot) do
    default_patterns = [
      ~r/(?:^|\n)\s*[›❯>]\s*(?=\n|$)/u,
      ~r/(?:^|\n)\s*[›❯]\s+\S[^\n]*(?=\n|$)/u,
      ~r/(?:^|\n)\s*(?:what would you like|how can i help).*$/iu
    ]

    Enum.any?(default_patterns ++ extra_patterns, &Regex.match?(&1, snapshot))
  end

  def nudge(%{id: id, runtime_task_path: task_path}, _config) do
    "GenSwarms turn #{id}: read and execute `#{task_path}`"
  end

  def nudge(%{id: id, task_path: task_path}, _config) do
    "GenSwarms turn #{id}: read and execute `#{task_path}`"
  end

  def maybe_model(args, config, flag \\ "--model") do
    case Map.get(config, :model) do
      model when is_binary(model) and model != "" -> args ++ [flag, model]
      _ -> args
    end
  end
end
