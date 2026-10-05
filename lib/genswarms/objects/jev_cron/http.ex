defmodule Genswarms.Objects.JevCron.HTTP do
  @moduledoc """
  JSON POST for `Genswarms.Objects.JevCron` through `curl` — the same transport
  subzeroclaw agents use. `:httpc` is not an option: some Erlang builds (Nix)
  ship inets without `http_util`, which `httpc` needs at request time.

  The command is an argv list (no shell). Headers — which carry the API key —
  and the body go through files in a private 0700 directory, so the key never
  appears in argv / `ps`. The directory is removed after the call.

  Replaceable via `config :genswarms, :jev_transport, Module` (tests), which
  must export `post(url, headers, body, timeout_ms)` returning
  `{:ok, status, body}` or `{:error, reason}`.
  """

  def post(url, headers, body, timeout_ms) do
    case System.find_executable("curl") do
      nil -> {:error, :curl_not_found}
      curl -> with_private_dir(&request(curl, &1, url, headers, body, timeout_ms))
    end
  end

  defp request(curl, dir, url, headers, body, timeout_ms) do
    header_file = Path.join(dir, "headers")
    body_file = Path.join(dir, "body")

    File.write!(
      header_file,
      Enum.map_join([{"content-type", "application/json"} | headers], "\n", fn {k, v} ->
        "#{k}: #{v}"
      end)
    )

    File.write!(body_file, body)

    args = [
      "-sS",
      "--proto",
      "=http,https",
      "--max-time",
      Integer.to_string(max(div(timeout_ms, 1000), 1)),
      "-X",
      "POST",
      "-H",
      "@" <> header_file,
      "--data-binary",
      "@" <> body_file,
      "-w",
      "\n%{http_code}",
      "--",
      url
    ]

    case System.cmd(curl, args, stderr_to_stdout: true) do
      {out, 0} ->
        case String.split(out, "\n") |> List.pop_at(-1) do
          {code, lines} ->
            case Integer.parse(code) do
              {status, ""} -> {:ok, status, Enum.join(lines, "\n")}
              _ -> {:error, {:bad_curl_output, String.slice(out, 0, 200)}}
            end
        end

      {out, exit} ->
        {:error, {:curl, exit, String.slice(String.trim(out), 0, 200)}}
    end
  end

  defp with_private_dir(fun) do
    dir = Path.join(System.tmp_dir!(), "genswarms-jev-#{System.unique_integer([:positive])}")
    File.mkdir!(dir)
    File.chmod!(dir, 0o700)

    try do
      fun.(dir)
    after
      File.rm_rf(dir)
    end
  end
end
