#!/bin/bash
# CONVERGENCE LOOP: coverage(SKIP_COMPLETION, MMC) -> rooted demand -> replay,
# repeated until BLOCKING hits 0 or MAXROUNDS is reached. Each round's
# coverage pass takes the HEAVY lock itself (inside coverage_report.py); each
# replay takes the SLOT lock. Usage: _converge6.sh <MAXROUNDS> [MMC]
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
MAX="${1:-6}"; MMC="${2:-300}"
LOG="$B/_converge6.log"; echo "=== converge start $(date -Is) MAX=$MAX MMC=$MMC ===" > "$LOG"
for R in $(seq 1 "$MAX"); do
  echo "--- round $R : dedup ---" >> "$LOG"
  python3 "$B/_dedup.py" >> "$LOG" 2>&1
  echo "--- round $R : coverage (MMC=$MMC) ---" >> "$LOG"
  env SKIP_COMPLETION=1 MISSING_CAP=1500 MAX_MISSING_PER_CLIQUE="$MMC" PYTHONPATH=src python3 "$B/coverage_report.py" >> "$LOG" 2>&1
  BL=$(python3 - "$B/coverage_summary.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
print(sum(1 for m in d.get("missing",[]) if not m.get("untracked")))
PY
)
  echo "[round $R] BLOCKING=$BL" >> "$LOG"
  if [ "$BL" = "0" ]; then echo "=== converge REACHED 0 BLOCKING at round $R $(date -Is) ===" >> "$LOG"; break; fi
  echo "--- round $R : rooted demand ---" >> "$LOG"
  python3 "$B/_demand_root.py" >> "$LOG" 2>&1
  for V in html_plain html_typed json_plain json_typed mobile_plain mobile_typed xml_plain; do
    F="$B/_demandR_${V}.json"
    [ -s "$F" ] || continue
    n=$(python3 -c "import json;print(len(json.load(open('$F'))))")
    echo "[round $R] $V : $n roots" >> "$LOG"
    flock /tmp/concolic-slot.lock env VARIANTS="$V" EXTRA_SEEDS_JSON="$F" \
      LABEL_SUFFIX="_R${R}${V:0:3}" MAX_RUNS=2500 TIME_BUDGET=600 \
      /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" >> "$LOG" 2>&1
  done
done
echo "=== converge DONE $(date -Is) ===" >> "$LOG"
