defmodule SubzeroclawSwarmWeb.Router do
  use SubzeroclawSwarmWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
    plug Corsica, origins: "*", allow_headers: :all, allow_methods: :all
  end

  # API root - returns API info
  scope "/", SubzeroclawSwarmWeb do
    pipe_through :api

    get "/", ApiController, :index
  end

  scope "/api", SubzeroclawSwarmWeb do
    pipe_through :api

    # Swarm management
    get "/swarms", SwarmController, :index
    post "/swarms", SwarmController, :create
    get "/swarms/:name", SwarmController, :show
    delete "/swarms/:name", SwarmController, :delete

    # Swarm lifecycle operations
    post "/swarms/:name/pause", SwarmController, :pause
    post "/swarms/:name/resume", SwarmController, :resume
    post "/swarms/:name/restart", SwarmController, :restart
    post "/swarms/:name/message", SwarmController, :route_message

    # Bulk operations
    post "/swarms/clean", SwarmController, :clean

    # Agent operations
    get "/swarms/:swarm_name/agents", SwarmController, :list_agents
    get "/swarms/:swarm_name/agents/:agent_name", SwarmController, :show_agent
    post "/swarms/:swarm_name/agents/:agent_name/task", SwarmController, :send_task
    post "/swarms/:swarm_name/agents/:agent_name/restart", SwarmController, :restart_agent
    get "/swarms/:swarm_name/agents/:agent_name/history", SwarmController, :agent_history
    get "/swarms/:swarm_name/agents/:agent_name/logs", SwarmController, :agent_logs
    get "/swarms/:swarm_name/agents/:agent_name/skills", SwarmController, :agent_skills

    put "/swarms/:swarm_name/agents/:agent_name/skills/:skill_name",
        SwarmController,
        :update_skill

    # Topology
    get "/swarms/:swarm_name/topology", SwarmController, :topology

    # Messages
    get "/swarms/:swarm_name/messages", SwarmController, :messages

    # Events (centralized logging)
    get "/events", EventsController, :index
    get "/swarms/:swarm_name/events", EventsController, :swarm_events
    get "/swarms/:swarm_name/agents/:agent_name/events", EventsController, :agent_events

    # Skills
    get "/skills", SkillsController, :index
    get "/skills/:name", SkillsController, :show

    # Config validation
    post "/config/validate", ConfigController, :validate
  end

end
