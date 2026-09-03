#!/bin/bash
# Replay the (corrected) demand roots, dedup, then the FINAL engine report.
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
LOG="$B/_rtf.log"; echo "=== replay+final start $(date -Is) ===" > "$LOG"
for V in html_typed mobile_typed json_typed html_plain json_plain mobile_plain xml_plain; do
  F="$B/_demandR_${V}.json"; [ -s "$F" ] || continue
  n=$(python3 -c "import json;print(len(json.load(open('$F'))))")
  echo "--- replay $V ($n roots) ---" >> "$LOG"
  flock /tmp/concolic-slot.lock env VARIANTS="$V" EXTRA_SEEDS_JSON="$F" \
    LABEL_SUFFIX="_D1${V:0:3}" MAX_RUNS=2500 TIME_BUDGET=600 \
    /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" >> "$LOG" 2>&1
done
echo "--- dedup ---" >> "$LOG"
python3 "$B/_dedup.py" >> "$LOG" 2>&1
echo "--- FINAL ENGINE REPORT ---" >> "$LOG"
MAX_MISSING_PER_CLIQUE=4 PYTHONPATH=src python3 "$B/coverage_report.py" >> "$LOG" 2>&1
echo "=== replay+final DONE rc=$? $(date -Is) ===" >> "$LOG"
