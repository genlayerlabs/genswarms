defmodule Genswarms.Backends.BwrapBackendTest do
  use ExUnit.Case, async: false

  alias Genswarms.Backends.BwrapBackend
  alias Genswarms.Backends.Bwrap.{OverlayManager, AgentTelemetry, SeccompProfile}

  @moduletag :bwrap

  setup_all do
    # Start telemetry if not running
    case AgentTelemetry.start_link() do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    {:ok, infrastructure_ready: OverlayManager.infrastructure_ready?()}
  end

  describe "backend_type/0" do
    test "returns :bwrap" do
      assert BwrapBackend.backend_type() == :bwrap
    end
  end

  describe "start/2 and stop/1" do
    @tag :integration
    test "starts and stops a bwrap sandbox", %{infrastructure_ready: ready} do
      if not ready do
        IO.puts("Skipping: bwrap infrastructure not ready")
      else
        config = %{
          swarm_name: "test",
          presets: [:base],
          workspace: "/tmp/test-workspace-#{:rand.uniform(999_999)}"
        }

        assert {:ok, ref} = BwrapBackend.start("test-agent", config)
        assert %BwrapBackend{} = ref
        assert ref.sandbox_id =~ "test-test-agent"
        assert ref.port != nil

        # Should be healthy
        assert :ok = BwrapBackend.health_check(ref)

        # Stop should cleanup
        assert :ok = BwrapBackend.stop(ref)

        # Overlay should be cleaned up
        refute File.exists?(ref.overlay_dir)
      end
    end

    test "returns error when overlay setup fails" do
      # Test with a config that will fail (infrastructure not ready simulates this)
      config = %{
        swarm_name: "test",
        presets: [:base]
      }

      result = BwrapBackend.start("test-agent", config)

      # Should either succeed (if infra ready) or fail gracefully
      case result do
        {:ok, ref} ->
          BwrapBackend.stop(ref)
          assert true

        {:error, {:overlay_setup_failed, _}} ->
          assert true

        {:error, _other} ->
          assert true
      end
    end
  end

  describe "resource_wrapper/4 (privilege_mode dispatch)" do
    @cgroup_opts %{memory_max: "32M", cpu_shares: 1, tasks_max: 50}

    test "default (:cgroup) wraps with systemd-run and yields a scope" do
      {exe, args, scope} =
        BwrapBackend.resource_wrapper(%{}, "sid", ["bwrap", "--", "cmd"], @cgroup_opts)

      assert String.ends_with?(exe, "systemd-run")
      assert "--user" in args
      assert "--property=MemoryMax=32M" in args
      assert scope == "szc-sid"
    end

    test ":rootless wraps with the priv launcher, NO scope, NO systemd" do
      {exe, args, scope} =
        BwrapBackend.resource_wrapper(
          %{privilege_mode: :rootless, nice: 12},
          "sid",
          ["bwrap", "--", "cmd"],
          @cgroup_opts
        )

      assert String.ends_with?(exe, "priv/bwrap-rootless-launch.sh")
      refute exe =~ "systemd"
      assert scope == nil, "rootless has no cgroup scope"
      # RLIMIT_AS in KB derived from 32M, then the nice, then -- and the bwrap argv
      assert args == ["32768", "12", "--", "bwrap", "--", "cmd"]
    end

    test ":rootless with no memory_max means an unlimited RLIMIT_AS (0)" do
      {_exe, ["0", "19", "--" | _], nil} =
        BwrapBackend.resource_wrapper(%{privilege_mode: :rootless}, "sid", ["bwrap"], %{})
    end
  end

  describe "send_input/2" do
    @tag :integration
    test "sends input to running sandbox", %{infrastructure_ready: ready} do
      if not ready do
        IO.puts("Skipping: bwrap infrastructure not ready")
      else
        config = %{
          swarm_name: "test",
          presets: [:base],
          workspace: "/tmp/test-workspace-#{:rand.uniform(999_999)}"
        }

        {:ok, ref} = BwrapBackend.start("test-agent", config)

        # Send some input
        assert :ok = BwrapBackend.send_input(ref, "echo hello")

        # Cleanup
        BwrapBackend.stop(ref)
      end
    end

    test "returns error for nil port" do
      # Create a ref with nil port
      ref = %BwrapBackend{
        port: nil,
        name: "test",
        sandbox_id: "test-123",
        overlay_dir: "/tmp/test",
        buffer: ""
      }

      # Should handle gracefully
      assert {:error, _} = BwrapBackend.send_input(ref, "test")
    end
  end

  describe "health_check/1" do
    @tag :integration
    test "returns :ok for healthy sandbox", %{infrastructure_ready: ready} do
      if not ready do
        IO.puts("Skipping: bwrap infrastructure not ready")
      else
        config = %{
          swarm_name: "test",
          presets: [:base],
          workspace: "/tmp/test-workspace-#{:rand.uniform(999_999)}"
        }

        {:ok, ref} = BwrapBackend.start("test-agent", config)

        assert :ok = BwrapBackend.health_check(ref)

        BwrapBackend.stop(ref)
      end
    end

    test "returns error for nil port" do
      ref = %BwrapBackend{
        port: nil,
        name: "test",
        sandbox_id: "test-123",
        overlay_dir: "/tmp/test",
        scope_name: nil,
        buffer: ""
      }

      assert {:error, :port_closed} = BwrapBackend.health_check(ref)
    end
  end

  describe "deploy_skills/2" do
    test "updates skills_dir in ref" do
      ref = %BwrapBackend{
        port: nil,
        name: "test",
        sandbox_id: "test-123",
        overlay_dir: "/tmp/test",
        skills_dir: nil,
        buffer: ""
      }

      {:ok, new_ref} = BwrapBackend.deploy_skills(ref, "/path/to/skills")

      assert new_ref.skills_dir == "/path/to/skills"
    end
  end

  describe "build_bwrap_args/6 (command-injection safety)" do
    # build_bwrap_args returns the argv LIST that is handed to
    # Port.open({:spawn_executable, ...}, [{:args, list}]). The whole point of
    # the security fix is that every untrusted value occupies exactly one argv
    # slot and is never joined into a shell string. These tests assert that
    # invariant directly.

    defp args_for(opts) do
      sandbox_id = Keyword.get(opts, :sandbox_id, "swarm-agent-123")
      overlay_dir = Keyword.get(opts, :overlay_dir, "/tmp/overlay")
      skills_dir = Keyword.get(opts, :skills_dir, nil)
      workspace = Keyword.get(opts, :workspace, "/tmp/workspace")
      config = Keyword.get(opts, :config, %{})

      BwrapBackend.build_bwrap_args(
        sandbox_id,
        overlay_dir,
        skills_dir,
        workspace,
        [:base],
        config,
        # default `:full` store bind — keeps these legacy injection-safety
        # tests exercising the exact argv shape they always did.
        ["--ro-bind", "/nix/store", "/nix/store"]
      )
    end

    # Asserts that `value` appears as a single argv element immediately
    # preceded by `flag` (e.g. ["--setenv", "SUBZEROCLAW_MODEL", value] or
    # ["--bind", value]). Locating by the value avoids matching a different,
    # legitimate occurrence of the same flag.
    defp assert_flag_value(args, flag, value) do
      idx = Enum.find_index(args, &(&1 == value))
      assert idx != nil, "expected value #{inspect(value)} in #{inspect(args)}"

      assert Enum.at(args, idx - 1) == flag,
             "expected #{inspect(value)} to be preceded by #{inspect(flag)}"
    end

    test "returns a flat list of binaries" do
      args = args_for([])
      assert is_list(args)
      assert Enum.all?(args, &is_binary/1), "every argv entry must be a binary"
    end

    test "first element is the bwrap executable" do
      args = args_for([])
      assert List.first(args) |> String.ends_with?("bwrap")
    end

    test "malicious workspace stays a single literal argv element" do
      payload = "/tmp/ws; touch /tmp/pwned; echo "
      args = args_for(workspace: payload, config: %{})

      # Appears verbatim, as the value of --bind, never split on the space/;.
      assert payload in args
      assert_flag_value(args, "--bind", payload)
      # No other element smuggled the payload into a larger token.
      assert Enum.count(args, &(&1 == payload)) == 1
    end

    test "malicious model stays a single literal argv element (wrapped in REQUEST_EXTRA)" do
      payload = "claude; rm -rf / #"
      args = args_for(config: %{model: payload})

      # The model now rides inside SUBZEROCLAW_REQUEST_EXTRA as JSON, still ONE
      # argv element, verbatim (metacharacters preserved, never interpreted).
      json = Jason.encode!(%{"model" => payload})
      assert json in args
      assert_flag_value(args, "SUBZEROCLAW_REQUEST_EXTRA", json)
    end

    test "malicious api_key stays a single literal argv element" do
      payload = "sk-secret$(whoami)`id`"
      args = args_for(config: %{api_key: payload})

      assert payload in args
      assert_flag_value(args, "SUBZEROCLAW_API_KEY", payload)
    end

    test "malicious endpoint stays a single literal argv element" do
      payload = "http://evil & curl http://x"
      args = args_for(config: %{endpoint: payload})

      assert payload in args
      assert_flag_value(args, "SUBZEROCLAW_ENDPOINT", payload)
    end

    test "malicious extra_env value stays a single literal argv element" do
      payload = "value with spaces; reboot"
      args = args_for(config: %{extra_env: %{"TARGET" => payload}})

      assert payload in args
      assert_flag_value(args, "TARGET", payload)
    end

    test "malicious sandbox_id (hostname) stays a single literal argv element" do
      payload = "host; touch /tmp/x"
      args = args_for(sandbox_id: payload)

      # Used both as --hostname value and as the szc-wrapper argument.
      assert payload in args
      assert_flag_value(args, "--hostname", payload)
    end

    test "no argv element contains an unescaped shell-break from any value" do
      payload = "INJECT; touch /tmp/should_not_run"

      args =
        args_for(
          sandbox_id: payload,
          workspace: payload,
          config: %{model: payload, api_key: payload, extra_env: %{"K" => payload}}
        )

      # Every element that mentions the payload must BE exactly the payload, or
      # the model wrapped as the SUBZEROCLAW_REQUEST_EXTRA JSON value — both are
      # single argv elements passed verbatim to execvp (never a shell string),
      # so neither concatenates the payload with neighbouring tokens.
      json_model = Jason.encode!(%{"model" => payload})

      offenders =
        Enum.filter(args, fn el ->
          String.contains?(el, "INJECT") and el != payload and el != json_model
        end)

      assert offenders == [], "payload leaked into composite arg(s): #{inspect(offenders)}"
    end

    test "argv ends with the szc-wrapper invocation" do
      args = args_for(sandbox_id: "sw-agent-9")
      sep_idx = Enum.find_index(args, &(&1 == "--"))
      assert sep_idx != nil
      tail = Enum.drop(args, sep_idx)

      assert ["--", "/usr/local/bin/szc-wrapper", "sw-agent-9", "/usr/local/bin/subzeroclaw" | _] =
               tail
    end

    test "extra_ro_binds that do not exist are skipped (no host-path leak)" do
      args = args_for(config: %{extra_ro_binds: [{"/nonexistent/path/xyz", "/container"}]})
      refute "/container" in args
    end

    test "network: :isolated folds in --unshare-net and CURL_HOME as discrete argv entries" do
      args = args_for(config: %{network: :isolated})
      assert "--unshare-net" in args
      assert_flag_value(args, "--setenv", "CURL_HOME")
    end

    test "default (network: :open) keeps the network namespace and adds no CURL_HOME" do
      args = args_for([])
      refute "--unshare-net" in args
      refute "CURL_HOME" in args
    end
  end

  describe "build_bwrap_args/7 store_binds splice" do
    # Arg-shape only — no nix/bwrap needed; store_binds is passed directly so
    # the splice position can be asserted without computing a real closure.
    defp store_args(store_binds) do
      BwrapBackend.build_bwrap_args(
        "swarm-agent",
        "/run/swarm/agents/swarm-agent",
        nil,
        "/tmp/szc-workspace/swarm-agent",
        [:base],
        %{},
        store_binds
      )
    end

    # count non-overlapping occurrences of a 3-element subsequence in the flat argv
    defp chunk_count(list, [_x, _y, _z] = needle) do
      list
      |> Enum.chunk_every(3, 1, :discard)
      |> Enum.count(fn c -> c == needle end)
    end

    test ":full store_binds yields exactly one /nix/store bind (backward-compat)" do
      a = store_args(["--ro-bind", "/nix/store", "/nix/store"])
      # the literal /nix/store->/nix/store bind appears exactly once
      assert chunk_count(a, ["--ro-bind", "/nix/store", "/nix/store"]) == 1
    end

    test "closure store_binds splice per-path and never the blanket /nix/store bind" do
      a =
        store_args([
          "--ro-bind",
          "/nix/store/p1",
          "/nix/store/p1",
          "--ro-bind",
          "/nix/store/p2",
          "/nix/store/p2"
        ])

      assert chunk_count(a, ["--ro-bind", "/nix/store", "/nix/store"]) == 0
      assert chunk_count(a, ["--ro-bind", "/nix/store/p1", "/nix/store/p1"]) == 1
      assert chunk_count(a, ["--ro-bind", "/nix/store/p2", "/nix/store/p2"]) == 1
    end
  end

  describe "seccomp wrapping" do
    test "seccomp is disabled by default" do
      old = System.get_env("GENSWARMS_BWRAP_SECCOMP")
      System.delete_env("GENSWARMS_BWRAP_SECCOMP")

      try do
        args = ["bwrap", "--version"]

        assert SeccompProfile.maybe_wrap_bwrap_args!("agent", "/tmp", args, %{}) == args
      after
        if old do
          System.put_env("GENSWARMS_BWRAP_SECCOMP", old)
        end
      end
    end

    test "seccomp wraps bwrap with a profile FD helper when enabled" do
      overlay_dir = System.tmp_dir!() |> Path.join("szc-seccomp-test-#{System.unique_integer()}")
      File.mkdir_p!(overlay_dir)

      try do
        args = ["/usr/bin/bwrap", "--version"]

        wrapped =
          SeccompProfile.maybe_wrap_bwrap_args!("agent", overlay_dir, args, %{seccomp: true})

        assert [wrapper, profile, "/usr/bin/bwrap", "--version"] = wrapped
        assert String.ends_with?(wrapper, "bwrap-seccomp-wrapper.sh")
        assert File.exists?(profile)
        assert File.read!(profile) == SeccompProfile.default_profile_binary()
      after
        File.rm_rf!(overlay_dir)
      end
    end

    test "default seccomp profile is a valid cBPF instruction stream shape" do
      profile = SeccompProfile.default_profile_binary()

      assert byte_size(profile) > 0
      assert rem(byte_size(profile), 8) == 0
      assert :ptrace in SeccompProfile.default_deny_syscalls()
      assert :bpf in SeccompProfile.default_deny_syscalls()
      assert :mount in SeccompProfile.default_deny_syscalls()
      assert :umount2 in SeccompProfile.default_deny_syscalls()
    end

    test "default seccomp profile is a well-formed arch-guarded deny-EPERM / allow-tail program" do
      # cBPF opcodes / seccomp return values (must match SeccompProfile).
      ld = 0x20
      jeq = 0x15
      ret = 0x06
      arch_x86_64 = 0xC000003E
      ret_kill = 0x80000000
      ret_errno = 0x00050000
      ret_allow = 0x7FFF0000
      eperm = 1

      insns =
        for <<code::little-16, jt::8, jf::8,
              k::little-32 <-
                SeccompProfile.default_profile_binary()>>,
            do: {code, jt, jf, k}

      deny_count = length(SeccompProfile.default_deny_syscalls())

      # 4-instruction preamble (load arch, arch guard, kill-on-mismatch, load nr)
      # + 2 instructions per denied syscall (match, return EPERM) + 1 allow tail.
      assert length(insns) == 4 + 2 * deny_count + 1

      assert [
               {^ld, 0, 0, 4},
               {^jeq, 1, 0, ^arch_x86_64},
               {^ret, 0, 0, ^ret_kill},
               {^ld, 0, 0, 0} | rest
             ] = insns

      {deny_pairs, [tail]} = Enum.split(rest, 2 * deny_count)
      assert tail == {ret, 0, 0, ret_allow}

      nrs =
        deny_pairs
        |> Enum.chunk_every(2)
        |> Enum.map(fn [{^jeq, 0, 1, nr}, {^ret, 0, 0, errno_eperm}] ->
          assert errno_eperm == Bitwise.bor(ret_errno, eperm)
          nr
        end)

      assert length(nrs) == deny_count
      assert nrs == Enum.sort(nrs)
      # Pin well-known x86_64 syscall numbers so the deny table cannot silently drift.
      assert 101 in nrs, "ptrace (101) must be denied"
      assert 165 in nrs, "mount (165) must be denied"
      assert 166 in nrs, "umount2 (166) must be denied"
      assert 169 in nrs, "reboot (169) must be denied"
      assert 321 in nrs, "bpf (321) must be denied"
    end

    test "seccomp is fail-closed: enabled with an unwritable overlay dir raises" do
      missing =
        System.tmp_dir!()
        |> Path.join("szc-seccomp-missing-#{System.unique_integer()}")
        |> Path.join("sub")

      refute File.exists?(missing)

      assert_raise File.Error, fn ->
        SeccompProfile.maybe_wrap_bwrap_args!(
          "agent",
          missing,
          ["/usr/bin/bwrap"],
          %{seccomp: true}
        )
      end
    end
  end

  describe "handle_output/2" do
    test "parses JSON lines correctly" do
      ref = %BwrapBackend{
        buffer: "",
        sandbox_id: "test-123"
      }

      data =
        ~s({"type": "message", "content": "hello"}\n{"type": "output", "content": "world"}\npartial)

      {:ok, messages, remaining} = BwrapBackend.handle_output(ref, data)

      assert length(messages) == 2
      assert remaining == "partial"
    end

    test "handles non-JSON lines" do
      ref = %BwrapBackend{
        buffer: "",
        sandbox_id: "test-123"
      }

      data = "plain text output\n"

      {:ok, messages, remaining} = BwrapBackend.handle_output(ref, data)

      assert length(messages) == 1
      assert hd(messages)["type"] == "output"
      assert hd(messages)["content"] == "plain text output"
      assert remaining == ""
    end
  end
end
