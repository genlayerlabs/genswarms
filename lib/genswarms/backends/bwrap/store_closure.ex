defmodule Genswarms.Backends.Bwrap.StoreClosure do
  @moduledoc """
  Computes the minimal /nix/store bind set for a bwrap agent under `store: :closure`:
  the runtime closure of the sandbox-base buildEnv UNION the dynamic-library closure of the
  externally-bind-mounted `subzeroclaw` ELF (it is built outside the buildEnv, so its loader/libs
  are not in the buildEnv closure) UNION `:extra_store_paths`. Fail-closed; successes cached in
  `:persistent_term`. Pure parsers are public for unit testing.
  """

  alias Genswarms.Backends.Bwrap.OverlayManager

  @doc "Parse `nix-store --query --requisites` output into a validated, non-empty store-path list."
  @spec parse_requisites(String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def parse_requisites(output) do
    paths =
      output
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    cond do
      paths == [] ->
        {:error, :empty_closure}

      bad = Enum.find(paths, &(not String.starts_with?(&1, "/nix/store/"))) ->
        {:error, {:non_store_path, bad}}

      true ->
        {:ok, paths}
    end
  end

  @doc "Reduce a /nix/store/<hash>-name/... file path to its store root /nix/store/<hash>-name."
  @spec store_root(String.t()) :: String.t()
  def store_root("/nix/store/" <> rest) do
    [top | _] = String.split(rest, "/", parts: 2)
    "/nix/store/" <> top
  end

  def store_root(other), do: other

  @doc "Extract the uniq /nix/store roots referenced by `ldd` output (libs + ELF interpreter)."
  @spec parse_ldd(String.t()) :: [String.t()]
  def parse_ldd(output) do
    ~r{/nix/store/[^\s:)]+}
    |> Regex.scan(output)
    |> List.flatten()
    |> Enum.map(&store_root/1)
    |> Enum.uniq()
  end

  @doc "Turn a store-path list into a flat bwrap `--ro-bind <p> <p>` argv fragment."
  @spec paths_to_binds([String.t()]) :: [String.t()]
  def paths_to_binds(paths), do: Enum.flat_map(paths, &["--ro-bind", &1, &1])

  @legacy_full_bind ["--ro-bind", "/nix/store", "/nix/store"]

  @doc """
  The bwrap store bind fragment for `store`. `:full` (default at the call site) = the legacy single
  bind. `:closure` = per-path `--ro-bind` for `closure(base) ∪ ldd(subzeroclaw) ∪ extra_store_paths`.
  """
  @spec bind_args(:full | :closure | term(), [atom()], String.t() | nil, map()) ::
          {:ok, [String.t()]} | {:error, term()}
  def bind_args(:full, _presets, _subzeroclaw, _config), do: {:ok, @legacy_full_bind}

  def bind_args(:closure, presets, subzeroclaw_binary, config) do
    with {:ok, paths} <- closure_paths(presets, subzeroclaw_binary, config) do
      {:ok, paths_to_binds(paths)}
    end
  end

  def bind_args(other, _presets, _subzeroclaw, _config), do: {:error, {:unknown_store_mode, other}}

  defp closure_paths(presets, subzeroclaw_binary, config) do
    with {:ok, base} <- OverlayManager.base_store_path(presets),
         {:ok, base_closure} <- cached_closure(base),
         {:ok, lib_paths} <- subzeroclaw_dep_paths(subzeroclaw_binary) do
      extra = Map.get(config, :extra_store_paths, [])
      {:ok, Enum.uniq(base_closure ++ lib_paths ++ extra)}
    end
  end

  # Cache SUCCESSFUL closures only (immutable per base store hash); failures are not cached.
  defp cached_closure(base) do
    key = {__MODULE__, :closure, base}

    case :persistent_term.get(key, nil) do
      nil ->
        with {:ok, paths} <- nix_requisites(base) do
          :persistent_term.put(key, paths)
          {:ok, paths}
        end

      paths ->
        {:ok, paths}
    end
  end

  defp nix_requisites(store_path) do
    case System.cmd(nix_store_bin(), ["--query", "--requisites", store_path],
           stderr_to_stdout: false
         ) do
      {out, 0} -> parse_requisites(out)
      {err, code} -> {:error, {:nix_store_failed, code, String.slice(err, 0, 200)}}
    end
  rescue
    e -> {:error, {:nix_store_exception, Exception.message(e)}}
  end

  defp subzeroclaw_dep_paths(nil), do: {:error, :no_subzeroclaw_binary}

  defp subzeroclaw_dep_paths(binary) do
    case System.cmd("ldd", [binary], stderr_to_stdout: false) do
      {out, 0} -> {:ok, parse_ldd(out)}
      {err, code} -> {:error, {:ldd_failed, code, String.slice(err, 0, 200)}}
    end
  rescue
    e -> {:error, {:ldd_exception, Exception.message(e)}}
  end

  defp nix_store_bin, do: System.find_executable("nix-store") || "nix-store"
end
