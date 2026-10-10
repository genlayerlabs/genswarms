defmodule GenswarmsWeb.UntrustedNamesTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  alias GenswarmsWeb.{SwarmController, EventsController, SwarmChannel}

  setup context do
    previous = Application.fetch_env(:genswarms, :restricted_names)
    Application.put_env(:genswarms, :restricted_names, Map.get(context, :restricted, false))

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:genswarms, :restricted_names, value)
        :error -> Application.delete_env(:genswarms, :restricted_names)
      end
    end)

    :ok
  end

  defmodule Handler do
    @behaviour Genswarms.Objects.ObjectHandler
    def init(_), do: {:ok, %{}}
    def handle_message(_, _, state), do: {:noreply, state}
    def interface(), do: %{}
  end

  defp fresh, do: "http_unknown_#{System.unique_integer([:positive])}"
  defp uninterned(name), do: assert_raise(ArgumentError, fn -> String.to_existing_atom(name) end)

  test "unknown agent lookups return errors without creating atoms" do
    for action <- [:show_agent, :agent_logs, :agent_history, :agent_skills, :update_skill] do
      name = fresh()

      params = %{
        "swarm_name" => "missing",
        "agent_name" => name,
        "skill_name" => "x.md",
        "content" => "x"
      }

      conn = apply(SwarmController, action, [build_conn(), params])
      assert conn.status == 404
      uninterned(name)
    end
  end

  test "HTTP routing and topology do not create destination atoms" do
    name = fresh()

    conn =
      SwarmController.route_message(build_conn(), %{
        "name" => "missing",
        "from" => "alpha",
        "to" => name,
        "content" => "x"
      })

    assert conn.status == 400
    uninterned(name)
    name = fresh()

    conn =
      SwarmController.patch_topology(build_conn(), %{
        "swarm_name" => "missing",
        "add" => [["alpha", name]]
      })

    assert conn.status == 400
    uninterned(name)
  end

  @tag :restricted
  test "restricted HTTP agent and object creation reject names that have not been configured" do
    swarm = "restricted-add-#{System.unique_integer([:positive])}"

    {:ok, ^swarm} =
      Genswarms.SwarmManager.start_from_config(%{
        name: swarm,
        agents: [%{name: :worker, backend: :mock}]
      })

    on_exit(fn -> Genswarms.SwarmManager.stop(swarm) end)

    for {action, extra} <- [
          {:add_agent, %{"backend" => "mock"}},
          {:add_object, %{"handler" => inspect(Handler)}}
        ] do
      name = fresh()
      params = Map.merge(%{"swarm_name" => swarm, "name" => name}, extra)
      conn = apply(SwarmController, action, [build_conn(), params])
      assert conn.status == 400
      assert Jason.decode!(conn.resp_body)["error"] == "restricted_names"
      uninterned(name)
    end
  end

  @tag :restricted
  test "restricted HTTP config creation rejects fresh names before boot" do
    name = fresh()

    conn =
      SwarmController.create(build_conn(), %{
        "config" => %{name: "http-new", agents: [%{name: name, backend: :mock}]}
      })

    assert conn.status == 400
    uninterned(name)

    {:ok, state} =
      Genswarms.IR.FromConfig.from_config(%{
        name: "http-ir-new",
        agents: [%{name: name, backend: :mock}]
      })

    conn = SwarmController.create(build_conn(), %{"ir" => Genswarms.IR.State.to_map(state)})
    assert conn.status == 400
    uninterned(name)
  end

  @tag :restricted
  test "restricted HTTP scaling cannot introduce new derived names" do
    base = fresh()
    swarm = "http-scale-#{System.unique_integer([:positive])}"

    {:ok, ^swarm} =
      Genswarms.SwarmManager.start_from_config(%{
        name: swarm,
        agents: [%{name: base, backend: :mock}]
      })

    on_exit(fn -> Genswarms.SwarmManager.stop(swarm) end)

    conn =
      SwarmController.scale_agent_group(build_conn(), %{
        "swarm_name" => swarm,
        "base_name" => base,
        "count" => 1
      })

    assert conn.status == 400
    uninterned(base <> "_1")
  end

  test "HTTP creation, topology and scaling still work with existing names" do
    swarm = "http-existing-#{System.unique_integer([:positive])}"
    on_exit(fn -> Genswarms.SwarmManager.stop(swarm) end)

    conn =
      SwarmController.create(build_conn(), %{
        "config" => %{
          "name" => swarm,
          "agents" => [%{"name" => Atom.to_string(:http_allowed), "backend" => "mock"}]
        }
      })

    assert conn.status == 201

    conn =
      SwarmController.add_agent(build_conn(), %{
        "swarm_name" => swarm,
        "name" => Atom.to_string(:http_extra),
        "backend" => "mock"
      })

    assert conn.status == 201

    conn =
      SwarmController.add_object(build_conn(), %{
        "swarm_name" => swarm,
        "name" => Atom.to_string(:http_sink),
        "handler" => inspect(Handler)
      })

    assert conn.status == 201

    conn =
      SwarmController.patch_topology(build_conn(), %{
        "swarm_name" => swarm,
        "add" => [["http_allowed", "http_sink"]]
      })

    assert conn.status == 200

    conn =
      SwarmController.scale_agent_group(build_conn(), %{
        "swarm_name" => swarm,
        "base_name" => "http_allowed",
        "count" => 1
      })

    assert conn.status == 200
    assert Jason.decode!(conn.resp_body)["result"]["added"] == [Atom.to_string(:http_allowed_1)]
  end

  test "dynamic HTTP creation, additions and scaling accept fresh node names" do
    swarm = "http-dynamic-#{System.unique_integer([:positive])}"
    base = fresh()
    extra = fresh()
    object = fresh()
    on_exit(fn -> Genswarms.SwarmManager.stop(swarm) end)

    conn =
      SwarmController.create(build_conn(), %{
        "config" => %{"name" => swarm, "agents" => [%{"name" => base, "backend" => "mock"}]}
      })

    assert conn.status == 201

    conn =
      SwarmController.add_agent(build_conn(), %{
        "swarm_name" => swarm,
        "name" => extra,
        "backend" => "mock",
        "connections" => [base]
      })

    assert conn.status == 201

    conn =
      SwarmController.add_object(build_conn(), %{
        "swarm_name" => swarm,
        "name" => object,
        "handler" => inspect(Handler),
        "incoming" => [base]
      })

    assert conn.status == 201

    conn =
      SwarmController.scale_agent_group(build_conn(), %{
        "swarm_name" => swarm,
        "base_name" => base,
        "count" => 2
      })

    assert conn.status == 200
    assert Jason.decode!(conn.resp_body)["result"]["added"] == [base <> "_1", base <> "_2"]

    {:ok, config} = Genswarms.SwarmManager.get_full_config(swarm)

    for replica <- [base <> "_1", base <> "_2"] do
      assert {String.to_existing_atom(extra), String.to_existing_atom(replica)} in config.topology

      assert {String.to_existing_atom(replica), String.to_existing_atom(object)} in config.topology
    end
  end

  test "dynamic HTTP IR creation admits fresh names" do
    swarm = "http-dynamic-ir-#{System.unique_integer([:positive])}"
    name = fresh()
    on_exit(fn -> Genswarms.SwarmManager.stop(swarm) end)

    {:ok, state} =
      Genswarms.IR.FromConfig.from_config(%{
        name: swarm,
        agents: [%{name: name, backend: :mock}]
      })

    uninterned(name)
    conn = SwarmController.create(build_conn(), %{"ir" => Genswarms.IR.State.to_map(state)})
    assert conn.status == 201
    assert is_atom(String.to_existing_atom(name))
  end

  test "the global name budget rejects a scale batch and survives deletion" do
    alias Genswarms.Config.RequestNames
    previous = Application.fetch_env(:genswarms, :max_dynamic_names)
    Application.put_env(:genswarms, :max_dynamic_names, RequestNames.allocated() + 2)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:genswarms, :max_dynamic_names, value)
        :error -> Application.delete_env(:genswarms, :max_dynamic_names)
      end
    end)

    swarm = "http-budget-#{System.unique_integer([:positive])}"
    base = fresh()
    on_exit(fn -> Genswarms.SwarmManager.stop(swarm) end)

    params = %{
      "config" => %{"name" => swarm, "agents" => [%{"name" => base, "backend" => "mock"}]}
    }

    assert SwarmController.create(build_conn(), params).status == 201

    conn =
      SwarmController.scale_agent_group(build_conn(), %{
        "swarm_name" => swarm,
        "base_name" => base,
        "count" => 2
      })

    assert conn.status == 400
    assert Jason.decode!(conn.resp_body)["error"] == "dynamic_name_limit_reached"
    uninterned(base <> "_1")
    uninterned(base <> "_2")
    {:ok, config} = Genswarms.SwarmManager.get_full_config(swarm)
    assert length(config.agents) == 1

    extra = fresh()

    assert SwarmController.add_agent(build_conn(), %{
             "swarm_name" => swarm,
             "name" => extra,
             "backend" => "mock"
           }).status == 201

    assert SwarmController.remove_agent(build_conn(), %{
             "swarm_name" => swarm,
             "agent_name" => extra
           }).status == 200

    rejected = fresh()

    conn =
      SwarmController.add_agent(build_conn(), %{
        "swarm_name" => swarm,
        "name" => rejected,
        "backend" => "mock"
      })

    assert conn.status == 400
    assert Jason.decode!(conn.resp_body)["error"] == "dynamic_name_limit_reached"
    uninterned(rejected)

    # The same cap is shared by object creation and both swarm-creation forms.
    conn =
      SwarmController.add_object(build_conn(), %{
        "swarm_name" => swarm,
        "name" => rejected,
        "handler" => inspect(Handler)
      })

    assert conn.status == 400
    assert Jason.decode!(conn.resp_body)["error"] == "dynamic_name_limit_reached"

    new_config = %{
      name: swarm <> "-new",
      agents: [%{name: rejected, backend: :mock}],
      options: %{restricted_names: false, max_dynamic_names: 1_000_000}
    }

    {:ok, ir} = Genswarms.IR.FromConfig.from_config(new_config)

    for body <- [%{"config" => new_config}, %{"ir" => Genswarms.IR.State.to_map(ir)}] do
      conn = SwarmController.create(build_conn(), body)
      assert conn.status == 400
      assert Jason.decode!(conn.resp_body)["error"] == "dynamic_name_limit_reached"
    end

    uninterned(rejected)

    # Stopping/recreating a swarm neither refunds nor recharges existing names.
    assert {:ok, _} = Genswarms.SwarmManager.stop(swarm)
    used = RequestNames.allocated()
    assert SwarmController.create(build_conn(), params).status == 201
    assert RequestNames.allocated() == used
  end

  test "HTTP event filters remain strings and do not create atoms" do
    name = fresh()

    conn =
      EventsController.index(build_conn(), %{
        "agent" => name,
        "level" => name,
        "category" => name,
        "event_type" => name
      })

    body = Jason.decode!(conn.resp_body)
    assert body["events"] == []
    uninterned(name)
  end

  test "WebSocket log and event filters do not create atoms" do
    name = fresh()

    socket = %Phoenix.Socket{
      assigns: %{
        swarm_name: "missing",
        log_subscriptions: MapSet.new(),
        event_subscriptions: MapSet.new()
      }
    }

    assert {:reply, {:ok, %{recent_logs: []}}, socket} =
             SwarmChannel.handle_in("subscribe_logs", %{"agent" => name}, socket)

    assert {:reply, {:ok, %{recent_events: []}}, socket} =
             SwarmChannel.handle_in(
               "subscribe_events",
               %{"filters" => %{"level" => name, "category" => name, "event_type" => name}},
               socket
             )

    event = %{agent: :alpha, level: :info, category: :agent, event_type: :stdout}
    assert {:noreply, ^socket} = SwarmChannel.handle_info({:log_event, event}, socket)
    uninterned(name)
  end
end
