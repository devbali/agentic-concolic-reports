#!/bin/bash
# PIPELINE 7 — the ONE-FLIP campaign against UNDECIDABILITY (§68.3).
# Seeds are JRuby time, not solver time. The re-census obeys the one-pass rule.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
. "$B/_cage.sh"
L="$B/_pipeline7.log"; : > "$L"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }

# never start while this drive's own §16c pass is still running
say "§16c pass was killed by the coordinator at 08:4x (§70); proceeding"
grep -E '^\[assumptions\]|^(COMPLETE|GENUINE|dumps_loaded|DEMAND_SETS|peak RSS)|confin' \
  "$B/_covC_p5_conf.log" 2>/dev/null | head -12 >> "$L"

say "7a: build one-flip seeds (ADDRESSABLE decisions only) [cap 2G]"
cage pxoneflip.scope 2G \
  env DUMP_LIST="$B/_rootbase_p5.txt" BASES_PER_DECISION=4 \
      PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      timeout 3600 python3 -u "$B/_oneflip_seeds.py" \
  > "$B/_oneflip_seeds.log" 2>&1
caged_verdict pxoneflip.scope "$B/_oneflip_seeds.log" 'one-flip seeds built' >> "$L"
grep -E 'ADDRESSABLE targets|one-flip seeds built|seeds ->|no parseable|lacks the key' \
  "$B/_oneflip_seeds.log" >> "$L" 2>/dev/null

say "7b: drive them (unique LABEL_SUFFIX, abort-checked, slot-limited)"
free -g | sed -n 2p >> "$L"
cage_drive pxdrive_OF0911.scope 3G env CONCOLIC_SLOTS=2 DRIVE_PAR=2 \
  bash "$B/_demand_drive.sh" OF0911 200 >> "$L" 2>&1
grep -E 'seeds ->|corpus after|abort|toxic|consumed' "$B/_demand_drive_OF0911.log" \
  2>/dev/null | tail -12 >> "$L"

say "7c: re-snapshot + exact prune"
find "$B" -maxdepth 1 -name 'dump_*.json' | sort > "$B/_snapshot_after_OF0911.txt"
say "corpus now $(wc -l < "$B/_snapshot_after_OF0911.txt") dumps"
# COMPANION (coordinator 2026-09-11): a census needs no exclusive slot —
# only the headroom rule. The slot gates below were removed for that reason.
wait_headroom 3 | tee -a "$L"
cage pxpruneOF.scope 3G \
  env DUMP_LIST="$B/_snapshot_after_OF0911.txt" PYTHONPATH=/home/dev/project/src \
      JAVA_TOOL_OPTIONS= python3 -u "$B/_prune_corpus.py" \
      --out "$B/_snapshot_pruned_OF0911.txt" >> "$L" 2>&1
say "pruned -> $(wc -l < "$B/_snapshot_pruned_OF0911.txt" 2>/dev/null) profiles"

say "7d: RE-CENSUS (3.5G, one-pass rule, <=5G room)"
# COMPANION (coordinator 2026-09-11): a census needs no exclusive slot —
# only the headroom rule. The slot gates below were removed for that reason.
wait_headroom 3 | tee -a "$L"
cage pxconf2.scope 3500M \
  env DUMP_LIST="$B/_snapshot_pruned_OF0911.txt" PYTHONPATH=/home/dev/project/src \
      JAVA_TOOL_OPTIONS= timeout 7200 \
  python3 -u /home/dev/project/reports/diaspora/tools/confinement_census.py "$B" \
      --json-out "$B/_confinement_census_OF0911.json" \
  > "$B/_confinement_census_OF0911.log" 2>&1
caged_verdict pxconf2.scope "$B/_confinement_census_OF0911.log" 'EXACT:|remaining' >> "$L"
say "pipeline7 done"
