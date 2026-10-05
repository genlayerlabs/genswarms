---
description: Objects in GenSwarms: deterministic, non-agentic Elixir components that participate in the swarm topology.
---

# Objects

Objects are non-agentic components of a swarm. Where an agent is backed by an LLM
that produces free-form text, an object is a plain Elixir module that runs
deterministic code. Objects participate in the swarm topology exactly like
agents: they receive messages, hold state, and send messages to other agents or
objects. They are the right tool for game referees, evaluators, gateways,
schedulers, validators, and bridges between swarms.

Each object is hosted by a `Genswarms.Objects.ObjectServer` (a GenServer). For a
native object the server delegates to a module that implements the
`Genswarms.Objects.ObjectHandler` behaviour. (Objects can also be backed by a
Docker or SSH process that speaks the same JSON protocol over stdin/stdout; this
guide focuses on native handlers, which are the common case.)

## The ObjectHandler behaviour

A native object is any module that declares `@behaviour
Genswarms.Objects.ObjectHandler` and implements its callbacks.

```elixir
defmodule ExampleSwarm.Objects.Evaluator do
  @behaviour Genswarms.Objects.ObjectHandler

  @impl true
  def init(config) do
    {:ok, %{config: config, results: []}}
  end

  @impl true
  def handle_message(from, content, state) do
    {:reply, "ack", state}
  end

  @impl true
  def interface do
    %{evaluate: %{input: "JSON list of configs", output: "JSON with results"}}
  end
end
```

### Callbacks

| Callback | Required | Purpose |
|----------|----------|---------|
| `init(config)` | yes | Build the handler's initial state from its declared config map. |
| `handle_message(from, content, state)` | yes | React to a message routed from another node. |
| `interface()` | yes | Return a schema describing the object's actions (introspection). |
| `handle_info(msg, state)` | no | Handle process messages such as timers. |
| `terminate(reason, state)` | no | Cleanup when the object stops. |
| `validate_config(config)` | no | Reject a bad config at validation time (`genswarms config validate`, swarm start) instead of at `init/1`. |

`handle_info/2` and `terminate/2` are the only optional callbacks — the
behaviour declares `@optional_callbacks [terminate: 2, handle_info: 2]`. The
`ObjectServer` checks at runtime (with `function_exported?/3`) whether the
handler exports them before calling them, so you only implement them if you
need them.

## init/1

`init/1` is called once when the `ObjectServer` starts. `config` is the map you
provide in the swarm configuration under the object's `:config` key.

The behaviour's published typespec covers the two-tuple and the single-send
forms:

```elixir
@callback init(config :: map()) ::
            {:ok, state}
            | {:ok, state, {:send, to, content}}
            | {:error, reason}
```

In addition, the `ObjectServer` also honors a `{:multi, messages}` form at
runtime (see the table below).

| Return value | Semantics |
|--------------|-----------|
| `{:ok, state}` | Initialize with `state`; do nothing else. |
| `{:ok, state, {:send, to, content}}` | Initialize, then send an opening message to `to`. |
| `{:ok, state, {:multi, messages}}` | Initialize, then send several opening messages (see below). |
| `{:error, reason}` | Initialization failed; the object enters its `:error` state and drops any messages delivered to it. |

The `{:ok, state, {:send, to, content}}` form is how an object kicks off a
conversation. The tic-tac-toe game (`examples/tic-tac-toe/objects/game.ex`) uses
it to send the first turn to the opening player:

```elixir
@impl true
def init(_config) do
  board = [[".", ".", "."], [".", ".", "."], [".", ".", "."]]
  state = %{board: board, turn: :player_x, game_over: false, winner: nil, move_count: 0}
  {:ok, state, {:send, :player_x, encode(:your_turn, %{board: board})}}
end
```

The `{:ok, state, {:multi, messages}}` form accepts a list of
`{:send, to, content}` and `{:broadcast, content}` tuples and dispatches all of
them after initialization. (Bare `{target, msg}` pairs are *not* accepted in the
`init/1` multi form; that shorthand only exists for `handle_message/3`'s
`:send_many`.)

