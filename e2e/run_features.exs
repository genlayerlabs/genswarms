# Gherkin-driven REAL e2e runner.
#
# Reads e2e/features/*.feature and executes each scenario against a swarm that
# ACTUALLY runs (bwrap + router paying). The .feature files are the written
# contract of what we test; this runner is the (replaceable) engine that runs
# them. No CI, no mocks — needs the live router + bwrap + tokens:
#
#   set -a; source ~/docs/personal/strategivm/.env; set +a
#   GENSWARMS_API_TOKEN=e2e-full GENSWARMS_CONFIG_API_TOKEN=e2e-cfg \
#   SUBZEROCLAW_PATH=~/docs/personal/subzeroclaw/subzeroclaw \
#   GENSWARMS_ALLOWED_ENDPOINTS=router.ygr.ai \
#   mix run e2e/run_features.exs
#
# Optional: FEATURE=engine_core to run one file.

require Logger
Logger.configure(level: :warning)

# ── minimal Gherkin engine ──────────────────────────────────────────────────
defmodule E2E.Gherkin do
  @moduledoc "Parse Feature/Background/Scenario/Given-When-Then-And; run steps."

  def parse(text) do
    # a @todo tag anywhere marks the whole feature as a not-yet-implemented
    # spec: its scenarios are the written map of what's missing, run as PENDING
    todo? = text |> String.split("\n") |> Enum.any?(&(String.trim(&1) == "@todo"))

    lines =
      text
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#") or String.starts_with?(&1, "@")))

    parsed =
      Enum.reduce(lines, %{feature: nil, background: [], scenarios: [], _cur: nil}, fn line, acc ->
      cond do
        kw?(line, "Feature:") ->
          %{acc | feature: rest(line, "Feature:")}

        kw?(line, "Background:") ->
          %{acc | _cur: :background}

        kw?(line, "Scenario:") ->
          sc = %{name: rest(line, "Scenario:"), steps: []}
          %{acc | scenarios: acc.scenarios ++ [sc], _cur: :scenario}

        step_kw = step_keyword(line) ->
          step = {step_kw, rest(line, step_kw)}
          add_step(acc, step)

        true ->
          acc
      end
    end)

    Map.put(parsed, :todo, todo?)
  end

  defp add_step(%{_cur: :background} = acc, step),
    do: %{acc | background: acc.background ++ [step]}

  defp add_step(%{_cur: :scenario, scenarios: scs} = acc, step) do
    {last, rest} = List.pop_at(scs, -1)
    %{acc | scenarios: rest ++ [%{last | steps: last.steps ++ [step]}]}
  end

  defp add_step(acc, _), do: acc

  defp step_keyword(line) do
    Enum.find(["Given ", "When ", "Then ", "And ", "But "], &String.starts_with?(line, &1))
    |> case do
      nil -> nil
      kw -> String.trim(kw)
    end
  end

  defp kw?(line, kw), do: String.starts_with?(line, kw)
  defp rest(line, kw), do: line |> String.replace_prefix(kw, "") |> String.trim()

  @doc "Run one parsed feature against a step registry [{regex, fun/2}]. fun raises to fail."
  def run(%{todo: true} = parsed, _registry, report) do
    Enum.each(parsed.scenarios, fn sc -> report.({:scenario_pending, sc.name}) end)
    {0, 0, length(parsed.scenarios)}
  end

  def run(parsed, registry, report) do
    {p, f} =
      Enum.reduce(parsed.scenarios, {0, 0}, fn sc, {pass, fail} ->
      report.({:scenario, sc.name})
      steps = parsed.background ++ sc.steps

      result =
        try do
          Enum.reduce(steps, %{}, fn {kw, text}, ctx ->
            run_step(kw, text, registry, ctx, report)
          end)

          :pass
        rescue
          e -> {:fail, Exception.message(e)}
        end

      case result do
        :pass -> {pass + 1, fail}
        {:fail, msg} -> report.({:scenario_fail, msg}); {pass, fail + 1}
      end
    end)

    {p, f, 0}
  end

  defp run_step(kw, text, registry, ctx, report) do
    case Enum.find_value(registry, fn {re, fun} ->
           case Regex.run(re, text, capture: :all_but_first) do
             nil -> nil
             caps -> {fun, caps}
           end
         end) do
      {fun, caps} ->
        ctx2 = fun.(ctx, caps) || ctx
        report.({:step_ok, kw, text})
        ctx2

      nil ->
        report.({:step_undef, kw, text})
        raise "undefined step: #{text}"
    end
  end
end

# ── boot + shared helpers ───────────────────────────────────────────────────
{:ok, _} = Application.ensure_all_started(:genswarms)
port = 4010
_ = Genswarms.Application.start_web_server(port: port)
base = "http://127.0.0.1:#{port}"
full = System.get_env("GENSWARMS_API_TOKEN") || "e2e-full"
cfgtok = System.get_env("GENSWARMS_CONFIG_API_TOKEN") || "e2e-cfg"
Code.require_file(Path.join(__DIR__, "support/echo_object.ex"))
Code.require_file(Path.join(__DIR__, "support/counter_object.ex"))
Code.require_file(Path.join(__DIR__, "support/reject/reject_object.ex"))
Code.require_file(Path.join(__DIR__, "support/shape_object.ex"))

# The Cron object ships in the genswarms-objects package (not the engine);
# load it by require, like a host swarm would, if the checkout is present.
cron_pkg = Path.expand("~/docs/genlayer/genswarms-objects/packages/cron")

