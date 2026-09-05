defmodule Genswarms.IR.OpPolicy do
  @moduledoc """
  Security policy for *proposed* overlay ops — enforced by the single writer
  (§5.1) before an op is assigned a `seq` and folded into the log.

  `IR.Fold` checks an op's structural preconditions (names, edges, digest guard).
  This layer adds the resource/authority limits the audit hardened on the old
  REST mutation surface, now centralized at the single point every mutation
  funnels through instead of scattered across controllers:

    * **per-swarm agent cap** on `add_agent` / `scale_agent_group` —
      resource-exhaustion DoS (audit #28); and
    * **rejection of host-escape backend config keys** in `add_agent`
      (`subzeroclaw_path`, `extra_ro_binds`, `extra_rw_binds`, `extra_path`) —
      audit #24.

  Operators may authorize an exact ordered read-only mount list per swarm through
  application config `:dynamic_agent_ro_binds`. Proposed ops cannot grant this
  authority; writable mounts and executable/path overrides remain forbidden.

  `validate/3` takes the proposed event and the current desired state, and reads
  operator-owned application policy.
  The endpoint allowlist (audit #30) is intentionally *not* here — in the IR a
  model is a logical ref (`openrouter:…`), so the host it resolves to is only
  known at resolve/actuation time; that check belongs there.
  """

  alias Genswarms.IR.State
  alias Genswarms.IR.Overlay.Event

  @default_max_agents 100

  # Backend config keys that grant host access; never settable through a proposed
  # op (an operator-authored seed may still use them — this guards the dynamic
  # control-plane surface, like #24 guarded the add_agent API).
  @forbidden_config_keys ~w(subzeroclaw_path extra_ro_binds extra_rw_binds extra_path)

  @doc """
  Validates a proposed op against the current state and policy.

  Options: `:max_agents` overrides the per-swarm cap (defaults to
  `config :genswarms, :max_agents_per_swarm`, else #{@default_max_agents}).
  """
  @spec validate(Event.t(), State.t(), keyword()) :: :ok | {:error, term()}
  def validate(event, state, opts \\ [])

  def validate(%Event{op: :add_agent, payload: p}, %State{agents: agents, name: name}, opts) do
    with :ok <- within_cap(length(agents) + 1, opts),
         :ok <- no_forbidden_keys(Map.get(p, "config", %{}), name),
         :ok <- no_forbidden_keys(backend_opts(p), name) do
      :ok
    end
  end

  def validate(%Event{op: :scale_agent_group, payload: %{"target_count" => target}}, _state, opts) do
    within_cap(target, opts)
  end

  def validate(%Event{}, _state, _opts), do: :ok

  @doc "The host-escape backend config keys rejected on a proposed op."
  @spec forbidden_config_keys() :: [String.t()]
  def forbidden_config_keys, do: @forbidden_config_keys

  defp within_cap(count, opts) do
    max =
      Keyword.get(opts, :max_agents) ||
        Application.get_env(:genswarms, :max_agents_per_swarm, @default_max_agents)

    if count <= max, do: :ok, else: {:error, {:agent_cap_exceeded, count, max}}
  end

  defp no_forbidden_keys(config, swarm_name) when is_map(config) do
    offending =
      config
      |> Enum.reject(fn {key, value} ->
        to_string(key) == "extra_ro_binds" and approved_ro_binds?(value, swarm_name)
      end)
      |> Enum.map(fn {key, _} -> to_string(key) end)
      |> Enum.filter(&(&1 in @forbidden_config_keys))
      |> Enum.uniq()
      |> Enum.sort()

    if offending == [], do: :ok, else: {:error, {:forbidden_config_keys, offending}}
  end

  defp no_forbidden_keys(_, _), do: :ok

  # Operator-owned application configuration, never IR state/options or request
  # payload. Exact ordered equality prevents path widening and mount shadowing.
  defp approved_ro_binds?(binds, swarm_name) do
    policies = Application.get_env(:genswarms, :dynamic_agent_ro_binds, %{})
    approved = if is_map(policies), do: Map.get(policies, swarm_name), else: nil

    with {:ok, proposed} <- normalize_binds(binds),
         {:ok, expected} <- normalize_binds(approved) do
      proposed == expected
    else
      _ -> false
    end
  end

  defp normalize_binds(binds) when is_list(binds) and binds != [] do
    Enum.reduce_while(binds, {:ok, []}, fn
      {host, target}, {:ok, acc} when is_binary(host) and is_binary(target) ->
        {:cont, {:ok, [{host, target} | acc]}}

      [host, target], {:ok, acc} when is_binary(host) and is_binary(target) ->
        {:cont, {:ok, [{host, target} | acc]}}

      _, _ ->
        {:halt, :error}
    end)
  end

  defp normalize_binds(_), do: :error

  defp backend_opts(%{"backend" => %{"opts" => opts}}), do: opts
  defp backend_opts(_), do: %{}
end
