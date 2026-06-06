defmodule GenswarmsWeb.ObjectHandlerValidationTest do
  @moduledoc """
  POST /api/swarms/:swarm/objects must only accept a handler that is a real
  module implementing the ObjectHandler behaviour. An arbitrary or nonexistent
  module name must be rejected (and must not mint an atom).
  """
  use ExUnit.Case, async: false

  import Phoenix.ConnTest

  alias GenswarmsWeb.SwarmController

  # A real handler implementing the ObjectHandler callbacks.
  defmodule GoodHandler do
    @behaviour Genswarms.Objects.ObjectHandler
    @impl true
    def init(_config), do: {:ok, %{}}
    @impl true
    def handle_message(_from, _content, state), do: {:noreply, state}
    @impl true
    def interface, do: %{}
  end

  defp add_object(handler) do
    params = %{"swarm_name" => "__no_such_swarm__", "name" => "obj", "handler" => handler}
    build_conn() |> SwarmController.add_object(params)
  end

  defp error(conn), do: Jason.decode!(conn.resp_body)["error"]

  test "a valid ObjectHandler module passes handler validation" do
    conn = add_object("GenswarmsWeb.ObjectHandlerValidationTest.GoodHandler")

    # It gets past the handler check; the only failure is the missing swarm.
    assert conn.status == 400
    assert error(conn) != "Invalid or missing object handler"
    assert error(conn) =~ "swarm_not_found"
  end

  test "a nonexistent module is rejected" do
    conn = add_object("Totally.Bogus.Module.That.Does.Not.Exist")
    assert conn.status == 400
    assert error(conn) == "Invalid or missing object handler"
  end

  test "an existing module that is not an ObjectHandler is rejected" do
    # File exists but does not implement the ObjectHandler callbacks.
    conn = add_object("File")
    assert conn.status == 400
    assert error(conn) == "Invalid or missing object handler"
  end

  test "a missing handler is rejected" do
    conn =
      build_conn()
      |> SwarmController.add_object(%{"swarm_name" => "s", "name" => "obj"})

    assert conn.status == 400
    assert error(conn) == "Invalid or missing object handler"
  end

  test "rejecting nonexistent handler names mints no atoms" do
    # Warm up so one-off lazy init isn't counted.
    for i <- 1..10, do: add_object("Bogus.Warmup.Module#{i}.X")

    before = :erlang.system_info(:atom_count)

    for i <- 1..300 do
      add_object("Bogus.Handler.Module.Number#{i}.Does.Not.Exist")
    end

    after_count = :erlang.system_info(:atom_count)
    assert after_count == before, "minted #{after_count - before} atoms resolving handlers"
  end
end
