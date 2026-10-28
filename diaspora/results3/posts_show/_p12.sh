#!/bin/bash
# PIPELINE 12 — construction against the RIGHT target: the OR-REFINED remaining
# set, emitted from the same universe confinement_census.py censuses as 16c.
# Rounds GC0911/R2C0911/OR0911 all emitted from the §16b universe (5.2e13) and
# could only hit the 2.02e7 OR demand by accident — 0/32/11 assignments over
# 40 584 runs. This is the same method aimed at the right set.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
. "$B/_cage.sh"
L="$B/_p12.log"; : > "$L"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }
SNAP="$B/_snapshot_pruned_OR0911.txt"

say "12a: EMIT the OR-refined remaining (not §16b) [3500M]"
cage pxemitOR2.scope 3500M \
  env BATCH="$B" DUMP_LIST="$SNAP" PYTHONPATH=/home/dev/project/src \
      JAVA_TOOL_OPTIONS= EMIT_OUT="$B/_enum_emit_ORDEMAND.json" \
      EMIT_MAX_PER_SET=8 timeout 10800 python3 -u "$B/_emit_or_demand.py" \
      > "$B/_emit_or_demand.log" 2>&1
caged_verdict pxemitOR2.scope "$B/_emit_or_demand.log" '^EMIT:|OR-refined:' >> "$L"
grep -E '^EMIT:|OR-refined:|EMIT over the OR' "$B/_emit_or_demand.log" >> "$L" 2>/dev/null

say "12b: construct per gate combination (fixed constructor, 8 bases)"
cage pxconsOR2.scope 2G \
  env EMIT_IN="$B/_enum_emit_ORDEMAND.json" DUMP_LIST="$B/_rootbase_p5.txt" \
      VARIANTS_PER_COMBO=8 PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      timeout 3600 python3 -u "$B/_construct_by_gate.py" > "$B/_construct_ORDEMAND.log" 2>&1
caged_verdict pxconsOR2.scope "$B/_construct_ORDEMAND.log" 'constructed seeds' >> "$L"
grep -E 'cubes emitted|GATE COMBINATIONS|constructed seeds|OUT-OF-DOMAIN' "$B/_construct_ORDEMAND.log" >> "$L" 2>/dev/null

say "12c: drive (caged)"
cage_drive pxdrive_OD0911.scope 3G env CONCOLIC_SLOTS=2 DRIVE_PAR=2 \
  bash "$B/_demand_drive.sh" OD0911 200 >> "$L" 2>&1
grep -E 'corpus after|abort|toxic' "$B/_demand_drive_OD0911.log" 2>/dev/null | tail -4 >> "$L"

say "12d: prune + re-census — the PRE-REGISTERED STOP (<1000 => exhausted)"
find "$B" -maxdepth 1 -name 'dump_*.json' | sort > "$B/_snapshot_after_OD0911.txt"
cage pxpruneOD.scope 3G \
  env DUMP_LIST="$B/_snapshot_after_OD0911.txt" PYTHONPATH=/home/dev/project/src \
      JAVA_TOOL_OPTIONS= python3 -u "$B/_prune_corpus.py" \
      --out "$B/_snapshot_pruned_OD0911.txt" >> "$L" 2>&1
cage pxconfOD.scope 3500M \
  env DUMP_LIST="$B/_snapshot_pruned_OD0911.txt" PYTHONPATH=/home/dev/project/src \
      JAVA_TOOL_OPTIONS= timeout 10800 \
  python3 -u /home/dev/project/reports/diaspora/tools/confinement_census.py "$B" \
      --json-out "$B/_confinement_census_OD0911.json" \
      > "$B/_confinement_census_OD0911.log" 2>&1
caged_verdict pxconfOD.scope "$B/_confinement_census_OD0911.log" 'EXACT:|remaining' >> "$L"
grep -E '^  16b:|^  16c:' "$B/_confinement_census_OD0911.log" >> "$L" 2>/dev/null
say "BASELINE remaining before this round: 20 229 143. Stop if moved < 1000."
say "pipeline12 done"
