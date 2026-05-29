import Config

# Do not print debug messages in production
config :logger, level: :info

# Runtime production configuration
config :subzeroclaw_swarm, SubzeroclawSwarmWeb.Endpoint, server: true
