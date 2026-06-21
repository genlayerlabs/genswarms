#!/usr/bin/env bash
# szc-wrapper-fifo.sh - FIFO-based protocol translator for Genswarms
#
# Usage: szc-wrapper-fifo.sh <agent_name> <subzeroclaw_path> [skills_dir]

AGENT_NAME="$1"
SZC_PATH="${2:-subzeroclaw}"
SKILLS_DIR="$3"

if [ -z "$AGENT_NAME" ] || [ -z "$SZC_PATH" ]; then
    echo '{"type":"error","content":"Usage: szc-wrapper-fifo.sh <agent_name> <subzeroclaw_path> [skills_dir]"}' >&2
    exit 1
fi

# Set environment
export SUBZEROCLAW_AGENT_NAME="$AGENT_NAME"
[ -n "$SKILLS_DIR" ] && export SUBZEROCLAW_SKILLS="$SKILLS_DIR"

# Create temp FIFOs
FIFO_DIR=$(mktemp -d)
INPUT_FIFO="$FIFO_DIR/input"
OUTPUT_FIFO="$FIFO_DIR/output"
ERR_FIFO="$FIFO_DIR/err"
mkfifo "$INPUT_FIFO" "$OUTPUT_FIFO" "$ERR_FIFO"

# Cleanup on exit
cleanup() {
    rm -rf "$FIFO_DIR"
    [ -n "$SZC_PID" ] && kill $SZC_PID 2>/dev/null
    [ -n "$INPUT_PID" ] && kill $INPUT_PID 2>/dev/null
    [ -n "$OUTPUT_PID" ] && kill $OUTPUT_PID 2>/dev/null
    [ -n "$ERR_PID" ] && kill $ERR_PID 2>/dev/null
}
trap cleanup EXIT

# Helper function: escape string for JSON
json_escape() {
    printf '%s' "$1" | jq -Rs '.'
}

# Process output from subzeroclaw
process_output() {
    while IFS= read -r line; do
        # Check for @agent: patterns
        if [[ "$line" =~ @([a-zA-Z_][a-zA-Z0-9_]*):\ *(.*) ]]; then
            target="${BASH_REMATCH[1]}"
            content="${BASH_REMATCH[2]}"
            if [ "$target" = "all" ]; then
                echo "{\"type\":\"broadcast\",\"content\":$(json_escape "$content")}"
            else
                echo "{\"type\":\"send\",\"to\":\"$target\",\"content\":$(json_escape "$content")}"
            fi
        fi
        # Always output the line as JSON
        echo "{\"type\":\"output\",\"content\":$(json_escape "$line")}"
    done < "$OUTPUT_FIFO"
}

# Process stderr from subzeroclaw: tag it as {"type":"log"} instead of merging
# it into stdout (the old 2>&1). Subzeroclaw's per-LLM-call banners and
# diagnostics go to stderr; keeping them OUT of the "output" stream is what
# lets the engine treat the turn's stdout as the model's actual text (reply
# auto-delivery, genswarms#53 G2) — while the content still reaches the engine
# (typed) for error detection and logging.
process_err() {
    while IFS= read -r line; do
        echo "{\"type\":\"log\",\"content\":$(json_escape "$line")}"
    done < "$ERR_FIFO"
}

# Relay orchestrator stdin (JSON) → subzeroclaw, NUL-framing each turn. Runs as a
# BACKGROUND job so the main shell is free to `wait` on subzeroclaw itself (below).
# Previously this loop ran in the main shell, which blocked here on orchestrator
# stdin and only reaped subzeroclaw AFTER the orchestrator closed the pipe — so a
# subzeroclaw that died mid-turn left this wrapper alive indefinitely, the engine's
# backend Port never saw {:exit_status}, and the agent wedged silently (stuck
# :working, queued tasks never dispatched). Matches the non-FIFO szc-wrapper.sh shape.
process_input() {
    # Opening the FIFO for writing blocks until subzeroclaw opens it for reading.
    exec 3>"$INPUT_FIFO"
    while IFS= read -r line; do
        msg_type=$(echo "$line" | jq -r '.type // empty' 2>/dev/null)
        # Frame each turn with a trailing NUL byte (printf '%s\0'), not a newline:
        # subzeroclaw reads a piped (non-tty) turn up to the NUL, so a multi-line
        # message stays ONE turn instead of fanning out into one turn per line. No
        # escaping — content passes verbatim. (See subzeroclaw read_turn().)
        case "$msg_type" in
            "task"|"message")
                from=$(echo "$line" | jq -r '.from // "orchestrator"')
                content=$(echo "$line" | jq -r '.content // ""')
                printf '%s\0' "[From $from] $content" >&3
                ;;
            "system")
                cmd=$(echo "$line" | jq -r '.command // ""')
                printf '%s\0' "/$cmd" >&3
                ;;
            *)
                # Pass through as-is
                printf '%s\0' "$line" >&3
                ;;
        esac
    done
    # Orchestrator closed stdin → close the write end so subzeroclaw reads EOF on
    # its stdin and exits cleanly; the main `wait` below then returns.
    exec 3>&-
}

# Start output/stderr processors in the background
process_output &
OUTPUT_PID=$!
process_err &
ERR_PID=$!

# Start subzeroclaw with FIFOs
"$SZC_PATH" < "$INPUT_FIFO" > "$OUTPUT_FIFO" 2> "$ERR_FIFO" &
SZC_PID=$!

# Relay orchestrator stdin in the background (see process_input above). Hand it the
# wrapper's OWN stdin via a saved fd: a backgrounded job's stdin otherwise defaults
# to /dev/null in a non-interactive shell, which would sever the orchestrator→agent
# relay — subzeroclaw would read immediate EOF and exit 0 without processing the
# turn (no reply). The explicit `<&4` redirect overrides that default.
exec 4<&0
process_input <&4 &
INPUT_PID=$!

# Wait on subzeroclaw itself. This returns the instant it exits OR dies — the real
# liveness edge. A crashed subzeroclaw now promptly ends the wrapper, so the engine's
# Port delivers {:exit_status} and the agent is stopped/recycled instead of wedging.
wait $SZC_PID 2>/dev/null
EXIT_STATUS=$?

# subzeroclaw is gone: stop relaying input and drain the output/stderr readers
# (they hit EOF once subzeroclaw closed those FIFOs — the final stderr lines are
# often the fatal error explaining the exit).
kill $INPUT_PID 2>/dev/null
wait $OUTPUT_PID 2>/dev/null
wait $ERR_PID 2>/dev/null

echo "{\"type\":\"exit\",\"status\":$EXIT_STATUS}"
exit $EXIT_STATUS
