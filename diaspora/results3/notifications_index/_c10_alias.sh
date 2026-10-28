#!/bin/bash
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
cd "$B"
. /home/dev/project/reports/diaspora/results3/notifications_index/_wait_mem.sh
wait_mem 4600 "$(basename "$0")"
systemd-run --user --slice=concolic-cov.slice --scope -p MemoryMax=2G -p MemorySwapMax=0 --quiet \
  choom -n 1000 -- env PLAN=_construct_CT5_plan.json REPORT=_construct_report.json \
  PYTHONPATH=/home/dev/project/src python3 -u "$B/_alias_miss.py" 'dump_*CT5*.json' \
  > "$B/_c10_alias.log" 2>&1
echo "[$(date -Is)] alias EXIT rc=$?"
