#!/usr/bin/env bash
# Full-corpus regeneration, all six endpoints, --reliable-pruning-witnesses
# both arms. Run under systemd-run (see the launch command in
# _PCFOLD3_STATUS.md). Sequential across endpoints (each uses up to 8
# shards internally) so this job's own total footprint stays within the
# authorized ~8-core budget instead of self-contending.
set -uo pipefail
PY=/home/dev/project/venvs/queries_from_runs/bin/python3
HERE=/home/dev/project/reports/diaspora/results3/queries_from_runs
R3=/home/dev/project/reports/diaspora/results3
OUT="$HERE"
LOG=/tmp/claude-1000/-home-dev-project/94ab9891-b436-4797-97e1-81b88a854f05/scratchpad/pcfold3_logs
mkdir -p "$LOG"

run_one() {
  ep=$1
  echo "=== START $ep $(date -Is) ===" | tee -a "$LOG/_progress.txt"
  "$PY" "$HERE/_pcfold3_parallel.py" --endpoint "$ep" \
      --dumpdir "$R3/$ep" --out-dir "$OUT" --shards 8 --cap 2 \
      --suffix _pcfold3 > "$LOG/$ep.log" 2>&1
  rc=$?
  echo "=== DONE $ep exit=$rc $(date -Is) ===" | tee -a "$LOG/_progress.txt"
}

# 2026-09-16 coordinator revision: notifications_index FIRST (the endpoint
# the diagnosis predicts the largest effect on -- get the answer in ~an hour
# instead of last). posts_show DROPPED: its corpus is being actively driven
# by a live campaign right now (growing by thousands of dumps per round), so
# extracting it is a moving target that would be superseded at closure
# anyway, and its loadability residue is corpus-bound (B-4), not
# extraction-bound -- this run cannot tell us anything about the pruning fix
# for that endpoint.
for ep in notifications_index comments_index conversations_index people_show people_stream; do
  run_one "$ep"
done
echo "VERDICT_PCFOLD3_ALL_DONE $(date -Is)" | tee -a "$LOG/_progress.txt"
