defmodule Genswarms.Backends.Bwrap.RootlessLauncher do
  @moduledoc """
  The `privilege_mode: :rootless` launch path for bwrap sandboxes.

  The classic path (`:cgroup`, the default) wraps every sandbox in a
  `systemd-run --user` scope for kernel-enforced limits — which is why the
  container around it needs systemd as PID 1 and `SYS_ADMIN`. This module is
  the trade the other way: **zero elevated capabilities**, plain-POSIX limits.

  | concern            | `:cgroup` (systemd)          | `:rootless` (this)            |
  |--------------------|------------------------------|-------------------------------|
  | memory cap         | cgroup MemoryMax (OOM kill)  | RLIMIT_AS (allocation fails)  |
  | cpu                | CPUWeight                    | nice                          |
  | tasks cap          | TasksMax                     | NOT enforced per-agent (*)    |
  | tree cleanup       | scope kill                   | PID namespace + die-with-parent |
  | host requirements  | systemd + delegated cgroups  | unprivileged userns only      |

  (*) RLIMIT_NPROC counts processes per real UID — with many agents sharing the
  BEAM's UID it would throttle them collectively and unpredictably, so we don't
  pretend to enforce it. Bound the aggregate at the pod/container level.

  Pick `:rootless` on shared/managed infrastructure (Kubernetes) where the pod
  is the hard boundary; keep `:cgroup` on dedicated boxes where you can afford
  the privileges and want kernel-hard per-agent enforcement.
  """

  @default_nice 19

  @doc """
  Builds the `{executable, argv, scope_name}` triple for a rootless launch —
  same shape `CgroupManager.create_scope/3` returns, with `scope_name` always
  `nil` (there is no scope; health/stop paths already treat nil as absent).

  `opts` takes `:memory_max` (a "32M"/"1G"-style string or nil) and `:nice`
  (integer, clamped to -20..19; only positive values make sense unprivileged).
  """
  @spec launch_spec([String.t()], map()) :: {String.t(), [String.t()], nil}
  def launch_spec(bwrap_args, opts \\ %{}) when is_list(bwrap_args) do
    as_kb = opts |> Map.get(:memory_max) |> memory_to_kb()
    nice = opts |> Map.get(:nice, @default_nice) |> clamp_nice()

    {launcher_path!(), [Integer.to_string(as_kb), Integer.to_string(nice), "--" | bwrap_args],
     nil}
  end

  @doc """
  Parses a systemd-style memory limit ("32M", "1G", "512K", bare bytes) into
  RLIMIT_AS kilobytes. `nil`, `0` or junk parse to `0` — which the launcher
  treats as "no limit" rather than guessing one.
  """
  @spec memory_to_kb(String.t() | non_neg_integer() | nil) :: non_neg_integer()
  def memory_to_kb(nil), do: 0
  def memory_to_kb(n) when is_integer(n) and n >= 0, do: div(n, 1024)

  def memory_to_kb(str) when is_binary(str) do
    case Integer.parse(String.trim(str)) do
      {n, unit} when n > 0 ->
        case String.upcase(String.trim(unit)) do
          "" -> div(n, 1024)
          "K" -> n
          "M" -> n * 1024
          "G" -> n * 1024 * 1024
          _ -> 0
        end

      _ ->
        0
    end
  end

  def memory_to_kb(_), do: 0

  defp clamp_nice(n) when is_integer(n), do: n |> max(-20) |> min(19)
  defp clamp_nice(_), do: @default_nice

  defp launcher_path! do
    path = Path.join(:code.priv_dir(:genswarms), "bwrap-rootless-launch.sh")

    unless File.exists?(path) do
      raise "bwrap-rootless-launch.sh missing from priv/ — broken genswarms install"
    end

    path
  end
end
