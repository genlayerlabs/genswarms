defmodule Genswarms.Backends.Bwrap.StoreClosure do
  @moduledoc """
  Computes the minimal /nix/store bind set for a bwrap agent under `store: :closure`:
  the runtime closure of the sandbox-base buildEnv UNION the dynamic-library closure of the
  externally-bind-mounted `subzeroclaw` ELF (it is built outside the buildEnv, so its loader/libs
  are not in the buildEnv closure) UNION `:extra_store_paths`. Fail-closed; successes cached in
  `:persistent_term`. Pure parsers are public for unit testing.
  """

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
end
