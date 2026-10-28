#!/bin/bash
# PIPELINE 13b — class (b): is a matched context CONSTRUCTIBLE for tonight's
# UNDECIDABLE decisions? Build one-flip seeds from VERBATIM bases, drive at
# most 200 runs, then apply §16c's exact keying to the result.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
. "$B/_cage.sh"
L="$B/_p13b.log"; : > "$L"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }
TAG=OF0911B

say "13b-1: the CURRENT undecidable list (OD0911 census)"
python3 -u "$B/_mk_undec_OD.py" > "$B/_mk_undec_OD.log" 2>&1
grep -E 'UNDECIDABLE now|wrote' "$B/_mk_undec_OD.log" >> "$L"

wait_alone p13b | tee -a "$L"
# HAZARD, closed before it fires: p12 left 13 080 constructed seeds in
# _demandR_<variant>.json. _oneflip_seeds.py writes only the variants it has
# bases for, so a stale file would be re-driven as if it were this round.
say "13b-1b: clearing p12's seed files ($(find "$B" -maxdepth 1 -name '_demandR_*.json' | wc -l) files)"
for f in "$B"/_demandR_*.json; do [ -e "$f" ] && mv "$f" "$f.p12"; done
say "13b-2: one-flip seeds from verbatim bases [2G]"
cage p13flip.scope 2G env PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
  UNDEC_IN=_undecidable_kinds_OD.json BASES_PER_DECISION=4 \
  DUMP_LIST="$B/_snapshot_pruned_OD0911.txt" \
  python3 -u "$B/_oneflip_seeds.py" > "$B/_oneflip_seeds_OD.log" 2>&1
caged_verdict p13flip.scope "$B/_oneflip_seeds_OD.log" 'one-flip seeds built' >> "$L"
grep -E 'one-flip seeds built|ADDRESSABLE|seeds ->' "$B/_oneflip_seeds_OD.log" >> "$L"

say "13b-3: TRIM to the 200-run budget (pre-registered cap)"
python3 -u "$B/_trim_seeds.py" 200 >> "$L" 2>&1

say "13b-4: drive (caged, 3G)"
cage_drive p13drive.scope 3G bash "$B/_demand_drive.sh" "$TAG" 100 >> "$L" 2>&1
grep -E 'corpus after|seeds ->' "$B/_demand_drive_${TAG}.log" >> "$L" 2>/dev/null

say "13b-5: §16c exact keying on the round + its bases [2G]"
cage p13ctx.scope 2G env PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
  UNDEC_IN=_undecidable_kinds_OD.json PATTERNS="dump_*${TAG}*.json" \
  DUMP_LIST="$B/_snapshot_pruned_OD0911.txt" OUT=_matched_ctx_${TAG}.json \
  python3 -u "$B/_matched_ctx_check.py" > "$B/_matched_ctx_${TAG}.log" 2>&1
caged_verdict p13ctx.scope "$B/_matched_ctx_${TAG}.log" 'MATCHED CTX DONE' >> "$L"
grep -E 'MATCHED CONTEXT NOW EXISTS|STILL NO MATCHED' "$B/_matched_ctx_${TAG}.log" >> "$L"
say "pipeline13b done"
