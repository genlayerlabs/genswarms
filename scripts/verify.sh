#!/usr/bin/env bash
# Long verification run: TLA+ model checking and property tests.
#
#   scripts/verify.sh            # both
#   scripts/verify.sh tla        # models only (needs java)
#   scripts/verify.sh props      # property tests only (needs mix, or docker)
#
# Knobs: PROPERTY_RUNS (default 200000), TLC_WORKERS (default auto),
#        TLC_HEAP (e.g. 64g), TLA_CONFIGS (default "Fixed FixedLarge").
set -euo pipefail
cd "$(dirname "$0")/.."

PROPERTY_RUNS="${PROPERTY_RUNS:-200000}"
TLA_JAR="${TLA_JAR:-${XDG_CACHE_HOME:-$HOME/.cache}/tla2tools-1.8.0.jar}"

tla() {
  if [ ! -f "$TLA_JAR" ]; then
    mkdir -p "$(dirname "$TLA_JAR")"
    curl -fsSL -o "$TLA_JAR" \
      https://github.com/tlaplus/tlaplus/releases/download/v1.8.0/tla2tools.jar
  fi

  local failed=0
  for config in ${TLA_CONFIGS:-Fixed FixedLarge}; do
    echo "== TLC: $config"
    # `tla && props` runs this function with errexit off, so track failure here.
    (cd verification/tla &&
      java -XX:+UseParallelGC ${TLC_HEAP:+-Xmx$TLC_HEAP} -cp "$TLA_JAR" tlc2.TLC \
        -deadlock -workers "${TLC_WORKERS:-auto}" -metadir "$(mktemp -d)" \
        -config "$config.cfg" SwarmDaemon.tla) || failed=1
  done
  return "$failed"
}

props() {
  echo "== property tests: $PROPERTY_RUNS runs each"
  if command -v mix >/dev/null; then
    mix deps.get
    PROPERTY_RUNS="$PROPERTY_RUNS" MIX_ENV=test mix test test/property
  else
    # No Elixir on the host: build and test in a throwaway container copy.
    docker run --rm -v "$PWD":/src:ro -e PROPERTY_RUNS="$PROPERTY_RUNS" -e MIX_ENV=test \
      elixir:1.18 sh -c '
        mkdir /work && cd /src &&
        tar cf - --exclude=_build --exclude=deps --exclude=.git . | tar xf - -C /work &&
        cd /work && mix local.hex --force && mix local.rebar --force &&
        mix deps.get && mix test test/property'
  fi
}

case "${1:-all}" in
  tla) tla ;;
  props) props ;;
  all) tla && props ;;
  *) echo "usage: $0 [tla|props|all]" >&2 && exit 2 ;;
esac
