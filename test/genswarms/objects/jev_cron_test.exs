defmodule Genswarms.Objects.JevCronTest do
  @moduledoc """
  JevCron: config validation, the /v1/decisions request/response contract,
  action application (templated sends + memory), queueing/coalescing, budget,
  endpoint policy, and an end-to-end run inside a real swarm (ObjectServer +
  Router) against a fake decisions transport.

  async: false — mutates app env (:jev_transport) and process env vars.
  """
  use ExUnit.Case, async: false

  alias Genswarms.Objects.JevCron
  alias Genswarms.Objects.ObjectServer
  alias Genswarms.SwarmManager
  alias Genswarms.CLI.SwarmRegistry
  alias Genswarms.Config.SwarmConfig

  defmodule FakeTransport do
    # Reports every request to the test and answers with the configured fun.
    def post(url, headers, body, _timeout) do
      %{pid: pid, reply: reply} = Application.fetch_env!(:genswarms, :jev_fake)
      decoded = Jason.decode!(body)
      send(pid, {:jev_request, url, headers, decoded})
      reply.(decoded)
    end
  end

  @actions [
    %{id: "nothing", when: "Nothing actionable"},
    %{
      id: "wake",
      when: "Something needs the coder",
      send: %{to: :sink, text: "Wake ({{trigger}}, {{confidence}}): {{message}}"},
      remember: %{"last" => "{{message}}"}
    }
  ]

  defp base_config(extra \\ %{}) do
    Map.merge(%{instructions: "Should the coder act?", actions: @actions}, extra)
  end

  defp answer(probs, extra \\ %{}) do
    fn _body ->
      {:ok, 200,
       Jason.encode!(
         Map.merge(
           %{"answers" => %{"q" => %{"probabilities" => probs}}, "model" => "jev-1.13"},
           extra
         )
       )}
    end
  end

  setup do
    prev_env =
      Map.new(
        ~w(GENSWARMS_JEV_ENDPOINT GENSWARMS_JEV_API_KEY GENSWARMS_ALLOWED_ENDPOINTS),
        &{&1, System.get_env(&1)}
      )

    System.put_env("GENSWARMS_JEV_ENDPOINT", "https://router.example/")
    System.put_env("GENSWARMS_JEV_API_KEY", "test-key")
    System.delete_env("GENSWARMS_ALLOWED_ENDPOINTS")
    Application.put_env(:genswarms, :jev_transport, FakeTransport)

    Application.put_env(:genswarms, :jev_fake, %{
      pid: self(),
      reply: answer(%{"nothing" => 0.1, "wake" => 0.9})
    })

    on_exit(fn ->
      Application.delete_env(:genswarms, :jev_transport)
      Application.delete_env(:genswarms, :jev_fake)

      Enum.each(prev_env, fn
        {k, nil} -> System.delete_env(k)
        {k, v} -> System.put_env(k, v)
      end)
    end)

    :ok
  end

  defp set_reply(fun),
    do: Application.put_env(:genswarms, :jev_fake, %{pid: self(), reply: fun})

  # Drive the handler like ObjectServer does: deliver the spawned decision's
  # result back into handle_info.
  defp await_decision(state) do
    assert_receive {:jev_result, _pid, _result} = msg, 1_000
    JevCron.handle_info(msg, state)
  end

  describe "validate_config/1" do
    test "accepts atom- and string-keyed configs and normalizes every" do
      assert {:ok, cfg} = JevCron.validate_config(base_config(%{every: "5m"}))
      assert cfg.every == 300_000
      assert cfg.on_message
      assert Enum.map(cfg.actions, & &1.id) == ["nothing", "wake"]

      string_keyed = %{
        "every" => 2_000,
        "instructions" => "x",
        "actions" => [
          %{"id" => "a", "when" => "A"},
          %{
            "id" => "b",
            "when" => "B",
            "send" => [%{"to" => "sink", "text" => "hi"}],
            "forget" => ["k"]
          }
        ]
      }

      assert {:ok, cfg} = JevCron.validate_config(string_keyed)
      assert cfg.every == 2_000
      assert [%{send: [%{to: "sink", text: "hi"}], forget: ["k"]}] = tl(cfg.actions)
    end

    test "rejects bad configs" do
      for {cfg, reason} <- [
            {base_config(%{every: "1ms"}), {:invalid, :every, "1ms"}},
            {base_config(%{every: 10}), {:invalid, :every, 10}},
            {base_config(%{on_message: false}), :no_trigger},
            {Map.delete(base_config(), :instructions), {:invalid, :instructions, nil}},
            {base_config(%{fallback: "nope"}), {:unknown_fallback, "nope"}},
            {base_config(%{min_confidence: 2}), {:invalid, :min_confidence, 2}},
            {base_config(%{endpoint: "file:///etc/passwd"}),
             {:invalid, :endpoint, "file:///etc/passwd"}}
          ] do
        assert {:error, ^reason} = JevCron.validate_config(cfg)
      end

      assert {:error, {:invalid, :actions, _}} =
               JevCron.validate_config(base_config(%{actions: [hd(@actions)]}))

      assert {:error, {:duplicate_action_ids, ["nothing"]}} =
               JevCron.validate_config(base_config(%{actions: [hd(@actions), hd(@actions)]}))

      assert {:error, {:invalid, :action_id, "has space"}} =
               JevCron.validate_config(
                 base_config(%{actions: [%{id: "has space", when: "x"}, hd(@actions)]})
               )
    end

    test "SwarmConfig surfaces handler config errors at validation time" do
      config = %{
        name: "jev-validate",
        agents: [],
        objects: [%{name: :watch, handler: JevCron, config: base_config(%{on_message: false})}],
        topology: []
      }

      assert {:error, {:invalid_object_config, :watch, :no_trigger}} = SwarmConfig.parse(config)
    end
  end

  describe "endpoint policy" do
    test "env endpoint is used by default; no endpoint at all fails init" do
      assert {:ok, "https://router.example"} = JevCron.resolve_endpoint(nil)
      System.delete_env("GENSWARMS_JEV_ENDPOINT")
      assert {:error, :no_jev_endpoint} = JevCron.init(base_config())
    end

    test "a per-object endpoint must be the env endpoint or allowlisted" do
      assert {:error, {:endpoint_not_allowed, "evil.example"}} =
               JevCron.init(base_config(%{endpoint: "https://evil.example"}))

      System.put_env("GENSWARMS_ALLOWED_ENDPOINTS", "other.example")

      assert {:ok, %{endpoint: "https://other.example"}} =
               JevCron.init(base_config(%{endpoint: "https://other.example"}))
    end

    test "unknown string targets fail init without minting atoms" do
      bad = "jev_cron_no_such_node_#{System.unique_integer([:positive])}"
      actions = [hd(@actions), %{id: "x", when: "x", send: %{to: bad, text: "t"}}]
      assert {:error, {:unknown_target, ^bad}} = JevCron.init(base_config(%{actions: actions}))
    end
  end

  describe "decisions" do
    test "a message triggers one decision; the chosen action sends and remembers" do
      {:ok, state} = JevCron.init(base_config())
      {:noreply, state} = JevCron.handle_message(:tester, "CI is red", state)

      assert_receive {:jev_request, "https://router.example/v1/decisions", headers, body}
      assert {"authorization", "Bearer test-key"} in headers
      assert body["questions"]["q"]["type"] == "choice"

      assert body["questions"]["q"]["criteria"] == %{
               "nothing" => "Nothing actionable",
               "wake" => "Something needs the coder"
             }

      assert %{
               "trigger" => "message",
               "from" => "tester",
               "message" => "CI is red",
               "memory" => %{}
             } = body["state"]

      assert {:multi, [{:send, :sink, "Wake (message, 0.900): CI is red"}], state} =
               await_decision(state)

      assert state.memory == %{"last" => "CI is red"}
      assert [%{"action" => "wake", "confidence" => 0.9}] = state.recent
      assert state.inflight == nil

      # memory and history flow into the next decision's state
      {:noreply, _} = JevCron.handle_message(:tester, "again", state)
      assert_receive {:jev_request, _, _, body}
      assert body["state"]["memory"] == %{"last" => "CI is red"}
      assert [%{"action" => "wake"}] = body["state"]["recent"]
    end

    test "low confidence applies the fallback (or nothing when none)" do
      set_reply(answer(%{"nothing" => 0.45, "wake" => 0.55}))
      {:ok, state} = JevCron.init(base_config(%{min_confidence: 0.7, fallback: "nothing"}))
      {:noreply, state} = JevCron.handle_message(:tester, "hm", state)
      assert {:noreply, state} = await_decision(state)
      assert [%{"action" => "nothing"}] = state.recent

      {:ok, state} = JevCron.init(base_config(%{min_confidence: 0.7}))
      {:noreply, state} = JevCron.handle_message(:tester, "hm", state)
      assert {:noreply, state} = await_decision(state)
      assert [%{"action" => nil}] = state.recent
    end

    test "router errors and malformed answers act on nothing" do
      for reply <- [
            fn _ -> {:ok, 502, "bad gateway"} end,
            fn _ -> {:error, :timeout} end,
            fn _ -> {:ok, 200, ~s({"answers":{}})} end,
            answer(%{"unknown" => 1.0})
          ] do
        set_reply(reply)
        {:ok, state} = JevCron.init(base_config())
        {:noreply, state} = JevCron.handle_message(:tester, "x", state)
        assert {:noreply, state} = await_decision(state)
        assert state.recent == [] and state.memory == %{}
      end
    end

    test "messages queue behind an in-flight decision; timer ticks coalesce" do
      {:ok, state} = JevCron.init(base_config(%{every: 60_000}))
      {:noreply, state} = JevCron.handle_message(:a, "one", state)
      {:noreply, state} = JevCron.handle_message(:b, "two", state)
      {:noreply, state} = JevCron.handle_info(:jev_tick, state)
      assert :queue.len(state.queue) == 1

      assert_receive {:jev_request, _, _, %{"state" => %{"message" => "one"}}}
      {:multi, _, state} = await_decision(state)
      # the queued message started as soon as the first decision finished
      assert_receive {:jev_request, _, _, %{"state" => %{"message" => "two"}}}
      {:multi, _, state} = await_decision(state)
      refute_receive {:jev_request, _, _, _}, 100
      assert state.decisions == 2
    end

    test "the timer triggers decisions with trigger=timer" do
      {:ok, state} = JevCron.init(base_config(%{every: 1_000, on_message: false}))
      {:noreply, state} = JevCron.handle_message(:tester, "ignored", state)
      refute_receive {:jev_request, _, _, _}, 50

      {:noreply, state} = JevCron.handle_info(:jev_tick, state)
      assert_receive {:jev_request, _, _, %{"state" => %{"trigger" => "timer"} = s}}
      refute Map.has_key?(s, "message")
      assert {:multi, [{:send, :sink, "Wake (timer, 0.900): "}], _} = await_decision(state)
    end

    test "the daily budget stops further decisions" do
      set_reply(
        answer(%{"nothing" => 1.0, "wake" => 0.0}, %{"x_router" => %{"cost_usd" => 0.02}})
      )

      {:ok, state} = JevCron.init(base_config(%{budget_usd_per_day: 0.01}))
      {:noreply, state} = JevCron.handle_message(:tester, "1", state)
      {:noreply, state} = await_decision(state)
      {:noreply, _state} = JevCron.handle_message(:tester, "2", state)
      refute_receive {:jev_request, _, _, %{"state" => %{"message" => "2"}}}, 100
    end

    test "policy_ir and context pass through; the result envelope is unwrapped" do
      set_reply(fn _ ->
        {:ok, 200,
         Jason.encode!(%{
           "result" => %{"answers" => %{"q" => %{"probabilities" => %{"nothing" => 1}}}}
         })}
      end)

      policy = ["policy", ["family_eq", "jev-1.13"]]
      {:ok, state} = JevCron.init(base_config(%{policy_ir: policy, context: %{repo: "g"}}))
      {:noreply, state} = JevCron.handle_message(:tester, "x", state)

      assert_receive {:jev_request, _, _,
                      %{"policy_ir" => ^policy, "state" => %{"context" => %{"repo" => "g"}}}}

      assert {:noreply, %{recent: [%{"action" => "nothing"}]}} = await_decision(state)
    end
  end

  test "a jev-cron object round-trips through the IR unchanged" do
    config = %{
      name: "jev-ir",
      agents: [],
      objects: [
        %{name: :sink, handler: Genswarms.Test.SinkHandler, config: %{}},
        %{name: :watch, handler: JevCron, config: base_config(%{every: "5m"})}
      ],
      topology: [{:watch, :sink}]
    }

    {:ok, state} = Genswarms.IR.FromConfig.from_config(config)
    {:ok, back} = Genswarms.IR.ToConfig.swarm_config(state)
    watch = Enum.find(back.objects, &(to_string(&1.name) == "watch"))
    assert watch.handler == JevCron
    assert {:ok, _} = JevCron.validate_config(watch.config)
  end

  test "render/2 fills known placeholders and leaves unknown ones" do
    vars = %{"message" => "m", memory: %{"k" => "v", "n" => [1]}}

    assert JevCron.render("{{message}} {{ memory.k }} {{memory.n}} {{nope}}", vars) ==
             "m v [1] {{nope}}"
  end

  describe "in a running swarm" do
    test "run_at_start decides on boot and routes the action through the topology" do
      swarm = "jevcron-#{System.unique_integer([:positive])}"

      config = %{
        name: swarm,
        agents: [],
        objects: [
          %{name: :sink, handler: Genswarms.Test.SinkHandler, config: %{test_pid: self()}},
          %{
            name: :watch,
            handler: JevCron,
            config: base_config(%{run_at_start: true, every: "1h"})
          }
        ],
        topology: [{:watch, :sink}]
      }

      {:ok, ^swarm} = SwarmManager.start_from_config(config)
      SwarmRegistry.clear_overlay(swarm)

      on_exit(fn ->
        SwarmManager.stop(swarm)
        SwarmRegistry.clear_overlay(swarm)
      end)

      assert_receive {:jev_request, _, _, %{"state" => %{"trigger" => "timer"}}}, 3_000
      assert_receive {:sink_got, :watch, "Wake (timer, 0.900): "}, 3_000

      ObjectServer.deliver_message(swarm, :watch, :tester, "deploy failed")

      assert_receive {:jev_request, _, _,
                      %{"state" => %{"message" => "deploy failed", "memory" => %{"last" => ""}}}},
                     3_000

      assert_receive {:sink_got, :watch, "Wake (message, 0.900): deploy failed"}, 3_000
    end
  end
end
