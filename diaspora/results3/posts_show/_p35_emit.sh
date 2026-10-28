#!/bin/bash
# =============================================================================
# P31 — the OR-refined census/emitter under DISCIPLINE §16f, with its OWN
# reproduction control in the SAME process (CENSUS_MODES).
#
#   prod  the booked product census  (CENSUS_LEAF_ENUM off — §86.1's code path,
#         byte-for-byte; this is the number of record for the list)
#   enum  the LEAF ENUMERATION with §16e/§16f OFF — MUST equal `prod`. A leaf
#         under §16b IS a full assignment, so the two counting methods compute
#         the same quantity two ways; the equality is the check that the new
#         machinery did not move anything.
#   16f   §16e + §16f (W=3, budget 20 000), the corrected residue. EMITS.
#
#   usage: bash _p31_emit.sh <TAG> <LIST>        cap 7G, detached by the caller
# Verdict: `P31-EMIT-DONE <TAG>` / `P31-EMIT-FAILED <TAG>`.
#
# P35 COPY, 2026-09-15. ONE change: it passes WITHDRAWN_PAIRS through to
# `_p26_emit_or.py`. `_p31_emit.sh` never set it, so the emitter recomputed
# confinement FROM THE CORPUS and silently re-derived the PRE-GATE licences --
# the first P35 census came back byte-identical to round 10 (confined 2701,
# sets 836, REMAINING 4371 / 3868) even though 564 pairs had been withdrawn.
# The emitter always supported it (`_p26_emit_or.py:91-94`); only the wrapper
# did not. Harmless before the gate existed (nothing was ever withdrawn);
# wrong the moment one is. `_p31_emit.sh` is NOT edited -- it is the emission
# of record for rounds 8-10.
# =============================================================================
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
cd "$B" || exit 2
. "$B/_cage.sh"
TAG="${1:?usage: _p31_emit.sh <TAG> <LIST>}"
LIST="${2:-$B/_snapshot_pruned_P30B2.txt}"
L="$B/_p31_emit_${TAG}.log"; : > "$L"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }
say "=== P31 EMIT $TAG  list=$(basename "$LIST") ($(wc -l < "$LIST") profiles) ==="
say "  modes=${CENSUS_MODES:-prod,enum,16f}  W=${FORECLOSURE_CONJUNCTION_WIDTH:-3}"
if [ "${P31_SKIP_ONEPASS:-0}" = 1 ]; then
  # `_cage.sh:wait_no_pass` blocks on ANY coverage_report.py. That was the
  # memory-era one-pass rule; the coordinator dropped it on 2026-09-13 when the
  # owner made the cage a flat 32 G. `_cage.sh` is SHARED and is not edited --
  # the function is overridden here, in this script only.
  say "  one-pass rule SKIPPED (P31_SKIP_ONEPASS=1); memory invariant and the"
  say "  gate CPU guard still apply. $(pgrep -af 'python3.*coverage_report\.py' 2>/dev/null | grep -v shell-snapshots | sed 's#.*results3/##;s# .*##' | tr '\n' ' ')"
else
  wait_no_pass | tee -a "$L"
fi
cage "p31emit${TAG}.scope" "${EMIT_CAP_MEM:-7G}" \
  /usr/bin/time -v -o "$B/_p31_emit_${TAG}.time" \
  env DUMP_LIST="$LIST" \
      CENSUS_MODES="${CENSUS_MODES:-prod,enum,16f}" \
      FORECLOSURE_CONJUNCTION_WIDTH="${FORECLOSURE_CONJUNCTION_WIDTH:-3}" \
      FORECLOSURE_CONJUNCTION_BUDGET="${FORECLOSURE_CONJUNCTION_BUDGET:-20000}" \
      ALSO_16B="${ALSO_16B:-0}" \
      WITHDRAWN_PAIRS="${WITHDRAWN_PAIRS:-}" \
      MAX_CLIQUES=16384 CUBE_CAP=20000 \
      EMIT_OUT="$B/_p31_emit_${TAG}" \
      EMIT_MAX_PER_SET="${EMIT_MAX_PER_SET:-0}" EMIT_CAP="${EMIT_CAP:-0}" \
      JSON_OUT="$B/_p31_census_${TAG}.json" \
      SUBCONJ_CLASSES_OUT="$B/_p31_subconj_classes_${TAG}.json" \
      PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      python3 -u "$B/_p26_emit_or.py" >> "$B/_p31_emit_${TAG}.out" 2>&1
say "P31 EMIT exit=$?"
if grep -q 'P26-EMIT-DONE' "$B/_p31_emit_${TAG}.out"; then
  grep -E 'LEAF ENUM ON|MODE |REPRODUCTION CHECK|§16e:|§16f:|EMITTED_CUBES|base coupling|=== PROJECTION|  pairs:' \
      "$B/_p31_emit_${TAG}.out" | tee -a "$L"
  grep -E 'Maximum resident|Elapsed' "$B/_p31_emit_${TAG}.time" 2>/dev/null | tee -a "$L"
  say "P31-EMIT-DONE $TAG"
else
  caged_verdict "p31emit${TAG}.scope" "$B/_p31_emit_${TAG}.out" 'P26-EMIT-DONE' | tee -a "$L"
  tail -25 "$B/_p31_emit_${TAG}.out" | sed 's/^/    /' | tee -a "$L"
  say "P31-EMIT-FAILED $TAG"; exit 10
fi