## handle_message/3

`handle_message/3` runs for every message routed to the object. `from` is the
sender's name (an atom), `content` is the message string, and `state` is the
current handler state. The return tuple tells the `ObjectServer` what to send
and how to update state.

The behaviour's published typespec covers the four common forms:

```elixir
@callback handle_message(from :: atom(), content :: String.t(), state) ::
            {:reply, response, new_state}
            | {:send, to, content, new_state}
            | {:broadcast, content, new_state}
            | {:noreply, new_state}
```

The handler may also return the multi-message tuples below. The full set of
return tuples honored by the `ObjectServer` dispatch is:

| Return tuple | Semantics |
|--------------|-----------|
| `{:reply, response, new_state}` | Route `response` back to the original sender (`from`). |
| `{:send, to, content, new_state}` | Route `content` to a specific node `to`. |
| `{:broadcast, content, new_state}` | Send `content` to every node connected to this object in the topology. |
| `{:noreply, new_state}` | Update state only; send nothing. |
| `{:send_many, messages, new_state}` | Send several messages at once (flexible item shapes — see below). |
| `{:multi, messages, new_state}` | Send several messages at once (tagged item shapes only). |

All routed targets are subject to the topology: a message only reaches `to` if
there is an edge from this object to `to` (or `to` is a system object — see
below). After any of these returns the object goes back to its `:idle` state and
its `message_count` is incremented.

### `:send_many` vs `:multi`

Both forms emit multiple messages from a single callback return. They differ
only in the item shapes they accept.

`:multi` accepts tagged tuples only — `{:send, to, msg}` and `{:broadcast, msg}`:

```elixir
{:multi,
 [
   {:send, :player_x, "your move"},
   {:broadcast, "game starting"}
 ], new_state}
```

`:send_many` accepts those tagged tuples *and* bare `{target, msg}` pairs, so you
can mix styles:

```elixir
{:send_many,
 [
   {:player_x, "your move"},          # bare {target, msg}
   {:send, :player_o, "stand by"},    # tagged send
   {:broadcast, "game starting"}      # tagged broadcast
 ], new_state}
```

Use `:send_many` when it is convenient to build a keyword-like list of
`{target, msg}` pairs; use `:multi` when you want every item explicitly tagged.

### Worked example: a turn-validating game object

The tic-tac-toe `Game` object (`examples/tic-tac-toe/objects/game.ex`, module
`TicTacToe.Objects.Game`) shows the common return tuples in one handler. It
replies to the sender on an invalid move, sends the next turn to the other
player on a valid move, and broadcasts the final result when the game ends.

```elixir
@impl true
def handle_message(from, content, state) do
  cond do
    state.game_over ->
      {:reply, encode(:error, "Game over. #{winner_msg(state.winner)}"), state}

    from != state.turn ->
      {:reply, encode(:error, "Not your turn, waiting for #{state.turn}"), state}

    true ->
      process_move(from, content, state)
  end
end

defp process_move(from, content, state) do
  # ... validate, update board ...
  case check_result(new_board) do
    {:win, p} ->
      winner = if p == "X", do: :player_x, else: :player_o
      {:broadcast, encode(:game_over, %{board: new_board, winner: winner}), final}

    :draw ->
      {:broadcast, encode(:game_over, %{board: new_board, winner: "draw"}), final}

    :continue ->
      {:send, next, encode(:your_turn, %{board: new_board}), new_state}
  end
end
```

## handle_info/2 for timers and process messages

Objects are GenServers, so they can receive ordinary process messages. Implement
the optional `handle_info/2` callback to react to timers scheduled with
`Process.send_after/3` or other Erlang messages. It returns the same tuples as
`handle_message/3` (including `:send_many` and `:multi`):

```elixir
@impl true
def init(_config) do
  Process.send_after(self(), :tick, 1_000)
  {:ok, %{ticks: 0}}
end

@impl true
def handle_info(:tick, state) do
  Process.send_after(self(), :tick, 1_000)
  {:broadcast, "tick #{state.ticks}", %{state | ticks: state.ticks + 1}}
end
```

