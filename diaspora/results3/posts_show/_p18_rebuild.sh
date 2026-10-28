#!/bin/bash
# =============================================================================
# P18 — REBUILD THE CONSTRUCTION INPUTS (index -> classify -> construct).
# Same shape as `_p15_rebuild.sh`; the index and the constructor are the P18
# ones (`_p18_index.py` adds the length-state masks, the api binding, and the
# necessity table; `_p18_construct.py` adds the governor pins).
#   usage: bash _p18_rebuild.sh <TAG> [PREVTAG]
# =============================================================================
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
cd "$B" || exit 2
. "$B/_cage.sh"
TAG="${1:?usage: _p18_rebuild.sh <TAG> [PREVTAG]}"
PREV="${2:-}"
STAMP="${STAMP:-20260912}"
low=$(echo "$TAG" | tr 'A-Z' 'a-z')
L="$B/_p18_rebuild_${TAG}.log"; : > "$L"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }

LIST="$B/_snapshot_pruned_${TAG}.txt"
CKPT="$B/_cov_${low}.ckpt.jsonl"
COV="$B/_cov_FINAL_${TAG}_${STAMP}.json"
for f in "$LIST" "$CKPT" "$COV"; do
  [ -s "$f" ] || { say "MISSING $f"; say "P18-REBUILD-FAILED"; exit 3; }
done

if [ -n "$PREV" ]; then
  say "archiving the driven round's artefacts as *_${PREV}*"
  for v in auth_html anon_html auth_json anon_json; do
    cp -f "$B/_p15_seeds_${v}.json"  "$B/_p15_seeds_${PREV}_${v}.json"  2>/dev/null
    cp -f "$B/_p15_seedsB_${v}.json" "$B/_p15_seedsB_${PREV}_${v}.json" 2>/dev/null
  done
  cp -f "$B/_p15_manifest.json" "$B/_p15_manifest_${PREV}.json" 2>/dev/null
  cp -f "$B/_p15_gaps.json"     "$B/_p15_gaps_${PREV}.json"     2>/dev/null
fi

ILIST="${INDEX_LIST:-$LIST}"
if [ "${SKIP_INDEX:-0}" = 1 ] && [ -s "$B/_p18_index.pkl" ]; then
  say "R1 index SKIPPED (SKIP_INDEX=1, reusing $(ls -la "$B/_p18_index.pkl" | awk '{print $6,$7,$8}'))"
else
  say "R1 index (cap 5G) over $(wc -l < "$ILIST") dumps"
  cage "p18idx${TAG}.scope" 5G \
    env DUMP_LIST="$ILIST" P18_INDEX="$B/_p18_index.pkl" \
        PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
        python3 -u "$B/_p18_index.py" > "$B/_p18_index_${TAG}.log" 2>&1
  say "R1 exit=$?"
  caged_verdict "p18idx${TAG}.scope" "$B/_p18_index_${TAG}.log" '^P18-INDEX-DONE' | tee -a "$L"
  grep -qE '^P18-INDEX-DONE' "$B/_p18_index_${TAG}.log" || { say "P18-REBUILD-FAILED index"; exit 4; }
  tail -3 "$B/_p18_index_${TAG}.log" | tee -a "$L"
fi

say "R2 classify (cap 4G) — witnesses from the CHECKPOINT"
cage "p18cls${TAG}.scope" 4G \
  env P15_CKPT="$CKPT" P15_COV="$COV" P15_INDEX="$B/_p18_index.pkl" \
      P15_GAPS="$B/_p15_gaps.json" PARTS_IN="${PARTS_IN:-$B/_p15_parts_eff_P16.json}" \
      P15_PARTS_OUT="$B/_p18_parts_eff_${TAG}.json" \
      PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      python3 -u "$B/_p15_classify.py" > "$B/_p18_classify_${TAG}.log" 2>&1
say "R2 exit=$?"
grep -E 'witnesses after|unmatched|SYNTHESISED|P15-CLASSIFY-DONE' "$B/_p18_classify_${TAG}.log" | tail -5 | tee -a "$L"
grep -qE '^P15-CLASSIFY-DONE' "$B/_p18_classify_${TAG}.log" || { say "P18-REBUILD-FAILED classify"; exit 5; }

EFF="$B/_p18_parts_eff_${TAG}.json"; [ -s "$EFF" ] || EFF="${PARTS_IN:-$B/_p15_parts_eff_P16.json}"
say "R3 construct (cap 4G) — BASES_PER_GAP=${BASES_PER_GAP:-2}  parts=$(basename "$EFF")"
cage "p18con${TAG}.scope" 4G \
  env P15_GAPS="$B/_p15_gaps.json" P18_INDEX="$B/_p18_index.pkl" \
      PARTS_IN="$EFF" BASES_PER_GAP="${BASES_PER_GAP:-2}" \
      PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      python3 -u "$B/_p18_construct.py" > "$B/_p18_construct_${TAG}.log" 2>&1
say "R3 exit=$?"
caged_verdict "p18con${TAG}.scope" "$B/_p18_construct_${TAG}.log" '^P18-CONSTRUCT-DONE' | tee -a "$L"
tail -35 "$B/_p18_construct_${TAG}.log" | tee -a "$L"
say "P18-REBUILD-DONE $TAG"
