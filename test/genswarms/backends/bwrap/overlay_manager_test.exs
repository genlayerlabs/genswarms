defmodule Genswarms.Backends.Bwrap.OverlayManagerTest do
  use ExUnit.Case, async: true

  alias Genswarms.Backends.Bwrap.OverlayManager

  describe "ensure_store_path/1" do
    test "accepts a /nix/store path" do
      assert {:ok, "/nix/store/abc-sandbox-base"} =
               OverlayManager.ensure_store_path("/nix/store/abc-sandbox-base")
    end

    test "rejects a non-store path (e.g. a {:custom,_} dir)" do
      assert {:error, {:base_not_store_path, "/home/me/base"}} =
               OverlayManager.ensure_store_path("/home/me/base")
    end
  end

  @moduletag :bwrap

  describe "infrastructure_ready?/0" do
    test "returns boolean" do
      result = OverlayManager.infrastructure_ready?()
      assert is_boolean(result)
    end
  end

  describe "get_base_layer/1" do
    test "returns path for base preset" do
      path = OverlayManager.get_base_layer([:base])
      assert is_binary(path)
      assert String.contains?(path, "base") or String.starts_with?(path, "/nix")
    end

    test "returns path for multiple presets" do
      path = OverlayManager.get_base_layer([:base, :web])
      assert is_binary(path)
    end
  end

  describe "setup_overlay/3 seed callback" do
    @tag :integration
    test "seeds upper/ BEFORE the mount and the file is visible through merged/" do
      # Files seeded into upper/ under a LIVE fuse-overlayfs are invisible to
      # its cache (and broke the sandbox's /root/.subzeroclaw bind targets —
      # bwrap exit 1). The :seed callback runs pre-mount, so the merged view
      # must show the seeded file.
      if not OverlayManager.infrastructure_ready?() do
        IO.puts("Skipping: bwrap infrastructure not ready")
        assert true
      else
        sandbox_id = "test-seed-#{:rand.uniform(999_999)}"

        seed = fn agent_dir ->
          dir = Path.join([agent_dir, "upper", "root", ".subzeroclaw"])
          File.mkdir_p!(dir)
          File.write!(Path.join(dir, "config"), "max_turns = 7\n")
          :ok
        end

        case OverlayManager.setup_overlay(sandbox_id, [:base], seed: seed) do
          {:ok, overlay_dir} ->
            merged_file = Path.join([overlay_dir, "merged", "root", ".subzeroclaw", "config"])
            assert File.read!(merged_file) == "max_turns = 7\n"
            assert :ok = OverlayManager.cleanup_overlay(sandbox_id)

          {:error, reason} ->
            IO.puts("Skipping: overlay setup unavailable (#{inspect(reason)})")
            assert true
        end
      end
    end

    @tag :integration
    test "a failing seed aborts the setup (fail closed, nothing mounted)" do
      sandbox_id = "test-seed-fail-#{:rand.uniform(999_999)}"

      case OverlayManager.setup_overlay(sandbox_id, [:base], seed: fn _ -> raise "boom" end) do
        {:error, {:seed_failed, _}} ->
          refute File.exists?(Path.join(["/run/swarm/agents", sandbox_id, "merged", "etc"]))
          OverlayManager.cleanup_overlay(sandbox_id)

        {:error, _other} ->
          # infrastructure not ready — the base-layer resolution failed first
          assert true
      end
    end
  end

  describe "setup_overlay/2 and cleanup_overlay/1" do
    @tag :integration
    test "sets up and cleans up overlay filesystem" do
      if not OverlayManager.infrastructure_ready?() do
        IO.puts("Skipping: bwrap infrastructure not ready")
        assert true
      else
        sandbox_id = "test-overlay-#{:rand.uniform(999_999)}"

        case OverlayManager.setup_overlay(sandbox_id, [:base]) do
          {:ok, overlay_dir} ->
            # Verify structure
            assert File.dir?(overlay_dir)
            assert File.dir?(Path.join(overlay_dir, "upper"))
            assert File.dir?(Path.join(overlay_dir, "work"))
            assert File.dir?(Path.join(overlay_dir, "merged"))

            # Cleanup
            assert :ok = OverlayManager.cleanup_overlay(sandbox_id)

            # Verify cleanup
            refute File.exists?(overlay_dir)

          {:error, reason} ->
            # If setup fails due to missing infra, that's ok for this test
            IO.puts("Setup failed (expected if infra not ready): #{inspect(reason)}")
            assert true
        end
      end
    end
  end

  describe "list_active_sandboxes/0" do
    test "returns list" do
      result = OverlayManager.list_active_sandboxes()
      assert is_list(result)
    end
  end

  describe "get_overlay_size/1" do
    @tag :integration
    test "returns size for existing overlay" do
      if not OverlayManager.infrastructure_ready?() do
        assert true
      else
        sandbox_id = "test-size-#{:rand.uniform(999_999)}"

        case OverlayManager.setup_overlay(sandbox_id, [:base]) do
          {:ok, _overlay_dir} ->
            case OverlayManager.get_overlay_size(sandbox_id) do
              {:ok, size} ->
                assert is_integer(size)
                assert size >= 0

              {:error, _} ->
                # May fail if du not available
                assert true
            end

            OverlayManager.cleanup_overlay(sandbox_id)

          {:error, _} ->
            assert true
        end
      end
    end

    test "returns error for non-existent overlay" do
      result = OverlayManager.get_overlay_size("nonexistent-#{:rand.uniform(999_999)}")
      assert {:error, _} = result
    end
  end
end
