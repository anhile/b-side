#!/bin/bash
# Experiment 2, guided. In each round a "home" app (B-Side's stand-in) claims
# the Play key, another player takes it, and then goes away in some way. You
# press Play/Pause (F8) once; the script records who received it and whether
# Apple Music was launched.
set -uo pipefail
cd "$(dirname "$0")"
mkdir -p results
LOG="$(pwd)/results/stack.log"
SUMMARY="$(pwd)/results/stack-summary.tsv"
WAIT=8

[ -d build/Stack-paused-home.app ] || ./build.sh

running() { pgrep -x "$1" >/dev/null; }
pause_for() { read -r -p "$1 Then press Enter. " _; }
spike() { open -n "build/Stack-$1-$2.app" --args -log "$LOG" "${@:3}"; }
stop() { pkill -f "Stack-$1-$2.app/Contents/MacOS/Stack"; }

echo "Experiment 2: does the Play key come back after another player."
echo "Before starting, quit B-Side, Music, Spotify, and pause or close any browser tab that played sound."
for app in B-Side Music Spotify; do
  while running "$app"; do pause_for "$app is running: quit it (Command-Q)."; done
done

printf "%s\tround\thome got\tother got\tMusic launched\n" "$(date +%FT%T)" >> "$SUMMARY"

for round in paused quit-paused quit-playing cleared browser; do
  echo
  echo "=== $round ==="
  while running Music; do pause_for "Music is running: quit it (Command-Q)."; done
  printf "%s\t%s\tround start\n" "$(date +%FT%T)" "$round" >> "$LOG"
  spike "$round" home
  sleep 2

  case $round in
    paused)       echo "The other player plays, then pauses and stays open."
                  spike "$round" intruder -then paused; sleep 4 ;;
    quit-paused)  echo "The other player plays, pauses, then quits."
                  spike "$round" intruder -then paused; sleep 4; stop "$round" intruder; sleep 2 ;;
    quit-playing) echo "The other player plays and quits while playing."
                  spike "$round" intruder -then playing; sleep 4; stop "$round" intruder; sleep 2 ;;
    cleared)      echo "The other player plays, then clears its Now Playing entry and stays open."
                  spike "$round" intruder -then cleared; sleep 4 ;;
    browser)      echo "Now a real browser: open a YouTube video (or anything with sound) in Safari or Chrome,"
                  echo "let it play for about 5 seconds, then close that TAB (keep the browser open)."
                  pause_for "When the tab is closed," ;;
  esac

  start_lines=$(wc -l < "$LOG")
  echo "Press Play/Pause (F8) ONCE now. Waiting $WAIT s..."
  sleep "$WAIT"

  got() { tail -n +"$((start_lines + 1))" "$LOG" | awk -F'\t' -v role="$1" '$3 == role && $4 ~ /^command / {sub("command ", "", $4); print $4}' | paste -sd, -; }
  home=$(got home); other=$(got intruder)
  [ "$round" = browser ] && other="(browser, not observable)"
  music=no
  running Music && music=yes
  stop "$round" home; stop "$round" intruder 2>/dev/null
  printf "%s\t%s\tround end, home: %s, other: %s, Music: %s\n" "$(date +%FT%T)" "$round" "${home:-none}" "${other:-none}" "$music" >> "$LOG"
  printf "%s\t%s\t%s\t%s\t%s\n" "$(date +%FT%T)" "$round" "${home:-none}" "${other:-none}" "$music" >> "$SUMMARY"
  echo "Result: home got: ${home:-none}; other got: ${other:-none}; Music launched: $music"
  [ "$round" = browser ] && echo "(If neither home nor Music reacted, the browser tab or the browser took it.)"
  sleep 1
done

echo
echo "Done. Quit Music if it is open. Results:"
tail -n 6 "$SUMMARY"
