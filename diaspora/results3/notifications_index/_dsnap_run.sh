#!/bin/bash
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
LOG="$B/_dsnap_run.log"; echo "start $(date -Is)" > "$LOG"
for V in html_typed mobile_typed json_typed html_plain mobile_plain; do
  F="$B/_dsnap_${V}.json"; [ -s "$F" ] || continue
  n=$(python3 -c "import json;print(len(json.load(open('$F'))))")
  echo "[$V] $n full-context seeds" >> "$LOG"
  flock /tmp/concolic-slot.lock env VARIANTS="$V" EXTRA_SEEDS_JSON="$F" SEEDS_ONLY=1 \
    LABEL_SUFFIX="_ds${V:0:3}" MAX_RUNS=3000 TIME_BUDGET=300 \
    /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" >> "$LOG" 2>&1
done
echo "DONE $(date -Is)" >> "$LOG"
