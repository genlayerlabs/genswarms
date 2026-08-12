defmodule Genswarms.Backends.Tmux.ArgvFile do
  @moduledoc false

  alias Genswarms.Backends.Tmux.RunnerHelpers

  @filename "host-launch.argv0"

  @doc "Wraps a large host argv in one strict, NUL-delimited xargs invocation."
  @spec wrap(map(), map()) :: {:ok, map()} | {:error, term()}
  def wrap(config, %{executable: executable, args: args} = launch)
      when is_binary(executable) and is_list(args) do
    with :ok <- validate_args(args),
         {:ok, xargs} <-
           RunnerHelpers.resolve_host_executable(config, :xargs_executable, "xargs"),
         {:ok, path} <- write_manifest(Map.fetch!(config, :state_dir), args) do
      {:ok,
       %{
         launch
         | executable: xargs,
           args: [
             "--null",
             "--arg-file=#{path}",
             "--max-args=#{length(args)}",
             "--exit",
             "--",
             executable
           ]
       }}
    end
  rescue
    KeyError -> {:error, :missing_state_dir}
  end

  def wrap(_config, launch), do: {:error, {:invalid_host_launch, launch}}

  defp validate_args([]), do: {:error, :empty_host_argv}

  defp validate_args(args) do
    case Enum.find(args, &(not is_binary(&1) or String.contains?(&1, <<0>>))) do
      nil -> :ok
      invalid -> {:error, {:invalid_host_argument, invalid}}
    end
  end

  defp write_manifest(state_dir, args) when is_binary(state_dir) do
    dir = Path.join(state_dir, ".genswarms")
    path = Path.join(dir, @filename)
    body = Enum.map(args, &[&1, <<0>>])
    tmp = path <> ".tmp-#{System.unique_integer([:positive])}"

    with :ok <- RunnerHelpers.private_dir(dir),
         :ok <- File.write(tmp, body, [:binary]),
         :ok <- File.chmod(tmp, 0o600),
         :ok <- File.rename(tmp, path) do
      {:ok, path}
    else
      {:error, _} = error ->
        _ = File.rm(tmp)
        error
    end
  end

  defp write_manifest(_state_dir, _args), do: {:error, :invalid_state_dir}
end
