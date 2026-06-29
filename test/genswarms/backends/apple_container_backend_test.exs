defmodule Genswarms.Backends.AppleContainerBackendTest do
  use ExUnit.Case, async: true

  alias Genswarms.Backends.AppleContainerBackend

  describe "backend_type/0" do
    test "returns :apple_container" do
      assert AppleContainerBackend.backend_type() == :apple_container
    end
  end

  describe "build_apple_container_args/8 (command-injection hardening)" do
    test "returns a flat argv list of strings (no host shell string)" do
      assert {:ok, args} =
               AppleContainerBackend.build_apple_container_args(
                 "szc-s-a",
                 "img:tag",
                 nil,
                 nil,
                 nil,
                 nil,
                 "agentA",
                 %{}
               )

      assert is_list(args)
      assert Enum.all?(args, &is_binary/1)
      assert ["--name", "szc-s-a" | _] = drop_until(args, "--name")
    end

    test "env values are literal argv elements; a malicious model cannot split argv or inject" do
      evil = "x'; touch /tmp/pwned #"

      assert {:ok, args} =
               AppleContainerBackend.build_apple_container_args(
                 "c",
                 "i",
                 nil,
                 "sk-secret",
                 evil,
                 nil,
                 "a",
                 %{}
               )

      assert ~s(SUBZEROCLAW_REQUEST_EXTRA={"model":"#{evil}"}) in args
      assert "SUBZEROCLAW_API_KEY=sk-secret" in args
      refute "touch" in args
      refute "/tmp/pwned" in args
    end

    test "default container command is argv ['sh','-c',script] inside the container" do
      assert {:ok, args} =
               AppleContainerBackend.build_apple_container_args(
                 "c",
                 "i",
                 nil,
                 nil,
                 nil,
                 nil,
                 "a",
                 %{}
               )

      assert ["sh", "-c", script] = Enum.take(args, -3)
      assert script =~ "subzeroclaw"
    end

    test "a string :cmd is wrapped as sh -c; a list :cmd is used as argv" do
      assert {:ok, str} =
               AppleContainerBackend.build_apple_container_args(
                 "c",
                 "i",
                 nil,
                 nil,
                 nil,
                 nil,
                 "a",
                 %{cmd: "python app.py"}
               )

      assert Enum.take(str, -3) == ["sh", "-c", "python app.py"]

      assert {:ok, lst} =
               AppleContainerBackend.build_apple_container_args(
                 "c",
                 "i",
                 nil,
                 nil,
                 nil,
                 nil,
                 "a",
                 %{cmd: ["python", "app.py"]}
               )

      assert Enum.take(lst, -2) == ["python", "app.py"]
    end
  end

  describe "network options" do
    test "network: :isolated fails closed" do
      assert {:error, {:unsupported_network, :isolated}} =
               AppleContainerBackend.build_apple_container_args(
                 "c",
                 "i",
                 nil,
                 nil,
                 nil,
                 nil,
                 "a",
                 %{network: :isolated}
               )
    end

    test "an explicit Apple container network name passes through" do
      assert {:ok, args} = build(%{network: "my-net"})
      assert ["--network", "my-net" | _] = drop_until(args, "--network")
    end
  end

  describe "determine_image/1" do
    test "uses explicit image before container_name" do
      assert AppleContainerBackend.determine_image(%{
               image: "explicit:latest",
               container_name: "name-image:latest"
             }) == "explicit:latest"
    end

    test "uses container_name as the image candidate for bare :apple_container configs" do
      assert AppleContainerBackend.determine_image(%{container_name: "szc-agent-code:latest"}) ==
               "szc-agent-code:latest"
    end

    test "matches full and devops preset combinations after sorting" do
      assert AppleContainerBackend.determine_image(%{
               presets: [:base, :web, :code, :data, :python, :node]
             }) == "szc-agent-full:latest"

      assert AppleContainerBackend.determine_image(%{
               presets: [:base, :code, :containers, :cloud]
             }) == "szc-agent-devops:latest"
    end
  end

  describe "resource caps" do
    test "memory_limit emits --memory with its value" do
      assert {:ok, args} = build(%{memory_limit: "2g"})
      assert ["--memory", "2g" | _] = drop_until(args, "--memory")
    end

    test "cpu_limit emits --cpus with its value" do
      assert {:ok, args} = build(%{cpu_limit: 2})
      assert ["--cpus", "2" | _] = drop_until(args, "--cpus")
    end

    test "Docker-only limits are not translated to fake Apple container flags" do
      assert {:ok, args} = build(%{memory_swap: "2g", pids_limit: 512})
      refute "--memory-swap" in args
      refute "--pids-limit" in args
    end
  end

  describe "platform-gated integration" do
    @tag :integration
    test "starts and stops a simple container only when Apple container is ready" do
      cond do
        not AppleContainerBackend.system_ready?() ->
          IO.puts("Skipping: Apple container service is not ready")

        not AppleContainerBackend.image_exists?("alpine:latest") ->
          IO.puts("Skipping: alpine:latest is not loaded in Apple container")

        true ->
          name = "szc-test-apple-#{System.unique_integer([:positive])}"

          assert {:ok, ref} =
                   AppleContainerBackend.start("agent", %{
                     swarm_name: "test",
                     container_name: name,
                     image: "alpine:latest",
                     cmd: ["sh", "-c", "while read line; do echo $line; done"]
                   })

          assert :ok = AppleContainerBackend.stop(ref)
      end
    end
  end

  defp build(config) do
    AppleContainerBackend.build_apple_container_args(
      "szc-test-agent",
      "szc-agent-base:latest",
      nil,
      "test-key",
      "test-model",
      config[:endpoint],
      "agent",
      config
    )
  end

  defp drop_until([val | _] = rest, val), do: rest
  defp drop_until([_ | t], val), do: drop_until(t, val)
  defp drop_until([], _val), do: []
end
