# REAL end-to-end: a swarm that actually runs — bwrap sandbox + router
# (paying) — exercising the feature surface where this week's bugs lived, with
# assertions on invariant properties (not on non-deterministic LLM text).
#
# Runs in its own BEAM on an isolated port so it disturbs nothing:
#
#   GENSWARMS_PATH unused (this IS the engine). From the genswarms repo:
#   set -a; source ~/docs/personal/strategivm/.env; set +a
#   GENSWARMS_API_TOKEN=e2e-full GENSWARMS_CONFIG_API_TOKEN=e2e-cfg \
#   SUBZEROCLAW_PATH=~/docs/personal/subzeroclaw/subzeroclaw \
#   GENSWARMS_ALLOWED_ENDPOINTS=router.ygr.ai \
#   mix run e2e/e2e_real.exs
#
# Asserts:
#   1. boot        — real bwrap agent + echo object start (seeds, endpoint)
#   2. ask         — agent's swarm-msg ask reaches echo and gets a REAL reply
#                    (the #79 bug: default-workspace bwrap asks died at 30s)
#   3. overlay     — a real REST hot-patch of the object's config lands, the
#                    object restarts with it, and snapshot/get_config agree
#                    (the #78 bug: replay/patch left three diverging truths)
#
# Exit 0 = all pass; non-zero = a failure (with a report).

require Logger
Logger.configure(level: :warning)

{:ok, _} = Application.ensure_all_started(:genswarms)

port = 4010
{:ok, _} = Genswarms.Application.start_web_server(port: port)
base = "http://127.0.0.1:#{port}"
full = System.get_env("GENSWARMS_API_TOKEN") || "e2e-full"
cfg = System.get_env("GENSWARMS_CONFIG_API_TOKEN") || "e2e-cfg"

Code.require_file(Path.join(__DIR__, "support/echo_object.ex"))

# ── tiny assert harness ─────────────────────────────────────────────────────
{:ok, results} = Agent.start_link(fn -> [] end)

check = fn name, cond? , detail ->
  Agent.update(results, &[{name, cond?, detail} | &1])
  IO.puts([if(cond?, do: "  PASS ", else: "  FAIL "), name, if(detail, do: " — #{detail}", else: "")])
end

curl = fn method, path, token, body ->
  args =
    ["-s", "-X", method, "#{base}#{path}", "-H", "Authorization: Bearer #{token}"] ++
      if(body, do: ["-H", "Content-Type: application/json", "-d", body], else: [])

  {out, _} = System.cmd("curl", args)
  out
end

swarm = "e2e-real-#{System.system_time(:second)}"

policy =
  Jason.encode!(%{
    "policy_ir" => [
      "policy",
      ["and", ["meets_req"], ["not", ["is", "disabled"]]],
      ["add",
       ["scale", 1000, ["neg", ["add", ["field", "price_in"], ["field", "price_out"]]]],
       ["normalize", ["field", "bench_agentic"]]],
      ["argmax"],
      ["id"],
      ["always", %{"action" => "next_candidate"}]
    ]
  })

config = %{
  name: swarm,
  agents: [
    %{
      name: :asker,
      backend: :bwrap,
      endpoint: "https://router.ygr.ai/v1/chat/completions",
      skills: [Path.join(__DIR__, "support/asker.md")],
      config: %{
        network: :isolated,
        api_key: System.get_env("UNHARDCODED_CONSUMER_KEY"),
        request_extra: Jason.decode!(policy)
      }
    }
  ],
  objects: [
    %{name: :echo, handler: Genswarms.E2E.EchoObject, config: %{tag: "base"}}
  ],
  # asker → echo (ask) and echo → asker (return edge, required for ask replies)
  topology: [{:asker, :echo}, {:echo, :asker}]
}

IO.puts("\n== e2e-real: #{swarm} ==")

# ── 1. boot ─────────────────────────────────────────────────────────────────
{:ok, ^swarm} = Genswarms.SwarmManager.start_from_config(config)
Process.sleep(3_000)

echo_pid = fn ->
  case Registry.lookup(Genswarms.AgentRegistry, {swarm, :echo}) do
    [{pid, _}] -> pid
    _ -> nil
  end
end

echo_state = fn -> :sys.get_state(echo_pid.()).handler_state end

agent_alive? =
  case Registry.lookup(Genswarms.AgentRegistry, {swarm, :asker}) do
    [{_, _}] -> true
    _ -> false
  end

check.("boot: echo object registered", echo_pid.() != nil, nil)
check.("boot: bwrap asker agent registered (sandbox seeded, endpoint ok)", agent_alive?, nil)

# ── 2. ask (the #79 path) ───────────────────────────────────────────────────
Genswarms.SwarmManager.send_task(swarm, :asker, "Haz el ask ahora.")

# poll up to 150s: a real bwrap+LLM turn that does one swarm-msg ask
asked? =
  Enum.reduce_while(1..75, false, fn _i, _ ->
    Process.sleep(2_000)
    if echo_state.().asks > 0, do: {:halt, true}, else: {:cont, false}
  end)

st = echo_state.()
check.("ask: echo received a real swarm-msg ask from the bwrap agent (#79)",
  asked?, "asks=#{st.asks} last=#{inspect(st.last)}")

# ── 3. overlay hot-patch via REST (the #78 path) ────────────────────────────
patch_resp = curl.("PATCH", "/api/swarms/#{swarm}/objects/echo/config", cfg,
  Jason.encode!(%{config: %{tag: "patched"}}))

patched_ok = String.contains?(patch_resp, "\"status\":\"updated\"")
check.("overlay: REST config patch accepted through the schema gate", patched_ok, patch_resp)

Process.sleep(2_000)
live_tag = echo_state.().tag
check.("overlay: the live object restarted with the patched config", live_tag == "patched",
  "live tag=#{inspect(live_tag)}")

snap = curl.("POST", "/api/swarms/#{swarm}/snapshot", full, nil)
snap_ok = String.contains?(snap, "patched")
check.("overlay: snapshot reflects the patch (no divergence #78)", snap_ok, nil)

listed = Genswarms.Objects.ObjectSupervisor.list_objects(swarm) |> Enum.map(& &1.name)
check.("overlay: object still listed after the patch-restart (#78)", :echo in listed,
  inspect(listed))

# ── teardown + report ───────────────────────────────────────────────────────
Genswarms.SwarmManager.stop(swarm)

all = Agent.get(results, & &1) |> Enum.reverse()
fails = Enum.count(all, fn {_, ok?, _} -> not ok? end)
IO.puts("\n== e2e-real: #{length(all) - fails}/#{length(all)} passed ==")
if fails > 0, do: System.halt(1), else: IO.puts("E2E REAL OK")
