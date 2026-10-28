#!/bin/bash
# PIPELINE 10 — drive what GC0911 REALISED, then re-census (companion).
# The 17 realised gates are NOT residue; deepen them with more bases/variants
# so the UNEVALUATED 68% gets more chances to be reached on the taken path.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
. "$B/_cage.sh"
L="$B/_pipeline10.log"; : > "$L"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }

say "10a: re-emit on the GC0911 snapshot (every cube) [cap 3500M]"
wait_headroom 3 | tee -a "$L"
cage pxemitR2.scope 3500M \
  env DUMP_LIST="$B/_snapshot_pruned_GC0911.txt" PYTHONPATH=/home/dev/project/src \
      JAVA_TOOL_OPTIONS= EMIT_REACHABLE_ONLY=0 REACH_SPLIT=1 \
      REACH_OUT=_reach_split_R2.json EMIT_OUT="$B/_enum_emit_R2.json" \
      EMIT_MAX_PER_SET=4 timeout 7200 python3 -u "$B/_exact_enum_emit.py" \
      --json-out "$B/_enum_R2.json" > "$B/_enum_emit_R2.log" 2>&1
caged_verdict pxemitR2.scope "$B/_enum_emit_R2.log" '^EMIT:' >> "$L"
grep -E '^EXACT:|^EMIT:|REACHABLE remaining|MULTI-GATE' "$B/_enum_emit_R2.log" >> "$L" 2>/dev/null

say "10b: construct, MORE bases per combination (the UNEVALUATED 68% is the wall)"
cage pxconsR2.scope 2G \
  env EMIT_IN="$B/_enum_emit_R2.json" DUMP_LIST="$B/_rootbase_p5.txt" \
      VARIANTS_PER_COMBO=8 PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      timeout 3600 python3 -u "$B/_construct_by_gate.py" \
      > "$B/_construct_R2.log" 2>&1
caged_verdict pxconsR2.scope "$B/_construct_R2.log" 'constructed seeds' >> "$L"
grep -E 'cubes emitted|GATE COMBINATIONS|constructed seeds|no base' "$B/_construct_R2.log" >> "$L" 2>/dev/null

say "10c: replay"
cage_drive pxdrive_R2C0911.scope 3G env CONCOLIC_SLOTS=2 DRIVE_PAR=2 \
  bash "$B/_demand_drive.sh" R2C0911 200 >> "$L" 2>&1
grep -E 'corpus after|abort|toxic' "$B/_demand_drive_R2C0911.log" 2>/dev/null | tail -6 >> "$L"

say "10d: prune + re-census (companion, headroom only)"
find "$B" -maxdepth 1 -name 'dump_*.json' | sort > "$B/_snapshot_after_R2C0911.txt"
wait_headroom 3 | tee -a "$L"
cage pxpruneR2.scope 3G \
  env DUMP_LIST="$B/_snapshot_after_R2C0911.txt" PYTHONPATH=/home/dev/project/src \
      JAVA_TOOL_OPTIONS= python3 -u "$B/_prune_corpus.py" \
      --out "$B/_snapshot_pruned_R2C0911.txt" >> "$L" 2>&1
wait_headroom 3 | tee -a "$L"
cage pxconfR2.scope 3500M \
  env DUMP_LIST="$B/_snapshot_pruned_R2C0911.txt" PYTHONPATH=/home/dev/project/src \
      JAVA_TOOL_OPTIONS= timeout 7200 \
  python3 -u /home/dev/project/reports/diaspora/tools/confinement_census.py "$B" \
      --json-out "$B/_confinement_census_R2C0911.json" \
      > "$B/_confinement_census_R2C0911.log" 2>&1
caged_verdict pxconfR2.scope "$B/_confinement_census_R2C0911.log" 'EXACT:|remaining' >> "$L"
grep -E '^  16b:|^  16c:' "$B/_confinement_census_R2C0911.log" >> "$L" 2>/dev/null
say "10e: realisation table for this round"
python3 -u "$B/_gc_realise.py" > "$B/_r2_realise.log" 2>&1
grep -E 'REALISED|UNEVALUATED|CONTRADICTED|FLIPPED BACK|realised at least' "$B/_r2_realise.log" >> "$L" 2>/dev/null
say "pipeline10 done"
