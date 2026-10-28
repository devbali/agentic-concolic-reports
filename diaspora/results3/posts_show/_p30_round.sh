#!/bin/bash
# ============================================================================
# P30 — the §16f round's TWO coverage passes, BACK TO BACK on ONE list, so the
# before/after differential is clean.
#
#   P30A0   §16e ON, §16f OFF   the baseline, RE-MEASURED under the CURRENT
#                               engine (§88.8 caught coverage.py changing
#                               mid-session; it changed again at 10:26, so
#                               _cov_FINAL_P29A2's 177 is not comparable).
#   P30A    §16e ON, §16f ON    W=3, budget 20000 (DISCIPLINE §16f).
#
# Both on a BYTE COPY of _snapshot_pruned_P29A2.txt (48 451 profiles), so the
# only difference between the two is the flag. Sequential: one coverage pass
# on the box at a time.  Verdict: `P30-ROUND-DONE` / `P30-ROUND-FAILED <tag>`.
# ============================================================================
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
cd "$B" || exit 2
L="$B/_p30_round.log"; : > "$L"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }
T0=$(date +%s)
say "=== P30 ROUND: two passes on _snapshot_pruned_P29A2 (byte copies) ==="
say "  engine coverage.py md5 $(md5sum /home/dev/project/src/concolic_engine/coverage.py | cut -d' ' -f1)"

FORECLOSURE_CONJUNCTIONS=1 FORECLOSURE_SUBCONJUNCTIONS=0 \
  bash "$B/_p30_pass.sh" P30A0 - >> "$L" 2>&1
grep -q 'P30-PASS-DONE P30A0' "$L" || { say "P30-ROUND-FAILED P30A0"; exit 10; }
say "--- P30A0 (§16e only) done at $(( $(date +%s)-T0 ))s"

FORECLOSURE_CONJUNCTIONS=1 FORECLOSURE_SUBCONJUNCTIONS=1 \
FORECLOSURE_CONJUNCTION_WIDTH=3 FORECLOSURE_CONJUNCTION_BUDGET=20000 \
  bash "$B/_p30_pass.sh" P30A - >> "$L" 2>&1
grep -q 'P30-PASS-DONE P30A' "$L" || { say "P30-ROUND-FAILED P30A"; exit 11; }
say "--- P30A (§16e + §16f W=3) done at $(( $(date +%s)-T0 ))s"
say "P30-ROUND-DONE wall=$(( $(date +%s)-T0 ))s"
