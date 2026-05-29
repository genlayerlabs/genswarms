# General application configuration
import Config

config :subzeroclaw_swarm,
  ecto_repos: [],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :subzeroclaw_swarm, SubzeroclawSwarmWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: SubzeroclawSwarmWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: SubzeroclawSwarm.PubSub

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :swarm, :agent]

# Use Jason for JSON parsing
config :phoenix, :json_library, Jason

# SubzeroclawSwarm specific configuration
config :subzeroclaw_swarm,
  # Default path to subzeroclaw binary
  subzeroclaw_path: System.get_env("SUBZEROCLAW_PATH", "subzeroclaw"),
  # Base directory for swarm data
  swarm_data_dir: System.get_env("SWARM_DATA_DIR", "~/.subzeroclaw/swarms"),
  # Default skills directory
  skills_dir: System.get_env("SKILLS_DIR", "priv/skills")

# Import environment specific config
import_config "#{config_env()}.exs"
