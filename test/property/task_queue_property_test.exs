defmodule Genswarms.Property.TaskQueuePropertyTest do
  @moduledoc """
  Rule: the SQLite task queue hands back exactly the tasks that were queued
  for that swarm and not yet marked processed, oldest first.
  """
  use ExUnit.Case
  use ExUnitProperties

  # Long runs (PROPERTY_RUNS) outlast the default 60s per test.
  @moduletag timeout: :infinity

  alias Genswarms.CLI.SwarmRegistry

  setup_all do
    SwarmRegistry.init()
  end

  defp op_gen do
    one_of([
      tuple(
        {constant(:queue), member_of([:a, :b]), member_of(["pq_x", "pq_y"]),
         string(:printable, max_length: 20)}
      ),
      tuple({constant(:process), member_of([:a, :b]), integer(0..5)}),
      tuple({constant(:poll), member_of([:a, :b])})
    ])
  end

  property "pending tasks match a simple list model" do
    check all(ops <- list_of(op_gen(), max_length: 20)) do
      run = System.unique_integer([:positive])
      swarms = %{a: "prop-queue-a-#{run}", b: "prop-queue-b-#{run}"}

      try do
        Enum.reduce(ops, %{a: [], b: []}, fn
          {:queue, key, agent, task}, model ->
            :ok = SwarmRegistry.queue_task(swarms[key], agent, task)
            Map.update!(model, key, &(&1 ++ [{agent, task}]))

          # Mark the nth pending task processed, as the daemon does after delivery.
          {:process, key, n}, model ->
            case Enum.at(SwarmRegistry.get_pending_tasks(swarms[key]), n) do
              nil ->
                model

              task ->
                :ok = SwarmRegistry.mark_task_processed(task.id)
                Map.update!(model, key, &List.delete_at(&1, n))
            end

          {:poll, key}, model ->
            pending = SwarmRegistry.get_pending_tasks(swarms[key])
            assert Enum.map(pending, &{to_string(&1.agent), &1.task}) == model[key]
            model
        end)
        |> then(fn model ->
          for {key, expected} <- model do
            pending = SwarmRegistry.get_pending_tasks(swarms[key])
            assert Enum.map(pending, &{to_string(&1.agent), &1.task}) == expected
          end
        end)
      after
        for {_key, swarm} <- swarms, do: SwarmRegistry.delete_swarm(swarm)
      end
    end
  end
end
