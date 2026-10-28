#!/bin/bash
# P44 — re-census after round $1 lands, so the yield CURVE is visible rather
# than a single endpoint. Builds a fresh pruned snapshot over everything driven
# so far, then the §16b prod census. Verdict: the `MODE prod:` line.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
cd "$B" || exit 2
R="${1:?round}"; TAG="${2:?census tag}"
L="$B/_p44_census_chain_$TAG.log"; : > "$L"
say(){ echo "[$(date -Is)] $*" >> "$L"; }
say "waiting for _p44_done_$R"
w=0
while [ ! -f "$B/_p44_done_$R" ]; do
  sleep 60; w=$((w+60))
  [ "$w" -gt 21600 ] && { say "ABORT: round $R did not land in 6 h"; exit 9; }
done
say "round $R landed; building the snapshot"
find "$B" -maxdepth 1 -name 'dump_*.json' | sed 's#^\./#'"$B"'/#' | sort -u > "$B/_snapshot_p44_$TAG.txt"
say "corpus $(wc -l < "$B/_snapshot_p44_$TAG.txt") dumps -> prune"
. "$B/_cage.sh"
cage "p44prune$TAG.scope" 4G \
  env DUMP_LIST="$B/_snapshot_p44_$TAG.txt" PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      python3 -u "$B/_prune_corpus.py" --out "$B/_snapshot_pruned_$TAG.txt" >> "$L" 2>&1
grep -q . "$B/_snapshot_pruned_$TAG.txt" || { say "P44-CENSUS-CHAIN-FAILED prune"; exit 4; }
say "pruned -> $(wc -l < "$B/_snapshot_pruned_$TAG.txt") profiles; census"
CENSUS_MODES=prod EMIT_CAP_MEM=20G P31_SKIP_ONEPASS=1 \
  WITHDRAWN_PAIRS="$B/_confinement_withdrawn.json" \
  bash "$B/_p35_emit.sh" "$TAG" "$B/_snapshot_pruned_$TAG.txt" >> "$L" 2>&1
say "P44-CENSUS-CHAIN-DONE $TAG $(grep 'MODE prod' "$B/_p31_emit_$TAG.out" 2>/dev/null | tail -1)"
