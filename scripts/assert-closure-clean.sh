#!/usr/bin/env bash
# Assert a sandbox-base closure exposes ONLY the hardened baseline toolset.
#
# Allowlist, not denylist. A denylist ("fail if you see gcc/python/nix/...") is
# incomplete by construction: it passes any escape-enabling tool nobody thought
# to enumerate (go, rustc, zig, tcc, a package manager, ...) while reporting
# "clean". This check instead asserts that every RUNNABLE package in the closure
# is one of the expected baseline packages; anything else — a compiler, an
# interpreter, nix, or drift from a preset bump — fails, without enumerating the
# infinite set of dangerous tools.
#
# Only packages that expose executables matter: runtime shared libraries
# (split `-lib`/`-libgcc` outputs with no bin/, e.g. gcc-*-lib, libgcc) are not
# runnable and are ignored — that is why they need no special-casing here.
#
# Usage:
#   scripts/assert-closure-clean.sh /run/swarm/sandbox-base/base-hardened
set -euo pipefail
base="${1:?usage: assert-closure-clean.sh <sandbox-base-path-or-symlink>}"
store_path="$(readlink -f "$base")"

# Executable-bearing packages a hardened base may expose (the `base` preset
# minus nix). Matched by package family, version-independent. DERIVED from the
# built closure of `sandboxBase-base-hardened`; extend it in the SAME PR that
# intentionally gives a preset a new tool, so an accidental addition still trips.
allow='^(bash|bash-interactive|coreutils|curl|file|findutils|gawk|gnugrep|gnused|jq|krb5|less|ncurses|which|zstd|swarm-msg|szc-wrapper)(-[0-9]|$)'

# Names of closure packages that expose runnable files (bin/sbin/libexec).
# NB: `find | grep` would mis-report under `set -o pipefail` (find exits non-zero
# on any missing dir, which is the common case), so capture its output instead.
runnable_pkgs="$(
  for p in $(nix-store --query --requisites "$store_path"); do
    found="$(find "$p/bin" "$p/sbin" "$p/libexec" -maxdepth 1 -type f -executable -print -quit 2>/dev/null || true)"
    if [ -n "$found" ]; then
      basename "$p" | sed -E 's/^[a-z0-9]{32}-//'
    fi
  done | sort -u
)"

unexpected="$(printf '%s\n' "$runnable_pkgs" | grep -vE "$allow" || true)"
if [ -n "$unexpected" ]; then
  echo "UNEXPECTED runnable packages in closure of $store_path" >&2
  echo "(not on the hardened-baseline allowlist — a compiler, interpreter, nix, or drift):" >&2
  printf '%s\n' "$unexpected" | sed 's/^/  /' >&2
  exit 1
fi
echo "closure clean (only hardened-baseline tools): $store_path"
