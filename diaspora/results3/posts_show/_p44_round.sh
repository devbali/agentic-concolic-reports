#!/bin/bash
# P44 ROUND — sample N real residue cubes -> gaps -> construct. One unit, one
# verdict line. Resumable: each stage is skipped if its artefact exists.
#   usage: bash _p44_round.sh <TAG> <N> [SEED]
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
cd "$B" || exit 2
TAG="${1:?tag}"; N="${2:?n}"; SEED="${3:-20260916}"
L="$B/_p44_round_${TAG}.log"; : > "$L"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }
say "=== P44 ROUND $TAG  N=$N seed=$SEED ==="
if [ ! -s "$B/_p44_sample_${TAG}.jsonl" ]; then
  P44_SEED="$SEED" python3 -u "$B/_p44_sample_jsonl.py" \
    "$B/_p31_emit_P35.jsonl" "$B/_p44_sample_${TAG}.jsonl" "$N" >> "$L" 2>&1 || {
    say "P44-ROUND-FAILED sample"; exit 3; }
fi
if [ ! -s "$B/_p44_gaps_${TAG}.json" ]; then
  env P23_JSONL="$B/_p44_sample_${TAG}.jsonl" P18_INDEX="$B/_p31_index_P35C.pkl" \
      P15_GAPS="$B/_p44_gaps_${TAG}.json" P23_PARTS="$B/_p44_parts_${TAG}.json" \
      P23_MAX_PER_SET=0 P23_MAX_TOTAL=0 PYTHONPATH=/home/dev/project/src \
      python3 -u "$B/_p23_gaps.py" >> "$L" 2>&1
  grep -q '^P23-GAPS-DONE' "$L" || { say "P44-ROUND-FAILED gaps"; exit 4; }
fi
P44_PARTS="$B/_p44_parts_${TAG}.json" bash "$B/_p44_construct.sh" "$TAG" \
  "$B/_p44_gaps_${TAG}.json" >> "$L" 2>&1
grep -q '^P31-CONSTRUCT-DONE' "$B/_p44_construct_${TAG}.log" || {
  say "P44-ROUND-FAILED construct"; exit 5; }
say "P44-ROUND-DONE $TAG  $(python3 -c "
import json;print(sum(len(json.load(open('$B/_p15_seeds${TAG}_%s.json'%v))) for v in ('auth_html','anon_html','auth_json','anon_json')))") seeds"
