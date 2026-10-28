#!/bin/bash
# =============================================================================
# P31 ENGINE CONTROL — §89.1's procedure, forced again by a mid-round edit.
#
# `src/concolic_engine/coverage.py` changed at 2026-09-13 21:26:36, FIFTEEN
# SECONDS before this round's S1 relaunch, by another campaign:
#     P30A0 / P30A / P30C / round 8   md5 7a480695e04f9f0e4ecd5d9cd39e91a7
#     P31 round 9                     md5 d08df10a67a3f07dc41e9f2a764b70d3
# Every number P31's YIELD is compared against (P30C: MISSING=161, OR-refined
# remaining 4 093 over 243 sets) was measured under the OLD engine. Moving
# corpus AND engine at once is exactly the confound §88.8 recorded and §89.1
# spent a pass retiring; it is not inherited silently a second time.
#
# WHAT IS AND IS NOT AFFECTED (measured by import, not assumed):
#   S6 THE TEST of the round        `_p15_explain.py` imports only
#      (contradicted length gates)  concolic_engine.assumptions (unchanged
#                                   since 2026-09-11) + coverage_assumptions.
#                                   ENGINE-INDEPENDENT. The round's verdict
#                                   stands whatever this control says.
#   S1/S7 passes                    coverage_report.py -> the engine. AFFECTED.
#   S2/S8 emissions                 `_p23_enum.py` imports CoverageChecker,
#                                   _maximal_cliques, minimal_subconjunction...
#                                   AFFECTED.
#
# THE CONTROL: re-run the P30C configuration — the SAME list, the same flags —
# under the CURRENT engine, and compare to P30C's MISSING=161. Equal means the
# change moved nothing on this endpoint and P30's numbers carry forward (which
# is what §89.1 found last time); different means P31's yield must be read
# against this number, not against 161.
#
#   usage: bash _p31_control.sh          (~7-15 min, cap 7G, one stage)
# Verdict: P31-CONTROL-DONE / P31-CONTROL-FAILED
# =============================================================================
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
cd "$B" || exit 2
. "$B/_cage.sh"; . "$B/_p31_guard.sh"
export P31_SKIP_ONEPASS=1
L="$B/_p31_control.log"; : > "$L"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }
say "=== P31 ENGINE CONTROL — P30C's list under the CURRENT engine ==="
say "  P30C engine md5 7a480695e04f9f0e4ecd5d9cd39e91a7  MISSING=161"
say "  now         md5 $(md5sum /home/dev/project/src/concolic_engine/coverage.py | cut -d' ' -f1)"
cp -f "$B/_snapshot_pruned_P30C.txt" "$B/_snapshot_pruned_P31CTLE.txt" || exit 3
say "  list $(wc -l < "$B/_snapshot_pruned_P31CTLE.txt") profiles (byte copy of P30C's)"
stage_begin CTLE 7
STAMP=20260913 PASS_CAP=7G FORECLOSURE_CONJUNCTIONS=1 FORECLOSURE_SUBCONJUNCTIONS=1 \
FORECLOSURE_CONJUNCTION_WIDTH=3 FORECLOSURE_CONJUNCTION_BUDGET=20000 \
  bash "$B/_p31_pass.sh" P31CTLE - "$B/_snapshot_pruned_P31CTLE.txt" >> "$L" 2>&1
stage_end CTLE
grep -qE 'P31-PASS-DONE' "$B/_p31_pass_P31CTLE.log" || { say "P31-CONTROL-FAILED"; tail -20 "$B/_p31_pass_P31CTLE.log" | tee -a "$L"; exit 4; }
grep -E '^\[foreclosure\]|^COMPLETE=|^GENUINE=|^dumps_loaded|^DEMAND_SETS|^CONJ_|^SUBCONJ_|^CONFINEMENT=' \
     "$B/_p31_pass_P31CTLE.log" | tee -a "$L"
m=$(grep -oE 'MISSING=[0-9]+' "$B/_p31_pass_P31CTLE.log" | head -1 | cut -d= -f2)
say "CONTROL: MISSING=$m   P30C under the old engine: 161   -> $([ "$m" = 161 ] && echo 'ENGINE CHANGE MOVED NOTHING; P30 numbers carry forward' || echo "ENGINE CHANGE MOVED IT BY $((m-161)); P31 yield must be read against $m, not 161")"
say "P31-CONTROL-DONE"
