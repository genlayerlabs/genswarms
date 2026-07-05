defmodule Genswarms.Objects.ConfigSchema do
  @moduledoc """
  The op gate for object config mutations, driven by each package's
  `config_schema` (gsp design §14.2.1: the configuration contract ships in
  the notarized `swarm-object.json` next to the handler's source).

  Fail-closed at every layer:

    * handler has no discoverable schema        → every patch rejected
    * patch key absent from the schema          → rejected
    * patch key present but not `x-mutable`     → rejected
    * host-escape backend keys                  → rejected unconditionally
      (mirrors `IR.OpPolicy`'s forbidden set — a config patch must never
      grant host access, whatever a schema claims)

  Only after a patch passes are its keys converted to atoms — the schema is
  a closed, package-authored set, so no caller-controlled atom minting at
  the top level. Nested map keys under an approved field are atomized with
  a hard cap on total keys (this surface sits behind the API token; the cap
  bounds the atom table impact of a compromised operator credential).
  """

  # deepest known package layout: <root>/lib/a/b/objects/handler.ex
  @max_walk_up 6
  # total nested keys allowed in one patch — atom-table backstop
  @max_patch_keys 200
  # host-escape keys (IR.OpPolicy audit #24) — never mutable via the API
  @forbidden_keys ~w(subzeroclaw_path extra_ro_binds extra_rw_binds extra_path)

  @doc """
  Validate a string-keyed JSON `patch` against the handler's schema and
  convert it to an atom-keyed config patch. `{:ok, atom_patch}` or
  `{:error, reason}`.
  """
  def validate_patch(handler, patch), do: validate_with_schema(schema_for(handler), patch)

  @doc "The pure half: validate a patch against an explicit schema (nil ⇒ reject all)."
  def validate_with_schema(schema, patch) when is_map(patch) do
    with :ok <- no_forbidden(patch),
         :ok <- bounded(patch),
         {:ok, schema} <- fetch_schema(schema),
         :ok <- all_mutable(patch, schema) do
      {:ok, atomize(patch)}
    end
  end

  def validate_with_schema(_schema, _patch), do: {:error, :patch_must_be_object}

  defp no_forbidden(patch) do
    case Enum.filter(@forbidden_keys, &Map.has_key?(patch, &1)) do
      [] -> :ok
      keys -> {:error, {:forbidden_keys, keys}}
    end
  end

  defp bounded(patch) do
    if count_keys(patch) <= @max_patch_keys, do: :ok, else: {:error, :patch_too_large}
  end

  defp count_keys(%{} = m),
    do: map_size(m) + (m |> Map.values() |> Enum.map(&count_keys/1) |> Enum.sum())

  defp count_keys(l) when is_list(l), do: l |> Enum.map(&count_keys/1) |> Enum.sum()
  defp count_keys(_), do: 0

  defp fetch_schema(%{} = schema), do: {:ok, schema}
  defp fetch_schema(_), do: {:error, :no_config_schema}

  defp all_mutable(patch, schema) do
    props = Map.get(schema, "properties", %{})

    rejected =
      patch
      |> Map.keys()
      |> Enum.reject(fn key ->
        case Map.get(props, key) do
          %{"x-mutable" => true} -> true
          _ -> false
        end
      end)

    case rejected do
      [] -> :ok
      keys -> {:error, {:immutable_keys, keys}}
    end
  end

  # keys validated against the closed schema set above; nested keys bounded
  defp atomize(%{} = m), do: Map.new(m, fn {k, v} -> {to_atom(k), atomize(v)} end)
  defp atomize(l) when is_list(l), do: Enum.map(l, &atomize/1)
  defp atomize(v), do: v

  defp to_atom(k) when is_binary(k), do: String.to_atom(k)
  defp to_atom(k), do: k

  @doc """
  Find the `config_schema` for a handler module: locate its compiled source
  and walk up looking for a `swarm-object.json` that binds THIS module.
  Returns the schema map or nil. Never consults a registry mirror —
  behavior lives in the hashed bytes.
  """
  def schema_for(handler) when is_atom(handler) and not is_nil(handler) do
    with true <- Code.ensure_loaded?(handler),
         source when is_list(source) <- handler.module_info(:compile)[:source] do
      source |> List.to_string() |> Path.dirname() |> find_schema(handler, @max_walk_up)
    else
      _ -> nil
    end
  rescue
    _ -> nil
  end

  # ref-map handlers (loader :require/:verify, design §14.3): the schema comes
  # straight from the swarm-object.json at the ref's path — the same notarized
  # bytes the loader already digest-verified when it bound the module.
  def schema_for(%{} = ref_spec) do
    with path when is_binary(path) and path != "" <-
           Map.get(ref_spec, :path) || Map.get(ref_spec, "path"),
         {:ok, raw} <- File.read(Path.join(path, "swarm-object.json")),
         {:ok, %{"config_schema" => schema}} when is_map(schema) <- Jason.decode(raw) do
      schema
    else
      _ -> nil
    end
  rescue
    _ -> nil
  end

  def schema_for(_), do: nil

  defp find_schema(_dir, _handler, 0), do: nil

  defp find_schema(dir, handler, depth) do
    path = Path.join(dir, "swarm-object.json")

    case File.read(path) do
      {:ok, raw} ->
        case Jason.decode(raw) do
          {:ok, %{"module" => mod, "config_schema" => schema}} when is_map(schema) ->
            if mod == inspect(handler), do: schema, else: nil

          _ ->
            nil
        end

      _ ->
        parent = Path.dirname(dir)
        if parent == dir, do: nil, else: find_schema(parent, handler, depth - 1)
    end
  end
end
