defmodule Genswarms.Objects.ObjectServerAwaitInitTest do
  @moduledoc """
  Regression tests for #80: ObjectServer.init/1 defers the handler's real
  init/1 call via `send(self(), :init_object)`, so start_link/start_object
  returning {:ok, pid} only means the PROCESS spawned — not that the
  handler's init actually succeeded. await_init/3 is the handshake callers
  must use to learn the real outcome.

  Covers: success, failure, a slow init (await_init must actually block,
  not just check a timestamp), a late caller (asking after resolution),
  and multiple concurrent callers all released with the same answer.
  """
  use ExUnit.Case, async: true

  alias Genswarms.Objects.ObjectServer

  defmodule PickyHandler do
    @moduledoc "Rejects init when config[:bad] is true; can also simulate a slow init."
    @behaviour Genswarms.Objects.ObjectHandler

    @impl true
    def init(config) do
      if ms = config[:slow], do: Process.sleep(ms)
      if config[:bad], do: {:error, :bad_config}, else: {:ok, %{}}
    end

    @impl true
    def handle_message(_from, _content, state), do: {:noreply, state}

    @impl true
    def interface(), do: %{}
  end

  defp start(name, config) do
    swarm = "await-init-#{System.unique_integer([:positive])}"

    {:ok, _pid} =
      ObjectServer.start_link(
        name: name,
        swarm_name: swarm,
        handler: PickyHandler,
        config: config
      )

    swarm
  end

  test "await_init returns :ok once a successful init resolves" do
    swarm = start(:ok_obj, %{})
    assert :ok = ObjectServer.await_init(swarm, :ok_obj)
  end

  test "await_init returns {:error, reason} once a rejecting init resolves" do
    swarm = start(:bad_obj, %{bad: true})
    assert {:error, :bad_config} = ObjectServer.await_init(swarm, :bad_obj)
  end

  test "await_init blocks until a slow init actually resolves" do
    swarm = start(:slow_obj, %{slow: 200})

    started = System.monotonic_time(:millisecond)
    assert :ok = ObjectServer.await_init(swarm, :slow_obj)
    elapsed = System.monotonic_time(:millisecond) - started

    assert elapsed >= 150,
           "await_init returned before init could plausibly have finished (elapsed=#{elapsed}ms)"
  end

  test "await_init called AFTER resolution still returns the right outcome" do
    swarm = start(:bad_obj2, %{bad: true})

    # Let it resolve first.
    assert {:error, :bad_config} = ObjectServer.await_init(swarm, :bad_obj2)
    # A second, later caller must get the same answer via init_error —
    # not hang (nothing left to queue on) and not get a stale :ok.
    assert {:error, :bad_config} = ObjectServer.await_init(swarm, :bad_obj2)
  end

  test "multiple concurrent callers are all released with the correct outcome" do
    swarm = start(:slow_bad, %{slow: 100, bad: true})

    tasks =
      for _ <- 1..5 do
        Task.async(fn -> ObjectServer.await_init(swarm, :slow_bad) end)
      end

    results = Task.await_many(tasks, 2_000)

    assert results == List.duplicate({:error, :bad_config}, 5)
  end
end
