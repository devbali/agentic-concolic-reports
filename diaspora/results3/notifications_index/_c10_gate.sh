#!/bin/bash
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
DECL="$1"; TAG="${2:-g1}"; CAP="${3:-5G}"; EXTRA="${4:-}"
cd "$B"
echo "[$(date -Is)] gate $TAG declared=$DECL cap=$CAP avail=$(free -m|awk '/^Mem/{print $7}')MB"
. /home/dev/project/reports/diaspora/results3/notifications_index/_wait_mem.sh
wait_mem 5120 "$(basename "$0")"
systemd-run --user --slice=concolic-cov.slice --scope -p MemoryMax="$CAP" -p MemorySwapMax=0 --quiet \
  choom -n 1000 -- \
  env CONCOLIC_SLOTS=2 PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
  timeout 36000 python3 -u \
    /home/dev/project/src/end_to_end_completion_checker/assumption/assumption_checker.py \
    "$B/assumption_manifest.json" --declared "$B/$DECL" $EXTRA \
    --json-out "$B/_gate_${TAG}.json" > "$B/_gate_${TAG}.log" 2>&1
echo "[$(date -Is)] gate $TAG EXIT rc=$?"
grep -E "^RESULT:|^\[canonicalize\]|^== derived" "$B/_gate_${TAG}.log"
