defmodule Genswarms.Config.RequestNames do
  @moduledoc """
  Admission of node names declared by the HTTP control plane.

  Dynamic mode is bounded by a VM-lifetime budget; restricted mode admits only
  existing atoms. This module must not be used for messages, lookups, arbitrary
  config keys or backend selectors: those always resolve existing atoms only.
  """

  alias Genswarms.Config.SwarmConfig

  @counter {__MODULE__, :allocated}
  @default_limit 10_000

  @doc "Number of reservations made in this VM, including failed starts. Never refunded."
  def allocated, do: :persistent_term.get(@counter, 0)

  @doc """
  Admits a complete batch of declared names or rejects it without creating atoms.
  `allocate: false` checks policy and capacity without consuming the budget.
  """
  def admit(names, opts \\ []) when is_list(names) do
    if Enum.all?(names, &valid_name?/1) do
      names = names |> Enum.map(&to_string/1) |> Enum.uniq()

      # Serialize admission across all request processes on this node. The
      # counter lives outside any supervisor/process, so restarting one cannot
      # replenish the budget while its atoms remain in the VM.
      :global.trans(
        {__MODULE__, self()},
        fn -> admit_locked(names, Keyword.get(opts, :allocate, true)) end,
        [node()]
      )
    else
      {:error, :invalid_node_name}
    end
  end

  defp admit_locked(names, allocate?) do
    with {:ok, restricted?} <- restricted_names(),
         {:ok, limit} <- dynamic_limit() do
      fresh = Enum.reject(names, &existing?/1)
      count = length(fresh)
      # Leave most of the atom table to code loading and trusted runtime work,
      # even if an operator configures an excessively large budget.
      atom_limit = :erlang.system_info(:atom_limit)
      limit = min(limit, div(atom_limit, 4))

      cond do
        count == 0 ->
          :ok

        restricted? ->
          {:error, :restricted_names}

        allocated() + count > limit ->
          {:error, :dynamic_name_limit_reached}

        :erlang.system_info(:atom_count) + count > atom_limit - div(atom_limit, 4) ->
          {:error, :atom_table_capacity_low}

        allocate? ->
          # Reserve before interning: an interrupted request may waste capacity,
          # but can never mint atoms without charging them to the lifetime cap.
          :persistent_term.put(@counter, allocated() + count)
          Enum.each(fresh, &String.to_atom/1)
          :ok

        true ->
          :ok
      end
    end
  end

  defp valid_name?(name) when is_binary(name),
    do: byte_size(name) <= 255 and SwarmConfig.valid_identifier?(name)

  defp valid_name?(name) when is_atom(name) and name not in [nil, true, false],
    do: valid_name?(Atom.to_string(name))

  defp valid_name?(_), do: false

  defp existing?(name) do
    String.to_existing_atom(name)
    true
  rescue
    ArgumentError -> false
  end

  defp restricted_names do
    case setting(:restricted_names, "GENSWARMS_RESTRICTED_NAMES") do
      value when value in [nil, false, "false", "0"] -> {:ok, false}
      value when value in [true, "true", "1"] -> {:ok, true}
      _ -> {:error, :invalid_name_policy}
    end
  end

  defp dynamic_limit do
    case setting(:max_dynamic_names, "GENSWARMS_MAX_DYNAMIC_NAMES") do
      nil -> {:ok, @default_limit}
      value when is_integer(value) and value >= 0 -> {:ok, value}
      value when is_binary(value) -> parse_limit(value)
      _ -> {:error, :invalid_name_policy}
    end
  end

  defp parse_limit(value) do
    case Integer.parse(value) do
      {n, ""} when n >= 0 -> {:ok, n}
      _ -> {:error, :invalid_name_policy}
    end
  end

  defp setting(key, env) do
    case Application.get_env(:genswarms, key) do
      nil -> System.get_env(env)
      value -> value
    end
  end
end
