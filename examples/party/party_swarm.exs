# Party Swarm - Test inter-agent messaging
#
# 10 agents at a party, chatting with each other.
# Tests the message routing infrastructure.

# Build absolute path for skills
skill_path = Path.join(__DIR__, "skills/party.md")

%{
  name: "party-test",

  agents: [
    %{name: :agent_1, backend: {:docker, "szc-agent-code:latest", %{memory_limit: "512m"}}, skills: [skill_path], model: "minimax/minimax-m2.7"},
    %{name: :agent_2, backend: {:docker, "szc-agent-code:latest", %{memory_limit: "512m"}}, skills: [skill_path], model: "minimax/minimax-m2.7"},
    %{name: :agent_3, backend: {:docker, "szc-agent-code:latest", %{memory_limit: "512m"}}, skills: [skill_path], model: "minimax/minimax-m2.7"},
    %{name: :agent_4, backend: {:docker, "szc-agent-code:latest", %{memory_limit: "512m"}}, skills: [skill_path], model: "minimax/minimax-m2.7"},
    %{name: :agent_5, backend: {:docker, "szc-agent-code:latest", %{memory_limit: "512m"}}, skills: [skill_path], model: "minimax/minimax-m2.7"},
    %{name: :agent_6, backend: {:docker, "szc-agent-code:latest", %{memory_limit: "512m"}}, skills: [skill_path], model: "minimax/minimax-m2.7"},
    %{name: :agent_7, backend: {:docker, "szc-agent-code:latest", %{memory_limit: "512m"}}, skills: [skill_path], model: "minimax/minimax-m2.7"},
    %{name: :agent_8, backend: {:docker, "szc-agent-code:latest", %{memory_limit: "512m"}}, skills: [skill_path], model: "minimax/minimax-m2.7"},
    %{name: :agent_9, backend: {:docker, "szc-agent-code:latest", %{memory_limit: "512m"}}, skills: [skill_path], model: "minimax/minimax-m2.7"},
    %{name: :agent_10, backend: {:docker, "szc-agent-code:latest", %{memory_limit: "512m"}}, skills: [skill_path], model: "minimax/minimax-m2.7"}
  ],

  # Full mesh - everyone can talk to everyone
  topology: [
    {:agent_1, :agent_2}, {:agent_1, :agent_3}, {:agent_1, :agent_4}, {:agent_1, :agent_5},
    {:agent_1, :agent_6}, {:agent_1, :agent_7}, {:agent_1, :agent_8}, {:agent_1, :agent_9}, {:agent_1, :agent_10},
    {:agent_2, :agent_1}, {:agent_2, :agent_3}, {:agent_2, :agent_4}, {:agent_2, :agent_5},
    {:agent_2, :agent_6}, {:agent_2, :agent_7}, {:agent_2, :agent_8}, {:agent_2, :agent_9}, {:agent_2, :agent_10},
    {:agent_3, :agent_1}, {:agent_3, :agent_2}, {:agent_3, :agent_4}, {:agent_3, :agent_5},
    {:agent_3, :agent_6}, {:agent_3, :agent_7}, {:agent_3, :agent_8}, {:agent_3, :agent_9}, {:agent_3, :agent_10},
    {:agent_4, :agent_1}, {:agent_4, :agent_2}, {:agent_4, :agent_3}, {:agent_4, :agent_5},
    {:agent_4, :agent_6}, {:agent_4, :agent_7}, {:agent_4, :agent_8}, {:agent_4, :agent_9}, {:agent_4, :agent_10},
    {:agent_5, :agent_1}, {:agent_5, :agent_2}, {:agent_5, :agent_3}, {:agent_5, :agent_4},
    {:agent_5, :agent_6}, {:agent_5, :agent_7}, {:agent_5, :agent_8}, {:agent_5, :agent_9}, {:agent_5, :agent_10},
    {:agent_6, :agent_1}, {:agent_6, :agent_2}, {:agent_6, :agent_3}, {:agent_6, :agent_4},
    {:agent_6, :agent_5}, {:agent_6, :agent_7}, {:agent_6, :agent_8}, {:agent_6, :agent_9}, {:agent_6, :agent_10},
    {:agent_7, :agent_1}, {:agent_7, :agent_2}, {:agent_7, :agent_3}, {:agent_7, :agent_4},
    {:agent_7, :agent_5}, {:agent_7, :agent_6}, {:agent_7, :agent_8}, {:agent_7, :agent_9}, {:agent_7, :agent_10},
    {:agent_8, :agent_1}, {:agent_8, :agent_2}, {:agent_8, :agent_3}, {:agent_8, :agent_4},
    {:agent_8, :agent_5}, {:agent_8, :agent_6}, {:agent_8, :agent_7}, {:agent_8, :agent_9}, {:agent_8, :agent_10},
    {:agent_9, :agent_1}, {:agent_9, :agent_2}, {:agent_9, :agent_3}, {:agent_9, :agent_4},
    {:agent_9, :agent_5}, {:agent_9, :agent_6}, {:agent_9, :agent_7}, {:agent_9, :agent_8}, {:agent_9, :agent_10},
    {:agent_10, :agent_1}, {:agent_10, :agent_2}, {:agent_10, :agent_3}, {:agent_10, :agent_4},
    {:agent_10, :agent_5}, {:agent_10, :agent_6}, {:agent_10, :agent_7}, {:agent_10, :agent_8}, {:agent_10, :agent_9}
  ]
}
