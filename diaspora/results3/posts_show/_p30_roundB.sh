#!/bin/bash
# ============================================================================
# P30 ROUND 8 — one construct -> drive -> pass round on the §16f-REFINED
# emission (_p30_emit_P30C.jsonl, 4 093 leaves over 243 demand sets).
#
# WHY NOT THE ORDINAL-FIXPOINT CONSTRUCTOR VERBATIM. §88.7's constructor bases
# each seed on the gap's OWN previous dump. Measured here (§89.2b/§89.4): only
# 45 of round 7's 374 still-demanded cubes are still a demanded §16f leaf, so
# the method is defined for almost none of the new demand. The new leaves have
# no prior dump; the round therefore uses the established base-search
# constructor over the SAME index machinery, and the per-key explain measures
# whether the CONTRADICTED class (ordinal shift, §88.2) returns — which is the
# thing worth knowing.
#
#   S0 hold while notifications' pass/drive runs   S1 rebuild (gaps/index/gaps/construct)
#   S2 drive DRIVE_PAR=2 CONCOLIC_SLOTS=4          S3 explain     S4 pass, §16e+§16f ON
# Verdict: P30-ROUNDB-DONE / P30-ROUNDB-FAILED <stage>
# ============================================================================
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
cd "$B" || exit 2
. "$B/_cage.sh"
TAG="${TAG:-P30B}"
L="$B/_p30_roundB.log"; : >> "$L"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }
T0=$(date +%s); STAMP=20260913
say "=== P30 ROUND 8 ($TAG) on the §16f emission ==="

w=0
while pgrep -f "notifications_index/coverage_report\.py" >/dev/null 2>&1 \
   || systemctl --user list-units 'notif-*' --no-legend 2>/dev/null | grep -q .; do
  [ $((w % 600)) -eq 0 ] && say "S0 HOLD (${w}s): notifications heavy job active"
  sleep 30; w=$((w+30))
done
[ "$w" -gt 0 ] && say "S0 notifications clear after ${w}s"

say "S1 REBUILD from _p30_emit_P30C.jsonl (cap ${P23_MAX_PER_SET:-3}/set)"
OLD_INDEX="$B/_p26_index_P26F.pkl" P23_MAX_PER_SET="${P23_MAX_PER_SET:-3}" \
P23_MAX_TOTAL="${P23_MAX_TOTAL:-0}" \
  bash "$B/_p30_rebuild.sh" "$TAG" "$B/_p30_emit_P30C.jsonl" "$B/_snapshot_pruned_P30C.txt" >> "$L" 2>&1
grep -qE 'P30-REBUILD-DONE' "$B/_p30_rebuild_${TAG}.log" || { say "P30-ROUNDB-FAILED rebuild"; tail -25 "$B/_p30_rebuild_${TAG}.log" | tee -a "$L"; exit 4; }
say "S1 P30-REBUILD-DONE $TAG  gaps=$(python3 -c "import json;print(len(json.load(open('$B/_p30_gaps_${TAG}.json'))))" 2>/dev/null)"

say "S2 DRIVE (DRIVE_PAR=2 CONCOLIC_SLOTS=4 chunk 200)"
before=$(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l)
SEEDSET="$TAG" DRIVE_PAR=2 CONCOLIC_SLOTS=4 \
  P15_MANIFEST="$B/_p15_manifest_${TAG}.json" \
  bash "$B/_p15_drive.sh" "$TAG" 200 >> "$L" 2>&1
DL="$B/_p15_drive_${TAG}.log"
grep -qE 'P15-DRIVE-DONE' "$DL" || { say "P30-ROUNDB-FAILED drive"; tail -20 "$DL" | tee -a "$L"; exit 5; }
after=$(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l)
say "S2 $(grep -E 'P15-DRIVE-DONE' "$DL" | tail -1)   corpus ${before} -> ${after}"

say "S3 EXPLAIN per key"
cage "p30exp${TAG}.scope" 4G \
  env P15_TAG="$TAG" P15_SET="$TAG" P15_GAPS="$B/_p30_gaps_${TAG}.json" \
      P15_MANIFEST="$B/_p15_manifest_${TAG}.json" \
      P15_OUT="$B/_p30_explain_${TAG}.json" \
      PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      python3 -u "$B/_p15_explain.py" > "$B/_p30_explain_${TAG}.log" 2>&1
caged_verdict "p30exp${TAG}.scope" "$B/_p30_explain_${TAG}.log" '^P15-EXPLAIN-DONE' | tee -a "$L"
grep -E 'WALKED|honoured|contradicted|never evaluated|cube literals|^  gaps' \
     "$B/_p30_explain_${TAG}.log" | head -22 | tee -a "$L"

say "S4 PASS ${TAG}2 (OR-refined, §16e+§16f ON, cap 7G)"
STAMP="$STAMP" PASS_CAP=7G FORECLOSURE_CONJUNCTIONS=1 FORECLOSURE_SUBCONJUNCTIONS=1 \
FORECLOSURE_CONJUNCTION_WIDTH=3 FORECLOSURE_CONJUNCTION_BUDGET=20000 \
  bash "$B/_p30_pass.sh" "${TAG}2" "$TAG" "$B/_snapshot_pruned_P30C.txt" >> "$L" 2>&1
grep -qE 'P30-PASS-DONE' "$B/_p30_pass_${TAG}2.log" || {
  say "P30-ROUNDB-FAILED pass"; tail -20 "$B/_p30_pass_${TAG}2.log" | tee -a "$L"; exit 6; }
grep -E '^\[assumptions\]|^\[foreclosure\]|^COMPLETE=|^GENUINE=|^dumps_loaded|^DEMAND_SETS|^CONJ_|^SUBCONJ_|^CONFINEMENT=|peak RSS|distinct outcome' \
     "$B/_p30_pass_${TAG}2.log" | tee -a "$L"
say "P30-ROUNDB-DONE wall=$(( $(date +%s)-T0 ))s"
