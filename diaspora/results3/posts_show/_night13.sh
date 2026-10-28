#!/bin/bash
# THE WHOLE REMAINING NIGHT, in ONE sequential chain, each stage gated by
# `wait_alone` (blocks on ANY agent's pass / census / enumerator / subsumption —
# notifications' agent holds priority for the pass slot) and caged with its own
# MemoryMax. Nothing here overlaps anything else on the box.
#   13PD  the part decomposition census (3 G)   -> _parts_OD0911.json
#   13a   part report / realisation / unevaluated-why (1-2 G)
#   13b   one-flip constructibility, <= 200 runs (2-3 G)
#   13c   THE FINAL PASS + the audits (5 G)
#   13d   extraction, both editions (2 G / 5 G)
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
. "$B/_cage.sh"
L="$B/_night13.log"; : > "$L"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }

say "=== NIGHT 13 START; box: $(free -m | awk 'NR==2{print $7}')M avail, slice $(systemctl --user show concolic-cov.slice -p MemoryCurrent --value) ==="

say "--- 13a: residual classification"
bash "$B/_p13a.sh" >> "$L" 2>&1
say "--- 13b: one-flip constructibility"
bash "$B/_p13b.sh" >> "$L" 2>&1
say "--- 13PD: decompose the OR-refined remaining (census only, REACH_SPLIT on) [3G]"
wait_alone decompPD | tee -a "$L"
cage pxdecompPD2.scope 3G \
  env BATCH="$B" DUMP_LIST="$B/_snapshot_pruned_OD0911.txt" PYTHONPATH=/home/dev/project/src \
      JAVA_TOOL_OPTIONS= REACH_SPLIT=1 REACH_OUT=_reach_split_PD.json EMIT_MAX_PER_SET=0 \
      PARTS_OUT="$B/_parts_OD0911.json" \
      timeout 10800 python3 -u "$B/_part_decomp.py" > "$B/_part_decomp.log" 2>&1
say "13PD exit=$?"
caged_verdict pxdecompPD2.scope "$B/_part_decomp.log" '^DECOMP DONE' >> "$L"
grep -E '^OR-refined:|^PARTS:|REACHABLE remaining|MULTI-GATE-FORECLOSED|leaf groups:' "$B/_part_decomp.log" >> "$L" 2>/dev/null

say "--- 13c: THE FINAL PASS + audits"
bash "$B/_p13c.sh" >> "$L" 2>&1
say "--- 13d: extraction"
bash "$B/_p13d.sh" >> "$L" 2>&1
say "=== NIGHT 13 DONE ==="
