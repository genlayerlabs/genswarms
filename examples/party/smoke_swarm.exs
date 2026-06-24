# Minimal smoke swarm — 2 local agents, no `model:` so each inherits the
# routing policy from SUBZEROCLAW_REQUEST_EXTRA (cache_hot affinity) and seals
# via SUBZEROCLAW_COMPACT_EXTRA. Tests the genswarms → subzeroclaw → unhardcoded
# router path end to end.
skill_path = Path.join(__DIR__, "skills/party.md")

%{
  name: "smoke",
  agents: [
    %{name: :a1, backend: :local, skills: [skill_path]},
    %{name: :a2, backend: :local, skills: [skill_path]}
  ],
  topology: [{:a1, :a2}, {:a2, :a1}]
}
