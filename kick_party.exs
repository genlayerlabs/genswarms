# Run the full-mesh party in THIS BEAM and kick every agent, so the cascade
# (and async compaction) runs without needing the HTTP API / a separate daemon.
{:ok, name} = Genswarms.SwarmManager.start_swarm("examples/party/party_local.exs")
IO.puts("started swarm: #{name}")
Process.sleep(4000)

# Kick via real mesh edges (agent->agent). agent_1 nudges everyone else;
# agent_2 nudges agent_1. Every agent gets a first turn -> the cascade starts.
kick = "¡Empieza la fiesta! Preséntate en una frase y saluda a 2 compañeros distintos con `swarm-msg send <nombre> <mensaje>`. Sé breve."
for j <- 2..8, do: Genswarms.Routing.Router.route(name, :agent_1, :"agent_#{j}", kick)
Genswarms.Routing.Router.route(name, :agent_2, :agent_1, kick)

IO.puts("kicked 8 agents — running 160s for chatter + compaction...")
Process.sleep(160_000)
IO.puts("done")
