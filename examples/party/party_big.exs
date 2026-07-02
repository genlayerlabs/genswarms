# Full-mesh party, LOCAL backend, with the BIG skill (>1k-token cacheable
# prefix). Drives sustained chatter so the router exercises prompt-cache hits
# (stable prefix reused each turn) and async compaction (context growth).
skill_path = Path.join(__DIR__, "skills/party_big.md")
names = for i <- 1..8, do: :"agent_#{i}"

%{
  name: "party-big",
  agents: for(n <- names, do: %{name: n, backend: :local, skills: [skill_path]}),
  topology: for(a <- names, b <- names, a != b, do: {a, b})
}
