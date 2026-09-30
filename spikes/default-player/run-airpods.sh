#!/bin/bash
# Experiment 3, guided: what AirPods send, and when Apple Music starts.
# Rounds 1-2 with no player registered, 3-5 with a "home" app that claims the
# Play key as B-Side does (it only logs), 6-7 with B-Side itself playing.
set -uo pipefail
cd "$(dirname "$0")"
mkdir -p results
LOG="$(pwd)/results/airpods.log"
SUMMARY="$(pwd)/results/airpods-summary.tsv"
BSIDE_LOG="$HOME/Library/Application Support/B-Side/events.log"
BSIDE_APP="$(cd ../.. && pwd)/build/Build/Products/Release/B-Side.app"

./build.sh >/dev/null # fresh bundle IDs for every run

running() { pgrep -x "$1" >/dev/null; }
pause_for() { read -r -p "$1 Then press Enter. " _; }
say() { echo "$@"; }
no_music() { while running Music; do pause_for "Music is running: quit it (Command-Q)."; done; }

say "Experiment 3: AirPods. Keep the AirPods paired with this Mac, and your iPhone"
say "away or with Bluetooth off, so they do not switch to it."
say "Before starting, quit B-Side, Music, Spotify, and close any browser tab that played sound."
for app in B-Side Music Spotify; do
  while running "$app"; do pause_for "$app is running: quit it (Command-Q)."; done
done
printf "%s\tround\tcommands\tMusic launched\toutput\n" "$(date +%FT%T)" >> "$SUMMARY"

record() { # record <round> <commands> <music> <output>
  printf "%s\t%s\tround end, commands: %s, Music: %s, output: %s\n" "$(date +%FT%T)" "$1" "$2" "$3" "$4" >> "$LOG"
  printf "%s\t%s\t%s\t%s\t%s\n" "$(date +%FT%T)" "$1" "$2" "$3" "$4" >> "$SUMMARY"
  say "Result: commands: $2; Music launched: $3; output: $4"
}

spike_round() { # spike_round <round> <instructions...>
  local round=$1
  say; say "=== $round ==="
  no_music
  printf "%s\t%s\tround start\n" "$(date +%FT%T)" "$round" >> "$LOG"
  local start; start=$(wc -l < "$LOG")
  open -n "build/AirPods-$round.app" --args -log "$LOG"
  sleep 2
  case $round in
    *-connect)
      pause_for "Put both AirPods in the case and close the lid. Wait until the Mac's speakers are the output (about 5 s)."
      pause_for "Now take them out and put them in your ears. When you hear the connection sound,"
      sleep 6 ;;
    *-press)
      say "Press the stem of one AirPod ONCE now. Waiting 8 s..."
      sleep 8 ;;
    *-ear)
      pause_for "Take ONE AirPod out, wait 3 seconds, put it back in. When it is back,"
      sleep 5 ;;
  esac
  local lines; lines=$(tail -n +"$((start + 1))" "$LOG")
  local commands; commands=$(echo "$lines" | awk -F'\t' '$4 ~ /^command / {sub("command ", "", $4); print $4}' | paste -sd, -)
  local output; output=$(echo "$lines" | awk -F'\t' '$4 ~ /^output / {sub("output ", "", $4); print $4}' | paste -sd'>' -)
  local music=no
  { running Music || echo "$lines" | grep -q "Music launched"; } && music=yes
  pkill -f "AirPods-$round.app/Contents/MacOS/Stack"
  record "$round" "${commands:-none}" "$music" "${output:-?}"
}

spike_round none-connect
spike_round none-press
spike_round home-connect
spike_round home-press
spike_round home-ear

# B-Side itself: what it receives while it really plays to the AirPods.
bside_round() { # bside_round <round>
  local round=$1
  say; say "=== $round ==="
  no_music
  printf "%s\t%s\tround start\n" "$(date +%FT%T)" "$round" >> "$LOG"
  local start; start=$(wc -l < "$BSIDE_LOG")
  case $round in
    bside-ear)
      pause_for "Take ONE AirPod out, wait 3 seconds, put it back in. When it is back,"
      sleep 5 ;;
    bside-press)
      say "Press the stem ONCE, wait 3 seconds, press it ONCE more. Waiting 12 s..."
      sleep 12 ;;
  esac
  # Only the command and play-state lines: track titles stay out of the results.
  local events; events=$(tail -n +"$((start + 1))" "$BSIDE_LOG" | awk -F'\t' '$3 == "remote" || $3 == "paused" || $3 == "playing" {print $3 ($4 != "" ? " " $4 : "")}' | paste -sd, -)
  local music=no
  running Music && music=yes
  printf "%s\t%s\tB-Side: %s\n" "$(date +%FT%T)" "$round" "${events:-nothing}" >> "$LOG"
  record "$round" "${events:-nothing}" "$music" "-"
}

say; say "=== B-Side ==="
open -n "$BSIDE_APP" --args -ApplePersistenceIgnoreState YES
pause_for "B-Side is starting. Press Play/Pause (F8) so it plays through the AirPods. When you hear music,"
bside_round bside-ear
bside_round bside-press

say
say "Done. B-Side is still open; quit it or keep it. Results:"
tail -n 8 "$SUMMARY"
