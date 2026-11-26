#!/usr/bin/env bash
# One short, self-contained verification job, sized to fit a small machine in
# under ten minutes. Many of these run in parallel with different seeds/sizes.
#
#   verify-shard.sh props <test file name> <seconds per property> <seed>
#   verify-shard.sh tla <daemons> <tasks> <bad tasks> <faults> <safe|live> <check|sim> <seconds> [seed]
#
# Always ends with one line:  SHARD_RESULT status=<pass|fail|timeout|error> ...
set -uo pipefail
cd "$(dirname "$0")/.."
log="$(mktemp)"
finish() { echo "SHARD_RESULT status=$1 job=\"$job\" $2"; exit 0; }

job="$*"
case "${1:-}" in
  props)
    file="test/property/$2"; seconds="$3"; seed="$4"
    mix deps.get >"$log" 2>&1 || { tail -20 "$log"; finish error "step=deps"; }
    PROPERTY_SECONDS="$seconds" MIX_ENV=test mix test "$file" --seed "$seed" >"$log" 2>&1
    code=$?
    grep -vE '^\s*$|\[(warning|info|error|debug)\]' "$log" | tail -60
    summary="$(grep -E '^[0-9]+ propert' "$log" | tail -1)"
    [ $code -eq 0 ] && finish pass "summary=\"$summary\"" || finish fail "summary=\"$summary\""
    ;;
  tla)
    daemons="$2"; tasks="$3"; bad="$4"; faults="$5"; kind="$6"; mode="$7"; seconds="$8"; seed="${9:-1}"
    jar="${TLA_JAR:-${XDG_CACHE_HOME:-$HOME/.cache}/tla2tools-1.8.0.jar}"
    if [ ! -f "$jar" ]; then
      mkdir -p "$(dirname "$jar")"
      curl -fsSL -o "$jar" https://github.com/tlaplus/tlaplus/releases/download/v1.8.0/tla2tools.jar ||
        finish error "step=download"
    fi
    set_of() { local out="" i; for i in $(seq 1 "$2"); do out="$out${out:+, }$1$i"; done; echo "{$out}"; }
    bad_set() { local out="" i; for i in $(seq $((tasks - bad + 1)) "$tasks"); do out="$out${out:+, }t$i"; done; echo "{$out}"; }
    work="$(mktemp -d)"; cp verification/tla/SwarmDaemon.tla "$work/"
    {
      echo "CONSTANTS"
      echo "  Daemons = $(set_of d "$daemons")"
      echo "  Tasks = $(set_of t "$tasks")"
      echo "  BadTasks = $(bad_set)"
      echo "  Fixed = TRUE"
      echo "  MaxFaults = $faults"
      echo "  None = None"
      echo "SPECIFICATION Spec"
      echo "INVARIANTS TypeOK OneLiveDaemon AtMostOnce RowTracksDaemon"
      [ "$kind" = live ] && echo "PROPERTY EveryTaskResolved"
    } >"$work/Shard.cfg"
    extra=()
    [ "$mode" = sim ] && extra=(-simulate -depth 200 -seed "$seed")
    (cd "$work" && timeout "$seconds" java -XX:+UseParallelGC -Xmx5g -cp "$jar" tlc2.TLC \
      -deadlock -workers auto -metadir "$work/states" -config Shard.cfg "${extra[@]}" SwarmDaemon.tla) >"$log" 2>&1
    code=$?
    grep -E 'Error|violated|No error|states generated|distinct states found, 0|Progress' "$log" | tail -8
    states="$(grep -oE '[0-9,]+ states (generated|checked)' "$log" | tail -1)"
    if grep -qE '^Error|is violated' "$log"; then
      sed -n '/^Error/,$p' "$log" | head -80
      finish fail "states=\"$states\""
    elif grep -q 'No error has been found' "$log"; then finish pass "states=\"$states\""
    elif [ $code -eq 124 ] && [ "$mode" = sim ]; then finish pass "states=\"$states\" note=time-boxed-walk"
    elif [ $code -eq 124 ]; then finish timeout "states=\"$states\""
    else tail -20 "$log"; finish error "exit=$code"
    fi
    ;;
  *) echo "usage: see header of $0" >&2; exit 2 ;;
esac
