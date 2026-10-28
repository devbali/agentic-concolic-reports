#!/bin/bash
# =============================================================================
# P23 — BUILD THE BATCH from the exact enumerator's streamed remaining cubes.
#   gaps-bridge (_p23_gaps.py) -> construct (_p23_construct.py)
# The index (_p23_index.py) and the enumeration (_p23_enum.py) are run
# SEPARATELY and once per round; this script is the cheap half.
#   usage: bash _p23_rebuild.sh <TAG>
#   env:   P23_MAX_PER_SET (0=every emitted cube)  BASES_PER_GAP (1)
#          P23_GROUP (set|gates)  P23_HARD_SPLIT (1)
# =============================================================================
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
cd "$B" || exit 2
. "$B/_cage.sh"
TAG="${1:?usage: _p23_rebuild.sh <TAG>}"
L="$B/_p23_rebuild_${TAG}.log"; : > "$L"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }

JSONL="${P23_JSONL:-$B/_p23_emit_${TAG}.json.jsonl}"
[ -s "$JSONL" ] || { say "MISSING $JSONL"; say "P23-REBUILD-FAILED"; exit 3; }
[ -s "${P23_INDEX:-$B/_p23_index.pkl}" ] || { say "MISSING _p23_index.pkl"; say "P23-REBUILD-FAILED"; exit 3; }

say "R1 gaps-bridge (cap 4G) over $(wc -l < "$JSONL") streamed cubes"
cage "p23gap${TAG}.scope" 4G \
  env P23_JSONL="$JSONL" P18_INDEX="${P23_INDEX:-$B/_p23_index.pkl}" \
      P15_GAPS="$B/_p23_gaps_${TAG}.json" P23_PARTS="$B/_p23_parts_${TAG}.json" \
      P23_MAX_PER_SET="${P23_MAX_PER_SET:-0}" P23_MAX_TOTAL="${P23_MAX_TOTAL:-0}" \
      PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      python3 -u "$B/_p23_gaps.py" > "$B/_p23_gaps_${TAG}.log" 2>&1
say "R1 exit=$?"
caged_verdict "p23gap${TAG}.scope" "$B/_p23_gaps_${TAG}.log" '^P23-GAPS-DONE' | tee -a "$L"
grep -qE '^P23-GAPS-DONE' "$B/_p23_gaps_${TAG}.log" || { say "P23-REBUILD-FAILED gaps"; exit 4; }
sed -n '/read .* streamed cubes/,$p' "$B/_p23_gaps_${TAG}.log" | head -40 | tee -a "$L"

say "R2 construct (cap 5G) BASES_PER_GAP=${BASES_PER_GAP:-1} GROUP=${P23_GROUP:-set}"
cage "p23con${TAG}.scope" 5G \
  env P15_GAPS="$B/_p23_gaps_${TAG}.json" P18_INDEX="${P23_INDEX:-$B/_p23_index.pkl}" \
      PARTS_IN="$B/_p23_parts_${TAG}.json" \
      BASES_PER_GAP="${BASES_PER_GAP:-1}" \
      P23_GROUP="${P23_GROUP:-set}" P23_HARD_SPLIT="${P23_HARD_SPLIT:-1}" \
      P15_PREFIX="_p15_seeds${TAG}_" P15_PREFIXB="_p15_seeds${TAG}B_" \
      P23_LABEL_A="${TAG}" P23_LABEL_B="${TAG}B" \
      P15_MANIFEST="_p15_manifest_${TAG}.json" \
      PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      python3 -u "$B/_p23_construct.py" > "$B/_p23_construct_${TAG}.log" 2>&1
say "R2 exit=$?"
caged_verdict "p23con${TAG}.scope" "$B/_p23_construct_${TAG}.log" '^P23-CONSTRUCT-DONE' | tee -a "$L"
tail -45 "$B/_p23_construct_${TAG}.log" | tee -a "$L"
say "P23-REBUILD-DONE $TAG"
