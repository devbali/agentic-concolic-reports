#!/bin/bash
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
cd "$B"
. /home/dev/project/reports/diaspora/results3/notifications_index/_wait_mem.sh
wait_mem 4600 "$(basename "$0")"
systemd-run --user --slice=concolic-cov.slice --scope -p MemoryMax=2G -p MemorySwapMax=0 --quiet \
  choom -n 1000 -- \
  env PLAN=_construct_CT4_plan.json REPORT=_construct_report.json \
  REM=_remaining_s3post.jsonl REM_NOW=_remaining_s4post.jsonl \
  DUMP_LIST="$B/_snapshot_pruned_20260911_094226.txt" PYTHONPATH=/home/dev/project/src \
  python3 -u "$B/_conj_forecl.py" 'dump_*CT4*.json' > "$B/_c10_conj.log" 2>&1
echo "[$(date -Is)] conj EXIT rc=$?"
