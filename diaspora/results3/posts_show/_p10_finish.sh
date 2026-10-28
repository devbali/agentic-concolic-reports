#!/bin/bash
# RECOVERY for pipeline 10's lost tail. 10c (the drive) completed — corpus
# 134 063 -> 147 015 (+12 952) — but 10d (prune + re-census) and 10e (the
# realisation table) never ran: the script was EDITED WHILE BASH WAS EXECUTING
# IT (routing the drive through cage_drive), bash resumed at a shifted byte
# offset and fell off the end. Same hazard this drive hit earlier and wrote
# down; repeating it is the defect, not the edit's content.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
. "$B/_cage.sh"
L="$B/_p10_finish.log"; : > "$L"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }

say "waiting for the OR census (it owns the companion slot)"
while systemctl --user is-active pxconfOR.scope >/dev/null 2>&1; do sleep 60; done
say "OR census finished"

say "10d(recovered): snapshot + prune"
find "$B" -maxdepth 1 -name 'dump_*.json' | sort > "$B/_snapshot_after_R2C0911.txt"
say "corpus $(wc -l < "$B/_snapshot_after_R2C0911.txt") dumps"
cage pxpruneR2.scope 3G \
  env DUMP_LIST="$B/_snapshot_after_R2C0911.txt" PYTHONPATH=/home/dev/project/src \
      JAVA_TOOL_OPTIONS= python3 -u "$B/_prune_corpus.py" \
      --out "$B/_snapshot_pruned_R2C0911.txt" >> "$L" 2>&1
say "pruned -> $(wc -l < "$B/_snapshot_pruned_R2C0911.txt" 2>/dev/null) profiles"

say "10e(recovered): realisation table for the R2C0911 round (fixed constructor)"
cage pxrealR2.scope 2G \
  env PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= DRIVE_TAG=R2C0911 \
      timeout 3600 python3 -u "$B/_gc_realise.py" > "$B/_r2_realise.log" 2>&1
caged_verdict pxrealR2.scope "$B/_r2_realise.log" 'GATE OUTCOMES' >> "$L"
grep -E 'REALISED|UNEVALUATED|CONTRADICTED|FLIPPED BACK|realised at least|drive dumps' \
  "$B/_r2_realise.log" >> "$L" 2>/dev/null

say "10f(recovered): re-census on the R2C0911 snapshot"
cage pxconfR2.scope 3500M \
  env DUMP_LIST="$B/_snapshot_pruned_R2C0911.txt" PYTHONPATH=/home/dev/project/src \
      JAVA_TOOL_OPTIONS= timeout 10800 \
  python3 -u /home/dev/project/reports/diaspora/tools/confinement_census.py "$B" \
      --json-out "$B/_confinement_census_R2C0911.json" \
      > "$B/_confinement_census_R2C0911.log" 2>&1
caged_verdict pxconfR2.scope "$B/_confinement_census_R2C0911.log" 'EXACT:|remaining' >> "$L"
grep -E '^  16b:|^  16c:|^EXACT:' "$B/_confinement_census_R2C0911.log" >> "$L" 2>/dev/null
say "p10 recovery done"
