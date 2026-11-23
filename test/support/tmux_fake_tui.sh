#!/bin/sh

workspace=$1
swarm=$2
agent=$3
mode=$4

printf 'FAKE_TUI_READY\n> '

pending=

while IFS= read -r line; do
  if [ "$mode" = "working_hold" ] && [ -z "$line" ]; then
    : > "$workspace/unexpected-enter"
  fi

  if [ "$mode" = "needs_second_enter" ] || [ "$mode" = "never_submit" ]; then
    if [ -z "$pending" ]; then
      case "$line" in
        "GenSwarms turn "*)
          pending=$line
          printf '\n> %s' "$pending"
          continue
          ;;
      esac
    elif [ -z "$line" ]; then
      if [ "$mode" = "never_submit" ]; then
        printf '\n> %s' "$pending"
        continue
      fi

      line=$pending
      pending=
    fi
  fi

  case "$line" in
    "GenSwarms turn "*)
      rest=${line#GenSwarms turn }
      turn_id=${rest%%:*}
      turn_dir="$workspace/.genswarms/turns/$swarm/$agent/$turn_id"

      # "late" completes a turn only when it is spoken to again about it.
      if [ "$mode" = "late" ]; then
        case "$line" in
          *"still open"*|*"restarted"*) late_done=1 ;;
          *) late_done= ;;
        esac
      fi

      if [ "$mode" = "symlink" ]; then
        ln -s "$workspace/host-secret.txt" "$turn_dir/reply.md"
        printf '%s' '{"status":"completed"}' > "$turn_dir/done.json.tmp"
        mv "$turn_dir/done.json.tmp" "$turn_dir/done.json"
      elif [ "$mode" = "late" ] && [ -z "$late_done" ]; then
        :
      elif [ "$mode" != "hold" ] && [ "$mode" != "working_hold" ] && [ "$mode" != "idle_hold" ]; then
        printf 'fake reply for %s\n' "$turn_id" > "$turn_dir/reply.md.tmp"
        mv "$turn_dir/reply.md.tmp" "$turn_dir/reply.md"
        printf '%s' '{"status":"completed"}' > "$turn_dir/done.json.tmp"
        mv "$turn_dir/done.json.tmp" "$turn_dir/done.json"
      fi

      if [ "$mode" = "working_hold" ]; then
        printf '\nWorking (esc to interrupt)\n\n> '
      elif [ "$mode" = "late" ] || [ "$mode" = "idle_hold" ]; then
        # Like a real client, take the input off the prompt: the submitted line scrolls
        # out of the rows around the cursor and the client sits idle at an empty prompt.
        printf '\naccepted\n.\n.\n.\n.\n.\n.\n.\nFAKE_TUI_READY\n> '
      else
        printf '\nFAKE_TUI_READY\n> '
      fi
      ;;
  esac
done
