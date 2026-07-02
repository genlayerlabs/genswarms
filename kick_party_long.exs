# Start the big-skill party and keep it talking for a few minutes: an initial
# kick to every agent, then periodic re-kicks so the mesh never goes idle.
{:ok, name} = Genswarms.SwarmManager.start_swarm("examples/party/party_big.exs")
IO.puts("started swarm: #{name}")
Process.sleep(4000)

kick = fn topic ->
  for j <- 2..8, do: Genswarms.Routing.Router.route(name, :agent_1, :"agent_#{j}", topic)
  Genswarms.Routing.Router.route(name, :agent_2, :agent_1, topic)
end

topics = [
  "¡Empieza la fiesta! Preséntate y pregunta a alguien en qué trabaja. Usa swarm-msg send.",
  "Cuenta algo interesante que hayas oído en la fiesta y pásalo a otro invitado.",
  "Busca puntos en común con dos invitados distintos. Sé breve.",
  "¿Quién es la persona más curiosa que has conocido aquí? Sigue charlando.",
  "Organiza un pequeño grupo: presenta a dos invitados entre sí.",
  "Comparte un consejo corto y pregunta a otro qué opina.",
  "La fiesta sigue — saluda a alguien con quien aún no has hablado.",
  "Despídete poco a poco pero mantén la charla viva un rato más."
]

Enum.each(Enum.with_index(topics), fn {t, i} ->
  IO.puts("kick round #{i + 1}")
  kick.(t)
  Process.sleep(30_000)
end)

IO.puts("done kicking; settling 20s")
Process.sleep(20_000)
IO.puts("done")
