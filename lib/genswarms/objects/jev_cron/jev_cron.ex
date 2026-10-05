defmodule Genswarms.Objects.JevCron do
  @moduledoc """
  A Jev-driven trigger object ("jev-cron").

  Every `every` (a timer) and/or on every message it receives, the object asks
  a Jev decision model — the unhardcoded router's `/v1/decisions` — to pick ONE
  action out of a closed catalogue, then applies that action deterministically:

    * `send`     — route templated messages to agents/objects (it produces),
    * `remember` / `forget` — change the object's memory (it changes state),
      which is part of the state Jev sees on the next decision.

  Jev never writes free text: it only returns a probability per action id. All
  text the object emits comes from the operator's templates. This makes a
  jev-cron a cheap gate in front of expensive agents — "every 5 minutes, is
  there anything worth waking the coder for?" costs one decision, not an LLM
  turn.

      %{
        name: :watch,
        handler: Genswarms.Objects.JevCron,
        config: %{
          every: "5m",
          instructions: "Decide whether the coder must act on the latest report.",
          context: %{repo: "genswarms"},
          actions: [
            %{id: "nothing", when: "Nothing new or nothing actionable"},
            %{id: "wake", when: "A failure or request that needs code changes",
              send: %{to: :coder, text: "Please look at: {{message}}"},
              remember: %{"last_wake" => "{{now}}"}}
          ],
          min_confidence: 0.6,
          fallback: "nothing"
        }
      }

  Sends obey the topology like any object send: add an edge from the
  jev-cron to every target.

  Endpoint and credentials: the router base URL is `config.endpoint` or the
  `GENSWARMS_JEV_ENDPOINT` env; the key is `GENSWARMS_JEV_API_KEY` and is never
  part of the config. A per-object `endpoint` is honoured only if it equals the
  env endpoint or its host is in `GENSWARMS_ALLOWED_ENDPOINTS` (same policy as
  `Genswarms.Backends.EndpointPolicy`); otherwise the object fails to start.

  Every decision is logged as a `:jev_decision` event (action, confidence,
  distribution, latency, cost), queryable with `genswarms events` and the
  events API.
  """

  @behaviour Genswarms.Objects.ObjectHandler

  require Logger

  alias Genswarms.Backends.EndpointPolicy
  alias Genswarms.Observability.LogStore

  @min_every_ms 1_000
  @max_actions 32
  @max_queue 20
  @max_message_chars 8_000
  @id_regex ~r/\A[a-zA-Z][a-zA-Z0-9_-]*\z/
  @template_regex ~r/\{\{\s*([a-zA-Z_][a-zA-Z0-9_.-]*)\s*\}\}/

  # ── config ───────────────────────────────────────────────────────────────────

  @doc """
  Validates and normalizes a jev-cron config (atom- or string-keyed, as it
  arrives from `.exs`, REST or a config patch). `{:ok, cfg}` or
  `{:error, reason}`. Called by `SwarmConfig` at validation time and by
  `init/1`.
  """
  @impl true
  def validate_config(config) when is_map(config) do
    with {:ok, every} <- parse_every(get(config, :every)),
         {:ok, on_message} <- bool(get(config, :on_message), true, :on_message),
         {:ok, run_at_start} <- bool(get(config, :run_at_start), false, :run_at_start),
         :ok <- has_trigger(every, on_message, run_at_start),
         {:ok, instructions} <- required_string(get(config, :instructions), :instructions),
         {:ok, actions} <- parse_actions(get(config, :actions)),
         {:ok, fallback} <- parse_fallback(get(config, :fallback), actions),
         {:ok, min_confidence} <-
           number_in(get(config, :min_confidence), 0.0, 0.0, 1.0, :min_confidence),
         {:ok, history} <- int_in(get(config, :history), 5, 0, 50, :history),
         {:ok, timeout_ms} <-
           int_in(get(config, :timeout_ms), 30_000, 1_000, 120_000, :timeout_ms),
         {:ok, budget} <- parse_budget(get(config, :budget_usd_per_day)),
         {:ok, endpoint} <- parse_endpoint(get(config, :endpoint)),
         {:ok, context} <- json_term(get(config, :context), :context),
         {:ok, policy_ir} <- json_term(get(config, :policy_ir), :policy_ir) do
      {:ok,
       %{
         every: every,
         on_message: on_message,
         run_at_start: run_at_start,
         instructions: instructions,
         actions: actions,
         fallback: fallback,
         min_confidence: min_confidence * 1.0,
         history: history,
         timeout_ms: timeout_ms,
         budget_usd_per_day: budget,
         endpoint: endpoint,
         context: context,
         policy_ir: policy_ir
       }}
    end
  end

  def validate_config(_), do: {:error, :config_must_be_map}

  defp get(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp parse_every(nil), do: {:ok, nil}

  defp parse_every(ms) when is_integer(ms) and ms >= @min_every_ms, do: {:ok, ms}

  defp parse_every(s) when is_binary(s) do
    case Regex.run(~r/\A(\d+)(ms|s|m|h|d)\z/, String.trim(s)) do
      [_, n, unit] ->
        ms = String.to_integer(n) * unit_ms(unit)
        if ms >= @min_every_ms, do: {:ok, ms}, else: {:error, {:invalid, :every, s}}

      _ ->
        {:error, {:invalid, :every, s}}
    end
  end

  defp parse_every(other), do: {:error, {:invalid, :every, other}}

  defp unit_ms("ms"), do: 1
  defp unit_ms("s"), do: 1_000
  defp unit_ms("m"), do: 60_000
  defp unit_ms("h"), do: 3_600_000
  defp unit_ms("d"), do: 86_400_000

  defp has_trigger(nil, false, false), do: {:error, :no_trigger}
  defp has_trigger(_every, _on_message, _run_at_start), do: :ok

  defp bool(nil, default, _key), do: {:ok, default}
  defp bool(b, _default, _key) when is_boolean(b), do: {:ok, b}
  defp bool(other, _default, key), do: {:error, {:invalid, key, other}}

  defp required_string(s, _key) when is_binary(s) and s != "", do: {:ok, s}
  defp required_string(other, key), do: {:error, {:invalid, key, other}}

  defp number_in(nil, default, _lo, _hi, _key), do: {:ok, default}

  defp number_in(n, _default, lo, hi, _key) when is_number(n) and n >= lo and n <= hi,
    do: {:ok, n}

  defp number_in(other, _default, _lo, _hi, key), do: {:error, {:invalid, key, other}}

  defp int_in(nil, default, _lo, _hi, _key), do: {:ok, default}

  defp int_in(n, _default, lo, hi, _key) when is_integer(n) and n >= lo and n <= hi,
    do: {:ok, n}

  defp int_in(other, _default, _lo, _hi, key), do: {:error, {:invalid, key, other}}

  defp parse_budget(nil), do: {:ok, nil}
  defp parse_budget(n) when is_number(n) and n > 0, do: {:ok, n * 1.0}
  defp parse_budget(other), do: {:error, {:invalid, :budget_usd_per_day, other}}

  defp parse_endpoint(nil), do: {:ok, nil}

  defp parse_endpoint(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        {:ok, String.trim_trailing(url, "/")}

      _ ->
        {:error, {:invalid, :endpoint, url}}
    end
  end

  defp parse_endpoint(other), do: {:error, {:invalid, :endpoint, other}}

  defp json_term(nil, _key), do: {:ok, nil}

  defp json_term(term, key) do
    case Jason.encode(term) do
      {:ok, _} -> {:ok, term}
      {:error, _} -> {:error, {:invalid, key, :not_json}}
    end
  end

  defp parse_actions(actions) when is_list(actions) and length(actions) in 2..@max_actions do
    actions
    |> Enum.reduce_while({:ok, []}, fn action, {:ok, acc} ->
      case parse_action(action) do
        {:ok, a} -> {:cont, {:ok, [a | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, parsed} ->
        parsed = Enum.reverse(parsed)
        ids = Enum.map(parsed, & &1.id)

        if length(Enum.uniq(ids)) == length(ids),
          do: {:ok, parsed},
          else: {:error, {:duplicate_action_ids, ids -- Enum.uniq(ids)}}

      error ->
        error
    end
  end

  defp parse_actions(other), do: {:error, {:invalid, :actions, {:need_2_to_32, other}}}

  defp parse_action(%{} = a) do
    with {:ok, id} <- action_id(get(a, :id)),
         {:ok, label} <- required_string(get(a, :when), {:action, id, :when}),
         {:ok, sends} <- parse_sends(get(a, :send), id),
         {:ok, remember} <- parse_remember(get(a, :remember), id),
         {:ok, forget} <- parse_forget(get(a, :forget), id) do
      {:ok, %{id: id, when: label, send: sends, remember: remember, forget: forget}}
    end
  end

  defp parse_action(other), do: {:error, {:invalid, :action, other}}

  defp action_id(id) when is_atom(id) and not is_nil(id), do: action_id(Atom.to_string(id))

  defp action_id(id) when is_binary(id) do
    if Regex.match?(@id_regex, id), do: {:ok, id}, else: {:error, {:invalid, :action_id, id}}
  end

  defp action_id(other), do: {:error, {:invalid, :action_id, other}}

  defp parse_sends(nil, _id), do: {:ok, []}
  defp parse_sends(%{} = send, id), do: parse_sends([send], id)

  defp parse_sends(sends, id) when is_list(sends) do
    Enum.reduce_while(sends, {:ok, []}, fn s, {:ok, acc} ->
      with %{} <- s,
           {:ok, to} <- target(get(s, :to)),
           text when is_binary(text) and text != "" <- get(s, :text) do
        {:cont, {:ok, acc ++ [%{to: to, text: text}]}}
      else
        {:error, _} = error -> {:halt, error}
        _ -> {:halt, {:error, {:invalid, {:action, id, :send}, s}}}
      end
    end)
  end

  defp parse_sends(other, id), do: {:error, {:invalid, {:action, id, :send}, other}}

  # String targets stay strings here: a JSON/YAML config is validated before
  # its node names become atoms. init/1 resolves them (resolve_targets/1).
  defp target(to) when is_atom(to) and not is_nil(to), do: {:ok, to}
  defp target(to) when is_binary(to) and to != "", do: {:ok, to}

  defp target(other), do: {:error, {:invalid, :send_to, other}}

  defp parse_remember(nil, _id), do: {:ok, %{}}

  defp parse_remember(%{} = m, id) do
    with {:ok, _} <- json_term(m, {:action, id, :remember}) do
      {:ok, Map.new(m, fn {k, v} -> {to_string(k), v} end)}
    end
  end

  defp parse_remember(other, id), do: {:error, {:invalid, {:action, id, :remember}, other}}

  defp parse_forget(nil, _id), do: {:ok, []}

  defp parse_forget(keys, id) when is_list(keys) do
    if Enum.all?(keys, &(is_binary(&1) or is_atom(&1))),
      do: {:ok, Enum.map(keys, &to_string/1)},
      else: {:error, {:invalid, {:action, id, :forget}, keys}}
  end

  defp parse_forget(other, id), do: {:error, {:invalid, {:action, id, :forget}, other}}

  defp parse_fallback(nil, _actions), do: {:ok, nil}

  defp parse_fallback(id, actions) do
    id = to_string(id)

    if Enum.any?(actions, &(&1.id == id)),
      do: {:ok, id},
      else: {:error, {:unknown_fallback, id}}
  end

  # Node names are atoms by the time the object starts; never mint from
  # (possibly REST) input — an unknown name fails init.
  defp resolve_targets(cfg) do
    Enum.reduce_while(cfg.actions, {:ok, []}, fn action, {:ok, acc} ->
      case resolve_sends(action.send) do
        {:ok, sends} -> {:cont, {:ok, acc ++ [%{action | send: sends}]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, actions} -> {:ok, %{cfg | actions: actions}}
      error -> error
    end
  end

  defp resolve_sends(sends) do
    Enum.reduce_while(sends, {:ok, []}, fn
      %{to: to} = s, {:ok, acc} when is_atom(to) ->
        {:cont, {:ok, acc ++ [s]}}

      %{to: to} = s, {:ok, acc} ->
        try do
          {:cont, {:ok, acc ++ [%{s | to: String.to_existing_atom(to)}]}}
        rescue
          ArgumentError -> {:halt, {:error, {:unknown_target, to}}}
        end
    end)
  end

  # ── endpoint ─────────────────────────────────────────────────────────────────

  @doc false
  def resolve_endpoint(cfg_endpoint) do
    env_endpoint =
      case System.get_env("GENSWARMS_JEV_ENDPOINT") do
        url when is_binary(url) and url != "" -> String.trim_trailing(url, "/")
        _ -> nil
      end

    cond do
      is_nil(cfg_endpoint) and is_nil(env_endpoint) ->
        {:error, :no_jev_endpoint}

      is_nil(cfg_endpoint) ->
        {:ok, env_endpoint}

      EndpointPolicy.trusted_endpoint?(cfg_endpoint, env_endpoint) ->
        {:ok, cfg_endpoint}

      true ->
        {:error, {:endpoint_not_allowed, URI.parse(cfg_endpoint).host}}
    end
  end

  # ── ObjectHandler ────────────────────────────────────────────────────────────

  @impl true
  def init(config) do
    with {:ok, cfg} <- validate_config(config),
         {:ok, cfg} <- resolve_targets(cfg),
         {:ok, endpoint} <- resolve_endpoint(cfg.endpoint) do
      {swarm, name} = identity()

      state = %{
        cfg: cfg,
        swarm: swarm,
        name: name,
        endpoint: endpoint,
        memory: %{},
        recent: [],
        decisions: 0,
        inflight: nil,
        queue: :queue.new(),
        spent: {Date.utc_today(), 0.0},
        budget_logged: nil,
        timer: nil
      }

      first = if cfg.run_at_start, do: 0, else: cfg.every
      {:ok, schedule(state, first)}
    end
  end

  @impl true
  def handle_message(from, content, %{cfg: %{on_message: true}} = state) do
    trigger = %{kind: "message", from: to_string(from), message: content}
    {:noreply, request_or_queue(trigger, state)}
  end

  def handle_message(_from, _content, state), do: {:noreply, state}

  @impl true
  def handle_info(:jev_tick, state) do
    state = schedule(%{state | timer: nil}, state.cfg.every)

    if state.inflight do
      # Coalesce: a timer firing while a decision is pending is redundant.
      {:noreply, state}
    else
      {:noreply, request(%{kind: "timer", from: nil, message: nil}, state)}
    end
  end

  def handle_info({:jev_result, pid, result}, %{inflight: %{pid: pid} = f} = state) do
    Process.demonitor(f.ref, [:flush])
    {messages, state} = apply_result(result, f, %{state | inflight: nil})
    state = drain(state)

    case messages do
      [] -> {:noreply, state}
      msgs -> {:multi, msgs, state}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{inflight: %{ref: ref} = f} = state) do
    log(:error, :jev_error, "Jev decision crashed", state, %{
      trigger: f.trigger.kind,
      reason: String.slice(inspect(reason), 0, 300)
    })

    {:noreply, drain(%{state | inflight: nil})}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def interface do
    %{
      trigger: %{
        input: "any message (when on_message is true) or the `every` timer",
        output:
          "one Jev-chosen action from the configured catalogue: templated sends and/or memory changes"
      }
    }
  end

  @impl true
  def terminate(_reason, %{inflight: %{pid: pid}}) do
    Process.exit(pid, :kill)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  # ── triggering ───────────────────────────────────────────────────────────────

  defp schedule(state, nil), do: state

  defp schedule(state, ms) do
    if state.timer, do: Process.cancel_timer(state.timer)
    %{state | timer: Process.send_after(self(), :jev_tick, ms)}
  end

  defp request_or_queue(trigger, %{inflight: nil} = state), do: request(trigger, state)

  defp request_or_queue(trigger, state) do
    queue = :queue.in(trigger, state.queue)

    if :queue.len(queue) > @max_queue do
      {{:value, dropped}, queue} = :queue.out(queue)

      log(:warning, :jev_dropped, "Jev trigger queue full, dropped oldest", state, %{
        from: dropped.from
      })

      %{state | queue: queue}
    else
      %{state | queue: queue}
    end
  end

  defp drain(%{inflight: nil} = state) do
    case :queue.out(state.queue) do
      {{:value, trigger}, queue} -> request(trigger, %{state | queue: queue})
      {:empty, _} -> state
    end
  end

  defp drain(state), do: state

  defp request(trigger, state) do
    state = roll_budget_day(state)

    if over_budget?(state) do
      today = Date.utc_today()

      if state.budget_logged != today do
        log(:warning, :jev_budget_exhausted, "Jev daily budget exhausted", state, %{
          budget_usd_per_day: state.cfg.budget_usd_per_day
        })
      end

      %{state | budget_logged: today}
    else
      body = request_body(trigger, state)
      url = state.endpoint <> "/v1/decisions"
      timeout = state.cfg.timeout_ms + 5_000
      parent = self()

      {pid, ref} =
        spawn_monitor(fn ->
          send(parent, {:jev_result, self(), decide(url, body, timeout)})
        end)

      %{state | inflight: %{pid: pid, ref: ref, trigger: trigger, started: now_ms()}}
    end
  end

  defp roll_budget_day(%{spent: {day, _}} = state) do
    today = Date.utc_today()
    if day == today, do: state, else: %{state | spent: {today, 0.0}}
  end

  defp over_budget?(%{cfg: %{budget_usd_per_day: nil}}), do: false
  defp over_budget?(%{cfg: %{budget_usd_per_day: b}, spent: {_, usd}}), do: usd >= b

  @doc false
  def request_body(trigger, state) do
    cfg = state.cfg

    jev_state =
      %{
        "now" => now_iso(),
        "trigger" => trigger.kind,
        "memory" => state.memory,
        "recent" => state.recent
      }
      |> put_some("from", trigger.from)
      |> put_some(
        "message",
        trigger.message && String.slice(trigger.message, 0, @max_message_chars)
      )
      |> put_some("context", cfg.context)

    question = %{
      "type" => "choice",
      "instructions" => cfg.instructions,
      "criteria" => Map.new(cfg.actions, &{&1.id, &1.when})
    }

    %{"state" => jev_state, "questions" => %{"q" => question}, "timeout_ms" => cfg.timeout_ms}
    |> put_some("policy_ir", cfg.policy_ir)
  end

  defp put_some(map, _key, nil), do: map
  defp put_some(map, key, value), do: Map.put(map, key, value)

  # Runs in the spawned decision process.
  defp decide(url, body, timeout) do
    headers =
      case System.get_env("GENSWARMS_JEV_API_KEY") do
        key when is_binary(key) and key != "" -> [{"authorization", "Bearer " <> key}]
        _ -> []
      end

    started = now_ms()

    with {:ok, status, raw} when status in 200..299 <-
           transport().post(url, headers, Jason.encode!(body), timeout),
         {:ok, envelope} <- Jason.decode(raw) do
      parse_response(envelope, now_ms() - started)
    else
      {:ok, status, raw} -> {:error, {:http, status, String.slice(to_string(raw), 0, 200)}}
      {:error, %Jason.DecodeError{}} -> {:error, :invalid_json}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc false
  def parse_response(envelope, latency_ms) do
    resp = if is_map(envelope["result"]), do: envelope["result"], else: envelope

    case get_in(resp, ["answers", "q", "probabilities"]) do
      %{} = probs when map_size(probs) > 0 ->
        {:ok,
         %{
           probabilities:
             Map.new(probs, fn {k, v} -> {k, if(is_number(v), do: v * 1.0, else: 0.0)} end),
           model: resp["model"],
           cost_usd: cost(resp),
           latency_ms: latency_ms
         }}

      _ ->
        {:error, :no_probabilities}
    end
  end

  defp cost(resp) do
    case get_in(resp, ["x_router", "cost_usd"]) || get_in(resp, ["usage", "cost"]) do
      n when is_number(n) -> n * 1.0
      _ -> nil
    end
  end

  defp transport, do: Application.get_env(:genswarms, :jev_transport, __MODULE__.HTTP)

  # ── applying a decision ──────────────────────────────────────────────────────

  defp apply_result({:ok, decision}, inflight, state) do
    cfg = state.cfg
    # Only the configured ids count; renormalize so missing ids weigh nothing.
    probs = Map.new(cfg.actions, &{&1.id, Map.get(decision.probabilities, &1.id, 0.0)})
    total = probs |> Map.values() |> Enum.sum()

    if total <= 0.0 do
      apply_result({:error, :empty_distribution}, inflight, state)
    else
      probs = Map.new(probs, fn {k, v} -> {k, v / total} end)
      {top, confidence} = Enum.max_by(cfg.actions, &probs[&1.id]) |> then(&{&1.id, probs[&1.id]})

      {chosen, fell_back} =
        if confidence < cfg.min_confidence, do: {cfg.fallback, true}, else: {top, false}

      action = Enum.find(cfg.actions, &(&1.id == chosen))
      trigger = inflight.trigger

      vars = %{
        "now" => now_iso(),
        "trigger" => trigger.kind,
        "from" => trigger.from || "",
        "message" => trigger.message || "",
        "action" => chosen || "",
        "confidence" => :erlang.float_to_binary(confidence, decimals: 3)
      }

      {messages, memory} = run_action(action, vars, state.memory)

      entry = %{
        "at" => vars["now"],
        "trigger" => trigger.kind,
        "action" => chosen,
        "confidence" => Float.round(confidence, 3)
      }

      {day, usd} = state.spent

      state = %{
        state
        | memory: memory,
          recent: Enum.take([entry | state.recent], cfg.history),
          decisions: state.decisions + 1,
          spent: {day, usd + (decision.cost_usd || 0.0)}
      }

      log(:info, :jev_decision, "Jev chose #{chosen || "no action"}", state, %{
        trigger: trigger.kind,
        from: trigger.from,
        top: top,
        action: chosen,
        confidence: Float.round(confidence, 3),
        fell_back: fell_back,
        probabilities: Map.new(probs, fn {k, v} -> {k, Float.round(v, 3)} end),
        sent_to: Enum.map(messages, fn {:send, to, _} -> to end),
        model: decision.model,
        latency_ms: decision.latency_ms,
        cost_usd: decision.cost_usd
      })

      {messages, state}
    end
  end

  defp apply_result({:error, reason}, inflight, state) do
    log(:warning, :jev_error, "Jev decision failed", state, %{
      trigger: inflight.trigger.kind,
      reason: String.slice(inspect(reason), 0, 300)
    })

    {[], state}
  end

  defp run_action(nil, _vars, memory), do: {[], memory}

  defp run_action(action, vars, memory) do
    vars = Map.put(vars, :memory, memory)
    messages = Enum.map(action.send, &{:send, &1.to, render(&1.text, vars)})

    memory =
      action.remember
      |> Map.new(fn {k, v} -> {k, if(is_binary(v), do: render(v, vars), else: v)} end)
      |> then(&Map.merge(memory, &1))
      |> Map.drop(action.forget)

    {messages, memory}
  end

  @doc false
  def render(template, vars) do
    Regex.replace(@template_regex, template, fn whole, key ->
      case lookup(key, vars) do
        nil -> whole
        v when is_binary(v) -> v
        v -> Jason.encode!(v)
      end
    end)
  end

  defp lookup("memory", vars), do: vars.memory
  defp lookup("memory." <> key, vars), do: Map.get(vars.memory, key)
  defp lookup(key, vars), do: Map.get(vars, key)

  # ── helpers ──────────────────────────────────────────────────────────────────

  # The ObjectServer registers {swarm, name} before it calls init/1.
  defp identity do
    case Registry.keys(Genswarms.AgentRegistry, self()) do
      [{swarm, name} | _] -> {swarm, name}
      _ -> {nil, nil}
    end
  rescue
    _ -> {nil, nil}
  end

  defp log(level, event, message, state, metadata) do
    Logger.log(level, "[#{state.swarm}/#{state.name}] #{message}")

    LogStore.log(level, :object, event, "#{state.name}: #{message}",
      swarm: state.swarm,
      agent: state.name,
      metadata: metadata
    )
  end

  defp now_ms, do: System.monotonic_time(:millisecond)
  defp now_iso, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
