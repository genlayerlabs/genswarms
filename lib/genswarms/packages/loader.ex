defmodule Genswarms.Packages.Loader do
  @moduledoc """
  Resolves a notarized package ref into an object-handler MODULE — the runtime
  half of the resolver→runtime circuit (gsp design §14.3). Fail-closed in both
  modes: on any mismatch the object does not start; a silently different
  handler is never bound.

  A swarm definition may declare an object handler as data instead of a module:

      %{name: :browse,
        handler: %{
          ref: "swarmidx:genlayerlabs/browse@0.1.1",
          digest: "sha256:…",                # the notarized digest, pinned in the def
          path: "vendor/swarmidx/genlayerlabs__browse@0.1.1",
          mode: :require                     # or :verify
        },
        config: %{…}}

  Modes:

    * `:require` — for IR-cast swarms with no mix dep: re-hash `path` against
      `digest`, compile the verified in-memory entry files in order, return the entry
      module. The module binding comes from `swarm-object.json` INSIDE the
      hashed bytes (§14.2) — never from registry metadata.
    * `:verify` — attestation for hosts that already compile the package as a
      mix dep: assert `path` (e.g. `deps/<app>/<pkg dir>`) re-hashes to the
      notarized digest and that the active entry module has proven provenance.
      Proof is either this loader's recorded verified compilation (including
      dependency-module identities), or a `beams` map in the signed entry
      mapping module names to SHA-256 digests of compiled BEAM artifacts. Merely
      being loaded, or having a matching source path, is insufficient.

  Plain module handlers (and nil) pass through untouched — the ref path is
  strictly opt-in.
  """

  alias Genswarms.Packages.Dirhash

  @entry_file "swarm-object.json"

  @spec resolve_handler(module() | nil | map()) :: {:ok, module() | nil} | {:error, term()}
  def resolve_handler(nil), do: {:ok, nil}
  def resolve_handler(handler) when is_atom(handler), do: {:ok, handler}

  def resolve_handler(%{} = spec) do
    with {:ok, ref} <- fetch_string(spec, :ref),
         {:ok, digest} <- fetch_string(spec, :digest),
         {:ok, path} <- fetch_string(spec, :path),
         {:ok, mode} <- fetch_mode(spec),
         {:ok, files} <- verified_files(ref, path, digest),
         {:ok, entry} <- read_entry(path, files) do
      :global.trans(
        {__MODULE__, self()},
        fn ->
          case mode do
            :require -> require_entry(path, digest, entry, files)
            :verify -> verify_entry(digest, entry)
          end
        end,
        [node()]
      )
    end
  end

  def resolve_handler(other), do: {:error, {:invalid_handler_spec, other}}

  # ── digest attestation ───────────────────────────────────────────────────────

  @doc "Returns exactly the regular-file bytes whose digest was verified."
  def verified_files(ref, path, digest) do
    case Dirhash.snapshot(path) do
      {:ok, files} ->
        case Dirhash.hash_files(files) do
          ^digest -> {:ok, files}
          got -> {:error, {:digest_mismatch, ref, got}}
        end

      {:error, reason} ->
        {:error, {:unreadable_package_dir, path, reason}}
    end
  end

  # ── the entry convention (§14.2): swarm-object.json inside the hashed bytes ──

  defp read_entry(path, snapshot) do
    file = Path.join(path, @entry_file)

    with {:ok, raw} <- Map.fetch(snapshot, @entry_file),
         {:ok, %{"module" => module} = entry} when is_binary(module) <- Jason.decode(raw) do
      files =
        case Map.get(entry, "files") do
          nil ->
            snapshot |> Map.keys() |> Enum.filter(&String.ends_with?(&1, ".ex")) |> Enum.sort()

          list when is_list(list) ->
            list

          _ ->
            [nil]
        end

      if Enum.all?(files, &safe_rel_path?/1),
        do: {:ok, %{module: module, files: files, beams: Map.get(entry, "beams", %{})}},
        else: {:error, {:unsafe_entry_files, files}}
    else
      :error -> {:error, {:missing_entry_file, file}}
      {:ok, other} -> {:error, {:invalid_entry_file, other}}
      {:error, reason} -> {:error, {:invalid_entry_file, reason}}
    end
  end

  # Entry files name paths INSIDE the verified dir only — no absolute paths, no
  # traversal (the entry file is notarized, but defense in depth costs nothing).
  defp safe_rel_path?(rel) when is_binary(rel) do
    Path.type(rel) == :relative and rel != "" and
      not Enum.any?(Path.split(rel), &(&1 in ["..", "."])) and not String.contains?(rel, "\\")
  end

  defp safe_rel_path?(_), do: false

  # ── :require — load the vendored code ────────────────────────────────────────

  defp require_entry(path, digest, %{module: module} = entry, snapshot) do
    case existing_module(module) do
      {:ok, mod} when not is_nil(mod) ->
        cond do
          not Code.ensure_loaded?(mod) ->
            compile_entry(path, digest, entry, snapshot)

          :persistent_term.get({__MODULE__, mod}, nil) == nil and entry.files != [] ->
            # Explicit require mode recompiles the snapshot, even if Mix has
            # previously loaded this module. Never borrow its existing identity.
            compile_entry(path, digest, entry, snapshot)

          true ->
            verify_entry(digest, entry)
        end

      :error ->
        compile_entry(path, digest, entry, snapshot)
    end
  rescue
    _ -> {:error, :package_compile_failed}
  end

  defp compile_entry(path, digest, %{module: module, files: files}, snapshot) do
    # Read/validate all entries before any compilation; never reopen a hashed path.
    sources = Enum.map(files, fn rel -> {rel, Map.fetch!(snapshot, rel)} end)

    compiled =
      Enum.flat_map(sources, fn {rel, bytes} ->
        Code.compile_string(bytes, Path.join(path, rel))
      end)

    with {:ok, mod} <- existing_module(module),
         true <- Enum.any?(compiled, fn {compiled_mod, _} -> compiled_mod == mod end) do
      identities = Map.new(compiled, fn {m, _} -> {m, m.module_info(:md5)} end)
      :persistent_term.put({__MODULE__, mod}, {digest, identities})
      {:ok, mod}
    else
      _ -> {:error, {:entry_module_not_defined_by_package, module}}
    end
  end

  # ── :verify — attest an already-compiled mix dep ─────────────────────────────

  defp verify_entry(digest, %{module: module, beams: beams}) do
    with {:ok, mod} <- existing_module(module),
         true <- Code.ensure_loaded?(mod) do
      case :persistent_term.get({__MODULE__, mod}, nil) do
        {^digest, identities} ->
          if Enum.all?(identities, fn {m, md5} ->
               Code.ensure_loaded?(m) and m.module_info(:md5) == md5
             end),
             do: {:ok, mod},
             else: {:error, :loaded_package_changed}

        _ ->
          verify_beam_manifest(mod, beams)
      end
    else
      _ -> {:error, {:entry_module_not_loaded, module}}
    end
  end

  defp verify_beam_manifest(mod, beams) when is_map(beams) and map_size(beams) > 0 do
    # Build pipelines can include hashes of compiled BEAMs in the signed entry.
    # Check both the disk binary and the running module to reject stale code paths.
    identities =
      Enum.map(beams, fn {name, digest} ->
        with {:ok, m} <- existing_module(name),
             {^m, bytes, _} <- :code.get_object_code(m),
             {:ok, {^m, md5}} <- :beam_lib.md5(bytes),
             true <- Code.ensure_loaded?(m) and m.module_info(:md5) == md5,
             true <-
               "sha256:" <> Base.encode16(:crypto.hash(:sha256, bytes), case: :lower) == digest do
          {:ok, m}
        else
          _ -> :error
        end
      end)

    if {:ok, mod} in identities and Enum.all?(identities, &match?({:ok, _}, &1)),
      do: {:ok, mod},
      else: {:error, :unproven_beam_provenance}
  end

  defp verify_beam_manifest(_, _), do: {:error, :unproven_beam_provenance}

  # to_existing_atom AFTER the package is loaded/compiled: the module atom
  # exists exactly when the module does — no atom minting from package data.
  defp existing_module(name) do
    {:ok, String.to_existing_atom("Elixir." <> String.trim_leading(name, "Elixir."))}
  rescue
    ArgumentError -> :error
  end

  defp fetch_string(spec, key) do
    case Map.get(spec, key) || Map.get(spec, to_string(key)) do
      v when is_binary(v) and v != "" -> {:ok, v}
      _ -> {:error, {:missing_handler_spec_key, key}}
    end
  end

  defp fetch_mode(spec) do
    case Map.get(spec, :mode) || Map.get(spec, "mode") do
      m when m in [:require, "require"] -> {:ok, :require}
      m when m in [nil, :verify, "verify"] -> {:ok, :verify}
      _ -> {:error, :invalid_handler_load_mode}
    end
  end
end
