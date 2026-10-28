#!/bin/bash
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
. "$B/_cage.sh"
L="$B/_or_census.log"; : > "$L"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }
# another census is running (the confinement agent's, read-only on this
# snapshot) — wait it out, then take the companion slot.
wait_box_clear | tee -a "$L"
say "box clear: no census, no blockaid subsumption"
say "engine: $(md5sum /home/dev/project/src/concolic_engine/coverage.py)"
wait_headroom 3.5 | tee -a "$L"
# SAME snapshot as _confinement_census_GC0911.json, identical flags: the only
# variable is the engine (strict -> OR-monotone).
cage pxconfOR.scope 3500M \
  env DUMP_LIST="$B/_snapshot_pruned_GC0911.txt" PYTHONPATH=/home/dev/project/src \
      JAVA_TOOL_OPTIONS= timeout 10800 \
  python3 -u /home/dev/project/reports/diaspora/tools/confinement_census.py "$B" \
      --json-out "$B/_confinement_census_OR.json" \
  > "$B/_confinement_census_OR.log" 2>&1
caged_verdict pxconfOR.scope "$B/_confinement_census_OR.log" 'EXACT:|remaining' >> "$L"
grep -E '^  16b:|^  16c:|^EXACT:|or_pairs|and_pairs|AND pair' "$B/_confinement_census_OR.log" >> "$L" 2>/dev/null
say "OR census done"
