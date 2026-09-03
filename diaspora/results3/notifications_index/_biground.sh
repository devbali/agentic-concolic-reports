#!/bin/bash
# ONE BIG demand round: coverage with a high MISSING_CAP so every blocking
# combination reaches the JSON, rooted demand, then a replay generous enough to
# actually walk all of them (roots are pushed as worklist ROOTS, so MAX_RUNS
# must exceed the root count by the flips we want around each).
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
LOG="$B/_biground.log"; echo "=== biground start $(date -Is) ===" > "$LOG"
python3 "$B/_dedup.py" >> "$LOG" 2>&1
env SKIP_COMPLETION=1 MISSING_CAP=12000 MAX_MISSING_PER_CLIQUE=60 PYTHONPATH=src \
  python3 "$B/coverage_report.py" >> "$LOG" 2>&1
python3 "$B/_demand_root.py" >> "$LOG" 2>&1
for V in html_typed mobile_typed json_typed html_plain json_plain mobile_plain xml_plain; do
  F="$B/_demandR_${V}.json"; [ -s "$F" ] || continue
  n=$(python3 -c "import json;print(len(json.load(open('$F'))))")
  echo "[big] $V : $n roots" >> "$LOG"
  flock /tmp/concolic-slot.lock env VARIANTS="$V" EXTRA_SEEDS_JSON="$F" \
    LABEL_SUFFIX="_BG${V:0:3}" MAX_RUNS=12000 TIME_BUDGET=900 \
    /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" >> "$LOG" 2>&1
done
python3 "$B/_dedup.py" >> "$LOG" 2>&1
echo "=== biground DONE $(date -Is) ===" >> "$LOG"
