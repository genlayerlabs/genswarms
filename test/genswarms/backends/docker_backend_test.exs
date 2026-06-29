defmodule Genswarms.Backends.DockerBackendTest do
  use ExUnit.Case, async: true

  alias Genswarms.Backends.DockerBackend

  describe "build_docker_args/8 (command-injection hardening)" do
    test "returns a flat argv list of strings (no shell string)" do
      args =
        DockerBackend.build_docker_args("szc-s-a", "img:tag", nil, nil, nil, nil, "agentA", %{})

      assert is_list(args)
      assert Enum.all?(args, &is_binary/1)
      # container name is a single discrete element right after --name
      assert ["--name", "szc-s-a" | _] = drop_until(args, "--name")
    end

    test "env values are literal argv elements; a malicious model cannot split argv or inject" do
      evil = "x'; touch /tmp/pwned #"
      args = DockerBackend.build_docker_args("c", "i", nil, "sk-secret", evil, nil, "a", %{})

      # the model now rides inside SUBZEROCLAW_REQUEST_EXTRA as JSON, still ONE
      # argv element, verbatim (quote preserved, not interpreted)
      assert ~s(SUBZEROCLAW_REQUEST_EXTRA={"model":"#{evil}"}) in args
      assert "SUBZEROCLAW_API_KEY=sk-secret" in args
      # it did not break out into separate tokens
      refute "touch" in args
      refute "/tmp/pwned" in args
    end

    test "default container command runs the FIFO protocol wrapper inside the container" do
      args = DockerBackend.build_docker_args("c", "i", nil, nil, nil, nil, "a", %{})
      assert Enum.any?(args, &String.ends_with?(&1, ":/src/genswarms-priv:ro"))
      assert ["sh", "-c", script, "szc-wrapper", "a"] = Enum.take(args, -5)
      assert script =~ "/src/genswarms-priv/szc-wrapper-fifo.sh \"$1\""
      assert script =~ "/root/build/subzeroclaw /skills"
      refute script =~ " a "
    end

    test "a string :cmd is wrapped as sh -c (container shell); a list :cmd is used as argv" do
      str =
        DockerBackend.build_docker_args("c", "i", nil, nil, nil, nil, "a", %{cmd: "python app.py"})

      assert Enum.take(str, -3) == ["sh", "-c", "python app.py"]

      lst =
        DockerBackend.build_docker_args("c", "i", nil, nil, nil, nil, "a", %{
          cmd: ["python", "app.py"]
        })

      assert Enum.take(lst, -2) == ["python", "app.py"]
    end
  end

  describe "network: :isolated" do
    test "drops the container network (--network none, never a net named 'isolated')" do
      args = isolated_args()
      assert ["--network", "none" | _] = drop_until(args, "--network")
      refute "isolated" in args
    end

    test "routes the agent's curl through the egress socket via CURL_HOME" do
      assert "CURL_HOME=/workspace" in isolated_args()
    end

    test "mounts the per-agent workspace at /workspace so .curlrc is visible" do
      assert "/tmp/szc-ws/agent:/workspace" in isolated_args()
    end

    test "mounts the per-agent egress volume (sidecar socket lives there)" do
      # container_name in build/1 is "szc-test-agent"
      assert "szc-egress-szc-test-agent:/egress" in isolated_args()
    end
  end

  describe "default (network: :open)" do
    test "no forced network, no CURL_HOME, no egress volume" do
      args = build(%{})
      refute "none" in args
      refute "CURL_HOME=/workspace" in args
      refute Enum.any?(args, &String.contains?(&1, "/egress"))
    end

    test "an explicit docker network name still passes through" do
      assert ["--network", "my-net" | _] = drop_until(build(%{network: "my-net"}), "--network")
    end
  end

  describe "determine_image/1" do
    test "matches full and devops preset combinations after sorting" do
      assert DockerBackend.determine_image(%{
               presets: [:base, :web, :code, :data, :python, :node]
             }) == "szc-agent-full:latest"

      assert DockerBackend.determine_image(%{
               presets: [:base, :code, :containers, :cloud]
             }) == "szc-agent-devops:latest"
    end
  end

  describe "resource caps (build_resource_args passthrough)" do
    test "no caps configured emits none of the resource flags" do
      args = build(%{})
      refute "--memory" in args
      refute "--memory-swap" in args
      refute "--cpus" in args
      refute "--pids-limit" in args
    end

    test "memory_limit emits --memory with its value" do
      assert ["--memory", "2g" | _] = drop_until(build(%{memory_limit: "2g"}), "--memory")
    end

    test "memory_swap emits --memory-swap (hard RAM ceiling, no ~2x swap escape)" do
      assert ["--memory-swap", "2g" | _] =
               drop_until(build(%{memory_swap: "2g"}), "--memory-swap")
    end

    test "cpu_limit emits --cpus with its value" do
      assert ["--cpus", "2" | _] = drop_until(build(%{cpu_limit: "2"}), "--cpus")
    end

    test "pids_limit emits --pids-limit, stringified (fork-bomb guard)" do
      assert ["--pids-limit", "512" | _] = drop_until(build(%{pids_limit: 512}), "--pids-limit")
    end
  end

  # Builds the docker run argv for the agent container.
  defp build(config) do
    DockerBackend.build_docker_args(
      "szc-test-agent",
      "szc-agent-base:latest",
      # skills_dir nil keeps the builder free of filesystem side effects
      nil,
      "test-key",
      "test-model",
      config[:endpoint],
      "agent",
      config
    )
  end

  defp isolated_args, do: build(%{network: :isolated, workspace: "/tmp/szc-ws/agent"})

  # return the list starting at the first occurrence of `val`
  defp drop_until([val | _] = rest, val), do: rest
  defp drop_until([_ | t], val), do: drop_until(t, val)
  defp drop_until([], _val), do: []
end
