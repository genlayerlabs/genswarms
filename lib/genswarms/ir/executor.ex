defmodule Genswarms.IR.Executor do
  @moduledoc """
  The effectful half of actuation: executes an `IR.Reconcile` plan against the
  live orchestrator, and reconstructs the **observed** state from it.

  This is where the IR is wired into the running system. The orchestrator module
  is injectable (`opts[:swarm_manager]`, default `Genswarms.SwarmManager`) so the
  action→call mapping is unit-testable without a live tree.

    * `observed/2` — read the swarm's live config (`get_full_config`, which the
      SwarmManager keeps updated as agents/objects/edges change) and translate it
      back to an `IR.State` via `IR.FromConfig`.
    * `apply_plan/3` — run a plan: each action becomes one orchestrator call.
    * `reconcile/3` — `observed` → `Reconcile.plan(desired, observed)` → apply.

  Note: today both `desired` and `observed` pass through `IR.FromConfig`, so
  matching nodes compare equal and a *restart* fires only on a real config
  change. When the registry exists and `desired` carries native `swarmidx:` refs,
  matching `observed` will need `resolve` first (future).
  """

  alias Genswarms.IR.{State, Reconcile, ToConfig, FromConfig}

  @default_sm Genswarms.SwarmManager

  @doc "Reconstructs the observed `IR.State` from the live swarm config."
  @spec observed(String.t(), keyword()) :: {:ok, State.t()} | {:error, term()}
  def observed(swarm_name, opts \\ []) do
    sm = Keyword.get(opts, :swarm_manager, @default_sm)

    with {:ok, config} <- sm.get_full_config(swarm_name),
         {:ok, state} <- FromConfig.from_config(config) do
      {:ok, %{state | phase: :observed}}
    end
  end

  @doc "Executes a reconcile plan against the orchestrator, action by action."
  @spec apply_plan(String.t(), [Reconcile.action()], keyword()) :: :ok | {:error, term()}
  def apply_plan(swarm_name, plan, opts \\ []) do
    sm = Keyword.get(opts, :swarm_manager, @default_sm)

    # Translate the whole plan before any effect. An unsupported package/policy
    # must not be discovered after removing the currently running node.
    with {:ok, prepared} <- prepare_plan(plan) do
      Enum.reduce_while(prepared, :ok, fn {original, action}, :ok ->
        case normalize(exec(sm, swarm_name, action)) do
          :ok -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, {original, reason}}}
        end
      end)
    end
  end

  @doc """
  Drives the live swarm toward `desired`: reads observed, plans, applies.
  Returns `{:ok, plan}` (the actions taken) or `{:error, reason}`.
  """
  @spec reconcile(String.t(), State.t(), keyword()) ::
          {:ok, [Reconcile.action()]} | {:error, term()}
  def reconcile(swarm_name, %State{} = desired, opts \\ []) do
    with {:ok, observed} <- observed(swarm_name, opts) do
      plan = Reconcile.plan(desired, observed)

      case apply_plan(swarm_name, plan, opts) do
        :ok -> {:ok, plan}
        {:error, _} = err -> err
      end
    end
  end

  # ── action → orchestrator call ───────────────────────────────────────────────

  defp prepare_plan(plan) do
    plan
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {action, index}, {:ok, acc} ->
      try do
        {:cont, {:ok, [{action, prepare_action(action)} | acc]}}
      rescue
        _ -> {:halt, {:error, {:invalid_runtime_spec, index}}}
      end
    end)
    |> case do
      {:ok, prepared} -> {:ok, Enum.reverse(prepared)}
      error -> error
    end
  end

  defp prepare_action({op, agent}) when op in [:start_agent, :restart_agent],
    do: {op, ToConfig.agent_spec(agent)}

  defp prepare_action({op, object}) when op in [:start_object, :restart_object],
    do: {op, ToConfig.object_spec(object)}

  defp prepare_action({op, _} = action)
       when op in [:stop_agent, :stop_object, :add_edge, :remove_edge],
       do: action

  defp exec(sm, swarm, {:start_agent, spec}), do: sm.add_agent(swarm, spec)
  defp exec(sm, swarm, {:stop_agent, name}), do: sm.remove_agent(swarm, name)

  defp exec(sm, swarm, {:restart_agent, a}) do
    with :ok <- normalize(sm.remove_agent(swarm, a.name)), do: sm.add_agent(swarm, a)
  end

  defp exec(sm, swarm, {:start_object, spec}), do: sm.add_object(swarm, spec)
  defp exec(sm, swarm, {:stop_object, name}), do: sm.remove_object(swarm, name)

  defp exec(sm, swarm, {:restart_object, o}) do
    with :ok <- normalize(sm.remove_object(swarm, o.name)), do: sm.add_object(swarm, o)
  end

  defp exec(sm, swarm, {:add_edge, e}), do: sm.add_topology_edges(swarm, [edge(e)])
  defp exec(sm, swarm, {:remove_edge, e}), do: sm.remove_topology_edges(swarm, [edge(e)])

  # Topology endpoints reference nodes that exist by the time edges are applied
  # (the plan starts nodes first).
  defp edge({from, to}), do: {String.to_atom(from), String.to_atom(to)}

  defp normalize(:ok), do: :ok
  defp normalize({:ok, _}), do: :ok
  defp normalize({:error, _} = err), do: err
  defp normalize(other), do: {:error, {:unexpected_result, other}}
end
