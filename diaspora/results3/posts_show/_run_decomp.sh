#!/bin/bash
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
. "$B/_cage.sh"
L="$B/_part_decomp.log"; : > "$L"
echo "[$(date -Is)] PD: decompose the OR-refined remaining — CENSUS ONLY, no emit (the cap-64 emit drove free -g to 0 and was killed deliberately at 19:15; the emitter-reach question is answered from the p12 cap-8 emit + per-part remaining) [3G]" >> "$L"
wait_no_pass
cage pxdecompPD2.scope 3G \
  env BATCH="$B" DUMP_LIST="$B/_snapshot_pruned_OD0911.txt" PYTHONPATH=/home/dev/project/src \
      JAVA_TOOL_OPTIONS= REACH_SPLIT=1 REACH_OUT=_reach_split_PD.json \
      EMIT_MAX_PER_SET=0 \
      PARTS_OUT="$B/_parts_OD0911.json" \
      timeout 10800 python3 -u "$B/_part_decomp.py" >> "$L" 2>&1
echo "[$(date -Is)] PD exit=$?" >> "$L"
caged_verdict pxdecompPD2.scope "$L" '^DECOMP DONE' >> "$L"
