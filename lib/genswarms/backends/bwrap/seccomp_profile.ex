defmodule Genswarms.Backends.Bwrap.SeccompProfile do
  @moduledoc """
  Builds and wires the default bwrap seccomp profile.

  Bubblewrap expects `--seccomp FD`, not a file path. The backend therefore
  inserts a tiny wrapper before bwrap; the wrapper opens the generated cBPF
  profile as FD 3 and then execs bwrap with `--seccomp 3`.
  """

  import Bitwise, only: [|||: 2]

  @audit_arch_x86_64 0xC000003E

  @bpf_ld_w_abs 0x20
  @bpf_jmp_jeq_k 0x15
  @bpf_ret_k 0x06

  @seccomp_ret_kill_process 0x80000000
  @seccomp_ret_errno 0x00050000
  @seccomp_ret_allow 0x7FFF0000

  @eperm 1

  # Conservative denylist for syscalls that are not part of normal shell/curl/jq
  # agent work and that are useful for kernel attack surface expansion or host
  # manipulation attempts. Mount setup is still allowed to bwrap itself; this
  # profile is loaded by bwrap for the sandboxed payload.
  @default_deny_x86_64 %{
    add_key: 248,
    bpf: 321,
    delete_module: 176,
    finit_module: 313,
    init_module: 175,
    kcmp: 312,
    kexec_file_load: 320,
    kexec_load: 246,
    keyctl: 250,
    mount: 165,
    move_mount: 429,
    open_tree: 428,
    perf_event_open: 298,
    pivot_root: 155,
    ptrace: 101,
    reboot: 169,
    request_key: 249,
    umount2: 166
  }

  @truthy ~w(1 true yes on default denylist)

  @doc """
  Returns true when bwrap seccomp should be enabled.

  It is off by default to preserve existing backend behaviour. Operators can
  enable it either in backend config (`seccomp: true`) or with
  `GENSWARMS_BWRAP_SECCOMP=1`.
  """
  @spec enabled?(map()) :: boolean()
  def enabled?(config) do
    value = Map.get(config, :seccomp, System.get_env("GENSWARMS_BWRAP_SECCOMP"))

    case value do
      true -> true
      :default -> true
      :denylist -> true
      v when is_binary(v) -> String.downcase(v) in @truthy
      _ -> false
    end
  end

  @doc """
  Generates the default seccomp cBPF profile as a binary.
  """
  @spec default_profile_binary() :: binary()
  def default_profile_binary do
    deny_numbers =
      @default_deny_x86_64
      |> Map.values()
      |> Enum.sort()

    ([
       stmt(@bpf_ld_w_abs, 4),
       jump(@bpf_jmp_jeq_k, @audit_arch_x86_64, 1, 0),
       stmt(@bpf_ret_k, @seccomp_ret_kill_process),
       stmt(@bpf_ld_w_abs, 0)
     ] ++
       Enum.flat_map(deny_numbers, fn nr ->
         [
           jump(@bpf_jmp_jeq_k, nr, 0, 1),
           stmt(@bpf_ret_k, @seccomp_ret_errno ||| @eperm)
         ]
       end) ++
       [stmt(@bpf_ret_k, @seccomp_ret_allow)])
    |> IO.iodata_to_binary()
  end

  @doc """
  Writes the profile under the sandbox overlay and prepends the FD wrapper.

  Raises on failure when seccomp is enabled. That makes the backend fail closed:
  an operator who enabled seccomp never silently gets an unfiltered sandbox.
  """
  @spec maybe_wrap_bwrap_args!(String.t(), String.t(), [String.t()], map()) :: [String.t()]
  def maybe_wrap_bwrap_args!(sandbox_id, overlay_dir, bwrap_args, config)
      when is_list(bwrap_args) do
    if enabled?(config) do
      profile_path = write_default_profile!(sandbox_id, overlay_dir)
      [wrapper_path!(), profile_path | bwrap_args]
    else
      bwrap_args
    end
  end

  @doc false
  @spec default_deny_syscalls() :: [atom()]
  def default_deny_syscalls do
    @default_deny_x86_64
    |> Map.keys()
    |> Enum.sort()
  end

  defp write_default_profile!(_sandbox_id, overlay_dir) do
    path = Path.join(overlay_dir, "seccomp.bpf")
    File.write!(path, default_profile_binary())
    path
  end

  defp wrapper_path! do
    path = Path.join(:code.priv_dir(:genswarms), "bwrap-seccomp-wrapper.sh")

    if File.exists?(path) do
      path
    else
      raise "bwrap seccomp wrapper not found at #{path}"
    end
  end

  defp stmt(code, k), do: <<code::little-16, 0, 0, k::little-32>>
  defp jump(code, k, jt, jf), do: <<code::little-16, jt, jf, k::little-32>>
end
