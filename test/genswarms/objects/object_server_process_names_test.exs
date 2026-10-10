defmodule Genswarms.Objects.ObjectServerProcessNamesTest do
  use ExUnit.Case, async: false

  alias Genswarms.Objects.ObjectServer

  test "process send and reply destinations do not create atoms" do
    for action <- ["send", "reply"] do
      name = "process_unknown_#{System.unique_integer([:positive])}"
      state = %ObjectServer{name: :process_object, swarm_name: "process-names", mode: :process}
      response = Jason.encode!(%{action: action, to: name, content: "x"})
      assert {:noreply, updated} = ObjectServer.handle_info({self(), {:data, response}}, state)
      assert updated.buffer == ""
      assert updated.state == :idle
      assert updated.message_count == 1
      assert_raise ArgumentError, fn -> String.to_existing_atom(name) end
    end
  end
end
