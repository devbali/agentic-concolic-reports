#!/bin/bash
# One demand round: coverage-only -> demand_round -> per-variant targeted DSE
# runs (EXTRA_SEEDS_JSON) appended to the corpus. Usage: _demand_loop.sh <round-tag>
set +e
unset JAVA_TOOL_OPTIONS
cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
TAG="${1:-r1}"
LOG="$B/_demand_${TAG}.log"
echo "=== demand round $TAG start $(date -Is) ===" > "$LOG"
SKIP_COMPLETION=1 MAX_MISSING_PER_CLIQUE=200 PYTHONPATH=src python3 "$B/coverage_report.py" >> "$LOG" 2>&1 || true
PYTHONPATH=src python3 "$B/demand_round.py" >> "$LOG" 2>&1
for V in html_plain html_typed json_plain json_typed mobile_plain mobile_typed xml_plain; do
  F="$B/_demand_${V}.json"
  [ -s "$F" ] || continue
  n=$(python3 -c "import json;print(len(json.load(open('$F'))))")
  echo "[demand $TAG] $V : $n seed dicts" >> "$LOG"
  flock /tmp/concolic-slot.lock env VARIANTS="$V" EXTRA_SEEDS_JSON="$F" LABEL_SUFFIX="_${TAG}${V:0:3}" \
    MAX_RUNS=4000 TIME_BUDGET=600 /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" >> "$LOG" 2>&1
done
echo "=== demand round $TAG DONE $(date -Is) ===" >> "$LOG"
