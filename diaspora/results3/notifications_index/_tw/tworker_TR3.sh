#!/bin/bash
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
F="$1"; TAG="$2"
bn=$(basename "$F" .json); TK=${bn#_treeR_}; TKN=${TK%%_*}; V=${TK#*_}
SFX="$( [ "${V##*_}" = typed ] && echo t || echo p )"
TOT=$(python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))))" "$F")
POS=0; TRY=0; LOST=0
while [ "$POS" -lt "$TOT" ] && [ "$TRY" -lt 60 ]; do
  REM="$B/_tw/rem_${TAG}_${TKN}_${V}.json"
  python3 -c "
import json,sys
json.dump(json.load(open(sys.argv[1]))[int(sys.argv[2]):],open(sys.argv[3],'w'))" "$F" "$POS" "$REM"
  OUT="$B/_tw/out_${TAG}_${TKN}_${V}_${TRY}.log"
  /home/dev/project/reports/diaspora/tools/slot env VARIANTS="$V" SEEDS_ONLY=1 \
    EXTRA_SEEDS_JSON="$REM" LABEL_SUFFIX="_${TAG}${TKN}${V:0:3}${SFX}r${TRY}" \
    MAX_RUNS=100000 TIME_BUDGET=1800 \
    /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" > "$OUT" 2>&1
  rc=$?; n=$(grep -c 'new path' "$OUT"); POS=$((POS+n))
  if [ "$rc" != "0" ]; then POS=$((POS+1)); LOST=$((LOST+1)); fi
  rm -f "$OUT"; TRY=$((TRY+1)); [ "$rc" = "0" ] && break
done
rm -f "$REM"
echo "[$(date -Is)] $TKN $V consumed=$POS/$TOT tries=$TRY aborted=$LOST" >> "$B/_tree_drive_${TAG}.log"
