defmodule Genswarms.Backends.Bwrap.EnvIsolationTest do
  @moduledoc """
  Runtime proof that the bwrap sandbox does not inherit the orchestrator's
  environment.

  `BwrapBackend.build_bwrap_args/7` emits `--clearenv` ahead of its explicit
  `--setenv` allowlist, and `build_env/2` only *merges* its curated entries
  into the BEAM environment (Erlang `Port.open({:env, ...})` semantics). The
  argv-shape tests in `BwrapBackendTest` can only assert that `--clearenv` is
  present and ordered; they cannot show that an arbitrary host variable is
  actually absent inside a live sandbox.

  These tests execute bwrap for real, so they are skipped when bwrap is missing
  or when user namespaces are unavailable in the environment.
  """
  use ExUnit.Case, async: false

  alias Genswarms.Backends.BwrapBackend

  @sentinel "GENSWARMS_HOST_SECRET_SENTINEL"

  # A minimal sandbox is enough to exercise the env policy: the production argv
  # needs a Nix base layer and an overlay root, neither of which is available in
  # a plain test run. The env flags under test are the production ones, extracted
  # from build_bwrap_args/7 rather than restated here, so this test cannot drift
  # away from the allowlist it is meant to police.
  @base_flags ["--ro-bind", "/", "/", "--dev", "/dev", "--unshare-all"]

  setup_all do
    sentinel = @sentinel
    value = "s3cr3t-#{Base.encode16(:crypto.strong_rand_bytes(8))}"
    previous = System.get_env(sentinel)
    System.put_env(sentinel, value)

    on_exit(fn ->
      if previous, do: System.put_env(sentinel, previous), else: System.delete_env(sentinel)
    end)

    case probe() do
      {:ok, bwrap} -> {:ok, bwrap: bwrap, sentinel: sentinel, value: value}
      :error -> {:ok, skip: true}
    end
  end

  # An absolute path: bwrap resolves the command against the *sandbox* PATH,
  # which `--setenv PATH ...` has not established yet at exec time.
  @env_binary "/usr/bin/env"

  defp probe do
    with path when is_binary(path) <- System.find_executable("bwrap"),
         {_, 0} <-
           System.cmd(path, @base_flags ++ ["--clearenv", @env_binary], stderr_to_stdout: true) do
      {:ok, path}
    else
      _ -> :error
    end
  end

  # The exact env-carrying portion of the production argv: `--clearenv` plus
  # every `--setenv NAME VALUE` pair that follows it, up to the `--` separator
  # that precedes the sandboxed command. `--chdir` and the other mount flags in
  # between are dropped: they are about the filesystem, not the environment, and
  # their targets do not exist in a minimal test sandbox.
  defp production_env_argv do
    args =
      BwrapBackend.build_bwrap_args(
        "sentinel-agent",
        "/tmp/overlay",
        nil,
        "/tmp/workspace",
        [:base],
        %{extra_env: %{"GENSWARMS_ALLOWED" => "allowed-value"}},
        ["--ro-bind", "/nix/store", "/nix/store"]
      )

    case Enum.find_index(args, &(&1 == "--clearenv")) do
      nil ->
        []

      clear_idx ->
        seg =
          args
          |> Enum.slice((clear_idx + 1)..(length(args) - 1))
          |> Enum.take_while(&(&1 != "--"))

        pairs =
          seg
          |> Enum.chunk_every(1)
          |> Enum.reduce({[], nil}, fn
            ["--setenv"], {acc, nil} -> {acc, :want_name}
            [name], {acc, :want_name} -> {acc, {:name, name}}
            [value], {acc, {:name, name}} -> {[{name, value} | acc], nil}
            _, acc -> acc
          end)
          |> elem(0)
          |> Enum.reverse()

        setenv_pairs = Enum.flat_map(pairs, fn {name, value} -> ["--setenv", name, value] end)

        ["--clearenv" | setenv_pairs]
    end
  end

  defp sandbox_env(bwrap, env_argv) do
    {out, 0} = System.cmd(bwrap, @base_flags ++ env_argv ++ [@env_binary], stderr_to_stdout: true)

    out
  end

  @tag :bwrap
  test "a host environment variable is absent inside the sandbox", ctx do
    if Map.get(ctx, :skip), do: assert(false)

    env_argv = production_env_argv()
    assert "--clearenv" in env_argv, "production argv lost --clearenv"

    inside = sandbox_env(ctx.bwrap, env_argv)

    refute inside =~ "#{ctx.sentinel}=",
           "host variable #{ctx.sentinel} leaked into the sandbox"

    # Control: the allowlisted variables the backend does set are present, so
    # the refutation above is about the leak and not an empty environment.
    assert inside =~ "PATH="
    assert inside =~ "HOME=/root"
    assert inside =~ "GENSWARMS_ALLOWED=allowed-value"
  end

  @tag :bwrap
  test "the same argv without --clearenv leaks the host variable", ctx do
    if Map.get(ctx, :skip), do: assert(false)

    # Guards the guard: with `--clearenv` removed the sentinel is visible. If
    # this ever stops holding, bwrap stopped honouring the flag on this platform
    # and the test above would pass for the wrong reason.
    inside = sandbox_env(ctx.bwrap, List.delete(production_env_argv(), "--clearenv"))

    assert inside =~ "#{ctx.sentinel}=",
           "expected the host variable to be inherited without --clearenv, " <>
             "so the isolation test above is not meaningful"
  end
end
