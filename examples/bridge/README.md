# Cross-Swarm Bridge Example

This example demonstrates two independent daemon swarms communicating via a bridge object. Each swarm runs as a separate OS process, and messages are exchanged through the shared SQLite task queue.

## Architecture

```
Daemon A (OS Process 1)              Daemon B (OS Process 2)
+------------------+                 +------------------+
|  messenger_a     |                 |  messenger_b     |
|       |          |                 |       ^          |
|       v          |                 |       |          |
|  bridge          | --- SQLite ---> |  (daemon polls)  |
|  (queue_task)    | <-- SQLite ---- |  (queue_task)    |
+------------------+                 +------------------+
           \                               /
            \_____ ~/.subzeroclaw/ _______/
                   swarm_registry.db
                   (shared SQLite)
```

## How It Works

1. **Bridge Object**: Each swarm has a bridge object that implements `ObjectHandler`
2. **SQLite Task Queue**: The bridge uses `SwarmRegistry.queue_task/3` to queue messages
3. **Daemon Polling**: Each daemon polls the task queue every ~500ms
4. **Message Delivery**: Queued tasks are delivered to the target agent

## Files

| File | Purpose |
|------|---------|
| `objects/bridge.ex` | Bridge ObjectHandler for cross-swarm routing |
| `swarm_a.exs` | Configuration for swarm-a with messenger_a |
| `swarm_b.exs` | Configuration for swarm-b with messenger_b |
| `skills/messenger.md` | Skill file teaching agents how to use the bridge |

## Usage

### 1. Build the CLI

```bash
mix escript.build
```

### 2. Start Both Swarms

```bash
./swarm start examples/bridge/swarm_a.exs
./swarm start examples/bridge/swarm_b.exs
```

### 3. Verify Status

```bash
./swarm status
```

You should see both swarm-a and swarm-b running.

### 4. Initiate Cross-Swarm Communication

Send a task to messenger_a:

```bash
./swarm task swarm-a messenger_a "Send a greeting to messenger_b in swarm-b"
```

### 5. Monitor Logs

In separate terminals, watch the logs from each swarm:

```bash
# Terminal 1
./swarm logs swarm-a --follow

# Terminal 2
./swarm logs swarm-b --follow
```

You should see:
- messenger_a sending a message to the bridge
- The bridge logging the forward to swarm-b
- messenger_b receiving the message (after ~500ms)

### 6. Check Events

```bash
./swarm events --follow
```

### 7. Stop Both Swarms

```bash
./swarm stop swarm-a
./swarm stop swarm-b
```

## Message Format

### Explicit Routing

Agents can specify the exact destination:

```
@bridge: {"to": {"swarm": "swarm-b", "agent": "messenger_b"}, "content": "Hello!"}
```

### Pre-configured Routing

If the bridge has routing configured, agents can send content directly:

```
@bridge: Hello from swarm-a!
```

The bridge configuration determines where messages are routed:

```elixir
config: %{
  swarm_name: "swarm-a",
  routing: %{messenger_a: {"swarm-b", :messenger_b}}
}
```

### Received Message Format

Messages arrive at the destination with source information:

```json
{"from_swarm": "swarm-a", "from_agent": "messenger_a", "content": "Hello!"}
```

## Latency

Message delivery has ~500ms latency due to the daemon polling interval. This is suitable for:
- Asynchronous workflows
- Task handoffs between swarms
- Collaborative agent systems

For lower latency, consider running swarms in the same process with direct object communication.

## Extending the Example

### Multiple Agents

Add more agents to each swarm and configure routing:

```elixir
routing: %{
  agent_1: {"swarm-b", :handler_1},
  agent_2: {"swarm-b", :handler_2}
}
```

### Bidirectional Communication

Both swarms have bridges configured for bidirectional routing, so messenger_b can reply to messenger_a.

### Custom Routing Logic

Modify `Bridge.Objects.Bridge.handle_message/3` to implement custom routing logic based on message content, load balancing, or other criteria.
