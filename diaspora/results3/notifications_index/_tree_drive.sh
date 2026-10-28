#!/bin/bash
# Drive the per-variant ROOTED tree seeds (_treeR_<variant>.json), with the
# same abort-resume loop as _chunk_drive.sh: these seed lists are small and a
# single toxic seed must not cost the rest of the list.
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
TAG="${1:?tag}"
LOG="$B/_tree_drive_${TAG}.log"
export CONCOLIC_SLOTS="${CONCOLIC_SLOTS:-3}"
say(){ echo "[$(date -Is)] $*" >> "$LOG"; }
say "=== TREE DRIVE $TAG ==="
before=$(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l); say "corpus before: $before"
for V in html_plain html_typed json_plain json_typed mobile_plain mobile_typed xml_plain; do
  F="$B/_treeR_${V}.json"; [ -s "$F" ] || continue
  ( SFX="$( [ "${V##*_}" = typed ] && echo t || echo p )"
    TOT=$(python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))))" "$F")
    POS=0; TRY=0
    while [ "$POS" -lt "$TOT" ] && [ "$TRY" -lt 40 ]; do
      REM="$B/_tw/treerem_${TAG}_${V}.json"
      python3 -c "
import json,sys
json.dump(json.load(open(sys.argv[1]))[int(sys.argv[2]):],open(sys.argv[3],'w'))" "$F" "$POS" "$REM"
      OUT="$B/_tw/tree_${TAG}_${V}_${TRY}.log"
      /home/dev/project/reports/diaspora/tools/slot env VARIANTS="$V" SEEDS_ONLY=1 \
        EXTRA_SEEDS_JSON="$REM" LABEL_SUFFIX="_${TAG}${V:0:3}${SFX}r${TRY}" \
        MAX_RUNS=100000 TIME_BUDGET=1800 \
        /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" > "$OUT" 2>&1
      rc=$?; n=$(grep -c 'new path' "$OUT"); POS=$((POS+n))
      [ "$rc" != "0" ] && { echo "[$(date -Is)] $V try$TRY rc=$rc paths=$n toxic#$POS" >> "$LOG"; POS=$((POS+1)); }
      TRY=$((TRY+1)); [ "$rc" = "0" ] && break
    done
    rm -f "$REM"
    echo "[$(date -Is)] $V DONE consumed=$POS/$TOT tries=$TRY" >> "$LOG" ) &
  sleep 1
done
wait
after=$(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l)
say "corpus after: $after (+$((after-before)))"
say "=== TREE DRIVE $TAG END ==="
