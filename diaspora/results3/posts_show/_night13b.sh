#!/bin/bash
# NIGHT 13, RESUMED after the ordering fix: 13a-2 (realisation) and 13a-3
# (unevaluated-why) are DONE and are not re-run. What is left needs the census
# first, because the undecidable list and the part report both read
# _parts_OD0911.json.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
. "$B/_cage.sh"
L="$B/_night13.log"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }

say "=== NIGHT 13b RESUME; box: $(free -m | awk 'NR==2{print $7}')M avail ==="
say "--- 13PD: decompose the OR-refined remaining (census only, REACH_SPLIT on) [3G]"
wait_alone decompPD | tee -a "$L"
cage pxdecompPD2.scope 3G \
  env BATCH="$B" DUMP_LIST="$B/_snapshot_pruned_OD0911.txt" PYTHONPATH=/home/dev/project/src \
      JAVA_TOOL_OPTIONS= REACH_SPLIT=1 REACH_OUT=_reach_split_PD.json EMIT_MAX_PER_SET=0 \
      PARTS_OUT="$B/_parts_OD0911.json" \
      timeout 10800 python3 -u "$B/_part_decomp.py" > "$B/_part_decomp.log" 2>&1
say "13PD exit=$?"
caged_verdict pxdecompPD2.scope "$B/_part_decomp.log" '^DECOMP DONE' >> "$L"
grep -E '^OR-refined:|^PARTS:|REACHABLE remaining|MULTI-GATE-FORECLOSED|  leaf groups:' "$B/_part_decomp.log" >> "$L" 2>/dev/null

say "--- 13a-1: the part report (needs the census) [1G]"
cage p13part.scope 1G env PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
  TOPN=12 MEMBERS=6 python3 -u "$B/_part_report.py" > "$B/_part_report.log" 2>&1
caged_verdict p13part.scope "$B/_part_report.log" 'PART REPORT DONE' >> "$L"

say "--- 13b: one-flip constructibility"
bash "$B/_p13b.sh" >> "$L" 2>&1
say "--- 13c: THE FINAL PASS + engine section + audits"
bash "$B/_p13c.sh" >> "$L" 2>&1
say "--- 13d: extraction"
bash "$B/_p13d.sh" >> "$L" 2>&1
say "=== NIGHT 13 DONE ==="
