#!/usr/bin/env bash
# Fail if a sandbox-base closure contains an escape-enabling tool (compiler,
# interpreter, or nix). Usage:
#   scripts/assert-closure-clean.sh /run/swarm/sandbox-base/base
set -euo pipefail
base="${1:?usage: assert-closure-clean.sh <sandbox-base-path-or-symlink>}"
store_path="$(readlink -f "$base")"
deny='(^|-)(gcc|clang|cc|ld|binutils|cc-wrapper|stdenv|nodejs|python3?|perl|ruby|nix|gdb)(-|$)'
# Runtime support libraries (libgcc, gcc-lib, libstdc++) are unavoidable in any
# closure and are NOT executables — exclude the split `-lib`/`-libgcc` outputs so
# only the actual compiler/interpreter packages trip the denylist.
allow='-(lib|libgcc|libcxx|libstdcxx)$'
hits="$(nix-store --query --requisites "$store_path" \
  | sed 's#^/nix/store/[a-z0-9]*-##' \
  | grep -Ei "$deny" \
  | grep -vEi -- "$allow" || true)"
if [ -n "$hits" ]; then
  echo "DENYLISTED tools in $store_path closure:" >&2
  echo "$hits" >&2
  exit 1
fi
echo "closure clean: $store_path"
