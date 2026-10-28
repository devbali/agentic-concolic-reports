#!/bin/bash
# P26 step A1 — emit EVERY remaining cube under the §16c OR-refined projection.
#   usage: bash _p26_emit.sh <TAG> <SNAPSHOT>
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
cd "$B" || exit 2
TAG="${1:?usage: _p26_emit.sh <TAG> <snapshot>}"
LIST="${2:-$B/_snapshot_pruned_P24.txt}"
L="$B/_p26_enum_${TAG}.log"
{
echo "[$(date -Is)] === P26 OR-REFINED EMISSION $TAG  list=$(basename "$LIST") ($(wc -l < "$LIST") profiles) ==="
echo "  engine coverage.py md5 $(md5sum /home/dev/project/src/concolic_engine/coverage.py | cut -d' ' -f1)"
} > "$L"
env DUMP_LIST="$LIST" \
    EMIT_OUT="$B/_p26_emit_${TAG}.json" \
    EMIT_MAX_PER_SET=0 EMIT_CAP=0 \
    MAX_CLIQUES=16384 CUBE_CAP=20000 OR_SHARING=1 \
    JSON_OUT="$B/_p26_enum_${TAG}.json" \
    PAIRS_OUT="$B/_p26_pairs_${TAG}.json" \
    ${WITHDRAWN_PAIRS:+WITHDRAWN_PAIRS="$WITHDRAWN_PAIRS"} \
    PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
    python3 -u "$B/_p26_emit_or.py" >> "$L" 2>&1
echo "[$(date -Is)] exit=$? " >> "$L"
grep -qE '^P26-EMIT-DONE' "$L" && echo "P26-EMIT-OK $TAG" >> "$L" || echo "P26-EMIT-NO-VERDICT $TAG -- TREAT AS KILLED" >> "$L"
