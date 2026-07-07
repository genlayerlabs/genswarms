defmodule Genswarms.E2E.TicTacToeE2ETest do
  @moduledoc """
  End-to-end over the `examples/tic-tac-toe` swarm — the engine's DETERMINISTIC
  spine, driven without an LLM.

  The value: an example is a running product. Booting it under mock agents and
  asserting on the object's state exercises the exact machinery where this
  week's bugs lived (SwarmManager.start_from_config → ObjectSupervisor →
  ObjectServer → Router topology gating → object lifecycle) with ZERO tokens,
  in milliseconds, in CI. Whether an LLM can *play* tic-tac-toe is a separate,
  paid, non-deterministic concern (a live smoke); the engine mechanics are not.

  Pattern (the template for the other examples): boot the real example config
  with `:mock` agents, push a scripted, rules-legal sequence of moves as if
  from the players, poll the object's handler state, assert the outcome.
  """
  use ExUnit.Case

  alias Genswarms.SwarmManager

  @example Path.expand("../../../examples/tic-tac-toe", __DIR__)

  setup_all do
    # The example loads its own object handler by convention; require it once.
    Code.require_file(Path.join(@example, "objects/game.ex"))
    :ok
  end

  setup do
    swarm = "ttt-e2e-#{System.unique_integer([:positive])}"

    config = %{
      name: swarm,
      # the example runs docker+LLM players; the ENGINE mechanics don't care —
      # mock players let the deterministic game object be driven from a test
      agents: [
        %{name: :player_x, backend: :mock},
        %{name: :player_o, backend: :mock}
      ],
      objects: [%{name: :game, handler: TicTacToe.Objects.Game, config: %{}}],
      topology: [
        {:player_x, :game},
        {:game, :player_x},
        {:player_o, :game},
        {:game, :player_o}
      ]
    }

    {:ok, ^swarm} = SwarmManager.start_from_config(config)
    on_exit(fn -> SwarmManager.stop(swarm) end)
    {:ok, swarm: swarm}
  end

  # The game object keeps its domain state as the GenServer's handler_state.
  defp game_state(swarm) do
    [{pid, _}] = Registry.lookup(Genswarms.AgentRegistry, {swarm, :game})
    :sys.get_state(pid).handler_state
  end

  defp board(rows), do: Jason.encode!(%{"board" => rows})

  # Push one player's move into the game object (as the Router would on a real
  # send) and block until the object has folded it in — move_count is the
  # monotonic progress signal, so the next move races nothing.
  defp move(swarm, from, rows, expect_count) do
    Genswarms.Objects.ObjectServer.deliver_message(swarm, :game, from, board(rows))
    wait_until(fn -> game_state(swarm).move_count >= expect_count end)
  end

  defp wait_until(fun, attempts \\ 200) do
    cond do
      fun.() -> :ok
      attempts > 0 -> Process.sleep(5); wait_until(fun, attempts - 1)
      true -> flunk("condition not met within timeout")
    end
  end

  test "a scripted legal game where X takes the top row ends with X the winner", %{swarm: swarm} do
    # initial state, before any move
    s0 = game_state(swarm)
    assert s0.turn == :player_x
    assert s0.move_count == 0
    refute s0.game_over

    # X . . / . . . / . . .
    move(swarm, :player_x, [["X", ".", "."], [".", ".", "."], [".", ".", "."]], 1)
    # X . . / O . . / . . .
    move(swarm, :player_o, [["X", ".", "."], ["O", ".", "."], [".", ".", "."]], 2)
    # X X . / O . . / . . .
    move(swarm, :player_x, [["X", "X", "."], ["O", ".", "."], [".", ".", "."]], 3)
    # X X . / O O . / . . .
    move(swarm, :player_o, [["X", "X", "."], ["O", "O", "."], [".", ".", "."]], 4)
    # X X X / O O . / . . .  → X wins row 0
    move(swarm, :player_x, [["X", "X", "X"], ["O", "O", "."], [".", ".", "."]], 5)

    final = game_state(swarm)
    assert final.game_over
    assert final.winner == :player_x
    assert final.move_count == 5
  end

  test "topology gating: the game only starts once, object is supervised", %{swarm: swarm} do
    # the object booted and is registered exactly once (a regression guard for
    # the ObjectSupervisor / registry bookkeeping we fixed in #78/#79)
    assert [{_pid, _}] = Registry.lookup(Genswarms.AgentRegistry, {swarm, :game})

    listed = Genswarms.Objects.ObjectSupervisor.list_objects(swarm)
    assert :game in Enum.map(listed, & &1.name)
  end

  test "an illegal move (not your turn) is rejected and state does not advance", %{swarm: swarm} do
    # O tries to move first — the object must refuse; move_count stays 0
    Genswarms.Objects.ObjectServer.deliver_message(
      swarm, :game, :player_o,
      board([["O", ".", "."], [".", ".", "."], [".", ".", "."]])
    )
    Process.sleep(50)

    s = game_state(swarm)
    assert s.move_count == 0
    assert s.turn == :player_x
    refute s.game_over
  end
end
