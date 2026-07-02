defmodule Genswarms.Config.SwarmConfigHandlerRefTest do
  use ExUnit.Case, async: true

  alias Genswarms.Config.SwarmConfig

  @ref %{
    ref: "swarmidx:genlayerlabs/browse@0.1.1",
    digest: "sha256:e7c3289ae951b2feaa2140eeec88accdc182f2e30883f4dd6d63be37cdc74c7b",
    path: "vendor/swarmidx/genlayerlabs__browse@0.1.1",
    mode: :verify
  }

  test "a notarized handler ref map validates structurally" do
    config = %{name: "t", agents: [%{name: :seed, backend: :mock, skills: []}], topology: [], objects: [%{name: :browse, handler: @ref, config: %{}}]}
    assert {:ok, _} = SwarmConfig.parse(config)
  end

  test "a malformed handler ref map is rejected" do
    for bad <- [
          Map.delete(@ref, :digest),
          %{@ref | ref: "github:not-a-swarmidx-ref"},
          %{@ref | digest: "md5:nope"},
          %{@ref | path: ""}
        ] do
      config = %{name: "t", agents: [%{name: :seed, backend: :mock, skills: []}], topology: [], objects: [%{name: :x, handler: bad, config: %{}}]}
      assert {:error, _} = SwarmConfig.parse(config)
    end
  end
end
