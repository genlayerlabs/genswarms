#!/bin/sh
# Rootless launcher for bwrap sandboxes (privilege_mode: :rootless).
#
# Replaces the systemd-run cgroup scope with plain-POSIX resource limits so a
# sandbox can start with ZERO elevated capabilities (no systemd PID 1, no
# delegated cgroups, no SYS_ADMIN):
#
#   - RLIMIT_AS (ulimit -v) caps the agent's address space — coarser than
#     cgroup MemoryMax (allocation fails instead of an OOM kill, and it is
#     per-process, not per-tree), but it bounds a runaway agent.
#   - nice(1) deprioritizes the whole sandbox — coarser than cgroup CPUWeight.
#
# Tree cleanup needs no cgroup either: the sandbox runs in its own PID
# namespace with --die-with-parent, so closing the port kills the whole tree.
#
# Usage: bwrap-rootless-launch.sh <rlimit_as_kb|0> <nice> -- <bwrap argv...>
# Both numbers are validated Elixir-side (integers only); everything after the
# literal -- is exec'd verbatim, never interpreted by this shell.
set -eu

as_kb="$1"
nice_n="$2"
shift 2
[ "${1:-}" = "--" ] && shift

if [ "$as_kb" -gt 0 ] 2>/dev/null; then
  ulimit -v "$as_kb" 2>/dev/null || true
fi

exec nice -n "$nice_n" "$@"
