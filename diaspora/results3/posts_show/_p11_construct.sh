#!/bin/bash
# PIPELINE 11 — construction on the OR-REFINED demand, with the pre-registered
# early stop. Waits for the disqualification measurement to free the cage.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
. "$B/_cage.sh"
L="$B/_p11.log"; : > "$L"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }

while systemctl --user is-active pxdisqwhy.scope >/dev/null 2>&1; do sleep 30; done
say "measurement finished; starting construction on the OR-refined demand"

say "11a: emit remaining cubes on the R2C0911 snapshot (OR-refined engine)"
cage pxemitOR.scope 3500M \
  env DUMP_LIST="$B/_snapshot_pruned_R2C0911.txt" PYTHONPATH=/home/dev/project/src \
      JAVA_TOOL_OPTIONS= EMIT_REACHABLE_ONLY=0 REACH_SPLIT=1 \
      REACH_OUT=_reach_split_OR.json EMIT_OUT="$B/_enum_emit_OR.json" \
      EMIT_MAX_PER_SET=8 timeout 7200 python3 -u "$B/_exact_enum_emit.py" \
      --json-out "$B/_enum_OR.json" > "$B/_enum_emit_OR.log" 2>&1
caged_verdict pxemitOR.scope "$B/_enum_emit_OR.log" '^EMIT:' >> "$L"
grep -E '^EXACT:|^EMIT:|REACHABLE remaining|MULTI-GATE' "$B/_enum_emit_OR.log" >> "$L" 2>/dev/null

say "11b: construct per gate combination (fixed constructor, 8 bases)"
cage pxconsOR.scope 2G \
  env EMIT_IN="$B/_enum_emit_OR.json" DUMP_LIST="$B/_rootbase_p5.txt" \
      VARIANTS_PER_COMBO=8 PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      timeout 3600 python3 -u "$B/_construct_by_gate.py" > "$B/_construct_OR.log" 2>&1
caged_verdict pxconsOR.scope "$B/_construct_OR.log" 'constructed seeds' >> "$L"
grep -E 'cubes emitted|GATE COMBINATIONS|constructed seeds|OUT-OF-DOMAIN' "$B/_construct_OR.log" >> "$L" 2>/dev/null

say "11c: drive (caged, so it counts toward the slice)"
cage_drive pxdrive_OR0911.scope 3G env CONCOLIC_SLOTS=2 DRIVE_PAR=2 \
  bash "$B/_demand_drive.sh" OR0911 200 >> "$L" 2>&1
grep -E 'corpus after|abort|toxic' "$B/_demand_drive_OR0911.log" 2>/dev/null | tail -4 >> "$L"

say "11d: prune + re-census — the EARLY-STOP test"
find "$B" -maxdepth 1 -name 'dump_*.json' | sort > "$B/_snapshot_after_OR0911.txt"
cage pxpruneOR.scope 3G \
  env DUMP_LIST="$B/_snapshot_after_OR0911.txt" PYTHONPATH=/home/dev/project/src \
      JAVA_TOOL_OPTIONS= python3 -u "$B/_prune_corpus.py" \
      --out "$B/_snapshot_pruned_OR0911.txt" >> "$L" 2>&1
cage pxconfOR2.scope 3500M \
  env DUMP_LIST="$B/_snapshot_pruned_OR0911.txt" PYTHONPATH=/home/dev/project/src \
      JAVA_TOOL_OPTIONS= timeout 10800 \
  python3 -u /home/dev/project/reports/diaspora/tools/confinement_census.py "$B" \
      --json-out "$B/_confinement_census_OR0911.json" \
      > "$B/_confinement_census_OR0911.log" 2>&1
caged_verdict pxconfOR2.scope "$B/_confinement_census_OR0911.log" 'EXACT:|remaining' >> "$L"
grep -E '^  16b:|^  16c:' "$B/_confinement_census_OR0911.log" >> "$L" 2>/dev/null
say "PRE-REGISTERED EARLY STOP: R2C0911 (12 952 seeds) moved remaining by 32."
say "If this round moves it by < 1000, the method is exhausted on this endpoint"
say "and this drive STOPS constructing and reports the number."
say "pipeline11 done"
