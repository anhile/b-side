#!/bin/bash
# Logs the memory of B-Side and its WebKit processes to CSV.
#
# Usage: scripts/measure.sh [minutes=30] [interval_seconds=10] [output.csv]
#
# Memory is phys_footprint from `footprint`, the number Activity Monitor shows
# in its Memory column. If `footprint` fails, the script falls back to
# `ps -o rss` and says so on stderr (RSS is a different, usually larger number).
set -u

MINUTES="${1:-30}"
INTERVAL="${2:-10}"
OUT="${3:-}"
STATE="$HOME/Library/Application Support/B-Side/processes.tsv"

cd "$(dirname "$0")/.."

# Prints "pid<TAB>name" per process. Prefers the list the app writes itself,
# which is exact even when Safari or other WebKit apps are running.
processes() {
  if [ -f "$STATE" ]; then
    local app_pid
    app_pid=$(awk -F'\t' 'NR==2 {print $1}' "$STATE")
    if [ -n "$app_pid" ] && kill -0 "$app_pid" 2>/dev/null; then
      awk -F'\t' 'NR>1 && $1 != "" {print $1 "\t" $2}' "$STATE"
      return 0
    fi
  fi
  # Fallback: match by name. This counts EVERY WebKit process of this user, so
  # quit Safari, Mail and other WebKit apps first or the total will be too high.
  local app_pid
  app_pid=$(pgrep -x -u "$USER" "B-Side" | head -1)
  [ -z "$app_pid" ] && return 1
  warn_once "state file missing; matching WebKit processes by name (other apps may be counted)"
  printf '%s\tB-Side\n' "$app_pid"
  ps -axo pid=,user=,comm= | awk -v user="$USER" '
    $2 == user && $3 ~ /com\.apple\.WebKit\./ {
      name = $3; sub(/.*com\.apple\.WebKit\./, "", name); print $1 "\t" name
    }'
}

variant() {
  if [ -f "$STATE" ]; then
    awk -F'\t' 'NR==1 {print $2}' "$STATE"
  else
    echo "${BSIDE_VARIANT:-unknown}"
  fi
}

memory_bytes() {
  local pid=$1 bytes kb
  bytes=$(footprint -f bytes --noCategories -p "$pid" 2>/dev/null | awk '/phys_footprint:/ {print $2; exit}')
  if [ -z "$bytes" ]; then
    kb=$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ')
    if [ -n "$kb" ]; then
      warn_once "footprint failed; using ps rss, which is not comparable to Activity Monitor"
      bytes=$((kb * 1024))
    fi
  fi
  echo "${bytes:-}"
}

WARNED=""
warn_once() {
  case "$WARNED" in *"$1"*) return ;; esac
  WARNED="$WARNED|$1"
  echo "warning: $1" >&2
}

echo "Waiting for B-Side..." >&2
until processes >/dev/null 2>&1; do sleep 1; done

VARIANT=$(variant)
if [ -z "$OUT" ]; then
  mkdir -p measurements
  OUT="measurements/variant-$VARIANT-$(date +%Y%m%d-%H%M%S).csv"
fi
echo "timestamp,variant,process,MB,total_MB,pid" > "$OUT"
echo "Variant $VARIANT: sampling every ${INTERVAL}s for ${MINUTES} min into $OUT" >&2

END=$((SECONDS + MINUTES * 60))
while [ "$SECONDS" -lt "$END" ]; do
  STARTED=$SECONDS
  NOW=$(date +%Y-%m-%dT%H:%M:%S)
  LIST=$(processes)
  if [ -z "$LIST" ]; then
    echo "$NOW  B-Side is not running" >&2
  else
    ROWS=""
    TOTAL=0
    while IFS=$'\t' read -r PID NAME; do
      BYTES=$(memory_bytes "$PID")
      [ -z "$BYTES" ] && continue   # process exited between listing and sampling
      TOTAL=$((TOTAL + BYTES))
      ROWS="$ROWS$PID $NAME $BYTES"$'\n'
    done <<< "$LIST"
    printf '%s' "$ROWS" | awk -v ts="$NOW" -v variant="$VARIANT" -v total="$TOTAL" '
      { printf "%s,%s,%s,%.1f,%.1f,%s\n", ts, variant, $2, $3 / 1048576, total / 1048576, $1 }' >> "$OUT"
    printf '%s  total %.1f MB\n' "$NOW" "$(echo "$TOTAL / 1048576" | bc -l)" >&2
  fi
  REST=$((INTERVAL - (SECONDS - STARTED)))
  [ "$REST" -gt 0 ] && sleep "$REST"
done

echo "Done: $OUT" >&2
