#!/usr/bin/env bash
# szc-wrapper-simple.sh - Simplified protocol translator (no jq required)
#
# Usage: szc-wrapper-simple.sh <agent_name> <subzeroclaw_path> [skills_dir]
#
# This wrapper translates between the orchestrator and subzeroclaw without
# requiring jq. It uses basic bash string manipulation for JSON parsing.

AGENT_NAME="$1"
SZC_PATH="${2:-subzeroclaw}"
SKILLS_DIR="$3"

if [ -z "$AGENT_NAME" ] || [ -z "$SZC_PATH" ]; then
    echo '{"type":"error","content":"Usage: szc-wrapper-simple.sh <agent_name> <subzeroclaw_path> [skills_dir]"}' >&2
    exit 1
fi

# Set environment
export SUBZEROCLAW_AGENT_NAME="$AGENT_NAME"
[ -n "$SKILLS_DIR" ] && export SUBZEROCLAW_SKILLS="$SKILLS_DIR"

# Create a temp file for communication
STDIN_FIFO=$(mktemp -u)
mkfifo "$STDIN_FIFO"

cleanup() {
    rm -f "$STDIN_FIFO"
    [ -n "$SZC_PID" ] && kill "$SZC_PID" 2>/dev/null
}
trap cleanup EXIT

# Start subzeroclaw in background, reading from our FIFO
"$SZC_PATH" < "$STDIN_FIFO" &
SZC_PID=$!

# Open the FIFO for writing (keeps it open)
exec 3>"$STDIN_FIFO"

# Function to extract JSON field value (simple parsing without jq)
get_json_field() {
    local json="$1"
    local field="$2"
    # Match "field": "value" or "field":"value"
    echo "$json" | sed -n 's/.*"'"$field"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
}

# Process stdin (JSON from orchestrator) and write to subzeroclaw
process_stdin() {
    while IFS= read -r line; do
        # Try to extract type field
        msg_type=$(get_json_field "$line" "type")

        case "$msg_type" in
            "task"|"message")
                from=$(get_json_field "$line" "from")
                content=$(get_json_field "$line" "content")
                [ -z "$from" ] && from="orchestrator"
                echo "[From $from] $content" >&3
                ;;
            "system")
                cmd=$(get_json_field "$line" "command")
                echo "/$cmd" >&3
                ;;
            *)
                # Not recognized JSON or unknown type, pass through
                echo "$line" >&3
                ;;
        esac
    done
}

# Process output from subzeroclaw
process_output() {
    while IFS= read -r line; do
        # Escape special characters for JSON
        escaped=$(echo "$line" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g')

        # Check for @agent: patterns
        if [[ "$line" =~ @([a-zA-Z_][a-zA-Z0-9_]*):\ *(.*) ]]; then
            target="${BASH_REMATCH[1]}"
            content="${BASH_REMATCH[2]}"
            escaped_content=$(echo "$content" | sed 's/\\/\\\\/g; s/"/\\"/g')

            if [ "$target" = "all" ]; then
                echo "{\"type\":\"broadcast\",\"content\":\"$escaped_content\"}"
            else
                echo "{\"type\":\"send\",\"to\":\"$target\",\"content\":\"$escaped_content\"}"
            fi
        fi

        # Always output the line
        echo "{\"type\":\"output\",\"content\":\"$escaped\"}"
    done
}

# Read output from subzeroclaw in background and process it
(
    # Wait for subzeroclaw to start outputting
    while kill -0 "$SZC_PID" 2>/dev/null; do
        if read -r -t 0.1 line < /proc/$SZC_PID/fd/1 2>/dev/null; then
            process_output <<< "$line"
        fi
    done
) &
OUTPUT_PID=$!

# Actually, the above approach is complex. Let's use a simpler method:
# Just run subzeroclaw with stdin/stdout directly connected

# Kill the background process we started
kill $OUTPUT_PID 2>/dev/null
kill $SZC_PID 2>/dev/null
rm -f "$STDIN_FIFO"

# Simple approach: connect stdin/stdout directly and wrap output
exec "$SZC_PATH" 2>&1 | while IFS= read -r line; do
    escaped=$(echo "$line" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g' | tr '\n' ' ')
    echo "{\"type\":\"output\",\"content\":\"$escaped\"}"
done &

# Forward stdin to subzeroclaw
cat > /proc/$!/fd/0 2>/dev/null

wait
echo '{"type":"exit","status":0}'
