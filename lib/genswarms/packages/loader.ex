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
      `digest`, `Code.require_file` the entry files in order, return the entry
      module. The module binding comes from `swarm-object.json` INSIDE the
      hashed bytes (§14.2) — never from registry metadata.
    * `:verify` — attestation for hosts that already compile the package as a
      mix dep: assert `path` (e.g. `deps/<app>/<pkg dir>`) re-hashes to the
      notarized digest and that the entry module is ALREADY loaded. No code
      loading — avoids double module definition. Turns the pinned ref into a
      boot-time supply-chain check: the code running is the code notarized.

  Plain module handlers (and nil) pass through untouched — the ref path is
  strictly opt-in.
  """

  alias Genswarms.Packages.Dirhash

  require Logger

  @entry_file "swarm-object.json"

  @spec resolve_handler(module() | nil | map()) :: {:ok, module() | nil} | {:error, term()}
  def resolve_handler(nil), do: {:ok, nil}
  def resolve_handler(handler) when is_atom(handler), do: {:ok, handler}

  def resolve_handler(%{} = spec) do
    with {:ok, ref} <- fetch_string(spec, :ref),
         {:ok, digest} <- fetch_string(spec, :digest),
         {:ok, path} <- fetch_string(spec, :path),
         mode <- fetch_mode(spec),
         :ok <- verify_digest(ref, path, digest),
         {:ok, entry} <- read_entry(path) do
      case mode do
        :require -> require_entry(ref, path, entry)
        :verify -> verify_entry(ref, entry)
      end
    end
  end

  def resolve_handler(other), do: {:error, {:invalid_handler_spec, other}}

  # ── digest attestation ───────────────────────────────────────────────────────

  defp verify_digest(ref, path, digest) do
    case Dirhash.hash_dir(path) do
      {:ok, ^digest} ->
        :ok

      {:ok, got} ->
        Logger.error(
          "[packages] #{ref}: DIGEST MISMATCH at #{path} — notarized #{digest}, on disk #{got}. " <>
            "Refusing to bind the handler."
        )

        {:error, {:digest_mismatch, ref, got}}

      {:error, reason} ->
        {:error, {:unreadable_package_dir, path, reason}}
    end
  end

  # ── the entry convention (§14.2): swarm-object.json inside the hashed bytes ──

  defp read_entry(path) do
    file = Path.join(path, @entry_file)

    with {:ok, raw} <- File.read(file),
         {:ok, %{"module" => module} = entry} when is_binary(module) <- Jason.decode(raw) do
      files =
        case Map.get(entry, "files") do
          list when is_list(list) and list != [] -> Enum.map(list, &to_string/1)
          _ -> path |> default_files() |> Enum.sort()
        end

      if Enum.all?(files, &safe_rel_path?/1),
        do: {:ok, %{module: module, files: files}},
        else: {:error, {:unsafe_entry_files, files}}
    else
      {:error, :enoent} -> {:error, {:missing_entry_file, file}}
      {:ok, other} -> {:error, {:invalid_entry_file, other}}
      {:error, reason} -> {:error, {:invalid_entry_file, reason}}
    end
  end

  defp default_files(path) do
    path
    |> Path.join("**/*.ex")
    |> Path.wildcard()
    |> Enum.map(&Path.relative_to(&1, path))
  end

  # Entry files name paths INSIDE the verified dir only — no absolute paths, no
  # traversal (the entry file is notarized, but defense in depth costs nothing).
  defp safe_rel_path?(rel) do
    not String.starts_with?(rel, "/") and not String.contains?(rel, "..")
  end

  # ── :require — load the vendored code ────────────────────────────────────────

  defp require_entry(ref, path, %{module: module, files: files}) do
    Enum.each(files, fn rel -> Code.require_file(Path.join(path, rel)) end)

    case existing_module(module) do
      {:ok, mod} ->
        Logger.info("[packages] #{ref}: loaded #{inspect(mod)} from verified bytes")
        {:ok, mod}

      :error ->
        {:error, {:entry_module_not_defined_by_package, module}}
    end
  rescue
    e -> {:error, {:package_compile_failed, ref, Exception.message(e)}}
  end

  # ── :verify — attest an already-compiled mix dep ─────────────────────────────

  defp verify_entry(ref, %{module: module}) do
    with {:ok, mod} <- existing_module(module),
         true <- Code.ensure_loaded?(mod) do
      Logger.info("[packages] #{ref}: attested — compiled bytes match the notarized digest")
      {:ok, mod}
    else
      _ -> {:error, {:entry_module_not_loaded, module}}
    end
  end

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
      m when m in [:require, "require"] -> :require
      _ -> :verify
    end
  end
end
