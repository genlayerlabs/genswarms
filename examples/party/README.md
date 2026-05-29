# Party Swarm Example

Tests the `swarm-msg` tool for agent-to-agent communication.

10 agents in a full mesh topology where everyone can talk to everyone. Agents introduce themselves, chat, and make connections using `swarm-msg send`.

## Run

```bash
mix swarm up examples/party/party_swarm.exs
```
