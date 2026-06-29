defmodule Genswarms.Backends.OciCli do
  @moduledoc """
  Shared core for OCI-CLI container backends (Docker and Apple `container`).

  Apple's `container` CLI is docker-compatible for the surface genswarms uses
  (`run`/`stop`/`inspect`/`--env`/`--volume`/`--memory`/`--cpus`). This module
  holds the argv builders both backends share — preset→image selection, the
  in-container bootstrap, env/volume/resource args — parameterized by the few
  real differences between the two CLIs:

    * the executable name (`docker` vs `container`),
    * the env flag (`-e` vs `--env`),
    * the read-only / read-write mount syntax (`-v host:c:ro` vs
      `--mount type=bind,...,readonly`).

  What is genuinely backend-specific stays in each backend: Docker's egress
  guard + `--network none`, Apple's isolated-network fail-closed, image
  loading, and the container lifecycle/inspect commands.
  """

  require Logger

  # Pre-built NixOS container images by (sorted) preset combination.
  @preset_images %{
    [:base] => "szc-agent-base:latest",
    [:base, :web] => "szc-agent-web:latest",
    [:base, :code] => "szc-agent-code:latest",
    [:base, :data] => "szc-agent-data:latest",
    [:base, :python] => "szc-agent-python:latest",
    [:base, :node] => "szc-agent-node:latest",
    [:base, :code, :data, :node, :python, :web] => "szc-agent-full:latest",
    [:base, :cloud, :code, :containers] => "szc-agent-devops:latest"
  }

  @default_image "szc-agent-base:latest"

  @doc "The preset→image table (sorted-preset keys)."
  def preset_images, do: @preset_images

  @doc """
  Selects the image from an explicit `:image`/`:container` or a preset set,
  falling back to the base image.
  """
  def determine_image(config) do
    cond do
      Map.has_key?(config, :image) ->
        config.image

      Map.has_key?(config, :container) ->
        config.container

      Map.has_key?(config, :presets) ->
        Map.get(@preset_images, Enum.sort(config.presets), @default_image)

      true ->
        @default_image
    end
  end

  @doc "Nix flake output suffix for a preset combination."
  def preset_to_build_name([:base]), do: "base"
  def preset_to_build_name([:base, :web]), do: "web"
  def preset_to_build_name([:base, :code]), do: "code"
  def preset_to_build_name([:base, :data]), do: "data"
  def preset_to_build_name([:base, :python]), do: "python"
  def preset_to_build_name([:base, :node]), do: "node"
  def preset_to_build_name([:base, :code, :containers, :cloud]), do: "devops"
  def preset_to_build_name(_), do: "full"

  @doc """
  Default in-container bootstrap as an argv list (`["sh", "-c", script, ...]`),
  passed to `<cli> run IMAGE sh -c <script>` so it runs in the *container's*
  shell, never the host's. The agent name rides as `$1` (never interpolated
  into the script). A configured integer `:max_turns` is appended to the
  harness config; a non-integer is dropped with a warning (the integer guard
  is the injection defense).
  """
  def default_container_cmd(agent_name, config, backend_label) do
    budget =
      case Map.get(config, :max_turns) do
        n when is_integer(n) and n > 0 ->
          " && echo \"max_turns = #{n}\" >> /root/.subzeroclaw/config"

        nil ->
          ""

        bad ->
          Logger.warning(
            "#{backend_label}: ignoring non-integer max_turns #{inspect(bad)} — step budget NOT applied"
          )

          ""
      end

    [
      "sh",
      "-c",
      "export HOME=/root && mkdir -p /root/.subzeroclaw /root/build && echo \"skills_dir = /skills\" > /root/.subzeroclaw/config#{budget} && cp -r /src/subzeroclaw/* /root/build/ && cd /root/build && make -s 2>/dev/null && exec bash /src/genswarms-priv/szc-wrapper-fifo.sh \"$1\" /root/build/subzeroclaw /skills",
      "szc-wrapper",
      to_string(agent_name)
    ]
  end

  @doc """
  Normalizes a user-supplied `:cmd` (runs *inside the container*): a list is
  used as argv; a bare string is wrapped as `sh -c <string>` (container shell,
  host-safe); `nil` falls back to the default bootstrap.
  """
  def normalize_container_cmd(nil, agent_name, config, backend_label),
    do: default_container_cmd(agent_name, config, backend_label)

  def normalize_container_cmd(cmd, _agent_name, _config, _label) when is_list(cmd),
    do: Enum.map(cmd, &to_string/1)

  def normalize_container_cmd(cmd, _agent_name, _config, _label) when is_binary(cmd),
    do: ["sh", "-c", cmd]

  @doc "Accept a `:request_extra`/`:compact_extra`-style key as a JSON string or a map."
  def config_json(config, key) do
    case Map.get(config, key) do
      nil -> nil
      v when is_binary(v) -> v
      v when is_map(v) -> Jason.encode!(v)
      _ -> nil
    end
  end

  @doc """
  Builds the env argv. `env_flag` is the CLI's per-var flag (`-e` / `--env`).
  `extra_pairs` ({"KEY","VAL"} tuples) are inserted after the endpoint var and
  before the operator-supplied `:env` map — used for backend-specific vars
  (Docker's `CURL_HOME`/`SWARM_TOPOLOGY`). Every value is a single literal
  argv element; the CLI never runs them through a shell.
  """
  def build_env_args(api_key, model, endpoint, agent_name, config, env_flag, extra_pairs \\ []) do
    request_extra =
      config_json(config, :request_extra) || (model && Jason.encode!(%{"model" => model}))

    compact_extra = config_json(config, :compact_extra)

    pairs =
      [{"SUBZEROCLAW_AGENT_NAME", to_string(agent_name)}]
      |> maybe_pair(api_key, "SUBZEROCLAW_API_KEY")
      |> maybe_pair(request_extra, "SUBZEROCLAW_REQUEST_EXTRA")
      |> maybe_pair(compact_extra, "SUBZEROCLAW_COMPACT_EXTRA")
      |> maybe_pair(endpoint, "SUBZEROCLAW_ENDPOINT")
      |> Kernel.++(extra_pairs)
      |> Kernel.++(additional_env_pairs(config))

    Enum.flat_map(pairs, fn {k, v} -> [env_flag, "#{k}=#{v}"] end)
  end

  defp maybe_pair(pairs, nil, _key), do: pairs
  defp maybe_pair(pairs, value, key), do: pairs ++ [{key, value}]

  defp additional_env_pairs(config) do
    Map.get(config, :env, %{})
    |> Enum.map(fn {k, v} -> {to_string(k), expand_env_var(v)} end)
    |> Enum.filter(fn {_k, v} -> v != nil and v != "" end)
  end

  @doc "Expands `${VAR}` and `$VAR` patterns against the host environment."
  def expand_env_var(value) when is_binary(value) do
    Regex.replace(~r/\$\{([A-Z_][A-Z0-9_]*)\}/, value, fn _, var_name ->
      System.get_env(var_name) || ""
    end)
    |> then(fn v ->
      Regex.replace(~r/\$([A-Z_][A-Z0-9_]*)/, v, fn _, var_name ->
        System.get_env(var_name) || ""
      end)
    end)
  end

  def expand_env_var(value), do: value

  @doc """
  Builds the volume argv shared by both backends. `ro`/`rw` are 2-arity
  builders `(host, container) -> [argv...]` supplying the CLI's read-only /
  read-write mount syntax. Mounts skills (ro), logs (rw), workspace (rw,
  unless an explicit `/workspace` volume is given), `/tmp` (rw), the genswarms
  priv dir (ro) and the subzeroclaw source (ro), then any operator `:volumes`.
  """
  def build_volume_args(skills_dir, config, ro, rw) do
    additional_vols = Map.get(config, :volumes, [])

    has_workspace_mount =
      Enum.any?(additional_vols, fn {_, container} ->
        container == "/workspace" or String.starts_with?(container, "/workspace")
      end)

    []
    |> append_if(skills_dir, fn v -> v ++ ro.(Path.expand(skills_dir), "/skills") end)
    |> append_if(skills_dir, fn v ->
      logs_dir = skills_dir |> Path.dirname() |> Path.join("logs")
      File.mkdir_p!(logs_dir)
      v ++ rw.(logs_dir, "/root/.subzeroclaw/logs")
    end)
    |> append_if(not has_workspace_mount, fn v ->
      workspace = Map.get(config, :workspace, "/tmp/szc-workspace")
      File.mkdir_p!(Path.expand(workspace))
      v ++ rw.(workspace, "/workspace")
    end)
    |> Kernel.++(rw.("/tmp", "/tmp"))
    |> append_priv_mount(ro)
    |> append_src_mount(config, ro)
    |> Kernel.++(Enum.flat_map(additional_vols, fn {h, c} -> rw.(Path.expand(h), c) end))
  end

  defp append_if(acc, falsy, _fun) when falsy in [nil, false], do: acc
  defp append_if(acc, _truthy, fun), do: fun.(acc)

  defp append_priv_mount(vols, ro) do
    priv_dir = genswarms_priv_dir()

    if File.dir?(priv_dir) do
      vols ++ ro.(priv_dir, "/src/genswarms-priv")
    else
      Logger.warning("genswarms priv directory not found at #{inspect(priv_dir)}")
      vols
    end
  end

  defp append_src_mount(vols, config, ro) do
    src =
      Map.get(config, :subzeroclaw_src) ||
        Application.get_env(:genswarms, :subzeroclaw_src) ||
        find_subzeroclaw_source()

    if src && File.dir?(src) do
      vols ++ ro.(src, "/src/subzeroclaw")
    else
      Logger.warning("subzeroclaw source not found at #{inspect(src)}")
      vols
    end
  end

  @doc "Resolves the genswarms `priv/` directory."
  def genswarms_priv_dir do
    case :code.priv_dir(:genswarms) do
      {:error, _} -> Path.expand("priv", File.cwd!())
      path -> List.to_string(path)
    end
  end

  @doc "Finds the subzeroclaw source dir (a sibling checkout with a Makefile)."
  def find_subzeroclaw_source do
    [
      Path.expand("../subzeroclaw", File.cwd!()),
      Path.expand("../../subzeroclaw", File.cwd!()),
      System.get_env("SUBZEROCLAW_SRC"),
      Path.expand("~/docs/personal/subzeroclaw")
    ]
    |> Enum.filter(&(&1 != nil))
    |> Enum.find(fn path ->
      File.dir?(path) && File.exists?(Path.join(path, "Makefile"))
    end)
  end

  # Docker supports all four; Apple `container` only `--memory`/`--cpus`.
  @default_resource_flags [
    {:memory_limit, "--memory"},
    {:memory_swap, "--memory-swap"},
    {:cpu_limit, "--cpus"},
    {:pids_limit, "--pids-limit"}
  ]

  @doc """
  Builds resource-limit argv from `{config_key, cli_flag}` specs (defaulting to
  the full Docker set, in order). Passthrough only — a key absent from config
  emits nothing. Backends that don't support a flag pass a narrower spec list
  so unsupported limits are never translated to fake flags.
  """
  def build_resource_args(config, flags \\ @default_resource_flags) do
    Enum.reduce(flags, [], fn {key, flag}, acc ->
      case Map.get(config, key) do
        nil -> acc
        value -> acc ++ [flag, to_string(value)]
      end
    end)
  end

  @doc """
  Runs the container CLI named `exe_name` with `args`, returning
  `{output, exit_code}`. A missing executable yields `{msg, 127}` (never
  raises), so callers can treat "CLI absent" like any non-zero result.
  """
  def cmd(exe_name, args) do
    case System.find_executable(exe_name) do
      nil -> {"#{exe_name} executable not found", 127}
      exe -> System.cmd(exe, args, stderr_to_stdout: true)
    end
  end
end