cron_loaded? =
  if File.dir?(cron_pkg) do
    for f <- ["cron_expr.ex", "schedule.ex", "job.ex", "store.ex", "cron.ex"] do
      p = Path.join(cron_pkg, f)
      if File.exists?(p) and not Code.ensure_loaded?(Module.concat([:"Elixir", "Genswarms", "Cron"])),
        do: Code.require_file(p)
    end

    Code.ensure_loaded?(Genswarms.Cron)
  else
    false
  end

here = __DIR__

assert! = fn cond?, msg -> unless cond?, do: raise(msg) end

curl = fn method, path, token, body ->
  args =
    ["-s", "-X", method, "#{base}#{path}", "-H", "Authorization: Bearer #{token}"] ++
      if(body, do: ["-H", "Content-Type: application/json", "-d", body], else: [])

  {out, _} = System.cmd("curl", args)
  out
end

# {status, body} — for the auth/gate scenarios that assert on HTTP codes
curl2 = fn method, path, token, body ->
  base_args = ["-s", "-o", "/dev/null", "-w", "%{http_code}", "-X", method, "#{base}#{path}"]
  auth = if token, do: ["-H", "Authorization: Bearer #{token}"], else: []
  data = if body, do: ["-H", "Content-Type: application/json", "-d", body], else: []
  {status, _} = System.cmd("curl", base_args ++ auth ++ data)
  # separate call for the body when needed
  bargs = ["-s", "-X", method, "#{base}#{path}"] ++ auth ++ data
  {b, _} = System.cmd("curl", bargs)
  {String.trim(status), b}
end

reg = fn swarm, name ->
  case Registry.lookup(Genswarms.AgentRegistry, {swarm, name}) do
    [{pid, _}] -> pid
    _ -> nil
  end
end

echo_state = fn swarm -> :sys.get_state(reg.(swarm, :echo)).handler_state end

{:ok, created} = Agent.start_link(fn -> [] end)

policy = fn filter_extra, score ->
  Jason.encode!(%{
    "policy_ir" => [
      "policy",
      ["and", ["meets_req"], ["not", ["is", "disabled"]]] ++ filter_extra,
      score,
      ["argmax"],
      ["id"],
      ["always", %{"action" => "next_candidate"}]
    ]
  })
end

free_pol = policy.([], ["add", ["scale", 1000, ["neg", ["add", ["field", "price_in"], ["field", "price_out"]]]], ["normalize", ["field", "bench_agentic"]]])
apex_pol = policy.([["family_eq", "claude-opus-4-8"], ["provider_eq", "openrouter"]], ["neg", ["add", ["field", "price_in"], ["field", "price_out"]]])

agent = fn name, skill, pol ->
  %{
    name: name,
    backend: :bwrap,
    endpoint: "https://router.ygr.ai/v1/chat/completions",
    skills: [Path.join(here, "support/#{skill}")],
    config: %{network: :isolated, api_key: System.get_env("UNHARDCODED_CONSUMER_KEY"),
              request_extra: Jason.decode!(pol)}
  }
end

usage_cached = fn swarm, name ->
  dir = Path.expand("~/.subzeroclaw/swarms/#{swarm}/#{name}/logs")
  case File.ls(dir) do
    {:ok, files} ->
      files
      |> Enum.flat_map(&String.split(File.read!(Path.join(dir, &1)), "\n"))
      |> Enum.filter(&String.contains?(&1, "USAGE"))
      |> Enum.map(fn l -> case Regex.run(~r/cached=(\d+)/, l) do [_, n] -> String.to_integer(n); _ -> 0 end end)
    _ -> []
  end
end

poll = fn fun, secs ->
  Enum.reduce_while(1..div(secs * 1000, 2000), false, fn _i, _ ->
    Process.sleep(2000)
    if fun.(), do: {:halt, true}, else: {:cont, false}
  end)
end

