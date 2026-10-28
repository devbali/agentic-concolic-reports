#!/bin/bash
# CAGED PIPELINE 4 — the SEPARABLE-EFFECTS line (owner reframe 2026-09-11).
# Tier 2 as an IndependenceAssumption does NOT ship. Caps sum to <= 4 G.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
. "$B/_cage.sh"
L="$B/_pipeline4.log"; : > "$L"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }

while systemctl --user is-active pxwhatif.scope >/dev/null 2>&1; do sleep 20; done
caged_verdict pxwhatif.scope "$B/_whatif_indep.log" '^EXACT:' >> "$L"

say "4a: footprint census (matched-context differential) [cap 3500M]"
cage pxfp.scope 3500M \
  env DUMP_LIST="$B/_snapshot_pruned_p5.txt" PYTHONPATH=/home/dev/project/src \
      JAVA_TOOL_OPTIONS= timeout 3600 python3 -u "$B/_footprint_census.py" \
  > "$B/_footprint_census.log" 2>&1
caged_verdict pxfp.scope "$B/_footprint_census.log" 'FOOTPRINT CENSUS' >> "$L"

say "4b: separable/overlapping/undecidable over the 1733 [cheap, inline]"
python3 -u "$B/_sep_pairs.py" > "$B/_sep_pairs.log" 2>&1
tail -30 "$B/_sep_pairs.log" >> "$L"

say "4c: priced collapse — census with the separability reduction [cap 3500M]"
cage pxsep.scope 3500M \
  env DUMP_LIST="$B/_snapshot_pruned_p5.txt" PYTHONPATH=/home/dev/project/src \
      JAVA_TOOL_OPTIONS= timeout 3600 python3 -u "$B/_whatif_separable.py" \
  > "$B/_whatif_separable.log" 2>&1
caged_verdict pxsep.scope "$B/_whatif_separable.log" '^EXACT:' >> "$L"

say "4d: re-keying magnitude (kept from the earlier queue) [cap 3500M]"
cage pxwfmerge.scope 3500M \
  env DUMP_LIST="$B/_snapshot_pruned_p5.txt" PYTHONPATH=/home/dev/project/src \
      JAVA_TOOL_OPTIONS= timeout 3600 python3 -u "$B/_whatif_wf_merge.py" \
  > "$B/_whatif_wf_merge.log" 2>&1
caged_verdict pxwfmerge.scope "$B/_whatif_wf_merge.log" '^EXACT:' >> "$L"
say "pipeline4 done"
