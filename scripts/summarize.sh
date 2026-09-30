#!/bin/bash
# Summarizes CSV files from measure.sh as rows for the table in RESULTS.md.
#
# Usage: scripts/summarize.sh measurements/*.csv
#
# Growth compares the average of the last 5 minutes with the average of
# minutes 2-7, so page load and the first track do not count as growth.
set -u

echo "| Variant | Samples | Avg total MB | Peak total MB | Early avg MB | Late avg MB | Growth MB | Peak WebContent MB | File |"
echo "|---|---|---|---|---|---|---|---|---|"

for FILE in "$@"; do
  awk -F, -v file="$(basename "$FILE")" '
    function seconds(ts,   parts) {
      # macOS awk has no mktime(); this is only used for differences within one run.
      split(ts, parts, /[-T:]/)
      return (parts[2] * 31 + parts[3]) * 86400 + parts[4] * 3600 + parts[5] * 60 + parts[6]
    }
    NR == 1 { next }
    {
      variant = $2
      if ($3 == "WebContent" && $4 > peak_web) peak_web = $4
      if ($1 == last) next          # total_MB repeats on every row of a sample
      last = $1
      n++
      time[n] = seconds($1)
      total[n] = $5
      sum += $5
      if ($5 > peak) peak = $5
    }
    END {
      if (n == 0) { printf "| ? | 0 | | | | | | | %s |\n", file; exit }
      start = time[1]; end = time[n]
      for (i = 1; i <= n; i++) {
        if (time[i] >= start + 120 && time[i] < start + 420) { early += total[i]; early_n++ }
        if (time[i] > end - 300) { late += total[i]; late_n++ }
      }
      if (early_n == 0 || end - start < 720) {
        growth = "run too short"; early_avg = "-"; late_avg = "-"
      } else {
        early_avg = sprintf("%.0f", early / early_n)
        late_avg = sprintf("%.0f", late / late_n)
        growth = sprintf("%+.0f", late / late_n - early / early_n)
      }
      printf "| %s | %d | %.0f | %.0f | %s | %s | %s | %.0f | %s |\n",
        variant, n, sum / n, peak, early_avg, late_avg, growth, peak_web, file
    }' "$FILE"
done
