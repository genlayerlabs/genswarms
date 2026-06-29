#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "Usage: bwrap-seccomp-wrapper.sh <profile.bpf> <bwrap> [bwrap args...]" >&2
  exit 64
fi

profile="$1"
shift
bwrap="$1"
shift

exec 3<"$profile"
exec "$bwrap" --seccomp 3 "$@"
