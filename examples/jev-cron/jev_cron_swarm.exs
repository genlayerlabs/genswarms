# Jev-cron: a cheap Jev decision gates an expensive LLM agent.
#
# :watch wakes every 10 minutes and on every message routed to it, asks Jev
# (the router's /v1/decisions) to pick one action, and only wakes :coder when
# something actually needs a fix. Requires GENSWARMS_JEV_ENDPOINT and
# GENSWARMS_JEV_API_KEY (see README.md).
skill_path = Path.join(__DIR__, "skills/coder.md")

%{
  name: "jev-cron",
  agents: [
    %{name: :coder, backend: :local, skills: [skill_path]}
  ],
  objects: [
    %{
      name: :watch,
      handler: Genswarms.Objects.JevCron,
      config: %{
        every: "10m",
        instructions:
          "A monitoring report or a periodic check arrived. Decide whether the coder must act now.",
        context: %{service: "genswarms", on_call: "coder"},
        actions: [
          %{id: "nothing", when: "Routine, informational, or already handled"},
          %{
            id: "wake",
            when: "Something is broken or failing and needs a code fix",
            send: %{to: :coder, text: "Jev ({{confidence}}) flagged this, please fix: {{message}}"},
            remember: %{"last_wake" => "{{now}}", "last_issue" => "{{message}}"}
          },
          %{
            id: "clear",
            when: "The report says a previously flagged problem is now resolved",
            forget: ["last_issue"]
          }
        ],
        min_confidence: 0.6,
        fallback: "nothing",
        budget_usd_per_day: 0.10
      }
    }
  ],
  topology: [{:watch, :coder}, {:coder, :watch}]
}
