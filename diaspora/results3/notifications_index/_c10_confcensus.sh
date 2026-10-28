#!/bin/bash
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
cd "$B"
echo "[$(date -Is)] confinement census avail=$(free -m|awk '/^Mem/{print $7}')MB"
. /home/dev/project/reports/diaspora/results3/notifications_index/_wait_mem.sh
wait_mem 4600 "$(basename "$0")"
systemd-run --user --slice=concolic-cov.slice --scope -p MemoryMax=4600M -p MemorySwapMax=0 --quiet \
  choom -n 1000 -- \
  env DUMP_LIST="$B/_snapshot_pruned_20260911_122751.txt" PYTHONPATH=/home/dev/project/src EMIT_REMAINING="$B/_remaining_conf.jsonl" \
  timeout 7200 python3 -u /home/dev/project/reports/diaspora/tools/confinement_census.py "$B" \
  --json-out "$B/_confinement_census.json" > "$B/_c10_confcensus.log" 2>&1
echo "[$(date -Is)] confinement census EXIT rc=$?"
