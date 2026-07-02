# Full-mesh party on the LOCAL backend (no docker image needed): N agents all
# talking to each other. With a lowered router compaction threshold this drives
# context growth fast enough to trigger async /v1/compact. No `model:` — each
# agent inherits the routing policy from SUBZEROCLAW_REQUEST_EXTRA (cache_hot
# affinity) and seals via SUBZEROCLAW_COMPACT_EXTRA.
skill_path = Path.join(__DIR__, "skills/party.md")
names = for i <- 1..8, do: :"agent_#{i}"

%{
  name: "party-local",
  agents: for(n <- names, do: %{name: n, backend: :local, skills: [skill_path]}),
  topology: for(a <- names, b <- names, a != b, do: {a, b})
}
