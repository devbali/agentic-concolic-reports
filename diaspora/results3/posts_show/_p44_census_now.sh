#!/bin/bash
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
cd "$B" || exit 2
TAG="P44FRESH1"
L="$B/_p44_census_chain_${TAG}.log"; : > "$L"
say(){ echo "[$(date -Is)] $*" >> "$L"; }
find "$B" -maxdepth 1 -name 'dump_*.json' | sort -u > "$B/_snapshot_p44_${TAG}.txt"
say "corpus $(wc -l < "$B/_snapshot_p44_${TAG}.txt") dumps -> prune"
. "$B/_cage.sh"
cage "p44prune${TAG}.scope" 8G \
  env DUMP_LIST="$B/_snapshot_p44_${TAG}.txt" PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      python3 -u "$B/_prune_corpus.py" --out "$B/_snapshot_pruned_${TAG}.txt" >> "$L" 2>&1
grep -q . "$B/_snapshot_pruned_${TAG}.txt" || { say "FAILED prune"; exit 4; }
say "pruned -> $(wc -l < "$B/_snapshot_pruned_${TAG}.txt") profiles; census"
CENSUS_MODES=prod EMIT_CAP_MEM=24G P31_SKIP_ONEPASS=1 \
  WITHDRAWN_PAIRS="$B/_confinement_withdrawn.json" \
  bash "$B/_p35_emit.sh" "$TAG" "$B/_snapshot_pruned_${TAG}.txt" >> "$L" 2>&1
say "DONE $TAG $(grep 'MODE prod' "$B/_p31_emit_${TAG}.out" 2>/dev/null | tail -1)"
