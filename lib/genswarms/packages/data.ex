defmodule Genswarms.Packages.Data do
  @moduledoc "Loads body.md and policy.json as data from digest-verified package snapshots."
  alias Genswarms.Packages.Loader

  def body!(ref) do
    files = files!(ref)
    content = Map.fetch!(files, "body.md")
    unless String.valid?(content), do: raise(ArgumentError, "invalid body encoding")
    %{"name" => "package-body.md", "content" => content}
  end

  def policy!(ref) do
    policy = ref |> files!() |> Map.fetch!("policy.json") |> Jason.decode!()
    unless is_map(policy) or is_list(policy), do: raise(ArgumentError, "invalid policy document")
    policy
  end

  defp files!(%{
         scheme: "swarmidx",
         kind: :data,
         opts: %{"path" => path},
         ref: ref,
         digest: digest
       })
       when is_binary(path) and is_binary(digest) do
    case Loader.verified_files(ref, path, digest) do
      {:ok, files} -> files
      {:error, _} -> raise ArgumentError, "package data verification failed"
    end
  end

  defp files!(_),
    do: raise(ArgumentError, "package data requires a digest and explicit opts.path")
end
