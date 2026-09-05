#!/bin/bash
# Offline transport fixture: consume the runtime's NUL-framed turns, never call a provider.
while IFS= read -r -d '' turn; do
    printf '%s\n' "$turn"
done
