# Use a temp SQLite DB for tests to avoid clobbering the dev .genswarms/swarms.db
test_db =
  Path.join(System.tmp_dir!(), "subzero_swarm_test_#{System.unique_integer([:positive])}.db")

test_events =
  Path.join(System.tmp_dir!(), "subzero_swarm_test_events_#{System.unique_integer([:positive])}")

Application.put_env(:genswarms, :db_path, test_db)
Application.put_env(:genswarms, :events_dir, test_events)

ExUnit.after_suite(fn _ ->
  File.rm(test_db)
  File.rm_rf(test_events)
end)

# Property tests: PROPERTY_RUNS=100000 for long runs (default 100 per property).
if runs = System.get_env("PROPERTY_RUNS") do
  Application.put_env(:stream_data, :max_runs, String.to_integer(runs))
end

# PROPERTY_SECONDS=90 runs each property for a fixed time instead of a fixed count.
if seconds = System.get_env("PROPERTY_SECONDS") do
  Application.put_env(:stream_data, :max_runs, 1_000_000_000)
  Application.put_env(:stream_data, :max_run_time, String.to_integer(seconds) * 1000)
end

# :known_bug tests document confirmed defects and fail today.
# Run them with `mix test --include known_bug`.
ExUnit.start(exclude: [:known_bug])
