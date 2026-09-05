defmodule Genswarms.Packages.Dirhash do
  @moduledoc """
  Reproducible directory digest, byte-compatible with the gsp CLI (Go) and the
  swarmidx notary (Python) — the cross-language contract the loader's
  attestation rests on.

  Go modules' `dirhash.Hash1` shape: for each file (named by its slash-separated
  path relative to the dir) compute sha256(content); emit `"<hex>  <name>\\n"`;
  sort lines by name; the digest is sha256 of their concatenation, rendered
  `"sha256:<hex>"`. `.git` directories are skipped (VCS internals are not
  package content; a clone's `.git` varies per clone).
  """

  @spec hash_dir(Path.t()) :: {:ok, String.t()} | {:error, term()}
  def hash_dir(root) do
    with {:ok, files} <- snapshot(root), do: {:ok, hash_files(files)}
  end

  @doc "Reads a bounded regular-file snapshot, so verified bytes can be consumed without reopening paths."
  def snapshot(root) do
    with {:ok, %{type: :directory}} <- File.lstat(root) do
      files = files_under(root, "")
      if length(files) > 10_000, do: raise(ArgumentError, "package file limit exceeded")

      {contents, _size} =
        Enum.reduce(files, {%{}, 0}, fn rel, {acc, size} ->
          path = Path.join(root, rel)
          %{type: :regular, size: file_size} = File.lstat!(path)

          if size + file_size > 64 * 1024 * 1024,
            do: raise(ArgumentError, "package byte limit exceeded")

          bytes = File.read!(path)

          if size + byte_size(bytes) > 64 * 1024 * 1024,
            do: raise(ArgumentError, "package byte limit exceeded")

          {Map.put(acc, rel, bytes), size + byte_size(bytes)}
        end)

      {:ok, contents}
    else
      _ -> {:error, {:not_a_directory, root}}
    end
  rescue
    _ -> {:error, :invalid_package_files}
  end

  @doc "The shared Go/Python digest of a map of relative file names to bytes."
  def hash_files(files) do
    lines =
      files
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {rel, content} ->
        inner = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
        "#{inner}  #{rel}\n"
      end)

    "sha256:" <> (:crypto.hash(:sha256, lines) |> Base.encode16(case: :lower))
  end

  defp files_under(root, prefix) do
    base = if prefix == "", do: root, else: Path.join(root, prefix)

    base
    |> File.ls!()
    |> Enum.flat_map(fn name ->
      rel = if prefix == "", do: name, else: prefix <> "/" <> name
      full = Path.join(root, rel)

      case File.lstat!(full).type do
        :directory when name == ".git" -> []
        :directory -> files_under(root, rel)
        :regular -> [rel]
        _ -> raise ArgumentError, "package contains non-regular files"
      end
    end)
  end
end
