defmodule Mix.Tasks.Genswarms.Ir do
  use Mix.Task
  @shortdoc "Start or restore a native IR swarm in the foreground"
  @moduledoc """
  Runs a native desired swarm.state until the process is stopped:

      mix genswarms.ir start seed.json
      mix genswarms.ir restore swarm-name

  The seed is persisted to SQLite before boot. Restore needs the database and
  referenced runtime assets, but does not read the original seed file. This is
  a foreground process; use a service supervisor for unattended operation.
  """

  def run(args) do
    {:ok, _} = Application.ensure_all_started(:genswarms)

    case execute(args) do
      {:ok, name} ->
        Mix.shell().info("Running native IR swarm: #{name}")
        Process.sleep(:infinity)

      {:error, _} ->
        Mix.raise("Native IR start/restore failed; check the seed, database and runtime assets")
    end
  end

  @doc false
  def execute(["start", path]) do
    with {:ok, bytes} <- File.read(path),
         {:ok, document} <- Jason.decode(bytes),
         do: Genswarms.start_swarm_from_ir(document)
  end

  def execute(["restore", name]), do: Genswarms.restore_swarm(name)
  def execute(_), do: {:error, :usage}
end