A `:reply` returned from `handle_info/2` has no original sender to reply to, so
the `ObjectServer` logs it and treats it as a state-only update.

## interface/0 introspection

`interface/0` returns a map describing the actions the object supports and their
expected input/output. It is surfaced through `ObjectServer.get_interface/2` for
display in tooling and dashboards and does not affect routing. By convention each
key is an action name pointing at a map with `:input` and `:output`
descriptions.

```elixir
@impl true
def interface do
  %{
    move: %{
      input: ~s({"board": [["X",".","."],[".",".","."],[".",".","."]]}),
      output: "Validates move, sends board to next player or announces winner"
    }
  }
end
```

## Logging from an object

Handlers can write structured entries to the centralized event log via
`Genswarms.Objects.ObjectServer.log/5`:

```elixir
alias Genswarms.Objects.ObjectServer

ObjectServer.log(:info, "tic-tac-toe", :game, "Move accepted", %{player: from})
```

The arguments are `level`, `swarm_name`, `object_name`, `message`, and an
optional `metadata` map (defaults to `%{}`):

```elixir
@spec log(level, swarm_name, object_name, message, metadata \\ %{}) :: term()
```

Internally this calls `LogStore.log/4` with `source: :object` and
`event: :custom`, tagging the entry with the swarm and object names. See
[observability.md](observability.md) for how these events are queried and
streamed.

## Declaring objects in a swarm

Objects are listed under the `:objects` key of a swarm configuration. Each entry
needs a `:name` and a `:handler`; the optional `:config` map is passed verbatim
to the handler's `init/1`. Objects appear in `:topology` edges just like agents.

The snippet below is the tic-tac-toe swarm
(`examples/tic-tac-toe/tic_tac_toe_swarm.exs`), trimmed for brevity:

```elixir
# Load the object handler module before referencing it in config.
Code.require_file("objects/game.ex", __DIR__)

%{
  name: "tic-tac-toe",
  agents: [
    %{
      name: :player_x,
      backend: {:docker, "szc-agent-code:latest", %{memory_limit: "512m"}},
      skills: [Path.join([__DIR__, "skills", "player_x.md"])],
      model: "minimax/minimax-m2.7"
    },
    %{
      name: :player_o,
      backend: {:docker, "szc-agent-code:latest", %{memory_limit: "512m"}},
      skills: [Path.join([__DIR__, "skills", "player_o.md"])],
      model: "minimax/minimax-m2.7"
    }
  ],
  objects: [
    %{
      name: :game,
      handler: TicTacToe.Objects.Game,
      config: %{}
    }
  ],
  topology: [
    {:player_x, :game},
    {:game, :player_x},
    {:player_o, :game},
    {:game, :player_o}
  ]
}
```

The `config` map is how you parameterize an object. A bridge object, for
instance, might receive its swarm name and a routing table:

```elixir
objects: [
  %{
    name: :bridge,
    handler: ExampleSwarm.Objects.Bridge,
    config: %{
      swarm_name: "example-swarm",
      routing: %{messenger_a: {"swarm-b", :messenger_b}}
    }
  }
]
```

See [configuration.md](configuration.md) for the full configuration DSL.

## Jev-cron

