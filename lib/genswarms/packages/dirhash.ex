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
    if File.dir?(root) do
      lines =
        root
        |> files_under("")
        |> Enum.sort()
        |> Enum.map(fn rel ->
          content = File.read!(Path.join(root, rel))
          inner = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
          "#{inner}  #{rel}\n"
        end)

      outer = :crypto.hash(:sha256, Enum.join(lines)) |> Base.encode16(case: :lower)
      {:ok, "sha256:" <> outer}
    else
      {:error, {:not_a_directory, root}}
    end
  rescue
    e -> {:error, e}
  end

  defp files_under(root, prefix) do
    base = if prefix == "", do: root, else: Path.join(root, prefix)

    base
    |> File.ls!()
    |> Enum.flat_map(fn name ->
      rel = if prefix == "", do: name, else: prefix <> "/" <> name
      full = Path.join(root, rel)

      cond do
        File.dir?(full) and name == ".git" -> []
        File.dir?(full) -> files_under(root, rel)
        true -> [rel]
      end
    end)
  end
end
