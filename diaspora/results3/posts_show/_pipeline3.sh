#!/bin/bash
# CAGED PIPELINE 3 (coordinator 2026-09-11). Every job via `cage`:
# concolic-cov.slice + per-job MemoryMax + choom -n 1000. THIS DRIVE'S caps sum
# to <= 4 G at every instant (pass B belongs to the detached sequence and is
# excluded from that sum by the owner's budget).
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
. "$B/_cage.sh"
L="$B/_pipeline3.log"; : > "$L"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }

while systemctl --user is-active pxwhatif.scope >/dev/null 2>&1; do sleep 20; done
say "stage 1 (whatif_indep) clear"
caged_verdict pxwhatif.scope "$B/_whatif_indep.log" '^EXACT:' >> "$L"

# ---- 3a: are the 1733 candidates NON-FORECLOSING?  (3.5 G, alone) ----------
say "3a: foreclosure check [cap 3500M]"
cage pxforecl.scope 3500M \
  env DUMP_LIST="$B/_snapshot_pruned_p5.txt" PYTHONPATH=/home/dev/project/src \
      JAVA_TOOL_OPTIONS= timeout 3600 python3 -u "$B/_forecl_check.py" \
  > "$B/_forecl_check.log" 2>&1
caged_verdict pxforecl.scope "$B/_forecl_check.log" 'NON-FORECLOSING' >> "$L"

# ---- 3b + 3c CONCURRENTLY (2 G + 1.5 G = 3.5 G) ---------------------------
say "3b: additive-dependence corpus scan [cap 2G]  ||  3c: X11 pricing [cap 1500M]"
cage pxadd.scope 2G \
  env DUMP_LIST="$B/_snapshot_20260910_p5.txt" SCAN_RUNS=8000 \
      PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      timeout 3600 python3 -u "$B/_additive_scan.py" \
  > "$B/_additive_scan.log" 2>&1 &
P1=$!
cage pxx11.scope 1500M \
  flock /tmp/concolic-heavy.lock env PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
    timeout 3600 python3 -u "$B/_x11_price.py" _tier2_negcontrol.json \
  > "$B/_x11_price.log" 2>&1 &
P2=$!
wait $P1; caged_verdict pxadd.scope "$B/_additive_scan.log" 'ADDITIVE-DEPENDENCE WITNESSES' >> "$L"
wait $P2; caged_verdict pxx11.scope "$B/_x11_price.log" 'X11 PRICING SUMMARY' >> "$L"

# ---- 3d: the re-keying magnitude (3.5 G, alone) ---------------------------
say "3d: wf-merge what-if [cap 3500M]"
cage pxwfmerge.scope 3500M \
  env DUMP_LIST="$B/_snapshot_pruned_p5.txt" PYTHONPATH=/home/dev/project/src \
      JAVA_TOOL_OPTIONS= timeout 3600 python3 -u "$B/_whatif_wf_merge.py" \
  > "$B/_whatif_wf_merge.log" 2>&1
caged_verdict pxwfmerge.scope "$B/_whatif_wf_merge.log" '^EXACT:' >> "$L"
say "pipeline3 done"
