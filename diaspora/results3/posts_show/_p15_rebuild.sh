#!/bin/bash
# =============================================================================
# P15 — REBUILD THE CONSTRUCTION INPUTS AFTER A PASS (index -> classify ->
# construct). One command between "the pass landed" and "the next drive".
#
#   usage: bash _p15_rebuild.sh <TAG> [PREVTAG]
#            TAG      the round whose pass just finished (e.g. P15C): reads
#                     _snapshot_pruned_<TAG>.txt, _cov_<tag>.ckpt.jsonl,
#                     _cov_FINAL_<TAG>_<STAMP>.json
#            PREVTAG  label used to ARCHIVE the seeds/manifest of the round
#                     that has just been driven, so its per-key explanation
#                     stays reproducible after the constructor overwrites
#                     `_p15_manifest.json` (which has a fixed path).
#
# Each stage is caged and judged by its own verdict line. PARTS stays
# `_parts_OD0911.json` unless PARTS_IN is exported: `_p15_classify.py` falls
# back to member-set CONTAINMENT when a checkpoint record's digest is not in
# the parts file, and reports `unmatched` — read that number, and only re-run
# `_part_decomp.py` (hours) if it is not ~0.
# =============================================================================
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
cd "$B" || exit 2
. "$B/_cage.sh"
TAG="${1:?usage: _p15_rebuild.sh <TAG> [PREVTAG]}"
PREV="${2:-}"
STAMP="${STAMP:-20260912}"
low=$(echo "$TAG" | tr 'A-Z' 'a-z')
L="$B/_p15_rebuild_${TAG}.log"; : > "$L"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }

LIST="$B/_snapshot_pruned_${TAG}.txt"
CKPT="$B/_cov_${low}.ckpt.jsonl"
COV="$B/_cov_FINAL_${TAG}_${STAMP}.json"
for f in "$LIST" "$CKPT" "$COV"; do
  [ -s "$f" ] || { say "MISSING $f"; say "P15-REBUILD-FAILED"; exit 3; }
done

if [ -n "$PREV" ]; then
  say "archiving the driven round's artefacts as *_${PREV}* (the constructor"
  say "  overwrites _p15_manifest.json, and the per-key explanation needs it)"
  for v in auth_html anon_html auth_json anon_json; do
    cp -f "$B/_p15_seeds_${v}.json"  "$B/_p15_seeds_${PREV}_${v}.json"  2>/dev/null
    cp -f "$B/_p15_seedsB_${v}.json" "$B/_p15_seedsB_${PREV}_${v}.json" 2>/dev/null
  done
  cp -f "$B/_p15_manifest.json" "$B/_p15_manifest_${PREV}.json" 2>/dev/null
  cp -f "$B/_p15_gaps.json"     "$B/_p15_gaps_${PREV}.json"     2>/dev/null
fi

# The BASE POOL is wider than the pass's DUMP_LIST: a dump the prune dropped
# as a duplicate PROFILE is still a perfectly good base (base choice reads its
# seed dict and its alias canonicals, not its profile), and dumps driven after
# the list was built (the P15BS subset) are not in it at all. INDEX_LIST may
# name a wider list; it defaults to the pass's own.
ILIST="${INDEX_LIST:-$LIST}"
say "R1 index (cap 4G) — corpus index + observed domain over $(wc -l < "$ILIST") dumps"
cage "p15idx${TAG}.scope" 4G \
  env DUMP_LIST="$ILIST" P15_INDEX="$B/_p15_index.pkl" \
      PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      python3 -u "$B/_p15_index.py" > "$B/_p15_index_${TAG}.log" 2>&1
say "R1 exit=$?"
caged_verdict "p15idx${TAG}.scope" "$B/_p15_index_${TAG}.log" '^P15-INDEX-DONE' | tee -a "$L"
grep -qE '^P15-INDEX-DONE' "$B/_p15_index_${TAG}.log" || { say "P15-REBUILD-FAILED index"; exit 4; }
tail -3 "$B/_p15_index_${TAG}.log" | tee -a "$L"

say "R2 classify (cap 4G) — witnesses from the CHECKPOINT, not the capped summary"
cage "p15cls${TAG}.scope" 4G \
  env P15_CKPT="$CKPT" P15_COV="$COV" P15_INDEX="$B/_p15_index.pkl" \
      P15_GAPS="$B/_p15_gaps.json" PARTS_IN="${PARTS_IN:-$B/_parts_OD0911.json}" \
      P15_PARTS_OUT="$B/_p15_parts_eff_${TAG}.json" \
      PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      python3 -u "$B/_p15_classify.py" > "$B/_p15_classify_${TAG}.log" 2>&1
say "R2 exit=$?"
grep -E 'TOTAL|unmatched|gaps whose|in-domain|witness' "$B/_p15_classify_${TAG}.log" | tail -20 | tee -a "$L"
[ -s "$B/_p15_gaps.json" ] || { say "P15-REBUILD-FAILED classify"; exit 5; }

# The constructor reads the EFFECTIVE parts (original + the parts classify had
# to synthesise), never the stale file, so `members_walked` is a real score for
# every gap instead of 0 for the ones the old decomposition does not contain.
EFF="$B/_p15_parts_eff_${TAG}.json"; [ -s "$EFF" ] || EFF="${PARTS_IN:-$B/_parts_OD0911.json}"
say "R3 construct (cap 4G) — BASES_PER_GAP=${BASES_PER_GAP:-2}  parts=$(basename "$EFF")"
cage "p15con${TAG}.scope" 4G \
  env P15_GAPS="$B/_p15_gaps.json" P15_INDEX="$B/_p15_index.pkl" \
      PARTS_IN="$EFF" \
      BASES_PER_GAP="${BASES_PER_GAP:-2}" \
      PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      python3 -u "$B/_p15_construct.py" > "$B/_p15_construct_${TAG}.log" 2>&1
say "R3 exit=$?"
tail -20 "$B/_p15_construct_${TAG}.log" | tee -a "$L"
say "P15-REBUILD-DONE $TAG"
