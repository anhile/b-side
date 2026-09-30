#!/bin/bash
# Experiment 1, guided: a baseline round with no spike, then one round per
# variant. In each round you press Play/Pause (F8) once; the script records
# whether the spike got the command and whether Apple Music was launched.
set -uo pipefail
cd "$(dirname "$0")"
mkdir -p results
LOG="$(pwd)/results/eligibility.log"
SUMMARY="$(pwd)/results/eligibility-summary.tsv"
WAIT=8

[ -d build/Eligibility-none.app ] || ./build.sh

running() { pgrep -x "$1" >/dev/null; }
pause_for() { read -r -p "$1 Then press Enter. " _; }

echo "Experiment 1: which registration gets the Play key right after launch."
echo "Before starting, quit B-Side, Music, Spotify, and pause or close any browser tab that played sound."
for app in B-Side Music Spotify; do
  while running "$app"; do pause_for "$app is running: quit it (Command-Q)."; done
done

printf "%s\tround\tcommand received\tMusic launched\n" "$(date +%FT%T)" >> "$SUMMARY"

for variant in baseline none paused playpaused playstopped; do
  echo
  echo "=== $variant ==="
  while running Music; do pause_for "Music is running: quit it (Command-Q)."; done
  printf "%s\t%s\tround start\n" "$(date +%FT%T)" "$variant" >> "$LOG"
  if [ "$variant" != baseline ]; then
    open -n "build/Eligibility-$variant.app" --args -log "$LOG"
    sleep 3
  fi
  start_lines=$(wc -l < "$LOG")
  echo "Press Play/Pause (F8) ONCE now. Waiting $WAIT s..."
  sleep "$WAIT"

  commands=$(tail -n +"$((start_lines + 1))" "$LOG" | awk -F'\t' '$3 ~ /^command / {sub("command ", "", $3); print $3}' | paste -sd, -)
  music=no
  running Music && music=yes
  [ "$variant" != baseline ] && pkill -f "Eligibility-$variant.app/Contents/MacOS/Eligibility"
  printf "%s\t%s\tround end, command: %s, Music: %s\n" "$(date +%FT%T)" "$variant" "${commands:-none}" "$music" >> "$LOG"
  printf "%s\t%s\t%s\t%s\n" "$(date +%FT%T)" "$variant" "${commands:-none}" "$music" >> "$SUMMARY"
  echo "Result: command received: ${commands:-none}; Music launched: $music"
  sleep 1
done

echo
echo "Done. Quit Music if it is open. Results:"
tail -n 6 "$SUMMARY"