`Genswarms.Objects.JevCron` is a built-in object that answers a closed question
on a timer and/or on every message it receives. It asks a **Jev** decision model
(the unhardcoded router's `/v1/decisions`) to choose **one action out of a fixed
catalogue**, then applies that action deterministically. Jev never writes text:
it returns one probability per action id, and everything the object sends comes
from your templates. A decision costs about $0.00002 and takes about 1 s, so a
jev-cron is a cheap gate in front of expensive LLM agents.

```elixir
objects: [
  %{
    name: :watch,
    handler: Genswarms.Objects.JevCron,
    config: %{
      every: "10m",
      instructions: "Decide whether the coder must act now.",
      context: %{service: "api"},
      actions: [
        %{id: "nothing", when: "Routine or already handled"},
        %{id: "wake", when: "Something is broken and needs a code fix",
          send: %{to: :coder, text: "Please fix: {{message}}"},
          remember: %{"last_issue" => "{{message}}"}},
        %{id: "clear", when: "A flagged problem is resolved", forget: ["last_issue"]}
      ],
      min_confidence: 0.6,
      fallback: "nothing"
    }
  }
],
topology: [{:watch, :coder}, {:coder, :watch}]
```

| Key | Default | Meaning |
|-----|---------|---------|
| `every` | none | Timer period: ms, or `"30s"`, `"5m"`, `"1h"`, `"1d"` (minimum 1 s). Omit for message-only. |
| `on_message` | `true` | Decide on every message routed to the object. |
| `run_at_start` | `false` | Decide once right after the object starts. |
| `instructions` | required | The question Jev answers. |
| `actions` | required | 2–32 actions, each `%{id, when}` plus optional `send` (`%{to, text}` or a list), `remember` (map merged into memory) and `forget` (keys dropped from memory). `when` is the label Jev scores. |
| `min_confidence` | `0.0` | Below it, `fallback` applies instead of the top action. |
| `fallback` | none | Action id used on low confidence. With no fallback, nothing happens. |
| `context` | none | Static JSON included in every decision state. |
| `history` | `5` | Recent decisions included in the state (0–50). |
| `policy_ir` | none | Router policy that selects the decision model, passed through unchanged. |
| `budget_usd_per_day` | none | Once the router-reported cost reaches this, decisions stop for the rest of the UTC day. |
| `timeout_ms` | `30000` | Decision timeout. |
| `endpoint` | env | Router base URL; see below. |

**Decision state.** Jev sees `now`, `trigger` (`"timer"` or `"message"`), `from`
and `message` (for messages), `context`, the object's `memory`, and `recent`
decisions. `remember`/`forget` change the memory, so each decision can depend
on what earlier ones did.

**Templates.** `send.text` and string `remember` values can use `{{message}}`,
`{{from}}`, `{{trigger}}`, `{{now}}`, `{{action}}`, `{{confidence}}`,
`{{memory}}` and `{{memory.KEY}}`.

**Concurrency.** Only one decision is in flight at a time. Messages that arrive
meanwhile wait in a queue (the oldest is dropped beyond 20), and a timer tick
that fires during a decision is skipped. Router errors and malformed answers
trigger no action and are logged as `jev_error`.

**Endpoint and key.** The router base URL comes from `GENSWARMS_JEV_ENDPOINT`;
the bearer key comes from `GENSWARMS_JEV_API_KEY` and is never part of the
config. A per-object `endpoint` is accepted only if it equals the env endpoint
or its host is listed in `GENSWARMS_ALLOWED_ENDPOINTS`; otherwise the object
fails to start. Requests go through `curl`, with the key in a private
temporary file rather than in argv.

**Observability.** Each decision is a `jev_decision` event with the trigger,
the top and applied action, the confidence, the full distribution, the targets
sent to, the model, the latency and the cost. Query them with
`genswarms events -s <swarm>`, `GET /api/swarms/:name/events`, or the
genswarms-fleet MCP.

**Validation and live tuning.** `genswarms config validate` checks a jev-cron
config before start. Every key except `endpoint` is `x-mutable`, so you can
retune a running jev-cron with `PATCH /api/swarms/:name/objects/:object/config`;
the object restarts with the merged config. See
[`examples/jev-cron`](https://github.com/genlayerlabs/genswarms/tree/main/examples/jev-cron).

## System objects

The router always allows messages to three reserved system object names, even
when no explicit topology edge exists:

| Name | Purpose |
|------|---------|
| `:metrics` | Metrics sink. |
| `:tick` | Clock / scheduling. |
| `:gateway` | External gateway. |

These are defined as `@system_objects [:metrics, :tick, :gateway]` in
`lib/genswarms/routing/router.ex`. Any node may send to them without declaring an
edge; define a handler for them only if you want to act on what they receive.

## See also

- [configuration.md](configuration.md) — declaring objects and topology
- [messaging.md](messaging.md) — how messages are routed between nodes
- [programmatic.md](programmatic.md) — driving swarms from Elixir code
- [observability.md](observability.md) — querying and streaming object log events
