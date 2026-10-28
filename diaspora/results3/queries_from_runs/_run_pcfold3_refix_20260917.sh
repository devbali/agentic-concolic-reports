#!/usr/bin/env bash
set -uo pipefail
PY=/home/dev/project/venvs/queries_from_runs/bin/python3
HERE=/home/dev/project/reports/diaspora/results3/queries_from_runs
R3=/home/dev/project/reports/diaspora/results3
LOG=/home/dev/project/reports/diaspora/results3/queries_from_runs/scratchpad_pcfold3_logs
mkdir -p "$LOG"

run_one() {
  ep=$1
  echo "=== START $ep $(date -Is) ===" | tee -a "$LOG/_progress_refix.txt"
  "$PY" "$HERE/_pcfold3_parallel.py" --endpoint "$ep" \
      --dumpdir "$R3/$ep" --out-dir "$HERE" --shards 8 --cap 2 \
      --suffix _pcfold3 > "$LOG/${ep}_refix.log" 2>&1
  rc=$?
  echo "=== DONE $ep exit=$rc $(date -Is) ===" | tee -a "$LOG/_progress_refix.txt"
}

for ep in notifications_index conversations_index people_show people_stream; do
  run_one "$ep"
done
echo "VERDICT_PCFOLD3_REFIX_ALL_DONE $(date -Is)" | tee -a "$LOG/_progress_refix.txt"
