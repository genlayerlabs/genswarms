# Explicitly paid/manual check. Never run by mix test.
# The env file supplies only UNHARDCODED_API_KEY; no other entries are imported.
# Two turns, at most three client requests per turn and 512 output tokens per request.
# Router-internal fallback attempts and final billing remain provider-controlled.
defmodule RouterRuntimeSmoke do
  alias Genswarms.Backends.BwrapBackend, as: Backend

  def wait_turn(ref, deadline, output \\ "") do
    receive do
      {port, {:data, {kind, bytes}}} when port == ref.port ->
        data = bytes <> if(kind == :eol, do: "\n", else: "")
        consume(ref, data, deadline, output)

      {port, {:data, bytes}} when port == ref.port ->
        consume(ref, bytes, deadline, output)

      {port, {:exit_status, code}} when port == ref.port ->
        raise "runtime exited before completing turn (status #{code})"
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        raise "bounded runtime smoke timed out"
    end
  end

  defp consume(ref, data, deadline, output) do
    {:ok, messages, remaining} = Backend.handle_output(ref, data)
    text = for %{"type" => "output", "content" => content} <- messages, do: content
    combined = output <> Enum.join(text, "\n")
    if byte_size(combined) > 65536, do: raise("output limit")

    if String.contains?(combined, "<<TURN_COMPLETE>>") do
      combined
    else
      wait_turn(%{ref | buffer: remaining}, deadline, combined)
    end
  end

  def run(root, env_file, runtime) do
    {:ok, vars} = Genswarms.CLI.EnvManager.parse_file(env_file)
    key = Map.get(vars, "UNHARDCODED_API_KEY")

    unless is_binary(key) and String.starts_with?(key, "llmr_") and
             not String.contains?(key, ["\r", "\n"]) do
      raise "The selected env file must contain a validly encoded Unhardcoded consumer key"
    end

    unless File.regular?(runtime), do: raise("The selected runtime binary does not exist")
    workspace = Path.join(root, "workspace")
    skills = Path.join(root, "skills")
    File.mkdir_p!(skills)

    File.write!(
      Path.join(skills, "task.md"),
      "Use tools only inside /workspace to complete the user's small file task. No network or other files."
    )

    config = %{
      swarm_name: "router-smoke",
      workspace: workspace,
      skills_dir: skills,
      subzeroclaw_path: runtime,
      api_key: key,
      endpoint: "https://router.ygr.ai/v1/chat/completions",
      request_extra: %{model: "profile:agent", max_tokens: 512},
      max_turns: 3,
      network: :isolated
    }

    case Backend.start("worker", config) do
      {:ok, ref} ->
        try do
          for {prompt, expected} <- [
                {"Use a shell command to write exactly 17 to /workspace/probe.txt. Read it back, then reply exactly VERIFIED_17.",
                 "17"},
                {"Read /workspace/probe.txt using a shell command, add six to that number, and overwrite the same file with the result. Reply exactly VERIFIED_23.",
                 "23"}
              ] do
            :ok = Backend.send_input(ref, Jason.encode!(%{type: "task", content: prompt}))
            output = wait_turn(ref, System.monotonic_time(:millisecond) + 90_000)
            file_ok = File.read!(Path.join(workspace, "probe.txt")) |> String.trim() == expected
            reply_ok = String.contains?(output, "VERIFIED_" <> expected)
            IO.inspect(%{expected: expected, file_ok: file_ok, reply_ok: reply_ok}, label: "turn")
            unless file_ok and reply_ok, do: raise("independent runtime checks failed")
          end

          :ok = Backend.health_check(ref)
          IO.puts("REAL_ROUTER_RUNTIME_TWO_TURNS_PASS")
        after
          Backend.stop(ref)
        end

      {:error, _reason} ->
        raise "sandbox startup failed"
    end
  end
end

unless Mix.env() == :test, do: raise("Run with MIX_ENV=test to disable automatic dotenv imports")

case System.argv() do
  [env_file, runtime] ->
    root =
      Path.join(
        System.tmp_dir!(),
        "genswarms-router-smoke-" <> Base.encode16(:crypto.strong_rand_bytes(12))
      )

    File.mkdir!(root)
    File.chmod!(root, 0o700)

    try do
      RouterRuntimeSmoke.run(root, Path.expand(env_file), Path.expand(runtime))
    after
      File.rm_rf!(root)
    end

  _ ->
    raise "Usage: MIX_ENV=test mix run scripts/unhardcoded-smoke.exs ENV_FILE SUBZEROCLAW_BINARY"
end
