#!/bin/bash
# STEP 1 of the phase-3 brief: measure the EXACT ENUMERATOR's cost on the p5
# snapshot. Capped at 4 GB by cgroup so it can never take down pass B (which
# is running beside it: this is NOT a coverage pass, it is a census).
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
LOG="$B/_enum_p5_cost.log"
: > "$LOG"
echo "launched $(date -Is)" >> "$LOG"
echo "free -m avail at launch: $(free -m | awk 'NR==2{print $7}')" >> "$LOG"
/usr/bin/time -v -o "$B/_enum_p5_cost.time" \
systemd-run --user --slice=concolic-cov.slice --scope -p MemoryMax=4G --unit=pxenumP5.scope \
  env DUMP_LIST="$B/_snapshot_pruned_p5.txt" PYTHONPATH=/home/dev/project/src \
      FORECLOSURE=1 MAX_CLIQUES=16384 JAVA_TOOL_OPTIONS= \
  timeout 3600 python3 -u "$B/_exact_enum.py" --json-out "$B/_enum_p5_cost.json" \
  >> "$LOG" 2>&1
echo "EXIT=$? finished $(date -Is)" >> "$LOG"
