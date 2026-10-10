defmodule Genswarms.CLI.APIClient do
  @moduledoc """
  HTTP client for communicating with the running Phoenix server.

  When the server is running in background (`swarm up`), CLI commands
  use this client to interact with the server via its REST API.
  """

  @default_base_url "http://localhost:4000"

  @doc """
  Returns the base URL for the API.
  """
  def base_url do
    System.get_env("SWARM_API_URL") || @default_base_url
  end

  @doc """
  Checks if the server is running.
  """
  def server_running? do
    case request(:get, "/api/swarms") do
      {:ok, _} -> true
      _ -> false
    end
  end

  @doc """
  Sends a task to an agent.
  """
  def send_task(swarm_name, agent_name, task) do
    body = Jason.encode!(%{task: task})
    request(:post, "/api/swarms/#{swarm_name}/agents/#{agent_name}/task", body)
  end

  @doc """
  Makes a POST request to the given path with the given body.
  """
  def post(path, body) do
    encoded = if is_binary(body), do: body, else: Jason.encode!(body)
    request(:post, path, encoded)
  end

  # Private

  # Sends the API token (if configured) so the CLI works against an
  # authenticated server. Reads GENSWARMS_API_TOKEN — the same variable the
  # server reads — so local use without a token keeps working unchanged.
  defp auth_header do
    case System.get_env("GENSWARMS_API_TOKEN") do
      token when is_binary(token) and token != "" -> "Authorization: Bearer #{token}\r\n"
      _ -> ""
    end
  end

  # Simple socket-based HTTP client to avoid :httpc/:http_util issues
  defp request(method, path, body \\ nil) do
    uri = URI.parse(base_url() <> path)
    host = uri.host || "localhost"
    port = uri.port || 4000

    method_str = method |> to_string() |> String.upcase()
    body_str = body || ""

    request_line =
      "#{method_str} #{uri.path || "/"}#{if uri.query, do: "?#{uri.query}", else: ""} HTTP/1.1\r\n"

    headers =
      "Host: #{host}:#{port}\r\n" <>
        auth_header() <>
        "Content-Type: application/json\r\n" <>
        "Accept: application/json\r\n" <>
        "Content-Length: #{byte_size(body_str)}\r\n" <>
        "Connection: close\r\n" <>
        "\r\n"

    request_bytes = request_line <> headers <> body_str

    case :gen_tcp.connect(
           String.to_charlist(host),
           port,
           [:binary, active: false, packet: :raw],
           10_000
         ) do
      {:ok, socket} ->
        :gen_tcp.send(socket, request_bytes)
        result = receive_response(socket, <<>>)
        :gen_tcp.close(socket)
        parse_http_response(result)

      {:error, reason} ->
        {:error, {:connection_error, reason}}
    end
  end

  defp receive_response(socket, acc) do
    case :gen_tcp.recv(socket, 0, 30_000) do
      {:ok, data} ->
        receive_response(socket, acc <> data)

      {:error, :closed} ->
        acc

      {:error, :timeout} ->
        acc

      {:error, _reason} ->
        acc
    end
  end

  defp parse_http_response(response) do
    case String.split(response, "\r\n\r\n", parts: 2) do
      [headers, body] ->
        status = parse_status_code(headers)

        if status in 200..299 do
          if body == "" do
            {:ok, %{}}
          else
            case Jason.decode(body) do
              {:ok, decoded} -> {:ok, decoded}
              {:error, _} -> {:ok, body}
            end
          end
        else
          {:error, {:http_error, status, body}}
        end

      _ ->
        {:error, {:parse_error, "Invalid HTTP response"}}
    end
  end

  defp parse_status_code(headers) do
    case Regex.run(~r/HTTP\/[\d.]+\s+(\d+)/, headers) do
      [_, status_str] -> String.to_integer(status_str)
      _ -> 0
    end
  end
end
