#!/bin/bash
# ============================================================================
# P29 ROUND 7 — the ORDINAL-FIXPOINT round (§88.2's remedy), end to end.
#
# A DIFFERENT METHOD from the six P26 rounds, which is why §87.3 item 3 does
# not forbid it: the base of every seed is the gap's OWN round-6 dump (a run
# whose upstream pins are already realised), and every demanded value is
# written at the raw ordinal THAT dump actually minted the canonical at.
# Plus the 20 render cubes are steered for the first time, through the
# RENDER_TEXT_SOURCE input (§88.4).
#
#   S0 wait for notifications' pass/drive to clear (coordinator rule)
#   S1 drive   451 seeds, DRIVE_PAR=2 CONCOLIC_SLOTS=4, chunk 200
#   S2 explain per key (_p15_explain.py, verbatim)
#   S3 pass    P29A2, OR-refined, §16e ON, cap 7G, checkpointed
# Verdict: P29-ROUND7-DONE / P29-ROUND7-FAILED <stage>
# ============================================================================
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
cd "$B" || exit 2
. "$B/_cage.sh"
L="$B/_p29_round7.log"; : >> "$L"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }
STAMP=20260913

say "=== P29 ROUND 7 (ordinal fixpoint) ==="
# ---- S0 coordinator rule: nothing of ours beside notifications' heavy jobs
w=0
while pgrep -f "notifications_index/coverage_report\.py" >/dev/null 2>&1 \
   || systemctl --user list-units 'notif-*' --no-legend 2>/dev/null | grep -q .; do
  [ $((w % 600)) -eq 0 ] && say "S0 HOLD (${w}s): notifications heavy job active"
  sleep 30; w=$((w+30))
done
[ "$w" -gt 0 ] && say "S0 notifications clear after ${w}s"

# ---- S1 drive
before=$(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l)
say "S1 DRIVE 451 seeds (SEEDSET=P29A, DRIVE_PAR=2, CONCOLIC_SLOTS=4)"
SEEDSET=P29A DRIVE_PAR=2 CONCOLIC_SLOTS=4 \
  P15_MANIFEST="$B/_p15_manifest_P29A.json" \
  bash "$B/_p15_drive.sh" P29A 200 >> "$L" 2>&1
DL="$B/_p15_drive_P29A.log"
grep -qE 'P15-DRIVE-DONE' "$DL" || { say "P29-ROUND7-FAILED drive"; tail -20 "$DL" | tee -a "$L"; exit 5; }
after=$(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l)
say "S1 $(grep -E 'P15-DRIVE-DONE' "$DL" | tail -1)   corpus ${before} -> ${after}"

# ---- S2 explain
say "S2 EXPLAIN per key"
cage "p29exp.scope" 4G \
  env P15_TAG="P29A" P15_SET="P29A" \
      P15_GAPS="$B/_p26_gaps_P26F.json" \
      P15_MANIFEST="$B/_p15_manifest_P29A.json" \
      P15_OUT="$B/_p29_explain_P29A.json" \
      PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      python3 -u "$B/_p15_explain.py" > "$B/_p29_explain_P29A.log" 2>&1
caged_verdict "p29exp.scope" "$B/_p29_explain_P29A.log" '^P15-EXPLAIN-DONE' | tee -a "$L"
grep -E 'WALKED|honoured|contradicted|never evaluated|cube literals|FIRST FAILING|^   ' \
     "$B/_p29_explain_P29A.log" | head -30 | tee -a "$L"

# ---- S3 pass on the extended corpus
say "S3 PASS P29A2 (OR-refined, §16e ON, cap 7G)"
STAMP="$STAMP" PASS_CAP=7G FORECLOSURE_CONJUNCTIONS=1 \
  bash "$B/_p29_pass.sh" P29A2 P29A "$B/_snapshot_pruned_P26F2.txt" >> "$L" 2>&1
grep -qE 'P29-PASS-DONE' "$B/_p29_pass_P29A2.log" || {
  say "P29-ROUND7-FAILED pass"; tail -20 "$B/_p29_pass_P29A2.log" | tee -a "$L"; exit 6; }
grep -E '^\[assumptions\]|^\[foreclosure\]|^COMPLETE=|^GENUINE=|^dumps_loaded|^DEMAND_SETS|^CONJ_|^CONFINEMENT=|peak RSS' \
     "$B/_p29_pass_P29A2.log" | tee -a "$L"
say "P29-ROUND7-DONE"