# ── step registry ───────────────────────────────────────────────────────────
steps = [
  {~r/^a running engine on an isolated port$/, fn ctx, _ -> ctx end},

  {~r/^a swarm with a bwrap "(\w+)" agent and an "(\w+)" object connected both ways$/,
   fn ctx, [ag, obj] ->
     swarm = "e2e-#{ctx[:_feature]}-#{System.unique_integer([:positive])}"
     config = %{
       name: swarm,
       agents: [
         agent.(String.to_atom(ag), "asker.md", free_pol),
         agent.(:cacher, "cacher.md", apex_pol)
       ],
       objects: [%{name: String.to_atom(obj), handler: Genswarms.E2E.EchoObject, config: %{tag: "base"}}],
       topology: [{String.to_atom(ag), String.to_atom(obj)}, {String.to_atom(obj), String.to_atom(ag)}]
     }
     {:ok, ^swarm} = Genswarms.SwarmManager.start_from_config(config)
     Agent.update(created, &[swarm | &1])
     Process.sleep(3000)
     Map.merge(ctx, %{swarm: swarm})
   end},

  {~r/^the "(\w+)" object is registered$/,
   fn ctx, [obj] -> assert!.(reg.(ctx.swarm, String.to_atom(obj)) != nil, "#{obj} not registered"); ctx end},

  {~r/^the "(\w+)" agent is registered$/,
   fn ctx, [ag] -> assert!.(reg.(ctx.swarm, String.to_atom(ag)) != nil, "#{ag} not registered"); ctx end},

  {~r/^the "(\w+)" agent is asked to ping the "(\w+)" object$/,
   fn ctx, [ag, _obj] -> Genswarms.SwarmManager.send_task(ctx.swarm, String.to_atom(ag), "Haz el ask ahora."); ctx end},

  {~r/^the "(\w+)" object records at least one ask within (\d+) seconds$/,
   fn ctx, [_obj, secs] ->
     ok = poll.(fn -> echo_state.(ctx.swarm).asks > 0 end, String.to_integer(secs))
     assert!.(ok, "no ask recorded (asks=#{echo_state.(ctx.swarm).asks})"); ctx
   end},

  {~r/^the last echoed text is "(\w+)"$/,
   fn ctx, [txt] -> assert!.(echo_state.(ctx.swarm).last == txt, "last=#{inspect(echo_state.(ctx.swarm).last)}"); ctx end},

  {~r/^the "(\w+)" object config is patched over REST to tag "(\w+)"$/,
   fn ctx, [obj, tag] ->
     resp = curl.("PATCH", "/api/swarms/#{ctx.swarm}/objects/#{obj}/config", cfgtok, Jason.encode!(%{config: %{tag: tag}}))
     Process.sleep(2000)
     Map.merge(ctx, %{patch_resp: resp, patched_tag: tag})
   end},

  {~r/^the patch is accepted through the schema gate$/,
   fn ctx, _ -> assert!.(String.contains?(ctx.patch_resp, "\"status\":\"updated\""), "patch: #{ctx.patch_resp}"); ctx end},

  {~r/^the live object restarts with tag "(\w+)"$/,
   fn ctx, [tag] -> assert!.(echo_state.(ctx.swarm).tag == tag, "live tag=#{inspect(echo_state.(ctx.swarm).tag)}"); ctx end},

  {~r/^the swarm snapshot reflects tag "(\w+)"$/,
   fn ctx, [tag] ->
     snap = curl.("POST", "/api/swarms/#{ctx.swarm}/snapshot", full, nil)
     assert!.(String.contains?(snap, tag), "snapshot missing #{tag}"); ctx
   end},

  {~r/^the "(\w+)" object is still listed$/,
   fn ctx, [obj] ->
     listed = Genswarms.Objects.ObjectSupervisor.list_objects(ctx.swarm) |> Enum.map(& &1.name)
     assert!.(String.to_atom(obj) in listed, "not listed: #{inspect(listed)}"); ctx
   end},

  {~r/^a bwrap "(\w+)" agent on the claude route with a large stable prefix$/,
   fn ctx, [ag] -> assert!.(reg.(ctx.swarm, String.to_atom(ag)) != nil, "#{ag} not up"); Map.merge(ctx, %{cacher: ag}) end},

  {~r/^the "(\w+)" agent runs two turns in the same session$/,
   fn ctx, [ag] ->
     Genswarms.SwarmManager.send_task(ctx.swarm, String.to_atom(ag), "Turno uno. Di OK.")
     Process.sleep(60_000)
     Genswarms.SwarmManager.send_task(ctx.swarm, String.to_atom(ag), "Turno dos. Di OK.")
     ctx
   end},

  {~r/^subzeroclaw's usage meter reports prompt-cache hits on a later call$/,
   fn ctx, _ ->
     ok = poll.(fn -> Enum.any?(usage_cached.(ctx.swarm, ctx.cacher), &(&1 > 0)) end, 90)
     assert!.(ok, "no cache hit: #{inspect(usage_cached.(ctx.swarm, ctx.cacher))}"); ctx
   end},

  # ── scheduling (cron) ─────────────────────────────────────────────────────
  {~r/^a cron swarm with a seed job due shortly targeting a counter object$/,
   fn ctx, _ ->
     assert!.(cron_loaded?, "Genswarms.Cron not available (genswarms-objects checkout?)")
     swarm = "e2e-#{ctx[:_feature]}-#{System.unique_integer([:positive])}"
     now = System.system_time(:millisecond)
     config = %{
       name: swarm,
       agents: [%{name: :noop, backend: :mock}],
       objects: [
         %{name: :counter, handler: Genswarms.E2E.CounterObject, config: %{}},
         %{name: :cron, handler: Genswarms.Cron, config: %{
            swarm_name: swarm,
            trusted_sources: [],
            allowed_targets: %{counter: ["tick"]},
            seed_jobs: [%{name: "e2e-seed", dedupe_key: "e2e-seed-#{swarm}",
                          schedule: %{"run_at" => now + 1500},
                          target: "counter", message: %{"action" => "tick"}}]
          }}
       ],
       topology: [{:cron, :counter}]
     }
     {:ok, ^swarm} = Genswarms.SwarmManager.start_from_config(config)
     Agent.update(created, &[swarm | &1])
     Map.merge(ctx, %{swarm: swarm})
   end},

  {~r/^the job's run_at elapses$/, fn ctx, _ -> Process.sleep(2500); ctx end},

  {~r/^the counter object receives exactly one scheduled tick within (\d+) seconds$/,
   fn ctx, [secs] ->
     cnt = fn -> :sys.get_state(reg.(ctx.swarm, :counter)).handler_state end
     ok = poll.(fn -> cnt.().received >= 1 end, String.to_integer(secs))
     s = cnt.()
     assert!.(ok and s.received == 1 and Map.get(s.by_action, "tick") == 1,
       "counter=#{inspect(s)}"); ctx
   end},

  {~r/^a cron swarm with empty trusted_sources$/,
   fn ctx, _ ->
     assert!.(cron_loaded?, "Genswarms.Cron not available")
     swarm = "e2e-#{ctx[:_feature]}-#{System.unique_integer([:positive])}"
     config = %{
       name: swarm, agents: [%{name: :noop, backend: :mock}],
       objects: [
         %{name: :counter, handler: Genswarms.E2E.CounterObject, config: %{}},
         %{name: :cron, handler: Genswarms.Cron, config: %{
            swarm_name: swarm, trusted_sources: [],
            allowed_targets: %{counter: ["tick"]}, seed_jobs: []}}
       ],
       topology: [{:cron, :counter}]
     }
     {:ok, ^swarm} = Genswarms.SwarmManager.start_from_config(config)
     Agent.update(created, &[swarm | &1])
     Map.merge(ctx, %{swarm: swarm})
   end},

  {~r/^an untrusted node sends a tick to cron$/,
   fn ctx, _ ->
     Genswarms.Objects.ObjectServer.deliver_message(ctx.swarm, :cron, :intruder,
       Jason.encode!(%{action: "tick"}))
     Process.sleep(1000); ctx
   end},

  {~r/^no scheduled delivery reaches the counter$/,
   fn ctx, _ ->
     s = :sys.get_state(reg.(ctx.swarm, :counter)).handler_state
     assert!.(s.received == 0, "counter got #{s.received}, expected 0"); ctx
   end},

  # ── lifecycle (deterministic, mock agents) ────────────────────────────────
  {~r/^a running swarm with an overlay-added counter object$/,
   fn ctx, _ ->
     swarm = "e2e-#{ctx[:_feature]}-#{System.unique_integer([:positive])}"
     Genswarms.CLI.SwarmRegistry.clear_overlay(swarm)
     {:ok, ^swarm} = Genswarms.SwarmManager.start_from_config(
       %{name: swarm, agents: [%{name: :seed, backend: :mock}], objects: [], topology: []})
     {:ok, :counter} = Genswarms.SwarmManager.add_object(
       swarm, %{name: :counter, handler: Genswarms.E2E.CounterObject, config: %{}}, persist: true)
     Agent.update(created, &[swarm | &1])
     Map.merge(ctx, %{swarm: swarm, seed_config:
       %{name: swarm, agents: [%{name: :seed, backend: :mock}], objects: [], topology: []}})
   end},

  {~r/^the swarm is stopped and started again$/,
   fn ctx, _ ->
     Genswarms.SwarmManager.stop(ctx.swarm)
     Process.sleep(300)
     {:ok, _} = Genswarms.SwarmManager.start_from_config(ctx.seed_config)
     Process.sleep(500); ctx
   end},

  {~r/^the counter object is present again via overlay replay$/,
   fn ctx, _ ->
     Genswarms.CLI.SwarmRegistry.clear_overlay(ctx.swarm)
     assert!.(reg.(ctx.swarm, :counter) != nil, "counter not replayed"); ctx
   end},

  {~r/^a swarm whose echo object was hot-patched to tag "(\w+)"$/,
   fn ctx, [tag] ->
     swarm = "e2e-#{ctx[:_feature]}-#{System.unique_integer([:positive])}"
     Genswarms.CLI.SwarmRegistry.clear_overlay(swarm)
     cfg = %{name: swarm, agents: [%{name: :seed, backend: :mock}],
             objects: [%{name: :echo, handler: Genswarms.E2E.EchoObject, config: %{tag: "base"}}],
             topology: []}
     {:ok, ^swarm} = Genswarms.SwarmManager.start_from_config(cfg)
     {:ok, :echo} = Genswarms.SwarmManager.update_object_config(swarm, :echo, %{tag: tag}, persist: true)
     Agent.update(created, &[swarm | &1])
     Map.merge(ctx, %{swarm: swarm, seed_config: cfg, tag: tag})
   end},

  {~r/^the live object, the snapshot and the listing all agree on tag "(\w+)"$/,
   fn ctx, [tag] ->
     live = echo_state.(ctx.swarm).tag
     snap = curl.("POST", "/api/swarms/#{ctx.swarm}/snapshot", full, nil)
     listed = Genswarms.Objects.ObjectSupervisor.list_objects(ctx.swarm) |> Enum.map(& &1.name)
     Genswarms.CLI.SwarmRegistry.clear_overlay(ctx.swarm)
     assert!.(live == tag, "live tag=#{inspect(live)}")
     assert!.(String.contains?(snap, tag), "snapshot missing #{tag}")
     assert!.(:echo in listed, "not listed: #{inspect(listed)}"); ctx
   end},

  {~r/^a running swarm with an echo object at tag "(\w+)"$/,
   fn ctx, [tag] ->
     swarm = "e2e-#{ctx[:_feature]}-#{System.unique_integer([:positive])}"
     {:ok, ^swarm} = Genswarms.SwarmManager.start_from_config(
       %{name: swarm, agents: [%{name: :seed, backend: :mock}],
         objects: [%{name: :echo, handler: Genswarms.E2E.EchoObject, config: %{tag: tag}}],
         topology: []})
     Agent.update(created, &[swarm | &1])
     Map.merge(ctx, %{swarm: swarm})
   end},

  {~r/^an immutable key is patched on it$/,
   fn ctx, _ ->
     resp = curl.("PATCH", "/api/swarms/#{ctx.swarm}/objects/echo/config", cfgtok,
       Jason.encode!(%{config: %{sender: "hijack"}}))
     Process.sleep(300)
     Map.merge(ctx, %{patch_resp: resp})
   end},

  {~r/^the patch is refused and the echo object still runs at tag "(\w+)"$/,
   fn ctx, [tag] ->
     refused = not String.contains?(ctx.patch_resp, "\"status\":\"updated\"")
     assert!.(refused, "patch unexpectedly accepted: #{ctx.patch_resp}")
     live = echo_state.(ctx.swarm).tag
     assert!.(live == tag, "echo tag=#{inspect(live)} expected #{tag}"); ctx
   end},

  {~r/^a swarm with a worker group scaled to (\d+) and persisted$/,
   fn ctx, [n] ->
     swarm = "e2e-#{ctx[:_feature]}-#{System.unique_integer([:positive])}"
     Genswarms.CLI.SwarmRegistry.clear_overlay(swarm)
     cfg = %{name: swarm, agents: [%{name: :worker_1, backend: :mock}], objects: [], topology: []}
     {:ok, ^swarm} = Genswarms.SwarmManager.start_from_config(cfg)
     {:ok, _} = Genswarms.SwarmManager.scale_agent_group(swarm, :worker, String.to_integer(n), persist: true)
     Agent.update(created, &[swarm | &1])
     Map.merge(ctx, %{swarm: swarm, seed_config: cfg, n: String.to_integer(n)})
   end},

  {~r/^all (\d+) worker members are restored$/,
   fn ctx, [n] ->
     all = Enum.all?(1..String.to_integer(n), fn i -> reg.(ctx.swarm, :"worker_#{i}") != nil end)
     Genswarms.CLI.SwarmRegistry.clear_overlay(ctx.swarm)
     assert!.(all, "not all workers restored"); ctx
   end},

  {~r/^a running swarm$/,
   fn ctx, _ ->
     swarm = "e2e-#{ctx[:_feature]}-#{System.unique_integer([:positive])}"
     cfg = %{name: swarm, agents: [%{name: :seed, backend: :mock}], objects: [], topology: []}
     {:ok, ^swarm} = Genswarms.SwarmManager.start_from_config(cfg)
     Agent.update(created, &[swarm | &1])
     Map.merge(ctx, %{swarm: swarm, seed_config: cfg})
   end},

  {~r/^it is started again under the same name$/,
   fn ctx, _ -> Map.merge(ctx, %{restart_result: Genswarms.SwarmManager.start_from_config(ctx.seed_config)}) end},

  {~r/^the second start is refused as already running$/,
   fn ctx, _ -> assert!.(match?({:error, :already_exists}, ctx.restart_result),
     "got #{inspect(ctx.restart_result)}"); ctx end},

  # ── security (deterministic: REST + auth/loader/endpoint-policy) ───────────
  {~r/^the swarm list is requested with no token$/,
   fn ctx, _ -> {s, _} = curl2.("GET", "/api/swarms", nil, nil); Map.put(ctx, :http, s) end},
  {~r/^the swarm list is requested with the full token$/,
   fn ctx, _ -> {s, _} = curl2.("GET", "/api/swarms", full, nil); Map.put(ctx, :http, s) end},
  {~r/^a swarm create is attempted with the config-scoped token$/,
   fn ctx, _ -> {s, _} = curl2.("POST", "/api/swarms", cfgtok, Jason.encode!(%{config: %{name: "x", agents: [], objects: [], topology: []}})); Map.put(ctx, :http, s) end},
  {~r/^it is rejected 401$/, fn ctx, _ -> assert!.(ctx.http == "401", "got #{ctx.http}"); ctx end},
  {~r/^it is accepted 200$/, fn ctx, _ -> assert!.(ctx.http == "200", "got #{ctx.http}"); ctx end},

  {~r/^a running swarm with an echo object$/,
   fn ctx, _ ->
     swarm = "e2e-#{ctx[:_feature]}-#{System.unique_integer([:positive])}"
     {:ok, ^swarm} = Genswarms.SwarmManager.start_from_config(
       %{name: swarm, agents: [%{name: :seed, backend: :mock}],
         objects: [%{name: :echo, handler: Genswarms.E2E.EchoObject, config: %{tag: "base"}}], topology: []})
     Agent.update(created, &[swarm | &1]); Map.merge(ctx, %{swarm: swarm})
   end},
  {~r/^its tag is patched with the config-scoped token$/,
   fn ctx, _ -> {s, _} = curl2.("PATCH", "/api/swarms/#{ctx.swarm}/objects/echo/config", cfgtok, Jason.encode!(%{config: %{tag: "cfg"}})); Map.put(ctx, :http, s) end},
  {~r/^it is accepted$/, fn ctx, _ -> assert!.(ctx.http == "200", "got #{ctx.http}"); ctx end},

  {~r/^an immutable key is patched$/,
   fn ctx, _ -> {s, b} = curl2.("PATCH", "/api/swarms/#{ctx.swarm}/objects/echo/config", cfgtok, Jason.encode!(%{config: %{sender: "x"}})); Map.merge(ctx, %{http: s, body: b}) end},
  {~r/^it is rejected 422$/, fn ctx, _ -> assert!.(ctx.http == "422", "got #{ctx.http}: #{ctx[:body]}"); ctx end},

  {~r/^a running swarm with a schemaless counter object$/,
   fn ctx, _ ->
     swarm = "e2e-#{ctx[:_feature]}-#{System.unique_integer([:positive])}"
     {:ok, ^swarm} = Genswarms.SwarmManager.start_from_config(
       %{name: swarm, agents: [%{name: :seed, backend: :mock}],
         objects: [%{name: :counter, handler: Genswarms.E2E.CounterObject, config: %{}}], topology: []})
     Agent.update(created, &[swarm | &1]); Map.merge(ctx, %{swarm: swarm})
   end},
  {~r/^any key is patched$/,
   fn ctx, _ -> {s, b} = curl2.("PATCH", "/api/swarms/#{ctx.swarm}/objects/counter/config", cfgtok, Jason.encode!(%{config: %{anything: 1}})); Map.merge(ctx, %{http: s, body: b}) end},
  {~r/^it is rejected 422 no schema$/,
   fn ctx, _ -> assert!.(ctx.http == "422" and String.contains?(ctx.body, "no_config_schema"), "#{ctx.http}: #{ctx.body}"); ctx end},

  {~r/^subzeroclaw_path is patched$/,
   fn ctx, _ -> {s, b} = curl2.("PATCH", "/api/swarms/#{ctx.swarm}/objects/echo/config", cfgtok, Jason.encode!(%{config: %{subzeroclaw_path: "/evil"}})); Map.merge(ctx, %{http: s, body: b}) end},

  {~r/^a patch with over 200 keys is applied$/,
   fn ctx, _ ->
     big = for i <- 1..250, into: %{}, do: {"k#{i}", i}
     {s, b} = curl2.("PATCH", "/api/swarms/#{ctx.swarm}/objects/echo/config", cfgtok, Jason.encode!(%{config: big}))
     Map.merge(ctx, %{http: s, body: b})
   end},
  {~r/^it is refused as patch_too_large$/,
   fn ctx, _ -> assert!.(ctx.http in ["400", "422"] and String.contains?(ctx.body, "patch_too_large"),
     "#{ctx.http}: #{ctx.body}"); ctx end},

  {~r/^a running swarm whose agent config holds an api_key$/,
   fn ctx, _ ->
     swarm = "e2e-#{ctx[:_feature]}-#{System.unique_integer([:positive])}"
     {:ok, ^swarm} = Genswarms.SwarmManager.start_from_config(
       %{name: swarm, agents: [%{name: :seed, backend: :mock, config: %{api_key: "sk-e2e-supersecret"}}],
         objects: [], topology: []})
     Agent.update(created, &[swarm | &1]); Map.merge(ctx, %{swarm: swarm})
   end},
  {~r/^the snapshot is rendered$/,
   fn ctx, _ -> {_, b} = curl2.("POST", "/api/swarms/#{ctx.swarm}/snapshot", full, nil); Map.put(ctx, :body, b) end},
  {~r/^the api_key reads REDACTED and the secret is nowhere in the text$/,
   fn ctx, _ ->
     assert!.(String.contains?(ctx.body, "REDACTED"), "no REDACTED in snapshot")
     assert!.(not String.contains?(ctx.body, "sk-e2e-supersecret"), "SECRET LEAKED in snapshot"); ctx
   end},

  {~r/^a package entry file list contains a traversal path$/,
   fn ctx, _ ->
     dir = Path.join(System.tmp_dir!(), "e2e-pkg-#{System.unique_integer([:positive])}")
     File.mkdir_p!(dir)
     File.write!(Path.join(dir, "swarm-object.json"),
       Jason.encode!(%{"module" => "Genswarms.E2E.EchoObject", "files" => ["../../etc/passwd"]}))
     {:ok, digest} = Genswarms.Packages.Dirhash.hash_dir(dir)
     result = Genswarms.Packages.Loader.resolve_handler(
       %{ref: "e2e:test@0", digest: digest, path: dir, mode: :require})
     Map.put(ctx, :loader_result, result)
   end},
  {~r/^the loader rejects it as unsafe$/,
   fn ctx, _ -> assert!.(match?({:error, {:unsafe_entry_files, _}}, ctx.loader_result),
     "got #{inspect(ctx.loader_result)}"); ctx end},

  {~r/^endpoint policy resolves an untrusted per-agent endpoint$/,
   fn ctx, _ ->
     {_ep, key} = Genswarms.Backends.EndpointPolicy.resolve(%{endpoint: "https://untrusted.e2e.example/v1"})
     Map.put(ctx, :ep_key, key)
   end},
  {~r/^no API key is handed out$/,
   fn ctx, _ -> assert!.(ctx.ep_key in [nil, ""], "key handed out: #{inspect(ctx.ep_key)}"); ctx end},

  # ── messaging & topology (deterministic: Router + object shapes) ───────────
  {~r/^a swarm where shape is connected to seen but not to unseen$/,
   fn ctx, _ ->
     swarm = "e2e-#{ctx[:_feature]}-#{System.unique_integer([:positive])}"
     {:ok, ^swarm} = Genswarms.SwarmManager.start_from_config(
       %{name: swarm, agents: [%{name: :seed, backend: :mock}],
         objects: [
           %{name: :shape, handler: Genswarms.E2E.ShapeObject, config: %{}},
           %{name: :seen, handler: Genswarms.E2E.CounterObject, config: %{}},
           %{name: :unseen, handler: Genswarms.E2E.CounterObject, config: %{}}
         ],
         topology: [{:shape, :seen}]})
     Agent.update(created, &[swarm | &1]); Map.merge(ctx, %{swarm: swarm})
   end},

  {~r/^a swarm where shape is connected to both seen and also_seen$/,
   fn ctx, _ ->
     swarm = "e2e-#{ctx[:_feature]}-#{System.unique_integer([:positive])}"
     {:ok, ^swarm} = Genswarms.SwarmManager.start_from_config(
       %{name: swarm, agents: [%{name: :seed, backend: :mock}],
         objects: [
           %{name: :shape, handler: Genswarms.E2E.ShapeObject, config: %{}},
           %{name: :seen, handler: Genswarms.E2E.CounterObject, config: %{}},
           %{name: :also_seen, handler: Genswarms.E2E.CounterObject, config: %{}}
         ],
         topology: [{:shape, :seen}, {:shape, :also_seen}]})
     Agent.update(created, &[swarm | &1]); Map.merge(ctx, %{swarm: swarm})
   end},

  {~r/^shape is told to send to (\w+)$/,
   fn ctx, [to] ->
     Genswarms.Objects.ObjectServer.deliver_message(ctx.swarm, :shape, :seed,
       Jason.encode!(%{do: "send", to: to}))
     Process.sleep(800); ctx
   end},

  {~r/^an edge from shape to unseen is added and shape sends to unseen$/,
   fn ctx, _ ->
     Genswarms.Routing.Router.add_edges(ctx.swarm, [{:shape, :unseen}])
     Process.sleep(200)
     Genswarms.Objects.ObjectServer.deliver_message(ctx.swarm, :shape, :seed,
       Jason.encode!(%{do: "send", to: "unseen"}))
     Process.sleep(800); ctx
   end},

  {~r/^shape broadcasts$/,
   fn ctx, _ ->
     Genswarms.Objects.ObjectServer.deliver_message(ctx.swarm, :shape, :seed,
       Jason.encode!(%{do: "broadcast"}))
     Process.sleep(800); ctx
   end},

  {~r/^(\w+) never receives it$/,
   fn ctx, [obj] ->
     s = :sys.get_state(reg.(ctx.swarm, String.to_atom(obj))).handler_state
     assert!.(s.received == 0, "#{obj} got #{s.received}, expected 0"); ctx
   end},

  {~r/^(\w+) receives exactly one tick$/,
   fn ctx, [obj] ->
     cnt = fn -> :sys.get_state(reg.(ctx.swarm, String.to_atom(obj))).handler_state end
     ok = poll.(fn -> cnt.().received >= 1 end, 8)
     s = cnt.()
     assert!.(ok and s.received == 1 and Map.get(s.by_action, "tick") == 1, "#{obj}=#{inspect(s)}"); ctx
   end},

  {~r/^both (\w+) and (\w+) receive a tick$/,
   fn ctx, [a, b] ->
     ca = fn -> :sys.get_state(reg.(ctx.swarm, String.to_atom(a))).handler_state.received end
     cb = fn -> :sys.get_state(reg.(ctx.swarm, String.to_atom(b))).handler_state.received end
     ok = poll.(fn -> ca.() >= 1 and cb.() >= 1 end, 8)
     assert!.(ok, "#{a}=#{ca.()} #{b}=#{cb.()}"); ctx
   end},

  # ── sandbox isolation (real bwrap sandbox, deterministic) ─────────────────
  {~r/^a bwrap agent started with network isolated$/,
   fn ctx, _ ->
     assert!.(System.get_env("UNHARDCODED_CONSUMER_KEY") not in [nil, ""], "no router key")
     swarm = "e2e-#{ctx[:_feature]}-#{System.unique_integer([:positive])}"
     {:ok, ^swarm} = Genswarms.SwarmManager.start_from_config(
       %{name: swarm, agents: [agent.(:prober, "prober.md", free_pol)], objects: [], topology: []})
     Agent.update(created, &[swarm | &1])
     Process.sleep(4000)
     Map.merge(ctx, %{swarm: swarm})
   end},

  {~r/^the engine's egress guard requests --unshare-net for it$/,
   fn ctx, _ ->
     args = Genswarms.Backends.EgressGuard.bwrap_net_args(%{network: :isolated})
     assert!.("--unshare-net" in args, "egress guard args=#{inspect(args)}"); ctx
   end},

  {~r/^the live sandbox process runs with --unshare-net$/,
   fn ctx, _ ->
     # find the running bwrap process for this swarm's sandbox and confirm the
     # network namespace is actually unshared (real isolation, not just config)
     found = poll.(fn ->
       {out, _} = System.cmd("bash", ["-c",
         "for p in /proc/[0-9]*/cmdline; do tr '\\0' ' ' < $p 2>/dev/null | grep -q '#{ctx.swarm}' && tr '\\0' ' ' < $p 2>/dev/null; echo; done | grep bwrap || true"])
       String.contains?(out, "--unshare-net")
     end, 20)
     assert!.(found, "no bwrap process with --unshare-net for #{ctx.swarm}"); ctx
   end},

  {~r/^the engine's egress guard requests no net-unshare for an open agent$/,
   fn ctx, _ ->
     args = Genswarms.Backends.EgressGuard.bwrap_net_args(%{})
     assert!.("--unshare-net" not in args, "open agent got net-unshare: #{inspect(args)}"); ctx
   end},

  # ── observability (event stream + observer detectors, no tokens) ──────────
  {~r/^a running swarm with an agent and an object$/,
   fn ctx, _ ->
     swarm = "e2e-#{ctx[:_feature]}-#{System.unique_integer([:positive])}"
     {:ok, ^swarm} = Genswarms.SwarmManager.start_from_config(
       %{name: swarm, agents: [%{name: :worker, backend: :mock}],
         objects: [%{name: :echo, handler: Genswarms.E2E.EchoObject, config: %{tag: "base"}}], topology: []})
     Agent.update(created, &[swarm | &1])
     Map.merge(ctx, %{swarm: swarm})
   end},

  {~r/^the swarm's events are queried$/,
   fn ctx, _ ->
     types = fn ->
       Genswarms.Observability.LogStore.query(swarm: ctx.swarm, limit: 200)
       |> Enum.map(&(&1[:event_type] || &1["event_type"]))
       |> Enum.map(&to_string/1)
     end
     poll.(fn -> "agent_started" in types.() end, 15)
     Map.put(ctx, :event_types, types.())
   end},
  {~r/^an agent_started event is present$/,
   fn ctx, _ -> assert!.("agent_started" in ctx.event_types, "types=#{inspect(Enum.uniq(ctx.event_types))}"); ctx end},
  {~r/^an object_started event is present$/,
   fn ctx, _ -> assert!.("object_started" in ctx.event_types, "types=#{inspect(Enum.uniq(ctx.event_types))}"); ctx end},

  {~r/^the observer detectors are loaded$/,
   fn ctx, _ ->
     obs = Path.expand("~/docs/genlayer/genswarms-observer/lib/genswarms/observer/detectors.ex")
     if File.exists?(obs) and not Code.ensure_loaded?(Genswarms.Observer.Detectors),
       do: Code.require_file(obs)
     assert!.(Code.ensure_loaded?(Genswarms.Observer.Detectors), "observer Detectors not available"); ctx
   end},
  {~r/^a swarm's dashboard fetch is a connection error$/,
   fn ctx, _ ->
     {alerts, _} = Genswarms.Observer.Detectors.detect("target",
       %{dashboard: {:error, :econnrefused}, events: {:error, :econnrefused}}, %{}, nil,
       System.system_time(:millisecond))
     Map.put(ctx, :alerts, alerts)
   end},
  {~r/^the detectors raise an endpoint_down alert for that swarm$/,
   fn ctx, _ ->
     types = Enum.map(ctx.alerts, & &1.type)
     assert!.(:endpoint_down in types, "alerts=#{inspect(types)}"); ctx
   end},
  {~r/^a swarm's dashboard is healthy and idle$/,
   fn ctx, _ ->
     now = System.system_time(:millisecond)
     healthy = %{"status" => "running", "summary" => %{"pool" => %{"leased" => 0, "size" => 4}},
                 "nodes" => [%{"name" => "a", "type" => "agent", "state" => "idle"}]}
     event = %{"id" => 1, "level" => "info",
               "timestamp" => now |> DateTime.from_unix!(:millisecond) |> DateTime.to_iso8601()}
     {alerts, _} = Genswarms.Observer.Detectors.detect("target",
       %{dashboard: {:ok, healthy}, events: {:ok, [event]}}, %{}, nil, now)
     Map.put(ctx, :alerts, alerts)
   end},
  {~r/^the detectors raise nothing$/,
   fn ctx, _ -> assert!.(ctx.alerts == [], "expected no alerts, got #{inspect(ctx.alerts)}"); ctx end},

  # ── routing economics (real agent, gpt-5.5 is $0) ─────────────────────────
  {~r/^a free-first economist agent$/,
   fn ctx, _ ->
     assert!.(System.get_env("UNHARDCODED_CONSUMER_KEY") not in [nil, ""], "no router key")
     swarm = "e2e-#{ctx[:_feature]}-#{System.unique_integer([:positive])}"
     {:ok, ^swarm} = Genswarms.SwarmManager.start_from_config(
       %{name: swarm, agents: [agent.(:economist, "economist.md", free_pol)], objects: [], topology: []})
     Agent.update(created, &[swarm | &1])
     Process.sleep(3000)
     Map.merge(ctx, %{swarm: swarm})
   end},
  {~r/^it takes a turn$/,
   fn ctx, _ ->
     Genswarms.SwarmManager.send_task(ctx.swarm, :economist, "Di OK.")
     usage = fn ->
       dir = Path.expand("~/.subzeroclaw/swarms/#{ctx.swarm}/economist/logs")
       case File.ls(dir) do
         {:ok, fs} ->
           fs |> Enum.flat_map(&String.split(File.read!(Path.join(dir, &1)), "\n"))
              |> Enum.filter(&String.contains?(&1, "USAGE"))
         _ -> []
       end
     end
     poll.(fn -> usage.() != [] end, 120)
     Map.put(ctx, :usage, usage.())
   end},
  {~r/^a model was chosen and the turn was metered at zero cost$/,
   fn ctx, _ ->
     assert!.(ctx.usage != [], "no USAGE line — turn never metered")
     line = hd(ctx.usage)
     assert!.(Regex.match?(~r/model=\S+/, line) and not Regex.match?(~r/model=\?/, line),
       "no model chosen: #{line}")
     assert!.(String.contains?(line, "cost_usd=0.000000"), "expected $0, got: #{line}"); ctx
   end}
]

# ── run all features ────────────────────────────────────────────────────────
files =
  case System.get_env("FEATURE") do
    nil -> Path.wildcard(Path.join(here, "features/*.feature"))
    f -> [Path.join(here, "features/#{f}.feature")]
  end

report = fn
  {:scenario, name} -> IO.puts("\n  Scenario: #{name}")
  {:scenario_pending, name} -> IO.puts("  Scenario: #{name}  — PENDING (spec only)")
  {:step_ok, kw, text} -> IO.puts("    ✓ #{kw} #{text}")
  {:step_undef, kw, text} -> IO.puts("    ? #{kw} #{text}  (UNDEFINED)")
  {:scenario_fail, msg} -> IO.puts("    ✗ FAILED: #{msg}")
end

{tp, tf, tpend} =
  Enum.reduce(files, {0, 0, 0}, fn file, {p, f, pend} ->
    parsed = E2E.Gherkin.parse(File.read!(file))
    fname = Path.basename(file, ".feature")
    IO.puts("\nFeature: #{parsed.feature}  [#{fname}]#{if parsed.todo, do: "  @todo", else: ""}")
    reg2 = [{~r/^a running engine on an isolated port$/, fn ctx, _ -> Map.put(ctx, :_feature, fname) end} | steps]
    {sp, sf, spend} = E2E.Gherkin.run(parsed, reg2, report)
    {p + sp, f + sf, pend + spend}
  end)

Enum.each(Agent.get(created, & &1), &Genswarms.SwarmManager.stop/1)

IO.puts("\n== features: #{tp} passed, #{tf} failed, #{tpend} pending (unwritten coverage) ==")
if tf > 0, do: System.halt(1), else: IO.puts("E2E FEATURES OK")
