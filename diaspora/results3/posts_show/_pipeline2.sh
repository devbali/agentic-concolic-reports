#!/bin/bash
# STAGE 3+ (coordinator 2026-09-11). All caged; caps sum to <= 4 G while pass B
# is alive, more after. Waits for stage 1 (pxwhatif.scope) to clear first.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
. "$B/_cage.sh"
L="$B/_pipeline2.log"; : > "$L"
say(){ echo "[$(date -Is)] $*" >> "$L"; }

while systemctl --user is-active pxwhatif.scope >/dev/null 2>&1; do sleep 20; done
say "stage 1 clear"

# ---- 3a: are the 1733 pairs NON-FORECLOSING? (3.5 G, alone) ---------------
say "3a foreclosure check"
cage pxforecl.scope 3500M \
  env DUMP_LIST="$B/_snapshot_pruned_p5.txt" PYTHONPATH=/home/dev/project/src \
      JAVA_TOOL_OPTIONS= timeout 3600 python3 -u "$B/_forecl_check.py" \
  > "$B/_forecl_check.log" 2>&1
caged_verdict pxforecl.scope "$B/_forecl_check.log" 'NON-FORECLOSING' >> "$L"

# ---- 3b: additive-dependence witnesses in the corpus (2 G) + 3c X11 (1.5 G)
# 3.5 G together; both start once 3a is done.
say "3b additive scan + 3c X11 control traces, concurrently"
cage pxadd.scope 2G \
  env DUMP_LIST="$B/_snapshot_20260910_p5.txt" SCAN_RUNS=8000 \
      PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      timeout 3600 python3 -u "$B/_additive_scan.py" \
  > "$B/_additive_scan.log" 2>&1 &
P1=$!
cage pxx11.scope 1500M \
  flock /tmp/concolic-heavy.lock python3 -u \
    /home/dev/project/src/end_to_end_completion_checker/assumption/assumption_checker.py \
    "$B/assumption_manifest.json" --declared "$B/_x11_pair.json" \
    --json-out "$B/_x11_results.json" --keep \
  > "$B/_x11.log" 2>&1 &
P2=$!
wait $P1; caged_verdict pxadd.scope "$B/_additive_scan.log" 'ADDITIVE-DEPENDENCE WITNESSES' >> "$L"
wait $P2; caged_verdict pxx11.scope "$B/_x11.log" 'RESULT:' >> "$L"
say "stage 3 done"
