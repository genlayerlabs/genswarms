# Bubblewrap sandbox environment builder for Genswarms agents
#
# Reuses the same tool presets as Docker containers but builds
# a directory structure suitable for bwrap bind-mounts.
#
# Usage:
#   nix build .#sandboxBase-base
#   nix build .#sandboxBase-web
#   ln -sf $(readlink result) /run/swarm/sandbox-base/base

{ pkgs, toolPresets }:

let
  # Build a sandbox environment using the same approach as containers.
  # Downstream projects can pass extraPackages to add domain-specific tools.
  mkSandboxBase = { name, presets, extraPackages ? [], includeNix ? true }:
    let
      # Resolve presets to actual packages (same as container.nix)
      presetPackages = builtins.concatLists (
        map (preset: toolPresets.${preset} or []) presets
      );

      # Core packages always included (same as container.nix). `nix` is included by
      # default (for `nix-shell -p ...` runtime installs); set `includeNix = false`
      # to drop it, denying an untrusted agent a runtime tool summoner.
      corePackages = with pkgs; [
        bashInteractive
        coreutils
        cacert
      ] ++ (if includeNix then [ nix ] else []);

      # Create the szc-wrapper script (bash version for sandbox use)
      wrapperScript = pkgs.writeShellScriptBin "szc-wrapper" ''
        #!/usr/bin/env bash
        # Protocol wrapper for subzeroclaw in bwrap sandbox
        AGENT_NAME="$1"
        SZC_PATH="''${2:-subzeroclaw}"
        SKILLS_DIR="$3"

        export SUBZEROCLAW_AGENT_NAME="$AGENT_NAME"
        [ -n "$SKILLS_DIR" ] && export SUBZEROCLAW_SKILLS="$SKILLS_DIR"

        # Run subzeroclaw
        exec "$SZC_PATH"
      '';

      # swarm-msg CLI for inter-agent messaging
      swarmMsg = pkgs.writeShellScriptBin "swarm-msg" (builtins.readFile ../swarm-msg);

      allPackages = corePackages ++ presetPackages ++ extraPackages ++ [
        wrapperScript
        swarmMsg
      ];

    in pkgs.buildEnv {
      name = "sandbox-${name}";
      paths = allPackages;

      # Create bin symlinks at top level for easy PATH setup
      pathsToLink = [ "/bin" "/lib" "/share" "/etc" ];
    };

in {
  # Pre-built sandbox environments (matching container.nix presets)
  base = mkSandboxBase { name = "base"; presets = [ "base" ]; };

  # Hardened base: identical to `base` but with `nix` dropped from the closure, so an
  # untrusted agent cannot summon tools at runtime. Verify with scripts/assert-closure-clean.sh.
  base-hardened = mkSandboxBase { name = "base-hardened"; presets = [ "base" ]; includeNix = false; };
  web = mkSandboxBase { name = "web"; presets = [ "base" "web" ]; };
  code = mkSandboxBase { name = "code"; presets = [ "base" "code" ]; };
  data = mkSandboxBase { name = "data"; presets = [ "base" "data" ]; };
  python = mkSandboxBase { name = "python"; presets = [ "base" "python" "data" ]; };
  node = mkSandboxBase { name = "node"; presets = [ "base" "node" "web" ]; };
  full = mkSandboxBase { name = "full"; presets = [ "base" "web" "code" "data" "python" "node" ]; };
  devops = mkSandboxBase { name = "devops"; presets = [ "base" "code" "containers" "cloud" ]; };

  # Export builder for custom combinations
  inherit mkSandboxBase;
}
