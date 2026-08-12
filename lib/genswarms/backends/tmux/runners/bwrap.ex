defmodule Genswarms.Backends.Tmux.Runners.Bwrap do
  @moduledoc false

  @behaviour Genswarms.Backends.Tmux.Runner

  alias Genswarms.Backends.BwrapBackend
  alias Genswarms.Backends.Tmux.ArgvFile

  alias Genswarms.Backends.Bwrap.{
    CgroupManager,
    OverlayManager,
    SeccompProfile,
    StoreClosure
  }

  alias Genswarms.Backends.Tmux.{RunnerHelpers, RunnerStore}

  defstruct [
    :config,
    :sandbox_id,
    :overlay_dir,
    :scope_name,
    :workspace,
    :state_dir,
    :client,
    :network,
    :privilege_mode,
    :client_source,
    :fingerprint,
    created?: false
  ]

  @identity_file ".genswarms-tmux-runner"
  @runtime_env_file "/root/.genswarms/runner.env"
  @runtime_env_launcher "/root/.genswarms/launch-with-env"

  @impl true
  def configure(config) do
    with {:ok, source} <-
           RunnerHelpers.normalize_source(Map.get(config, :client_source), :host_nix),
         {:ok, network} <- RunnerHelpers.normalize_network(config),
         :ok <- validate_network(network),
         {:ok, privilege_mode} <- normalize_privilege_mode(Map.get(config, :privilege_mode)) do
      state_dir =
        Path.expand(Map.get(config, :state_dir) || RunnerHelpers.default_state_dir(config))

      {:ok,
       config
       |> Map.put(:runner_kind, :bwrap)
       |> Map.put(:client_source, source)
       |> Map.put(:runner_network, network)
       |> Map.put(:state_dir, state_dir)
       |> Map.put(:runtime_workspace, "/workspace")
       |> Map.put(:runtime_skills_dir, "/skills")
       |> Map.put(:runtime_home, "/root")
       |> Map.put(:privilege_mode, privilege_mode)
       |> Map.put(:executable_scope, if(source == :runtime, do: :runtime, else: :host))}
    end
  end

  @impl true
  def prepare(config, launch, pane_state) do
    sandbox_id = "gstui-#{config.swarm_name}-#{config.agent_name}"

    with {:ok, bwrap} <-
           RunnerHelpers.resolve_host_executable(config, :bwrap_executable, "bwrap"),
         :ok <- prepare_directories(config),
         {:ok, launch, client_store_paths} <- prepare_client(config, launch),
         {:ok, env_pairs} <- environment(config, launch),
         fingerprint = runner_fingerprint(config, bwrap, launch, env_pairs),
         {:ok, overlay_dir, rootless_base, created?} <-
           prepare_overlay(config, sandbox_id, pane_state, fingerprint) do
      finish_prepare(
        config,
        bwrap,
        sandbox_id,
        overlay_dir,
        rootless_base,
        created?,
        client_store_paths,
        launch,
        env_pairs,
        fingerprint
      )
    end
  rescue
    error -> {:error, {:bwrap_prepare_failed, Exception.message(error)}}
  end

  @impl true
  def destroy(%__MODULE__{} = ref) do
    CgroupManager.kill_scope(ref.scope_name)
    OverlayManager.cleanup_overlay(ref.sandbox_id)
    :ok
  end

  @impl true
  def health_check(%__MODULE__{} = ref) do
    with true <- File.dir?(ref.overlay_dir) or {:error, :overlay_missing},
         :ok <- verify_fingerprint(ref.overlay_dir, ref.fingerprint) do
      if ref.scope_name && not CgroupManager.scope_active?(ref.scope_name),
        do: {:error, :scope_dead},
        else: :ok
    end
  end

  @impl true
  def session_info(%__MODULE__{} = ref) do
    %{
      kind: :bwrap,
      filesystem_isolation: true,
      process_isolation: true,
      network: ref.network,
      sandbox_id: ref.sandbox_id,
      privilege_mode: ref.privilege_mode,
      client_source: ref.client_source,
      workspace: ref.workspace,
      state_dir: ref.state_dir
    }
  end

  @doc false
  def build_bwrap_args(
        config,
        bwrap,
        sandbox_id,
        overlay_dir,
        rootless_base,
        store_paths,
        launch,
        _env_pairs
      ) do
    root_args =
      if rootless_base do
        [
          "--overlay-src",
          rootless_base,
          "--overlay",
          Path.join(overlay_dir, "upper"),
          Path.join(overlay_dir, "work"),
          "/"
        ]
      else
        ["--bind", Path.join(overlay_dir, "merged"), "/"]
      end

    with {:ok, ro, rw} <- RunnerHelpers.extra_binds(config) do
      store_args = StoreClosure.paths_to_binds(store_paths)

      core_mounts =
        [
          "--bind",
          config.workspace,
          "/workspace",
          "--bind",
          config.state_dir,
          "/root"
        ] ++ skills_mount(config)

      extra_mounts =
        Enum.flat_map(ro, fn {host, runtime} -> ["--ro-bind", host, runtime] end) ++
          Enum.flat_map(rw, fn {host, runtime} -> ["--bind", host, runtime] end)

      network_args = if config.runner_network == :none, do: ["--unshare-net"], else: []

      {:ok,
       [
         bwrap,
         "--unshare-user",
         "--unshare-pid",
         "--unshare-uts",
         "--unshare-ipc",
         "--uid",
         "1000",
         "--gid",
         "1000"
       ] ++
         root_args ++
         store_args ++
         network_args ++
         core_mounts ++
         extra_mounts ++
         [
           "--proc",
           "/proc",
           "--dev",
           "/dev",
           "--tmpfs",
           "/tmp",
           "--hostname",
           sandbox_id,
           "--new-session",
           "--die-with-parent",
           "--cap-drop",
           "ALL",
           "--clearenv",
           "--chdir",
           "/workspace"
         ] ++
         ["--", "/bin/sh", @runtime_env_launcher, launch.executable | launch.args]}
    end
  end

  defp validate_network(network) when network in [:open, :none], do: :ok
  defp validate_network(network), do: {:error, {:unsupported_bwrap_network, network}}

  defp normalize_privilege_mode(value) when value in [nil, :rootless, "rootless"],
    do: {:ok, :rootless}

  defp normalize_privilege_mode(value) when value in [:cgroup, "cgroup"], do: {:ok, :cgroup}

  defp normalize_privilege_mode(value),
    do: {:error, {:unsupported_bwrap_privilege_mode, value}}

  defp prepare_directories(config) do
    with :ok <- File.mkdir_p(config.workspace),
         :ok <- RunnerHelpers.private_dir(config.state_dir),
         :ok <- RunnerHelpers.validate_mount_path(config.workspace),
         :ok <- RunnerHelpers.validate_mount_path(config.state_dir),
         :ok <- maybe_validate_skills(config),
         {:ok, _names} <- RunnerHelpers.pass_env(config),
         {:ok, _pairs} <- RunnerHelpers.runner_env(config),
         {:ok, _ro, _rw} <- RunnerHelpers.extra_binds(config) do
      :ok
    end
  end

  defp maybe_validate_skills(%{skills_dir: path}) when is_binary(path) do
    with true <- File.dir?(path) or {:error, {:skills_dir_not_found, path}},
         :ok <- RunnerHelpers.validate_mount_path(Path.expand(path)) do
      :ok
    end
  end

  defp maybe_validate_skills(_config), do: :ok

  defp prepare_client(%{client_source: :runtime}, launch), do: {:ok, launch, []}

  defp prepare_client(%{client_source: :host_nix} = config, launch) do
    RunnerStore.resolve_host_launch(config, launch)
  end

  defp prepare_overlay(config, sandbox_id, %{dead?: false}, fingerprint) do
    overlay_dir = overlay_dir(sandbox_id)

    with true <-
           File.dir?(overlay_dir) or
             {:error, {:runner_state_mismatch, :live_pane_without_overlay}},
         :ok <- verify_fingerprint(overlay_dir, fingerprint) do
      {:ok, overlay_dir, rootless_base(config), false}
    end
  end

  defp prepare_overlay(config, sandbox_id, _pane_state, fingerprint) do
    CgroupManager.kill_scope(scope_name(config, sandbox_id))
    OverlayManager.cleanup_overlay(sandbox_id)
    presets = Map.get(config, :presets, [:base])

    result =
      case Map.get(config, :privilege_mode, :cgroup) do
        value when value in [:rootless, "rootless"] ->
          with {:ok, dir, base} <- OverlayManager.setup_overlay(sandbox_id, presets, :rootless),
               :ok <- seed_overlay(dir) do
            {:ok, dir, base, true}
          end

        _ ->
          case OverlayManager.setup_overlay(sandbox_id, presets, seed: &seed_overlay/1) do
            {:ok, dir} -> {:ok, dir, nil, true}
            {:error, _} = error -> error
          end
      end

    case result do
      {:ok, dir, _base, true} = ok ->
        case write_fingerprint(dir, fingerprint) do
          :ok ->
            ok

          {:error, _} = error ->
            OverlayManager.cleanup_overlay(sandbox_id)
            error
        end

      {:error, _} = error ->
        OverlayManager.cleanup_overlay(sandbox_id)
        error
    end
  end

  defp finish_prepare(
         config,
         bwrap,
         sandbox_id,
         overlay_dir,
         rootless_base,
         created?,
         client_store_paths,
         launch,
         env_pairs,
         fingerprint
       ) do
    result =
      try do
        with :ok <- write_environment_files(config.state_dir, env_pairs),
             {:ok, store_paths} <- store_paths(config, rootless_base, client_store_paths),
             {:ok, bwrap_args} <-
               build_bwrap_args(
                 config,
                 bwrap,
                 sandbox_id,
                 overlay_dir,
                 rootless_base,
                 store_paths,
                 launch,
                 env_pairs
               ) do
          wrapped_args =
            SeccompProfile.maybe_wrap_bwrap_args!(sandbox_id, overlay_dir, bwrap_args, config)

          cgroup_opts = %{
            memory_max: memory_limit(config),
            cpu_shares: Map.get(config, :cpu_shares, 100),
            tasks_max: Map.get(config, :tasks_max, 50)
          }

          {executable, args, scope_name} =
            BwrapBackend.resource_wrapper(config, sandbox_id, wrapped_args, cgroup_opts)

          ref = %__MODULE__{
            config: config,
            sandbox_id: sandbox_id,
            overlay_dir: overlay_dir,
            scope_name: scope_name,
            workspace: config.workspace,
            state_dir: config.state_dir,
            client: config.client,
            network: config.runner_network,
            privilege_mode: Map.get(config, :privilege_mode, :cgroup),
            client_source: config.client_source,
            fingerprint: fingerprint,
            created?: created?
          }

          ArgvFile.wrap(config, %{executable: executable, args: args, env: []})
          |> case do
            {:ok, pane_launch} -> {:ok, ref, pane_launch}
            {:error, _} = error -> error
          end
        end
      rescue
        error -> {:error, {:bwrap_prepare_failed, Exception.message(error)}}
      end

    case result do
      {:ok, _ref, _launch} = ok ->
        ok

      {:error, _} = error ->
        cleanup_failed_prepare(config, sandbox_id, created?)
        error
    end
  end

  defp cleanup_failed_prepare(config, sandbox_id, true) do
    CgroupManager.kill_scope(scope_name(config, sandbox_id))
    OverlayManager.cleanup_overlay(sandbox_id)
  end

  defp cleanup_failed_prepare(_config, _sandbox_id, false), do: :ok

  defp runner_fingerprint(config, bwrap, launch, env_pairs) do
    {:ok, ro, rw} = RunnerHelpers.extra_binds(config)

    contract = %{
      bwrap: bwrap,
      launch: launch,
      workspace: config.workspace,
      state_dir: config.state_dir,
      skills_dir: Map.get(config, :skills_dir),
      network: config.runner_network,
      client_source: config.client_source,
      base_layer: OverlayManager.get_base_layer(Map.get(config, :presets, [:base])),
      privilege_mode: Map.get(config, :privilege_mode, :cgroup),
      store: Map.get(config, :store, :full),
      extra_store_paths: Map.get(config, :extra_store_paths, []),
      client_store_paths: Map.get(config, :client_store_paths),
      extra_ro_binds: ro,
      extra_rw_binds: rw,
      memory_limit: memory_limit(config),
      cpu_shares: Map.get(config, :cpu_shares, 100),
      tasks_max: Map.get(config, :tasks_max, 50),
      nice: Map.get(config, :nice, 19),
      seccomp: SeccompProfile.enabled?(config),
      env: env_pairs
    }

    :sha256
    |> :crypto.hash(:erlang.term_to_binary(contract, [:deterministic]))
    |> Base.encode16(case: :lower)
  end

  defp write_fingerprint(overlay_dir, fingerprint) do
    path = Path.join(overlay_dir, @identity_file)

    with :ok <- File.write(path, fingerprint, [:binary]),
         :ok <- File.chmod(path, 0o600) do
      :ok
    end
  end

  defp verify_fingerprint(overlay_dir, fingerprint) do
    path = Path.join(overlay_dir, @identity_file)

    case File.read(path) do
      {:ok, ^fingerprint} -> :ok
      {:ok, _other} -> {:error, {:runner_state_mismatch, :bwrap_config_changed}}
      {:error, :enoent} -> {:error, {:runner_state_mismatch, :bwrap_identity_missing}}
      {:error, reason} -> {:error, {:bwrap_identity_read_failed, reason}}
    end
  end

  defp seed_overlay(dir) do
    etc = Path.join([dir, "upper", "etc"])
    root = Path.join([dir, "upper", "root"])

    with :ok <- File.mkdir_p(etc),
         :ok <- File.mkdir_p(root),
         :ok <- copy_if_present("/etc/resolv.conf", Path.join(etc, "resolv.conf")),
         :ok <- copy_if_present("/etc/hosts", Path.join(etc, "hosts")) do
      :ok
    end
  end

  defp copy_if_present(source, target) do
    if File.regular?(source), do: File.cp(source, target), else: :ok
  end

  defp store_paths(config, rootless_base, client_paths) do
    case Map.get(config, :store, :full) do
      value when value in [:full, "full"] ->
        {:ok, ["/nix/store"]}

      value when value in [:closure, "closure"] ->
        base = rootless_base || OverlayManager.get_base_layer(Map.get(config, :presets, [:base]))

        with {:ok, base_root} <- OverlayManager.ensure_store_path(base),
             {:ok, base_paths} <- RunnerStore.query_closure(config, base_root),
             {:ok, extra} <- validate_extra_store_paths(config) do
          {:ok, Enum.uniq(base_paths ++ client_paths ++ extra)}
        end

      other ->
        {:error, {:unknown_store_mode, other}}
    end
  end

  defp validate_extra_store_paths(config) do
    paths = Map.get(config, :extra_store_paths, [])

    if is_list(paths) and Enum.all?(paths, &RunnerStore.valid_store_path?/1),
      do: {:ok, paths},
      else: {:error, {:invalid_extra_store_paths, paths}}
  end

  defp environment(config, launch) do
    with {:ok, names} <- RunnerHelpers.pass_env(config),
         {:ok, configured} <- RunnerHelpers.runner_env(config),
         {:ok, passed} <- fetch_passed_env(names),
         {:ok, launch_env} <- validate_launch_env(Map.get(launch, :env, [])) do
      fixed = [
        {"HOME", "/root"},
        {"PATH", "/bin:/usr/bin:/usr/local/bin"},
        {"TERM", "xterm-256color"},
        {"XDG_CONFIG_HOME", "/root/.config"},
        {"XDG_DATA_HOME", "/root/.local/share"},
        {"XDG_STATE_HOME", "/root/.local/state"}
      ]

      {:ok, dedupe_env(configured ++ passed ++ launch_env ++ fixed)}
    end
  end

  defp fetch_passed_env(names) do
    case Enum.find(names, &is_nil(System.get_env(&1))) do
      nil -> {:ok, Enum.map(names, &{&1, System.fetch_env!(&1)})}
      missing -> {:error, {:missing_pass_env, missing}}
    end
  end

  defp validate_launch_env(env) when is_list(env) do
    if Enum.all?(env, fn
         {key, value} -> is_binary(key) and is_binary(value)
         _ -> false
       end),
       do: {:ok, env},
       else: {:error, :invalid_launch_env}
  end

  defp validate_launch_env(_env), do: {:error, :invalid_launch_env}

  defp dedupe_env(pairs) do
    pairs
    |> Enum.reduce(%{}, fn {key, value}, acc -> Map.put(acc, key, value) end)
    |> Enum.sort()
  end

  # bwrap's --setenv puts values in the host-visible argv. Persist the selected
  # environment as private data inside the already-private client HOME and use
  # a constant container-local bootstrap script instead. Values are POSIX-shell
  # quoted and never interpolated into the launcher body or a host shell.
  @doc false
  def write_environment_files(state_dir, env_pairs) do
    dir = Path.join(state_dir, ".genswarms")
    env_path = Path.join(dir, "runner.env")
    launcher_path = Path.join(dir, "launch-with-env")

    env_body =
      Enum.map_join(env_pairs, "", fn {key, value} ->
        "#{key}=#{shell_quote(value)}\n"
      end)

    launcher = "#!/bin/sh\nset -a\n. #{@runtime_env_file}\nset +a\nexec \"$@\"\n"

    with :ok <- RunnerHelpers.private_dir(dir),
         :ok <- write_private_atomic(env_path, env_body, 0o600),
         :ok <- write_private_atomic(launcher_path, launcher, 0o700) do
      :ok
    end
  end

  defp write_private_atomic(path, body, mode) do
    tmp = path <> ".tmp-#{System.unique_integer([:positive])}"

    with :ok <- File.write(tmp, body, [:binary]),
         :ok <- File.chmod(tmp, mode),
         :ok <- File.rename(tmp, path) do
      :ok
    else
      {:error, _} = error ->
        _ = File.rm(tmp)
        error
    end
  end

  defp shell_quote(value), do: "'" <> String.replace(value, "'", "'\"'\"'") <> "'"

  defp skills_mount(%{skills_dir: path}) when is_binary(path),
    do: ["--ro-bind", Path.expand(path), "/skills"]

  defp skills_mount(_config), do: []

  defp rootless_base(config) do
    case Map.get(config, :privilege_mode, :cgroup) do
      value when value in [:rootless, "rootless"] ->
        OverlayManager.get_base_layer(Map.get(config, :presets, [:base]))

      _ ->
        nil
    end
  end

  defp memory_limit(%{privilege_mode: :rootless} = config),
    do: Map.get(config, :memory_limit)

  defp memory_limit(config), do: Map.get(config, :memory_limit, "2G")

  defp overlay_dir(sandbox_id) do
    root = Application.get_env(:genswarms, :bwrap_agents_dir, "/run/swarm/agents")
    Path.join(root, sandbox_id)
  end

  defp scope_name(config, sandbox_id) do
    case Map.get(config, :privilege_mode, :cgroup) do
      value when value in [:rootless, "rootless"] -> nil
      _ -> "szc-#{sandbox_id}"
    end
  end
end
