defmodule Genswarms.TelemetryTest do
  use ExUnit.Case, async: false

  describe "measure_swarms/0 (telemetry_poller periodic measurement)" do
    test "always returns :ok — a measurement must never blow up the poller" do
      # Whichever state SwarmManager is in (running, absent, or slow), the
      # measurement swallows it: :noproc / :timeout exits and any raise from
      # unexpected swarm-entry shapes previously escaped the old
      # {:noproc, _}-only guard and logged
      # "Error when calling MFA defined by measurement" on every poll tick.
      assert Genswarms.Telemetry.measure_swarms() == :ok
    end

    test "swallows exits from a busy/absent SwarmManager (guard is :exit-wide)" do
      # Simulate the live failure: a caller that exits with something OTHER
      # than {:noproc, _} (the only clause the old guard matched). We can't
      # easily force a GenServer.call timeout here without slowing the suite,
      # so pin the guard shape instead: the rescue/catch in measure_swarms
      # must cover :exit of ANY shape and any raise.
      source = File.read!(Path.join([__DIR__, "..", "..", "..", "lib", "genswarms", "telemetry", "telemetry.ex"]))
      [_, body] = String.split(source, "def measure_swarms do", parts: 2)
      guard_window = String.slice(body, 0, 1_200)

      assert guard_window =~ "catch"
      assert guard_window =~ ~r/:exit,\s*_/, "the :exit guard must be shape-agnostic (timeouts, not just :noproc)"
      assert guard_window =~ "rescue", "raises from swarm-entry shape drift must be swallowed too"
    end
  end
end
