defmodule Genswarms.Backends.Bwrap.OverlayManager do
  @moduledoc """
  Manages per-agent root filesystems for bwrap sandboxes.

  In `:cgroup` mode, uses fuse-overlayfs (userspace overlay filesystem) to
  create per-agent writable layers on top of shared read-only Nix base layers.
  In `:rootless` mode, materializes the Nix base's symlink forest into the
  per-agent `merged/` directory and binds that directory as `/`. This avoids
  nested overlayfs mounts, which managed container filesystems commonly reject
  even when unprivileged user namespaces themselves are enabled.

  ## Directory Structure

      /run/swarm/
      ├── sandbox-base/          # Symlinks to pre-built Nix environments
      │   ├── base -> /nix/store/...
      │   ├── web -> /nix/store/...
      │   └── code -> /nix/store/...
      └── agents/{sandbox_id}/   # Per-agent (on tmpfs)
          ├── upper/             # Seed/COW writes
          ├── work/              # Overlay workdir (:cgroup only)
          └── merged/            # Mounted union or materialized root

  ## Requirements

  - fuse-overlayfs installed (`:cgroup` mode only)
  - /run/swarm mounted as tmpfs (configured via NixOS module)
  - Pre-built sandbox bases via `nix build .#sandboxBase-*`
  """

  require Logger

  @swarm_base_dir "/run/swarm"
  @sandbox_bases_dir "/run/swarm/sandbox-base"
  @agents_dir "/run/swarm/agents"

  # bwrap can create bind destinations only when all of their parents are
  # writable. Rootless roots start as the tiny Nix buildEnv symlink forest, so
  # create the standard mount destinations up front. Arbitrary extra binds are
  # still created by bwrap under this writable per-agent root.
  @rootless_mount_dirs [
    "nix/store",
    "root/.subzeroclaw/skills",
    "root/.subzeroclaw/logs",
    "workspace",
    "usr/local/bin",
    "usr/bin",
    "run/secrets",
    "skills",
    "proc",
    "dev",
    "tmp"
  ]

  @doc """
  Sets up an overlay filesystem for an agent sandbox.

  Creates the upper/work/merged directories and mounts fuse-overlayfs.

  Returns `{:ok, overlay_dir}` or `{:error, reason}`.
  """
  @spec setup_overlay(String.t(), [atom()]) :: {:ok, String.t()} | {:error, term()}
  def setup_overlay(sandbox_id, presets), do: setup_overlay(sandbox_id, presets, [])

  @doc """
  As `setup_overlay/2`, with options:

    * `:mode` — `:cgroup` (default) mounts fuse-overlayfs; `:rootless`
      materializes a writable per-agent root and returns its resolved base as
      `{:ok, agent_dir, base_layer}`.
    * `:seed` — `fn agent_dir -> :ok end`, invoked AFTER the upper/work/merged
      dirs exist and BEFORE the root is mounted/materialized. This is the only
      safe moment to write seed files (DNS, harness config) into `upper/`:
      mutating it behind a live FUSE daemon is undefined, and rootless mode
      merges it into `merged/` during materialization. A raising or non-`:ok`
      seed aborts the setup — fail closed.
  """
  @spec setup_overlay(String.t(), [atom()], keyword() | :rootless) ::
          {:ok, String.t()} | {:ok, String.t(), String.t()} | {:error, term()}
  def setup_overlay(sandbox_id, presets, opts) when is_list(opts) do
    case Keyword.get(opts, :mode, :cgroup) do
      :rootless -> setup_rootless(sandbox_id, presets, opts)
      :cgroup -> setup_cgroup(sandbox_id, presets, opts)
      mode -> {:error, {:unsupported_root_mode, mode}}
    end
  end

  # Kept for callers using the original rootless API. New callers should pass
  # `mode: :rootless` so a seed callback can be staged before materialization.
  def setup_overlay(sandbox_id, presets, :rootless) do
    setup_overlay(sandbox_id, presets, mode: :rootless)
  end

  defp setup_cgroup(sandbox_id, presets, opts) do
    agent_dir = Path.join(agents_dir(), sandbox_id)
    upper_dir = Path.join(agent_dir, "upper")
    work_dir = Path.join(agent_dir, "work")
    merged_dir = Path.join(agent_dir, "merged")

    with :ok <- ensure_base_dirs_exist(),
         :ok <- create_agent_dirs(agent_dir, upper_dir, work_dir, merged_dir),
         {:ok, base_layer} <- resolve_base_layer(presets),
         :ok <- run_seed(Keyword.get(opts, :seed), agent_dir),
         :ok <- mount_overlay(base_layer, upper_dir, work_dir, merged_dir) do
      {:ok, agent_dir}
    end
  end

  # Rootless deliberately avoids both host-side FUSE and bwrap's nested kernel
  # overlay. The latter fails with EINVAL on common Kubernetes/containerd
  # backing filesystems even though a basic bwrap user namespace works. Nix
  # buildEnv roots are mostly symlinks into /nix/store, so materializing their
  # directory/symlink skeleton is cheap while retaining per-agent writes.
  defp setup_rootless(sandbox_id, presets, opts) do
    agent_dir = Path.join(agents_dir(), sandbox_id)
    upper_dir = Path.join(agent_dir, "upper")
    work_dir = Path.join(agent_dir, "work")
    merged_dir = Path.join(agent_dir, "merged")

    with {:ok, base_layer} <- resolve_base_layer(presets),
         :ok <- create_agent_dirs(agent_dir, upper_dir, work_dir, merged_dir),
         :ok <- run_seed(Keyword.get(opts, :seed), agent_dir),
         :ok <- materialize_root(base_layer, upper_dir, merged_dir) do
      {:ok, agent_dir, base_layer}
    else
      {:error, {:mkdir_failed, reason}} -> {:error, {:mkdir_failed, reason}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp run_seed(nil, _agent_dir), do: :ok

  defp run_seed(seed, agent_dir) when is_function(seed, 1) do
    case seed.(agent_dir) do
      :ok -> :ok
      other -> {:error, {:seed_failed, other}}
    end
  rescue
    e -> {:error, {:seed_failed, Exception.message(e)}}
  end

  defp materialize_root(base_layer, upper_dir, merged_dir) do
    with {:ok, []} <- File.ls(merged_dir),
         :ok <- merge_tree(base_layer, merged_dir),
         :ok <- merge_tree(upper_dir, merged_dir),
         :ok <- ensure_mount_dirs(merged_dir),
         :ok <- sync_modes(upper_dir, merged_dir) do
      :ok
    else
      {:ok, _entries} -> {:error, {:materialize_failed, :merged_not_empty}}
      {:error, reason} -> {:error, {:materialize_failed, reason}}
    end
  end

  # Merge without ever following a destination symlink. File.cp_r/2 follows a
  # destination symlink on conflicts, which could otherwise attempt to write
  # through the Nix base into /nix/store when applying the seed layer.
  defp merge_tree(source, destination) do
    with {:ok, entries} <- File.ls(source) do
      Enum.reduce_while(entries, :ok, fn entry, :ok ->
        case merge_entry(Path.join(source, entry), Path.join(destination, entry)) do
          :ok -> {:cont, :ok}
          {:error, _} = error -> {:halt, error}
        end
      end)
    end
  end

  defp merge_entry(source, destination) do
    case File.lstat(source) do
      {:ok, %{type: :directory}} ->
        case File.lstat(destination) do
          {:ok, %{type: :directory}} ->
            merge_tree(source, destination)

          {:error, :enoent} ->
            copy_path(source, destination)

          {:ok, _other} ->
            with :ok <- remove_path(destination), do: copy_path(source, destination)

          {:error, reason} ->
            {:error, {:stat_failed, destination, reason}}
        end

      {:ok, _other} ->
        with :ok <- remove_path(destination), do: copy_path(source, destination)

      {:error, reason} ->
        {:error, {:stat_failed, source, reason}}
    end
  end

  defp copy_path(source, destination) do
    case File.cp_r(source, destination) do
      {:ok, _paths} -> :ok
      {:error, reason, path} -> {:error, {:copy_failed, path, reason}}
    end
  end

  # File.cp_r/2 preserves regular-file modes but creates directories using the
  # process umask. Re-apply seed-layer permissions after all mountpoints exist,
  # most importantly 0700 on /run/secrets and 0600 on provider credentials.
  # Children are handled first so a restrictive parent mode cannot block the
  # remainder of the traversal.
  defp sync_modes(source, destination) do
    case File.lstat(source) do
      {:ok, %{type: :directory, mode: mode}} ->
        with {:ok, entries} <- File.ls(source),
             :ok <- sync_child_modes(entries, source, destination),
             :ok <- File.chmod(destination, Bitwise.band(mode, 0o777)) do
          :ok
        end

      {:ok, %{type: :regular, mode: mode}} ->
        File.chmod(destination, Bitwise.band(mode, 0o777))

      {:ok, %{type: :symlink}} ->
        :ok

      {:ok, _other} ->
        :ok

      {:error, reason} ->
        {:error, {:stat_failed, source, reason}}
    end
  end

  defp sync_child_modes(entries, source, destination) do
    Enum.reduce_while(entries, :ok, fn entry, :ok ->
      case sync_modes(Path.join(source, entry), Path.join(destination, entry)) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp remove_path(path) do
    case File.lstat(path) do
      {:error, :enoent} ->
        :ok

      {:ok, _} ->
        case File.rm_rf(path) do
          {:ok, _paths} -> :ok
          {:error, reason, failed_path} -> {:error, {:remove_failed, failed_path, reason}}
        end

      {:error, reason} ->
        {:error, {:stat_failed, path, reason}}
    end
  end

  defp ensure_mount_dirs(root) do
    Enum.reduce_while(@rootless_mount_dirs, :ok, fn relative, :ok ->
      case ensure_relative_dir(root, Path.split(relative)) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp ensure_relative_dir(_current, []), do: :ok

  defp ensure_relative_dir(current, [segment | rest]) do
    path = Path.join(current, segment)

    result =
      case File.lstat(path) do
        {:ok, %{type: :directory}} ->
          :ok

        {:error, :enoent} ->
          File.mkdir(path)

        {:ok, _other} ->
          with :ok <- remove_path(path), do: File.mkdir(path)

        {:error, reason} ->
          {:error, reason}
      end

    with :ok <- result, do: ensure_relative_dir(path, rest)
  end

  @doc """
  Cleans up an overlay filesystem.

  Unmounts the overlay and removes all per-agent directories.
  """
  @spec cleanup_overlay(String.t()) :: :ok
  def cleanup_overlay(sandbox_id) do
    agent_dir = Path.join(agents_dir(), sandbox_id)
    merged_dir = Path.join(agent_dir, "merged")

    # Unmount fuse-overlayfs
    unmount_overlay(merged_dir)

    # Remove agent directory
    case File.rm_rf(agent_dir) do
      {:ok, _} ->
        :ok

      {:error, reason, _} ->
        Logger.warning("Failed to cleanup overlay for #{sandbox_id}: #{inspect(reason)}")
        :ok
    end
  end

  @doc """
  Gets the path to the base layer for the given presets.

  Base layers are pre-built Nix store paths containing all tools
  for a preset combination.
  """
  @spec get_base_layer([atom()]) :: String.t()
  def get_base_layer(presets) do
    preset_name = presets_to_name(presets)
    base_path = Path.join(@sandbox_bases_dir, preset_name)

    if File.exists?(base_path) do
      # Follow the complete symlink chain. Deployments commonly use
      # /run/swarm/... -> checkout/result -> /nix/store/...; resolving only
      # the first hop makes a valid Nix base fail `store: :closure`.
      case :file.read_link_all(String.to_charlist(base_path)) do
        {:ok, target} -> List.to_string(target)
        {:error, _} -> base_path
      end
    else
      # Fallback to base preset
      Path.join(@sandbox_bases_dir, "base")
    end
  end

  @doc """
  Canonical /nix/store path of the base layer the overlay ACTUALLY mounts for `presets`
  — resolved via the SAME `resolve_base_layer/1` that `setup_overlay/2` uses, so the
  closure is computed against the exact lower layer (not the divergent `get_base_layer/1`).
  `{:error, {:base_not_store_path, _}}` for a non-store ({:custom, dir}) base — :closure is
  unsupported there (a non-store dir has no `nix-store` closure).
  """
  @spec base_store_path([atom()]) :: {:ok, String.t()} | {:error, term()}
  def base_store_path(presets) do
    with {:ok, base} <- resolve_base_layer(presets), do: ensure_store_path(base)
  end

  @doc false
  @spec ensure_store_path(String.t()) :: {:ok, String.t()} | {:error, term()}
  def ensure_store_path("/nix/store/" <> _ = path), do: {:ok, path}

  def ensure_store_path(path) when is_binary(path) do
    case :file.read_link_all(String.to_charlist(path)) do
      {:ok, resolved} -> resolved |> List.to_string() |> ensure_store_path()
      {:error, _} -> {:error, {:base_not_store_path, path}}
    end
  end

  def ensure_store_path(other), do: {:error, {:base_not_store_path, other}}

  @doc """
  Checks if the swarm base directories exist.
  Returns true if the bwrap infrastructure is set up.
  """
  @spec infrastructure_ready?() :: boolean()
  def infrastructure_ready? do
    File.dir?(@swarm_base_dir) &&
      File.dir?(@sandbox_bases_dir) &&
      File.exists?(Path.join(@sandbox_bases_dir, "base"))
  end

  @doc """
  Lists all active sandbox overlay directories.
  """
  @spec list_active_sandboxes() :: [String.t()]
  def list_active_sandboxes do
    case File.ls(agents_dir()) do
      {:ok, dirs} -> dirs
      {:error, _} -> []
    end
  end

  @doc """
  Gets memory usage of an overlay seed/COW directory.
  """
  @spec get_overlay_size(String.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def get_overlay_size(sandbox_id) do
    upper_dir = Path.join([agents_dir(), sandbox_id, "upper"])

    case System.cmd("du", ["-sb", upper_dir], stderr_to_stdout: true) do
      {output, 0} ->
        [size_str | _] = String.split(output)
        {:ok, String.to_integer(size_str)}

      {_, _} ->
        {:error, :not_found}
    end
  end

  # Private functions

  # Overridable for tests and non-/run hosts; default unchanged.
  defp agents_dir do
    Application.get_env(:genswarms, :bwrap_agents_dir, @agents_dir)
  end

  defp ensure_base_dirs_exist do
    cond do
      not File.dir?(@swarm_base_dir) ->
        {:error, {:missing_swarm_dir, @swarm_base_dir}}

      not File.dir?(@sandbox_bases_dir) ->
        {:error, {:missing_sandbox_bases, @sandbox_bases_dir}}

      true ->
        # Ensure agents directory exists
        File.mkdir_p(agents_dir())
        :ok
    end
  end

  defp create_agent_dirs(agent_dir, upper_dir, work_dir, merged_dir) do
    with :ok <- File.mkdir_p(agent_dir),
         :ok <- File.mkdir_p(upper_dir),
         :ok <- File.mkdir_p(work_dir),
         :ok <- File.mkdir_p(merged_dir) do
      :ok
    else
      {:error, reason} -> {:error, {:mkdir_failed, reason}}
    end
  end

  defp resolve_base_layer(presets) when is_list(presets) do
    # Check for a custom base layer path in the presets
    # e.g., presets: [{:custom, "/path/to/my/base"}, :base]
    case Enum.find(presets, fn p -> match?({:custom, _}, p) end) do
      {:custom, custom_path} ->
        expanded = Path.expand(custom_path)

        if File.dir?(expanded) do
          Logger.info("[OverlayManager] Using custom base layer: #{expanded}")
          {:ok, expanded}
        else
          {:error, {:custom_base_not_found, expanded}}
        end

      nil ->
        resolve_named_preset(presets)
    end
  end

  defp resolve_named_preset(presets) do
    preset_name = presets_to_name(presets)

    # Search in system dir + any extra dirs registered by downstream projects
    # e.g., Application.put_env(:genswarms, :extra_preset_dirs, ["/my/presets"])
    search_dirs = [
      @sandbox_bases_dir
      | Application.get_env(:genswarms, :extra_preset_dirs, [])
    ]

    # Look for the preset in all search directories
    found =
      Enum.find_value(search_dirs, fn dir ->
        path = Path.join(dir, preset_name)
        if File.exists?(path), do: resolve_symlink(path)
      end)

    cond do
      found ->
        {:ok, found}

      preset_name != "base" ->
        # Try falling back to base in any search dir
        fallback =
          Enum.find_value(search_dirs, fn dir ->
            path = Path.join(dir, "base")
            if File.exists?(path), do: resolve_symlink(path)
          end)

        if fallback do
          Logger.warning("Preset #{preset_name} not found, falling back to base")
          {:ok, fallback}
        else
          {:error, {:base_layer_not_found, preset_name}}
        end

      true ->
        {:error, {:base_layer_not_found, preset_name}}
    end
  end

  defp resolve_symlink(path) do
    case File.read_link(path) do
      {:ok, target} ->
        if String.starts_with?(target, "/") do
          target
        else
          Path.join(Path.dirname(path), target)
        end

      {:error, :einval} ->
        # Not a symlink, return as-is
        path

      {:error, _} ->
        path
    end
  end

  defp mount_overlay(base_layer, upper_dir, work_dir, merged_dir) do
    # Use fuse-overlayfs for userspace overlay mounting
    # Format: fuse-overlayfs -o lowerdir=X,upperdir=Y,workdir=Z MOUNTPOINT
    cmd = "fuse-overlayfs"

    args = [
      "-o",
      "lowerdir=#{base_layer},upperdir=#{upper_dir},workdir=#{work_dir}",
      merged_dir
    ]

    case System.cmd(cmd, args, stderr_to_stdout: true) do
      {_, 0} ->
        :ok

      {output, code} ->
        Logger.error("fuse-overlayfs mount failed (exit #{code}): #{output}")
        {:error, {:mount_failed, output}}
    end
  end

  defp unmount_overlay(merged_dir) do
    # fusermount -u for userspace unmount. In :rootless mode nothing was ever
    # mounted host-side — and the image may not even ship fusermount — so a
    # missing binary is as benign as an already-unmounted dir.
    case System.cmd("fusermount", ["-u", merged_dir], stderr_to_stdout: true) do
      {_, 0} ->
        :ok

      {output, _} ->
        # May already be unmounted
        Logger.debug("Unmount of #{merged_dir}: #{output}")
        :ok
    end
  rescue
    e in ErlangError ->
      Logger.debug("fusermount unavailable (#{inspect(e.original)}) — nothing to unmount")
      :ok
  end

  defp presets_to_name(presets) do
    # Sort for consistent naming, filter out custom tuples
    presets
    |> Enum.reject(&match?({:custom, _}, &1))
    |> Enum.sort()
    |> Enum.map(&Atom.to_string/1)
    |> Enum.join("-")
  end
end
