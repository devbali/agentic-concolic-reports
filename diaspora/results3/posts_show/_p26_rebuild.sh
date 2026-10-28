#!/bin/bash
# =============================================================================
# P26 step A2 — BUILD the batch from the OR-refined emission.
#   gaps(bootstrap, old index -> parts) -> index(fresh, P24 corpus, those parts)
#   -> gaps(final, fresh index) -> construct
# The bootstrap gaps pass exists only because `_p23_gaps.py` needs an index for
# its domain/seedable classification while `_p23_index.py` needs a parts file
# for its necessity table; the parts are a pure function of the emission, so
# the bootstrap's parts and the final ones are identical.
#   usage: bash _p26_rebuild.sh <TAG> <emit.jsonl> <snapshot>
# =============================================================================
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
cd "$B" || exit 2
. "$B/_cage.sh"
TAG="${1:?usage: _p26_rebuild.sh <TAG> <jsonl> <snapshot>}"
JSONL="${2:-$B/_p26_emit_${TAG}.json.jsonl}"
LIST="${3:-$B/_snapshot_pruned_P24.txt}"
OLDIDX="${OLD_INDEX:-$B/_p23_index_R2.pkl}"
NEWIDX="$B/_p26_index_${TAG}.pkl"
L="$B/_p26_rebuild_${TAG}.log"; : > "$L"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }

[ -s "$JSONL" ] || { say "MISSING $JSONL"; say "P26-REBUILD-FAILED"; exit 3; }
say "=== P26 REBUILD $TAG  $(wc -l < "$JSONL") streamed OR-refined cubes ==="

say "S1 gaps BOOTSTRAP (parts only, old index $(basename "$OLDIDX"))"
cage "p26gapb${TAG}.scope" 4G \
  env P23_JSONL="$JSONL" P18_INDEX="$OLDIDX" \
      P15_GAPS="$B/_p26_gaps_boot_${TAG}.json" P23_PARTS="$B/_p26_parts_${TAG}.json" \
      P23_MAX_PER_SET=0 P23_MAX_TOTAL=0 \
      PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      python3 -u "$B/_p23_gaps.py" > "$B/_p26_gaps_boot_${TAG}.log" 2>&1
caged_verdict "p26gapb${TAG}.scope" "$B/_p26_gaps_boot_${TAG}.log" '^P23-GAPS-DONE' | tee -a "$L"
grep -qE '^P23-GAPS-DONE' "$B/_p26_gaps_boot_${TAG}.log" || { say "P26-REBUILD-FAILED bootstrap"; exit 4; }
rm -f "$B/_p26_gaps_boot_${TAG}.json"

say "S2 index FRESH over $(basename "$LIST") ($(wc -l < "$LIST") profiles) -> $(basename "$NEWIDX")"
cage "p26idx${TAG}.scope" 6G \
  env DUMP_LIST="$LIST" PARTS_IN="$B/_p26_parts_${TAG}.json" P18_INDEX="$NEWIDX" \
      P18_MIN_RUNS="${P18_MIN_RUNS:-200}" \
      PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      python3 -u "$B/_p23_index.py" > "$B/_p26_index_${TAG}.log" 2>&1
caged_verdict "p26idx${TAG}.scope" "$B/_p26_index_${TAG}.log" '^P23-INDEX-DONE' | tee -a "$L"
grep -qE '^P23-INDEX-DONE' "$B/_p26_index_${TAG}.log" || { say "P26-REBUILD-FAILED index"; exit 5; }
grep -E '^(expr universe|dumps|indexed|NECESSITY|MINTING|   must-be)' "$B/_p26_index_${TAG}.log" | tee -a "$L"

say "S3 gaps FINAL (fresh index)"
cage "p26gap${TAG}.scope" 4G \
  env P23_JSONL="$JSONL" P18_INDEX="$NEWIDX" \
      P15_GAPS="$B/_p26_gaps_${TAG}.json" P23_PARTS="$B/_p26_parts_${TAG}.json" \
      P23_MAX_PER_SET=0 P23_MAX_TOTAL=0 \
      PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      python3 -u "$B/_p23_gaps.py" > "$B/_p26_gaps_${TAG}.log" 2>&1
caged_verdict "p26gap${TAG}.scope" "$B/_p26_gaps_${TAG}.log" '^P23-GAPS-DONE' | tee -a "$L"
grep -qE '^P23-GAPS-DONE' "$B/_p26_gaps_${TAG}.log" || { say "P26-REBUILD-FAILED gaps"; exit 6; }
sed -n '/read .* streamed cubes/,$p' "$B/_p26_gaps_${TAG}.log" | head -45 | tee -a "$L"

say "S4 construct (cap 5G) GROUP=set HARD_SPLIT=1 BASES_PER_GAP=1"
cage "p26con${TAG}.scope" 5G \
  env P15_GAPS="$B/_p26_gaps_${TAG}.json" P18_INDEX="$NEWIDX" \
      PARTS_IN="$B/_p26_parts_${TAG}.json" \
      BASES_PER_GAP="${BASES_PER_GAP:-1}" \
      P23_GROUP="${P23_GROUP:-set}" P23_HARD_SPLIT="${P23_HARD_SPLIT:-1}" \
      P15_PREFIX="_p15_seeds${TAG}_" P15_PREFIXB="_p15_seeds${TAG}B_" \
      P23_LABEL_A="${TAG}" P23_LABEL_B="${TAG}B" \
      P15_MANIFEST="_p15_manifest_${TAG}.json" \
      PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      python3 -u "$B/_p23_construct.py" > "$B/_p26_construct_${TAG}.log" 2>&1
caged_verdict "p26con${TAG}.scope" "$B/_p26_construct_${TAG}.log" '^P23-CONSTRUCT-DONE' | tee -a "$L"
tail -50 "$B/_p26_construct_${TAG}.log" | tee -a "$L"
grep -qE '^P23-CONSTRUCT-DONE' "$B/_p26_construct_${TAG}.log" || { say "P26-REBUILD-FAILED construct"; exit 7; }
say "P26-REBUILD-DONE $TAG"
