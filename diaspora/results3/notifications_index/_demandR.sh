#!/bin/bash
# ROOTED demand round: coverage(MMC) -> _demand_root.py -> replay each rooted
# seed dict (base dump seeds + demanded assignment) as a worklist ROOT, letting
# the DSE keep flipping from it. Usage: _demandR.sh <TAG> [MMC] [MAXRUNS]
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
TAG="${1:-R1}"; MMC="${2:-300}"; MR="${3:-900}"
LOG="$B/_demandR_${TAG}.log"; echo "=== rooted demand $TAG start $(date -Is) ===" > "$LOG"
env SKIP_COMPLETION=1 MAX_MISSING_PER_CLIQUE="$MMC" PYTHONPATH=src python3 "$B/coverage_report.py" >> "$LOG" 2>&1
python3 "$B/_demand_root.py" >> "$LOG" 2>&1
for V in html_plain html_typed json_plain json_typed mobile_plain mobile_typed xml_plain; do
  F="$B/_demandR_${V}.json"
  [ -s "$F" ] || continue
  n=$(python3 -c "import json;print(len(json.load(open('$F'))))")
  echo "[rooted $TAG] $V : $n roots" >> "$LOG"
  flock /tmp/concolic-slot.lock env VARIANTS="$V" EXTRA_SEEDS_JSON="$F" \
    LABEL_SUFFIX="_${TAG}${V:0:3}" MAX_RUNS="$MR" TIME_BUDGET=500 \
    /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" >> "$LOG" 2>&1
done
echo "=== rooted demand $TAG DONE $(date -Is) ===" >> "$LOG"
