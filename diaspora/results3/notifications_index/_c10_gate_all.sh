#!/bin/bash
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
cd "$B"
. "$B/_wait_mem.sh"; wait_mem 7168 "gatebench"
T0=$(date +%s)
systemd-run --user --slice=concolic-cov.slice --scope -p MemoryMax=7G -p MemorySwapMax=0 --quiet \
  choom -n 1000 -- \
  env CONCOLIC_SLOTS=3 CONCOLIC_PROBE_WORKERS=3 ACHK_PROBE_BATCH=40 \
  PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
  timeout 86400 python3 -u \
    /home/dev/project/src/end_to_end_completion_checker/assumption/assumption_checker.py \
    "$B/assumption_manifest.json" --declared "$B/_gate_classes_ALL.json" \
    --json-out "$B/_gate_ALL_results.json" > "$B/_gate_ALL.log" 2>&1
echo "[bench] EXIT rc=$? wall=$(( $(date +%s)-T0 ))s"
grep -E "^RESULT:|^== derived" "$B/_gate_ALL.log"
