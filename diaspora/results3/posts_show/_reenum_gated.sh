#!/bin/bash
# STEP 3 of the 2026-09-11 ruling: re-enumerate p5 with the restored,
# GATE-TESTED tier installed. Same snapshot, same tool, same flags as
# `_enum_p5_cost.log` — so the only thing that moved is the assumption layer.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
TAG="${1:-gated}"
systemd-run --user --slice=concolic-cov.slice --scope -p MemoryMax=5G --unit="pxenum_${TAG}.scope" \
  env DUMP_LIST="$B/_snapshot_pruned_p5.txt" PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      REACH_SPLIT=1 REACH_OUT="_reach_split_${TAG}.json" \
  timeout 3600 python3 -u "$B/_exact_enum_emit.py" --json-out "$B/_enum_${TAG}.json" \
  > "$B/_enum_${TAG}.log" 2>&1
echo "EXIT=$? $(date -Is)" >> "$B/_enum_${TAG}.log"
grep -E '^\[assumptions\]|evaluation sets|nodes\(active\)|tree_missing=|^EXACT:|^FORECLOSURE:|clique width|REACHABLE remaining|MULTI-GATE' "$B/_enum_${TAG}.log"
