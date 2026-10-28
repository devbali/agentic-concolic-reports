#!/bin/bash
# =============================================================================
# P31 REBUILD — copy of `_p30_rebuild.sh` (which is NOT edited) with ONE
# change: step S4 runs `_p31_construct.py` instead of `_p23_construct.py`, so
# the base choice is a HARD FILTER on the cube's upstream emptiness pins
# (§89.10's localisation; see the P31 constructor's docstring).
#
#   gaps(bootstrap, old index -> parts) -> index(FRESH, over the post-round-8
#   corpus, so round 8's own 569 dumps are available as bases) -> gaps(final)
#   -> construct(P31)
#
#   usage: bash _p31_rebuild.sh <TAG> <emit.jsonl> <snapshot>
# Verdict: P31-REBUILD-DONE <TAG> / P31-REBUILD-FAILED <stage>
# =============================================================================
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
cd "$B" || exit 2
. "$B/_cage.sh"
TAG="${1:?usage: _p31_rebuild.sh <TAG> <jsonl> <snapshot>}"
JSONL="${2:?usage: _p31_rebuild.sh <TAG> <jsonl> <snapshot>}"
LIST="${3:?usage: _p31_rebuild.sh <TAG> <jsonl> <snapshot>}"
OLDIDX="${OLD_INDEX:-$B/_p30_index_P30B.pkl}"
NEWIDX="$B/_p31_index_${TAG}.pkl"
L="$B/_p31_rebuild_${TAG}.log"; : > "$L"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }

[ -s "$JSONL" ] || { say "MISSING $JSONL"; say "P31-REBUILD-FAILED input"; exit 3; }
[ -s "$LIST" ]  || { say "MISSING $LIST";  say "P31-REBUILD-FAILED input"; exit 3; }
say "=== P31 REBUILD $TAG  $(wc -l < "$JSONL") streamed OR-refined cubes ==="

say "S1 gaps BOOTSTRAP (parts only, old index $(basename "$OLDIDX"))"
cage "p31gapb${TAG}.scope" 4G \
  env P23_JSONL="$JSONL" P18_INDEX="$OLDIDX" \
      P15_GAPS="$B/_p31_gaps_boot_${TAG}.json" P23_PARTS="$B/_p31_parts_${TAG}.json" \
      P23_MAX_PER_SET="${P23_MAX_PER_SET:-3}" P23_MAX_TOTAL="${P23_MAX_TOTAL:-0}" \
      PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      python3 -u "$B/_p23_gaps.py" > "$B/_p31_gaps_boot_${TAG}.log" 2>&1
caged_verdict "p31gapb${TAG}.scope" "$B/_p31_gaps_boot_${TAG}.log" '^P23-GAPS-DONE' | tee -a "$L"
grep -qE '^P23-GAPS-DONE' "$B/_p31_gaps_boot_${TAG}.log" || { say "P31-REBUILD-FAILED bootstrap"; exit 4; }
rm -f "$B/_p31_gaps_boot_${TAG}.json"

say "S2 index FRESH over $(basename "$LIST") ($(wc -l < "$LIST") profiles) -> $(basename "$NEWIDX")"
cage "p31idx${TAG}.scope" 6G \
  env DUMP_LIST="$LIST" PARTS_IN="$B/_p31_parts_${TAG}.json" P18_INDEX="$NEWIDX" \
      P18_MIN_RUNS="${P18_MIN_RUNS:-200}" \
      PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      python3 -u "$B/_p23_index.py" > "$B/_p31_index_${TAG}.log" 2>&1
caged_verdict "p31idx${TAG}.scope" "$B/_p31_index_${TAG}.log" '^P23-INDEX-DONE' | tee -a "$L"
grep -qE '^P23-INDEX-DONE' "$B/_p31_index_${TAG}.log" || { say "P31-REBUILD-FAILED index"; exit 5; }
grep -E '^(expr universe|dumps|indexed|NECESSITY|MINTING|   must-be)' "$B/_p31_index_${TAG}.log" | tee -a "$L"

say "S3 gaps FINAL (fresh index)"
cage "p31gap${TAG}.scope" 4G \
  env P23_JSONL="$JSONL" P18_INDEX="$NEWIDX" \
      P15_GAPS="$B/_p31_gaps_${TAG}.json" P23_PARTS="$B/_p31_parts_${TAG}.json" \
      P23_MAX_PER_SET="${P23_MAX_PER_SET:-3}" P23_MAX_TOTAL="${P23_MAX_TOTAL:-0}" \
      PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      python3 -u "$B/_p23_gaps.py" > "$B/_p31_gaps_${TAG}.log" 2>&1
caged_verdict "p31gap${TAG}.scope" "$B/_p31_gaps_${TAG}.log" '^P23-GAPS-DONE' | tee -a "$L"
grep -qE '^P23-GAPS-DONE' "$B/_p31_gaps_${TAG}.log" || { say "P31-REBUILD-FAILED gaps"; exit 6; }
sed -n '/read .* streamed cubes/,$p' "$B/_p31_gaps_${TAG}.log" | head -45 | tee -a "$L"

say "S4 construct P31 (cap 5G) HARD pin filter + gate filter + own-dump rank-0"
cage "p31con${TAG}.scope" 5G \
  env P15_GAPS="$B/_p31_gaps_${TAG}.json" P18_INDEX="$NEWIDX" \
      PARTS_IN="$B/_p31_parts_${TAG}.json" \
      BASES_PER_GAP="${BASES_PER_GAP:-1}" \
      P23_GROUP="${P23_GROUP:-set}" P23_HARD_SPLIT="${P23_HARD_SPLIT:-1}" \
      P31_PIN_HARD="${P31_PIN_HARD:-1}" P31_GATE_HARD="${P31_GATE_HARD:-1}" \
      P31_OWN_FIRST="${P31_OWN_FIRST:-1}" P31_GROUP_GATES="${P31_GROUP_GATES:-1}" \
      P31_OWN_GAPS="${P31_OWN_GAPS:-$B/_p30_gaps_P30B.json}" \
      P31_OWN_EXPLAIN="${P31_OWN_EXPLAIN:-$B/_p30_explain_P30B.json}" \
      P31_PINREPORT="$B/_p31_pins_${TAG}.json" \
      P15_PREFIX="_p15_seeds${TAG}_" P15_PREFIXB="_p15_seeds${TAG}B_" \
      P23_LABEL_A="${TAG}" P23_LABEL_B="${TAG}B" \
      P15_MANIFEST="_p15_manifest_${TAG}.json" \
      PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      python3 -u "$B/_p31_construct.py" > "$B/_p31_construct_${TAG}.log" 2>&1
caged_verdict "p31con${TAG}.scope" "$B/_p31_construct_${TAG}.log" '^P31-CONSTRUCT-DONE' | tee -a "$L"
tail -60 "$B/_p31_construct_${TAG}.log" | tee -a "$L"
grep -qE '^P31-CONSTRUCT-DONE' "$B/_p31_construct_${TAG}.log" || { say "P31-REBUILD-FAILED construct"; exit 7; }
say "P31-REBUILD-DONE $TAG"
