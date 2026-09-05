defmodule Genswarms.IR.SerializationTest do
  use ExUnit.Case, async: true

  alias Genswarms.IR.{FromConfig, State, ToConfig}

  test "public JSON round-trips every parsed state field, including native refs and null opts" do
    doc = %{
      "v" => 1,
      "kind" => "swarm.state",
      "name" => "serialized",
      "phase" => "observed",
      "agents" => [
        %{
          "name" => "worker",
          "body" => %{
            "ref" => "swarmidx:fixture/body@1",
            "kind" => "data",
            "digest" => "sha256:aaaa",
            "opts" => nil
          },
          "model" => %{
            "policy" => %{
              "ref" => "swarmidx:fixture/policy@1",
              "kind" => "data",
              "digest" => "sha256:bbbb"
            }
          },
          "backend" => %{
            "ref" => "tmux",
            "client" => "codex",
            "image" => "fixture:code",
            "opts" => %{"runner" => "docker", "network" => "none"}
          },
          "overrides" => %{
            "endpoint" => "http://127.0.0.1:9999/v1",
            "request_extra" => %{"label" => "café🚀"}
          },
          "config" => %{"items" => [1, true, nil, "~literal"]}
        }
      ],
      "objects" => [
        %{
          "name" => "board",
          "handler" => %{
            "ref" => "swarmidx:fixture/board@1",
            "kind" => "code",
            "digest" => "sha256:cccc",
            "opts" => %{"path" => "/fixture/board", "mode" => "require"}
          },
          "config" => %{"capacity" => 8}
        }
      ],
      "topology" => [["worker", "board"], ["board", "worker"]],
      "options" => %{"nested" => %{"enabled" => true}}
    }

    assert {:ok, state} = State.parse(doc)
    encoded = state |> State.to_map() |> Jason.encode!()
    assert {:ok, ^state} = encoded |> Jason.decode!() |> State.parse()
    refute encoded =~ "\"scheme\""
  end

  test "provider and package loader configuration survives an actual JSON boundary" do
    handler = %{
      ref: "swarmidx:fixture/board@1",
      digest: "sha256:aaaa",
      path: "/fixture/board",
      mode: :require
    }

    provider = %{
      endpoint: "http://127.0.0.1:9999/v1",
      request_extra: %{"fixture" => [1, "~literal"]},
      compact_extra: ~s({"keep_recent":4})
    }

    config = %{
      name: "serialized",
      agents: [Map.merge(%{name: :worker, backend: :mock}, provider)],
      objects: [%{name: :board, handler: handler, config: %{"capacity" => 8}}],
      topology: [{:worker, :board}]
    }

    assert {:ok, state} = FromConfig.from_config(config)

    assert {:ok, restored} =
             state |> State.to_map() |> Jason.encode!() |> Jason.decode!() |> State.parse()

    assert Map.take(ToConfig.agent_spec(hd(restored.agents)), Map.keys(provider)) == provider
    assert ToConfig.object_spec(hd(restored.objects)).handler == handler
    assert restored == state
  end

  test "a default verify-mode package handler and string-keyed spec retain meaning" do
    handler = %{
      "ref" => "swarmidx:fixture/board@1",
      "digest" => "sha256:aaaa",
      "path" => "/fixture/board"
    }

    assert {:ok, state} =
             FromConfig.from_config(%{
               name: "s",
               agents: [],
               objects: [%{name: :board, handler: handler}]
             })

    assert ToConfig.object_spec(hd(state.objects)).handler.mode == :verify

    assert {:error, :invalid_handler_load_mode} =
             FromConfig.from_config(%{
               name: "s",
               agents: [],
               objects: [%{name: :board, handler: Map.put(handler, "mode", "unknown")}]
             })
  end

  test "non-JSON metadata is not silently serialized as a portable checkpoint" do
    assert {:ok, state} =
             FromConfig.from_config(%{name: "s", agents: [], options: %{callback: fn -> :ok end}})

    assert_raise Protocol.UndefinedError, fn -> state |> State.to_map() |> Jason.encode!() end
  end

  test "typed bind options survive native JSON and restore runtime tuple pairs" do
    opts = %{
      extra_ro_binds: [{"/fixture/source", "/fixture/target"}],
      extra_rw_binds: [{"/fixture/write", "/work"}]
    }

    assert {:ok, state} =
             FromConfig.from_config(%{
               name: "binds",
               agents: [%{name: :worker, backend: {:bwrap, opts}, config: opts}]
             })

    assert {:ok, restored} =
             state |> State.to_map() |> Jason.encode!() |> Jason.decode!() |> State.parse()

    spec = ToConfig.agent_spec(hd(restored.agents))
    assert spec.backend == {:bwrap, opts}
    assert spec.config == opts
  end
end
