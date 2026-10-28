#!/bin/bash
# =============================================================================
# P30 — the OR-refined census/emitter under DISCIPLINE §16f, with its OWN
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
#   usage: bash _p30_emit.sh <TAG> <LIST>        cap 7G, detached by the caller
# Verdict: `P30-EMIT-DONE <TAG>` / `P30-EMIT-FAILED <TAG>`.
# =============================================================================
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
cd "$B" || exit 2
. "$B/_cage.sh"
TAG="${1:?usage: _p30_emit.sh <TAG> <LIST>}"
LIST="${2:-$B/_snapshot_pruned_P30A.txt}"
L="$B/_p30_emit_${TAG}.log"; : > "$L"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }
say "=== P30 EMIT $TAG  list=$(basename "$LIST") ($(wc -l < "$LIST") profiles) ==="
say "  modes=${CENSUS_MODES:-prod,enum,16f}  W=${FORECLOSURE_CONJUNCTION_WIDTH:-3}"
wait_no_pass | tee -a "$L"
cage "p30emit${TAG}.scope" "${EMIT_CAP_MEM:-7G}" \
  /usr/bin/time -v -o "$B/_p30_emit_${TAG}.time" \
  env DUMP_LIST="$LIST" \
      CENSUS_MODES="${CENSUS_MODES:-prod,enum,16f}" \
      FORECLOSURE_CONJUNCTION_WIDTH="${FORECLOSURE_CONJUNCTION_WIDTH:-3}" \
      FORECLOSURE_CONJUNCTION_BUDGET="${FORECLOSURE_CONJUNCTION_BUDGET:-20000}" \
      ALSO_16B="${ALSO_16B:-0}" \
      MAX_CLIQUES=16384 CUBE_CAP=20000 \
      EMIT_OUT="$B/_p30_emit_${TAG}" \
      EMIT_MAX_PER_SET="${EMIT_MAX_PER_SET:-0}" EMIT_CAP="${EMIT_CAP:-0}" \
      JSON_OUT="$B/_p30_census_${TAG}.json" \
      SUBCONJ_CLASSES_OUT="$B/_p30_subconj_classes.json" \
      PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      python3 -u "$B/_p26_emit_or.py" >> "$B/_p30_emit_${TAG}.out" 2>&1
say "P30 EMIT exit=$?"
if grep -q 'P26-EMIT-DONE' "$B/_p30_emit_${TAG}.out"; then
  grep -E 'LEAF ENUM ON|MODE |REPRODUCTION CHECK|§16e:|§16f:|EMITTED_CUBES|base coupling|=== PROJECTION|  pairs:' \
      "$B/_p30_emit_${TAG}.out" | tee -a "$L"
  grep -E 'Maximum resident|Elapsed' "$B/_p30_emit_${TAG}.time" 2>/dev/null | tee -a "$L"
  say "P30-EMIT-DONE $TAG"
else
  caged_verdict "p30emit${TAG}.scope" "$B/_p30_emit_${TAG}.out" 'P26-EMIT-DONE' | tee -a "$L"
  tail -25 "$B/_p30_emit_${TAG}.out" | sed 's/^/    /' | tee -a "$L"
  say "P30-EMIT-FAILED $TAG"; exit 10
fi
