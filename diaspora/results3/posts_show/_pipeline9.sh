#!/bin/bash
# PIPELINE 9 — CONSTRUCT-BEFORE-RESIDUE (RUNBOOK Phase 2, 2026-09-11).
# Held until the gate-aware census lands. Nothing here declares anything: it
# builds the remaining cubes by gate combination, replays them, and reports what
# realises. Only a gate that FLIPS BACK DESPITE ITS SEED is impossibility
# evidence — that is the only thing allowed to be called residue afterwards.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
. "$B/_cage.sh"
L="$B/_pipeline9.log"; : > "$L"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }

while [ ! -s "$B/_confinement_census_gateaware.json" ]; do sleep 60; done
say "gate-aware census landed"

say "9a: emit EVERY remaining cube (EMIT_REACHABLE_ONLY=0) [cap 3500M]"
wait_headroom 3 | tee -a "$L"
cage pxemitga.scope 3500M \
  env DUMP_LIST="$B/_snapshot_pruned_p5.txt" PYTHONPATH=/home/dev/project/src \
      JAVA_TOOL_OPTIONS= EMIT_REACHABLE_ONLY=0 REACH_SPLIT=1 \
      REACH_OUT=_reach_split_gateaware.json \
      EMIT_OUT="$B/_enum_emit_gateaware.json" EMIT_MAX_PER_SET=4 \
      timeout 7200 python3 -u "$B/_exact_enum_emit.py" \
      --json-out "$B/_enum_gateaware.json" \
  > "$B/_enum_emit_gateaware.log" 2>&1
caged_verdict pxemitga.scope "$B/_enum_emit_gateaware.log" '^EMIT:' >> "$L"
grep -E '^EXACT:|^EMIT:|REACHABLE remaining|MULTI-GATE-FORECLOSED' \
  "$B/_enum_emit_gateaware.log" >> "$L" 2>/dev/null

say "9b: construct one seed per GATE COMBINATION (x4 variants) [cap 2G]"
cage pxconstruct.scope 2G \
  env EMIT_IN="$B/_enum_emit_gateaware.json" DUMP_LIST="$B/_rootbase_p5.txt" \
      VARIANTS_PER_COMBO=4 PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      timeout 3600 python3 -u "$B/_construct_by_gate.py" \
  > "$B/_construct_by_gate.log" 2>&1
caged_verdict pxconstruct.scope "$B/_construct_by_gate.log" 'constructed seeds' >> "$L"
grep -E 'cubes emitted|GATE COMBINATIONS|constructed seeds|no base|-> _demandR' \
  "$B/_construct_by_gate.log" >> "$L" 2>/dev/null

say "9c: REPLAY them (JRuby; slot-limited; unique LABEL_SUFFIX)"
free -g | sed -n 2p >> "$L"
cage_drive pxdrive_GC0911.scope 3G env CONCOLIC_SLOTS=2 DRIVE_PAR=2 \
  bash "$B/_demand_drive.sh" GC0911 200 >> "$L" 2>&1
grep -E 'seeds ->|corpus after|abort|toxic|consumed' \
  "$B/_demand_drive_GC0911.log" 2>/dev/null | tail -12 >> "$L"

say "9d: re-snapshot, prune, re-census — what REALISED"
find "$B" -maxdepth 1 -name 'dump_*.json' | sort > "$B/_snapshot_after_GC0911.txt"
wait_headroom 3 | tee -a "$L"
cage pxpruneGC.scope 3G \
  env DUMP_LIST="$B/_snapshot_after_GC0911.txt" PYTHONPATH=/home/dev/project/src \
      JAVA_TOOL_OPTIONS= python3 -u "$B/_prune_corpus.py" \
      --out "$B/_snapshot_pruned_GC0911.txt" >> "$L" 2>&1
 tee -a "$L"$| tee -a "$L"; wait_headroom 3 | tee -a "$L"
cage pxconfGC.scope 3500M \
  env DUMP_LIST="$B/_snapshot_pruned_GC0911.txt" PYTHONPATH=/home/dev/project/src \
      JAVA_TOOL_OPTIONS= timeout 7200 \
  python3 -u /home/dev/project/reports/diaspora/tools/confinement_census.py "$B" \
      --json-out "$B/_confinement_census_GC0911.json" \
  > "$B/_confinement_census_GC0911.log" 2>&1
caged_verdict pxconfGC.scope "$B/_confinement_census_GC0911.log" 'EXACT:|remaining' >> "$L"
say "pipeline9 done — per-combination table to be built from _construct_plan.json + the re-census"
