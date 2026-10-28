#!/bin/bash
# ============================================================================
# P30 ROUND 8 — the ORDINAL-FIXPOINT round ITERATED, on the gaps that are
# STILL demanded under DISCIPLINE §16f.
#
# Same method as round 7 (§88.7): the base of every seed is the gap's OWN
# most recent dump, and every demanded value is written at the raw ordinal
# THAT dump actually minted the canonical at. Round 8 differs only in the
# base generation (round 7's dumps) and in the gap list, which is filtered to
# the cubes §16f has NOT foreclosed.
#
#   S0 hold while any notifications pass/drive runs (they have priority)
#   S1 per-key record of round 7 (_p29_perkey.py over _p15_manifest_P29A)
#   S2 construct  (_p30_construct.py, SEEDSET=P30A)
#   S3 drive      DRIVE_PAR=2 CONCOLIC_SLOTS=4, chunk 200
#   S4 explain    (_p15_explain.py, verbatim)
#   S5 pass       P30A2, OR-refined, §16e+§16f ON, cap 7G, checkpointed
# Verdict: P30-ROUND8-DONE / P30-ROUND8-FAILED <stage>
# ============================================================================
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
cd "$B" || exit 2
. "$B/_cage.sh"
L="$B/_p30_round8.log"; : >> "$L"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }
STAMP=20260913
GAPS="${GAPS:-$B/_p30_gaps_live.json}"
T0=$(date +%s)
say "=== P30 ROUND 8 (ordinal fixpoint, §16f-filtered gaps) ==="
[ -s "$GAPS" ] || { say "P30-ROUND8-FAILED no gap list $GAPS"; exit 2; }
say "  gaps: $(python3 -c "import json;print(len(json.load(open('$GAPS'))))") still demanded"

w=0
while pgrep -f "notifications_index/coverage_report\.py" >/dev/null 2>&1 \
   || systemctl --user list-units 'notif-*' --no-legend 2>/dev/null | grep -q .; do
  [ $((w % 600)) -eq 0 ] && say "S0 HOLD (${w}s): notifications heavy job active"
  sleep 30; w=$((w+30))
done
[ "$w" -gt 0 ] && say "S0 notifications clear after ${w}s"

say "S1 PER-KEY record of round 7 (over the FULL round-6 gap list; the §16f
     filter is applied to the per-key record afterwards, because _p29_perkey.py
     joins the manifest against every gap it seeded)"
cage "p30perkey.scope" 5G \
  env P15_TAG=P29A P15_SET=P29A P15_GAPS="$B/_p26_gaps_P26F.json" \
      P15_MANIFEST="$B/_p15_manifest_P29A.json" \
      P29_OUT="$B/_p30_perkey_P29A.json" \
      PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      python3 -u "$B/_p29_perkey.py" > "$B/_p30_perkey.log" 2>&1
[ -s "$B/_p30_perkey_P29A.json" ] || { say "P30-ROUND8-FAILED perkey"; tail -20 "$B/_p30_perkey.log" | tee -a "$L"; exit 3; }
grep -E 'gaps|walked|honoured|contradicted|never' "$B/_p30_perkey.log" | head -12 | tee -a "$L"

say "S1b FILTER the per-key record to the gaps §16f still demands"
python3 - "$B/_p30_perkey_P29A.json" "$GAPS" "$B/_p30_perkey_live.json" <<'PY' | tee -a "$L"
import json, sys
per = json.load(open(sys.argv[1]))
keep = {g["id"] for g in json.load(open(sys.argv[2]))}
out = {k: v for k, v in per.items() if k in keep}
json.dump(out, open(sys.argv[3], "w"))
print(f"  per-key {len(per)} -> {len(out)} still demanded "
      f"({sum(1 for v in out.values() if not v['walked'])} non-walking)")
PY

say "S2 CONSTRUCT (ordinal fixpoint, SEEDSET=P30A)"
env SEEDSET=P30A P30_PERKEY="$B/_p30_perkey_live.json" P30_GAPS="$GAPS" \
    PYTHONPATH=/home/dev/project/src \
    python3 -u "$B/_p30_construct.py" > "$B/_p30_construct.log" 2>&1
grep -qE '^P30-CONSTRUCT-DONE' "$B/_p30_construct.log" || { say "P30-ROUND8-FAILED construct"; tail -20 "$B/_p30_construct.log" | tee -a "$L"; exit 4; }
grep -E 'seeds|literals written|^   |unwritable|P30-CONSTRUCT-DONE' "$B/_p30_construct.log" | tee -a "$L"

say "S3 DRIVE (DRIVE_PAR=2 CONCOLIC_SLOTS=4 chunk 200)"
before=$(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l)
SEEDSET=P30A DRIVE_PAR=2 CONCOLIC_SLOTS=4 \
  P15_MANIFEST="$B/_p15_manifest_P30A.json" \
  bash "$B/_p15_drive.sh" P30A 200 >> "$L" 2>&1
DL="$B/_p15_drive_P30A.log"
grep -qE 'P15-DRIVE-DONE' "$DL" || { say "P30-ROUND8-FAILED drive"; tail -20 "$DL" | tee -a "$L"; exit 5; }
after=$(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l)
say "S3 $(grep -E 'P15-DRIVE-DONE' "$DL" | tail -1)   corpus ${before} -> ${after}"

say "S4 EXPLAIN per key"
cage "p30exp.scope" 4G \
  env P15_TAG="P30A" P15_SET="P30A" P15_GAPS="$GAPS" \
      P15_MANIFEST="$B/_p15_manifest_P30A.json" \
      P15_OUT="$B/_p30_explain_P30A.json" \
      PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      python3 -u "$B/_p15_explain.py" > "$B/_p30_explain_P30A.log" 2>&1
caged_verdict "p30exp.scope" "$B/_p30_explain_P30A.log" '^P15-EXPLAIN-DONE' | tee -a "$L"
grep -E 'WALKED|honoured|contradicted|never evaluated|cube literals|^  gaps' \
     "$B/_p30_explain_P30A.log" | head -20 | tee -a "$L"

say "S5 PASS P30A2 (OR-refined, §16e+§16f ON, cap 7G)"
STAMP="$STAMP" PASS_CAP=7G FORECLOSURE_CONJUNCTIONS=1 FORECLOSURE_SUBCONJUNCTIONS=1 \
FORECLOSURE_CONJUNCTION_WIDTH=3 FORECLOSURE_CONJUNCTION_BUDGET=20000 \
  bash "$B/_p30_pass.sh" P30A2 P30A "$B/_snapshot_pruned_P30A.txt" >> "$L" 2>&1
grep -qE 'P30-PASS-DONE' "$B/_p30_pass_P30A2.log" || {
  say "P30-ROUND8-FAILED pass"; tail -20 "$B/_p30_pass_P30A2.log" | tee -a "$L"; exit 6; }
grep -E '^\[assumptions\]|^\[foreclosure\]|^COMPLETE=|^GENUINE=|^dumps_loaded|^DEMAND_SETS|^CONJ_|^SUBCONJ_|^CONFINEMENT=|peak RSS' \
     "$B/_p30_pass_P30A2.log" | tee -a "$L"
say "P30-ROUND8-DONE wall=$(( $(date +%s)-T0 ))s"
