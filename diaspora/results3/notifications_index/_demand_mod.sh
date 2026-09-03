#!/bin/bash
# LEAN demand round: coverage(MMC=200) -> demand_round -> SEEDS_ONLY replay of
# each demanded combo ONCE per variant (no flip-expansion). Keeps the corpus
# small so coverage + the assumption gate stay tractable. Usage: _demand_lean.sh <tag>
set +e
unset JAVA_TOOL_OPTIONS
cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
TAG="${1:-L1}"
LOG="$B/_demand_${TAG}.log"
echo "=== mod demand $TAG start $(date -Is) ===" > "$LOG"
SKIP_COMPLETION=1 MAX_MISSING_PER_CLIQUE=300 PYTHONPATH=src python3 "$B/coverage_report.py" >> "$LOG" 2>&1 || true
PYTHONPATH=src python3 "$B/demand_round.py" >> "$LOG" 2>&1
for V in html_plain html_typed json_plain json_typed mobile_plain mobile_typed xml_plain; do
  F="$B/_demand_${V}.json"
  [ -s "$F" ] || continue
  n=$(python3 -c "import json;print(len(json.load(open('$F'))))")
  echo "[mod $TAG] $V : $n seed dicts (SEEDS_ONLY)" >> "$LOG"
  flock /tmp/concolic-slot.lock env VARIANTS="$V" EXTRA_SEEDS_JSON="$F" 
    LABEL_SUFFIX="_${TAG}${V:0:3}" MAX_RUNS=800 TIME_BUDGET=280 \
    /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" >> "$LOG" 2>&1
done
echo "=== mod demand $TAG DONE $(date -Is) ===" >> "$LOG"
